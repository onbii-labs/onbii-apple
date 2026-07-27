import SwiftUI

/// The Onbii palette, as adaptive colours that follow the system appearance.
///
/// Every value resolves through `OnbiiBrand.xcassets`, where each colour set
/// carries its light value and its dark value. Nothing else in the codebase
/// names those assets by string, so a renamed colour set is a compile-time
/// problem in this file rather than a silent black rectangle at runtime.
///
/// **Usage rule, from the brand guidelines.** In light mode, headings stay
/// ``onbiiPrimaryText``; the accent is reserved for small, dense elements —
/// all-caps sub-headers, buttons, borders, badges — where block density carries
/// the colour better than thin strokes. In dark mode a display-serif title in
/// ``onbiiAccent`` on ``onbiiBackground`` is the signature look and passes AAA.
/// Because the accent set already darkens to a deeper copper in light mode,
/// small accented elements are safe unconditionally; only a hero title needs to
/// branch on `\.colorScheme`.
public extension Color {
    /// Page background. Ivory in light, Graphite in dark.
    static var onbiiBackground: Color { brand("OnbiiBackground") }
    /// Cards and grouped rows. White in light, Midnight in dark.
    static var onbiiSurface: Color { brand("OnbiiSurface") }
    /// A surface raised above ``onbiiSurface``.
    static var onbiiElevated: Color { brand("OnbiiElevated") }
    /// Primary text. Ink in light, near-Ivory in dark.
    static var onbiiPrimaryText: Color { brand("OnbiiPrimaryText") }
    /// Secondary and metadata text.
    static var onbiiSecondaryText: Color { brand("OnbiiSecondaryText") }
    /// Hairlines and borders.
    static var onbiiDivider: Color { brand("OnbiiDivider") }
    /// The brand accent. Deep copper in light, Champagne in dark.
    static var onbiiAccent: Color { brand("OnbiiAccent") }
    /// Text and symbols drawn **on** an accent fill.
    ///
    /// Always required with `.tint(.onbiiAccent)` on a filled control: SwiftUI's
    /// prominent button style assumes a dark, saturated tint and picks white,
    /// which against Champagne is 1.4:1 — unreadable — and against light-mode
    /// Copper is 3.2:1, below AA for body text. Ink and Graphite give 5.1:1 and
    /// 13.1:1.
    static var onbiiOnAccent: Color { brand("OnbiiOnAccent") }
    /// The accent's pressed/hover partner.
    static var onbiiAccentHover: Color { brand("OnbiiAccentHover") }
    /// Something completed and safe.
    static var onbiiSuccess: Color { brand("OnbiiSuccess") }
    /// Something in progress or worth noticing.
    static var onbiiWarning: Color { brand("OnbiiWarning") }
    /// Something that needs the person's attention.
    static var onbiiError: Color { brand("OnbiiError") }

    private static func brand(_ name: String) -> Color {
        Color(name, bundle: .module)
    }
}

/// Leading-dot use in `foregroundStyle`, `tint`, `fill`, `background`, …
public extension ShapeStyle where Self == Color {
    static var onbiiBackground: Color { .onbiiBackground }
    static var onbiiSurface: Color { .onbiiSurface }
    static var onbiiElevated: Color { .onbiiElevated }
    static var onbiiPrimaryText: Color { .onbiiPrimaryText }
    static var onbiiSecondaryText: Color { .onbiiSecondaryText }
    static var onbiiDivider: Color { .onbiiDivider }
    static var onbiiAccent: Color { .onbiiAccent }
    static var onbiiOnAccent: Color { .onbiiOnAccent }
    static var onbiiAccentHover: Color { .onbiiAccentHover }
    static var onbiiSuccess: Color { .onbiiSuccess }
    static var onbiiWarning: Color { .onbiiWarning }
    static var onbiiError: Color { .onbiiError }
}
