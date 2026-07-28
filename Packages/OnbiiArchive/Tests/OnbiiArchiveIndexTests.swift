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

// MARK: What a look found, including what it could not read

/// Skipping an unreadable bundle is right for the list of objects and wrong as
/// the whole answer. An object arriving from another device is unreadable for a
/// few seconds, and an app that never hears about it presents an incomplete
/// list as a complete one — which is how a recording made on a walk was missing
/// from a Mac window (field test 2).
@Test
func aListingReportsWhatItCouldNotReadRatherThanDroppingIt() throws {
    let directory = try makeIndexTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try writeBundle(in: directory, named: "Good", createdAt: 0)

    let arrivingURL = directory.appendingPathComponent("Arriving.onbii")
    try FileManager.default.createDirectory(
        at: arrivingURL,
        withIntermediateDirectories: true
    )

    let listing = OnbiiArchiveIndex().contents(in: [directory])

    #expect(listing.objects.map(\.manifest.title) == ["Good"])
    #expect(listing.unreadable.map(\.lastPathComponent) == ["Arriving.onbii"])
}

/// The convenience that every existing caller uses must keep behaving exactly as
/// it did: the objects, and only the objects.
@Test
func theObjectsCallStillReturnsOnlyWhatCouldBeRead() throws {
    let directory = try makeIndexTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try writeBundle(in: directory, named: "Good", createdAt: 0)
    try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("Broken.onbii"),
        withIntermediateDirectories: true
    )

    let index = OnbiiArchiveIndex()

    #expect(index.objects(in: [directory]).map(\.manifest.title) == ["Good"])
    #expect(index.objects(in: [directory]) == index.contents(in: [directory]).objects)
}

/// A folder with nothing wrong with it reports nothing wrong with it. The
/// "still arriving" line must not appear because a directory happens to be
/// empty.
@Test
func aHealthyArchiveReportsNothingUnreadable() throws {
    let directory = try makeIndexTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try writeBundle(in: directory, named: "One", createdAt: 0)
    try writeBundle(in: directory, named: "Two", createdAt: 1_000)

    let listing = OnbiiArchiveIndex().contents(in: [directory])

    #expect(listing.objects.count == 2)
    #expect(listing.unreadable.isEmpty)
}

/// Asking for a download of something that is not in iCloud must be a quiet
/// no-op rather than a throw: the same call runs over a damaged local folder.
@Test
func requestingADownloadOfALocalFolderIsHarmless() throws {
    let directory = try makeIndexTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let brokenURL = directory.appendingPathComponent("Broken.onbii")
    try FileManager.default.createDirectory(
        at: brokenURL,
        withIntermediateDirectories: true
    )

    OnbiiArchiveIndex().requestDownload(of: [brokenURL])

    #expect(FileManager.default.fileExists(atPath: brokenURL.path))
}
