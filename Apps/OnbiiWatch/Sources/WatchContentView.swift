import SwiftUI

struct WatchContentView: View {
    @State private var model = WatchViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if model.state == .stopping {
                    ProgressView()
                        .controlSize(.large)
                    Text("Saving on Watch…")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                } else {
                    Image(
                        systemName: model.isRecording
                            ? "waveform.circle.fill"
                            : "waveform.circle"
                    )
                    .font(.system(size: 42))
                    .foregroundStyle(
                        model.isRecording ? Color.red : Color.accentColor
                    )
                }

                if model.isRecording || model.state == .stopping {
                    Text(model.durationText)
                        .font(.title2.monospacedDigit())
                }

                Button(role: model.isRecording ? .destructive : nil) {
                    if model.isRecording {
                        model.stopRecording()
                    } else {
                        model.startRecording()
                    }
                } label: {
                    Label(
                        model.primaryActionTitle,
                        systemImage: model.primaryActionSystemImage
                    )
                }
                .disabled(!model.canUsePrimaryAction)

                if model.isTransferInProgress && model.state != .stopping {
                    ProgressView()
                }

                if model.canRetryTransfer {
                    Button("Retry Transfer") {
                        model.retryTransfer()
                    }
                }

                Text(model.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}
