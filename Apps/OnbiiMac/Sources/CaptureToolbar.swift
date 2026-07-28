import OnbiiUI
import SwiftUI

/// Capture lives in the toolbar so the window's body can be about the archive.
/// Recording is always an explicit action here — there is no path through this
/// app that starts a recording the person did not press.
struct CaptureToolbar: ToolbarContent {
    @Bindable var model: ImportViewModel

    private var canStart: Bool {
        model.archiveURL != nil && !model.isBusy
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .status) {
            StatusPill(model: model)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if model.isCapturing, model.captureKind == .microphone {
                Button {
                    model.stopCapture()
                } label: {
                    Label(
                        "Stop \(model.captureDurationText)",
                        systemImage: "stop.circle.fill"
                    )
                }
                .tint(.red)
                .help("Stop recording and preserve it")
            } else {
                Button {
                    model.startCapture()
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .disabled(!canStart)
                .help("Record from the microphone")
            }

            if model.isCapturing, model.captureKind == .call {
                Button {
                    model.stopCapture()
                } label: {
                    Label(
                        "Stop Call \(model.captureDurationText)",
                        systemImage: "stop.circle.fill"
                    )
                }
                .tint(.red)
                .help("Stop the call capture and preserve both tracks")
            } else {
                Button {
                    model.startCallCapture()
                } label: {
                    Label("Record Call", systemImage: "person.2.wave.2")
                }
                .disabled(!canStart)
                .help(
                    "Record system output and the microphone as separate sources"
                )
            }

            Button {
                model.importAudio()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .disabled(!canStart)
            .help("Preserve an audio file you already have")
        }
    }
}

/// The nine app states, compressed into one line the person can ignore when
/// nothing is happening.
private struct StatusPill: View {
    @Bindable var model: ImportViewModel

    var body: some View {
        switch model.state {
        case .idle:
            EmptyView()

        case let .importing(filename):
            pill {
                ProgressView().controlSize(.small)
                Text("Preserving \(filename)…")
            }

        case .preparingCapture:
            pill {
                ProgressView().controlSize(.small)
                Text("Preparing audio capture…")
            }

        case .capturing:
            pill {
                // A red record dot is a platform convention, not a brand
                // decision. It stays red.
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                Text(model.captureDurationText)
                    .monospacedDigit()
                Text(captureDescription)
                    .foregroundStyle(.onbiiSecondaryText)
            }

        case let .transcribing(message):
            pill {
                ProgressView().controlSize(.small)
                Text(message)
            }

        case let .completed(bundleURL, warning):
            pill {
                if let warning {
                    // Preserved, but not as expected. The source is safe; the
                    // app saying so out loud is the point.
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.onbiiWarning)
                    Text("\(bundleURL.lastPathComponent): \(warning)")
                        .textSelection(.enabled)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.onbiiSuccess)
                    Text("\(bundleURL.lastPathComponent) is safely in your archive.")
                }
            }

        case let .transcribed(bundleURL):
            pill {
                Image(systemName: "text.badge.checkmark")
                    .foregroundStyle(.onbiiSuccess)
                Text("\(bundleURL.lastPathComponent) now has an on-device transcript.")
            }

        case let .foundNoSpeech(_, message):
            pill {
                // Not the error triangle. Nothing is broken, and the icon is
                // the first thing read.
                Image(systemName: "waveform.slash")
                    .foregroundStyle(.onbiiSecondaryText)
                Text(message)
                    .textSelection(.enabled)
            }

        case let .opened(bundleURL):
            pill {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.onbiiSecondaryText)
                Text("\(bundleURL.lastPathComponent) is open for inspection.")
            }

        case let .failed(message):
            pill {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.onbiiError)
                Text(message)
                    .textSelection(.enabled)
            }
        }
    }

    private func pill(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: OnbiiTheme.Spacing.s) {
            content()
        }
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, OnbiiTheme.Spacing.m)
        .padding(.vertical, OnbiiTheme.Spacing.xs)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .frame(maxWidth: 520)
    }

    private var captureDescription: String {
        switch model.captureKind {
        case .microphone:
            "Microphone capture is visibly active."
        case .call:
            "System output and microphone capture are visibly active."
        case nil:
            "Audio capture is visibly active."
        }
    }
}
