import OnbiiArchive
import OnbiiCore
import OnbiiProcessing
import OnbiiUI
import SwiftUI

/// What one object holds. Sources are named as sources and derived artefacts as
/// derived, because the difference is the whole point: the recording is the
/// irreplaceable truth and everything else can be made again.
struct MobileObjectDetailView: View {
    let bundle: OnbiiBundle
    @Bindable var model: MobileViewModel

    /// Folded away by default. These answer "what exactly is in here?", which is
    /// a question people ask occasionally and not on arrival.
    @State private var showsDetails = false
    @State private var showsResources = false

    var body: some View {
        List {
            Section {
                Text(bundle.manifest.title)
                    .font(.onbiiSectionTitle)
                    .foregroundStyle(.onbiiPrimaryText)
                OnbiiStatusBadge(model.indicator(for: bundle))
            }

            // What the person came for sits directly under the title. The
            // metadata below is available but folded away — it answers
            // questions rather than opening the screen.
            if bundle.manifest.hasTranscript {
                Section {
                    NavigationLink {
                        OnbiiTranscriptView(bundle: bundle)
                            .navigationTitle("Transcript")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Read Transcript", systemImage: "text.alignleft")
                    }
                }
            }

            Section {
                DisclosureGroup(isExpanded: $showsDetails) {
                    ForEach(factRows, id: \.label) { row in
                        LabeledContent(row.label) {
                            Text(row.value)
                                .foregroundStyle(.onbiiSecondaryText)
                                .textSelection(.enabled)
                        }
                    }
                } label: {
                    Text("Details")
                        .onbiiSubheaderStyle()
                }
            }

            Section {
                DisclosureGroup(isExpanded: $showsResources) {
                    ForEach(bundle.manifest.resources, id: \.id) { resource in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(roleLabel(resource.role))
                                .font(.onbiiSubheader)
                                .foregroundStyle(roleTint(resource.role))
                            Text(resource.path)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.onbiiPrimaryText)
                        }
                    }
                } label: {
                    Text("Resources")
                        .onbiiSubheaderStyle()
                }
            } footer: {
                if showsResources {
                    Text(
                        "The source is the original recording and cannot be "
                            + "regenerated. Everything else was derived from it."
                    )
                }
            }

            Section {
                if model.canTranscribe(bundle) {
                    transcribeControls
                }

                repairOffer

                ShareLink(item: bundle.url) {
                    Label("Share Object", systemImage: "square.and.arrow.up")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listRowBackground(Color.onbiiSurface)
        .scrollContentBackground(.hidden)
        .background(Color.onbiiBackground)
        .navigationTitle(bundle.manifest.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: bundle.manifest.objectID) {
            model.resolvePlaceNameIfNeeded(for: bundle)
            model.checkForRepairs(bundle)
        }
    }

    /// Offered, never done quietly.
    ///
    /// The object is saying something its own contents contradict — a duration
    /// the audio disproves, coordinates with no name. Correcting that changes
    /// what the object records about itself, so it is a person's call, and the
    /// offer says what is wrong rather than just "repair".
    @ViewBuilder
    private var repairOffer: some View {
        if let findings = model.repairFindings[bundle.manifest.objectID],
           let summary = findings.summary {
            Button {
                model.repair(bundle)
            } label: {
                Label("Correct What This Object Records", systemImage: "wrench.adjustable")
            }
            .disabled(model.isBusy)

            Text(
                summary + " Re-measures the preserved audio and resolves the "
                    + "coordinates. The recording itself is not touched."
            )
            .font(.caption)
            .foregroundStyle(.onbiiSecondaryText)
        }
    }

    /// Transcribe, with the language chosen here rather than in Settings.
    ///
    /// The button uses the default; the menu beside it transcribes in any other
    /// language without leaving the object. Which language a recording is in is
    /// a property of the recording, so someone who keeps notes in Dutch and
    /// English should not have to visit Settings between them.
    ///
    /// "Again" rather than a repeat of the same offer: a second run is a new
    /// generation, not a no-op, and the existing transcript is kept.
    @ViewBuilder
    private var transcribeControls: some View {
        let supersedes = model.wouldSupersedeTranscript(bundle)

        Button {
            model.transcribe(bundle)
        } label: {
            Label(
                supersedes
                    ? "Transcribe Again in \(model.selectedLanguageDisplayName)"
                    : "Transcribe in \(model.selectedLanguageDisplayName)",
                systemImage: supersedes ? "arrow.clockwise" : "text.viewfinder"
            )
        }
        .disabled(model.isBusy)

        Menu {
            ForEach(model.availableLanguages) { language in
                Button(
                    language.isInstalled
                        ? language.displayName
                        : "\(language.displayName) — download"
                ) {
                    model.transcribe(bundle, in: language.locale)
                }
            }
        } label: {
            Label("Transcribe in Another Language", systemImage: "globe")
        }
        .disabled(model.isBusy)

        if supersedes {
            Text(
                "A new transcript supersedes the current one. The current one is "
                    + "kept inside the object, with the language it was made in."
            )
            .font(.caption)
            .foregroundStyle(.onbiiSecondaryText)
        }
    }

    private var factRows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [
            ("Type", bundle.manifest.objectType),
            (
                "Created",
                bundle.manifest.createdAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
            ),
        ]

        if let location = model.locationDescription(for: bundle) {
            rows.append(("Location", location))
        }

        let applications = (bundle.manifest.sourceApplications ?? [])
            .map { $0.name ?? $0.bundleIdentifier }
        if !applications.isEmpty {
            rows.append(("Source apps", applications.joined(separator: ", ")))
        }

        rows.append(("Object ID", bundle.manifest.objectID.rawValue))
        return rows
    }

    private func roleLabel(_ role: OnbiiResource.Role) -> String {
        switch role {
        case .source: "Source"
        case .humanReadable: "Readable"
        case .derived: "Derived"
        case .attachment: "Attachment"
        }
    }

    /// The source is the thing that cannot be regenerated, so it is the only
    /// role that gets the accent.
    private func roleTint(_ role: OnbiiResource.Role) -> Color {
        switch role {
        case .source: .onbiiAccent
        case .humanReadable, .derived, .attachment: .onbiiSecondaryText
        }
    }
}
