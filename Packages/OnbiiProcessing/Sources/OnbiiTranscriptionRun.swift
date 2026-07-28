#if os(macOS) || os(iOS)
import Foundation
import OnbiiArchive
import OnbiiCore
import OnbiiTranscription

/// Transcribing one object, end to end: recognise each source track, derive
/// rough speaker turns, render the readable facets, and attach the result to the
/// object with its provenance.
///
/// This lived twice — once in the Mac view model, once in the iPhone one — and
/// the two had already drifted. It sits here rather than in `OnbiiTranscription`
/// (which must not know what a bundle is) or `OnbiiArchive` (which must not know
/// what recognition is): composing them is a job of its own, and it is the
/// *processing pipeline* stage that `PRINCIPLES.md` already names.
///
/// It never touches a source. Transcription enriches an object; the recordings
/// it reads are returned exactly as they were.
public struct OnbiiTranscriptionRun: Sendable {
    /// What the run is doing, for an app that wants to say so.
    public enum Progress: Equatable, Sendable {
        case downloadingModel(language: String, fraction: Double)
        case transcribing(track: Int, of: Int)
        case identifyingSpeakers(track: Int, of: Int)
        case attaching
    }

    public enum RunError: Error, LocalizedError, Equatable {
        case noTranscribableAudio

        public var errorDescription: String? {
            switch self {
            case .noTranscribableAudio:
                "This object has no source audio to transcribe."
            }
        }
    }

    /// What a completed run produced.
    ///
    /// Recognising no speech is not an error. The run did everything it was
    /// asked to, the object is untouched apart from the record of the attempt,
    /// and the reason is usually the situation rather than anything wrong: a
    /// quiet walk, a recording of a room. Field test 2 showed what happens when
    /// this is thrown instead — the apps rendered it as *Needs attention*, which
    /// blames the object for a quiet morning.
    public enum Outcome: Sendable {
        /// A transcript was produced and attached.
        case transcribed(OnbiiBundle)
        /// Every second was read and no speech was recognised. The bundle is
        /// returned because it now records the attempt.
        case foundNoSpeech(
            bundle: OnbiiBundle,
            language: String,
            secondsListened: TimeInterval
        )

        /// The object as it now stands on disk, either way.
        public var bundle: OnbiiBundle {
            switch self {
            case let .transcribed(bundle): bundle
            case let .foundNoSpeech(bundle, _, _): bundle
            }
        }

        /// What to tell a person, where there is anything worth telling them.
        public var spokenSummary: String? {
            switch self {
            case .transcribed:
                nil
            case let .foundNoSpeech(_, language, seconds):
                "No speech was recognised in \(language) across "
                    + "\(Self.spoken(seconds)). The recording is unchanged — "
                    + "try another language if this one is wrong."
            }
        }

        private static func spoken(_ seconds: TimeInterval) -> String {
            let whole = Int(seconds.rounded())
            let minutes = whole / 60
            guard minutes > 0 else { return "\(whole) seconds" }
            return String(format: "%d:%02d", minutes, whole % 60)
        }
    }

    /// How a language came to be used, so the object can record it (`0033`).
    public struct Language: Sendable, Equatable {
        public var locale: Locale
        public var selection: OnbiiDerivationConfiguration.LanguageSelection

        public init(
            locale: Locale,
            selection: OnbiiDerivationConfiguration.LanguageSelection = .chosen
        ) {
            self.locale = locale
            self.selection = selection
        }
    }

    /// Identifies the speaker-turn model in provenance. Enough to tell two
    /// generations apart, which is what `0033` asks of a model identity.
    public static let speakerModelName = "3D-Speaker CAM++ (VoxCeleb) on-device"
    public static let transcriberName = "Apple Speech on-device"

    public init() {}

