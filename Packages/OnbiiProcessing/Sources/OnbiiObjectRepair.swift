#if os(macOS) || os(iOS)
import Foundation
import OnbiiArchive
import OnbiiCore
import OnbiiTranscription

/// Re-derives what an object records about itself, and corrects it where the
/// object's own contents show it to be wrong.
///
/// Two facts from the first field test motivate this. A twenty-minute Watch
/// recording is filed as `durationSeconds: 0`, because the app was suspended and
/// the capture timer reported zero. All three objects carry good coordinates and
/// `"name": ""`, because the geocoder had no label for a spot in a park that
/// morning. Both were fixed for objects written afterwards; neither fix reaches
/// back, and regenerating `content.md` during a re-transcription faithfully
/// reproduced both.
///
/// ## Why this is not supersession
///
/// [`0032`](../../../docs/spec/docs/decisions/0032-reprocessing-supersedes-and-retains.md)
/// governs derived *results* — a transcript replaced by a better transcript.
/// These are facts about the object: how long the preserved audio is, what the
/// coordinates are called. There is no earlier "generation" of a duration to
/// retain, only a wrong number to correct, and the provenance says a correction
/// happened and what made it. The rendering it feeds — `content.md` — *is* a
/// resource, and that does supersede, so the object still shows what it used to
/// say.
///
/// ## What it will not touch
///
/// Only gaps and demonstrable falsehoods. A duration is corrected because the
/// preserved file is evidence against the recorded one. A place name is only
/// ever *filled in*, never replaced: a name already there may have been typed by
/// a person, and
/// [`0010`](../../../docs/spec/docs/decisions/0010-human-edits-are-protected.md)
/// requires that reprocessing never displaces a human edit. Sources are not read
/// for anything except their length, and never modified.
///
/// Repair is a deliberate act. Nothing here happens because an object was opened
/// or synced.
public struct OnbiiObjectRepair: Sendable {
    /// Resolves coordinates to a place name. Injected rather than imported so
    /// this stays free of `OnbiiCapture`: a geocoder is a metadata oracle, not
    /// part of acquisition, and a different implementation should be able to
    /// supply a different one.
    public typealias PlaceNameResolver = @Sendable (
        _ latitude: Double, _ longitude: Double
    ) async -> String?

    /// What an object would gain from being repaired, or did gain.
    public struct Findings: Sendable, Equatable {
        /// Source resource IDs whose recorded duration the file contradicts,
        /// with what the file actually holds.
        public var durations: [String: Double] = [:]
        /// A name for coordinates that have none.
        public var placeName: String?

        public init(durations: [String: Double] = [:], placeName: String? = nil) {
            self.durations = durations
            self.placeName = placeName
        }

        public var isEmpty: Bool {
            durations.isEmpty && placeName == nil
        }

        /// What to tell someone before they decide to repair.
        public var summary: String? {
            var parts = [String]()
            if !durations.isEmpty {
                parts.append(
                    durations.count == 1
                        ? "a recorded duration the audio contradicts"
                        : "\(durations.count) recorded durations the audio contradicts"
                )
            }
            if placeName != nil {
                parts.append("a place with no name")
            }
            guard !parts.isEmpty else { return nil }
            return "This object has " + parts.joined(separator: " and ") + "."
        }
    }

    public static let agentName = "OnbiiArchive fact repair"

    public init() {}

    /// What is wrong with this object, without changing anything.
    ///
    /// Safe to call on any object, including while browsing: it reads the
    /// preserved audio's length and asks the resolver for a name. It writes
    /// nothing.
    public func findings(
        for bundle: OnbiiBundle,
        resolvingPlaceName resolver: PlaceNameResolver? = nil
    ) async -> Findings {
        var findings = Findings()

        for resource in bundle.manifest.resources where resource.role == .source {
            guard OnbiiSourceDuration.isMeasurable(mediaType: resource.mediaType),
                  let measured = OnbiiSourceDuration.seconds(
                      of: bundle.url(for: resource)
                  ),
                  OnbiiSourceDuration.disagrees(
                      reported: resource.durationSeconds,
                      measured: measured
                  ) || resource.durationSeconds == nil else {
                continue
            }
            findings.durations[resource.id] = measured
        }

        if let location = bundle.manifest.location,
           location.resolvedName == nil,
           let resolver {
            findings.placeName = await resolver(
                location.latitude, location.longitude
            )
        }

        return findings
    }

