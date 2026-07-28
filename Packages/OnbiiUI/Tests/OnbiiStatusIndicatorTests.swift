import OnbiiArchive
import OnbiiUI
import Testing

// These tests cover the mapping from manifest status plus session activity to
// what a person sees. They deliberately do not assert anything about resolved
// colours: colour sets in a package resource bundle are compiled by Xcode, not
// by the SwiftPM command line, so a runtime colour assertion here would be
// testing the test runner rather than the app.

@Test
func manifestStatusShowsThroughWhenNothingIsHappening() {
    #expect(OnbiiStatusIndicator(.transcribed) == .transcribed)
    #expect(OnbiiStatusIndicator(.awaitingTranscription) == .awaitingTranscription)
    #expect(OnbiiStatusIndicator(.sourceOnly) == .sourceOnly)
}

@Test
func activityTakesPrecedenceOverManifestStatus() {
    let working = OnbiiStatusIndicator(
        .awaitingTranscription,
        activity: .working("Transcribing on device…")
    )
    #expect(working == .working("Transcribing on device…"))

    let failed = OnbiiStatusIndicator(
        .awaitingTranscription,
        activity: .failed("No speech model installed.")
    )
    #expect(failed == .needsAttention("No speech model installed."))
}

/// A failed attempt says something about this session, not about the object —
/// an already-transcribed object that fails a second run is still transcribed
/// underneath, and clearing the activity must reveal that unchanged.
@Test
func clearingActivityRevealsTheUnchangedObject() {
    #expect(
        OnbiiStatusIndicator(.transcribed, activity: .failed("Interrupted"))
            == .needsAttention("Interrupted")
    )
    #expect(OnbiiStatusIndicator(.transcribed, activity: nil) == .transcribed)
}

@Test
func everyIndicatorCarriesATitleAndASymbol() {
    let indicators: [OnbiiStatusIndicator] = [
        .transcribed,
        .awaitingTranscription,
        .sourceOnly,
        .working("Transcribing on device…"),
        .needsAttention("Transcription failed."),
    ]

    for indicator in indicators {
        #expect(!indicator.title.isEmpty)
        #expect(!indicator.shortTitle.isEmpty)
        #expect(!indicator.systemImage.isEmpty)
    }
}

/// A long message must not become the label of a dense row.
@Test
func longMessagesCollapseInTheShortTitle() {
    let message = "The on-device speech model for Dutch is not installed."
    #expect(OnbiiStatusIndicator.needsAttention(message).title == message)
    #expect(OnbiiStatusIndicator.needsAttention(message).shortTitle == "Needs attention")
    #expect(OnbiiStatusIndicator.working(message).shortTitle == "Working")
}
