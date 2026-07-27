import Foundation
import OnbiiTranscription
@testable import OnbiiUI
import Testing

@Test
func consecutiveSegmentsFromOneSpeakerBecomeOneTurn() {
    let document = makeDocument([
        segment("Hello there.", at: 0, speaker: "S1"),
        segment("How are you?", at: 2, speaker: "S1"),
        segment("Very well.", at: 5, speaker: "S2"),
    ])

    let turns = OnbiiTranscriptView.turns(in: document)

    #expect(turns.count == 2)
    #expect(turns[0].text == "Hello there. How are you?")
    #expect(turns[0].startSeconds == 0)
    #expect(turns[1].text == "Very well.")
    #expect(turns[1].startSeconds == 5)
}

/// A speaker returning after someone else has spoken starts a new turn, rather
/// than being merged back into their earlier one.
@Test
func aSpeakerReturningStartsANewTurn() {
    let document = makeDocument([
        segment("One.", at: 0, speaker: "S1"),
        segment("Two.", at: 1, speaker: "S2"),
        segment("Three.", at: 2, speaker: "S1"),
    ])

    let turns = OnbiiTranscriptView.turns(in: document)

    #expect(turns.map(\.text) == ["One.", "Two.", "Three."])
}

/// Without diarization the capture track groups the turns — and it is labelled
/// as a track, never as a person.
@Test
func undiarizedSegmentsGroupByTrackAndAreLabelledHonestly() {
    let document = makeDocument([
        segment("From the room.", at: 0, speaker: nil, role: "microphone"),
        segment("Still the room.", at: 3, speaker: nil, role: "microphone"),
        segment("From the call.", at: 6, speaker: nil, role: "system-audio"),
    ])

    let turns = OnbiiTranscriptView.turns(in: document)

    #expect(turns.count == 2)
    #expect(turns[0].speaker == "Microphone")
    #expect(turns[0].text == "From the room. Still the room.")
    #expect(turns[1].speaker == "System audio")
}

@Test
func speakerLabelsStayOpaque() {
    #expect(
        OnbiiTranscriptView.label(for: segment("x", at: 0, speaker: "S3"))
            == "Speaker S3"
    )
    #expect(
        OnbiiTranscriptView.label(for: segment("x", at: 0, speaker: nil, role: "recording"))
            == "Recording"
    )
}

@Test
func emptySegmentsAreDropped() {
    let document = makeDocument([
        segment("   ", at: 0, speaker: "S1"),
        segment("Real text.", at: 1, speaker: "S1"),
    ])

    let turns = OnbiiTranscriptView.turns(in: document)

    #expect(turns.count == 1)
    #expect(turns[0].text == "Real text.")
}

@Test
func timestampsGrowToHoursOnlyWhenNeeded() {
    #expect(OnbiiTranscriptView.timestamp(0) == "00:00")
    #expect(OnbiiTranscriptView.timestamp(62) == "01:02")
    #expect(OnbiiTranscriptView.timestamp(3_723) == "1:02:03")
}

private func segment(
    _ text: String,
    at start: TimeInterval,
    speaker: String?,
    role: String = "recording"
) -> OnbiiTranscriptSegment {
    OnbiiTranscriptSegment(
        text: text,
        startSeconds: start,
        durationSeconds: 1,
        sourceRole: role,
        speakerID: speaker
    )
}

private func makeDocument(_ timeline: [OnbiiTranscriptSegment]) -> OnbiiTranscriptDocument {
    OnbiiTranscriptDocument(
        generatedAt: Date(timeIntervalSince1970: 0),
        tracks: [],
        timeline: timeline,
        speakerModel: "test-model"
    )
}
