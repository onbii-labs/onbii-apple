import Foundation

/// Small Markdown→HTML renderer for the Quick Look preview. It covers the subset
/// `content.md` uses — headings, unordered lists, paragraphs, bold, italic, and
/// inline code — rather than being a general CommonMark implementation.
enum MarkdownPreview {
    static func html(from markdown: String) -> String {
        var body = ""
        var paragraph: [String] = []
        var inList = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            body += "<p>\(paragraph.map(inline).joined(separator: "<br>"))</p>\n"
            paragraph = []
        }
        func closeList() {
            if inList { body += "</ul>\n"; inList = false }
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph(); closeList()
            } else if line.hasPrefix("## ") {
                flushParagraph(); closeList()
                body += "<h2>\(inline(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("# ") {
                flushParagraph(); closeList()
                body += "<h1>\(inline(String(line.dropFirst(2))))</h1>\n"
            } else if line.hasPrefix("- ") {
                flushParagraph()
                if !inList { body += "<ul>\n"; inList = true }
                body += "<li>\(inline(String(line.dropFirst(2))))</li>\n"
            } else {
                closeList()
                paragraph.append(line)
            }
        }
        flushParagraph(); closeList()
        return document(body: body)
    }

    // MARK: Inline

    /// Splits on backticks so emphasis is never applied inside code spans (our
    /// source paths and filenames contain underscores).
    private static func inline(_ text: String) -> String {
        text.components(separatedBy: "`").enumerated().map { index, part in
            index.isMultiple(of: 2)
                ? emphasis(escape(part))
                : "<code>\(escape(part))</code>"
        }.joined()
    }

    private static func emphasis(_ escaped: String) -> String {
        var value = escaped
        value = replace(value, #"\*\*(.+?)\*\*"#, "<strong>$1</strong>")
        value = replace(value, #"_(.+?)_"#, "<em>$1</em>")
        return value
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func replace(
        _ text: String,
        _ pattern: String,
        _ template: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }

    // MARK: Document

    private static func document(body: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body {
          font: -apple-system-body, system-ui, sans-serif;
          line-height: 1.55;
          margin: 0; padding: 28px 32px;
          color: #1d1d1f;
        }
        h1 { font-size: 1.6em; margin: 0 0 .4em; }
        h2 {
          font-size: 1.05em; text-transform: uppercase; letter-spacing: .04em;
          color: #86868b; margin: 1.6em 0 .6em;
        }
        ul { margin: .2em 0 1em; padding-left: 1.2em; color: #515154; }
        li { margin: .15em 0; }
        p { margin: 0 0 .9em; }
        strong { font-weight: 600; }
        code {
          font: ui-monospace, SFMono-Regular, Menlo, monospace;
          font-size: .9em; background: rgba(128,128,128,.16);
          padding: .1em .35em; border-radius: 4px;
        }
        @media (prefers-color-scheme: dark) {
          body { color: #f5f5f7; }
          ul { color: #aeaeb2; }
        }
        </style></head>
        <body>
        \(body)</body></html>
        """
    }
}
