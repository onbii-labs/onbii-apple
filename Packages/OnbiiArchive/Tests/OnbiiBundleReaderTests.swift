import Foundation
import OnbiiArchive
import OnbiiCore
import Testing

@Test
func readerLoadsBundleWrittenByWriter() throws {
    let temporaryDirectory = try makeReaderTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let sourceURL = temporaryDirectory.appendingPathComponent("original.m4a")
    try Data("audio".utf8).write(to: sourceURL)
    let bundleURL = temporaryDirectory.appendingPathComponent("Readable.onbii")
    let request = OnbiiImportRequest(
        sourceAudioURL: sourceURL,
        destinationBundleURL: bundleURL,
        objectID: .init(rawValue: "readable-object"),
        title: "Readable",
        createdAt: Date(timeIntervalSince1970: 0),
        mediaType: "audio/mp4"
    )
    let writtenManifest = try OnbiiBundleWriter().write(request)

    let bundle = try OnbiiBundleReader().read(at: bundleURL)

    #expect(bundle.url == bundleURL)
    #expect(bundle.manifest == writtenManifest)
    #expect(
        bundle.url(for: bundle.manifest.resources[0])
            == bundleURL.appendingPathComponent("source/recording.m4a")
    )
}

@Test
func readerRejectsMalformedManifest() throws {
    let temporaryDirectory = try makeReaderTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let bundleURL = temporaryDirectory.appendingPathComponent("Malformed.onbii")
    try FileManager.default.createDirectory(
        at: bundleURL,
        withIntermediateDirectories: true
    )
    try Data("not json".utf8).write(
        to: bundleURL.appendingPathComponent("manifest.json")
    )

    #expect(throws: OnbiiBundleReaderError.manifestCannotBeDecoded) {
        try OnbiiBundleReader().read(at: bundleURL)
    }
}

@Test
func readerRejectsMissingDeclaredResource() throws {
    let temporaryDirectory = try makeReaderTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let sourceURL = temporaryDirectory.appendingPathComponent("original.m4a")
    try Data("audio".utf8).write(to: sourceURL)
    let bundleURL = temporaryDirectory.appendingPathComponent("Incomplete.onbii")
    let request = OnbiiImportRequest(
        sourceAudioURL: sourceURL,
        destinationBundleURL: bundleURL,
        title: "Incomplete"
    )
    try OnbiiBundleWriter().write(request)
    try FileManager.default.removeItem(
        at: bundleURL.appendingPathComponent("source/recording.m4a")
    )

    #expect(
        throws: OnbiiBundleReaderError.declaredResourceIsMissing(
            id: "source-recording",
            path: "source/recording.m4a"
        )
    ) {
        try OnbiiBundleReader().read(at: bundleURL)
    }
}

private func makeReaderTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}
