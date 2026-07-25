import Foundation
@testable import OnbiiArchive
import Testing

@Test
func contentMarkdownShowsPendingWithoutTranscript() {
    let markdown = OnbiiContentMarkdown.render(
        title: "Conversation",
        createdAt: Date(timeIntervalSince1970: 0),
        sources: [
            .init(storedPath: "source/recording.m4a", originalFilename: "memo.m4a"),
        ]
    )
    #expect(markdown.contains("# Conversation"))
    #expect(
        markdown.contains("- Source: `source/recording.m4a` (original: `memo.m4a`)")
    )
    #expect(markdown.contains("## Transcript"))
    #expect(markdown.contains("_Transcription pending._"))
    #expect(!markdown.contains("Speakers:"))
}

@Test
func contentMarkdownReflectsTranscriptAndSpeakerCount() {
    let markdown = OnbiiContentMarkdown.render(
        title: "Conversation",
        createdAt: Date(timeIntervalSince1970: 0),
        sources: [.init(storedPath: "source/recording.m4a")],
        transcript: "**00:00 Speaker 1:** Hello",
        speakerCount: 2
    )
    #expect(markdown.contains("- Speakers: 2 (rough)"))
    #expect(markdown.contains("**00:00 Speaker 1:** Hello"))
    #expect(!markdown.contains("_Transcription pending._"))
    // No original filename provided → no "(original: …)" suffix.
    #expect(markdown.contains("- Source: `source/recording.m4a`"))
    #expect(!markdown.contains("(original:"))
}
