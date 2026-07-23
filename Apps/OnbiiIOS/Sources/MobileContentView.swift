import SwiftUI
import UniformTypeIdentifiers

struct MobileContentView: View {
    @State private var model = MobileViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.isRecording {
                        Button(role: .destructive) {
                            model.stopRecording()
                        } label: {
                            Label(
                                "Stop Recording \(model.durationText)",
                                systemImage: "stop.circle.fill"
                            )
                            .monospacedDigit()
                        }
                    } else {
                        Button {
                            model.startRecording()
                        } label: {
                            Label("Record Audio", systemImage: "record.circle")
                        }
                        .disabled(model.isBusy)
                    }

                    Button {
                        model.showsImporter = true
                    } label: {
                        Label("Import Audio from Files", systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.isBusy)
                } header: {
                    Text("Capture")
                } footer: {
                    Text(
                        "Objects are stored locally in Files under "
                            + "On My iPhone → Onbii → Onbii Archive."
                    )
                }

                statusSection

                Section("Objects") {
                    if model.objects.isEmpty {
                        ContentUnavailableView(
                            "No Onbii Objects",
                            systemImage: "archivebox",
                            description: Text("Record or import audio to create one.")
                        )
                    } else {
                        ForEach(model.objects, id: \.manifest.objectID) { bundle in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bundle.manifest.title)
                                    Text(
                                        bundle.manifest.createdAt.formatted(
                                            date: .abbreviated,
                                            time: .shortened
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                ShareLink(item: bundle.url) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Onbii")
        }
        .fileImporter(
            isPresented: $model.showsImporter,
            allowedContentTypes: [.audio]
        ) { result in
            model.importAudio(result)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .preparing:
            Section {
                Label("Preparing microphone…", systemImage: "waveform")
            }
        case .recording:
            Section {
                Label(
                    "Recording is visibly active.",
                    systemImage: "record.circle.fill"
                )
                .foregroundStyle(.red)
            }
        case .preserving:
            Section {
                HStack {
                    ProgressView()
                    Text("Preserving the original recording…")
                }
            }
        case .completed(let filename):
            Section {
                Label(
                    "\(filename) is safely stored.",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}
