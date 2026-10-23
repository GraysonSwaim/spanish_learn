import SwiftUI
import SwiftData

/// One reading, set like the article it came from, sentence by sentence. Tap a word you don't know, or hold and slide
/// across a phrase, to mark it and see roughly what it means; Tarjetas turns the marked words into cards.
/// A reading made from a link can also be read on the article's own page (`PageReader`), marked the same way.
struct ReadingView: View {
    @Bindable var reading: Reading
    @Query private var cards: [Card]

    enum Mode { case page, text }

    @State private var mode = Mode.page
    @State private var words: [[Range<String.Index>]] = []
    @State private var known = Set<String>()
    /// The word or phrase whose meaning is showing.
    @State private var lookup: Lookup?
    @State private var makingCards = false
    /// What's selected on the page.
    @State private var selection: PageSelection?
    @State private var page = PageHandle()
    @State private var pageFailed = false

    private var runs: [Run] { Lectura.runs(lines: reading.lines, marks: reading.marks) }
    private var pageURL: URL? { reading.url.isEmpty ? nil : URL(string: reading.url) }
    private var onPage: Bool { mode == .page && pageURL != nil && !pageFailed }

    var body: some View {
        Group {
            if onPage, let url = pageURL {
                PageReader(url: url, lines: reading.lines, marks: reading.marks, known: known, handle: page,
                           onTap: pageTapped, onSelect: pageSelected, onFail: { pageFailed = true })
            } else {
                lines
            }
        }
        .background(Backdrop())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if pageURL != nil, !pageFailed {
                ToolbarItem(placement: .principal) {
                    Picker("Vista", selection: $mode) {
                        Text("Original").tag(Mode.page)
                        Text("Texto").tag(Mode.text)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if onPage { pagePanel }
                actions
            }
        }
        .onAppear(perform: load)
        .onChange(of: reading.lines.count) { words = reading.lines.map(Lectura.words) }
        .onChange(of: mode) {
            lookup = nil
            selection = nil
        }
        .sheet(isPresented: $makingCards) {
            NavigationStack { ReadingCardsView(reading: reading) }
        }
    }

    private var lines: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text(reading.title).font(Typo.display(28)).foregroundStyle(Palette.ink)
                Text(pageFailed ? "No se pudo abrir la página del artículo; aquí está su texto. Toca una palabra que no conoces, o mantén pulsado y desliza para una frase."
                     : "Toca una palabra que no conoces, o mantén pulsado y desliza para una frase. Lo que marques se hace tarjeta.")
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
                    WordLookup(text: text) { unmark(l) }
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, alignment: .leading)
                        .presentationCompactAdaptation(.popover)
                }
            }
    }

    /// Over the page: the meaning of what was tapped, or a way to mark what's selected.
    @ViewBuilder
    private var pagePanel: some View {
        if let s = selection, !s.phrase.isEmpty {
            Button { markSelection(s) } label: {
                Label("Marcar «\(s.phrase)»", systemImage: "highlighter").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftButtonStyle(fill: Palette.paper, text: Palette.ink, size: 17))
            .padding(.horizontal, 16)
        } else if let l = lookup, let text = phrase(l) {
            WordLookup(text: text, onRemove: { unmark(l) }, onClose: { lookup = nil })
                .id(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.paper, in: .rect(cornerRadius: 18))
                .shadow(color: Palette.shadow, radius: 10, y: 3)
                .padding(.horizontal, 16)
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

    private func unmark(_ l: Lookup) {
        guard let line = reading.lines[safe: l.line] else { return }
        Lectura.unmark(&reading.marks, line: l.line, text: line, word: l.words.lowerBound)
        lookup = nil
    }

    private func pageTapped(_ paragraph: String, at: Int) {
        guard let w = Lectura.words(in: paragraph, from: at, to: at + 1) else { return }
        selection = nil
        tapped(line: line(for: paragraph), word: w.lowerBound, rect: .zero)
    }

    private func pageSelected(_ s: PageSelection?) {
        selection = s
        if s != nil { lookup = nil }
    }

    private func markSelection(_ s: PageSelection) {
        guard let span = Lectura.words(in: s.text, from: s.start, to: s.end) else { return }
        picked(line: line(for: s.text), span: span, rect: .zero)
        selection = nil
        page.clearSelection()
    }

    /// The line that is a paragraph of the page: it becomes one of the reading's lines when it isn't yet.
    private func line(for paragraph: String) -> Int {
        if let i = reading.lines.firstIndex(of: paragraph) { return i }
        reading.lines.append(paragraph)
        return reading.lines.count - 1
    }

    /// The words of a lookup as they stand in the line.
    private func phrase(_ l: Lookup) -> String? {
        guard let line = reading.lines[safe: l.line] else { return nil }
        let ws = Lectura.words(line)
        guard l.words.upperBound < ws.count else { return nil }
        return String(line[ws[l.words.lowerBound].lowerBound..<ws[l.words.upperBound].upperBound])
    }
}

/// A word or phrase being looked up, and where it is in its line.
private struct Lookup: Equatable {
    let line: Int
    let words: ClosedRange<Int>
    let rect: CGRect
}
