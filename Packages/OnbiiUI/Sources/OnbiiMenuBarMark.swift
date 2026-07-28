#if os(macOS)
import AppKit
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
public enum OnbiiMenuBarMark {
    /// The menu bar's own glyph size.
    public static let glyphSize: CGFloat = 18

    /// The mark at menu bar size, ready to hand to `MenuBarExtra`.
    ///
    /// Sized on the `NSImage` rather than with a SwiftUI `.frame`. A status item
    /// takes its width from the image's own `size`, and a `frame` modifier only
    /// constrains the layout SwiftUI does around it — which is why a 512 pt
    /// asset came out filling the menu bar however tightly it was framed.
    ///
    /// The instance is copied before being resized: `Bundle.image(forResource:)`
    /// hands back a cached image, and mutating it would resize it for every
    /// other caller too.
    public static func image(size: CGFloat = glyphSize) -> Image? {
        guard let cached = Bundle.module.image(forResource: "OnbiiMenuBarMark"),
              let copy = cached.copy() as? NSImage else {
            return nil
        }
        copy.size = NSSize(width: size, height: size)
        copy.isTemplate = true
        return Image(nsImage: copy)
    }
}
#endif
