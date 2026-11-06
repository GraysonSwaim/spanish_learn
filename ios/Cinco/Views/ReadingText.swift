import SwiftUI
import UIKit
@preconcurrency import Translation

/// One line of a reading, set as running text. Tap a word to pick it; hold on a word and slide to pick a phrase. Only
/// words picked are coloured (a phrase as one band), by what `MarkColor` says of them. A UITextView underneath, since
/// SwiftUI's Text can't say which word is under a finger.
struct ReadingText: UIViewRepresentable {
    let text: String
    let words: [Range<String.Index>]
    /// The picked runs in this line, as word places, with their colours.
    let spans: [(span: ClosedRange<Int>, color: MarkColor)]
    /// A word tapped, with where it is in this view.
    let onTap: (Int, CGRect) -> Void
    /// A phrase picked by sliding, with where it is.
    let onPick: (ClosedRange<Int>, CGRect) -> Void

    static let size: CGFloat = 19

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView(usingTextLayoutManager: false)
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = true
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let c = context.coordinator
        let hold = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.3
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: hold)
        tv.addGestureRecognizer(hold)
        tv.addGestureRecognizer(tap)
        c.view = tv
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        c.colors = .init(ink: resolve(Palette.ink, context), seen: resolve(Palette.mark, context), new: resolve(Palette.markNew, context),
                         pending: resolve(Palette.markPending, context))
        c.render()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        // Measured from the text itself: the view's own sizeThatFits can answer for the width it had before.
        let width = proposal.width ?? 320
        guard let s = uiView.attributedText, s.length > 0 else { return CGSize(width: width, height: 0) }
        let h = s.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height
        return CGSize(width: width, height: ceil(h) + 1)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func resolve(_ color: Color, _ context: Context) -> UIColor {
        UIColor(cgColor: color.resolve(in: context.environment).cgColor)
    }

    final class Coordinator: NSObject {
        struct Colors {
            var ink, seen, new, pending: UIColor

            func of(_ c: MarkColor) -> UIColor {
                switch c {
                case .seen: seen
                case .new: new
                case .pending: pending
                }
            }
        }

        var parent: ReadingText
        var colors = Colors(ink: .label, seen: .systemYellow, new: .systemGreen, pending: .systemGray5)
        weak var view: UITextView?
        /// The phrase under the finger while sliding.
        private var picking: ClosedRange<Int>?
        private var anchor = 0
        private let feedback = UISelectionFeedbackGenerator()

        init(_ parent: ReadingText) { self.parent = parent }

        private var ranges: [NSRange] { parent.words.map { NSRange($0, in: parent.text) } }

        func render() {
            guard let tv = view else { return }
            let p = parent
            let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(name: "BricolageGrotesque-Medium", size: ReadingText.size)
                                                                     ?? .systemFont(ofSize: ReadingText.size))
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 6
            let s = NSMutableAttributedString(string: p.text, attributes: [.font: font, .foregroundColor: colors.ink, .paragraphStyle: para])
            let rs = ranges
            for (span, color) in p.spans + (picking.map { [($0, MarkColor.pending)] } ?? []) {
                guard let r = range(span, rs) else { continue }
                s.addAttribute(.backgroundColor, value: colors.of(color), range: r)
            }
            tv.attributedText = s
        }

        private func range(_ span: ClosedRange<Int>, _ rs: [NSRange]) -> NSRange? {
            guard span.upperBound < rs.count else { return nil }
            let a = rs[span.lowerBound], b = rs[span.upperBound]
            return NSRange(location: a.location, length: b.location + b.length - a.location)
        }

        /// The word under a point. `near`: the closest word even when the point is between words or past the text.
        private func word(at point: CGPoint, near: Bool) -> Int? {
            guard let tv = view else { return nil }
            let lm = tv.layoutManager, tc = tv.textContainer
            let g = lm.glyphIndex(for: point, in: tc)
            if !near, !lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc).insetBy(dx: -6, dy: -5).contains(point) {
                return nil
            }
            let ch = lm.characterIndexForGlyph(at: g)
            let rs = ranges
            if let w = rs.firstIndex(where: { NSLocationInRange(ch, $0) }) { return w }
            guard near else { return nil }
            return rs.indices.min { distance(ch, rs[$0]) < distance(ch, rs[$1]) }
        }

        private func distance(_ ch: Int, _ r: NSRange) -> Int {
            ch < r.location ? r.location - ch : max(0, ch - (r.location + r.length - 1))
        }

        private func rect(_ span: ClosedRange<Int>) -> CGRect {
            guard let tv = view, let r = range(span, ranges) else { return .zero }
            let lm = tv.layoutManager
            return lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil), in: tv.textContainer)
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let w = word(at: g.location(in: view), near: false) else { return }
            parent.onTap(w, rect(w...w))
        }

        @objc func hold(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began:
                guard let w = word(at: g.location(in: view), near: false) else {
                    g.state = .cancelled
                    return
                }
                anchor = w
                picking = w...w
                feedback.selectionChanged()
                render()
            case .changed:
                guard picking != nil, let w = word(at: g.location(in: view), near: true) else { return }
                let next = min(anchor, w)...max(anchor, w)
                if next != picking {
                    picking = next
                    feedback.selectionChanged()
                    render()
                }
            case .ended:
                guard let span = picking else { return }
                let r = rect(span)
                picking = nil
                parent.onPick(span, r)
            default:
                picking = nil
                render()
            }
        }
    }
}

/// What a picked word or phrase means: its card's meaning once it has one, and until then Apple's translation on the
/// phone. With what became of it in the library, and a way to unpick it.
struct WordLookup: View {
    let text: String
    /// The card's meaning, once it's settled.
    var meaning: String? = nil
    var color = MarkColor.pending
    let onRemove: () -> Void
    /// Shown with a way to close it, when it isn't a popover.
    var onClose: (() -> Void)? = nil

    @State private var config: TranslationSession.Configuration?
    @State private var english: String?
    @State private var failed = false

    private var status: String {
        switch color {
        case .pending: "Guardándola…"
        case .seen: "Ya la tenías: vuelve a repasarse"
        case .new: "Nueva en tu biblioteca"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(text).font(Typo.text(19, .heavy)).foregroundStyle(Palette.ink)
                Spacer(minLength: 4)
                Button {
                    Speaker.shared.speak(text, lang: Prefs.current.voiceLang)
                } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Escuchar")
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                    .accessibilityLabel("Cerrar")
                }
            }
            Group {
                if let shown = meaning ?? english {
                    Text(shown).font(Typo.text(17)).foregroundStyle(Palette.en)
                } else if failed {
                    Text("Sin traducción en este iPhone.").font(Typo.text(15)).foregroundStyle(Palette.muted)
                } else {
                    ProgressView()
                }
            }
            .frame(minHeight: 22, alignment: .leading)
            HStack {
                Text(status).font(Typo.text(13)).foregroundStyle(Palette.muted)
                Spacer(minLength: 12)
                Button("Quitar", role: .destructive, action: onRemove).font(Typo.text(14, .heavy))
            }
        }
        .padding(16)
        .translationTask(config) { session in
            do {
                let r = try await session.translate(text)
                english = r.targetText
            } catch {
                failed = true
            }
        }
        .onAppear {
            config = .init(source: Locale.Language(identifier: "es"), target: Locale.Language(identifier: "en"))
        }
    }
}
