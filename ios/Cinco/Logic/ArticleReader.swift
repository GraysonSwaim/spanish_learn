import Foundation
import NaturalLanguage
import WebKit

/// An article's main text, read from its page for a reading made from a link (`ReadingView.readArticle`).
nonisolated struct Article: Equatable {
    var title: String
    var site: String
    /// One paragraph per line, the way `Lectura.lines` splits a reading.
    var text: String
    /// Taken from the page's own JSON-LD `articleBody` rather than Readability's guess.
    var fromMetadata: Bool
    var isSpanish: Bool

    var paragraphs: Int { text.split(whereSeparator: \.isNewline).count }
}

/// Text rules for reading an article: finding a link in what was pasted, and choosing and cleaning the text a page gives.
/// The same page always gives the same text: no model is involved.
nonisolated enum ArticleText {
    /// Shorter than this, a text is a teaser or a cookie notice, not an article.
    static let minChars = 200
    /// Metadata text paragraphs longer than this are split into a few sentences each.
    static let longParagraph = 700

    /// The http(s) link in a short paste, like a shared "Title https://…". A long paste is a text, even with a link in it.
    static func link(in s: String) -> URL? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 500 else { return nil }
        if !t.contains(":"), !t.contains(" "), t.contains(".") { t = "https://" + t }
        let found = (try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue))?
            .matches(in: t, range: NSRange(t.startIndex..., in: t))
            .compactMap(\.url)
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") && ($0.host()?.contains(".") ?? false) } ?? []
        return found.count == 1 ? found[0] : nil
    }

    /// The page's metadata text when it's the whole article in paragraphs, else Readability's paragraphs, else
    /// whatever metadata there is, split into paragraphs of a few sentences. Nothing when neither is an article's worth.
    static func choose(paragraphs: [String], metadata: String) -> (lines: [String], fromMetadata: Bool) {
        let read = clean(paragraphs)
        let meta = clean(metadata.components(separatedBy: .newlines))
        let readChars = read.joined().count, metaChars = meta.joined().count
        // Metadata in paragraphs, and not a teaser of what Readability found.
        if meta.count > 1, metaChars >= minChars, Double(metaChars) >= 0.8 * Double(readChars) { return (split(meta), true) }
        if readChars >= minChars { return (read, false) }
        if metaChars >= minChars { return (split(meta), true) }
        return ([], false)
    }

    /// The labels news pages put between paragraphs: ads, bylines, photo credits, links elsewhere. Compared without
    /// case or accents; a line is dropped when it is one of `labels` or starts with one of `labelStarts`.
    static let labels: Set<String> = ["publicidad", "anuncio", "advertisement", "compartir", "mas leidas", "lo mas leido",
                                      "noticias relacionadas", "relacionado", "relacionadas", "te puede interesar",
                                      "lee tambien", "seguir leyendo", "sigue leyendo"]
    static let labelStarts = ["fuente de la imagen", "pie de foto", "autor,", "titulo del autor", "fecha de publicacion",
                              "tiempo de lectura", "saltar ", "final de ", "lee tambien:", "te puede interesar:",
                              "suscribete", "foto:", "imagen:", "credito:"]

    /// Spaces evened out, and labels, lines with no letters and lines already seen dropped.
    static func clean(_ lines: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for l in lines {
            let t = l.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard t.contains(where: \.isLetter), !isLabel(t), seen.insert(t).inserted else { continue }
            out.append(t)
        }
        return out
    }

    static func isLabel(_ line: String) -> Bool {
        // Not TextMatch.strip: it drops the commas and colons that tell "Autor, …" from "Autoridades …".
        let s = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":.· "))
        return labels.contains(s) || labelStarts.contains { s.hasPrefix($0) }
    }

    /// Long paragraphs as runs of three sentences, so a reading isn't one wall of text.
    static func split(_ lines: [String]) -> [String] {
        lines.flatMap { l -> [String] in
            guard l.count > longParagraph else { return [l] }
            let tok = NLTokenizer(unit: .sentence)
            tok.string = l
            tok.setLanguage(.spanish)
            let sentences = tok.tokens(for: l.startIndex..<l.endIndex).map { l[$0].trimmingCharacters(in: .whitespaces) }
            return stride(from: 0, to: sentences.count, by: 3).map { sentences[$0..<min($0 + 3, sentences.count)].joined(separator: " ") }
        }
    }

    /// A link's site, as a reading's name until the article's own title is read.
    static func site(_ url: URL) -> String {
        let host = url.host() ?? "Lectura"
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func isSpanish(_ text: String) -> Bool {
        NLLanguageRecognizer.dominantLanguage(for: String(text.prefix(2000))) == .spanish
    }
}

