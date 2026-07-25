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
