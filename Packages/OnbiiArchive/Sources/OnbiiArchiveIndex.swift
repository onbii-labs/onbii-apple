import Foundation
import OnbiiCore

/// Lists the Onbii objects that are present in one or more archive directories.
///
/// This is a read-only view over ordinary folders. It holds no state between
/// calls, writes nothing, and treats the filesystem as the truth every time it
/// is asked — an object that appears in the archive by any route (Finder, sync,
/// another app) is simply there on the next read.
///
/// Listing is deliberately best-effort. A bundle the reader rejects is skipped
/// rather than surfaced as a broken row or allowed to fail the whole listing:
/// readers must never partially trust a malformed object, and one bad folder
/// must not hide the user's other knowledge.
/// What one look at the archive found.
///
/// Two lists, because "not there" and "there but not readable yet" are different
/// facts and only one of them is the person's problem. An object arriving from
/// another device exists in the archive before it can be opened, and reporting
/// nothing about it is how an app comes to present a list that is quietly
/// missing something.
public struct OnbiiArchiveListing: Sendable {
    public var objects: [OnbiiBundle]
    /// Directories that carry the extension but could not be read — still
    /// arriving over sync, or damaged. Never silently dropped.
    public var unreadable: [URL]

    public init(objects: [OnbiiBundle], unreadable: [URL] = []) {
        self.objects = objects
        self.unreadable = unreadable
    }
}

public struct OnbiiArchiveIndex: Sendable {
    private let reader: OnbiiBundleReader

    public init(reader: OnbiiBundleReader = OnbiiBundleReader()) {
        self.reader = reader
    }

    /// Every readable `.onbii` object across the given directories, newest
    /// first. Duplicate directories are visited once, and an object reached
    /// through two directories is reported once.
    public func objects(in directories: [URL]) -> [OnbiiBundle] {
        contents(in: directories).objects
    }

    /// Everything one look found: the objects, and the entries that look like
    /// objects but could not be read.
    ///
    /// An unreadable entry is still reported rather than skipped. It is usually
    /// an object that has not finished arriving from another device, which is a
    /// temporary and unalarming state — but an app that never hears about it
    /// cannot say "one object is still arriving" and cannot ask for it to be
    /// downloaded. Occasionally it is a damaged folder, and that is worth
    /// knowing too.
    public func contents(in directories: [URL]) -> OnbiiArchiveListing {
        var seenDirectories: Set<String> = []
        var seenObjects: Set<String> = []
        var bundles: [OnbiiBundle] = []
        var unreadable: [URL] = []

        for directory in directories {
            let key = directory.standardizedFileURL.path
            guard seenDirectories.insert(key).inserted else { continue }

            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in contents where url.pathExtension.lowercased() == "onbii" {
                guard let bundle = try? reader.read(at: url) else {
                    unreadable.append(url)
                    continue
                }
                guard seenObjects.insert(bundle.manifest.objectID.rawValue).inserted
                else { continue }
                bundles.append(bundle)
            }
        }

        return OnbiiArchiveListing(
            objects: bundles.sorted { $0.manifest.createdAt > $1.manifest.createdAt },
            unreadable: unreadable
        )
    }

    /// Asks iCloud for anything that is present but not yet downloaded.
    ///
    /// Best-effort and deliberately silent: a failure here costs freshness and
    /// nothing else, and an entry that is damaged rather than absent will simply
    /// stay unreadable and be reported again on the next look.
    public func requestDownload(of urls: [URL]) {
        for url in urls {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }
}
