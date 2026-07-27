import SwiftUI

/// The Onbii mark, at a size the caller chooses.
///
/// The artwork carries its own dark field, so it reads correctly on a light and
/// a dark background without a second variant. It is decorative wherever it is
/// used here — the surrounding copy always says what the screen is — so it is
/// hidden from assistive technology rather than given a redundant label.
public struct OnbiiBrandMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 88) {
        self.size = size
    }

    public var body: some View {
        Image("OnbiiMark", bundle: .module)
            // Never let the system template this: an alpha or low-colour brand
            // image rendered as a mask comes out flat white.
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: size * OnbiiTheme.Radius.markFraction,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)
    }
}

#Preview("Brand mark") {
    HStack(spacing: OnbiiTheme.Spacing.l) {
        OnbiiBrandMark(size: 44)
        OnbiiBrandMark(size: 88)
        OnbiiBrandMark(size: 128)
    }
    .padding(OnbiiTheme.Spacing.xl)
    .background(Color.onbiiBackground)
}
