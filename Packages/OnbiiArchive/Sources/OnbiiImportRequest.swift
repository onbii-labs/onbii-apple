import Foundation
import OnbiiCore

/// The normalized input handed from a source adapter to the archive writer.
public struct OnbiiImportRequest: Sendable {
    public var sourceAudioURL: URL
    public var destinationBundleURL: URL
    public var objectID: OnbiiObjectID
    public var objectType: String
    public var title: String
    public var createdAt: Date
    public var mediaType: String
    public var sourceAgentName: String

    public init(
        sourceAudioURL: URL,
        destinationBundleURL: URL,
        objectID: OnbiiObjectID = .generated(),
        objectType: String = "recorded-conversation",
        title: String,
        createdAt: Date = Date(),
        mediaType: String = "application/octet-stream",
        sourceAgentName: String = "macOS file import"
    ) {
        self.sourceAudioURL = sourceAudioURL
        self.destinationBundleURL = destinationBundleURL
        self.objectID = objectID
        self.objectType = objectType
        self.title = title
        self.createdAt = createdAt
        self.mediaType = mediaType
        self.sourceAgentName = sourceAgentName
    }
}
