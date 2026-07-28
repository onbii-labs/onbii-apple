import SwiftUI

/// The Watch app sits on a full Forest field rather than the system's black.
///
/// That is what carries the identity here: with the field behind it, the mark
/// simply belongs to the screen, the way it does inside the app icon. The Watch
/// has one job and one screen, so a single brand surface costs nothing in
/// legibility — every foreground colour below is checked against Forest.
///
/// The accent is Champagne, as on every other platform.
///
/// It is worth knowing why that is not obvious. Champagne is a 68%-luminance
/// near-neutral, and the eye resolves hue far worse than luminance at fine
/// detail, so it only reads as champagne across a reasonably large area. On a
/// watch that rules it out for hairlines — but a button pill and a solid mark
/// are large areas, and there it reads correctly. Confirmed on a real device
/// with a swatch drawn beside the mark.
///
/// So: keep Champagne on anything with mass, and never rely on it for thin
/// strokes here. The Watch-specific mark exists for exactly that reason.
struct WatchContentView: View {
    @State private var model = WatchViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            content
                // The sanctioned watchOS way to own the whole surface. It also
                // puts the Forest field behind the navigation chrome, which is
                // where the system draws the clock.
                .containerBackground(Color("OnbiiForest"), for: .navigation)
        }
        // Becoming active is the first moment this app can tell whether a
        // recording it believes is running actually survived being in the
        // background. Nothing runs while watchOS has the process suspended, so
        // there is no earlier honest opportunity.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.verifyRecordingIsStillRunning()
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                if model.state == .stopping {
                    ProgressView()
                        .controlSize(.large)
                    Text("Saving on Watch…")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                } else if model.isRecording {
                    // A red record indicator is the platform convention for an
                    // active recording, not a brand decision. It stays red.
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.red)
                } else {
                    WatchBrandMark()
                }

                if model.isRecording || model.state == .stopping {
                    Text(model.durationText)
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(model.isRecording ? Color.red : Color.accentColor)
                }

                Button {
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
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(WatchPrimaryButtonStyle(isDestructive: model.isRecording))
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
                    // Full accent, not a faded one — 8.8:1 on Forest. At this
                    // size it reads near-white, which is right for secondary
                    // text; the brand is carried by the mark and the button.
                    .foregroundStyle(Color.accentColor)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

/// The Onbii mark, exactly the artwork the Mac and iPhone use.
///
/// It is the **opaque** artwork, not a transparent cut-out, and it needs no
/// cut-out: the field is exactly the Forest token, so the square dissolves into
/// the screen. A transparent variant was tried and reverted — it added an alpha
/// channel and dropped the colour profile for no benefit.
///
/// It is drawn large (120pt) on purpose. The strokes are ~10px in the 512px
/// source, so at 82pt they landed at 3.2 device pixels and the Champagne read
/// as white; at 120pt they are ~4.7. Do not shrink this without checking how
/// the mark reads on a real Watch — it is not something a Simulator screenshot
/// or a colour measurement will tell you.
private struct WatchBrandMark: View {
    var body: some View {
        Image("OnbiiMark")
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 120, height: 120)
            .accessibilityHidden(true)
    }
}

/// Champagne fill with Graphite on top — 8.8:1 against Forest, 13.1:1 label on
/// fill.
///
/// The system prominent style would draw its label white, which against a light
/// accent is unreadable. This mirrors `OnbiiProminentButtonStyle`
/// in `OnbiiUI` — duplicated deliberately, because the Watch takes no
/// dependency on that package (it would drag `OnbiiArchive` onto a device that
/// has no business reading or writing bundles).
private struct WatchPrimaryButtonStyle: ButtonStyle {
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        // Named `Content` rather than `Body`: a nested `Body` would collide with
        // ButtonStyle's associated type.
        Content(configuration: configuration, isDestructive: isDestructive)
    }

    private struct Content: View {
        let configuration: ButtonStyleConfiguration
        let isDestructive: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(labelColor)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(fill, in: Capsule())
                .contentShape(Capsule())
                .opacity(configuration.isPressed ? 0.8 : 1)
        }

        /// Disabled lifts the Forest field with a trace of the accent rather
        /// than fading the fill. A faded warm fill over Forest goes muddy
        /// brown; a neutral white lift reads cold against the warm field.
        private var fill: AnyShapeStyle {
            guard isEnabled else { return AnyShapeStyle(Color.accentColor.opacity(0.18)) }
            return AnyShapeStyle(isDestructive ? Color.red : Color.accentColor)
        }

        private var labelColor: Color {
            guard isEnabled else { return Color.accentColor.opacity(0.55) }
            return isDestructive ? .white : Color("OnbiiOnAccent")
        }
    }
}
