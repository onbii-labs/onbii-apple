import Foundation
import OnbiiArchive
import OnbiiCore
import Testing

@Test
func enrichmentAddsTranscriptArtifactsAndPreservesSourceBytes() throws {
    let temporaryDirectory = try makeEnrichmentTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let sourceURL = temporaryDirectory.appendingPathComponent("recording.m4a")
    let sourceBytes = Data("irreplaceable source audio".utf8)
    try sourceBytes.write(to: sourceURL)
    let bundleURL = temporaryDirectory.appendingPathComponent("Recording.onbii")
    try OnbiiBundleWriter().write(
        OnbiiImportRequest(
            sourceAudioURL: sourceURL,
            destinationBundleURL: bundleURL,
            objectID: .init(rawValue: "object-1"),
            title: "Recording"
        )
    )

    let transcriptJSON = temporaryDirectory.appendingPathComponent("transcript.json")
    let transcriptMarkdown = temporaryDirectory.appendingPathComponent("transcript.md")
    try Data(#"{"timeline":[]}"#.utf8).write(to: transcriptJSON)
    try Data("# Transcript\n".utf8).write(to: transcriptMarkdown)

    let enriched = try OnbiiBundleEnricher().enrich(
        OnbiiBundleEnrichmentRequest(
            bundleURL: bundleURL,
            artifacts: [
                OnbiiBundleArtifact(
                    sourceURL: transcriptJSON,
                    resourceID: "derived-transcript",
                    role: .derived,
                    path: "derived/transcript.json",
                    mediaType: "application/json"
                ),
                OnbiiBundleArtifact(
                    sourceURL: transcriptMarkdown,
                    resourceID: "transcript-markdown",
                    role: .humanReadable,
                    path: "transcript.md",
                    mediaType: "text/markdown; charset=utf-8"
                ),
            ],
            action: "transcribed",
            occurredAt: Date(timeIntervalSince1970: 10),
            agent: .init(kind: "software", name: "Apple Speech on-device"),
            inputResourceIDs: ["source-recording"]
        )
    )

    #expect(
        try Data(contentsOf: bundleURL.appendingPathComponent("source/recording.m4a"))
            == sourceBytes
    )
    #expect(enriched.manifest.resources.contains { $0.id == "derived-transcript" })
    #expect(enriched.manifest.resources.contains { $0.id == "transcript-markdown" })
    #expect(enriched.manifest.provenance.last?.action == "transcribed")
    #expect(enriched.manifest.provenance.last?.inputResourceIDs == ["source-recording"])
    #expect(
        Set(enriched.manifest.provenance.last?.outputResourceIDs ?? []) == [
            "derived-transcript",
            "transcript-markdown",
        ]
    )
}

@Test
func invalidEnrichmentLeavesOriginalBundleReadable() throws {
    let temporaryDirectory = try makeEnrichmentTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let sourceURL = temporaryDirectory.appendingPathComponent("recording.m4a")
    try Data("source".utf8).write(to: sourceURL)
    let bundleURL = temporaryDirectory.appendingPathComponent("Recording.onbii")
    try OnbiiBundleWriter().write(
        OnbiiImportRequest(
            sourceAudioURL: sourceURL,
            destinationBundleURL: bundleURL,
            title: "Recording"
        )
    )
    let originalManifestData = try Data(
        contentsOf: bundleURL.appendingPathComponent("manifest.json")
    )

    #expect(throws: OnbiiBundleEnricherError.duplicateResourceID("content-markdown")) {
        try OnbiiBundleEnricher().enrich(
            OnbiiBundleEnrichmentRequest(
                bundleURL: bundleURL,
                artifacts: [
                    OnbiiBundleArtifact(
                        sourceURL: sourceURL,
                        resourceID: "content-markdown",
                        role: .derived,
                        path: "derived/transcript.json",
                        mediaType: "application/json"
                    ),
                ],
                action: "transcribed",
                agent: .init(kind: "software", name: "test"),
                inputResourceIDs: ["source-recording"]
            )
        )
    }

    let unchangedBundle = try OnbiiBundleReader().read(at: bundleURL)
    #expect(unchangedBundle.manifest.title == "Recording")
    #expect(
        try Data(contentsOf: bundleURL.appendingPathComponent("manifest.json"))
            == originalManifestData
    )
}

