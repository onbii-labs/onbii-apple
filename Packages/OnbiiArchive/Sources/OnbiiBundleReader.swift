import Foundation
import OnbiiCore

public struct OnbiiBundle: Equatable, Sendable {
    public let url: URL
    public let manifest: OnbiiManifest

    public init(url: URL, manifest: OnbiiManifest) {
        self.url = url
        self.manifest = manifest
    }

    public func url(for resource: OnbiiResource) -> URL {
        url.appendingPathComponent(resource.path)
    }
}

public enum OnbiiBundleReaderError: Error, Equatable, Sendable {
    case notOnbiiBundle(String)
    case bundleDoesNotExist(String)
    case bundleIsNotDirectory(String)
    case manifestIsMissing
    case manifestCannotBeDecoded
    case declaredResourceIsMissing(id: String, path: String)
}

extension OnbiiBundleReaderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .notOnbiiBundle(path):
            "The selected item is not an .onbii bundle: \(path)"
        case let .bundleDoesNotExist(path):
            "The Onbii bundle does not exist: \(path)"
        case let .bundleIsNotDirectory(path):
            "This draft Onbii bundle must be a directory package: \(path)"
        case .manifestIsMissing:
            "The Onbii bundle does not contain manifest.json."
        case .manifestCannotBeDecoded:
            "The Onbii manifest is not valid draft manifest JSON."
        case let .declaredResourceIsMissing(id, path):
            "The resource '\(id)' is declared but missing at '\(path)'."
        }
    }
}

public struct OnbiiBundleReader: Sendable {
    public init() {}

    public func read(at bundleURL: URL) throws -> OnbiiBundle {
        let fileManager = FileManager.default

        guard bundleURL.pathExtension.lowercased() == "onbii" else {
            throw OnbiiBundleReaderError.notOnbiiBundle(bundleURL.path)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: bundleURL.path,
            isDirectory: &isDirectory
        ) else {
            throw OnbiiBundleReaderError.bundleDoesNotExist(bundleURL.path)
        }
        guard isDirectory.boolValue else {
            throw OnbiiBundleReaderError.bundleIsNotDirectory(bundleURL.path)
        }

        let manifestURL = bundleURL.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw OnbiiBundleReaderError.manifestIsMissing
        }

        let manifest: OnbiiManifest
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try decoder.decode(
                OnbiiManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw OnbiiBundleReaderError.manifestCannotBeDecoded
        }

        try manifest.validate()

        for resource in manifest.resources {
            let resourceURL = bundleURL.appendingPathComponent(resource.path)
            guard fileManager.fileExists(atPath: resourceURL.path) else {
                throw OnbiiBundleReaderError.declaredResourceIsMissing(
                    id: resource.id,
                    path: resource.path
                )
            }
        }

        return OnbiiBundle(url: bundleURL, manifest: manifest)
    }
}
