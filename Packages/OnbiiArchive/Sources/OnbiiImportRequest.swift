import Foundation
import OnbiiCore

public struct OnbiiSourceFile: Sendable {
    public var resourceID: String
    public var sourceURL: URL
    public var storedFilename: String
    public var mediaType: String
    public var captureStartedAt: Date?
    public var durationSeconds: Double?

    public init(
        resourceID: String,
        sourceURL: URL,
        storedFilename: String,
        mediaType: String,
        captureStartedAt: Date? = nil,
        durationSeconds: Double? = nil
    ) {
        self.resourceID = resourceID
        self.sourceURL = sourceURL
        self.storedFilename = storedFilename
        self.mediaType = mediaType
        self.captureStartedAt = captureStartedAt
        self.durationSeconds = durationSeconds
    }
}

/// The normalized input handed from a source adapter to the archive writer.
public struct OnbiiImportRequest: Sendable {
    public var sources: [OnbiiSourceFile]
    public var destinationBundleURL: URL
    public var objectID: OnbiiObjectID
    public var objectType: String
    public var title: String
    public var createdAt: Date
    public var sourceAction: String
    public var sourceAgentName: String
    public var location: OnbiiLocation?
    public var sourceApplications: [OnbiiSourceApplication]?

    public init(
        sources: [OnbiiSourceFile],
        destinationBundleURL: URL,
        objectID: OnbiiObjectID = .generated(),
        objectType: String = "recorded-conversation",
        title: String,
        createdAt: Date = Date(),
        sourceAction: String,
        sourceAgentName: String,
        location: OnbiiLocation? = nil,
        sourceApplications: [OnbiiSourceApplication]? = nil
    ) {
        self.sources = sources
        self.destinationBundleURL = destinationBundleURL
        self.objectID = objectID
        self.objectType = objectType
        self.title = title
        self.createdAt = createdAt
        self.sourceAction = sourceAction
        self.sourceAgentName = sourceAgentName
        self.location = location
        self.sourceApplications = sourceApplications
    }

    public init(
        sourceAudioURL: URL,
        destinationBundleURL: URL,
        objectID: OnbiiObjectID = .generated(),
        objectType: String = "recorded-conversation",
        title: String,
        createdAt: Date = Date(),
        mediaType: String = "application/octet-stream",
        sourceAction: String = "imported",
        sourceAgentName: String = "macOS file import",
        location: OnbiiLocation? = nil
    ) {
        let sourceExtension = sourceAudioURL.pathExtension
        let storedFilename = sourceExtension.isEmpty
            ? "recording"
            : "recording.\(sourceExtension)"
        self.init(
            sources: [
                OnbiiSourceFile(
                    resourceID: "source-recording",
                    sourceURL: sourceAudioURL,
                    storedFilename: storedFilename,
                    mediaType: mediaType
                ),
            ],
            destinationBundleURL: destinationBundleURL,
            objectID: objectID,
            objectType: objectType,
            title: title,
            createdAt: createdAt,
            sourceAction: sourceAction,
            sourceAgentName: sourceAgentName,
            location: location
        )
    }
}
