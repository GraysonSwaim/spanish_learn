import SwiftUI
import SwiftData

/// One reading, line by line. Español → inglés: tap the words you don't know to mark them, and write your English under
/// each line. Inglés → español (Al revés): write the Spanish again from the English, then compare. Claude checks either
/// way; Tarjetas turns the marked words into cards.
struct ReadingView: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var reading: Reading
    @Query private var cards: [Card]

    @State private var backwards = false
    @State private var words: [[Range<String.Index>]] = []
    @State private var known = Set<String>()
    /// Al revés lines whose original is showing before a check.
    @State private var peek = Set<Int>()
    /// es-en lines whose translation from Claude is showing although the learner left them blank.
    @State private var shown = Set<Int>()
    @FocusState private var focus: Int?
    @State private var busy = false
    @State private var error: String?
    @State private var askConsent = false
    @State private var makingCards = false

    private var runs: [Run] { Lectura.runs(lines: reading.lines, marks: reading.marks) }
    private var current: Tutor.Check? { backwards ? reading.backCheck : reading.check }
    private var written: Int {
        (backwards ? reading.back : reading.english).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text(reading.title).font(Typo.display(28)).foregroundStyle(Palette.ink)
                SoftSegmented(options: [(false, "Español → inglés"), (true, "Inglés → español")], selection: $backwards, size: 15)
                Text(backwards
                     ? "Escribe cada línea en español sin mirar el original. Luego revisa."
                     : "Toca las palabras que no conoces y escribe tu traducción debajo de cada línea.")
                    .font(Typo.text(15)).foregroundStyle(Palette.muted)

                ForEach(reading.lines.indices, id: \.self) { i in
                    Group { if backwards { backRow(i) } else { row(i) } }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel(radius: 18, shadow: 2)
                }

                if let c = current { extras(c) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Backdrop())
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actions }
        .environment(\.openURL, OpenURLAction { url in
            toggle(url)
            return .handled
        })
        .onAppear(perform: load)
        .alert(Tutor.consentTitle, isPresented: $askConsent) {
            Button("Enviar") { Tutor.consented = true; review() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text(Tutor.consentMessage) }
        .alert("Revisar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .sheet(isPresented: $makingCards) {
            NavigationStack { ReadingCardsView(reading: reading) }
        }
    }

    // MARK: rows

    private func row(_ i: Int) -> some View {
        let c = reading.check?.lines[safe: i]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                spanish(i)
                Spacer(minLength: 4)
                speakButton(reading.lines[i])
            }
            TextField("Tu traducción…", text: lineBinding(i, \.english), axis: .vertical)
                .font(Typo.text(17)).foregroundStyle(Palette.en)
                .focused($focus, equals: i)
                .submitLabel(.next)
            if let c {
                if c.verdict == "blank" {
                    if shown.contains(i) {
                        Text(c.better).font(Typo.italic(15)).foregroundStyle(Palette.muted)
                    } else if !c.better.isEmpty {
                        Button("Ver la traducción") { shown.insert(i) }.font(Typo.text(14, .heavy)).tint(Palette.accentInk)
                    }
                } else {
                    LineVerdict(check: c, betterLabel: "Mejor")
                }
            }
        }
    }

    private func backRow(_ i: Int) -> some View {
        let c = reading.backCheck?.lines[safe: i]
        let source = reading.source(i)
        return VStack(alignment: .leading, spacing: 10) {
            Text(source.isEmpty ? "Traduce esta línea primero en Español → inglés." : source)
                .font(Typo.text(18, .bold)).foregroundStyle(source.isEmpty ? Palette.muted : Palette.en)
            if !source.isEmpty {
                TextField("En español…", text: lineBinding(i, \.back), axis: .vertical)
                    .font(Typo.text(17)).foregroundStyle(Palette.ink)
                    .focused($focus, equals: i)
                    .submitLabel(.next)
                    .textInputAutocapitalization(.sentences)
                    // Autocorrect would put in the accents and spellings this is meant to practise.
                    .autocorrectionDisabled()
                if let c, c.verdict != "blank" {
                    LineVerdict(check: c, betterLabel: "Corregido")
                }
                if c != nil || peek.contains(i) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Original").font(Typo.text(12, .heavy)).foregroundStyle(Palette.muted).textCase(.uppercase)
                        spanish(i)
                    }
                } else {
                    Button("Ver el original") { peek.insert(i) }.font(Typo.text(14, .heavy)).tint(Palette.accentInk)
                }
            }
        }
    }

    /// The Spanish line, every word a link: tapping marks or unmarks it. Marked words are highlighted (a phrase as one
    /// band), and words already in the deck are underlined with dots.
    private func spanish(_ i: Int) -> some View {
        let line = reading.lines[i]
        let ws = words[safe: i] ?? []
        let on = Lectura.marked(reading.marks, line: i)
        var out = AttributedString()
        var cursor = line.startIndex
        for (w, r) in ws.enumerated() {
            var gap = AttributedString(String(line[cursor..<r.lowerBound]))
            if w > 0, on.contains(w), on.contains(w - 1), Lectura.joins(line[cursor..<r.lowerBound]) {
                gap.backgroundColor = Palette.mark
            }
            out += gap
            let word = String(line[r])
            var a = AttributedString(word)
            a.link = URL(string: "cinco-word:\(i).\(w)")
            if on.contains(w) {
                a.backgroundColor = Palette.mark
            } else if known.contains(TextMatch.strip(word)) {
                a.underlineStyle = Text.LineStyle(pattern: .dot, color: Palette.sea)
            }
            out += a
            cursor = r.upperBound
        }
        out += AttributedString(String(line[cursor...]))
        return Text(out)
            .font(Typo.text(20, .bold))
            .foregroundStyle(Palette.ink)
            .tint(Palette.ink)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func speakButton(_ text: String) -> some View {
        Button {
            Speaker.shared.speak(text, lang: Prefs.current.voiceLang)
        } label: {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.muted)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Escuchar la línea")
    }

    /// Claude's notes on the text, and the words it thinks you missed, each a tap away from being marked.
    @ViewBuilder
    private func extras(_ c: Tutor.Check) -> some View {
        let unmarked = c.missed.filter { m in
            guard let line = reading.lines[safe: m.line], let ws = Lectura.find(m.text, in: line) else { return false }
            let on = Lectura.marked(reading.marks, line: m.line)
            return !ws.allSatisfy(on.contains)
        }
        if !unmarked.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Parece que no conocías").font(Typo.text(15, .heavy)).foregroundStyle(Palette.ink)
                FlowLayout(spacing: 8) {
                    ForEach(unmarked, id: \.self) { m in
                        Button { mark(m) } label: {
                            Label(m.text, systemImage: "plus").font(Typo.text(15, .bold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Palette.mark, in: .capsule)
                                .foregroundStyle(Palette.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Marcarlas todas") { unmarked.forEach(mark) }.font(Typo.text(14, .heavy)).tint(Palette.accentInk)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).panel(radius: 18, shadow: 2)
        }
        if !c.notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Notas", systemImage: "sparkles").font(Typo.text(15, .heavy)).foregroundStyle(Palette.ink)
                ForEach(c.notes, id: \.self) { n in
                    Text(n).font(Typo.text(15)).foregroundStyle(Palette.ink)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).panel(radius: 18, shadow: 2)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: review) {
                if busy { ProgressView().tint(.white) } else { Label("Revisar", systemImage: "sparkles") }
            }
            .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 18))
            .disabled(busy || written == 0 || !Tutor.available)
            .opacity(written == 0 || !Tutor.available ? 0.5 : 1)

            let n = runs.filter { !reading.carded.contains($0.id) }.count
            Button { makingCards = true } label: { Text(n > 0 ? "Tarjetas · \(n)" : "Tarjetas") }
                .buttonStyle(SoftButtonStyle(fill: Palette.sea, text: .white, size: 18))
                .disabled(runs.isEmpty)
                .opacity(runs.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }

    // MARK: actions

    private func load() {
        words = reading.lines.map(Lectura.words)
        known = Lectura.knownWords(cards)
        // An older reading, or one synced from a device with fewer lines written, gets room for every line.
        if reading.english.count < reading.lines.count {
            reading.english += Array(repeating: "", count: reading.lines.count - reading.english.count)
        }
        if reading.back.count < reading.lines.count {
            reading.back += Array(repeating: "", count: reading.lines.count - reading.back.count)
        }
        reading.opened = .now
    }

    /// Return moves on to the next line instead of starting a new one.
    private func lineBinding(_ i: Int, _ path: ReferenceWritableKeyPath<Reading, [String]>) -> Binding<String> {
        Binding(
            get: { reading[keyPath: path][safe: i] ?? "" },
            set: { v in
                guard i < reading[keyPath: path].count else { return }
                if v.contains("\n") {
                    reading[keyPath: path][i] = v.replacingOccurrences(of: "\n", with: "")
                    focus = i + 1 < reading.lines.count ? i + 1 : nil
                } else {
                    reading[keyPath: path][i] = v
                }
            })
    }

    private func toggle(_ url: URL) {
        guard url.scheme == "cinco-word" else { return }
        let key = url.absoluteString.replacingOccurrences(of: "cinco-word:", with: "")
        if let k = reading.marks.firstIndex(of: key) { reading.marks.remove(at: k) } else { reading.marks.append(key) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func mark(_ m: Tutor.Missed) {
        guard let line = reading.lines[safe: m.line], let ws = Lectura.find(m.text, in: line) else { return }
        for w in ws where !reading.marks.contains(Lectura.markKey(line: m.line, word: w)) {
            reading.marks.append(Lectura.markKey(line: m.line, word: w))
        }
    }

    private func review() {
        guard Tutor.consented else { askConsent = true; return }
        focus = nil
        busy = true
        let back = backwards
        let lines = reading.lines.indices.map { i in
            back
                ? Tutor.LineInput(spanish: reading.lines[i], english: reading.source(i), attempt: reading.back[safe: i] ?? "")
                : Tutor.LineInput(spanish: reading.lines[i], attempt: reading.english[safe: i] ?? "")
        }
        Task {
            do throws(Tutor.Failure) {
                let c = try await Tutor.check(title: reading.title, lines: lines, enToEs: back)
                if back { reading.backCheck = c } else { reading.check = c }
                try? ctx.save()
            } catch {
                self.error = error.message
            }
            busy = false
        }
    }
}

/// A line's verdict: a coloured dot and word, the comment, and the better version when it differs.
private struct LineVerdict: View {
    let check: Tutor.LineCheck
    let betterLabel: String

    private var color: Color {
        switch check.verdict {
        case "good": Palette.good
        case "close": Palette.near
        default: Palette.again
        }
    }

    private var word: String {
        switch check.verdict {
        case "good": "Bien"
        case "close": "Casi"
        default: "No del todo"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(word).font(Typo.text(14, .heavy)).foregroundStyle(color)
            }
            if !check.comment.isEmpty {
                Text(check.comment).font(Typo.text(15)).foregroundStyle(Palette.ink)
            }
            if check.verdict != "good", !check.better.isEmpty {
                (Text("\(betterLabel): ").font(Typo.text(14, .heavy)) + Text(check.better).font(Typo.italic(15)))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: .rect(cornerRadius: 12))
    }
}

/// Lays its children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { r in r.last.map { $0.x + $0.size.width } ?? 0 }.max() ?? 0
        let height = rows.last.flatMap { r in r.map { $0.y + $0.size.height }.max() } ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var i = 0
        for row in arrange(subviews, width: bounds.width) {
            for p in row {
                subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: ProposedViewSize(p.size))
                i += 1
            }
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [[(x: CGFloat, y: CGFloat, size: CGSize)]] {
        var rows: [[(x: CGFloat, y: CGFloat, size: CGSize)]] = [[]]
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append([])
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rows[rows.count - 1].append((x, y, size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return rows
    }
}
