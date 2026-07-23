import Foundation
import OnbiiCore

public enum OnbiiBundleWriterError: Error, Equatable, Sendable {
    case sourceIsNotARegularFile(String)
    case destinationIsNotOnbiiBundle(String)
    case destinationAlreadyExists(String)
}

extension OnbiiBundleWriterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .sourceIsNotARegularFile(path):
            "The import source is not a regular file: \(path)"
        case let .destinationIsNotOnbiiBundle(path):
            "The bundle destination must use the .onbii extension: \(path)"
        case let .destinationAlreadyExists(path):
            "A file already exists at the bundle destination: \(path)"
        }
    }
}

/// Writes the Milestone 1 draft directory representation of an Onbii object.
///
/// The bundle is assembled beside its destination and moved into place only
/// after all files and the validated manifest have been written.
public struct OnbiiBundleWriter: Sendable {
    public init() {}

    @discardableResult
    public func write(_ request: OnbiiImportRequest) throws -> OnbiiManifest {
        let fileManager = FileManager.default
        try validateRequest(request, fileManager: fileManager)

        let parentURL = request.destinationBundleURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parentURL,
            withIntermediateDirectories: true
        )

        let stagingURL = parentURL.appendingPathComponent(
            ".onbii-writing-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }

        let sourceDirectory = stagingURL.appendingPathComponent("source", isDirectory: true)
        try fileManager.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )

        let sourceExtension = request.sourceAudioURL.pathExtension
        let storedFilename = sourceExtension.isEmpty ? "recording" : "recording.\(sourceExtension)"
        let storedSourceURL = sourceDirectory.appendingPathComponent(storedFilename)
        try fileManager.copyItem(at: request.sourceAudioURL, to: storedSourceURL)

        let contentURL = stagingURL.appendingPathComponent("content.md")
        let content = Self.initialMarkdown(for: request, storedSourcePath: "source/\(storedFilename)")
        try Data(content.utf8).write(to: contentURL, options: .atomic)

        let attributes = try fileManager.attributesOfItem(atPath: storedSourceURL.path)
        let sourceByteCount = (attributes[.size] as? NSNumber)?.int64Value
        let contentByteCount = Int64(Data(content.utf8).count)

        let sourceResource = OnbiiResource(
            id: "source-recording",
            role: .source,
            path: "source/\(storedFilename)",
            mediaType: request.mediaType,
            byteCount: sourceByteCount,
            originalFilename: request.sourceAudioURL.lastPathComponent
        )
        let contentResource = OnbiiResource(
            id: "content-markdown",
            role: .humanReadable,
            path: "content.md",
            mediaType: "text/markdown; charset=utf-8",
            byteCount: contentByteCount
        )

        let writerAgent = OnbiiProvenanceEvent.Agent(
            kind: "software",
            name: "OnbiiArchive"
        )
        let manifest = OnbiiManifest(
            objectID: request.objectID,
            objectType: request.objectType,
            title: request.title,
            createdAt: request.createdAt,
            resources: [sourceResource, contentResource],
            provenance: [
                OnbiiProvenanceEvent(
                    action: "imported",
                    occurredAt: request.createdAt,
                    agent: .init(kind: "source-adapter", name: request.sourceAgentName),
                    outputResourceIDs: [sourceResource.id]
                ),
                OnbiiProvenanceEvent(
                    action: "rendered",
                    occurredAt: request.createdAt,
                    agent: writerAgent,
                    inputResourceIDs: [sourceResource.id],
                    outputResourceIDs: [contentResource.id]
                ),
            ]
        )
        try manifest.validate()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(
            to: stagingURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        try fileManager.moveItem(at: stagingURL, to: request.destinationBundleURL)
        return manifest
    }

    private func validateRequest(
        _ request: OnbiiImportRequest,
        fileManager: FileManager
    ) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: request.sourceAudioURL.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            throw OnbiiBundleWriterError.sourceIsNotARegularFile(
                request.sourceAudioURL.path
            )
        }
        let sourceAttributes = try fileManager.attributesOfItem(
            atPath: request.sourceAudioURL.path
        )
        guard sourceAttributes[.type] as? FileAttributeType == .typeRegular else {
            throw OnbiiBundleWriterError.sourceIsNotARegularFile(
                request.sourceAudioURL.path
            )
        }

        guard request.destinationBundleURL.pathExtension.lowercased() == "onbii" else {
            throw OnbiiBundleWriterError.destinationIsNotOnbiiBundle(
                request.destinationBundleURL.path
            )
        }

        guard !fileManager.fileExists(atPath: request.destinationBundleURL.path) else {
            throw OnbiiBundleWriterError.destinationAlreadyExists(
                request.destinationBundleURL.path
            )
        }
    }

    private static func initialMarkdown(
        for request: OnbiiImportRequest,
        storedSourcePath: String
    ) -> String {
        let safeTitle = request.title
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        let date = request.createdAt.formatted(.iso8601)

        return """
        # \(safeTitle)

        - Created: \(date)
        - Source: `\(storedSourcePath)`
        - Original filename: `\(request.sourceAudioURL.lastPathComponent)`

        ## Transcript

        _Transcription pending._
        """
        + "\n"
    }
}
