import SwiftUI
import SwiftData

/// One reading, set like the article it came from. A scanned page first feeds the library: its new words go in, to be
/// studied from here, and the session comes back to the page to read it. Tap a word you don't understand, or hold and
/// slide across a phrase, and it's recorded: yellow if it's in the library already, green if it's new to it. Words you
/// know are already highlighted, more palely, until that's turned off.
/// A reading made from a link can also be read on the article's own page (`PageReader`), tapped the same way.
struct ReadingView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.study) private var study
    @Bindable var reading: Reading
    /// Take the page's words straight away, for a page just scanned.
    var justScanned = false
    @Query(sort: \Card.order) private var cards: [Card]
    @AppStorage(PrefKey.highlightKnown) private var highlightKnown = true

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
    @State private var problem: String?
    @State private var askScanConsent = false
    @State private var askConsent = false
    /// Tapped words are settled one at a time, by this.
    @State private var settling = false
    @State private var settleFailed = Set<String>()

    private var pageURL: URL? { reading.url.isEmpty || reading.book != nil ? nil : URL(string: reading.url) }
    private var onPage: Bool { mode == .page && pageURL != nil && !pageFailed }
    private var isBook: Bool { reading.book != nil }
    /// This page's cards in the library.
    private var pageCards: [Card] { Library.cards(on: reading, in: cards) }
    /// The page's words waiting to go into the library.
    private var waiting: Int {
        reading.pageWords.map { Library.newWords($0, index: Library.index(cards)).count } ?? 0
    }

    var body: some View {
        let colors = reading.markColors
        let known = highlightKnown ? Library.known(cards) : nil
        Group {
            if onPage, let url = pageURL {
                PageReader(url: url, lines: reading.lines, marks: reading.marks, colors: colors, known: known, handle: page,
                           onTap: pageTapped, onSelect: pageSelected, onFail: { pageFailed = true })
            } else {
                lines(colors)
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
            VStack(spacing: 8) {
                if onPage { pagePanel(colors) }
                actions
            }
        }
        .onAppear(perform: load)
        .onChange(of: reading.lines.count) { words = reading.lines.map(Lectura.words) }
        .onChange(of: mode) {
            lookup = nil
            selection = nil
        }
        .task {
            if justScanned, isBook, reading.pageWords == nil { takeWords() }
        }
        .task(id: KnownLines(known: known, lines: reading.lines, page: reading.pageWords ?? [])) {
            guard let known else { knownSpans = []; return }
            let (lines, page) = (reading.lines, reading.pageWords ?? [])
            let found = await Task.detached(priority: .userInitiated) { known.spans(lines: lines, page: page) }.value
            if !Task.isCancelled { knownSpans = found }
        }
        .alert("¿Enviar la página a Claude?", isPresented: $askScanConsent) {
            Button("Enviar") { Tutor.scanConsented = true; takeWords() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text(Tutor.scanConsentMessage) }
        .alert(Tutor.consentTitle, isPresented: $askConsent) {
            Button("Enviar") { Tutor.consented = true; settle() }
            if Tutor.onDeviceAvailable { Button("Solo en el iPhone") { settle(claude: false) } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text(Tutor.consentMessage) }
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
        let onThisPage = pageCards
        let toStudy = Library.toStudy(onThisPage).count
        let unseen = onThisPage.contains { $0.stage == 0 }
        return VStack(spacing: 8) {
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
                if toStudy > 0 {
                    Button(action: studyPage) {
                        Text("Estudiar estas palabras · \(toStudy)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 18))
                }
                if isBook, reading.pageWords == nil {
                    Button(action: takeWords) {
                        Text("Sacar las palabras de esta página").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftButtonStyle(fill: Palette.sea, text: .white, size: 18))
                } else if waiting > 0, !unseen {
                    Button(action: addMore) {
                        Text("Añadir \(min(waiting, Prefs.current.newPerScan)) más · quedan \(waiting)").frame(maxWidth: .infinity)
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
        let plan = Library.plan(cards, first: Set(pageCards.map(\.id)))
        study(plan.pool, queue: plan.queue, label: reading.title, fresh: plan.fresh)
    }

    /// Reads the page's words and adds the first of the new ones to the library.
    private func takeWords() {
        guard Tutor.scanConsented else { askScanConsent = true; return }
        working = "Leyendo las palabras de la página…"
        problem = nil
        Task {
            do throws(Tutor.Failure) {
                if reading.pageWords == nil { reading.pageWords = try await Tutor.words(lines: reading.lines) }
                try? ctx.save()
                working = "Preparando tus tarjetas…"
                try await Library.addNext(from: reading, limit: Prefs.current.newPerScan, ctx: ctx)
            } catch {
                problem = error.message
            }
            working = nil
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
        if reading.lines.isEmpty, let url = pageURL { Task { await readArticle(url) } }
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

    /// The article's text, for the Texto view and in case the page won't open. Paragraphs already marked on the page
    /// keep their place, so their marks still point at them.
    private func readArticle(_ url: URL) async {
        guard let a = try? await ArticleReader.read(url) else { return }
        reading.lines += Lectura.lines(a.text).filter { !reading.lines.contains($0) }
        if !a.title.isEmpty, reading.title == ArticleText.site(url) { reading.title = a.title }
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
