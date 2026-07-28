#if os(macOS) || os(iOS)
import Foundation
import OnbiiCore
@testable import OnbiiProcessing
import OnbiiTranscription
import Testing

/// The run itself needs speech recognition, a real model and real audio, so it
/// is exercised against fixtures on a device rather than here. What is checkable
/// without any of that is the reasoning the run does *around* recognition —
/// which is where field test 1's failures actually were.
@Suite
struct TranscriptionRunTests {
    /// Dual-source call capture keeps its two legs distinguishable so voices
    /// from different capture legs are never merged. Anything else is honestly
    /// just "the recording", never a person.
    @Test
    func trackRolesAreHonestSourceAttribution() {
        #expect(
            OnbiiTranscriptionRun.trackRole(for: "source-system-audio")
                == "system-audio"
        )
        #expect(
            OnbiiTranscriptionRun.trackRole(for: "source-microphone-audio")
                == "microphone"
        )
        #expect(
            OnbiiTranscriptionRun.trackRole(for: "source-recording") == "recording"
        )
    }

    /// `0033` requires the model identity to be enough to tell two generations
    /// apart, and the speaker model is part of what decides a result.
    @Test
    func theModelIdentityIsRecorded() {
        #expect(!OnbiiTranscriptionRun.transcriberName.isEmpty)
        #expect(OnbiiTranscriptionRun.speakerModelName.contains("CAM++"))
    }

    /// An implementation that only ever asks a person is fully conformant under
    /// `0033` — it records that the language was chosen. Detection is not
    /// required, but the record has to be able to say which happened.
    @Test
    func aLanguageCarriesHowItWasArrivedAt() {
        let chosen = OnbiiTranscriptionRun.Language(locale: Locale(identifier: "nl-NL"))
        #expect(chosen.selection == .chosen)

        let detected = OnbiiTranscriptionRun.Language(
            locale: Locale(identifier: "nl-NL"),
            selection: .detected
        )
        #expect(detected.selection == .detected)
    }

    /// Diarization is derived data. It never blocks producing a transcript, and
    /// it never touches a source — an embedder that cannot read the audio leaves
    /// the words exactly as they were.
    @Test
    func diarizationFailureLeavesTheTranscriptIntact() async {
        let segments = [
            OnbiiTranscriptSegmentFixture.make("hello", at: 0),
            OnbiiTranscriptSegmentFixture.make("there", at: 1),
        ]
        let result = await OnbiiTranscriptionRun.diarize(
            segments,
            audioURL: URL(fileURLWithPath: "/nonexistent/nothing.m4a"),
            labelPrefix: "t0s"
        )
        #expect(result == segments)
        #expect(result.allSatisfy { $0.speakerID == nil })
    }

    @Test
    func diarizingNothingIsNotAnError() async {
        let result = await OnbiiTranscriptionRun.diarize(
            [],
            audioURL: URL(fileURLWithPath: "/nonexistent/nothing.m4a"),
            labelPrefix: "t0s"
        )
        #expect(result.isEmpty)
    }
}

private enum OnbiiTranscriptSegmentFixture {
    static func make(_ text: String, at start: TimeInterval) -> OnbiiTranscriptSegment {
        OnbiiTranscriptSegment(
            text: text,
            startSeconds: start,
            durationSeconds: 0.5,
            sourceRole: "recording"
        )
    }
}
#endif
