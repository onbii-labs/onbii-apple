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
    private var interruptionTask: Task<Void, Never>?
    private var stalledTransferTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private var pendingURL: URL?
    private var pendingMetadata: OnbiiWatchRecordingMetadata?
    /// Set when a recording ended without being asked to; shown until the next
    /// recording starts.
    private var pendingInterruption: String?
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

    /// What is true right now.
    ///
    /// An interruption is announced *in front of* whatever the app is doing
    /// next, and keeps being announced while the audio is saved and handed to
    /// the iPhone — the recording still ended early, and the transfer
    /// succeeding does not make that less true.
    var statusText: String {
        guard let pendingInterruption else {
            return baseStatusText
        }
        return "\(pendingInterruption) \(baseStatusText)"
    }

    private var baseStatusText: String {
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

    /// Re-checks a recording the app believes is running.
    ///
    /// Called every time the app becomes active. watchOS suspending this app is
    /// invisible from inside it — no callback runs while the process does not —
    /// so returning to the foreground is the first honest chance to notice. This
    /// is the check that was missing when twenty-five minutes of a walk went
    /// unrecorded behind a screen that said "Recording is visibly active".
    func verifyRecordingIsStillRunning() {
        guard state == .recording,
              let interruption = recorder.verifyStillRecording() else {
            return
        }
        handle(interruption)
    }

    func startRecording() {
        guard canUsePrimaryAction, !isRecording else {
            return
        }
        pendingInterruption = nil
        state = .preparing
        // Asked here rather than at launch: a permission prompt makes sense next
        // to the thing it is for. Never blocks the recording.
        Task { await WatchNotifier.requestAuthorizationIfNeeded() }

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
                observeInterruptions()
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
        finishRecording(interruption: nil)
    }

    /// Preserves and transfers whatever reached the file, whether the person
    /// asked for the stop or the system did. An interruption is not a reason to
    /// discard audio — it is a reason to say so.
    private func finishRecording(interruption: String?) {
        state = .stopping
        WKInterfaceDevice.current().play(.stop)
        durationTask?.cancel()
        durationTask = nil
        interruptionTask?.cancel()
        interruptionTask = nil
        pendingInterruption = interruption

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

    /// Listens for the recording dying while the app is running. The other half
    /// of the problem — the app not running at all — is
    /// ``verifyRecordingIsStillRunning()``.
    private func observeInterruptions() {
        interruptionTask?.cancel()
        interruptionTask = Task { [weak self] in
            guard let interruptions = self?.recorder.interruptions else { return }
            for await interruption in interruptions {
                guard let self, state == .recording else { return }
                handle(interruption)
                return
            }
        }
    }

    private func handle(_ interruption: OnbiiCaptureInterruption) {
        WKInterfaceDevice.current().play(.failure)
        // The haptic says something happened; this says what. On a walk with the
        // app in the background, that is the difference between turning around
        // and carrying on believing you are recording.
        Task { await WatchNotifier.captureStopped(interruption.message) }
        finishRecording(interruption: interruption.message)
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
        watchForStalledTransfer()
    }

    /// Says so when a transfer has not completed in a reasonable time.
    ///
    /// Watch Connectivity queues a file and delivers it when it can, which is
    /// usually fine and occasionally never. Until then the audio is safe on the
    /// Watch — but the person's mental model is that a recording they finished is
    /// already in their archive, and nothing corrects that. This is the transfer
    /// half of "the app must say when capture or transfer fails".
    ///
    /// Deliberately a plain wait rather than a guess at the cause. It reports
    /// that it has not arrived, which is the fact; why is Watch Connectivity's
    /// business.
    private func watchForStalledTransfer() {
        stalledTransferTask?.cancel()
        stalledTransferTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.transferPatienceSeconds))
            guard !Task.isCancelled, let self, state == .queued else { return }
            await WatchNotifier.transferOutstanding()
        }
    }

    /// Long enough that an ordinary transfer finishes first, short enough that
    /// someone still on the same walk hears about it.
    private static let transferPatienceSeconds = 180.0

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
            stalledTransferTask?.cancel()
            stalledTransferTask = nil
            if let error {
                state = .failed(
                    "Transfer failed: \(error.localizedDescription)"
                )
                Task {
                    await WatchNotifier.captureStopped(
                        "The recording could not be sent to your iPhone: "
                            + "\(error.localizedDescription) It is still on this "
                            + "Watch."
                    )
                }
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
