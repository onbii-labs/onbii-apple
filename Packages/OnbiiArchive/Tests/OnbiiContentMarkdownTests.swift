import Foundation
import OnbiiCore
@testable import OnbiiArchive
import Testing

@Test
func contentMarkdownShowsCaptureContext() {
    let markdown = OnbiiContentMarkdown.render(
        title: "Standup",
        createdAt: Date(timeIntervalSince1970: 0),
        sources: [.init(storedPath: "source/system-audio.caf")],
        location: OnbiiLocation(
            latitude: 52.3702, longitude: 4.8952, name: "Amsterdam, Netherlands"
        ),
        sourceApplications: [
            OnbiiSourceApplication(
                bundleIdentifier: "com.microsoft.teams2", name: "Microsoft Teams"
            ),
        ]
    )
    #expect(markdown.contains("- Source app: Microsoft Teams"))
    #expect(markdown.contains("- Location: Amsterdam, Netherlands (52.3702, 4.8952)"))
}

@Test
func contentMarkdownLocationFallsBackToCoordinates() {
    let markdown = OnbiiContentMarkdown.render(
        title: "Memo",
        createdAt: Date(timeIntervalSince1970: 0),
        sources: [.init(storedPath: "source/recording.m4a")],
        location: OnbiiLocation(latitude: 52.3702, longitude: 4.8952)
    )
    #expect(markdown.contains("- Location: 52.3702, 4.8952"))
    #expect(!markdown.contains("Source app"))
}

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
