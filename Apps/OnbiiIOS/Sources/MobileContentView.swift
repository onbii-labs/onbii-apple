import OnbiiTranscription
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
                    Text("New objects are stored in \(model.archiveDescription).")
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
                        if !model.availableLanguages.isEmpty {
                            Picker(
                                "Transcription language",
                                selection: Bindable(model).selectedLanguageID
                            ) {
                                ForEach(model.availableLanguages) { language in
                                    Text(
                                        language.isInstalled
                                            ? language.displayName
                                            : "\(language.displayName) — download"
                                    )
                                    .tag(language.id)
                                }
                            }
                        }
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
                                if !model.hasTranscript(bundle) {
                                    Button {
                                        model.transcribe(bundle)
                                    } label: {
                                        Image(systemName: "text.viewfinder")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(model.isBusy)
                                }
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
        .onReceive(
            NotificationCenter.default.publisher(
                for: .onbiiWatchRecordingReceived
            )
        ) { notification in
            model.watchRecordingReceived(notification)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch model.state {
        case .preparingArchive:
            Section {
                HStack {
                    ProgressView()
                    Text("Connecting to iCloud Drive…")
                }
            }
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
        case .transcribing(let message):
            Section {
                HStack {
                    ProgressView()
                    Text(message)
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
