import OnbiiUI
import SwiftUI
import UniformTypeIdentifiers

/// The iPhone home: what is in the archive, what state each object is in, and
/// the two ways to add to it.
struct MobileContentView: View {
    @State private var model = MobileViewModel()
    @State private var showsSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if model.objects.isEmpty, !model.isBusy {
                    OnbiiEmptyState(
                        title: "Nothing preserved yet.",
                        message: "Record a conversation or import audio you "
                            + "already have. The original is kept, never replaced."
                    ) {
                        Button {
                            model.startRecording()
                        } label: {
                            Label("Record Audio", systemImage: "record.circle")
                        }
                        .buttonStyle(.onbiiProminent)
                    }
                } else {
                    objectList
                }
            }
            .background(Color.onbiiBackground)
            .navigationTitle("Onbii")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                captureBar
            }
        }
        .tint(.onbiiAccent)
        // Becoming active is the first moment this app can tell whether a
        // recording it believes is running survived the screen locking. Nothing
        // runs while iOS has the process suspended, so there is no earlier
        // honest opportunity.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.verifyRecordingIsStillRunning()
            }
        }
        .sheet(isPresented: $showsSettings) {
            MobileSettingsView(model: model)
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

    private var objectList: some View {
        List {
            statusSection

            Section {
                ForEach(model.objects, id: \.manifest.objectID) { bundle in
                    NavigationLink {
                        MobileObjectDetailView(bundle: bundle, model: model)
                    } label: {
                        MobileObjectRow(
                            bundle: bundle,
                            indicator: model.indicator(for: bundle)
                        )
                    }
                    .listRowBackground(Color.onbiiSurface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        ShareLink(item: bundle.url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            } header: {
                Text("Objects")
                    .onbiiSubheaderStyle()
            } footer: {
                Text("Stored in \(model.archiveDescription).")
            }
        }
        .listStyle(.insetGrouped)
        // The palette carries the brand rather than the system's grey: Ivory or
        // Graphite behind, cards on top.
        .scrollContentBackground(.hidden)
        .background(Color.onbiiBackground)
        .refreshable {
            model.reloadObjects()
        }
    }

    /// Capture stays reachable from anywhere in the list rather than scrolling
    /// away above the objects.
    private var captureBar: some View {
        HStack(spacing: OnbiiTheme.Spacing.m) {
            if model.isRecording {
                // Destructive keeps the system red fill, where white is correct
                // and the platform convention for stopping a recording holds.
                Button(role: .destructive) {
                    model.stopRecording()
                } label: {
                    Label(
                        "Stop \(model.durationText)",
                        systemImage: "stop.circle.fill"
                    )
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    model.startRecording()
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.onbiiProminent)
                .disabled(model.isBusy)

                Button {
                    model.showsImporter = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.isBusy)
            }
        }
        .padding(.horizontal, OnbiiTheme.Spacing.l)
        .padding(.vertical, OnbiiTheme.Spacing.m)
        .background(.bar)
    }

    @ViewBuilder
    private var statusSection: some View {
        switch model.state {
        case .idle:
            EmptyView()

        case .preparingArchive:
            statusRow {
                ProgressView()
                Text("Connecting to iCloud Drive…")
            }

        case .preparing:
            statusRow {
                ProgressView()
                Text("Preparing microphone…")
            }

        case .recording:
            statusRow {
                // A red record dot is a platform convention, not a brand
                // decision. It stays red.
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                Text("Recording is visibly active.")
            }

        case .preserving:
            statusRow {
                ProgressView()
                Text("Preserving the original recording…")
            }

        case let .transcribing(message):
            statusRow {
                ProgressView()
                Text(message)
            }

        case let .completed(filename, warning):
            statusRow {
                if let warning {
                    // Preserved, but not as expected. The source is safe; the
                    // app saying so out loud is the point.
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.onbiiWarning)
                    Text("\(filename): \(warning)")
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.onbiiSuccess)
                    Text("\(filename) is safely stored.")
                }
            }

        case let .failed(message):
            statusRow {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.onbiiError)
                Text(message)
            }
        }
    }

    private func statusRow(@ViewBuilder content: () -> some View) -> some View {
        Section {
            HStack(spacing: OnbiiTheme.Spacing.s) {
                content()
            }
            .listRowBackground(Color.onbiiSurface)
        }
    }
}

#Preview("Light") {
    MobileContentView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MobileContentView()
        .preferredColorScheme(.dark)
}
