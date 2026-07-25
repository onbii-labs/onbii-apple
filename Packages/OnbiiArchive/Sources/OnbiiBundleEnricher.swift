import Foundation
import OnbiiCore

public struct OnbiiBundleArtifact: Sendable {
    public var sourceURL: URL
    public var resourceID: String
    public var role: OnbiiResource.Role
    public var path: String
    public var mediaType: String

    public init(
        sourceURL: URL,
        resourceID: String,
        role: OnbiiResource.Role,
        path: String,
        mediaType: String
    ) {
        self.sourceURL = sourceURL
        self.resourceID = resourceID
        self.role = role
        self.path = path
        self.mediaType = mediaType
    }
}

public struct OnbiiBundleEnrichmentRequest: Sendable {
    public var bundleURL: URL
    public var artifacts: [OnbiiBundleArtifact]
    /// Artifacts that overwrite an existing resource in place (matched by ID at
    /// the same path), e.g. rewriting `content.md` to reflect a new transcript.
    /// Unlike `artifacts`, each must already exist in the bundle.
    public var replacements: [OnbiiBundleArtifact]
    public var action: String
    public var occurredAt: Date
    public var agent: OnbiiProvenanceEvent.Agent
    public var inputResourceIDs: [String]

    public init(
        bundleURL: URL,
        artifacts: [OnbiiBundleArtifact],
        replacements: [OnbiiBundleArtifact] = [],
        action: String,
        occurredAt: Date = Date(),
        agent: OnbiiProvenanceEvent.Agent,
        inputResourceIDs: [String]
    ) {
        self.bundleURL = bundleURL
        self.artifacts = artifacts
        self.replacements = replacements
        self.action = action
        self.occurredAt = occurredAt
        self.agent = agent
        self.inputResourceIDs = inputResourceIDs
    }
}

public enum OnbiiBundleEnricherError: Error, Equatable, Sendable {
    case noArtifacts
    case artifactIsNotARegularFile(String)
    case duplicateResourceID(String)
    case duplicateResourcePath(String)
    case unknownReplacementResource(String)
    case replacementPathMismatch(String)
    case replacementFailed(String)
}

extension OnbiiBundleEnricherError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noArtifacts:
            "At least one derived artifact is required."
        case .artifactIsNotARegularFile(let path):
            "The derived artifact is not a regular file: \(path)"
        case .duplicateResourceID(let id):
            "The resource ID already exists in the bundle: \(id)"
        case .duplicateResourcePath(let path):
            "The resource path already exists in the bundle: \(path)"
        case .unknownReplacementResource(let id):
            "The resource to replace does not exist in the bundle: \(id)"
        case .replacementPathMismatch(let id):
            "The replacement path does not match the existing resource: \(id)"
        case .replacementFailed(let path):
            "The validated bundle update could not replace the bundle at \(path)."
        }
    }
}

/// Adds derived artifacts through a validated, whole-package replacement.
///
/// Existing resources are copied unchanged into a sibling staging package.
/// The original package is replaced only after the staged package can be read
/// and validated as a complete Onbii bundle.
public struct OnbiiBundleEnricher: Sendable {
    public init() {}

    @discardableResult
    public func enrich(_ request: OnbiiBundleEnrichmentRequest) throws -> OnbiiBundle {
        let fileManager = FileManager.default
        let original = try OnbiiBundleReader().read(at: request.bundleURL)
        try validate(request, against: original.manifest, fileManager: fileManager)

        let parentURL = request.bundleURL.deletingLastPathComponent()
        let stagingURL = parentURL.appendingPathComponent(
            ".onbii-enriching-\(UUID().uuidString).onbii",
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }

        try fileManager.copyItem(at: request.bundleURL, to: stagingURL)

        var manifest = original.manifest
        for artifact in request.artifacts {
            let destinationURL = stagingURL.appendingPathComponent(artifact.path)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: artifact.sourceURL, to: destinationURL)
            let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            manifest.resources.append(
                OnbiiResource(
                    id: artifact.resourceID,
                    role: artifact.role,
                    path: artifact.path,
                    mediaType: artifact.mediaType,
                    byteCount: (attributes[.size] as? NSNumber)?.int64Value
                )
            )
        }

        for replacement in request.replacements {
            let destinationURL = stagingURL.appendingPathComponent(replacement.path)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: replacement.sourceURL, to: destinationURL)
            let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            guard let index = manifest.resources.firstIndex(
                where: { $0.id == replacement.resourceID }
            ) else {
                throw OnbiiBundleEnricherError.unknownReplacementResource(
                    replacement.resourceID
                )
            }
            manifest.resources[index].role = replacement.role
            manifest.resources[index].mediaType = replacement.mediaType
            manifest.resources[index].byteCount =
                (attributes[.size] as? NSNumber)?.int64Value
        }

        manifest.provenance.append(
            OnbiiProvenanceEvent(
                action: request.action,
                occurredAt: request.occurredAt,
                agent: request.agent,
                inputResourceIDs: request.inputResourceIDs,
                outputResourceIDs: request.artifacts.map(\.resourceID)
                    + request.replacements.map(\.resourceID)
            )
        )
        try manifest.validate()
        try Self.write(manifest, to: stagingURL)
        _ = try OnbiiBundleReader().read(at: stagingURL)

        do {
            _ = try fileManager.replaceItemAt(
                request.bundleURL,
                withItemAt: stagingURL,
                backupItemName: nil,
                options: []
            )
        } catch {
            throw OnbiiBundleEnricherError.replacementFailed(request.bundleURL.path)
        }

        return try OnbiiBundleReader().read(at: request.bundleURL)
    }

    private func validate(
        _ request: OnbiiBundleEnrichmentRequest,
        against manifest: OnbiiManifest,
        fileManager: FileManager
    ) throws {
        guard !(request.artifacts.isEmpty && request.replacements.isEmpty) else {
            throw OnbiiBundleEnricherError.noArtifacts
        }

        var resourceIDs = Set(manifest.resources.map(\.id))
        var resourcePaths = Set(manifest.resources.map(\.path))
        for artifact in request.artifacts {
            try Self.assertRegularFile(artifact.sourceURL, fileManager: fileManager)
            guard resourceIDs.insert(artifact.resourceID).inserted else {
                throw OnbiiBundleEnricherError.duplicateResourceID(artifact.resourceID)
            }
            guard resourcePaths.insert(artifact.path).inserted else {
                throw OnbiiBundleEnricherError.duplicateResourcePath(artifact.path)
            }
        }

        for replacement in request.replacements {
            try Self.assertRegularFile(replacement.sourceURL, fileManager: fileManager)
            guard let existing = manifest.resources.first(
                where: { $0.id == replacement.resourceID }
            ) else {
                throw OnbiiBundleEnricherError.unknownReplacementResource(
                    replacement.resourceID
                )
            }
            guard existing.path == replacement.path else {
                throw OnbiiBundleEnricherError.replacementPathMismatch(
                    replacement.resourceID
                )
            }
        }

        var candidate = manifest
        candidate.resources.append(
            contentsOf: request.artifacts.map {
                OnbiiResource(
                    id: $0.resourceID,
                    role: $0.role,
                    path: $0.path,
                    mediaType: $0.mediaType
                )
            }
        )
        try candidate.validate()
    }

    private static func assertRegularFile(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              (try fileManager.attributesOfItem(atPath: url.path)[.type]
                as? FileAttributeType) == .typeRegular else {
            throw OnbiiBundleEnricherError.artifactIsNotARegularFile(url.path)
        }
    }

    private static func write(_ manifest: OnbiiManifest, to bundleURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(
            to: bundleURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }
}
