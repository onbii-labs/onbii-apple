import SwiftUI

@main
struct OnbiiMacApp: App {
    /// The model lives here rather than in `ContentView` because the Settings
    /// scene is a sibling of the window, not a child of it, and both need the
    /// same archive.
    @State private var model = ImportViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1040, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Audio…") {
                    model.importAudio()
                }
                .keyboardShortcut("i")
                .disabled(model.archiveURL == nil || model.isBusy)

                Divider()

                Button("Refresh Archive") {
                    model.reloadObjects()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.archiveURL == nil)
            }
        }

        Settings {
            MacSettingsView(model: model)
        }
    }
}
