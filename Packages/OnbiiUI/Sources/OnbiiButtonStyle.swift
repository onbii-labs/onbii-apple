import SwiftUI

/// The filled brand button: accent fill, legible ink on top.
///
/// This exists rather than `.buttonStyle(.borderedProminent).tint(.onbiiAccent)`
/// because that combination is actively broken with this palette. The system
/// prominent style assumes a dark, saturated tint and draws its label white —
/// white on dark-mode Champagne is 1.4:1, which is unreadable, and white on
/// light-mode Copper is 3.2:1, below AA for body text. Pairing the fill with
/// ``Color/onbiiOnAccent`` gives 13.1:1 and 5.1:1.
///
/// The label is not stretched: add `.frame(maxWidth: .infinity)` to it where a
/// full-width control is wanted.
public struct OnbiiProminentButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        // Named `Content` rather than `Body`: a nested `Body` would collide with
        // ButtonStyle's associated type. It is a view so it can read
        // `\.isEnabled`, which a ButtonStyle cannot.
        Content(configuration: configuration)
    }

    private struct Content: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(isEnabled ? .onbiiOnAccent : .onbiiSecondaryText)
                .padding(.vertical, OnbiiTheme.Spacing.m)
                .padding(.horizontal, OnbiiTheme.Spacing.l)
                .background(fill, in: Capsule())
                .contentShape(Capsule())
        }

        /// Disabled swaps the fill rather than fading it. Fading Champagne to
        /// 40% over a dark background gives a muddy brown with an illegible
        /// label; a muted surface with secondary text stays readable.
        private var fill: Color {
            guard isEnabled else { return .onbiiElevated }
            return configuration.isPressed ? .onbiiAccentHover : .onbiiAccent
        }
    }
}

public extension ButtonStyle where Self == OnbiiProminentButtonStyle {
    static var onbiiProminent: Self { .init() }
}

#Preview("Prominent button") {
    VStack(spacing: OnbiiTheme.Spacing.l) {
        Button("Record Audio") {}
            .buttonStyle(.onbiiProminent)
        Button("Disabled") {}
            .buttonStyle(.onbiiProminent)
            .disabled(true)
    }
    .padding(OnbiiTheme.Spacing.xl)
    .background(Color.onbiiBackground)
}
