import Foundation

/// Where a recording was captured. Coordinates are the source of truth; `name`
/// is a best-effort reverse-geocoded label and may be absent (e.g. offline).
public struct OnbiiLocation: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracyMeters: Double?
    /// A human-readable place name, reverse-geocoded best-effort. Never required.
    public var name: String?
    public var capturedAt: Date?

    public init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double? = nil,
        name: String? = nil,
        capturedAt: Date? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.name = name
        self.capturedAt = capturedAt
    }

    /// The place name, or `nil` when there is not one to show.
    ///
    /// For a best-effort field, **absent and empty are the same thing**. A
    /// geocoder can succeed and hand back an empty label — a park a few hundred
    /// metres from a named city does exactly that — and every reader that
    /// checked only for `nil` then rendered a blank row. Objects already written
    /// carry `"name": ""`, so tolerating it on read is not optional.
    ///
    /// This is the single definition. Readers use it instead of `name`.
    public var resolvedName: String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// An application whose audio was present in a system-audio capture. For a
/// recorded Teams or Zoom call this is often more meaningful context than the
/// physical location. Identified from the audio-producing processes at capture
/// time, not from per-application audio isolation (which Milestone 1 does not do
/// — the system tap records the global output mix).
public struct OnbiiSourceApplication: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var name: String?

    public init(bundleIdentifier: String, name: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}
