import Foundation
@testable import OnbiiTranscription
import Testing

@Test
func timelineMergesTrackOffsetsChronologically() {
    let system = track(
        role: "system-audio",
        words: [("remote", 0.2)]
    )
    let microphone = track(
        role: "microphone",
        words: [("local", 0)]
    )

    let timeline = OnbiiTranscriptTimeline.merge(
        [
            (system, offset: 0),
            (microphone, offset: 0.5),
        ]
    )

    #expect(timeline.map(\.text) == ["remote", "local"])
    #expect(timeline.map(\.startSeconds) == [0.2, 0.5])
}

@Test
func timelineSuppressesOnlyLongLikelyEchoRuns() {
    let system = track(
        role: "system-audio",
        words: [
            ("please", 1.0),
            ("review", 1.3),
            ("this", 1.6),
            ("today", 1.9),
        ]
    )
    let microphone = track(
        role: "microphone",
        words: [
            ("local", 0.2),
            ("please", 1.1),
            ("review", 1.4),
            ("this", 1.7),
            ("today", 2.0),
            ("yes", 3.0),
        ]
    )

    let timeline = OnbiiTranscriptTimeline.merge(
        [
            (system, offset: 0),
            (microphone, offset: 0),
        ]
    )

    #expect(
        timeline.filter { $0.sourceRole == "microphone" }.map(\.text)
            == ["local", "yes"]
    )
    #expect(
        timeline.filter { $0.sourceRole == "system-audio" }.map(\.text)
            == ["please", "review", "this", "today"]
    )
}

@Test
func markdownGroupsNearbyWordsBySpeaker() {
    let document = OnbiiTranscriptDocument(
        generatedAt: Date(timeIntervalSince1970: 0),
        tracks: [],
        timeline: [
            segment("Hello", at: 1, role: "system-audio"),
            segment("there.", at: 1.4, role: "system-audio"),
            segment("Hi", at: 2, role: "microphone"),
        ]
    )

    let markdown = OnbiiTranscriptMarkdown.render(document, title: "Call")

    #expect(markdown.contains("**00:01 System audio:** Hello there."))
    #expect(markdown.contains("**00:02 Microphone:** Hi"))
    #expect(markdown.contains("Source recordings remain unchanged."))
}

private func track(
    role: String,
    words: [(text: String, time: TimeInterval)]
) -> OnbiiTrackTranscript {
    OnbiiTrackTranscript(
        sourceResourceID: "source-\(role)",
        sourceRole: role,
        localeIdentifier: "en-US",
        formattedText: words.map(\.text).joined(separator: " "),
        segments: words.map {
            OnbiiTranscriptSegment(
                text: $0.text,
                startSeconds: $0.time,
                durationSeconds: 0.2,
                confidence: 0.9,
                sourceRole: role
            )
        }
    )
}

private func segment(
    _ text: String,
    at time: TimeInterval,
    role: String
) -> OnbiiTranscriptSegment {
    OnbiiTranscriptSegment(
        text: text,
        startSeconds: time,
        durationSeconds: 0.2,
        confidence: 0.9,
        sourceRole: role
    )
}
