import AppKit

/// Renders the `content.md` subset (headings, unordered lists, paragraphs, bold,
/// italic, inline code) to an `NSAttributedString` for display in an NSTextView.
/// Native text rendering is used deliberately: a WKWebView cannot launch its
/// helper processes inside a Quick Look extension's sandbox and hangs.
enum MarkdownPreview {
    static func attributedString(from markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            appendBlock(
                paragraph.joined(separator: " "),
                font: bodyFont, color: .labelColor, spacingAfter: 9, into: output
            )
            paragraph = []
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("## ") {
                flushParagraph()
                appendBlock(
                    String(line.dropFirst(3)).uppercased(),
                    font: h2Font, color: Brand.accent,
                    spacingBefore: 14, spacingAfter: 5, into: output
                )
            } else if line.hasPrefix("# ") {
                flushParagraph()
                appendBlock(
                    String(line.dropFirst(2)),
                    font: h1Font, color: .labelColor, spacingAfter: 10, into: output
                )
            } else if line.hasPrefix("- ") {
                flushParagraph()
                appendBlock(
                    "•  " + String(line.dropFirst(2)),
                    font: bodyFont, color: .secondaryLabelColor,
                    spacingAfter: 3, headIndent: 16, into: output
                )
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return output
    }

    // MARK: Blocks

    private static func appendBlock(
        _ text: String,
        font: NSFont,
        color: NSColor,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat,
        headIndent: CGFloat = 0,
        into output: NSMutableAttributedString
    ) {
        let start = output.length
        appendInline(text, baseFont: font, color: color, into: output)
        output.append(NSAttributedString(string: "\n"))

        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = spacingAfter
        style.paragraphSpacingBefore = spacingBefore
        style.lineSpacing = 2
        style.headIndent = headIndent
        output.addAttribute(
            .paragraphStyle,
            value: style,
            range: NSRange(location: start, length: output.length - start)
        )
    }

    // MARK: Inline

    /// Splits on backticks first so emphasis is never applied inside code spans
    /// (our source paths and filenames contain underscores).
    private static func appendInline(
        _ text: String,
        baseFont: NSFont,
        color: NSColor,
        into output: NSMutableAttributedString
    ) {
        for (index, segment) in text.components(separatedBy: "`").enumerated() {
            if index.isMultiple(of: 2) {
                appendEmphasis(segment, baseFont: baseFont, color: color, into: output)
            } else {
                output.append(NSAttributedString(
                    string: segment,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(
                            ofSize: baseFont.pointSize - 1, weight: .regular
                        ),
                        .foregroundColor: color,
                    ]
                ))
            }
        }
    }

    private static func appendEmphasis(
        _ text: String,
        baseFont: NSFont,
        color: NSColor,
        into output: NSMutableAttributedString
    ) {
        let manager = NSFontManager.shared
        for (boldIndex, boldPart) in text.components(separatedBy: "**").enumerated() {
            let isBold = !boldIndex.isMultiple(of: 2)
            for (italicIndex, part) in boldPart.components(separatedBy: "_").enumerated() {
                let isItalic = !italicIndex.isMultiple(of: 2)
                guard !part.isEmpty else { continue }
                var font = baseFont
                if isBold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
                if isItalic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
                output.append(NSAttributedString(
                    string: part,
                    attributes: [.font: font, .foregroundColor: color]
                ))
            }
        }
    }

    // MARK: Fonts

    /// The preview's type scale. Deliberately the system font, not the brand
    /// display serif: registering a font inside the Quick Look sandbox is risk
    /// this panel does not need, and body text should match Finder's.
    private enum Size {
        /// The object's title.
        static let title: CGFloat = 22
        /// The all-caps section sub-header, matching the apps' sub-label scale.
        static let subheader: CGFloat = 11
        /// Body and list items.
        static let body: CGFloat = 13
    }

    private static var h1Font: NSFont { .systemFont(ofSize: Size.title, weight: .bold) }
    private static var h2Font: NSFont {
        .systemFont(ofSize: Size.subheader, weight: .semibold)
    }
    private static var bodyFont: NSFont { .systemFont(ofSize: Size.body) }

    // MARK: Brand

    /// The one brand colour this extension uses, on the small all-caps
    /// sub-headers where the guidelines want it.
    ///
    /// Duplicated from `OnbiiUI`'s `OnbiiAccent` on purpose: the Quick Look
    /// extension is sandboxed down to read-only access to the previewed file,
    /// and pulling in SwiftUI plus a resource bundle to colour two headings is
    /// a bad trade. Keep the two values in step — see
    /// `Packages/OnbiiUI/Sources/Resources/README.md`.
    private enum Brand {
        static let accent = NSColor(name: "OnbiiAccent") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0xE7 / 255, green: 0xD5 / 255, blue: 0xBE / 255, alpha: 1)
                : NSColor(srgbRed: 0xB8 / 255, green: 0x85 / 255, blue: 0x52 / 255, alpha: 1)
        }
    }
}
