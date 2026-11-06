import Foundation
import UIKit
import Vision

/// One printed line of a scanned page and where it sits, as fractions of the page with y going up (Vision's way).
nonisolated struct ScannedLine: Equatable {
    var text: String
    var minX: Double
    var maxX: Double
    var midY: Double
    var height: Double
}

nonisolated struct ScannedPage: Equatable {
    var paragraphs: [String]
    /// The number printed on the page, when there is one.
    var number: Int?
}

/// Printed lines back into the paragraphs a reading is made of. A book breaks its lines wherever the margin falls, so
/// where each line sits says where the paragraphs are.
nonisolated enum PageText {
    private static let endings = Set(".?!…:;»”\"’)")
    private static let hyphens = Set("-‐‑\u{00AD}")
    private static let dashes = Set("—―–")

    static func assemble(_ raw: [ScannedLine]) -> ScannedPage {
        var lines = rows(raw)
        var number: Int?
        if let first = lines.first, let n = pageNumber(first.text) {
            number = n
            lines.removeFirst()
        }
        if let last = lines.last, let n = pageNumber(last.text) {
            number = number ?? n
            lines.removeLast()
        }
        guard !lines.isEmpty else { return ScannedPage(paragraphs: [], number: number) }

        let spacing = median(zip(lines, lines.dropFirst()).map { $0.midY - $1.midY }) ?? lines[0].height * 1.4
        let left = sorted(lines.map(\.minX), at: 0.25)
        let right = sorted(lines.map(\.maxX), at: 0.9)

        // A running head or chapter title: short, set apart from the text, and not the end of a sentence.
        if lines.count >= 3, lines[0].midY - lines[1].midY > 1.5 * spacing,
           lines[0].maxX - lines[0].minX < 0.75 * (right - left), !endsSentence(lines[0].text) {
            number = number ?? headNumber(lines[0].text)
            lines.removeFirst()
        }

        var paragraphs: [String] = []
        var current = ""
        for (i, line) in lines.enumerated() {
            if i > 0, startsParagraph(line, after: lines[i - 1], spacing: spacing, left: left, right: right) {
                paragraphs.append(current)
                current = ""
            }
            current = current.isEmpty ? line.text : glue(current, line.text)
        }
        paragraphs.append(current)
        return ScannedPage(paragraphs: paragraphs, number: number)
    }

    /// The pages' paragraphs in order, with one that runs over the end of a page made whole again.
    static func joined(_ pages: [ScannedPage]) -> [String] {
        var out: [String] = []
        for page in pages {
            for (i, p) in page.paragraphs.enumerated() {
                if i == 0, let last = out.last, !endsSentence(last) || startsLowercase(p) {
                    out[out.count - 1] = glue(last, p)
                } else {
                    out.append(p)
                }
            }
        }
        return out
    }

    /// "pág. 47" or "págs. 47–49", from the numbers found on the pages.
    static func label(_ numbers: [Int]) -> String? {
        guard let first = numbers.first, let last = numbers.last else { return nil }
        return last > first ? "págs. \(first)–\(last)" : "pág. \(first)"
    }

    // MARK: pieces

    /// Top to bottom, with pieces of one printed row put back together, left to right.
    private static func rows(_ raw: [ScannedLine]) -> [ScannedLine] {
        let lines = raw
            .map { var l = $0; l.text = l.text.trimmingCharacters(in: .whitespacesAndNewlines); return l }
            .filter { !$0.text.isEmpty }
            .sorted { $0.midY > $1.midY }
        var out: [ScannedLine] = []
        for line in lines {
            if let last = out.last, abs(last.midY - line.midY) < 0.5 * min(last.height, line.height) {
                let (a, b) = last.minX <= line.minX ? (last, line) : (line, last)
                out[out.count - 1] = ScannedLine(text: a.text + " " + b.text, minX: a.minX, maxX: max(a.maxX, b.maxX),
                                                 midY: last.midY, height: max(a.height, b.height))
            } else {
                out.append(line)
            }
        }
        return out
    }

    private static func startsParagraph(_ line: ScannedLine, after prev: ScannedLine, spacing: Double, left: Double, right: Double) -> Bool {
        if prev.midY - line.midY > 1.5 * spacing { return true }
        // Curved paper can push a wrapped line in, and "—le preguntó" continues a line of dialogue.
        if startsLowercase(line.text) { return false }
        if let c = line.text.first, dashes.contains(c) { return true }
        if line.minX - left > 0.02 { return true }
        return prev.maxX < right - 0.1 && endsSentence(prev.text)
    }

    private static func glue(_ a: String, _ b: String) -> String {
        if let c = a.last, hyphens.contains(c), startsLowercase(b) { return a.dropLast() + b }
        return a + " " + b
    }

    private static func endsSentence(_ s: String) -> Bool { s.last.map(endings.contains) ?? false }

    /// Whether the first letter is lowercase, looking past a dialogue dash or an opening mark.
    private static func startsLowercase(_ s: String) -> Bool {
        s.first { $0.isLetter || $0.isNumber }?.isLowercase ?? false
    }

    /// The number of a line that's nothing else: "47", "— 47 —".
    private static func pageNumber(_ s: String) -> Int? {
        let digits = s.filter { !"-–—·. ".contains($0) }
        return digits.count <= 4 && digits.allSatisfy(\.isNumber) ? Int(digits) : nil
    }

    /// A number at either end of a running head: "47  CAPÍTULO TRES".
    private static func headNumber(_ s: String) -> Int? {
        let parts = s.split(separator: " ")
        return [parts.first, parts.last].compactMap { $0.flatMap { pageNumber(String($0)) } }.first
    }

    private static func median(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : sorted(xs, at: 0.5) }

    private static func sorted(_ xs: [Double], at fraction: Double) -> Double {
        xs.sorted()[Int(Double(xs.count - 1) * fraction)]
    }
}

/// Reading scanned pages. Everything here happens on the phone.
nonisolated enum PageScan {
    /// How many pages one scan keeps: more than this is more than one sitting's study.
    static let maxPages = 5

    /// The printed lines Vision finds in a picture of a page.
    static func recognize(_ image: UIImage) -> [ScannedLine] {
        guard let cg = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["es-ES"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation(image.imageOrientation))
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { o in
            guard let text = o.topCandidates(1).first?.string else { return nil }
            let b = o.boundingBox
            return ScannedLine(text: text, minX: b.minX, maxX: b.maxX, midY: b.midY, height: b.height)
        }
    }

    /// The pages, in order, off the main thread.
    static func read(_ images: [UIImage]) async -> [ScannedPage] {
        await Task.detached(priority: .userInitiated) {
            images.prefix(maxPages).map { PageText.assemble(recognize($0)) }
        }.value
    }

    /// "Mi libro · pág. 47", or the date when no page number was found.
    static func title(book: String, pages: [ScannedPage], now: Date = .now) -> String {
        let label = PageText.label(pages.compactMap(\.number))
            ?? now.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es")))
        return "\(book) · \(label)"
    }

    /// The page's own theme, inside its book's: "Pág. 47".
    static func pageName(_ title: String, book: String) -> String {
        let prefix = "\(book) · "
        let name = title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : title
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private static func orientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
