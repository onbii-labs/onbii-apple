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

/// On-device transcription built on the `SpeechAnalyzer` stack (macOS 26 /
/// iOS 26+). Prefers `SpeechTranscriber` (the higher-quality long-form model)
/// for the languages it supports, and falls back to `DictationTranscriber` for
/// the others (e.g. Dutch), which tracks the broader system dictation language
/// set. Language models install on demand through `AssetInventory`. Fully
/// on-device: audio never leaves the device. See
/// `docs/spec/docs/decisions/0029-compact-audio-originals.md`.
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

    /// The union of locales supported by either on-device model.
    public static func supportedLocales() async -> [Locale] {
        let speech = await SpeechTranscriber.supportedLocales
        let dictation = await DictationTranscriber.supportedLocales
        return deduplicated(speech + dictation)
    }

    /// The union of locales whose model is already installed for either model.
    public static func installedLocales() async -> [Locale] {
        let speech = await SpeechTranscriber.installedLocales
        let dictation = await DictationTranscriber.installedLocales
        return deduplicated(speech + dictation)
    }

    public static func isModelInstalled(for locale: Locale) async -> Bool {
        guard let resolved = await resolveModule(for: locale) else {
            return false
        }
        return await AssetInventory.status(forModules: [resolved.module]) == .installed
    }

    /// Ensures the model backing `locale` is installed, downloading it if
    /// necessary. `progress` receives fractionCompleted (0...1) during a
    /// download.
    public static func prepareModel(
        for locale: Locale,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let resolved = await resolveModule(for: locale) else {
            throw AppleOnDeviceTranscriberError.unsupportedLocale(
                locale.identifier(.bcp47)
            )
        }
        try await installModelIfNeeded(
            module: resolved.module,
            localeID: resolved.locale.identifier(.bcp47),
            progress: progress
        )
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

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: audioURL)
        } catch {
            throw AppleOnDeviceTranscriberError.audioUnreadable(
                error.localizedDescription
            )
        }

        if let speechLocale = await SpeechTranscriber.supportedLocale(
            equivalentTo: locale
        ) {
            let transcriber = SpeechTranscriber(
                locale: speechLocale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange, .transcriptionConfidence]
            )
            try await Self.installModelIfNeeded(
                module: transcriber,
                localeID: speechLocale.identifier(.bcp47)
            )
            let result = try await Self.analyze(file: file, module: transcriber) {
                var segments = [OnbiiTranscriptSegment]()
                var textParts = [String]()
                for try await value in transcriber.results {
                    Self.appendSegments(
                        from: value.text,
                        sourceRole: sourceRole,
                        into: &segments,
                        textParts: &textParts
                    )
                }
                return (segments, textParts.joined(separator: " "))
            }
            return OnbiiTrackTranscript(
                sourceResourceID: sourceResourceID,
                sourceRole: sourceRole,
                localeIdentifier: speechLocale.identifier(.bcp47),
                formattedText: result.text,
                segments: result.segments
            )
        } else if let dictationLocale = await DictationTranscriber.supportedLocale(
            equivalentTo: locale
        ) {
            let transcriber = DictationTranscriber(
                locale: dictationLocale,
                contentHints: [],
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange, .transcriptionConfidence]
            )
            try await Self.installModelIfNeeded(
                module: transcriber,
                localeID: dictationLocale.identifier(.bcp47)
            )
            let result = try await Self.analyze(file: file, module: transcriber) {
                var segments = [OnbiiTranscriptSegment]()
                var textParts = [String]()
                for try await value in transcriber.results {
                    Self.appendSegments(
                        from: value.text,
                        sourceRole: sourceRole,
                        into: &segments,
                        textParts: &textParts
                    )
                }
                return (segments, textParts.joined(separator: " "))
            }
            return OnbiiTrackTranscript(
                sourceResourceID: sourceResourceID,
                sourceRole: sourceRole,
                localeIdentifier: dictationLocale.identifier(.bcp47),
                formattedText: result.text,
                segments: result.segments
            )
        } else {
            throw AppleOnDeviceTranscriberError.unsupportedLocale(
                locale.identifier(.bcp47)
            )
        }
    }

    // MARK: Internals

    private static func resolveModule(
        for locale: Locale
    ) async -> (module: any SpeechModule, locale: Locale)? {
        if let speechLocale = await SpeechTranscriber.supportedLocale(
            equivalentTo: locale
        ) {
            let module = SpeechTranscriber(
                locale: speechLocale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )
            return (module, speechLocale)
        }
        if let dictationLocale = await DictationTranscriber.supportedLocale(
            equivalentTo: locale
        ) {
            let module = DictationTranscriber(
                locale: dictationLocale,
                contentHints: [],
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )
            return (module, dictationLocale)
        }
        return nil
    }

    private static func installModelIfNeeded(
        module: any SpeechModule,
        localeID: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let status = await AssetInventory.status(forModules: [module])
        if status == .installed {
            return
        }
        guard status != .unsupported else {
            throw AppleOnDeviceTranscriberError.unsupportedLocale(localeID)
        }
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [module]
        ) else {
            return
        }
        let observation = progress.map { handler in
            request.progress.observe(
                \.fractionCompleted,
                options: [.initial, .new]
            ) { progress, _ in
                handler(progress.fractionCompleted)
            }
        }
        defer { observation?.invalidate() }
        try await request.downloadAndInstall()
    }

    private static func analyze(
        file: AVAudioFile,
        module: any SpeechModule,
        collect: @escaping @Sendable () async throws
            -> (segments: [OnbiiTranscriptSegment], text: String)
    ) async throws -> (segments: [OnbiiTranscriptSegment], text: String) {
        let analyzer = SpeechAnalyzer(modules: [module])
        let collector = Task { try await collect() }
        do {
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            _ = try? await collector.value
            throw AppleOnDeviceTranscriberError.recognitionFailed(
                error.localizedDescription
            )
        }
        return try await collector.value
    }

    private static func appendSegments(
        from attributed: AttributedString,
        sourceRole: String,
        into segments: inout [OnbiiTranscriptSegment],
        textParts: inout [String]
    ) {
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

    private static func deduplicated(_ locales: [Locale]) -> [Locale] {
        var seen = Set<String>()
        var result = [Locale]()
        for locale in locales where seen.insert(locale.identifier(.bcp47)).inserted {
            result.append(locale)
        }
        return result
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
