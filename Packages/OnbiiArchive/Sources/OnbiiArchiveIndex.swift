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
public struct OnbiiArchiveIndex: Sendable {
    private let reader: OnbiiBundleReader

    public init(reader: OnbiiBundleReader = OnbiiBundleReader()) {
        self.reader = reader
    }

    /// Every readable `.onbii` object across the given directories, newest
    /// first. Duplicate directories are visited once, and an object reached
    /// through two directories is reported once.
    public func objects(in directories: [URL]) -> [OnbiiBundle] {
        var seenDirectories: Set<String> = []
        var seenObjects: Set<String> = []
        var bundles: [OnbiiBundle] = []

        for directory in directories {
            let key = directory.standardizedFileURL.path
            guard seenDirectories.insert(key).inserted else { continue }

            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in contents where url.pathExtension.lowercased() == "onbii" {
                guard let bundle = try? reader.read(at: url) else { continue }
                guard seenObjects.insert(bundle.manifest.objectID.rawValue).inserted
                else { continue }
                bundles.append(bundle)
            }
        }

        return bundles.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }
}
