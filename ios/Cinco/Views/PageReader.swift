import SwiftUI
import WebKit

/// A stretch of one paragraph selected on the page, in UTF-16 units.
struct PageSelection: Equatable {
    let text: String
    let start: Int
    let end: Int

    var phrase: String {
        let s = text as NSString
        guard start >= 0, end <= s.length, start < end else { return "" }
        return s.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespaces)
    }
}

/// What the reading view can ask of the page.
final class PageHandle {
    fileprivate weak var web: WKWebView?

    func clearSelection() {
        web?.callAsyncJavaScript("cinco.clearSelection()", in: nil, in: PageReader.world)
    }
}

/// The article's own page, as it was published, with Lecturas' marking on it (`PageMarks.js`): tap a word, or select a
/// phrase the usual way. Marks, and words already in the deck, are painted on the page. Links don't leave the article,
/// and the commonest ad networks aren't loaded.
struct PageReader: UIViewRepresentable {
    let url: URL
    let lines: [String]
    let marks: [String]
    let known: Set<String>
    let handle: PageHandle
    /// A word tapped: its paragraph, and where in it.
    let onTap: (_ paragraph: String, _ at: Int) -> Void
    /// What's selected now, when it's in one paragraph.
    let onSelect: (PageSelection?) -> Void
    let onFail: () -> Void

    /// The page script's own world, apart from the page's scripts.
    static let world = WKContentWorld.world(name: "cinco")

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        let ucc = config.userContentController
        if let js = Self.script {
            ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world))
        }
        ucc.add(context.coordinator, contentWorld: Self.world, name: "cinco")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        #if DEBUG
        web.isInspectable = true
        #endif
        context.coordinator.web = web
        handle.web = web
        Task {
            if let ads = await Self.adBlock.value { ucc.add(ads) }
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.paint()
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
        web.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private static let script: String? = Bundle.main.url(forResource: "PageMarks", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    /// Requests to these hosts aren't made. Ads are most of what makes a news page slow and jumpy.
    private nonisolated static let adHosts = ["doubleclick.net", "googlesyndication.com", "googletagservices.com", "adservice.google.com",
                                  "amazon-adsystem.com", "taboola.com", "outbrain.com", "criteo.com", "criteo.net", "adnxs.com",
                                  "rubiconproject.com", "pubmatic.com", "smartadserver.com", "teads.tv", "seedtag.com", "sunmedia.tv"]

    private static let adBlock: Task<WKContentRuleList?, Never> = Task { @MainActor in
        var rules: [[String: Any]] = adHosts.map { host in
            let h = host.replacingOccurrences(of: ".", with: "\\.")
            return ["trigger": ["url-filter": "^https?://([^/]+\\.)?\(h)[:/]", "load-type": ["third-party"]],
                    "action": ["type": "block"]]
        }
        // And the empty boxes the ads would have filled.
        rules.append(["trigger": ["url-filter": ".*"],
                      "action": ["type": "css-display-none",
                                 "selector": "[id^='div-gpt-ad'], ins.adsbygoogle, [data-ad-slot], [id^='taboola'], .OUTBRAIN"]])
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "cinco-ads", encodedContentRuleList: json)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: PageReader
        weak var web: WKWebView?
        /// The page's paragraphs, as it last read them.
        private var texts: [String] = []
        private var painted: Painted?

        private struct Painted: Equatable {
            var lines: [String], marks: [String], known: Set<String>, texts: [String]
        }

        init(_ parent: PageReader) { self.parent = parent }

        /// Sends the page what to paint, when that has changed.
        func paint() {
            let p = parent
            let now = Painted(lines: p.lines, marks: p.marks, known: p.known, texts: texts)
            guard now != painted, let web, !texts.isEmpty else { return }
            painted = now
            let list: [[Any]] = texts.compactMap { t in
                let (m, k) = Lectura.paint(t, lines: p.lines, marks: p.marks, known: p.known)
                return m.isEmpty && k.isEmpty ? nil : [t, m, k]
            }
            web.callAsyncJavaScript("cinco.paint(list)", arguments: ["list": list], in: nil, in: PageReader.world)
        }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let m = message.body as? [String: Any] else { return }
            switch m["type"] as? String {
            case "blocks":
                texts = m["texts"] as? [String] ?? []
                paint()
            case "tap":
                if let text = m["text"] as? String, let at = m["at"] as? Int { parent.onTap(text, at) }
            case "select":
                if let text = m["text"] as? String, let start = m["start"] as? Int, let end = m["end"] as? Int {
                    parent.onSelect(PageSelection(text: text, start: start, end: end))
                } else {
                    parent.onSelect(nil)
                }
            default:
                break
            }
        }

        /// Links stay in the article: this reading is this page. A link within it (a footnote, a consent box) is fine.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, action.targetFrame?.isMainFrame ?? true else { return .allow }
            return webView.url.map(Self.page) == action.request.url.map(Self.page) ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { parent.onFail() }
        }

        /// A link without its #fragment.
        private static func page(_ url: URL) -> String {
            url.absoluteString.split(separator: "#", maxSplits: 1).first.map(String.init) ?? url.absoluteString
        }
    }
}
