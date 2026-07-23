import Foundation

public struct OnbiiTranscriptSegment: Codable, Equatable, Sendable {
    public var text: String
    public var startSeconds: TimeInterval
    public var durationSeconds: TimeInterval
    public var confidence: Float?
    public var sourceRole: String

    public init(
        text: String,
        startSeconds: TimeInterval,
        durationSeconds: TimeInterval,
        confidence: Float? = nil,
        sourceRole: String
    ) {
        self.text = text
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.confidence = confidence
        self.sourceRole = sourceRole
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

    public init(
        generatedAt: Date = Date(),
        tracks: [OnbiiTrackTranscript],
        timeline: [OnbiiTranscriptSegment]
    ) {
        self.generatedAt = generatedAt
        self.tracks = tracks
        self.timeline = timeline
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
        let lines = utterances(from: document.timeline).map { utterance in
            "**\(timestamp(utterance.startSeconds)) \(label(utterance.role)):** "
                + utterance.text
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

    private struct Utterance {
        var startSeconds: TimeInterval
        var role: String
        var text: String
        var endSeconds: TimeInterval
    }

    private static func utterances(
        from segments: [OnbiiTranscriptSegment]
    ) -> [Utterance] {
        var result = [Utterance]()
        for segment in segments {
            if var current = result.last,
               current.role == segment.sourceRole,
               segment.startSeconds - current.endSeconds <= 1.5 {
                result.removeLast()
                current.text = append(segment.text, to: current.text)
                current.endSeconds = segment.startSeconds + segment.durationSeconds
                result.append(current)
            } else {
                result.append(
                    Utterance(
                        startSeconds: segment.startSeconds,
                        role: segment.sourceRole,
                        text: segment.text,
                        endSeconds: segment.startSeconds + segment.durationSeconds
                    )
                )
            }
        }
        return result
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

    private static func label(_ role: String) -> String {
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
