import Foundation

public enum OnbiiManifestValidationError: Error, Equatable, Sendable {
    case emptyField(String)
    case duplicateResourceID(String)
    case invalidResourcePath(String)
    case duplicateProvenanceEventID(String)
    case unknownProvenanceResource(eventID: String, resourceID: String)
}

extension OnbiiManifestValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .emptyField(field):
            "The required field '\(field)' is empty."
        case let .duplicateResourceID(id):
            "The resource ID '\(id)' occurs more than once."
        case let .invalidResourcePath(path):
            "The resource path '\(path)' is not a safe bundle-relative path."
        case let .duplicateProvenanceEventID(id):
            "The provenance event ID '\(id)' occurs more than once."
        case let .unknownProvenanceResource(eventID, resourceID):
            "The provenance event '\(eventID)' refers to unknown resource '\(resourceID)'."
        }
    }
}

public extension OnbiiManifest {
    func validate() throws {
        try requireNonempty(schemaVersion, field: "schemaVersion")
        try requireNonempty(objectID.rawValue, field: "objectID")
        try requireNonempty(objectType, field: "objectType")
        try requireNonempty(title, field: "title")

        var resourceIDs = Set<String>()
        for resource in resources {
            try requireNonempty(resource.id, field: "resources[].id")
            try requireNonempty(resource.mediaType, field: "resources[].mediaType")

            guard Self.isSafeRelativePath(resource.path) else {
                throw OnbiiManifestValidationError.invalidResourcePath(resource.path)
            }
            guard resourceIDs.insert(resource.id).inserted else {
                throw OnbiiManifestValidationError.duplicateResourceID(resource.id)
            }
        }

        var eventIDs = Set<String>()
        for event in provenance {
            try requireNonempty(event.id, field: "provenance[].id")
            try requireNonempty(event.action, field: "provenance[].action")
            try requireNonempty(event.agent.kind, field: "provenance[].agent.kind")
            try requireNonempty(event.agent.name, field: "provenance[].agent.name")

            guard eventIDs.insert(event.id).inserted else {
                throw OnbiiManifestValidationError.duplicateProvenanceEventID(event.id)
            }

            for resourceID in event.inputResourceIDs + event.outputResourceIDs
            where !resourceIDs.contains(resourceID) {
                throw OnbiiManifestValidationError.unknownProvenanceResource(
                    eventID: event.id,
                    resourceID: resourceID
                )
            }
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else {
            return false
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

private func requireNonempty(_ value: String, field: String) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw OnbiiManifestValidationError.emptyField(field)
    }
}
