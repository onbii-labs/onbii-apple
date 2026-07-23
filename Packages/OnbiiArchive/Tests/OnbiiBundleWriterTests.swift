import Foundation
import OnbiiArchive
import OnbiiCore
import Testing

@Test
func importCreatesInspectableBundleAndPreservesSource() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let sourceURL = temporaryDirectory.appendingPathComponent("original.m4a")
    let sourceData = Data("source audio bytes".utf8)
    try sourceData.write(to: sourceURL)

    let bundleURL = temporaryDirectory.appendingPathComponent(
        "Conversation.onbii",
        isDirectory: true
    )
    let request = OnbiiImportRequest(
        sourceAudioURL: sourceURL,
        destinationBundleURL: bundleURL,
        objectID: .init(rawValue: "object-1"),
        title: "Conversation",
        createdAt: Date(timeIntervalSince1970: 0),
        mediaType: "audio/mp4"
    )

    let writtenManifest = try OnbiiBundleWriter().write(request)

    #expect(
        try Data(contentsOf: bundleURL.appendingPathComponent("source/recording.m4a"))
            == sourceData
    )
    let markdown = try String(
        contentsOf: bundleURL.appendingPathComponent("content.md"),
        encoding: .utf8
    )
    #expect(markdown.contains("# Conversation"))
    #expect(markdown.contains("_Transcription pending._"))

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decodedManifest = try decoder.decode(
        OnbiiManifest.self,
        from: Data(contentsOf: bundleURL.appendingPathComponent("manifest.json"))
    )
    #expect(decodedManifest == writtenManifest)
    try decodedManifest.validate()
    #expect(decodedManifest.resources.first?.originalFilename == "original.m4a")
    #expect(decodedManifest.resources.first?.role == .source)
}

@Test
func writerDoesNotReplaceExistingBundle() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let sourceURL = temporaryDirectory.appendingPathComponent("original.m4a")
    try Data().write(to: sourceURL)
    let bundleURL = temporaryDirectory.appendingPathComponent("Existing.onbii")
    try FileManager.default.createDirectory(
        at: bundleURL,
        withIntermediateDirectories: true
    )
    let request = OnbiiImportRequest(
        sourceAudioURL: sourceURL,
        destinationBundleURL: bundleURL,
        title: "Existing"
    )

    #expect(throws: OnbiiBundleWriterError.destinationAlreadyExists(bundleURL.path)) {
        try OnbiiBundleWriter().write(request)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}
