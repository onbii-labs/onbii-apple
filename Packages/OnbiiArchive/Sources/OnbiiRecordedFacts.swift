import Foundation
import OnbiiCore

/// Corrections to what an object records about itself.
///
/// Not derived results — those supersede, under
/// [`0032`](../../../docs/spec/docs/decisions/0032-reprocessing-supersedes-and-retains.md).
/// These are *facts*: how long the preserved recording is, and what the
/// coordinates it carries are called. A manifest is supposed to describe the
/// object truthfully, and the first field test produced two that do not — a
/// twenty-minute source filed as zero seconds, and good coordinates with an
/// empty place name.
///
/// Deliberately a closed, typed set rather than a general "edit the manifest"
/// hook. The archive's job is to protect the object's invariants, and a
/// general-purpose mutation would hand that away.
public struct OnbiiRecordedFactCorrections: Sendable, Equatable {
    /// Measured durations, by source resource ID. The file is the evidence.
    public var sourceDurations: [String: Double]
    /// A place name for coordinates the object already carries.
    ///
    /// Only ever fills a gap. A name that is already there may have been typed
    /// by a person, and reprocessing must never displace a human edit
    /// ([`0010`](../../../docs/spec/docs/decisions/0010-human-edits-are-protected.md)).
    public var locationName: String?

    public init(
        sourceDurations: [String: Double] = [:],
        locationName: String? = nil
    ) {
        self.sourceDurations = sourceDurations
        self.locationName = locationName
    }

    public var isEmpty: Bool {
        sourceDurations.isEmpty && locationName == nil
    }

    /// Applies the corrections, refusing anything that would displace something
    /// already recorded that a person could have put there.
    public func apply(to manifest: inout OnbiiManifest) {
        for (resourceID, seconds) in sourceDurations {
            guard let index = manifest.resources.firstIndex(
                where: { $0.id == resourceID }
            ) else { continue }
            manifest.resources[index].durationSeconds = seconds
        }
        if let locationName,
           manifest.location != nil,
           manifest.location?.resolvedName == nil {
            manifest.location?.name = locationName
        }
    }
}
