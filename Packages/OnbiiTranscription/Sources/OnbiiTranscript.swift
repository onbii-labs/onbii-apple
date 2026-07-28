import Foundation

public struct OnbiiTranscriptSegment: Codable, Equatable, Sendable {
    public var text: String
    public var startSeconds: TimeInterval
    public var durationSeconds: TimeInterval
    public var confidence: Float?
    /// The capture track this text came from (`microphone`, `system-audio`, or
    /// `recording`). This is honest source attribution, never a person.
    public var sourceRole: String
    /// An opaque, per-object diarization label (e.g. `S1`, `S2`) assigned by
    /// voice clustering, or `nil` when the recording has not been diarized.
    ///
    /// The value carries no cross-object meaning: `S2` in one object is
    /// unrelated to `S2` in another. Mapping a label to a named person (or a
    /// reusable voice signature) is a later, separately provenanced step, so
    /// this stays deliberately opaque. See `OnbiiSpeakerDiarization`.
    public var speakerID: String?

    public init(
        text: String,
        startSeconds: TimeInterval,
        durationSeconds: TimeInterval,
        confidence: Float? = nil,
        sourceRole: String,
        speakerID: String? = nil
    ) {
        self.text = text
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.confidence = confidence
        self.sourceRole = sourceRole
        self.speakerID = speakerID
    }
}

public struct OnbiiTrackTranscript: Codable, Equatable, Sendable {
    public var sourceResourceID: String
    public var sourceRole: String
    public var localeIdentifier: String
    public var formattedText: String
    public var segments: [OnbiiTranscriptSegment]

    public init(
        sourceResourceID: String,
        sourceRole: String,
        localeIdentifier: String,
        formattedText: String,
        segments: [OnbiiTranscriptSegment]
    ) {
        self.sourceResourceID = sourceResourceID
        self.sourceRole = sourceRole
        self.localeIdentifier = localeIdentifier
        self.formattedText = formattedText
        self.segments = segments
    }
}

public struct OnbiiTranscriptDocument: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var tracks: [OnbiiTrackTranscript]
    public var timeline: [OnbiiTranscriptSegment]
    /// The speaker-embedding model that produced the diarization (the segment
    /// `speakerID`s), or nil when the recording was not diarized. Records the
    /// provenance of the derived speaker turns.
    public var speakerModel: String?

    public init(
        generatedAt: Date = Date(),
        tracks: [OnbiiTrackTranscript],
        timeline: [OnbiiTranscriptSegment],
        speakerModel: String? = nil
    ) {
        self.generatedAt = generatedAt
        self.tracks = tracks
        self.timeline = timeline
        self.speakerModel = speakerModel
    }
}

public enum OnbiiTranscriptTimeline {
    public static func merge(
        _ transcripts: [(transcript: OnbiiTrackTranscript, offset: TimeInterval)],
        suppressLikelyEcho: Bool = true
    ) -> [OnbiiTranscriptSegment] {
        let shifted = transcripts.map { item in
            (
                role: item.transcript.sourceRole,
                segments: item.transcript.segments.map { segment in
                    var value = segment
                    value.startSeconds += item.offset
                    return value
                }
            )
        }
        var suppressedMicrophoneIndices = Set<Int>()
        if suppressLikelyEcho,
           let system = shifted.first(where: { $0.role == "system-audio" }),
           let microphone = shifted.first(where: { $0.role == "microphone" }) {
            suppressedMicrophoneIndices = likelyEchoIndices(
                system: system.segments,
                microphone: microphone.segments
            )
        }

        return shifted
            .flatMap { item in
                item.segments.enumerated().compactMap { index, segment in
                    if item.role == "microphone",
                       suppressedMicrophoneIndices.contains(index) {
                        return nil
                    }
                    return segment
                }
            }
            .sorted {
                if $0.startSeconds != $1.startSeconds {
                    return $0.startSeconds < $1.startSeconds
                }
                return $0.sourceRole < $1.sourceRole
            }
    }

    /// Suppresses only runs of at least three matching words at nearly the same
    /// time. Short coincidences are retained to avoid erasing real dialogue.
    private static func likelyEchoIndices(
        system: [OnbiiTranscriptSegment],
        microphone: [OnbiiTranscriptSegment]
    ) -> Set<Int> {
        var suppressed = Set<Int>()
        for microphoneStart in microphone.indices where !suppressed.contains(
            microphoneStart
        ) {
            for systemStart in system.indices {
                var count = 0
                while microphoneStart + count < microphone.count,
                      systemStart + count < system.count {
                    let microphoneSegment = microphone[microphoneStart + count]
                    let systemSegment = system[systemStart + count]
                    let lag = microphoneSegment.startSeconds
                        - systemSegment.startSeconds
                    guard normalized(microphoneSegment.text)
                            == normalized(systemSegment.text),
                          lag >= -0.1,
                          lag <= 0.75 else {
                        break
                    }
                    count += 1
                }
                guard count >= 3 else {
                    continue
                }
                suppressed.formUnion(microphoneStart..<(microphoneStart + count))
                break
            }
        }
        return suppressed
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}

public enum OnbiiTranscriptMarkdown {
    public static func render(
        _ document: OnbiiTranscriptDocument,
        title: String
    ) -> String {
        let safeTitle = title
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        return """
        # Transcript: \(safeTitle)

        _Generated on-device. Source recordings remain unchanged._

        \(body(document))
        """
        + "\n"
    }

    /// The speaker-turn body without the document header. Reused as the
    /// object's `content.md` transcript section so the two views share exactly
    /// the same turn rendering.
    ///
    /// Turn shaping lives in ``OnbiiTranscriptTurns`` because the in-app
    /// transcript view needs exactly the same answer, and when each of them
    /// shaped turns for itself they drifted.
    public static func body(_ document: OnbiiTranscriptDocument) -> String {
        let lines = OnbiiTranscriptTurns.turns(in: document.timeline).map { turn in
            "**\(OnbiiTranscriptTurns.timestamp(turn.startSeconds)) "
                + "\(turn.speaker):** \(turn.text)"
        }
        return lines.isEmpty ? "_No speech was recognized._" : lines.joined(
            separator: "\n\n"
        )
    }
}
