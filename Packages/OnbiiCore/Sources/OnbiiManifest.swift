import Foundation

/// The logical description of an Onbii knowledge object.
///
/// This is an implementation profile for the Milestone 1 proving ground, not
/// the final Onbii specification.
public struct OnbiiManifest: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var objectID: OnbiiObjectID
    public var objectType: String
    public var title: String
    public var createdAt: Date
    public var resources: [OnbiiResource]
    public var provenance: [OnbiiProvenanceEvent]
    /// Where the recording was captured, when available and permitted.
    public var location: OnbiiLocation?
    /// Applications whose audio was present in a system-audio capture.
    public var sourceApplications: [OnbiiSourceApplication]?

    public init(
        schemaVersion: String = OnbiiSchema.currentDraftVersion,
        objectID: OnbiiObjectID,
        objectType: String,
        title: String,
        createdAt: Date,
        resources: [OnbiiResource],
        provenance: [OnbiiProvenanceEvent],
        location: OnbiiLocation? = nil,
        sourceApplications: [OnbiiSourceApplication]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.objectID = objectID
        self.objectType = objectType
        self.title = title
        self.createdAt = createdAt
        self.resources = resources
        self.provenance = provenance
        self.location = location
        self.sourceApplications = sourceApplications
    }
}

public enum OnbiiSchema {
    /// A deliberately draft implementation version. It makes no compatibility
    /// promise on behalf of the shared specification.
    public static let currentDraftVersion = "0.1.0-draft"
}

/// An opaque stable identity. The default generator currently uses UUIDs, but
/// callers and readers must not infer semantics from the stored value.
public struct OnbiiObjectID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func generated() -> Self {
        Self(rawValue: UUID().uuidString.lowercased())
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct OnbiiResource: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case source
        case humanReadable = "human-readable"
        case derived
        case attachment
    }

    public var id: String
    public var role: Role
    public var path: String
    public var mediaType: String
    public var byteCount: Int64?
    public var originalFilename: String?
    public var captureStartedAt: Date?
    public var durationSeconds: Double?

    public init(
        id: String,
        role: Role,
        path: String,
        mediaType: String,
        byteCount: Int64? = nil,
        originalFilename: String? = nil,
        captureStartedAt: Date? = nil,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.role = role
        self.path = path
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.originalFilename = originalFilename
        self.captureStartedAt = captureStartedAt
        self.durationSeconds = durationSeconds
    }
}

public struct OnbiiProvenanceEvent: Codable, Equatable, Sendable {
    public struct Agent: Codable, Equatable, Sendable {
        public var kind: String
        public var name: String
        public var version: String?

        public init(kind: String, name: String, version: String? = nil) {
            self.kind = kind
            self.name = name
            self.version = version
        }
    }

    public var id: String
    public var action: String
    public var occurredAt: Date
    public var agent: Agent
    public var inputResourceIDs: [String]
    public var outputResourceIDs: [String]

    public init(
        id: String = UUID().uuidString.lowercased(),
        action: String,
        occurredAt: Date,
        agent: Agent,
        inputResourceIDs: [String] = [],
        outputResourceIDs: [String] = []
    ) {
        self.id = id
        self.action = action
        self.occurredAt = occurredAt
        self.agent = agent
        self.inputResourceIDs = inputResourceIDs
        self.outputResourceIDs = outputResourceIDs
    }
}
