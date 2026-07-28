import Foundation

/// Reports that an archive directory has changed, so something can read it again.
///
/// It carries no objects and holds no state about them. Everything it says is
/// "look again"; ``OnbiiArchiveIndex`` remains the only thing that reads, and
/// the filesystem remains the truth every time it is asked. Deleting this type
/// would cost freshness and nothing else.
///
/// Field test 2 is why it exists: an object recorded on a walk was missing from
/// a freshly launched Mac window, because the app read the folder once and then
/// never again. Presenting a list as *the archive* while having no way to know
/// whether it still is, is the same class of dishonesty as claiming to record
/// while suspended.
///
/// **Two mechanisms, because an archive is not always one kind of place.** The
/// default archive lives in the app's iCloud Drive container, where objects
/// arrive from other devices and may exist before they are downloaded — that
/// needs `NSMetadataQuery`, which is the only API that reports an item the
/// filesystem cannot yet open. A person may equally point Onbii at an ordinary
/// folder on a disk, where there is no sync and a directory watch is exactly
/// right. Choosing by inspection rather than by configuration keeps the caller
/// from having to know which it has.
@MainActor
public final class OnbiiArchiveWatcher {
    /// Fires when the archive may have changed. Values are deliberately
    /// meaningless: the only correct response is to re-read.
    public let changes: AsyncStream<Void>

    /// How long to wait for a burst to settle before reporting it.
    ///
    /// iCloud reports a single arriving object as a stream of updates as it
    /// downloads. Re-reading the whole archive on each one would be wasteful and
    /// would flicker a list while a person is looking at it.
    public static let quietPeriod: Duration = .milliseconds(400)

    private let continuation: AsyncStream<Void>.Continuation
    private let directoryURL: URL
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var accessedSecurityScope = false
    private var settling: Task<Void, Never>?

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        (changes, continuation) = AsyncStream.makeStream()
    }

    deinit {
        // `stop()` is main-actor isolated and deinit is not, so the release of
        // the two resources that genuinely leak is done directly. Both are safe
        // from any thread.
        source?.cancel()
        if descriptor >= 0 {
            close(descriptor)
        }
    }

    /// Begins watching. Calling it twice is a no-op rather than a second watch.
    public func start() {
        guard query == nil, source == nil else { return }

        // Held for the lifetime of the watch: a directory descriptor and a
        // metadata query both need the access that a bookmark grants. The call
        // is reference-counted, so nesting inside a caller's own access is fine,
        // and it is a harmless `false` for a URL that never needed it.
        accessedSecurityScope = directoryURL.startAccessingSecurityScopedResource()

        if Self.canQueryMetadata(for: directoryURL) {
            startMetadataQuery()
        } else {
            startDirectoryWatch()
        }
    }

    public func stop() {
        settling?.cancel()
        settling = nil

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        query?.stop()
        query = nil

        source?.cancel()
        source = nil
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }

        if accessedSecurityScope {
            directoryURL.stopAccessingSecurityScopedResource()
            accessedSecurityScope = false
        }
    }

    // MARK: Mechanisms

    /// The iCloud case. `NSMetadataQuery` reports objects that exist but are not
    /// downloaded, which a directory watch cannot — and which is exactly the
    /// state an object is in shortly after another device made it.
    private func startMetadataQuery() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(
            format: "%K LIKE '*.onbii'",
            NSMetadataItemFSNameKey
        )
        // Batched rather than live: a download in progress otherwise produces a
        // notification per progress update.
        query.notificationBatchingInterval = 1.0

        for name in [
            NSNotification.Name.NSMetadataQueryDidFinishGathering,
            NSNotification.Name.NSMetadataQueryDidUpdate,
        ] {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: query,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.report()
                }
            }
            observers.append(observer)
        }

        self.query = query
        query.start()
    }

    /// The ordinary-folder case: watch the directory itself and re-read when it
    /// is written to. Nothing here knows what changed, which is the point.
    private func startDirectoryWatch() {
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // Nothing to watch and nothing to report. A folder that cannot be
            // opened is a problem the reader will surface far more usefully than
            // a watcher can.
            if accessedSecurityScope {
                directoryURL.stopAccessingSecurityScopedResource()
                accessedSecurityScope = false
            }
            return
        }
        self.descriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.report()
            }
        }
        source.resume()
        self.source = source
    }

    // MARK: Reporting

    /// Coalesces a burst into one report.
    private func report() {
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(for: Self.quietPeriod)
            guard !Task.isCancelled else { return }
            self?.continuation.yield(())
        }
    }

    /// Whether *this app* can watch this directory with an `NSMetadataQuery`.
    ///
    /// Not "is it in iCloud Drive" — that was the first version of this check
    /// and it was wrong in a way that broke the Mac completely.
    /// `NSMetadataQueryUbiquitousDocumentsScope` searches the app's **own**
    /// ubiquity container, so it needs the app to have one. The Mac app does not:
    /// it holds no `com.apple.developer.ubiquity-container-identifiers`
    /// entitlement and reaches iCloud Drive purely as a user-selected folder
    /// through a security-scoped bookmark. Asking it for a ubiquitous query
    /// produced a query over nothing, which never fired, so an object arriving
    /// from the iPhone was never noticed.
    ///
    /// A directory watch works there instead, and works well: iCloud
    /// materialises a file into the folder, and the folder changes.
    static func canQueryMetadata(for url: URL) -> Bool {
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: OnbiiCloudArchive.containerIdentifier
        ) else {
            return false
        }
        return url.standardizedFileURL.path.hasPrefix(
            container.standardizedFileURL.path
        )
    }
}
