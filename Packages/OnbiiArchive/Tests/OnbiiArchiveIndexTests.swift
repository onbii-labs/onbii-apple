import Foundation
import OnbiiArchive
import OnbiiCore
import Testing

@Test
func indexListsObjectsNewestFirst() throws {
    let directory = try makeIndexTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try writeBundle(in: directory, named: "Older", createdAt: 0)
    try writeBundle(in: directory, named: "Newer", createdAt: 1_000)

    let objects = OnbiiArchiveIndex().objects(in: [directory])

    #expect(objects.map(\.manifest.title) == ["Newer", "Older"])
}

@Test
func indexSkipsUnreadableBundlesInsteadOfFailing() throws {
    let directory = try makeIndexTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try writeBundle(in: directory, named: "Good", createdAt: 0)

    let brokenURL = directory.appendingPathComponent("Broken.onbii")
    try FileManager.default.createDirectory(
        at: brokenURL,
        withIntermediateDirectories: true
    )
    try Data("not json".utf8).write(
        to: brokenURL.appendingPathComponent("manifest.json")
    )

    let objects = OnbiiArchiveIndex().objects(in: [directory])

    #expect(objects.map(\.manifest.title) == ["Good"])
}

@Test
func indexIgnoresNonBundleEntries() throws {
    let directory = try makeIndexTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try writeBundle(in: directory, named: "Object", createdAt: 0)
    try Data("loose".utf8).write(to: directory.appendingPathComponent("notes.md"))
    try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("Some Folder"),
        withIntermediateDirectories: true
    )

    let objects = OnbiiArchiveIndex().objects(in: [directory])

    #expect(objects.count == 1)
}

@Test
func indexReportsAnObjectOnceAcrossRepeatedDirectories() throws {
    let directory = try makeIndexTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try writeBundle(in: directory, named: "Object", createdAt: 0)

    let objects = OnbiiArchiveIndex().objects(
        in: [directory, directory.appendingPathComponent("..").standardizedFileURL
            .appendingPathComponent(directory.lastPathComponent)]
    )

    #expect(objects.count == 1)
}

@Test
func indexReturnsNothingForAMissingDirectory() {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    #expect(OnbiiArchiveIndex().objects(in: [missing]).isEmpty)
}

@discardableResult
private func writeBundle(
    in directory: URL,
    named title: String,
    createdAt seconds: TimeInterval
) throws -> URL {
    let sourceURL = directory.appendingPathComponent("\(title).m4a")
    try Data("audio".utf8).write(to: sourceURL)

    let bundleURL = directory.appendingPathComponent("\(title).onbii")
    try OnbiiBundleWriter().write(
        OnbiiImportRequest(
            sourceAudioURL: sourceURL,
            destinationBundleURL: bundleURL,
            title: title,
            createdAt: Date(timeIntervalSince1970: seconds),
            mediaType: "audio/mp4"
        )
    )
    try FileManager.default.removeItem(at: sourceURL)
    return bundleURL
}

private func makeIndexTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}