    /// Corrects the object, and regenerates `content.md` so the readable facet
    /// stops repeating what was wrong.
    ///
    /// - Returns: the object as it now stands, and what was corrected. Returns
    ///   the bundle untouched when there is nothing to correct — a repair that
    ///   finds nothing writes nothing.
    @discardableResult
    public func repair(
        _ bundle: OnbiiBundle,
        resolvingPlaceName resolver: PlaceNameResolver? = nil,
        occurredAt: Date = Date()
    ) async throws -> (bundle: OnbiiBundle, corrected: Findings) {
        let findings = await findings(for: bundle, resolvingPlaceName: resolver)
        guard !findings.isEmpty else {
            return (bundle, findings)
        }

        // Apply to a copy first, so `content.md` is rendered from the corrected
        // facts rather than the ones being replaced.
        var corrected = bundle.manifest
        let corrections = OnbiiRecordedFactCorrections(
            sourceDurations: findings.durations,
            locationName: findings.placeName
        )
        corrections.apply(to: &corrected)

        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "OnbiiRepair-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let contentURL = workingDirectory.appendingPathComponent("content.md")
        try Data(Self.renderContent(for: corrected, in: bundle).utf8)
            .write(to: contentURL, options: .atomic)

        let request = OnbiiBundleEnrichmentRequest(
            bundleURL: bundle.url,
            artifacts: [],
            supersessions: [
                OnbiiBundleSupersession(
                    artifact: OnbiiBundleArtifact(
                        sourceURL: contentURL,
                        resourceID: "content-markdown",
                        role: .humanReadable,
                        path: "content.md",
                        mediaType: "text/markdown; charset=utf-8"
                    )
                ),
            ],
            action: OnbiiProvenanceEvent.correctedAction,
            occurredAt: occurredAt,
            agent: .init(kind: "software", name: Self.agentName),
            inputResourceIDs: bundle.manifest.resources
                .filter { findings.durations.keys.contains($0.id) }
                .map(\.id),
            corrections: corrections
        )
        let repaired = try await Task.detached(priority: .userInitiated) {
            try OnbiiBundleEnricher().enrich(request)
        }.value
        return (repaired, findings)
    }

    /// Re-renders the object's front page from a corrected manifest, keeping
    /// whatever transcript it already presents.
    private static func renderContent(
        for manifest: OnbiiManifest,
        in bundle: OnbiiBundle
    ) -> String {
        var transcript: String?
        var speakerCount: Int?
        if let resource = manifest.resources.first(
            where: { $0.id == "derived-transcript" }
        ), let data = try? Data(contentsOf: bundle.url(for: resource)) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let document = try? decoder.decode(
                OnbiiTranscriptDocument.self, from: data
            ) {
                transcript = OnbiiTranscriptMarkdown.body(document)
                let speakers = Set(document.timeline.compactMap(\.speakerID)).count
                speakerCount = speakers > 0 ? speakers : nil
            }
        }

        return OnbiiContentMarkdown.render(
            title: manifest.title,
            createdAt: manifest.createdAt,
            sources: manifest.resources
                .filter { $0.role == .source }
                .map {
                    OnbiiContentMarkdown.Source(
                        storedPath: $0.path,
                        originalFilename: $0.originalFilename
                    )
                },
            location: manifest.location,
            sourceApplications: manifest.sourceApplications,
            transcript: transcript,
            speakerCount: speakerCount
        )
    }
}
#endif
