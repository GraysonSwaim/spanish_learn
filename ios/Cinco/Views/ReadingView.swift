import SwiftUI
import SwiftData

/// One reading, set like the article it came from. A new reading, scanned or from a link, first feeds the library: its new
/// words go in, they're studied straight away, and the session comes back here to read it. Tap a word you don't understand, or hold and
/// slide across a phrase, and it's recorded: yellow if it's in the library already, green if it's new to it. Words you
/// know are already highlighted, more palely, until that's turned off.
/// A reading made from a link can also be read on the article's own page (`PageReader`), tapped the same way.
struct ReadingView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.study) private var study
    @Bindable var reading: Reading
    /// Just made: its words go in and are studied before it's read.
    let isNew: Bool
    @AppStorage(PrefKey.highlightKnown) private var highlightKnown = true
    @Environment(\.sessionCovers) private var covered
    /// What this page needs from the library, kept up to date by `LibraryWatch`.
    @State private var library = ReadingLibrary()

    enum Mode { case page, text }

    @State private var mode = Mode.page
    @State private var words: [[Range<String.Index>]] = []
    /// The words you know, by line.
    @State private var knownSpans: [[ClosedRange<Int>]] = []
    /// The word or phrase whose meaning is showing.
    @State private var lookup: Lookup?
    /// What's selected on the page.
    @State private var selection: PageSelection?
    @State private var page = PageHandle()
    @State private var pageFailed = false

    /// Taking the page's words.
    @State private var working: String?
    /// A new reading's words are on their way, and study comes next.
    @State private var preparing: Bool
    /// Whether this is still on screen, so a session doesn't open over wherever the learner has gone.
    @State private var onScreen = false
    /// A new reading turned out to have nothing to study.
    @State private var allKnown = false
    @State private var problem: String?
    @State private var askScanConsent = false
    @State private var askConsent = false
    /// Tapped words are settled one at a time, by this.
    @State private var settling = false
    @State private var settleFailed = Set<String>()

    init(reading: Reading, isNew: Bool = false) {
        self.reading = reading
        self.isNew = isNew
        _preparing = State(initialValue: isNew && reading.pageWords == nil)
    }

    private var pageURL: URL? { reading.url.isEmpty || reading.book != nil ? nil : URL(string: reading.url) }
    private var onPage: Bool { mode == .page && pageURL != nil && !pageFailed }
    private var isBook: Bool { reading.book != nil }
    var body: some View {
        let colors = reading.markColors
        let known = library.known
        Group {
            if preparing {
                preparingView
            } else if onPage, let url = pageURL {
                PageReader(url: url, lines: reading.lines, marks: reading.marks, colors: colors, known: known,
                           page: reading.pageWords ?? [], handle: page,
                           onTap: pageTapped, onSelect: pageSelected, onFail: { pageFailed = true })
            } else {
                lines(colors)
            }
        }
        .background(Backdrop())
        .background {
            if !covered { LibraryWatch(reading: reading, highlight: highlightKnown, library: $library).equatable() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if pageURL != nil, !pageFailed, !reading.lines.isEmpty, !preparing {
                ToolbarItem(placement: .principal) {
                    Picker("Vista", selection: $mode) {
                        Text("Original").tag(Mode.page)
                        Text("Texto").tag(Mode.text)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    highlightKnown.toggle()
                } label: {
                    Image(systemName: "highlighter").foregroundStyle(highlightKnown ? Palette.accent : Palette.muted)
                }
                .accessibilityLabel("Resaltar las que ya sabes")
                .accessibilityAddTraits(highlightKnown ? .isSelected : [])
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !preparing {
                VStack(spacing: 8) {
                    if onPage { pagePanel(colors) }
                    actions
                }
            }
        }
        .onAppear {
            onScreen = true
            load()
        }
        .onDisappear { onScreen = false }
        .onChange(of: reading.lines.count) { words = reading.lines.map(Lectura.words) }
        .onChange(of: mode) {
            lookup = nil
            selection = nil
        }
        .task { await begin() }
        .task(id: KnownLines(known: known, lines: reading.lines, page: reading.pageWords ?? [])) {
            guard let known else { knownSpans = []; return }
            let (lines, page) = (reading.lines, reading.pageWords ?? [])
            let found = await Task.detached(priority: .userInitiated) { known.spans(lines: lines, page: page) }.value
            if !Task.isCancelled { knownSpans = found }
        }
        .alert("¿Enviar la página a Claude?", isPresented: $askScanConsent) {
            Button("Enviar") { Tutor.scanConsented = true; takeWords() }
            Button("Cancelar", role: .cancel) { preparing = false }
        } message: { Text(isBook ? Tutor.scanConsentMessage : Tutor.articleConsentMessage) }
        .alert(Tutor.consentTitle, isPresented: $askConsent) {
            Button("Enviar") { Tutor.consented = true; settle() }
            if Tutor.onDeviceAvailable { Button("Solo en el iPhone") { settle(claude: false) } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text(Tutor.consentMessage) }
    }

    /// While a new reading's words are on their way. Reading is never held back: it can be read straight away.
    private var preparingView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
            Text(working ?? "Preparando…").font(Typo.text(17, .bold)).foregroundStyle(Palette.ink)
            Text("Primero estudias las palabras que no sabes, y luego lo lees.")
                .font(Typo.text(15)).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Leer sin estudiar") { preparing = false }
                .font(Typo.text(16, .bold))
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private func lines(_ colors: [String: MarkColor]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text(reading.title).font(Typo.display(28)).foregroundStyle(Palette.ink)
                Text(pageFailed && reading.lines.isEmpty ? "No se pudo abrir la página del artículo, ni leer su texto."
                     : pageFailed ? "No se pudo abrir la página del artículo; aquí está su texto. Toca lo que no entiendas y queda guardado."
                     : "Toca lo que no entiendas, o mantén pulsado y desliza para una frase. Amarillo: ya estaba en tu biblioteca. Verde: es nueva." + (highlightKnown ? " Amarillo pálido: ya la has estudiado." : ""))
                    .font(Typo.text(15)).foregroundStyle(Palette.muted)
                    .padding(.bottom, 8)

                ForEach(reading.lines.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 6) {
                        spanish(i, colors)
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

    /// The Spanish line as running text, its tapped words coloured. A tap or a slide records, and shows the meaning.
    private func spanish(_ i: Int, _ colors: [String: MarkColor]) -> some View {
        let line = reading.lines[i]
        let spans = Lectura.spans(reading.marks, line: i, text: line).map { s in
            (span: s, color: colors["\(i).\(s.lowerBound)-\(s.upperBound)"] ?? MarkColor.pending)
        }
        return ReadingText(text: line, words: words[safe: i] ?? [], spans: spans, known: knownSpans[safe: i] ?? [],
                           onTap: { w, rect in tapped(line: i, word: w, rect: rect) },
                           onPick: { span, rect in picked(line: i, span: span, rect: rect) })
            .popover(isPresented: Binding(get: { lookup?.line == i }, set: { if !$0 { lookup = nil } }),
                     attachmentAnchor: .rect(.rect(lookup?.line == i ? lookup!.rect : .zero))) {
                if let l = lookup, let text = phrase(l) {
                    wordLookup(l, text: text, colors: colors, onClose: nil)
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, alignment: .leading)
                        .presentationCompactAdaptation(.popover)
                }
            }
    }

    private func wordLookup(_ l: Lookup, text: String, colors: [String: MarkColor], onClose: (() -> Void)?) -> some View {
        let id = Lectura.markKey(line: l.line, first: l.words.lowerBound, last: l.words.upperBound)
        return WordLookup(text: text, meaning: reading.glosses[id]?.english, color: colors[id] ?? .pending,
                          onRemove: { unmark(l) }, onClose: onClose)
    }

    /// Over the page: the meaning of what was tapped, or a way to record what's selected.
    @ViewBuilder
    private func pagePanel(_ colors: [String: MarkColor]) -> some View {
        if let s = selection, !s.phrase.isEmpty {
            Button { markSelection(s) } label: {
                Label("Guardar «\(s.phrase)»", systemImage: "highlighter").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftButtonStyle(fill: Palette.paper, text: Palette.ink, size: 17))
            .padding(.horizontal, 16)
        } else if let l = lookup, let text = phrase(l) {
            wordLookup(l, text: text, colors: colors, onClose: { lookup = nil })
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

    /// What's next for this page: its words going in, studying them, and more of them when you want them. Reading is
    /// never held back by any of it.
    private var actions: some View {
        VStack(spacing: 8) {
            if let working {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(working).font(Typo.text(15, .bold)).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                if let problem {
                    Text(problem).font(Typo.text(14, .bold)).foregroundStyle(Palette.again)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if allKnown {
                    Text("Ya sabes todas sus palabras.").font(Typo.text(14, .bold)).foregroundStyle(Palette.good)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if library.toStudy > 0 {
                    Button { studyPage() } label: {
                        Text("Estudiar estas palabras · \(library.toStudy)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 18))
                }
                if reading.pageWords == nil, !reading.lines.isEmpty {
                    Button(action: takeWords) {
                        Text(isBook ? "Sacar las palabras de esta página" : "Sacar las palabras de este artículo").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftButtonStyle(fill: Palette.sea, text: .white, size: 18))
                } else if library.waiting > 0, !library.unseen {
                    Button(action: addMore) {
                        Text("Añadir \(min(library.waiting, Prefs.current.newPerScan)) más · quedan \(library.waiting)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftButtonStyle(fill: Palette.sea, text: .white, size: 18))
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }

    // MARK: actions

    /// The whole library, this page's words first.
    private func studyPage() {
        let all = Deck.allCards(ctx)
        let plan = Library.plan(all, first: Set(Library.cards(on: reading, in: all).map(\.id)))
        study(plan.pool, queue: plan.queue, label: reading.title, fresh: plan.fresh)
    }

    /// What opening a reading sets going: an article's text if it hasn't got it yet, then, for a new one, its words.
    private func begin() async {
        var article: Article?
        if reading.lines.isEmpty, let url = pageURL {
            working = "Leyendo el artículo…"
            article = await readArticle(url)
            working = nil
        }
        guard preparing else { return }
        if reading.lines.isEmpty {
            problem = "No encontré el texto de este artículo, así que no hay tarjetas. Puedes leerlo igual."
            preparing = false
        } else if article?.isSpanish == false {
            problem = "Este artículo no parece estar en español, así que no he sacado sus palabras."
            preparing = false
        } else {
            takeWords()
        }
    }

    /// Reads the page's words and adds the first of the new ones to the library.
    private func takeWords() {
        guard Tutor.scanConsented else { askScanConsent = true; return }
        working = isBook ? "Leyendo las palabras de la página…" : "Leyendo las palabras del artículo…"
        problem = nil
        Task {
            do throws(Tutor.Failure) {
                if reading.pageWords == nil { reading.pageWords = try await Tutor.words(lines: Tutor.firstPages(reading.lines)) }
                try? ctx.save()
                working = "Preparando tus tarjetas…"
                try await Library.addNext(from: reading, limit: Prefs.current.newPerScan, ctx: ctx)
            } catch {
                problem = error.message
            }
            working = nil
            studyFirst()
        }
    }

    /// A new reading's words are in: on to studying them, unless they've been left for later or there's nothing to study.
    private func studyFirst() {
        guard preparing else { return }
        preparing = false
        guard problem == nil, onScreen else { return }
        if Library.toStudy(Library.cards(on: reading, in: Deck.allCards(ctx))).isEmpty {
            allKnown = true
        } else {
            studyPage()
        }
    }

    private func addMore() {
        working = "Preparando tus tarjetas…"
        problem = nil
        Task {
            do throws(Tutor.Failure) {
                try await Library.addNext(from: reading, limit: Prefs.current.newPerScan, ctx: ctx)
            } catch {
                problem = error.message
            }
            working = nil
        }
    }

    private func load() {
        words = reading.lines.map(Lectura.words)
        reading.opened = .now
        KnownWords.fetchLemmas()
        if !Tutor.needsConsent { settle() }
    }

    /// Settles the tapped words still waiting, one at a time. One that fails waits until the reading is opened again.
    private func settle(claude: Bool = true) {
        guard !settling else { return }
        settling = true
        Task {
            while let run = Library.unresolved(reading).first(where: { !settleFailed.contains($0.id) }) {
                do throws(Tutor.Failure) {
                    try await Library.record(run, in: reading, claude: claude, ctx: ctx)
                } catch {
                    settleFailed.insert(run.id)
                }
            }
            settling = false
        }
    }

    private func record() {
        if Tutor.needsConsent { askConsent = true } else { settle() }
    }

    /// The article's text, for its words, the Texto view, and in case the page won't open. Paragraphs already marked on
    /// the page keep their place, so their marks still point at them.
    private func readArticle(_ url: URL) async -> Article? {
        guard let a = try? await ArticleReader.read(url) else { return nil }
        reading.lines += Lectura.lines(a.text).filter { !reading.lines.contains($0) }
        if !a.title.isEmpty, reading.title == ArticleText.site(url) { reading.title = a.title }
        return a
    }

    /// A tap on a new word records it; on one already tapped, shows the phrase it's in.
    private func tapped(line i: Int, word w: Int, rect: CGRect) {
        if let span = Lectura.spans(reading.marks, line: i, text: reading.lines[i]).first(where: { $0.contains(w) }) {
            lookup = Lookup(line: i, words: span, rect: rect)
        } else {
            Lectura.mark(&reading.marks, line: i, first: w, last: w)
            UISelectionFeedbackGenerator().selectionChanged()
            lookup = Lookup(line: i, words: w...w, rect: rect)
            record()
        }
    }

    /// A slide across words records them as one phrase, in place of any marks they cross.
    private func picked(line i: Int, span: ClosedRange<Int>, rect: CGRect) {
        Lectura.mark(&reading.marks, line: i, first: span.lowerBound, last: span.upperBound)
        lookup = Lookup(line: i, words: span, rect: rect)
        record()
    }

    private func unmark(_ l: Lookup) {
        guard let line = reading.lines[safe: l.line] else { return }
        if let run = Lectura.runs(lines: reading.lines, marks: reading.marks)
            .first(where: { $0.line == l.line && ($0.first...$0.last).contains(l.words.lowerBound) }) {
            Library.forget(run, in: reading, ctx: ctx)
        }
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

/// What a reading needs from the library. A long library takes a while to go through, so it's worked out off the main thread
/// from a plain copy of the cards: the same answers `Library.cards(on:in:)` and `Library.newWords` give.
nonisolated struct ReadingLibrary: Equatable, Sendable {
    /// The words to highlight, if that's on.
    var known: KnownWords?
    /// The page's cards to learn, or back for review.
    var toStudy = 0
    /// Whether any of the page's cards hasn't been met yet.
    var unseen = false
    /// The page's words waiting to go into the library.
    var waiting = 0

    struct Word: Equatable, Sendable {
        let id: String, es: String, exWord: String, stage: Int, due: Date, sources: [String]
        let isConj: Bool, isDropped: Bool
    }

    /// What the answers depend on.
    struct Inputs: Equatable, Sendable {
        let words: [Word]
        let title: String
        let page: [PageWord]?
        let highlight: Bool
    }

    init() {}

    init(_ s: Inputs, now: Date = .now) {
        known = s.highlight ? KnownWords(s.words.filter { !$0.isConj && !$0.isDropped && $0.stage > 0 }.map { ($0.es, $0.exWord) }) : nil

        let cards = s.words.filter { !$0.isConj }
        var index: [String: Word] = [:]
        for c in cards {
            for k in Library.keys(c.es) where index[k] == nil { index[k] = c }
        }
        let found = { (es: String) in Library.keys(es).lazy.compactMap { index[$0] }.first }
        var onPage = (s.page ?? []).compactMap { found($0.spanish) }
        onPage += cards.filter { c in c.sources.contains { Source($0)?.title == s.title } }
        var seen = Set<String>()
        onPage = onPage.filter { !$0.isDropped && seen.insert($0.id).inserted }

        toStudy = onPage.count { $0.stage < 5 || $0.due <= now.addingTimeInterval(Scheduler.lookahead) }
        unseen = onPage.contains { $0.stage == 0 }
        waiting = (s.page ?? []).count { found($0.spanish) == nil }
    }
}

/// Keeps `ReadingLibrary` up to date, apart from the reading, so it can stop while a session covers the screen. The reading
/// itself has to stay, as it holds the page, and looks at no card: it only redraws when one of these answers changes.
private struct LibraryWatch: View, Equatable {
    let reading: Reading
    /// Which reading, for comparing: SwiftUI may compare off the main actor, where `reading` can't be touched.
    private let readingID: ObjectIdentifier
    let highlight: Bool
    @Binding var library: ReadingLibrary
    @Query(sort: \Card.order) private var cards: [Card]

    init(reading: Reading, highlight: Bool, library: Binding<ReadingLibrary>) {
        self.reading = reading
        readingID = ObjectIdentifier(reading)
        self.highlight = highlight
        _library = library
    }

    /// A binding never compares equal, and the work here shouldn't be redone each time the reading redraws.
    nonisolated static func == (a: LibraryWatch, b: LibraryWatch) -> Bool {
        a.readingID == b.readingID && a.highlight == b.highlight
    }

    var body: some View {
        let source = ReadingLibrary.Inputs(
            words: cards.map { ReadingLibrary.Word(id: $0.id, es: $0.es, exWord: $0.exWord, stage: $0.stage, due: $0.due,
                                                   sources: $0.sources, isConj: $0.isConj, isDropped: $0.isDropped) },
            title: reading.title, page: reading.pageWords, highlight: highlight)
        Color.clear.task(id: source) {
            let found = await Task.detached(priority: .userInitiated) { ReadingLibrary(source) }.value
            if !Task.isCancelled { library = found }
        }
    }
}

/// What the known words in a reading's lines depend on.
private struct KnownLines: Equatable {
    let known: KnownWords?
    let lines: [String]
    let page: [PageWord]
}

/// A word or phrase being looked up, and where it is in its line.
private struct Lookup: Equatable {
    let line: Int
    let words: ClosedRange<Int>
    let rect: CGRect
}