/// Loads an article in a web view nobody sees, the way Safari would (sites that turn away a plain download still
/// answer it), and runs Mozilla's Readability (Firefox's Reader View) and `ArticleExtract.js` on the page.
final class ArticleReader: NSObject, WKNavigationDelegate {
    enum Failure: LocalizedError {
        case load, empty

        var errorDescription: String? {
            switch self {
            case .load: "No se pudo abrir esa página."
            case .empty: "No encontré el texto de un artículo en esa página."
            }
        }
    }

    static func read(_ url: URL) async throws -> Article {
        try await ArticleReader().read(url)
    }

    private let web: WKWebView
    private var loading: CheckedContinuation<Void, Error>?
    private var attempt = 0

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        // A phone-sized page, so sites serve their mobile layout.
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        super.init()
        web.navigationDelegate = self
    }

    private func read(_ url: URL) async throws -> Article {
        defer { web.stopLoading() }
        // An http link is tried over https first. Some sites (larevista.ec) have no https at all, so the plain page is
        // the fallback: Info.plist lets web views, and only web views, load it.
        if url.scheme?.lowercased() == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.scheme = "https"
            if let secure = parts.url {
                do { try await load(secure, timeout: 8) } catch { try await load(url) }
            } else {
                try await load(url)
            }
        } else {
            try await load(url)
        }
        // Pages that build their text with scripts get a moment, and another try if it isn't there yet.
        for wait in [0.8, 2.5] {
            try await Task.sleep(for: .seconds(wait))
            if let a = try await extract(), !a.text.isEmpty { return a }
        }
        throw Failure.empty
    }

    private func load(_ url: URL, timeout: TimeInterval = 20) async throws {
        attempt += 1
        let this = attempt
        try await withCheckedThrowingContinuation { c in
            loading = c
            web.load(URLRequest(url: url, timeoutInterval: timeout))
            // A page whose ads never finish loading is read as it stands (unless a later load has begun).
            Task { try? await Task.sleep(for: .seconds(15)); if self.attempt == this { self.loaded(nil) } }
        }
    }

    private func extract() async throws -> Article? {
        guard let script = Self.script,
              let d = try await web.callAsyncJavaScript(script, contentWorld: .defaultClient) as? [String: Any] else { return nil }
        let picked = ArticleText.choose(paragraphs: d["paragraphs"] as? [String] ?? [], metadata: d["metadata"] as? String ?? "")
        let text = picked.lines.joined(separator: "\n")
        return Article(title: (d["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                       site: d["site"] as? String ?? "", text: text, fromMetadata: picked.fromMetadata,
                       isSpanish: ArticleText.isSpanish(text))
    }

    /// Readability, then the script that calls it, as one function body.
    private static let script: String? = {
        let parts = ["Readability", "ArticleExtract"].compactMap { name in
            Bundle.main.url(forResource: name, withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        return parts.count == 2 ? parts.joined(separator: "\n;\n") : nil
    }()

    private func loaded(_ error: Error?) {
        guard let c = loading else { return }
        loading = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded(nil) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Stopped partway (a redirect, a cancelled ad): what loaded may still hold the article.
        loaded(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        loaded(Failure.load)
    }
}
