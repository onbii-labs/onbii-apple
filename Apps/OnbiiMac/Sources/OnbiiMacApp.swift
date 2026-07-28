import OnbiiUI
import SwiftUI
import UserNotifications

@main
struct OnbiiMacApp: App {
    /// The model lives here rather than in `ContentView` because the Settings
    /// scene is a sibling of the window, not a child of it, and both need the
    /// same archive.
    @State private var model = ImportViewModel()
    @State private var suggestions: CaptureSuggestionDelegate

    /// Named so the menu-bar item can reopen the window after it was closed.
    static let mainWindowID = "onbii-main"

    init() {
        let model = ImportViewModel()
        let suggestions = CaptureSuggestionDelegate { model.startCapture() }
        _model = State(initialValue: model)
        _suggestions = State(initialValue: suggestions)
        // Both at launch, because a suggestion can arrive before any window has
        // been opened — which is the whole point of it.
        OnbiiNotifier.registerCaptureSuggestion()
        UNUserNotificationCenter.current().delegate = suggestions
    }

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
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

        // Always at the ready: capture without finding a window first.
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            // The recording state has to be visible from the menu bar itself,
            // not only once the menu is opened. An app that is recording and
            // does not look like it is the failure Milestone 1.6 is named for.
            Image(
                systemName: model.isCapturing
                    ? "record.circle.fill"
                    : "waveform.circle"
            )
        }

        Settings {
            MacSettingsView(model: model)
        }
    }
}
