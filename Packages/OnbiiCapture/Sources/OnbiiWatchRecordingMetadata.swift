import Foundation

/// Property-list metadata accompanying a Watch Connectivity audio transfer.
public struct OnbiiWatchRecordingMetadata: Equatable, Sendable {
    private enum Key {
        static let schemaVersion = "schemaVersion"
        static let captureStartedAt = "captureStartedAt"
        static let durationSeconds = "durationSeconds"
    }

    public static let currentSchemaVersion = 1

    public var captureStartedAt: Date
    public var durationSeconds: Double

    public init(
        captureStartedAt: Date,
        durationSeconds: Double
    ) {
        self.captureStartedAt = captureStartedAt
        self.durationSeconds = durationSeconds
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
    }

    public var propertyList: [String: Any] {
        [
            Key.schemaVersion: Self.currentSchemaVersion,
            Key.captureStartedAt: captureStartedAt,
            Key.durationSeconds: durationSeconds,
        ]
    }
}
