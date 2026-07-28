import SwiftUI

/// The Onbii mark for a macOS menu bar item.
///
/// A separate asset from ``OnbiiBrandMark`` rather than a variant of it, because
/// the two need opposite rendering. The brand mark carries its own Forest field
/// and must never be templated; a menu bar image must be, so the system can
/// paint it black on a light bar, white on a dark one, and invert it while the
/// menu is open.
///
/// See `docs/architecture/visual-identity.md` for the artwork spec.
public struct OnbiiMenuBarMark: View {
    /// The menu bar's own glyph size. A custom image has to say this: unlike an
    /// SF Symbol it carries no intrinsic point size, so `resizable()` alone
    /// makes it fill whatever the bar offers.
    public static let glyphSize: CGFloat = 18

    private let size: CGFloat

    public init(size: CGFloat = OnbiiMenuBarMark.glyphSize) {
        self.size = size
    }

    public var body: some View {
        Image("OnbiiMenuBarMark", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
