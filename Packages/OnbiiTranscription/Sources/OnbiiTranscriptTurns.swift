import Foundation

/// A readable block of transcript: one speaker, speaking continuously.
public struct OnbiiTranscriptTurn: Equatable, Sendable {
    /// The label to show. Either `Speaker N` for a diarized voice, or an honest
    /// capture-track name when the recording was never diarized.
    public var speaker: String
    public var startSeconds: TimeInterval
    public var text: String

    public init(speaker: String, startSeconds: TimeInterval, text: String) {
        self.speaker = speaker
        self.startSeconds = startSeconds
        self.text = text
    }
}

/// Collapses a segment timeline into speaker turns.
///
/// This is the single definition. The Markdown renderer and the in-app
/// transcript view both read it, because they were each grouping turns
/// separately and had each grown the same bug: a word the embedder could not
/// place kept `speakerID == nil`, and both renderers then labelled it with its
/// *capture track* — which for a single-track recording reads "Recording".
/// Inside a diarized transcript that looks like a second person and cuts a
/// sentence in half:
///
/// ```text
/// **00:08 Speaker 1:** Ik heb nu m'n telefoon in het
/// **00:11 Recording:** Nederlands gezet
/// ```
///
/// The fallback was honest when nothing had been diarized. It is not honest
/// inside a document that has been.
public enum OnbiiTranscriptTurns {
    /// Groups the timeline into turns.
    ///
    /// A new turn begins only when the speaker changes — never on a pause — so a
    /// speaker who stops to think stays in one block instead of looking like
    /// someone else resumed.
    ///
    /// When the document is diarized at all, a segment with no speaker joins its
    /// neighbouring turn (the preceding one where there is one, otherwise the
    /// following one) rather than becoming a speaker of its own. That is a
    /// guess, and it can be wrong where an unplaced word really did start a new
    /// turn — but it is a smaller and more recoverable error than presenting a
    /// track name as a person. It is also **presentation only**: the derived
    /// transcript keeps its `null`, and says exactly which words were never
    /// placed.
    ///
    /// Track labels are reserved for transcripts with no diarization at all,
    /// where they are the truth.
    public static func turns(
        in timeline: [OnbiiTranscriptSegment]
    ) -> [OnbiiTranscriptTurn] {
        let segments = timeline.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !segments.isEmpty else { return [] }

        let keys = groupingKeys(for: segments)
        let labels = displayLabels(for: segments, keys: keys)

        var turns = [OnbiiTranscriptTurn]()
        var currentKey: String?
        for (index, segment) in segments.enumerated() {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if keys[index] == currentKey, var last = turns.popLast() {
                last.text = joined(text, onto: last.text)
                turns.append(last)
            } else {
                turns.append(
                    OnbiiTranscriptTurn(
                        speaker: labels[keys[index]] ?? roleLabel(segment.sourceRole),
                        startSeconds: segment.startSeconds,
                        text: text
                    )
                )
                currentKey = keys[index]
            }
        }
        return turns
    }

    /// A grouping key per segment. Diarized documents resolve an unassigned
    /// segment to its nearest assigned neighbour; undiarized ones group by
    /// capture track.
    private static func groupingKeys(
        for segments: [OnbiiTranscriptSegment]
    ) -> [String] {
        let isDiarized = segments.contains { $0.speakerID != nil }
        guard isDiarized else {
            return segments.map { "role:\($0.sourceRole)" }
        }

        var keys = segments.map { segment -> String? in
            segment.speakerID.map { "speaker:\($0)" }
        }
        var lastAssigned: String?
        for index in keys.indices {
            if let key = keys[index] {
                lastAssigned = key
            } else {
                keys[index] = lastAssigned
            }
        }
        // Anything still unassigned precedes the first placed word; it belongs
        // to whichever turn opens the document.
        var nextAssigned: String?
        for index in keys.indices.reversed() {
            if let key = keys[index] {
                nextAssigned = key
            } else {
                keys[index] = nextAssigned
            }
        }
        return zip(keys, segments).map { key, segment in
            key ?? "role:\(segment.sourceRole)"
        }
    }

    /// Maps grouping keys to display labels: diarized speakers become
    /// `Speaker 1`, `Speaker 2`, … numbered by first appearance, so the internal
    /// label (`t0s2`) is never read aloud to anyone. Undiarized tracks keep
    /// their source label.
    private static func displayLabels(
        for segments: [OnbiiTranscriptSegment],
        keys: [String]
    ) -> [String: String] {
        var labels = [String: String]()
        var speakerCount = 0
        for (index, key) in keys.enumerated() where labels[key] == nil {
            if key.hasPrefix("speaker:") {
                speakerCount += 1
                labels[key] = "Speaker \(speakerCount)"
            } else {
                labels[key] = roleLabel(segments[index].sourceRole)
            }
        }
        return labels
    }

    private static func joined(_ text: String, onto existing: String) -> String {
        if let first = text.unicodeScalars.first,
           CharacterSet.punctuationCharacters.contains(first) {
            return existing + text
        }
        return existing + " " + text
    }

    static func roleLabel(_ role: String) -> String {
        switch role {
        case "system-audio": "System audio"
        case "microphone": "Microphone"
        default: "Recording"
        }
    }

    public static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, (total % 3600) / 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }
}
