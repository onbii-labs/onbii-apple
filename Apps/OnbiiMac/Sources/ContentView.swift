import OnbiiUI
import SwiftUI

/// The window shell: the archive on the left, one object on the right, capture
/// in the toolbar. The window is a view over the person's folder — everything
/// it shows is read back from there, and nothing it shows lives only here.
struct ContentView: View {
    @Bindable var model: ImportViewModel

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
