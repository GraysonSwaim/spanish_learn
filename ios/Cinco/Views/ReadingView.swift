import SwiftUI
import SwiftData

/// One reading, set like the article it came from, sentence by sentence. Tap a word you don't know, or hold and slide
/// across a phrase, to mark it and see roughly what it means; Tarjetas turns the marked words into cards.
/// A reading made from a link can also be read on the article's own page (`PageReader`), marked the same way.
/// A scanned page of a book is studied first: Claude picks its words, they're studied from here, and the session comes
/// back to the page to read it.
struct ReadingView: View {
    @Bindable var reading: Reading
    /// Go straight to the cards, for a page just scanned.
    var startCards = false
    @Environment(\.study) private var study
    @Query private var cards: [Card]
    @Query private var chunks: [Chunk]

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
    private var pageURL: URL? { reading.url.isEmpty || reading.book != nil ? nil : URL(string: reading.url) }
    private var onPage: Bool { mode == .page && pageURL != nil && !pageFailed }
    private var isBook: Bool { reading.book != nil }

    /// A book page's words to study before reading it: the ones new to its theme, and those from the deck it brought back.
    private var pageWords: [Card] {
        guard isBook else { return [] }
        let theme = chunks.first { $0.readingID == reading.id }?.id
        return cards.filter { c in
            !c.isConj && !c.isDropped && (c.chunkID == theme || c.sourceList.contains { $0.title == reading.title })
        }
    }

    /// A session over them would have something to show.
    private var canStudy: Bool {
        let words = pageWords
        return !Scheduler.dailyQueue(words).isEmpty || !Scheduler.unseen(words, staggerTenses: false, verbs: []).isEmpty
    }

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
            if pageURL != nil, !pageFailed, !reading.lines.isEmpty {
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
        .onChange(of: cards.count) { known = Lectura.knownWords(cards) }
        // After the screen has arrived: a sheet asked for during the push doesn't come up.
        .task {
            guard startCards, reading.marks.isEmpty, reading.carded.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(450))
            makingCards = true
        }
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
                Text(isBook ? "Estudia primero las palabras de esta página; luego léela con calma. Si te atascas, toca una palabra para ver qué significa."
                     : pageFailed && reading.lines.isEmpty ? "No se pudo abrir la página del artículo, ni leer su texto."
                     : pageFailed ? "No se pudo abrir la página del artículo; aquí está su texto. Toca una palabra que no conoces, o mantén pulsado y desliza para una frase."
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
                .background(Palette.paper, in: .rect(cornerRadius: 6))
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
        // A book page with nothing marked yet can still have its words chosen.
        let choosable = isBook && runs.isEmpty
        let enabled = !runs.isEmpty || choosable
        return VStack(spacing: 8) {
            if canStudy {
                Button { studyPage() } label: {
                    Text("Estudiar estas palabras · \(pageWords.count)").frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 18))
            }
            // A page whose words are all cards has nothing more to make.
            if !isBook || n > 0 || runs.isEmpty {
                Button { makingCards = true } label: {
                    Text(choosable ? "Elegir las palabras" : n > 0 ? "Hacer tarjetas · \(n)" : runs.isEmpty ? "Marca palabras para hacer tarjetas" : "Tarjetas")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle(fill: Palette.sea, text: .white, size: 18))
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }

    // MARK: actions

    private func studyPage() {
        let theme = chunks.first { $0.readingID == reading.id }
        study(pageWords, label: theme?.name ?? reading.title, key: "page:" + reading.id)
    }

    private func load() {
        words = reading.lines.map(Lectura.words)
        known = Lectura.knownWords(cards)
        reading.opened = .now
        if reading.lines.isEmpty, let url = pageURL { Task { await readArticle(url) } }
    }

    /// The article's text, for the Texto view and in case the page won't open. Paragraphs already marked on the page
    /// keep their place, so their marks still point at them.
    private func readArticle(_ url: URL) async {
        guard let a = try? await ArticleReader.read(url) else { return }
        reading.lines += Lectura.lines(a.text).filter { !reading.lines.contains($0) }
        if !a.title.isEmpty, reading.title == ArticleText.site(url) { reading.title = a.title }
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
