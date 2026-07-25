import Foundation
import Observation
import OnbiiCapture
import WatchKit
@preconcurrency import WatchConnectivity

@MainActor
@Observable
final class WatchViewModel: NSObject {
    enum State: Equatable {
        case connecting
        case idle
        case preparing
        case recording
        case stopping
        case queued
        case transferred
        case failed(String)
    }

    private let recorder = OnbiiMicrophoneRecorder()
    private let session: WCSession?
    private var durationTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private var pendingURL: URL?
    private var pendingMetadata: OnbiiWatchRecordingMetadata?
    private let locationProvider = OnbiiLocationProvider()
    private var pendingCaptureLocation: OnbiiCapturedLocation?

    /// Fetches the Watch's location asynchronously at record start (no geocode —
    /// the iPhone names it). Best-effort; never blocks recording.
    private func beginCaptureLocation() {
        pendingCaptureLocation = nil
        Task { [weak self] in
            guard let captured = await self?.locationProvider
                .currentLocation(reverseGeocode: false) else {
                return
            }
            self?.pendingCaptureLocation = captured
        }
    }

    private(set) var state: State = .connecting
    private(set) var duration: TimeInterval = 0

    override init() {
        if WCSession.isSupported() {
            let session = WCSession.default
            self.session = session
            super.init()
            session.delegate = self
            session.activate()
        } else {
            session = nil
            super.init()
            state = .failed("Watch Connectivity is unavailable.")
        }
    }

    var isRecording: Bool {
        state == .recording
    }

    var canUsePrimaryAction: Bool {
        if isRecording {
            return true
        }
        return state == .idle || state == .transferred
    }

    var canRetryTransfer: Bool {
        guard pendingURL != nil else {
            return false
        }
        if case .failed = state {
            return true
        }
        return false
    }

    var isTransferInProgress: Bool {
        state == .stopping || state == .queued
    }

    var primaryActionTitle: String {
        switch state {
        case .recording:
            "Stop"
        case .stopping:
            "Stopping…"
        case .queued:
            "Transferring…"
        default:
            "Record"
        }
    }

    var primaryActionSystemImage: String {
        switch state {
        case .recording:
            "stop.circle.fill"
        case .stopping, .queued:
            "arrow.up.circle"
        default:
            "record.circle"
        }
    }

    var durationText: String {
        let seconds = Int(duration.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var statusText: String {
        switch state {
        case .connecting:
            "Connecting to iPhone…"
        case .idle:
            "Ready to record."
        case .preparing:
            "Preparing microphone…"
        case .recording:
            "Recording is visibly active."
        case .stopping:
            "Recording stopped. Saving…"
        case .queued:
            "Saved on this Watch. Transferring to iPhone…"
        case .transferred:
            "Recording transferred to iPhone."
        case .failed(let message):
            message
        }
    }

    func startRecording() {
        guard state == .idle || state == .transferred else {
            return
        }
        state = .preparing

        Task {
            guard await recorder.requestPermission() else {
                state = .failed("Microphone permission is required.")
                return
            }

            do {
                let destinationURL = try makeRecordingURL()
                let startedAt = Date()
                let recorder = self.recorder
                // Run the audio-session activation and engine start off the main
                // actor so the UI stays responsive (showing "Preparing…") during
                // the mic spin-up instead of blocking on it.
                try await Task.detached(priority: .userInitiated) {
                    try recorder.startRecording(to: destinationURL)
                }.value
                recordingStartedAt = startedAt
                beginCaptureLocation()
                duration = 0
                state = .recording
                WKInterfaceDevice.current().play(.start)
                beginDurationUpdates()
            } catch {
                recordingStartedAt = nil
                state = .failed(error.localizedDescription)
            }
        }
    }

    func stopRecording() {
        guard state == .recording else {
            return
        }

        state = .stopping
        WKInterfaceDevice.current().play(.stop)
        durationTask?.cancel()
        durationTask = nil

        let finalDuration = recorder.duration
        guard let finalizedURL = recorder.stopRecording() else {
            state = .failed("The Watch recording could not be saved.")
            WKInterfaceDevice.current().play(.failure)
            return
        }

        let startedAt = recordingStartedAt ?? Date()
        recordingStartedAt = nil
        duration = finalDuration
        pendingURL = finalizedURL
        pendingMetadata = OnbiiWatchRecordingMetadata(
            captureStartedAt: startedAt,
            durationSeconds: finalDuration,
            latitude: pendingCaptureLocation?.latitude,
            longitude: pendingCaptureLocation?.longitude,
            horizontalAccuracyMeters: pendingCaptureLocation?.horizontalAccuracyMeters
        )
        WKInterfaceDevice.current().play(.success)
        queuePendingTransfer()
    }

    func retryTransfer() {
        queuePendingTransfer()
    }

    private func queuePendingTransfer() {
        guard let session,
              session.activationState == .activated,
              let pendingURL,
              let pendingMetadata
        else {
            state = .failed(
                "The iPhone connection is unavailable. The recording remains on this Watch."
            )
            return
        }

        session.transferFile(
            pendingURL,
            metadata: pendingMetadata.propertyList
        )
        state = .queued
    }

    private func makeRecordingURL() throws -> URL {
        let directory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Outgoing", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent(
            "watch-\(UUID().uuidString.lowercased()).m4a"
        )
    }

    private func beginDurationUpdates() {
        durationTask?.cancel()
        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else {
                    return
                }
                duration = recorder.duration
            }
        }
    }
}

extension WatchViewModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if let error {
                state = .failed(error.localizedDescription)
            } else if activationState == .activated {
                state = .idle
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: (any Error)?
    ) {
        let transferredURL = fileTransfer.file.fileURL
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if let error {
                state = .failed(
                    "Transfer failed: \(error.localizedDescription)"
                )
                return
            }
            try? FileManager.default.removeItem(at: transferredURL)
            if pendingURL == transferredURL {
                pendingURL = nil
                pendingMetadata = nil
            }
            state = .transferred
        }
    }
}
