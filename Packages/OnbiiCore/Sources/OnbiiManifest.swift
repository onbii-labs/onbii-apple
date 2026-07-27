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

/// The inputs that decided what a derived result says.
///
/// Required by spec decision `0033`: a derived result records the configuration
/// that determined it, in the object's provenance — not only inside the derived
/// artifact's own format. Field test 1 produced the case. A recording was
/// transcribed as Australian English because that was the phone's system
/// language; the conversation was Dutch. The locale was written only into
/// `derived/transcript.json`, so reading the object could not distinguish
/// "transcribed badly" from "transcribed under the wrong assumption" — and only
/// the second was true.
///
/// Deliberately generic. `0033` constrains the *record*, never the technique:
/// how a language is arrived at differs by platform and will keep changing, so
/// implementation detail goes in ``parameters`` rather than growing fields here.
public struct OnbiiDerivationConfiguration: Codable, Equatable, Sendable {
    /// How the language was arrived at. Automatic detection is not required by
    /// `0033`; an implementation that only ever asks a person is conformant, and
    /// records that it asked.
    public enum LanguageSelection: String, Codable, Sendable {
        case chosen
        case detected
    }

    /// BCP-47 tags. More than one must be expressible for a single result:
    /// a conversation that runs Dutch and English together is the ordinary case.
    public var languages: [String]?
    public var languageSelection: LanguageSelection?
    /// Implementation-specific detail. An implementation-specific derived
    /// document may hold more; it may not be the only place the deciding inputs
    /// appear.
    public var parameters: [String: String]?

    public init(
        languages: [String]? = nil,
        languageSelection: LanguageSelection? = nil,
        parameters: [String: String]? = nil
    ) {
        self.languages = languages
        self.languageSelection = languageSelection
        self.parameters = parameters
    }
}

public struct OnbiiProvenanceEvent: Codable, Equatable, Sendable {
    public struct Agent: Codable, Equatable, Sendable {
        public var kind: String
        public var name: String
        /// Enough to tell two generations apart — required by `0033` for the
        /// model or tool that produced a derived result.
        public var version: String?

        public init(kind: String, name: String, version: String? = nil) {
            self.kind = kind
            self.name = name
            self.version = version
        }
    }

    /// Reprocessing supersedes rather than overwriting or forking (`0032`).
    /// A `superseded` event names which result replaced which.
    public static let supersededAction = "superseded"

    public var id: String
    public var action: String
    public var occurredAt: Date
    public var agent: Agent
    public var inputResourceIDs: [String]
    public var outputResourceIDs: [String]
    /// What determined this result, where it was a derivation. Travels with the
    /// event rather than the resource, so a superseded generation keeps the
    /// configuration it was made with instead of inheriting the current one.
    public var configuration: OnbiiDerivationConfiguration?

    public init(
        id: String = UUID().uuidString.lowercased(),
        action: String,
        occurredAt: Date,
        agent: Agent,
        inputResourceIDs: [String] = [],
        outputResourceIDs: [String] = [],
        configuration: OnbiiDerivationConfiguration? = nil
    ) {
        self.id = id
        self.action = action
        self.occurredAt = occurredAt
        self.agent = agent
        self.inputResourceIDs = inputResourceIDs
        self.outputResourceIDs = outputResourceIDs
        self.configuration = configuration
    }
}
