import Foundation
@testable import OnbiiTranscription
import Testing

// MARK: - Clustering

@Test
func clusteringSeparatesTwoDistinctVoices() {
    let voiceA: [Float] = [1, 0, 0]
    let voiceB: [Float] = [0, 1, 0]
    // Interleaved so first-appearance labeling is exercised.
    let labels = OnbiiSpeakerClustering.cluster(
        embeddings: [voiceB, voiceA, voiceA, voiceB],
        distanceThreshold: 0.5
    )
    #expect(labels == [0, 1, 1, 0])
}

@Test
func clusteringMergesNearIdenticalVoices() {
    let labels = OnbiiSpeakerClustering.cluster(
        embeddings: [[1, 0, 0], [0.99, 0.01, 0], [0.98, 0.0, 0.02]],
        distanceThreshold: 0.5
    )
    #expect(Set(labels) == [0])
}

@Test
func clusteringHonorsThreshold() {
    // Cosine distance ~0.29 between these; a tight threshold keeps them apart.
    let embeddings: [[Float]] = [[1, 0], [0.7, 0.7]]
    #expect(
        OnbiiSpeakerClustering.cluster(
            embeddings: embeddings,
            distanceThreshold: 0.1
        ) == [0, 1]
    )
    #expect(
        Set(
            OnbiiSpeakerClustering.cluster(
                embeddings: embeddings,
                distanceThreshold: 0.5
            )
        ) == [0]
    )
}

@Test
func consolidationAbsorbsSmallFragmentsIntoNearestSpeaker() {
    let voiceA: [Float] = [1, 0, 0]
    let voiceB: [Float] = [0, 1, 0]
    // Far enough from both A and B to be its own cluster, but nearer A.
    let fragment: [Float] = [0.3, 0, 0.95]
    let embeddings = Array(repeating: voiceA, count: 5)
        + Array(repeating: voiceB, count: 5)
        + Array(repeating: fragment, count: 2)

    let raw = OnbiiSpeakerClustering.cluster(
        embeddings: embeddings,
        distanceThreshold: 0.5
    )
    #expect(Set(raw).count == 3)   // A, B, and the small fragment cluster

    let consolidated = OnbiiSpeakerClustering.consolidate(
        embeddings: embeddings,
        labels: raw,
        minClusterSize: 4
    )
    #expect(Set(consolidated).count == 2)            // fragment absorbed
    #expect(Set(consolidated[0..<5]).count == 1)     // all A → one speaker
    #expect(Set(consolidated[5..<10]).count == 1)    // all B → one speaker
    #expect(consolidated[0] != consolidated[5])      // A and B are distinct
    #expect(consolidated[10] == consolidated[0])     // fragment joined A
}

@Test
func consolidationKeepsRawClustersWhenNoneReachMinimum() {
    let embeddings = [[Float]([1, 0, 0]), [Float]([0, 1, 0])]
    let raw = OnbiiSpeakerClustering.cluster(
        embeddings: embeddings,
        distanceThreshold: 0.5
    )
    let consolidated = OnbiiSpeakerClustering.consolidate(
        embeddings: embeddings,
        labels: raw,
        minClusterSize: 4
    )
    #expect(consolidated == [0, 1])
}

@Test
func consolidationFractionalFloorScalesWithLength() {
    let voiceA: [Float] = [1, 0, 0]
    let voiceB: [Float] = [0, 1, 0]
    let fragment: [Float] = [0.3, 0, 0.95]   // own cluster, nearer A
    let embeddings = Array(repeating: voiceA, count: 48)
        + Array(repeating: voiceB, count: 48)
        + Array(repeating: fragment, count: 4)
    let raw = OnbiiSpeakerClustering.cluster(
        embeddings: embeddings,
        distanceThreshold: 0.5
    )
    #expect(Set(raw).count == 3)

    // Absolute floor alone keeps the 4-window fragment as a speaker.
    let absolute = OnbiiSpeakerClustering.consolidate(
        embeddings: embeddings,
        labels: raw,
        minClusterSize: 2
    )
    #expect(Set(absolute).count == 3)

    // A 5% fractional floor (= 5 of 100 windows) absorbs the fragment.
    let fractional = OnbiiSpeakerClustering.consolidate(
        embeddings: embeddings,
        labels: raw,
        minClusterSize: 2,
        minClusterFraction: 0.05
    )
    #expect(Set(fractional).count == 2)
}

// MARK: - Windowing

@Test
func windowingPoolsShortWordsAndBreaksOnSilence() {
    let starts: [TimeInterval] = [
        0.0, 0.5, 1.0,   // voice A, contiguous
        5.0, 5.5, 6.0,   // after a long gap
    ]
    let segments = starts.map {
        OnbiiTranscriptSegment(
            text: "w",
            startSeconds: $0,
            durationSeconds: 0.5,
            sourceRole: "recording"
        )
    }
    let windows = OnbiiSpeakerWindowing.windows(
        for: segments,
        minWindowSeconds: 0.8,
        maxGapSeconds: 1.0
    )
    #expect(windows.count == 2)
    #expect(windows.map(\.segmentIndices) == [[0, 1, 2], [3, 4, 5]])
}

