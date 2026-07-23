#if os(macOS) || os(iOS)
@preconcurrency import Speech
import Foundation

public enum OnbiiSpeechAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

public enum AppleOnDeviceTranscriberError: Error, LocalizedError {
    case authorizationDenied
    case unsupportedLocale(String)
    case recognizerUnavailable(String)
    case onDeviceRecognitionUnavailable(String)
    case recognitionFailed(String)
    case noSpeechDetected
    case noFinalResult

    public var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Speech recognition permission was not granted."
        case .unsupportedLocale(let identifier):
            "Speech recognition is unavailable for locale \(identifier)."
        case .recognizerUnavailable(let identifier):
            "Speech recognition is temporarily unavailable for \(identifier)."
        case .onDeviceRecognitionUnavailable(let identifier):
            "On-device speech recognition is unavailable for \(identifier)."
        case .recognitionFailed(let message):
            "Speech recognition failed: \(message)"
        case .noSpeechDetected:
            "No speech was detected."
        case .noFinalResult:
            "Speech recognition ended without a final transcript."
        }
    }
}

public final class AppleOnDeviceTranscriber: @unchecked Sendable {
    private final class RecognitionOperation: @unchecked Sendable {
        private let lock = NSLock()
        private var completed = false
        var task: SFSpeechRecognitionTask?

        func complete(
            _ result: Result<OnbiiTrackTranscript, any Error>,
            continuation: CheckedContinuation<OnbiiTrackTranscript, any Error>
        ) {
            lock.lock()
            guard !completed else {
                lock.unlock()
                return
            }
            completed = true
            task = nil
            lock.unlock()
            continuation.resume(with: result)
        }
    }

    public init() {}

    public static var authorization: OnbiiSpeechAuthorization {
        map(SFSpeechRecognizer.authorizationStatus())
    }

    public static func requestAuthorization() async -> OnbiiSpeechAuthorization {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: map(status))
            }
        }
    }

    public func transcribe(
        audioURL: URL,
        sourceResourceID: String,
        sourceRole: String,
        locale: Locale = .current
    ) async throws -> OnbiiTrackTranscript {
        guard Self.authorization == .authorized else {
            throw AppleOnDeviceTranscriberError.authorizationDenied
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AppleOnDeviceTranscriberError.unsupportedLocale(
                locale.identifier
            )
        }
        guard recognizer.isAvailable else {
            throw AppleOnDeviceTranscriberError.recognizerUnavailable(
                locale.identifier
            )
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw AppleOnDeviceTranscriberError.onDeviceRecognitionUnavailable(
                locale.identifier
            )
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<OnbiiTrackTranscript, any Error>) in
            let operation = RecognitionOperation()
            operation.task = recognizer.recognitionTask(with: request) {
                result,
                error in
                if let error {
                    if Self.isNoSpeechDetected(error) {
                        operation.complete(
                            .success(
                                OnbiiTrackTranscript(
                                    sourceResourceID: sourceResourceID,
                                    sourceRole: sourceRole,
                                    localeIdentifier: locale.identifier,
                                    formattedText: "",
                                    segments: []
                                )
                            ),
                            continuation: continuation
                        )
                        return
                    }
                    operation.complete(
                        .failure(
                            AppleOnDeviceTranscriberError.recognitionFailed(
                                error.localizedDescription
                            )
                        ),
                        continuation: continuation
                    )
                    return
                }
                guard let result, result.isFinal else {
                    return
                }

                let transcription = result.bestTranscription
                operation.complete(
                    .success(
                        OnbiiTrackTranscript(
                            sourceResourceID: sourceResourceID,
                            sourceRole: sourceRole,
                            localeIdentifier: locale.identifier,
                            formattedText: transcription.formattedString,
                            segments: transcription.segments.map {
                                OnbiiTranscriptSegment(
                                    text: $0.substring,
                                    startSeconds: $0.timestamp,
                                    durationSeconds: $0.duration,
                                    confidence: $0.confidence,
                                    sourceRole: sourceRole
                                )
                            }
                        )
                    ),
                    continuation: continuation
                )
            }
        }
    }

    private static func map(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> OnbiiSpeechAuthorization {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .authorized:
            .authorized
        @unknown default:
            .denied
        }
    }

    static func isNoSpeechDetected(_ error: any Error) -> Bool {
        let error = error as NSError
        return (
            error.domain == "kAFAssistantErrorDomain"
                && error.code == 1110
        ) || error.localizedDescription.localizedCaseInsensitiveCompare(
            "No speech detected"
        ) == .orderedSame
    }
}
#endif
