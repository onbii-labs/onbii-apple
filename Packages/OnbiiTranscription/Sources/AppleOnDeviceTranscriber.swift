#if os(macOS) || os(iOS)
@preconcurrency import Speech
import AVFoundation
import CoreMedia
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
    case modelUnavailable(String)
    case audioUnreadable(String)
    case recognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Speech recognition permission was not granted."
        case .unsupportedLocale(let identifier):
            "On-device transcription is not supported for \(identifier)."
        case .modelUnavailable(let identifier):
            "The on-device language model for \(identifier) could not be installed."
        case .audioUnreadable(let message):
            "The recording could not be read: \(message)"
        case .recognitionFailed(let message):
            "Speech recognition failed: \(message)"
        }
    }
}

/// On-device transcription built on the `SpeechAnalyzer` / `SpeechTranscriber`
/// stack (macOS 26 / iOS 26+). Language models are installed on demand through
/// `AssetInventory`, so callers never depend on a pre-installed dictation model.
/// Fully on-device: audio never leaves the device.
public final class AppleOnDeviceTranscriber: @unchecked Sendable {
    public init() {}

    // MARK: Authorization

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

    // MARK: Language / model availability

    /// Locales the on-device transcriber can handle on this device.
    public static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    /// Locales whose on-device model is already downloaded.
    public static func installedLocales() async -> [Locale] {
        await SpeechTranscriber.installedLocales
    }

    public static func isModelInstalled(for locale: Locale) async -> Bool {
        let target = locale.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == target }
    }

    /// Ensures the on-device model for `locale` is installed, downloading it if
    /// necessary. `progress` receives the fractionCompleted (0...1) during a
    /// download. Throws if the locale is unsupported or the model cannot install.
    public static func prepareModel(
        for locale: Locale,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(
            equivalentTo: locale
        ) else {
            throw AppleOnDeviceTranscriberError.unsupportedLocale(locale.identifier)
        }
        let transcriber = Self.makeTranscriber(locale: supported)
        try await installModelIfNeeded(for: transcriber, locale: supported, progress: progress)
    }

    // MARK: Transcription

    public func transcribe(
        audioURL: URL,
        sourceResourceID: String,
        sourceRole: String,
        locale: Locale = .current
    ) async throws -> OnbiiTrackTranscript {
        guard Self.authorization == .authorized else {
            throw AppleOnDeviceTranscriberError.authorizationDenied
        }
        guard let supported = await SpeechTranscriber.supportedLocale(
            equivalentTo: locale
        ) else {
            throw AppleOnDeviceTranscriberError.unsupportedLocale(locale.identifier)
        }

        let transcriber = Self.makeTranscriber(locale: supported)
        try await Self.installModelIfNeeded(for: transcriber, locale: supported)

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: audioURL)
        } catch {
            throw AppleOnDeviceTranscriberError.audioUnreadable(
                error.localizedDescription
            )
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let collected = Self.collect(
            from: transcriber,
            sourceRole: sourceRole
        )
        do {
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            await analyzer.cancelAndFinishNow()
            _ = try? await collected
            throw AppleOnDeviceTranscriberError.recognitionFailed(
                error.localizedDescription
            )
        }

        let result = try await collected
        return OnbiiTrackTranscript(
            sourceResourceID: sourceResourceID,
            sourceRole: sourceRole,
            localeIdentifier: supported.identifier(.bcp47),
            formattedText: result.text,
            segments: result.segments
        )
    }

    // MARK: Internals

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
    }

    private static func installModelIfNeeded(
        for transcriber: SpeechTranscriber,
        locale: Locale,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        if status == .installed {
            return
        }
        guard status != .unsupported else {
            throw AppleOnDeviceTranscriberError.unsupportedLocale(
                locale.identifier(.bcp47)
            )
        }
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) else {
            // Nothing to install (already available) — proceed.
            return
        }
        let observation = progress.map { handler in
            request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                handler(progress.fractionCompleted)
            }
        }
        defer { observation?.invalidate() }
        try await request.downloadAndInstall()
    }

    private static func collect(
        from transcriber: SpeechTranscriber,
        sourceRole: String
    ) async throws -> (segments: [OnbiiTranscriptSegment], text: String) {
        var segments = [OnbiiTranscriptSegment]()
        var textParts = [String]()
        for try await result in transcriber.results {
            let attributed = result.text
            let plain = String(attributed.characters)
            if !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textParts.append(plain)
            }
            for run in attributed.runs {
                guard let timeRange = run.audioTimeRange else {
                    continue
                }
                let text = String(attributed[run.range].characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    continue
                }
                let confidence = run.transcriptionConfidence.map { Float($0) }
                segments.append(
                    OnbiiTranscriptSegment(
                        text: text,
                        startSeconds: timeRange.start.seconds,
                        durationSeconds: timeRange.duration.seconds,
                        confidence: confidence,
                        sourceRole: sourceRole
                    )
                )
            }
        }
        return (segments, textParts.joined(separator: " "))
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
}
#endif
