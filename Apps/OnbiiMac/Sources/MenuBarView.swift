import OnbiiArchive
import OnbiiUI
import SwiftUI

/// The always-ready surface: capture without finding a window.
///
/// The roadmap's phrase is "always at the ready", and the point is that starting
/// a recording should never require locating an app first. A conversation does
/// not wait while somebody hunts through Mission Control, and the first field
/// test's most valuable recordings were the ones nobody planned.
///
/// It is a view over the same view model the window uses, not a second app and
/// not a second source of truth. There is one archive access, one set of
/// security-scoped bookmarks, and one answer to what the app is doing.
struct MenuBarView: View {
    @Bindable var model: ImportViewModel
    @Environment(\.openWindow) private var openWindow

    /// How many recent objects to offer. Enough to reach what was just recorded,
    /// far short of being a second object list — that is the window's job, and
    /// duplicating it here would mean two places to keep honest.
    private static let recentCount = 5

    var body: some View {
        Group {
            if model.archiveURL == nil {
                Button("Choose Archive…") { model.chooseArchive() }
                Divider()
            } else {
                captureControls
                Divider()
                recentObjects
                Divider()
            }

            Button("Open Onbii") { showWindow() }
                .keyboardShortcut("o")

            Button("Quit Onbii") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    @ViewBuilder
    private var captureControls: some View {
        if model.isCapturing {
            // The elapsed time, because an always-ready recorder that cannot be
            // seen is exactly the thing Milestone 1.6 exists to prevent.
            Text("Recording — \(model.captureDurationText)")
            Button("Stop and Preserve") { model.stopCapture() }
                .keyboardShortcut("r")
        } else if model.isBusy {
            Text(busyDescription)
        } else {
            Button("Record Microphone") { model.startCapture() }
                .keyboardShortcut("r")
            Button("Record Call (System Audio + Microphone)") {
                model.startCallCapture()
            }
            Button("Import Audio…") { model.importAudio() }
        }
    }

    private var busyDescription: String {
        switch model.state {
        case let .transcribing(message): message
        case let .importing(filename): "Preserving \(filename)…"
        case .preparingCapture: "Preparing audio capture…"
        default: "Working…"
        }
    }

    @ViewBuilder
    private var recentObjects: some View {
        if model.objects.isEmpty {
            Text("Nothing preserved yet")
        } else {
            ForEach(model.objects.prefix(Self.recentCount), id: \.manifest.objectID) {
                bundle in
                Button {
                    model.selectedObjectID = bundle.manifest.objectID
                    showWindow()
                } label: {
                    Text(bundle.manifest.title)
                }
            }
        }
    }

    /// Brings the window back, creating it if closing it left none.
    ///
    /// Closing the window must not be the same as quitting — that is what makes
    /// this "always at the ready" rather than "ready while a window happens to
    /// be open".
    private func showWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let existing = NSApplication.shared.windows.first(where: {
            $0.canBecomeMain && $0.contentView != nil
        }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: OnbiiMacApp.mainWindowID)
        }
    }
}
