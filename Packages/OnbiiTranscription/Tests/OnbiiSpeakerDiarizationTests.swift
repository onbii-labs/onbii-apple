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

// MARK: - Embed range (field test 1, finding 5)

/// An isolated short word bounded by long pauses is a run of one, with nothing
/// to fold into. It used to reach the embedder as 0.18 s of audio, come back
/// `nil`, and keep no speaker at all.
@Test
func anIsolatedShortWordBorrowsTheSurroundingSilence() throws {
    let segments = [
        OnbiiTranscriptSegment(
            text: "nu", startSeconds: 4.0, durationSeconds: 0.18,
            sourceRole: "recording"
        ),
        OnbiiTranscriptSegment(
            text: "later", startSeconds: 9.0, durationSeconds: 0.5,
            sourceRole: "recording"
        ),
    ]
    let windows = OnbiiSpeakerWindowing.windows(
        for: segments,
        minWindowSeconds: 2.5,
        maxGapSeconds: 1.0
    )

    let short = try #require(windows.first)
    // The word span is untouched — that is what carries the label.
    #expect(short.startSeconds == 4.0)
    #expect(abs(short.endSeconds - 4.18) < 0.001)
    // The audio range is wide enough to embed.
    #expect(short.embedEndSeconds - short.embedStartSeconds >= 2.5)
    // ...and it never reaches the neighbouring word.
    #expect(short.embedStartSeconds >= 0)
    #expect(short.embedEndSeconds <= 9.0)
}

/// Widening into another speaker's voice would be a worse answer than no
/// answer, so the neighbouring words are a hard bound.
@Test
func wideningStopsAtTheNeighbouringWords() {
    let range = OnbiiSpeakerWindowing.embedRange(
        start: 5.0,
        end: 5.2,
        lowerBound: 4.8,
        upperBound: 5.6,
        minWindowSeconds: 3.0
    )
    #expect(range.start == 4.8)
    #expect(range.end == 5.6)
}

/// When the silence on one side runs out, the deficit is spent on the other.
@Test
func wideningSpendsWhatItCannotTakeFromOneSideOnTheOther() {
    let range = OnbiiSpeakerWindowing.embedRange(
        start: 0.0,
        end: 0.2,
        lowerBound: 0.0,
        upperBound: 100.0,
        minWindowSeconds: 3.0
    )
    #expect(range.start == 0.0)
    #expect(abs((range.end - range.start) - 3.0) < 0.001)
}

@Test
func aLongEnoughWindowIsNotWidened() {
    let segments = (0..<6).map {
        OnbiiTranscriptSegment(
            text: "w",
            startSeconds: Double($0) * 0.5,
            durationSeconds: 0.5,
            sourceRole: "recording"
        )
    }
    let windows = OnbiiSpeakerWindowing.windows(
        for: segments,
        minWindowSeconds: 2.5,
        maxGapSeconds: 1.0
    )
    for window in windows {
        #expect(window.embedStartSeconds == window.startSeconds)
        #expect(window.embedEndSeconds == window.endSeconds)
    }
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

/// Stands in for the Core ML embedder's real refusal: anything under a second
/// of audio comes back `nil`.
private struct MinimumLengthEmbedder: OnbiiSpeakerEmbedder {
    let minimumSeconds: TimeInterval
    func embedding(
        from start: TimeInterval,
        to end: TimeInterval
    ) async throws -> [Float]? {
        end - start >= minimumSeconds ? [1, 0, 0] : nil
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

/// The end-to-end shape of finding 5: a 0.18 s word between long pauses used to
/// come back unlabelled. With the surrounding silence borrowed, it is placed.
@Test
func anIsolatedShortWordNowGetsASpeaker() async throws {
    let segments = [
        OnbiiTranscriptSegment(
            text: "nu", startSeconds: 4.0, durationSeconds: 0.18,
            sourceRole: "recording"
        ),
        OnbiiTranscriptSegment(
            text: "later", startSeconds: 9.0, durationSeconds: 0.5,
            sourceRole: "recording"
        ),
    ]
    let diarized = try await OnbiiSpeakerDiarizer(
        minWindowSeconds: 2.5,
        maxGapSeconds: 1.0,
        distanceThreshold: 0.5
    ).diarize(
        track: segments,
        using: MinimumLengthEmbedder(minimumSeconds: 1.0)
    )

    #expect(diarized[0].speakerID != nil)
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
