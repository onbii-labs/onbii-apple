import Foundation
@testable import OnbiiArchive
import OnbiiCore
import Testing

/// Spec decision `0032`: reprocessing supersedes. It neither overwrites nor
/// forks. Field test 1 produced the case that forced it — an object transcribed
/// in the wrong language that could not be transcribed again, because the
/// implementation treated *a transcript exists* as a terminal state.
@Suite
struct SupersessionTests {
    @Test
    func theNewGenerationBecomesCurrentAndTheOldOneIsRetained() throws {
        let object = try Object()
        try object.transcribe(text: "wrong language", at: object.firstRun)
        let superseded = try object.transcribe(
            text: "right language",
            at: object.secondRun
        )

        // Current: same path, same ID, new content. Every existing reader —
        // Finder, Quick Look, Obsidian, both apps — finds it unchanged.
        let current = try #require(
            superseded.manifest.resources.first { $0.id == "derived-transcript" }
        )
        #expect(current.path == "derived/transcript.json")
        #expect(
            try String(contentsOf: superseded.url(for: current), encoding: .utf8)
                == "right language"
        )

        // Retained: the earlier generation is still declared, still on disk,
        // and still says what it said.
        let retiredID = OnbiiSupersededGeneration.resourceID(
            for: "derived-transcript",
            at: object.secondRun
        )
        let retired = try #require(
            superseded.manifest.resources.first { $0.id == retiredID }
        )
        #expect(retired.path.hasPrefix("superseded/"))
        #expect(
            try String(contentsOf: superseded.url(for: retired), encoding: .utf8)
                == "wrong language"
        )
    }

    /// `0032`: provenance must express supersession, not only creation — which
    /// result replaced which, produced by what, and when.
    @Test
    func provenanceNamesWhichResultReplacedWhich() throws {
        let object = try Object()
        try object.transcribe(text: "first", at: object.firstRun)
        let superseded = try object.transcribe(text: "second", at: object.secondRun)

        let event = try #require(
            superseded.manifest.provenance.first {
                $0.action == OnbiiProvenanceEvent.supersededAction
            }
        )
        #expect(event.occurredAt == object.secondRun)
        #expect(
            event.inputResourceIDs.contains(
                OnbiiSupersededGeneration.resourceID(
                    for: "derived-transcript",
                    at: object.secondRun
                )
            )
        )
        #expect(event.outputResourceIDs.contains("derived-transcript"))
    }

    /// `0033`: each generation keeps the configuration it was made with, rather
    /// than inheriting the current one. That is the whole point — it is how
    /// "transcribed badly" is told apart from "transcribed under the wrong
    /// assumption".
    @Test
    func eachGenerationKeepsTheConfigurationItWasMadeWith() throws {
        let object = try Object()
        try object.transcribe(
            text: "first",
            at: object.firstRun,
            languages: ["en-AU"]
        )
        let superseded = try object.transcribe(
            text: "second",
            at: object.secondRun,
            languages: ["nl-NL"]
        )

        let generations = superseded.manifest.transcriptGenerations
        #expect(generations.count == 2)
        #expect(generations[0].configuration?.languages == ["en-AU"])
        #expect(generations[0].isCurrent == false)
        #expect(generations[1].configuration?.languages == ["nl-NL"])
        #expect(generations[1].isCurrent)
        #expect(
            generations[1].configuration?.spokenDescription?.contains("Dutch")
                == true
        )
    }

    /// A retired identifier must not read as a current transcript.
    /// `OnbiiObjectStatus` matches those identifiers exactly, and an object
    /// holding only superseded results is not a transcribed object.
    @Test
    func retiredIdentifiersDoNotCountAsATranscript() {
        let retired = OnbiiSupersededGeneration.resourceID(
            for: "derived-transcript",
            at: Date(timeIntervalSince1970: 1_000)
        )
        #expect(!OnbiiManifest.transcriptResourceIDs.contains(retired))
        #expect(retired.hasPrefix("superseded-"))

        let manifest = OnbiiManifest(
            objectID: .generated(),
            objectType: "recorded-conversation",
            title: "Only superseded",
            createdAt: Date(timeIntervalSince1970: 0),
            resources: [
                OnbiiResource(
                    id: retired,
                    role: .derived,
                    path: "superseded/x/derived/transcript.json",
                    mediaType: "application/json"
                ),
            ],
            provenance: []
        )
        #expect(!manifest.hasTranscript)
    }

    /// The object stays a valid Onbii bundle: the reader confirms every declared
    /// resource exists, retained generations included.
    @Test
    func theObjectRemainsReadableAfterSupersession() throws {
        let object = try Object()
        try object.transcribe(text: "first", at: object.firstRun)
        try object.transcribe(text: "second", at: object.secondRun)

        let reread = try OnbiiBundleReader().read(at: object.bundleURL)
        #expect(reread.manifest.hasTranscript)
        #expect(reread.status == .transcribed)
        // The source is untouched by any of this.
        let source = try #require(
            reread.manifest.resources.first { $0.role == .source }
        )
        #expect(
            try Data(contentsOf: reread.url(for: source)) == Data("audio".utf8)
        )
    }

    /// Superseding something that is not there is a caller mistake, not a quiet
    /// no-op: adding a first generation is what `artifacts` is for.
    @Test
    func supersedingSomethingThatDoesNotExistIsRejected() throws {
        let object = try Object()
        #expect(throws: OnbiiBundleEnricherError.self) {
            try object.transcribe(text: "no previous", at: object.firstRun, superseding: true)
        }
    }
}

