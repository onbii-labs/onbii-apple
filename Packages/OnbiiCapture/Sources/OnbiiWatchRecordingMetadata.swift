import Foundation

/// Property-list metadata accompanying a Watch Connectivity audio transfer.
public struct OnbiiWatchRecordingMetadata: Equatable, Sendable {
    private enum Key {
        static let schemaVersion = "schemaVersion"
        static let captureStartedAt = "captureStartedAt"
        static let durationSeconds = "durationSeconds"
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let horizontalAccuracyMeters = "horizontalAccuracyMeters"
    }

    public static let currentSchemaVersion = 1

    public var captureStartedAt: Date
    public var durationSeconds: Double
    /// Where the Watch was at record time, when available and permitted. The
    /// iPhone reverse-geocodes these coordinates when it builds the object.
    public var latitude: Double?
    public var longitude: Double?
    public var horizontalAccuracyMeters: Double?

    public init(
        captureStartedAt: Date,
        durationSeconds: Double,
        latitude: Double? = nil,
        longitude: Double? = nil,
        horizontalAccuracyMeters: Double? = nil
    ) {
        self.captureStartedAt = captureStartedAt
        self.durationSeconds = durationSeconds
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
    }

    public init?(propertyList: [String: Any]) {
        guard propertyList[Key.schemaVersion] as? Int
                == Self.currentSchemaVersion,
              let captureStartedAt = propertyList[Key.captureStartedAt] as? Date,
              let durationSeconds = propertyList[Key.durationSeconds] as? Double
        else {
            return nil
        }
        self.captureStartedAt = captureStartedAt
        self.durationSeconds = durationSeconds
        self.latitude = propertyList[Key.latitude] as? Double
        self.longitude = propertyList[Key.longitude] as? Double
        self.horizontalAccuracyMeters =
            propertyList[Key.horizontalAccuracyMeters] as? Double
    }

    public var propertyList: [String: Any] {
        var list: [String: Any] = [
            Key.schemaVersion: Self.currentSchemaVersion,
            Key.captureStartedAt: captureStartedAt,
            Key.durationSeconds: durationSeconds,
        ]
        if let latitude { list[Key.latitude] = latitude }
        if let longitude { list[Key.longitude] = longitude }
        if let horizontalAccuracyMeters {
            list[Key.horizontalAccuracyMeters] = horizontalAccuracyMeters
        }
        return list
    }
}
