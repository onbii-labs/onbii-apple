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
    private let scopeURL: URL?
    private let scrolls: Bool
    @State private var state: LoadState = .loading

    /// - Parameters:
    ///   - accessedThrough: the security-scoped URL that grants access to this
    ///     bundle, where one is needed. A sandboxed macOS app holds its
    ///     permission against the *archive folder* the person chose, not against
    ///     each object inside it, so reading a resource without it fails even
    ///     though the file is plainly there.
    ///   - scrolls: `true` for a screen of its own, as on iPhone. `false` when
    ///     embedding inside a pane that already scrolls, as in the macOS object
    ///     detail — nesting scroll views there would trap the wheel.
    public init(
        bundle: OnbiiBundle,
        accessedThrough scopeURL: URL? = nil,
        scrolls: Bool = true
    ) {
        self.bundle = bundle
        self.scopeURL = scopeURL
        self.scrolls = scrolls
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
            if scrolls {
                ScrollView { content }
                    .background(Color.onbiiBackground)
            } else {
                content
            }
        }
        .task(id: bundle.manifest.objectID) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(OnbiiTheme.Spacing.l)

        case let .document(document):
            turns(of: document)

        case let .plainText(text):
            Text(text)
                .font(.body)
                .foregroundStyle(.onbiiPrimaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(scrolls ? OnbiiTheme.Spacing.l : 0)

        case let .unavailable(message):
            OnbiiEmptyState(title: "No transcript to show.", message: message)
        }
    }

    // MARK: Turns

    private func turns(of document: OnbiiTranscriptDocument) -> some View {
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
        .padding(scrolls ? OnbiiTheme.Spacing.l : 0)
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
        let scopeURL = scopeURL
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.read(bundle, accessedThrough: scopeURL)
        }.value
        state = loaded
    }

    private nonisolated static func read(
        _ bundle: OnbiiBundle,
        accessedThrough scopeURL: URL?
    ) -> LoadState {
        // Both: the archive scope covers objects inside the chosen folder, the
        // bundle's own scope covers one opened directly from Finder.
        let scopes = [scopeURL, bundle.url].compactMap(\.self)
        let held = scopes.filter { $0.startAccessingSecurityScopedResource() }
        defer { held.forEach { $0.stopAccessingSecurityScopedResource() } }

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
        // Diarization labels are internal strings like `t0s1` — track 0,
        // speaker 1. They must stay opaque, but they should not be read aloud
        // to anyone either, so they are numbered in order of first appearance.
        // This is presentation only: the manifest keeps its own labels.
        var ordinals: [String: Int] = [:]

        for segment in document.timeline {
            let key = segment.speakerID ?? segment.sourceRole
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if key == currentKey, var last = turns.popLast() {
                last.text += " " + text
                turns.append(last)
            } else {
                if let speakerID = segment.speakerID, ordinals[speakerID] == nil {
                    ordinals[speakerID] = ordinals.count + 1
                }
                turns.append(
                    Turn(
                        speaker: label(
                            for: segment,
                            ordinal: segment.speakerID.flatMap { ordinals[$0] }
                        ),
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
    nonisolated static func label(
        for segment: OnbiiTranscriptSegment,
        ordinal: Int? = nil
    ) -> String {
        if segment.speakerID != nil {
            return "Speaker \(ordinal ?? 1)"
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
