import SwiftUI
import SwiftData

/// One reading, set like the article it came from, sentence by sentence. Tap a word you don't know, or hold and slide
/// across a phrase, to mark it and see roughly what it means; Tarjetas turns the marked words into cards.
struct ReadingView: View {
    @Bindable var reading: Reading
    @Query private var cards: [Card]

    @State private var words: [[Range<String.Index>]] = []
    @State private var known = Set<String>()
    /// The word or phrase whose meaning is showing.
    @State private var lookup: Lookup?
    @State private var makingCards = false

    private var runs: [Run] { Lectura.runs(lines: reading.lines, marks: reading.marks) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text(reading.title).font(Typo.display(28)).foregroundStyle(Palette.ink)
                Text("Toca una palabra que no conoces, o mantén pulsado y desliza para una frase. Lo que marques se hace tarjeta.")
                    .font(Typo.text(15)).foregroundStyle(Palette.muted)
                    .padding(.bottom, 8)

                ForEach(reading.lines.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 6) {
                        spanish(i)
                        speakButton(reading.lines[i])
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actions }
        .onAppear(perform: load)
        .sheet(isPresented: $makingCards) {
            NavigationStack { ReadingCardsView(reading: reading) }
        }
    }

    /// The Spanish line as running text, its marked words highlighted. A tap or a slide marks, and shows the meaning.
    private func spanish(_ i: Int) -> some View {
        let line = reading.lines[i]
        return ReadingText(text: line, words: words[safe: i] ?? [], spans: Lectura.spans(reading.marks, line: i, text: line),
                           known: known,
                           onTap: { w, rect in tapped(line: i, word: w, rect: rect) },
                           onPick: { span, rect in picked(line: i, span: span, rect: rect) })
            .popover(isPresented: Binding(get: { lookup?.line == i }, set: { if !$0 { lookup = nil } }),
                     attachmentAnchor: .rect(.rect(lookup?.line == i ? lookup!.rect : .zero))) {
                if let l = lookup, let text = phrase(l) {
                    WordLookup(text: text) {
                        Lectura.unmark(&reading.marks, line: l.line, text: line, word: l.words.lowerBound)
                        lookup = nil
                    }
                }
            }
    }

    private func speakButton(_ text: String) -> some View {
        Button {
            Speaker.shared.speak(text, lang: Prefs.current.voiceLang)
        } label: {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.muted)
                .frame(width: 32, height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Escuchar la línea")
    }

    private var actions: some View {
        let n = runs.filter { !reading.carded.contains($0.id) }.count
        return Button { makingCards = true } label: {
            Text(n > 0 ? "Hacer tarjetas · \(n)" : runs.isEmpty ? "Marca palabras para hacer tarjetas" : "Tarjetas")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SoftButtonStyle(fill: Palette.sea, text: .white, size: 18))
        .disabled(runs.isEmpty)
        .opacity(runs.isEmpty ? 0.5 : 1)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }

    // MARK: actions

    private func load() {
        words = reading.lines.map(Lectura.words)
        known = Lectura.knownWords(cards)
        reading.opened = .now
    }

    /// A tap on an unmarked word marks it as a card of its own; on a marked one, shows the phrase it's in.
    private func tapped(line i: Int, word w: Int, rect: CGRect) {
        if let span = Lectura.spans(reading.marks, line: i, text: reading.lines[i]).first(where: { $0.contains(w) }) {
            lookup = Lookup(line: i, words: span, rect: rect)
        } else {
            Lectura.mark(&reading.marks, line: i, first: w, last: w)
            UISelectionFeedbackGenerator().selectionChanged()
            lookup = Lookup(line: i, words: w...w, rect: rect)
        }
    }

    /// A slide across words marks them as one phrase, in place of any marks they cross.
    private func picked(line i: Int, span: ClosedRange<Int>, rect: CGRect) {
        Lectura.mark(&reading.marks, line: i, first: span.lowerBound, last: span.upperBound)
        lookup = Lookup(line: i, words: span, rect: rect)
    }

    /// The words of a lookup as they stand in the line.
    private func phrase(_ l: Lookup) -> String? {
        guard let line = reading.lines[safe: l.line], let ws = words[safe: l.line], l.words.upperBound < ws.count else { return nil }
        return String(line[ws[l.words.lowerBound].lowerBound..<ws[l.words.upperBound].upperBound])
    }
}

/// A word or phrase being looked up, and where it is in its line.
private struct Lookup: Equatable {
    let line: Int
    let words: ClosedRange<Int>
    let rect: CGRect
}