@Test
func enrichmentReplacesContentMarkdownInPlace() throws {
    let temporaryDirectory = try makeEnrichmentTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let sourceURL = temporaryDirectory.appendingPathComponent("recording.m4a")
    let sourceBytes = Data("irreplaceable source audio".utf8)
    try sourceBytes.write(to: sourceURL)
    let bundleURL = temporaryDirectory.appendingPathComponent("Recording.onbii")
    try OnbiiBundleWriter().write(
        OnbiiImportRequest(
            sourceAudioURL: sourceURL,
            destinationBundleURL: bundleURL,
            title: "Recording"
        )
    )
    let contentPath = bundleURL.appendingPathComponent("content.md")
    #expect(try String(contentsOf: contentPath, encoding: .utf8)
        .contains("_Transcription pending._"))

    let newContent = temporaryDirectory.appendingPathComponent("new-content.md")
    try Data("# Recording\n\n## Transcript\n\n**00:00 Speaker 1:** Hi\n".utf8)
        .write(to: newContent)

    let enriched = try OnbiiBundleEnricher().enrich(
        OnbiiBundleEnrichmentRequest(
            bundleURL: bundleURL,
            artifacts: [],
            replacements: [
                OnbiiBundleArtifact(
                    sourceURL: newContent,
                    resourceID: "content-markdown",
                    role: .humanReadable,
                    path: "content.md",
                    mediaType: "text/markdown; charset=utf-8"
                ),
            ],
            action: "transcribed",
            agent: .init(kind: "software", name: "test"),
            inputResourceIDs: ["source-recording"]
        )
    )

    let updated = try String(contentsOf: contentPath, encoding: .utf8)
    #expect(updated.contains("**00:00 Speaker 1:** Hi"))
    #expect(!updated.contains("_Transcription pending._"))
    // Exactly one content-markdown resource (replaced, not duplicated).
    #expect(
        enriched.manifest.resources.filter { $0.id == "content-markdown" }.count == 1
    )
    #expect(
        try Data(contentsOf: bundleURL.appendingPathComponent("source/recording.m4a"))
            == sourceBytes
    )
    #expect(enriched.manifest.provenance.last?.outputResourceIDs == ["content-markdown"])
    let resource = enriched.manifest.resources.first { $0.id == "content-markdown" }
    #expect(resource?.byteCount == Int64(try Data(contentsOf: contentPath).count))
}

@Test
func enrichmentRejectsReplacementOfUnknownResource() throws {
    let temporaryDirectory = try makeEnrichmentTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let sourceURL = temporaryDirectory.appendingPathComponent("recording.m4a")
    try Data("source".utf8).write(to: sourceURL)
    let bundleURL = temporaryDirectory.appendingPathComponent("Recording.onbii")
    try OnbiiBundleWriter().write(
        OnbiiImportRequest(
            sourceAudioURL: sourceURL,
            destinationBundleURL: bundleURL,
            title: "Recording"
        )
    )
    let replacement = temporaryDirectory.appendingPathComponent("x.md")
    try Data("x".utf8).write(to: replacement)

    #expect(throws: OnbiiBundleEnricherError.unknownReplacementResource("nope")) {
        try OnbiiBundleEnricher().enrich(
            OnbiiBundleEnrichmentRequest(
                bundleURL: bundleURL,
                artifacts: [],
                replacements: [
                    OnbiiBundleArtifact(
                        sourceURL: replacement,
                        resourceID: "nope",
                        role: .humanReadable,
                        path: "nope.md",
                        mediaType: "text/markdown; charset=utf-8"
                    ),
                ],
                action: "transcribed",
                agent: .init(kind: "software", name: "test"),
                inputResourceIDs: []
            )
        )
    }
}

private func makeEnrichmentTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}
