import OnbiiArchive
import OnbiiCore
import OnbiiUI
import SwiftUI

/// What one object holds. Sources are named as sources and derived artefacts as
/// derived, because the difference is the whole point: the recording is the
/// irreplaceable truth and everything else can be made again.
struct ObjectDetailView: View {
    let bundle: OnbiiBundle
    @Bindable var model: ImportViewModel

    /// Folded away by default. The transcript is what the pane is for; the
    /// metadata answers occasional questions and should not crowd it out.
    @State private var showsDetails = false
    @State private var showsResources = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OnbiiTheme.Spacing.l) {
                header

                if bundle.manifest.hasTranscript {
                    Divider().overlay(Color.onbiiDivider)
                    transcript
                }

                Divider().overlay(Color.onbiiDivider)
                fold("Details", isExpanded: $showsDetails) { facts }
                fold("Resources", isExpanded: $showsResources) { resources }
            }
            .padding(OnbiiTheme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.onbiiBackground)
        .id(bundle.manifest.objectID)
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: OnbiiTheme.Spacing.s) {
            Text("Transcript")
                .onbiiSubheaderStyle()
            // Not scrolling: this pane already does, and nesting the two would
            // trap the scroll wheel over the transcript.
            OnbiiTranscriptView(
                bundle: bundle,
                accessedThrough: model.archiveURL,
                scrolls: false
            )
        }
    }

    private func fold(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> some View
    ) -> some View {
        // Built before the escaping closure so the builder need not escape.
        let folded = content()
            .padding(.top, OnbiiTheme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)

        return DisclosureGroup(isExpanded: isExpanded) {
            folded
        } label: {
            Text(title)
                .onbiiSubheaderStyle()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OnbiiTheme.Spacing.m) {
            Text(bundle.manifest.title)
                .font(.onbiiSectionTitle)
                .foregroundStyle(.onbiiPrimaryText)
                .textSelection(.enabled)

            HStack(spacing: OnbiiTheme.Spacing.m) {
                OnbiiStatusBadge(model.indicator(for: bundle))

                Spacer()

                if model.canTranscribeSelectedBundle,
                   bundle.manifest.objectID == model.selectedObjectID {
                    Button("Transcribe On Device") {
                        model.transcribeSelectedBundle()
                    }
                    .disabled(model.isBusy)
                }

                Button("Reveal in Finder") {
                    model.reveal(bundle)
                }
            }
        }
    }

    private var facts: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: OnbiiTheme.Spacing.l,
            verticalSpacing: 8
        ) {
            ForEach(factRows, id: \.label) { row in
                GridRow {
                    Text(row.label)
                        .foregroundStyle(.onbiiSecondaryText)
                    Text(row.value)
                        .foregroundStyle(.onbiiPrimaryText)
                        .textSelection(.enabled)
                }
            }
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

        if let location = bundle.manifest.location {
            rows.append(("Location", location.name ?? coordinates(of: location)))
        }

        let applications = (bundle.manifest.sourceApplications ?? [])
            .map { $0.name ?? $0.bundleIdentifier }
        if !applications.isEmpty {
            rows.append(("Source apps", applications.joined(separator: ", ")))
        }

        rows.append(("Object ID", bundle.manifest.objectID.rawValue))
        return rows
    }

    private func coordinates(of location: OnbiiLocation) -> String {
        String(format: "%.4f, %.4f", location.latitude, location.longitude)
    }

    private var resources: some View {
        VStack(alignment: .leading, spacing: OnbiiTheme.Spacing.s) {
            ForEach(bundle.manifest.resources, id: \.id) { resource in
                HStack(spacing: OnbiiTheme.Spacing.m) {
                    Text(roleLabel(resource.role))
                        .font(.onbiiSubheader)
                        .foregroundStyle(roleTint(resource.role))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            roleTint(resource.role).opacity(0.12),
                            in: RoundedRectangle(
                                cornerRadius: OnbiiTheme.Radius.badge,
                                style: .continuous
                            )
                        )
                        .frame(width: 110, alignment: .leading)

                    Text(resource.path)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.onbiiPrimaryText)
                        .textSelection(.enabled)

                    Spacer()
                }
            }
        }
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
