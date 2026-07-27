import OnbiiArchive
import OnbiiCore
import OnbiiUI
import SwiftUI

/// What one object holds. Sources are named as sources and derived artefacts as
/// derived, because the difference is the whole point: the recording is the
/// irreplaceable truth and everything else can be made again.
struct MobileObjectDetailView: View {
    let bundle: OnbiiBundle
    @Bindable var model: MobileViewModel

    var body: some View {
        List {
            Section {
                Text(bundle.manifest.title)
                    .font(.onbiiSectionTitle)
                    .foregroundStyle(.onbiiPrimaryText)
                OnbiiStatusBadge(model.indicator(for: bundle))
            }

            Section {
                ForEach(factRows, id: \.label) { row in
                    LabeledContent(row.label) {
                        Text(row.value)
                            .foregroundStyle(.onbiiSecondaryText)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("Details")
                    .onbiiSubheaderStyle()
            }

            Section {
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
            } header: {
                Text("Resources")
                    .onbiiSubheaderStyle()
            } footer: {
                Text(
                    "The source is the original recording and cannot be "
                        + "regenerated. Everything else was derived from it."
                )
            }

            Section {
                if model.canTranscribe(bundle) {
                    Button {
                        model.transcribe(bundle)
                    } label: {
                        Label("Transcribe On Device", systemImage: "text.viewfinder")
                    }
                    .disabled(model.isBusy)
                }

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
            rows.append((
                "Location",
                location.name
                    ?? String(
                        format: "%.4f, %.4f",
                        location.latitude,
                        location.longitude
                    )
            ))
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