// MARK: - Helpers

/// A real bundle on disk, transcribed through the real enricher.
private struct Object {
    let directory: URL
    let bundleURL: URL
    let firstRun = Date(timeIntervalSince1970: 1_000_000)
    let secondRun = Date(timeIntervalSince1970: 2_000_000)

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnbiiSupersessionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let sourceURL = directory.appendingPathComponent("recording.m4a")
        try Data("audio".utf8).write(to: sourceURL)
        bundleURL = directory.appendingPathComponent("Object.onbii")

        try OnbiiBundleWriter().write(
            OnbiiImportRequest(
                sources: [
                    OnbiiSourceFile(
                        resourceID: "source-recording",
                        sourceURL: sourceURL,
                        storedFilename: "recording.m4a",
                        mediaType: "audio/mp4"
                    ),
                ],
                destinationBundleURL: bundleURL,
                title: "Object",
                createdAt: Date(timeIntervalSince1970: 0),
                sourceAction: "captured",
                sourceAgentName: "test"
            )
        )
    }

    /// Attaches a transcript the way `OnbiiProcessing` does: an addition the
    /// first time, a supersession after that.
    @discardableResult
    func transcribe(
        text: String,
        at date: Date,
        languages: [String] = ["nl-NL"],
        superseding forced: Bool? = nil
    ) throws -> OnbiiBundle {
        let stageURL = directory.appendingPathComponent("stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: stageURL,
            withIntermediateDirectories: true
        )
        let jsonURL = stageURL.appendingPathComponent("transcript.json")
        try Data(text.utf8).write(to: jsonURL)

        let artifact = OnbiiBundleArtifact(
            sourceURL: jsonURL,
            resourceID: "derived-transcript",
            role: .derived,
            path: "derived/transcript.json",
            mediaType: "application/json"
        )
        let existing = try OnbiiBundleReader().read(at: bundleURL)
        let supersedes = forced
            ?? existing.manifest.resources.contains { $0.id == artifact.resourceID }

        return try OnbiiBundleEnricher().enrich(
            OnbiiBundleEnrichmentRequest(
                bundleURL: bundleURL,
                artifacts: supersedes ? [] : [artifact],
                supersessions: supersedes
                    ? [OnbiiBundleSupersession(artifact: artifact)] : [],
                action: "transcribed",
                occurredAt: date,
                agent: .init(kind: "software", name: "test transcriber"),
                inputResourceIDs: ["source-recording"],
                configuration: OnbiiDerivationConfiguration(
                    languages: languages,
                    languageSelection: .chosen
                )
            )
        )
    }
}