@Test
func windowingFoldsTooShortTrailingWindow() {
    let starts: [TimeInterval] = [0.0, 0.5, 1.0, 1.5]
    let segments = starts.map {
        OnbiiTranscriptSegment(
            text: "w",
            startSeconds: $0,
            durationSeconds: 0.4,
            sourceRole: "recording"
        )
    }
    // First window fills to >= 1.5s at index 2; the lone tail folds back in.
    let windows = OnbiiSpeakerWindowing.windows(
        for: segments,
        minWindowSeconds: 1.5,
        maxGapSeconds: 1.0
    )
    #expect(windows.count == 1)
    #expect(windows[0].segmentIndices == [0, 1, 2, 3])
}

// MARK: - Diarizer

private struct SplitVoiceEmbedder: OnbiiSpeakerEmbedder {
    let boundary: TimeInterval
    func embedding(
        from start: TimeInterval,
        to end: TimeInterval
    ) async throws -> [Float]? {
        start < boundary ? [1, 0, 0] : [0, 1, 0]
    }
}

private struct SilentTailEmbedder: OnbiiSpeakerEmbedder {
    let silentFrom: TimeInterval
    func embedding(
        from start: TimeInterval,
        to end: TimeInterval
    ) async throws -> [Float]? {
        start >= silentFrom ? nil : [1, 0, 0]
    }
}

@Test
func diarizerLabelsTwoVoicesAcrossOneTrack() async throws {
    let starts: [TimeInterval] = [0.0, 0.5, 1.0, 5.0, 5.5, 6.0]
    let segments = starts.map {
        OnbiiTranscriptSegment(
            text: "w",
            startSeconds: $0,
            durationSeconds: 0.5,
            sourceRole: "recording"
        )
    }
    let diarized = try await OnbiiSpeakerDiarizer(
        minWindowSeconds: 0.8,
        maxGapSeconds: 1.0,
        distanceThreshold: 0.5
    ).diarize(track: segments, using: SplitVoiceEmbedder(boundary: 3.0))

    #expect(diarized.prefix(3).allSatisfy { $0.speakerID == "S1" })
    #expect(diarized.suffix(3).allSatisfy { $0.speakerID == "S2" })
}

@Test
func diarizerLeavesUnembeddableWindowsUnlabeled() async throws {
    let starts: [TimeInterval] = [0.0, 0.5, 1.0, 5.0, 5.5, 6.0]
    let segments = starts.map {
        OnbiiTranscriptSegment(
            text: "w",
            startSeconds: $0,
            durationSeconds: 0.5,
            sourceRole: "recording"
        )
    }
    let diarized = try await OnbiiSpeakerDiarizer(
        minWindowSeconds: 0.8,
        maxGapSeconds: 1.0,
        distanceThreshold: 0.5
    ).diarize(track: segments, using: SilentTailEmbedder(silentFrom: 3.0))

    #expect(diarized.prefix(3).allSatisfy { $0.speakerID == "S1" })
    #expect(diarized.suffix(3).allSatisfy { $0.speakerID == nil })
}

// MARK: - Markdown rendering

@Test
func markdownKeepsOneSpeakerTogetherAcrossLongPause() {
    let document = OnbiiTranscriptDocument(
        generatedAt: Date(timeIntervalSince1970: 0),
        tracks: [],
        timeline: [
            segment("Hello", at: 0, role: "recording"),
            segment("again", at: 30, role: "recording"),
        ]
    )
    let markdown = OnbiiTranscriptMarkdown.render(document, title: "Memo")
    // A 30s pause must not split one speaker into two blocks.
    #expect(markdown.contains("**00:00 Recording:** Hello again"))
    #expect(!markdown.contains("**00:30"))
}

@Test
func markdownNumbersDiarizedSpeakersByFirstAppearance() {
    let document = OnbiiTranscriptDocument(
        generatedAt: Date(timeIntervalSince1970: 0),
        tracks: [],
        timeline: [
            segment("Morning", at: 0, role: "recording", speaker: "S1"),
            segment("Hi", at: 2, role: "recording", speaker: "S2"),
            segment("Shall we start?", at: 4, role: "recording", speaker: "S1"),
        ]
    )
    let markdown = OnbiiTranscriptMarkdown.render(document, title: "Standup")
    #expect(markdown.contains("**00:00 Speaker 1:** Morning"))
    #expect(markdown.contains("**00:02 Speaker 2:** Hi"))
    #expect(markdown.contains("**00:04 Speaker 1:** Shall we start?"))
}

private func segment(
    _ text: String,
    at time: TimeInterval,
    role: String,
    speaker: String? = nil
) -> OnbiiTranscriptSegment {
    OnbiiTranscriptSegment(
        text: text,
        startSeconds: time,
        durationSeconds: 0.5,
        confidence: 0.9,
        sourceRole: role,
        speakerID: speaker
    )
}
