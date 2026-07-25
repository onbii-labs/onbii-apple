import Cocoa
import QuickLookUI

/// Quick Look preview for `.onbii` objects. `.onbii` is a package (a folder), so
/// macOS would otherwise show a generic package icon; this renders the object's
/// `content.md` front-page view as formatted text. Rendering is native
/// (NSTextView) and synchronous — a WKWebView hangs inside the QL sandbox.
final class PreviewViewController: NSViewController,
    @preconcurrency QLPreviewingController {
    private var textView: NSTextView!

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 24, height: 20)
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true

        scrollView.documentView = text
        textView = text
        view = scrollView
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        let markdown = (try? String(
            contentsOf: url.appendingPathComponent("content.md"),
            encoding: .utf8
        )) ?? "_No preview available._"
        textView.textStorage?.setAttributedString(
            MarkdownPreview.attributedString(from: markdown)
        )
        handler(nil)
    }
}
