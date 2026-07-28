import OnbiiUI
import SwiftUI

/// The window shell: the archive on the left, one object on the right, capture
/// in the toolbar. The window is a view over the person's folder — everything
/// it shows is read back from there, and nothing it shows lives only here.
struct ContentView: View {
    @Bindable var model: ImportViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            ObjectListView(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
        } detail: {
            if let bundle = model.selectedBundle {
                ObjectDetailView(bundle: bundle, model: model)
            } else {
                emptyDetail
                    .background(Color.onbiiBackground)
            }
        }
        .navigationTitle("Onbii")
        .navigationSubtitle(model.archiveShortName)
        .toolbar {
            CaptureToolbar(model: model)
        }
        .onOpenURL { url in
            model.openBundle(url)
        }
        .task {
            model.reloadObjects()
        }
        // An object can arrive while this window sits open — from a walk, over
        // iCloud, or because someone moved a folder in Finder. Reading the
        // archive once at launch and then presenting that list as *the archive*
        // is how a recording made an hour earlier was missing from it (field
        // test 2). Coming back to the window is the first honest moment to look
        // again, and it is what the iPhone already does.
        //
        // It is not the whole answer: a window left in front for an hour still
        // will not notice. Watching an iCloud container properly means an
        // `NSMetadataQuery`, which belongs with Milestone 1.5's always-ready
        // strand rather than here.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reloadObjects()
            }
        }
    }

    @ViewBuilder
    private var emptyDetail: some View {
        if model.archiveURL == nil {
            OnbiiEmptyState(
                title: "Choose where your knowledge lives.",
                message: "Onbii writes ordinary folders you own. Pick one, and "
                    + "everything you record or import is preserved there."
            ) {
                Button("Choose Archive…") {
                    model.chooseArchive()
                }
                .buttonStyle(.onbiiProminent)
            }
        } else if model.objects.isEmpty {
            OnbiiEmptyState(
                title: "Nothing preserved yet.",
                message: "Record a conversation or import audio you already "
                    + "have. The original is kept, never replaced."
            ) {
                Button("Import Audio…") {
                    model.importAudio()
                }
                .buttonStyle(.onbiiProminent)
                .disabled(model.isBusy)
            }
        } else {
            OnbiiEmptyState(
                title: "Your knowledge, preserved.",
                message: "Select an object to inspect what it holds."
            )
        }
    }
}

#Preview("Light") {
    ContentView(model: ImportViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView(model: ImportViewModel())
        .preferredColorScheme(.dark)
}
