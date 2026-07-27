import OnbiiArchive
import OnbiiCore
import OnbiiTranscription
import SwiftUI

/// Reads an object's transcript back.
///
/// The transcript is **derived data**, and this view keeps saying so: it shows
/// when it was generated, which model produced the speaker turns, and that the
/// source recordings were not touched. Speaker labels are the manifest's own
/// opaque per-object labels — `S1` is not a person, and it means nothing outside
/// this object.
///
/// Nothing here writes. It reads what the bundle already declares, so deleting
/// this view leaves every object exactly as it was.
public struct OnbiiTranscriptView: View {
    private let bundle: OnbiiBundle
    @State private var state: LoadState = .loading

    public init(bundle: OnbiiBundle) {
        self.bundle = bundle
    }

    private enum LoadState {
        case loading
        /// The structured artefact: speaker turns and timings.
        case document(OnbiiTranscriptDocument)
        /// Only the human-readable facet was present — older objects, or one
        /// written by something that did not produce the JSON.
        case plainText(String)
        case unavailable(String)
    }

    public var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case let .document(document):
                turns(of: document)

            case let .plainText(text):
                ScrollView {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.onbiiPrimaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OnbiiTheme.Spacing.l)
                }

            case let .unavailable(message):
                OnbiiEmptyState(title: "No transcript to show.", message: message)
            }
        }
        .background(Color.onbiiBackground)
        .task(id: bundle.manifest.objectID) { await load() }
    }

    // MARK: Turns

    private func turns(of document: OnbiiTranscriptDocument) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OnbiiTheme.Spacing.l) {
                ForEach(Array(Self.turns(in: document).enumerated()), id: \.offset) { _, turn in
                    VStack(alignment: .leading, spacing: OnbiiTheme.Spacing.xs) {
                        HStack(spacing: OnbiiTheme.Spacing.s) {
                            Text(turn.speaker)
                                .onbiiSubheaderStyle()
                            Text(Self.timestamp(turn.startSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.onbiiSecondaryText)
                        }

                        Text(turn.text)
                            .font(.body)
                            .foregroundStyle(.onbiiPrimaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                provenance(of: document)
            }
            .padding(OnbiiTheme.Spacing.l)
        }
    }

    private func provenance(of document: OnbiiTranscriptDocument) -> some View {
        VStack(alignment: .leading, spacing: OnbiiTheme.Spacing.xs) {
            Divider().overlay(Color.onbiiDivider)

            Text(
                "Generated on device "
                    + document.generatedAt.formatted(date: .abbreviated, time: .shortened)
                    + ". The original recordings were not changed."
            )

            if document.speakerModel != nil {
                Text(
                    "Speaker labels are a rough grouping by voice. They are not "
                        + "names, and they mean nothing outside this object."
                )
            }
        }
        .font(.caption)
        .foregroundStyle(.onbiiSecondaryText)
        .padding(.top, OnbiiTheme.Spacing.m)
    }

    // MARK: Loading

    private func load() async {
        let bundle = bundle
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.read(bundle)
        }.value
        state = loaded
    }

    private nonisolated static func read(_ bundle: OnbiiBundle) -> LoadState {
        let hasAccess = bundle.url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { bundle.url.stopAccessingSecurityScopedResource() }
        }

        // Prefer the structured artefact; it carries the turns and timings.
        if let resource = bundle.manifest.resources.first(where: {
            $0.id == "derived-transcript"
        }), let data = try? Data(contentsOf: bundle.url(for: resource)) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let document = try? decoder.decode(OnbiiTranscriptDocument.self, from: data) {
                return .document(document)
            }
        }

        // Fall back to the human-readable facet, which is what any other tool
        // would read too.
        if let resource = bundle.manifest.resources.first(where: {
            $0.id == "transcript-markdown"
        }), let text = try? String(contentsOf: bundle.url(for: resource), encoding: .utf8) {
            return .plainText(text)
        }

        return .unavailable(
            bundle.manifest.hasTranscribableAudio
                ? "This object has not been transcribed yet."
                : "This object has no audio to transcribe."
        )
    }

    // MARK: Shaping

    struct Turn: Equatable {
        var speaker: String
        var startSeconds: TimeInterval
        var text: String
    }

    /// Collapses the segment timeline into readable turns: consecutive segments
    /// from the same speaker (or, undiarized, the same capture track) become one
    /// paragraph rather than one line per recognised phrase.
    nonisolated static func turns(in document: OnbiiTranscriptDocument) -> [Turn] {
        var turns: [Turn] = []
        var currentKey: String?

        for segment in document.timeline {
            let key = segment.speakerID ?? segment.sourceRole
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if key == currentKey, var last = turns.popLast() {
                last.text += " " + text
                turns.append(last)
            } else {
                turns.append(
                    Turn(
                        speaker: label(for: segment),
                        startSeconds: segment.startSeconds,
                        text: text
                    )
                )
                currentKey = key
            }
        }

        return turns
    }

    /// A speaker label, or honest track attribution when the object has not
    /// been diarized. Track attribution is never presented as a speaker.
    nonisolated static func label(for segment: OnbiiTranscriptSegment) -> String {
        if let speakerID = segment.speakerID {
            return "Speaker \(speakerID)"
        }
        return switch segment.sourceRole {
        case "microphone": "Microphone"
        case "system-audio": "System audio"
        default: "Recording"
        }
    }

    nonisolated static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, (total % 3600) / 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }
}
