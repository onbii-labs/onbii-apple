import Foundation
import OnbiiArchive
import OnbiiCore
import Testing

@Test
func preservedAudioWithoutATranscriptAwaitsTranscription() {
    let manifest = makeManifest(resources: [audioSource])

    #expect(manifest.status == .awaitingTranscription)
    #expect(manifest.hasTranscribableAudio)
    #expect(!manifest.hasTranscript)
}

@Test
func derivedTranscriptCountsAsTranscribed() {
    let manifest = makeManifest(resources: [
        audioSource,
        OnbiiResource(
            id: "derived-transcript",
            role: .derived,
            path: "derived/transcript.json",
            mediaType: "application/json"
        ),
    ])

    #expect(manifest.status == .transcribed)
}

/// The case the macOS inspector used to get wrong: it tested only
/// `derived-transcript`, so an object carrying just the Markdown artefact was
/// offered "Transcribe On Device" again.
@Test
func transcriptMarkdownAloneAlsoCountsAsTranscribed() {
    let manifest = makeManifest(resources: [
        audioSource,
        OnbiiResource(
            id: "transcript-markdown",
            role: .derived,
            path: "transcript.md",
            mediaType: "text/markdown"
        ),
    ])

    #expect(manifest.status == .transcribed)
    #expect(manifest.hasTranscript)
}

@Test
func anObjectWithNoAudioSourceIsSourceOnly() {
    let manifest = makeManifest(resources: [
        OnbiiResource(
            id: "source-document",
            role: .source,
            path: "source/notes.pdf",
            mediaType: "application/pdf"
        ),
    ])

    #expect(manifest.status == .sourceOnly)
    #expect(!manifest.hasTranscribableAudio)
}

/// The human-readable facet is written for every object and is not a transcript.
@Test
func theHumanReadableFacetIsNotATranscript() {
    let manifest = makeManifest(resources: [
        audioSource,
        OnbiiResource(
            id: "content-markdown",
            role: .humanReadable,
            path: "content.md",
            mediaType: "text/markdown"
        ),
    ])

    #expect(manifest.status == .awaitingTranscription)
}

private let audioSource = OnbiiResource(
    id: "source-recording",
    role: .source,
    path: "source/recording.m4a",
    mediaType: "audio/mp4"
)

private func makeManifest(
    resources: [OnbiiResource],
    provenance: [OnbiiProvenanceEvent] = []
) -> OnbiiManifest {
    OnbiiManifest(
        objectID: .init(rawValue: "status-object"),
        objectType: "recording",
        title: "Status",
        createdAt: Date(timeIntervalSince1970: 0),
        resources: resources,
        provenance: provenance
    )
}

// MARK: Runs that found nothing

/// An object nobody has processed says nothing about processing.
@Test
func anUntouchedObjectRecordsNoEmptyRuns() {
    let manifest = makeManifest(resources: [audioSource])

    #expect(manifest.emptyDerivations.isEmpty)
    #expect(manifest.emptyDerivationSummary == nil)
}

/// The language is the actionable part. "Nothing was found" invites trying the
/// same setting again; naming the language is what lets a person choose a
/// different one.
@Test
func anEmptyRunIsSummarisedWithTheLanguageItUsed() {
    let manifest = makeManifest(
        resources: [audioSource],
        provenance: [
            makeEmptyRun(languages: ["nl-NL"], at: 1_000_000)
        ]
    )

    let summary = manifest.emptyDerivationSummary
    #expect(summary?.contains("Dutch") == true)
    #expect(summary?.contains("found no speech") == true)
    #expect(summary?.contains("unchanged") == true)
    #expect(manifest.status == .awaitingTranscription)
}

/// Every language tried is worth naming, because the whole point is knowing
/// which ones are already ruled out.
@Test
func severalEmptyRunsNameEveryLanguageTried() {
    let manifest = makeManifest(
        resources: [audioSource],
        provenance: [
            makeEmptyRun(languages: ["nl-NL"], at: 1_000_000),
            makeEmptyRun(languages: ["en-US"], at: 2_000_000),
        ]
    )

    let summary = try? #require(manifest.emptyDerivationSummary)
    #expect(summary?.contains("Dutch") == true)
    #expect(summary?.contains("English") == true)
    #expect(summary?.contains("most recently") == true)
    #expect(manifest.emptyDerivations.count == 2)
}

/// A transcript makes the earlier empty runs history rather than the object's
/// current condition — the views ask for this only when there is no transcript,
/// and the reading stays available either way.
@Test
func anEmptyRunSurvivesALaterSuccessfulTranscript() {
    let manifest = makeManifest(
        resources: [
            audioSource,
            OnbiiResource(
                id: "derived-transcript",
                role: .derived,
                path: "derived/transcript.json",
                mediaType: "application/json"
            ),
        ],
        provenance: [makeEmptyRun(languages: ["nl-NL"], at: 1_000_000)]
    )

    #expect(manifest.status == .transcribed)
    #expect(manifest.emptyDerivations.count == 1)
}

private func makeEmptyRun(
    languages: [String],
    at seconds: TimeInterval
) -> OnbiiProvenanceEvent {
    OnbiiProvenanceEvent(
        action: OnbiiProvenanceEvent.foundNothingAction,
        occurredAt: Date(timeIntervalSince1970: seconds),
        agent: .init(kind: "software", name: "Apple Speech on-device"),
        inputResourceIDs: ["source-recording"],
        outputResourceIDs: [],
        configuration: OnbiiDerivationConfiguration(
            languages: languages,
            languageSelection: .chosen
        )
    )
}

// MARK: What unattended processing should pick up

@Test
func aPreservedRecordingWithNoTranscriptAwaitsOne() {
    let manifest = makeManifest(resources: [audioSource])

    #expect(manifest.awaitsFirstTranscript)
}

/// `0032` makes a second transcript safe — it supersedes and retains — but it
/// also says reprocessing is deliberate. Safe is not the same as permitted, and
/// nothing should produce a generation nobody asked for.
@Test
func anObjectThatAlreadyHasATranscriptIsNeverPickedUp() {
    let manifest = makeManifest(resources: [
        audioSource,
        OnbiiResource(
            id: "derived-transcript",
            role: .derived,
            path: "derived/transcript.json",
            mediaType: "application/json"
        ),
    ])

    #expect(!manifest.awaitsFirstTranscript)
    #expect(manifest.status == .transcribed)
}

/// The condition that stops a loop. A quiet walk transcribes to nothing and
/// records that it did; without this, every re-read of the archive would queue
/// the same recording again for as long as the app was open.
@Test
func anObjectAlreadyFoundToHoldNoSpeechIsNotPickedUpAgain() {
    let manifest = makeManifest(
        resources: [audioSource],
        provenance: [makeEmptyRun(languages: ["nl-NL"], at: 1_000_000)]
    )

    #expect(!manifest.awaitsFirstTranscript)
    // Still awaiting a transcript as far as its status goes — it simply has
    // nothing outstanding that running the same thing again would fix.
    #expect(manifest.status == .awaitingTranscription)
}

@Test
func anObjectWithNoAudioHasNothingToTranscribe() {
    let manifest = makeManifest(resources: [
        OnbiiResource(
            id: "source-document",
            role: .source,
            path: "source/notes.pdf",
            mediaType: "application/pdf"
        ),
    ])

    #expect(!manifest.awaitsFirstTranscript)
}