    /// Transcribes `bundle` and returns it as it now stands on disk.
    ///
    /// When the object already carries a transcript, the new one **supersedes**
    /// it: the earlier generation is retained with the configuration it was made
    /// under, and the newer becomes current (`0032`). Reprocessing is never
    /// automatic — it happens because someone asked for it.
    public func run(
        on bundle: OnbiiBundle,
        language: Language,
        progress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async throws -> Outcome {
        let sources = bundle.manifest.resources.filter {
            $0.role == .source && $0.mediaType.hasPrefix("audio/")
        }
        guard !sources.isEmpty else {
            throw RunError.noTranscribableAudio
        }

        try await installModelIfNeeded(for: language.locale, progress: progress)

        let transcriber = AppleOnDeviceTranscriber()
        let firstStart = sources.compactMap(\.captureStartedAt).min()
        var tracks = [OnbiiTrackTranscript]()
        var timelineInputs = [(transcript: OnbiiTrackTranscript, offset: TimeInterval)]()

        for (index, resource) in sources.enumerated() {
            progress(.transcribing(track: index + 1, of: sources.count))
            var transcript = try await transcriber.transcribe(
                audioURL: bundle.url(for: resource),
                sourceResourceID: resource.id,
                sourceRole: Self.trackRole(for: resource.id),
                locale: language.locale
            )
            progress(.identifyingSpeakers(track: index + 1, of: sources.count))
            transcript.segments = await Self.diarize(
                transcript.segments,
                audioURL: bundle.url(for: resource),
                labelPrefix: "t\(index)s"
            )
            let offset: TimeInterval = if let firstStart,
                let started = resource.captureStartedAt {
                max(0, started.timeIntervalSince(firstStart))
            } else {
                0
            }
            tracks.append(transcript)
            timelineInputs.append((transcript, offset: offset))
        }

        let generatedAt = Date()
        guard tracks.contains(where: { !$0.segments.isEmpty }) else {
            return try await recordFindingNothing(
                on: bundle,
                sources: sources,
                language: language,
                tracks: tracks,
                occurredAt: generatedAt
            )
        }

        let anyDiarized = tracks.contains { track in
            track.segments.contains { $0.speakerID != nil }
        }
        let document = OnbiiTranscriptDocument(
            generatedAt: generatedAt,
            tracks: tracks,
            timeline: OnbiiTranscriptTimeline.merge(timelineInputs),
            speakerModel: anyDiarized ? Self.speakerModelName : nil
        )

        progress(.attaching)
        return .transcribed(
            try await attach(
                document,
                to: bundle,
                sources: sources,
                language: language,
                tracks: tracks,
                generatedAt: generatedAt
            )
        )
    }

    // MARK: Finding nothing

    /// Writes the fact that a run happened and produced nothing.
    ///
    /// No resource is added — there is nothing to preserve, and an empty
    /// transcript would make the object claim to be transcribed. What goes in is
    /// the event and its configuration, so the object can later answer "has
    /// anyone tried, and in what language" without an application remembering
    /// it. Recording this must never turn a quiet recording into a failure: if
    /// the write fails, the outcome is still reported.
    private func recordFindingNothing(
        on bundle: OnbiiBundle,
        sources: [OnbiiResource],
        language: Language,
        tracks: [OnbiiTrackTranscript],
        occurredAt: Date
    ) async throws -> Outcome {
        var usedLanguages = [String]()
        for identifier in tracks.map(\.localeIdentifier)
        where !usedLanguages.contains(identifier) {
            usedLanguages.append(identifier)
        }
        if usedLanguages.isEmpty {
            usedLanguages = [language.locale.identifier(.bcp47)]
        }
        let request = OnbiiBundleEnrichmentRequest(
            bundleURL: bundle.url,
            artifacts: [],
            action: OnbiiProvenanceEvent.foundNothingAction,
            occurredAt: occurredAt,
            agent: .init(kind: "software", name: Self.transcriberName),
            inputResourceIDs: sources.map(\.id),
            configuration: OnbiiDerivationConfiguration(
                languages: usedLanguages,
                languageSelection: language.selection
            ),
            recordsOutcomeOnly: true
        )
        let recorded = try? await Task.detached(priority: .userInitiated) {
            try OnbiiBundleEnricher().enrich(request)
        }.value

        let spokenLanguage = OnbiiDerivationConfiguration.languageName(
            for: usedLanguages[0]
        )
        return .foundNoSpeech(
            bundle: recorded ?? bundle,
            language: spokenLanguage,
            secondsListened: sources.compactMap(\.durationSeconds).max() ?? 0
        )
    }

    // MARK: Attaching

    private func attach(
        _ document: OnbiiTranscriptDocument,
        to bundle: OnbiiBundle,
        sources: [OnbiiResource],
        language: Language,
        tracks: [OnbiiTrackTranscript],
        generatedAt: Date
    ) async throws -> OnbiiBundle {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "OnbiiTranscribing-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let jsonURL = workingDirectory.appendingPathComponent("transcript.json")
        let markdownURL = workingDirectory.appendingPathComponent("transcript.md")
        let contentURL = workingDirectory.appendingPathComponent("content.md")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [
            .prettyPrinted, .sortedKeys, .withoutEscapingSlashes,
        ]
        try encoder.encode(document).write(to: jsonURL, options: .atomic)
        try Data(
            OnbiiTranscriptMarkdown.render(
                document,
                title: bundle.manifest.title
            ).utf8
        ).write(to: markdownURL, options: .atomic)

        let speakerCount = Set(document.timeline.compactMap(\.speakerID)).count
        try Data(
            OnbiiContentMarkdown.render(
                title: bundle.manifest.title,
                createdAt: bundle.manifest.createdAt,
                sources: bundle.manifest.resources
                    .filter { $0.role == .source }
                    .map {
                        OnbiiContentMarkdown.Source(
                            storedPath: $0.path,
                            originalFilename: $0.originalFilename
                        )
                    },
                location: bundle.manifest.location,
                sourceApplications: bundle.manifest.sourceApplications,
                transcript: OnbiiTranscriptMarkdown.body(document),
                speakerCount: speakerCount > 0 ? speakerCount : nil
            ).utf8
        ).write(to: contentURL, options: .atomic)

        let transcriptArtifacts = [
            OnbiiBundleArtifact(
                sourceURL: jsonURL,
                resourceID: "derived-transcript",
                role: .derived,
                path: "derived/transcript.json",
                mediaType: "application/json"
            ),
            OnbiiBundleArtifact(
                sourceURL: markdownURL,
                resourceID: "transcript-markdown",
                role: .humanReadable,
                path: "transcript.md",
                mediaType: "text/markdown; charset=utf-8"
            ),
        ]
        let contentArtifact = OnbiiBundleArtifact(
            sourceURL: contentURL,
            resourceID: "content-markdown",
            role: .humanReadable,
            path: "content.md",
            mediaType: "text/markdown; charset=utf-8"
        )

        // A first transcript is an addition; a later one supersedes. The
        // difference is what 0032 is about, and it is decided by what the object
        // already holds rather than by anything the caller says.
        let existing = Set(bundle.manifest.resources.map(\.id))
        var artifacts = [OnbiiBundleArtifact]()
        var supersessions = [OnbiiBundleSupersession]()
        for artifact in transcriptArtifacts {
            if existing.contains(artifact.resourceID) {
                supersessions.append(OnbiiBundleSupersession(artifact: artifact))
            } else {
                artifacts.append(artifact)
            }
        }
        // `content.md` is the object's front page, regenerated from whatever is
        // current. It is a rendering, not a result, so it is retained alongside
        // the generation it belonged to rather than replaced in place.
        supersessions.append(OnbiiBundleSupersession(artifact: contentArtifact))

        // The languages actually used, not the ones asked for: the recogniser
        // resolves a request to a locale it supports, and the object should
        // record what happened. Plural because a single result may legitimately
        // involve more than one — 0033 requires that to be expressible.
        var usedLanguages = [String]()
        for identifier in tracks.map(\.localeIdentifier)
        where !usedLanguages.contains(identifier) {
            usedLanguages.append(identifier)
        }
        let request = OnbiiBundleEnrichmentRequest(
            bundleURL: bundle.url,
            artifacts: artifacts,
            supersessions: supersessions,
            action: "transcribed",
            occurredAt: generatedAt,
            agent: .init(
                kind: "software",
                name: Self.transcriberName,
                version: document.speakerModel.map {
                    "speakers: \($0)"
                }
            ),
            inputResourceIDs: sources.map(\.id),
            configuration: OnbiiDerivationConfiguration(
                languages: usedLanguages,
                languageSelection: language.selection
            )
        )
        return try await Task.detached(priority: .userInitiated) {
            try OnbiiBundleEnricher().enrich(request)
        }.value
    }

    // MARK: Pieces

    private func installModelIfNeeded(
        for locale: Locale,
        progress: @escaping @Sendable (Progress) -> Void
    ) async throws {
        guard !(await AppleOnDeviceTranscriber.isModelInstalled(for: locale)) else {
            return
        }
        let name = Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
        try await AppleOnDeviceTranscriber.prepareModel(for: locale) { fraction in
            progress(.downloadingModel(language: name, fraction: fraction))
        }
    }

    /// Best-effort rough speaker turns for one track. On any failure the
    /// segments are returned unchanged, so transcription still succeeds and the
    /// transcript falls back to track labels. Diarization is derived data and
    /// never blocks producing a transcript.
    static func diarize(
        _ segments: [OnbiiTranscriptSegment],
        audioURL: URL,
        labelPrefix: String
    ) async -> [OnbiiTranscriptSegment] {
        guard !segments.isEmpty else { return segments }
        do {
            let embedder = try OnbiiCoreMLSpeakerEmbedder(audioURL: audioURL)
            return try await OnbiiSpeakerDiarizer().diarize(
                track: segments,
                using: embedder,
                labelPrefix: labelPrefix
            )
        } catch {
            return segments
        }
    }

    /// Honest source attribution for a track. Dual-source call capture keeps its
    /// two legs distinguishable; anything else is just "the recording".
    static func trackRole(for resourceID: String) -> String {
        switch resourceID {
        case "source-system-audio": "system-audio"
        case "source-microphone-audio": "microphone"
        default: "recording"
        }
    }
}
#endif
