import Foundation
@testable import OnbiiTranscription
import Testing

@Test
func consecutiveSegmentsFromOneSpeakerBecomeOneTurn() {
    let turns = OnbiiTranscriptTurns.turns(in: [
        segment("Hello there.", at: 0, speaker: "S1"),
        segment("How are you?", at: 2, speaker: "S1"),
        segment("Very well.", at: 5, speaker: "S2"),
    ])

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
    let turns = OnbiiTranscriptTurns.turns(in: [
        segment("One.", at: 0, speaker: "S1"),
        segment("Two.", at: 1, speaker: "S2"),
        segment("Three.", at: 2, speaker: "S1"),
    ])

    #expect(turns.map(\.text) == ["One.", "Two.", "Three."])
}

/// Without diarization the capture track groups the turns — and it is labelled
/// as a track, never as a person.
@Test
func undiarizedSegmentsGroupByTrackAndAreLabelledHonestly() {
    let turns = OnbiiTranscriptTurns.turns(in: [
        segment("From the room.", at: 0, speaker: nil, role: "microphone"),
        segment("Still the room.", at: 3, speaker: nil, role: "microphone"),
        segment("From the call.", at: 6, speaker: nil, role: "system-audio"),
    ])

    #expect(turns.count == 2)
    #expect(turns[0].speaker == "Microphone")
    #expect(turns[0].text == "From the room. Still the room.")
    #expect(turns[1].speaker == "System audio")
}

/// Diarization labels are internal strings like `t0s1`. They stay opaque — no
/// names, no meaning outside the object — but they are numbered for reading
/// rather than shown raw.
@Test
func speakerLabelsAreNumberedNotLeaked() {
    let turns = OnbiiTranscriptTurns.turns(in: [
        segment("First.", at: 0, speaker: "t0s2"),
        segment("Second.", at: 1, speaker: "t0s1"),
        segment("Third.", at: 2, speaker: "t0s2"),
    ])

    #expect(turns.map(\.speaker) == ["Speaker 1", "Speaker 2", "Speaker 1"])
    #expect(!turns.contains { $0.speaker.contains("t0s") })
}

@Test
func trackAttributionIsNeverPresentedAsASpeaker() {
    #expect(OnbiiTranscriptTurns.roleLabel("recording") == "Recording")
    #expect(OnbiiTranscriptTurns.roleLabel("microphone") == "Microphone")
    #expect(OnbiiTranscriptTurns.roleLabel("system-audio") == "System audio")
}

@Test
func emptySegmentsAreDropped() {
    let turns = OnbiiTranscriptTurns.turns(in: [
        segment("   ", at: 0, speaker: "S1"),
        segment("Real text.", at: 1, speaker: "S1"),
    ])

    #expect(turns.count == 1)
    #expect(turns[0].text == "Real text.")
}

@Test
func timestampsGrowToHoursOnlyWhenNeeded() {
    #expect(OnbiiTranscriptTurns.timestamp(0) == "00:00")
    #expect(OnbiiTranscriptTurns.timestamp(62) == "01:02")
    #expect(OnbiiTranscriptTurns.timestamp(3_723) == "1:02:03")
}

// MARK: - Unplaced words (field test 1, finding 5)

/// The exact shape the first field test produced: a word the embedder could not
/// place, mid-sentence, rendered under the capture-track label so that it read
/// as a second person and cut the sentence in two.
@Test
func anUnplacedWordJoinsThePrecedingTurnRatherThanBecomingASpeaker() {
    let turns = OnbiiTranscriptTurns.turns(in: [
        segment("Ik heb nu m'n telefoon in het", at: 8, speaker: "t0s1"),
        segment("Nederlands gezet", at: 11, speaker: nil),
    ])

    #expect(turns.count == 1)
    #expect(turns[0].speaker == "Speaker 1")
    #expect(turns[0].text == "Ik heb nu m'n telefoon in het Nederlands gezet")
    #expect(!turns.contains { $0.speaker == "Recording" })
}

/// An unplaced word before anything has been placed has no preceding turn to
/// join, so it joins the one that opens the document.
@Test
func anUnplacedWordAtTheStartJoinsTheFollowingTurn() {
    let turns = OnbiiTranscriptTurns.turns(in: [
        segment("Nu", at: 0, speaker: nil),
        segment("op de telefoon opnemen", at: 2, speaker: "t0s1"),
    ])

    #expect(turns.count == 1)
    #expect(turns[0].speaker == "Speaker 1")
    #expect(turns[0].text == "Nu op de telefoon opnemen")
}

/// Track labels are still the truth for a transcript that was never diarized —
/// the fallback was only dishonest *inside* a diarized document.
@Test
func trackLabelsSurviveWhenNothingWasDiarized() {
    let turns = OnbiiTranscriptTurns.turns(in: [
        segment("One", at: 0, speaker: nil),
        segment("two", at: 1, speaker: nil),
    ])

    #expect(turns.count == 1)
    #expect(turns[0].speaker == "Recording")
}

/// An unplaced word must not silently merge two different speakers' turns.
@Test
func anUnplacedWordBetweenTwoSpeakersJoinsTheEarlierOne() {
    let turns = OnbiiTranscriptTurns.turns(in: [
        segment("Mine.", at: 0, speaker: "S1"),
        segment("unplaced", at: 1, speaker: nil),
        segment("Yours.", at: 2, speaker: "S2"),
    ])

    #expect(turns.map(\.speaker) == ["Speaker 1", "Speaker 2"])
    #expect(turns[0].text == "Mine. unplaced")
    #expect(turns[1].text == "Yours.")
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
