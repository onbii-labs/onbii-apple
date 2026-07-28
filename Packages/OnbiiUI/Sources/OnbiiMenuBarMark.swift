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
    public init() {}

    public var body: some View {
        Image("OnbiiMenuBarMark", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }
}
