import Foundation
@testable import OnbiiCapture
import Testing

/// Field test 1, finding 1: the app went on displaying "Recording is visibly
/// active" after watchOS had suspended it, and reported a duration of zero for
/// twenty minutes of audio.
///
/// The behaviour that matters most — a real recording surviving, or not
/// surviving, a real suspension — cannot be produced here. It needs a device
/// and a walk. What *is* checkable is that the recorder does not invent an
/// answer when it has none.
@Suite
struct MicrophoneRecorderHonestyTests {
    @Test
    func aRecorderThatNeverStartedReportsNothing() {
        let recorder = OnbiiMicrophoneRecorder()
        #expect(!recorder.isRecording)
        #expect(recorder.duration == 0)
        #expect(recorder.stopRecording() == nil)
    }

    /// The foreground re-check must stay silent when there is nothing to
    /// report. It is called on every activation, and an app that cried wolf
    /// there would be as untrustworthy as one that said nothing.
    @Test
    func verifyingWithoutARecordingInFlightReportsNothing() {
        let recorder = OnbiiMicrophoneRecorder()
        #expect(recorder.verifyStillRecording() == nil)
        #expect(recorder.verifyStillRecording() == nil)
    }

    /// Whatever happened, the audio that reached the file is kept. Every message
    /// has to say so, because the first instinct on reading "interrupted" is to
    /// assume the recording was lost.
    @Test
    func everyInterruptionSaysTheCapturedAudioIsKept() {
        let interruptions: [OnbiiCaptureInterruption] = [
            .interrupted("a call arrived."),
            .stoppedUnexpectedly("the system stopped this app."),
        ]
        for interruption in interruptions {
            #expect(interruption.message.contains("kept"))
            #expect(!interruption.message.isEmpty)
        }
    }
}
