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
            let turns = OnbiiTranscriptTurns.turns(in: document.timeline)
            ForEach(Array(turns.enumerated()), id: \.offset) { _, turn in
                VStack(alignment: .leading, spacing: OnbiiTheme.Spacing.xs) {
                    HStack(spacing: OnbiiTheme.Spacing.s) {
                        Text(turn.speaker)
                            .onbiiSubheaderStyle()
                        Text(OnbiiTranscriptTurns.timestamp(turn.startSeconds))
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
        let generations = bundle.manifest.transcriptGenerations
        return VStack(alignment: .leading, spacing: OnbiiTheme.Spacing.xs) {
            Divider().overlay(Color.onbiiDivider)

            Text(
                "Generated on device "
                    + document.generatedAt.formatted(date: .abbreviated, time: .shortened)
                    + ". The original recordings were not changed."
            )

            // What this transcript assumed. Spec decision 0033 exists so that
            // "this transcript is wrong" can be told apart from "this transcript
            // was made under the wrong assumption" — which is what actually
            // happened when a Dutch conversation was read as Australian English.
            if let current = generations.last(where: \.isCurrent),
               let described = current.configuration?.spokenDescription {
                Text(described)
            }

            if document.speakerModel != nil {
                Text(
                    "Speaker labels are a rough grouping by voice. They are not "
                        + "names, and they mean nothing outside this object."
                )
            }

            // Earlier generations are retained rather than overwritten (0032),
            // so what changed stays visible instead of being asserted.
            if generations.count > 1 {
                let earlier = generations.dropLast()
                Text(
                    earlier.count == 1
                        ? "An earlier transcript is kept inside this object."
                        : "\(earlier.count) earlier transcripts are kept inside "
                            + "this object."
                )
                ForEach(Array(earlier.enumerated()), id: \.offset) { _, generation in
                    if let described = generation.configuration?.spokenDescription {
                        Text(
                            "• \(described) Superseded "
                                + generation.occurredAt.formatted(
                                    date: .abbreviated, time: .shortened
                                )
                                + "."
                        )
                    }
                }
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

}
