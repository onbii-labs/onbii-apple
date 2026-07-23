import OnbiiArchive
import SwiftUI

struct ContentView: View {
    @State private var model = ImportViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Onbii")
                    .font(.largeTitle.weight(.semibold))
                Text("Preserve a recording as a knowledge object you control.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Archive") {
                HStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .foregroundStyle(.secondary)

                    Text(model.archiveDisplayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(model.archiveURL == nil ? "Choose…" : "Change…") {
                        model.chooseArchive()
                    }
                    .disabled(model.isImporting)
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 12) {
                Button {
                    model.importAudio()
                } label: {
                    Label("Import Audio", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.archiveURL == nil || model.isImporting)

                Button {
                    // Live capture is intentionally a separate acquisition path.
                } label: {
                    Label("Start Capture", systemImage: "record.circle")
                }
                .controlSize(.large)
                .disabled(true)

                if model.isImporting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            statusView

            if let bundle = model.selectedBundle {
                BundleInspectorView(bundle: bundle) {
                    model.revealSelectedBundle()
                }
            }

            Spacer()
        }
        .padding(28)
        .onOpenURL { url in
            model.openBundle(url)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.state {
        case .idle:
            Text("Choose an archive folder, then import an existing audio file.")
                .foregroundStyle(.secondary)

        case .importing(let filename):
            Label("Preserving \(filename)…", systemImage: "waveform")
                .foregroundStyle(.secondary)

        case .completed(let bundleURL):
            HStack {
                Label(
                    "\(bundleURL.lastPathComponent) is safely in your archive.",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)

                Spacer()

                Button("Reveal in Finder") {
                    model.revealSelectedBundle()
                }
            }

        case .opened(let bundleURL):
            Label(
                "\(bundleURL.lastPathComponent) is open for inspection.",
                systemImage: "doc.text.magnifyingglass"
            )
            .foregroundStyle(.secondary)

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }
}

private struct BundleInspectorView: View {
    let bundle: OnbiiBundle
    let reveal: () -> Void

    var body: some View {
        GroupBox("Knowledge Object") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(bundle.manifest.title)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("Reveal in Finder", action: reveal)
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Type")
                            .foregroundStyle(.secondary)
                        Text(bundle.manifest.objectType)
                    }
                    GridRow {
                        Text("Created")
                            .foregroundStyle(.secondary)
                        Text(
                            bundle.manifest.createdAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                    }
                    GridRow {
                        Text("Object ID")
                            .foregroundStyle(.secondary)
                        Text(bundle.manifest.objectID.rawValue)
                            .textSelection(.enabled)
                    }
                }

                Divider()

                Text("Resources")
                    .font(.headline)

                ForEach(bundle.manifest.resources, id: \.id) { resource in
                    HStack(spacing: 10) {
                        Text(resource.role.rawValue.capitalized)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())

                        Text(resource.path)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
