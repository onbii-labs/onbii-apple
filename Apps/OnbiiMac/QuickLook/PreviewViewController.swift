import Cocoa
import QuickLookUI
import WebKit

/// Quick Look preview for `.onbii` objects. `.onbii` is a package (a folder), so
/// macOS would otherwise show a generic package icon; this renders the object's
/// `content.md` front-page view as formatted Markdown instead.
final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {
    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false  // static preview, no scripts
        configuration.defaultWebpagePreferences = preferences
        return WKWebView(frame: .zero, configuration: configuration)
    }()

    private var completion: ((Error?) -> Void)?

    override func loadView() {
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        view = webView
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        completion = handler
        let markdown = (try? String(
            contentsOf: url.appendingPathComponent("content.md"),
            encoding: .utf8
        )) ?? "_No preview available._"
        webView.loadHTMLString(MarkdownPreview.html(from: markdown), baseURL: nil)
    }
}

extension PreviewViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        completion?(nil)
        completion = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        completion?(nil)  // still show whatever rendered; never fail the preview
        completion = nil
    }
}
