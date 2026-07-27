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

private func makeManifest(resources: [OnbiiResource]) -> OnbiiManifest {
    OnbiiManifest(
        objectID: .init(rawValue: "status-object"),
        objectType: "recording",
        title: "Status",
        createdAt: Date(timeIntervalSince1970: 0),
        resources: resources,
        provenance: []
    )
}
