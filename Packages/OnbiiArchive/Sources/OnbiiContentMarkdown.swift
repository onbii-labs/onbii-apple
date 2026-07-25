import Foundation

/// Renders the object's readable `content.md` — its front-page content view:
/// metadata plus a transcript section. Shared by `OnbiiBundleWriter` (the
/// initial "transcription pending" state) and the transcription flow (the actual
/// transcript), so the two can never drift. The transcript body is passed in
/// already rendered, keeping this independent of the transcription module.
public enum OnbiiContentMarkdown {
    public struct Source: Sendable, Equatable {
        public var storedPath: String
        public var originalFilename: String?

        public init(storedPath: String, originalFilename: String? = nil) {
            self.storedPath = storedPath
            self.originalFilename = originalFilename
        }
    }

    /// - Parameters:
    ///   - transcript: the rendered transcript body, or nil for the pending
    ///     placeholder shown before a recording has been transcribed.
    ///   - speakerCount: rough number of distinct speakers, shown when diarized.
    public static func render(
        title: String,
        createdAt: Date,
        sources: [Source],
        transcript: String? = nil,
        speakerCount: Int? = nil
    ) -> String {
        let safeTitle = title
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        let date = createdAt.formatted(.iso8601)
        let sourceLines = sources.map { source in
            if let original = source.originalFilename {
                "- Source: `\(source.storedPath)` (original: `\(original)`)"
            } else {
                "- Source: `\(source.storedPath)`"
            }
        }.joined(separator: "\n")

        var metadata = """
        # \(safeTitle)

        - Created: \(date)
        \(sourceLines)
        """
        if let speakerCount, speakerCount > 0 {
            metadata += "\n- Speakers: \(speakerCount) (rough)"
        }

        return """
        \(metadata)

        ## Transcript

        \(transcript ?? "_Transcription pending._")
        """
        + "\n"
    }
}
