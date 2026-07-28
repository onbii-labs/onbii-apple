import Foundation
import OnbiiArchive
import Testing

/// Waits for the watcher's next report, or gives up.
///
/// Generous on purpose: the watcher deliberately lets a burst settle before
/// reporting, and a test written tight against that interval is a test that
/// fails on a busy machine rather than a test that means anything.
private func nextChange(
    in stream: AsyncStream<Void>,
    within seconds: Double
) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await _ in stream { return true }
            return false
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return false
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
}

/// The behaviour the Mac window depends on: something lands in the archive and
/// the app is told to look again. Field test 2 found the app never being told.
///
/// This exercises the ordinary-folder mechanism. The iCloud one cannot be tested
/// here — it needs a ubiquity container, a signed app and a second device — and
/// the honest note about that limitation is in the watcher itself.
@Test
func aWatcherReportsSomethingArrivingInTheFolder() async throws {
    let directory = try makeWatcherTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let stream = await MainActor.run { () -> AsyncStream<Void> in
        let watcher = OnbiiArchiveWatcher(directoryURL: directory)
        watcher.start()
        // Deliberately retained by the stream's consumer for the length of the
        // test; `stop()` happens when the directory goes away with it.
        watchers.append(watcher)
        return watcher.changes
    }

    // Let the source attach before writing, or the write can precede the watch.
    try await Task.sleep(for: .milliseconds(200))
    try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("Arrived.onbii"),
        withIntermediateDirectories: true
    )

    #expect(await nextChange(in: stream, within: 5))
}

/// Stopping means stopping. A watcher still reporting after the archive changed
/// would re-read a folder nobody is looking at, and would keep a torn-down view
/// model alive to hear about it.
@Test
func aStoppedWatcherReportsNothing() async throws {
    let directory = try makeWatcherTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let stream = await MainActor.run { () -> AsyncStream<Void> in
        let watcher = OnbiiArchiveWatcher(directoryURL: directory)
        watcher.start()
        watcher.stop()
        // Retained deliberately. A watcher that deallocates here finishes its
        // stream on the way out, and the expectation below would pass without
        // `stop()` doing anything at all.
        watchers.append(watcher)
        return watcher.changes
    }

    try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("Ignored.onbii"),
        withIntermediateDirectories: true
    )

    #expect(!(await nextChange(in: stream, within: 1.5)))
}

/// Starting twice must not attach two watches to one folder — the second would
/// double every report and leak a descriptor — and the teardown must survive it.
@Test
func startingTwiceIsANoOpAndStoppingTwiceIsSafe() async throws {
    let directory = try makeWatcherTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    await MainActor.run {
        let watcher = OnbiiArchiveWatcher(directoryURL: directory)
        watcher.start()
        watcher.start()
        watcher.stop()
        watcher.stop()
    }
}

/// Held only so a watcher outlives the `MainActor.run` that made it; a watcher
/// that deallocates mid-test would stop reporting for the wrong reason.
@MainActor
private var watchers: [OnbiiArchiveWatcher] = []

private func makeWatcherTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}
