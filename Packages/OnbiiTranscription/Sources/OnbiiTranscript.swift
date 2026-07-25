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
        let labels = displayLabels(for: document.timeline)
        let lines = turns(from: document.timeline).map { turn in
            "**\(timestamp(turn.startSeconds)) \(labels[turn.key] ?? "Recording"):** "
                + turn.text
        }
        let body = lines.isEmpty ? "_No speech was recognized._" : lines.joined(
            separator: "\n\n"
        )
        return """
        # Transcript: \(safeTitle)

        _Generated on-device. Source recordings remain unchanged._

        \(body)
        """
        + "\n"
    }

    private struct Turn {
        var key: String
        var startSeconds: TimeInterval
        var text: String
    }

    /// Groups the timeline into speaker turns. A new turn begins only when the
    /// speaker changes — never on a pause. This means a single speaker who
    /// pauses stays in one block instead of looking like a different person
    /// resumed. When the recording has been diarized, the grouping key is the
    /// opaque speaker ID; before diarization it falls back to the capture track,
    /// which is honest source attribution rather than an inferred speaker.
    private static func turns(
        from segments: [OnbiiTranscriptSegment]
    ) -> [Turn] {
        var result = [Turn]()
        for segment in segments {
            let key = groupingKey(for: segment)
            if var current = result.last, current.key == key {
                result.removeLast()
                current.text = append(segment.text, to: current.text)
                result.append(current)
            } else {
                result.append(
                    Turn(
                        key: key,
                        startSeconds: segment.startSeconds,
                        text: segment.text
                    )
                )
            }
        }
        return result
    }

    private static func groupingKey(for segment: OnbiiTranscriptSegment) -> String {
        if let speakerID = segment.speakerID {
            return "speaker:\(speakerID)"
        }
        return "role:\(segment.sourceRole)"
    }

    /// Maps each grouping key to a display label. Diarized speakers become
    /// `Speaker 1`, `Speaker 2`, … numbered by first appearance; undiarized
    /// tracks keep their source label.
    private static func displayLabels(
        for segments: [OnbiiTranscriptSegment]
    ) -> [String: String] {
        var labels = [String: String]()
        var speakerCount = 0
        for segment in segments {
            let key = groupingKey(for: segment)
            guard labels[key] == nil else {
                continue
            }
            if segment.speakerID != nil {
                speakerCount += 1
                labels[key] = "Speaker \(speakerCount)"
            } else {
                labels[key] = roleLabel(segment.sourceRole)
            }
        }
        return labels
    }

    private static func append(_ text: String, to existing: String) -> String {
        let punctuation = CharacterSet.punctuationCharacters
        if let first = text.unicodeScalars.first, punctuation.contains(first) {
            return existing + text
        }
        return existing + " " + text
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private static func roleLabel(_ role: String) -> String {
        switch role {
        case "system-audio":
            "System audio"
        case "microphone":
            "Microphone"
        default:
            "Recording"
        }
    }
}
