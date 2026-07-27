import SwiftUI

/// The non-colour, non-typographic constants of the Onbii visual identity.
///
/// These exist so that spacing and corner radii are decided once rather than
/// re-invented per screen. Anything platform-conventional — control sizes, list
/// insets, navigation chrome — is deliberately *not* here: those belong to the
/// platform, and overriding them makes an app feel foreign rather than branded.
public enum OnbiiTheme {
    public enum Spacing {
        /// Between an icon and its label.
        public static let xs: CGFloat = 4
        /// Within a row.
        public static let s: CGFloat = 8
        /// Between related rows.
        public static let m: CGFloat = 12
        /// Between groups.
        public static let l: CGFloat = 20
        /// Around a screen's content.
        public static let xl: CGFloat = 32
    }

    public enum Radius {
        public static let badge: CGFloat = 6
        public static let card: CGFloat = 12
        /// Fraction of the mark's width, matching the app icon's corner.
        public static let markFraction: CGFloat = 0.2237
    }
}
