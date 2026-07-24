import Foundation

public enum OnbiiCloudArchiveError: Error, Equatable, Sendable {
    case iCloudUnavailable
}

extension OnbiiCloudArchiveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            "iCloud Drive is unavailable. Check that you are signed in and iCloud Drive is enabled."
        }
    }
}

/// Resolves the shared, app-owned archive in the Onbii iCloud Drive container.
///
/// Call this API away from the main actor. Establishing access to a ubiquity
/// container can block while the system prepares iCloud Drive.
public struct OnbiiCloudArchive: Sendable {
    public static let containerIdentifier = "iCloud.com.yepyr.onbii"
    public static let archiveDirectoryName = "Onbii Archive"

    public init() {}

    public func directoryURL() throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.ubiquityIdentityToken != nil,
              let containerURL = fileManager.url(
                  forUbiquityContainerIdentifier: Self.containerIdentifier
              ) else {
            throw OnbiiCloudArchiveError.iCloudUnavailable
        }

        let archiveURL = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(Self.archiveDirectoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: archiveURL,
            withIntermediateDirectories: true
        )
        return archiveURL
    }
}
