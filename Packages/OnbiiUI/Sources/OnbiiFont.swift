import CoreText
import SwiftUI

/// The Onbii display face.
///
/// Only the display serif is embedded. Body text, controls, labels and
/// navigation titles stay on the system font: the brand guidelines call the
/// geometric sans "the system font bridge" to SF Pro, and a custom face in a
/// system navigation bar reads as a bug rather than as brand. Prata appears in
/// *content* — an empty-state hero, an object's title — never in chrome.
public enum OnbiiFontFamily {
    /// The PostScript name inside `Prata-Regular.ttf`, which is what
    /// `Font.custom` matches on.
    public static let display = "Prata-Regular"

    /// Registered once per process, lazily, the first time any brand font is
    /// asked for.
    ///
    /// Every accessor below reads this before building a `Font`, so it is not
    /// possible to render Prata before it has been registered — which is the
    /// usual failure of runtime font registration. If registration does fail,
    /// `Font.custom` falls back to the system font: the app still works and
    /// still reads, it just loses the serif.
    public static let isRegistered: Bool = {
        guard let url = Bundle.module.url(
            forResource: "Prata-Regular",
            withExtension: "ttf",
            subdirectory: "Fonts"
        ) else {
            return false
        }

        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(
            url as CFURL,
            .process,
            &error
        )
        error?.release()
        return registered
    }()
}

public extension Font {
    /// Prata at an explicit size.
    ///
    /// `relativeTo:` keeps the face inside Dynamic Type on iOS, so a person who
    /// has scaled their text up still gets a scaled brand title rather than a
    /// fixed one.
    static func onbiiDisplay(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .largeTitle
    ) -> Font {
        _ = OnbiiFontFamily.isRegistered
        return .custom(OnbiiFontFamily.display, size: size, relativeTo: style)
    }

    /// The one large brand moment on a screen. The guidelines' 48–72px web hero
    /// lands around here once it is inside a window rather than a page.
    static var onbiiHero: Font { .onbiiDisplay(34, relativeTo: .largeTitle) }

    /// A section or object title (the guidelines' 32–40px heading).
    static var onbiiSectionTitle: Font { .onbiiDisplay(22, relativeTo: .title2) }

    /// Small, bold, all-caps sub-label. Deliberately the system font: this is
    /// where the accent colour lives, and thin serif strokes at 12pt would fail
    /// contrast exactly where the guidelines want density.
    static var onbiiSubheader: Font { .system(.caption, weight: .bold) }
}

public extension View {
    /// The guidelines' "sub-labels / metas" treatment: small, bold, tracked,
    /// upper-case, accented.
    func onbiiSubheaderStyle() -> some View {
        font(.onbiiSubheader)
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(.onbiiAccent)
    }
}
