import Foundation
import OnbiiCore

/// Replacing a derived result with a newer one, keeping the older.
///
/// Spec decision `0032`: reprocessing **supersedes**. It neither overwrites nor
/// forks. The newest result becomes current — what `content.md`, previews and
/// applications present — and earlier results are retained with their own
/// provenance, so what changed between generations stays visible rather than
/// being asserted.
///
/// ## Why the current generation keeps its path
///
/// The incoming artifact takes the **stable path and resource ID**
/// (`derived/transcript.json`, `transcript.md`, …) and the outgoing one is moved
/// aside. That way Finder, Quick Look, Obsidian, a future CLI and both apps go
/// on finding the current result exactly where they already look, with no
/// change at all — which is what "applications are views" is for. It also
/// satisfies `0032`'s requirement that a reader can tell which generation is
/// current without guessing.
///
/// ## What this does not decide
///
/// The on-disk representation of generations is **open** under
/// [`0025`](../../../docs/spec/docs/decisions/0025-onbii-package-format-open.md),
/// and `0032` deliberately left it there. The layout below is one concrete,
/// reversible choice for the Milestone 1 profile — a mirror of the object's own
/// structure under `superseded/<timestamp>/`, so that opening the package shows
/// plainly what the object used to look like. It is documented in
/// `docs/architecture/milestone-1-bundle-profile.md` and is **not** promoted to
/// the shared specification. In particular there is no generation *number*
/// anywhere: ordering is expressed by provenance timestamps, which the manifest
/// already has.
public struct OnbiiBundleSupersession: Sendable {
    /// The incoming generation. Takes the outgoing one's path and resource ID.
    public var artifact: OnbiiBundleArtifact

    public init(artifact: OnbiiBundleArtifact) {
        self.artifact = artifact
    }
}

public enum OnbiiSupersededGeneration {
    /// The directory one retired generation is moved into.
    public static func directory(at date: Date) -> String {
        "superseded/\(stamp(date))"
    }

    /// Where a resource currently at `path` is retired to.
    public static func path(for path: String, at date: Date) -> String {
        "\(directory(at: date))/\(path)"
    }

    /// The retired resource's new identity.
    ///
    /// Must not collide with the identifiers a current generation uses —
    /// `OnbiiObjectStatus` matches those exactly, and an object holding only
    /// superseded transcripts must not read as transcribed.
    public static func resourceID(for resourceID: String, at date: Date) -> String {
        "superseded-\(stamp(date))-\(resourceID)"
    }

    /// A compact, sortable, filename-safe UTC stamp: `20260727T065217Z`.
    static func stamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let day = String(
            format: "%04d%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
        let time = String(
            format: "%02d%02d%02d",
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
        return "\(day)T\(time)Z"
    }
}
