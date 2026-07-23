#if os(macOS)
import Foundation

public struct OnbiiDualAudioCaptureResult: Sendable {
    public let systemAudio: OnbiiRecordedAudio
    public let microphoneAudio: OnbiiRecordedAudio

    public init(
        systemAudio: OnbiiRecordedAudio,
        microphoneAudio: OnbiiRecordedAudio
    ) {
        self.systemAudio = systemAudio
        self.microphoneAudio = microphoneAudio
    }
}

public enum OnbiiDualAudioCaptureError: Error, Equatable, Sendable {
    case unsupportedSystemVersion
    case alreadyRecording
    case incompleteCapture
}

extension OnbiiDualAudioCaptureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSystemVersion:
            "System audio capture requires macOS 14.2 or later."
        case .alreadyRecording:
            "A dual-source capture session is already active."
        case .incompleteCapture:
            "The capture session did not produce both source tracks."
        }
    }
}

@MainActor
public final class OnbiiDualAudioCaptureSession {
    private let systemAudioRecorder = OnbiiSystemAudioRecorder()
    private let microphoneRecorder = OnbiiMicrophoneRecorder()
    private var microphoneStartedAt: Date?

    public init() {}

    public var isRecording: Bool {
        systemAudioRecorder.isRecording || microphoneRecorder.isRecording
    }

    public var duration: TimeInterval {
        max(systemAudioRecorder.duration, microphoneRecorder.duration)
    }

    public func requestMicrophonePermission() async -> Bool {
        await microphoneRecorder.requestPermission()
    }

    public func start(
        systemAudioURL: URL,
        microphoneAudioURL: URL
    ) throws {
        guard #available(macOS 14.2, *) else {
            throw OnbiiDualAudioCaptureError.unsupportedSystemVersion
        }
        guard !isRecording else {
            throw OnbiiDualAudioCaptureError.alreadyRecording
        }

        try systemAudioRecorder.startRecording(to: systemAudioURL)

        do {
            try microphoneRecorder.startRecording(to: microphoneAudioURL)
            microphoneStartedAt = Date()
        } catch {
            _ = try? systemAudioRecorder.stopRecording()
            throw error
        }
    }

    public func stop() throws -> OnbiiDualAudioCaptureResult {
        let microphoneDuration = microphoneRecorder.duration
        let microphoneURL = microphoneRecorder.stopRecording()
        let microphoneResult = microphoneURL.map {
            OnbiiRecordedAudio(
                url: $0,
                startedAt: microphoneStartedAt ?? Date(),
                duration: microphoneDuration
            )
        }
        microphoneStartedAt = nil

        let systemAudioResult: OnbiiRecordedAudio
        do {
            guard let result = try systemAudioRecorder.stopRecording() else {
                throw OnbiiDualAudioCaptureError.incompleteCapture
            }
            systemAudioResult = result
        } catch {
            throw error
        }

        guard let microphoneResult else {
            throw OnbiiDualAudioCaptureError.incompleteCapture
        }

        return OnbiiDualAudioCaptureResult(
            systemAudio: systemAudioResult,
            microphoneAudio: microphoneResult
        )
    }
}
#endif
