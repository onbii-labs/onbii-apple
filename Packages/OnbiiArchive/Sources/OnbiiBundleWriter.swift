import Foundation
import OnbiiCore

public enum OnbiiBundleWriterError: Error, Equatable, Sendable {
    case sourceIsNotARegularFile(String)
    case noSources
    case invalidStoredFilename(String)
    case duplicateStoredFilename(String)
    case destinationIsNotOnbiiBundle(String)
    case destinationAlreadyExists(String)
}

extension OnbiiBundleWriterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .sourceIsNotARegularFile(path):
            "The import source is not a regular file: \(path)"
        case .noSources:
            "At least one source file is required."
        case let .invalidStoredFilename(filename):
            "The stored source filename is invalid: \(filename)"
        case let .duplicateStoredFilename(filename):
            "The stored source filename occurs more than once: \(filename)"
        case let .destinationIsNotOnbiiBundle(path):
            "The bundle destination must use the .onbii extension: \(path)"
        case let .destinationAlreadyExists(path):
            "A file already exists at the bundle destination: \(path)"
        }
    }
}

/// What the writer produced, and anything it noticed while producing it.
public struct OnbiiBundleWriteResult: Sendable {
    public var manifest: OnbiiManifest
    /// Sources whose capture-reported duration disagreed with the file that was
    /// preserved. A recording that died without the app noticing surfaces here.
    public var durationMismatches: [OnbiiSourceDurationMismatch]

    public init(
        manifest: OnbiiManifest,
        durationMismatches: [OnbiiSourceDurationMismatch] = []
    ) {
        self.manifest = manifest
        self.durationMismatches = durationMismatches
    }
}

/// Writes the Milestone 1 draft directory representation of an Onbii object.
///
/// The bundle is assembled beside its destination and moved into place only
/// after all files and the validated manifest have been written.
public struct OnbiiBundleWriter: Sendable {
    public init() {}

    /// Writes the bundle and returns its manifest.
    ///
    /// Kept for callers that only need the manifest. Prefer ``preserve(_:)``
    /// where the caller can act on what the writer noticed.
    @discardableResult
    public func write(_ request: OnbiiImportRequest) throws -> OnbiiManifest {
        try preserve(request).manifest
    }

    @discardableResult
    public func preserve(_ request: OnbiiImportRequest) throws -> OnbiiBundleWriteResult {
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

        var sourceResources = [OnbiiResource]()
        var durationMismatches = [OnbiiSourceDurationMismatch]()
        for source in request.sources {
            let storedSourceURL = sourceDirectory.appendingPathComponent(
                source.storedFilename
            )
            try fileManager.copyItem(at: source.sourceURL, to: storedSourceURL)

            let attributes = try fileManager.attributesOfItem(
                atPath: storedSourceURL.path
            )

            // Prefer the file over the capture side's word for it. The measured
            // value is the only one the writer can verify, and trusting the
            // claim once put `durationSeconds: 0` on a twenty-minute recording.
            // Measurement is best-effort: an unreadable file still gets
            // preserved, keeping whatever the caller reported.
            var durationSeconds = source.durationSeconds
            if OnbiiSourceDuration.isMeasurable(mediaType: source.mediaType),
               let measured = OnbiiSourceDuration.seconds(of: storedSourceURL) {
                if OnbiiSourceDuration.disagrees(
                    reported: source.durationSeconds,
                    measured: measured
                ), let reported = source.durationSeconds {
                    durationMismatches.append(
                        OnbiiSourceDurationMismatch(
                            resourceID: source.resourceID,
                            reportedSeconds: reported,
                            measuredSeconds: measured
                        )
                    )
                }
                durationSeconds = measured
            }

            sourceResources.append(
                OnbiiResource(
                    id: source.resourceID,
                    role: .source,
                    path: "source/\(source.storedFilename)",
                    mediaType: source.mediaType,
                    byteCount: (attributes[.size] as? NSNumber)?.int64Value,
                    originalFilename: source.sourceURL.lastPathComponent,
                    captureStartedAt: source.captureStartedAt,
                    durationSeconds: durationSeconds
                )
            )
        }

        let contentURL = stagingURL.appendingPathComponent("content.md")
        let content = Self.initialMarkdown(for: request)
        try Data(content.utf8).write(to: contentURL, options: .atomic)

        let contentByteCount = Int64(Data(content.utf8).count)

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
            resources: sourceResources + [contentResource],
            provenance: [
                OnbiiProvenanceEvent(
                    action: request.sourceAction,
                    occurredAt: request.createdAt,
                    agent: .init(kind: "source-adapter", name: request.sourceAgentName),
                    outputResourceIDs: sourceResources.map(\.id)
                ),
                OnbiiProvenanceEvent(
                    action: "rendered",
                    occurredAt: request.createdAt,
                    agent: writerAgent,
                    inputResourceIDs: sourceResources.map(\.id),
                    outputResourceIDs: [contentResource.id]
                ),
            ],
            location: request.location,
            sourceApplications: request.sourceApplications
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
        return OnbiiBundleWriteResult(
            manifest: manifest,
            durationMismatches: durationMismatches
        )
    }

    private func validateRequest(
        _ request: OnbiiImportRequest,
        fileManager: FileManager
    ) throws {
        guard !request.sources.isEmpty else {
            throw OnbiiBundleWriterError.noSources
        }

        var storedFilenames = Set<String>()
        for source in request.sources {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: source.sourceURL.path,
                isDirectory: &isDirectory
            ), !isDirectory.boolValue else {
                throw OnbiiBundleWriterError.sourceIsNotARegularFile(
                    source.sourceURL.path
                )
            }
            let sourceAttributes = try fileManager.attributesOfItem(
                atPath: source.sourceURL.path
            )
            guard sourceAttributes[.type] as? FileAttributeType == .typeRegular else {
                throw OnbiiBundleWriterError.sourceIsNotARegularFile(
                    source.sourceURL.path
                )
            }

            guard !source.storedFilename.isEmpty,
                  source.storedFilename == (source.storedFilename as NSString)
                    .lastPathComponent,
                  source.storedFilename != ".",
                  source.storedFilename != ".." else {
                throw OnbiiBundleWriterError.invalidStoredFilename(
                    source.storedFilename
                )
            }
            guard storedFilenames.insert(source.storedFilename).inserted else {
                throw OnbiiBundleWriterError.duplicateStoredFilename(
                    source.storedFilename
                )
            }
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

    private static func initialMarkdown(for request: OnbiiImportRequest) -> String {
        OnbiiContentMarkdown.render(
            title: request.title,
            createdAt: request.createdAt,
            sources: request.sources.map {
                OnbiiContentMarkdown.Source(
                    storedPath: "source/\($0.storedFilename)",
                    originalFilename: $0.sourceURL.lastPathComponent
                )
            },
            location: request.location,
            sourceApplications: request.sourceApplications
        )
    }
}
