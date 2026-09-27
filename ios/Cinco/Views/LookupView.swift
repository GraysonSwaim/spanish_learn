import SwiftUI
import SwiftData

/// The dictionary: look a word up (in Spanish, any conjugated form, or English) and add it to the deck.
/// With nothing typed it suggests the most common words the deck doesn't have yet.
struct LookupView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var cards: [Card]
    var initial = ""
    @State private var query = ""
    @State private var filter = "all"
    @State private var added: String?
    @State private var draft: CardRecord?
    /// When the hand-written card's form opened, to confirm a card saved from it.
    @State private var draftOpened: Date?
    /// Added from this screen: they stay in the suggestions, ticked, so the rows don't shift under a finger.
    @State private var justAdded: Set<Int> = []
    @FocusState private var focused: Bool

    private let lex = Lexicon.shared

    /// Spanish of every word card, without article or accents, to mark words already in the deck.
    private var have: Set<String> {
        Set(cards.filter { !$0.isConj }.flatMap { TextMatch.alternatives($0.es).map(TextMatch.noArticle) })
    }

    var body: some View {
        let have = have
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchField.padding(.bottom, 18)
                if !lex.isAvailable {
                    Text("El diccionario no está disponible.").font(Typo.text(16)).foregroundStyle(Palette.muted)
                } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    suggestions(have)
                } else {
                    results(have)
                }
                Text(lex.credits)
                    .font(Typo.text(12)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 22)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Backdrop())
        .navigationTitle("Diccionario")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .overlay(alignment: .bottom) { toast }
        .onAppear { if query.isEmpty { query = initial } }
        .sheet(item: $draft, onDismiss: confirmDraft) { d in NavigationStack { EditCardView(card: nil, draft: d) } }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .heavy)).foregroundStyle(Palette.muted)
            TextField("", text: $query, prompt: Text("pedir, pidió, to ask…").foregroundStyle(Palette.muted.opacity(0.7)))
                .font(Typo.text(18, .bold)).foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).focused($focused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Palette.muted)
                }
                .accessibilityLabel("Borrar")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .panel(radius: 16, shadow: 3)
    }

    @ViewBuilder
    private func suggestions(_ have: Set<String>) -> some View {
        let pos = filter == "all" ? nil : filter
        let list = lex.top(pos == nil ? 400 : 250, pos: pos)
            .filter { e in (justAdded.contains(e.id) || !have.contains(TextMatch.noArticle(e.word)))
                && (pos != nil || Self.content.contains(e.senses.first?.pos ?? "")) }
            .prefix(40)
        Text("Las más comunes que aún no tienes").font(Typo.display(22)).foregroundStyle(Palette.ink).padding(.bottom, 10)
        SoftSegmented(options: [("all", "Todas"), ("verb", "Verbos"), ("noun", "Sustantivos"), ("adj", "Adjetivos")],
                        selection: $filter, size: 14)
            .padding(.bottom, 16)
        rows(Array(list), have: have)
    }

    @ViewBuilder
    private func results(_ have: Set<String>) -> some View {
        let list = lex.search(query)
        let typed = query.trimmingCharacters(in: .whitespaces)
        if list.isEmpty && have.contains(TextMatch.noArticle(typed)) {
            Label("«\(typed)» no está en el diccionario, pero ya está en tu mazo.", systemImage: "checkmark.circle.fill")
                .font(Typo.text(16, .bold)).foregroundStyle(Palette.good)
        } else if list.isEmpty {
            Text("No encontré «\(typed)». Prueba con otra forma de la palabra o con su significado en inglés, o escribe tú la tarjeta.")
                .font(Typo.text(16)).foregroundStyle(Palette.muted).padding(.bottom, 16)
            Button("Escribir «\(typed)» a mano") { draftOpened = .now; draft = CardRecord(es: typed) }
                .buttonStyle(SoftButtonStyle(fill: Palette.sea, text: .white, size: 19))
        } else {
            rows(list, have: have)
            Button { draftOpened = .now; draft = CardRecord(es: typed) } label: {
                Text("¿No es lo que buscas? ").foregroundStyle(Palette.muted)
                    + Text("Escríbela a mano").foregroundStyle(Palette.accentInk)
            }
            .font(Typo.text(15, .heavy)).buttonStyle(.plain)
            .frame(maxWidth: .infinity).padding(.top, 16)
        }
    }

    private func rows(_ list: [LexEntry], have: Set<String>) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                if i > 0 { Divider().overlay(Palette.line) }
                let inDeck = have.contains(TextMatch.noArticle(e.word))
                HStack(spacing: 10) {
                    NavigationLink { EntryView(entry: e) } label: { LexRow(entry: e) }
                        .buttonStyle(.plain)
                    if inDeck {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(Palette.good)
                            .accessibilityLabel("Ya está en tu mazo")
                    } else {
                        Button { quickAdd(e) } label: {
                            Image(systemName: "plus").font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Palette.accent, in: .circle)
                                .shadow(color: Palette.accent.opacity(0.35), radius: 6, y: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Añadir \(e.word) a tus tarjetas")
                    }
                }
                .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 11)
            }
        }
        .panel()
    }

    @ViewBuilder
    private var toast: some View {
        if let added {
            Text(added)
                .font(Typo.text(15, .heavy)).foregroundStyle(Palette.onGood)
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(Palette.good, in: .capsule)
                .softShadow(radius: 12, y: 6)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Adds the word with its first meaning and, for a verb, the six core tenses.
    private func quickAdd(_ e: LexEntry) {
        let rec = e.record(senses: Array(e.senses.prefix(1)), tenses: LexEntry.coreTenses)
        let error = Deck.save(rec, editing: nil, ctx: ctx)
        if error == nil { justAdded.insert(e.id) }
        show(error ?? "«\(rec.es)» añadida")
    }

    private func confirmDraft() {
        guard let opened = draftOpened else { return }
        draftOpened = nil
        if let c = cards.first(where: { !$0.isConj && $0.added >= opened }) { show("«\(c.es)» añadida") }
    }

    private func show(_ message: String) {
        withAnimation(.snappy) { added = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { if added == message { added = nil } }
        }
    }

    /// Parts of speech worth a card on their own; "de", "que" and "la" aren't.
    private static let content: Set<String> = ["noun", "verb", "adj", "adv", "intj", "phrase"]
}

/// A dictionary word in a list: the word with its article, what it is, and its first meaning.
struct LexRow: View {
    let entry: LexEntry

    var body: some View {
        let first = entry.senses.first
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.spanish(for: first)).font(Typo.text(18, .heavy)).foregroundStyle(Palette.ink)
                Text(entry.pos.prefix(2).map(LexEntry.posName).joined(separator: ", "))
                    .font(Typo.text(12, .bold)).foregroundStyle(Palette.muted)
            }
            if let first {
                Text(LexEntry.short(first.g)).font(Typo.text(15)).foregroundStyle(Palette.en).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

/// One dictionary word in full: its meanings (tap to choose which go on the card), examples and,
/// for a verb, its conjugation tables. The card it will make is shown, editable, before adding.
struct EntryView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var cards: [Card]
    let entry: LexEntry

    @State private var chosen: Set<Int> = [0]
    @State private var tenses: Set<String> = LexEntry.coreTenses
    @State private var es = ""
    @State private var en = ""
    /// What the preview last filled in, so a hand edit isn't overwritten when the meanings change.
    @State private var auto = ("", "")
    @State private var showTables = false
    @State private var message: String?

    private var chosenSenses: [LexEntry.Sense] {
        entry.senses.indices.filter(chosen.contains).map { entry.senses[$0] }
    }

    private var inDeck: Bool {
        let w = TextMatch.noArticle(entry.word)
        return cards.contains { !$0.isConj && TextMatch.alternatives($0.es).map(TextMatch.noArticle).contains(w) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 20)
                section("Significados")
                meanings.padding(.bottom, 22)
                if !entry.sentences.isEmpty {
                    section("En una frase")
                    sentenceList.padding(.bottom, 22)
                }
                if !entry.origin.isEmpty {
                    section("Origen")
                    Text(entry.origin).font(Typo.text(15)).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).panel(radius: 16, shadow: 3)
                        .padding(.bottom, 22)
                }
                if entry.isVerb {
                    section("Conjugación")
                    conjugation.padding(.bottom, 22)
                }
                section("Tu tarjeta")
                preview.padding(.bottom, 20)
                addButton
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Backdrop())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear(perform: refresh)
        .onChange(of: chosen) { refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(entry.spanish(for: chosenSenses.first ?? entry.senses.first))
                    .font(Typo.display(40)).foregroundStyle(Palette.ink)
                Button { Speaker.shared.speak(entry.word, lang: Prefs.current.voiceLang) } label: { SpeakIcon() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Escúchala")
            }
            HStack(spacing: 8) {
                ForEach(entry.pos.prefix(3), id: \.self) { p in
                    Text(LexEntry.posName(p)).font(Typo.text(13, .heavy)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Palette.seaSoft, in: .capsule)
                }
                if !entry.ipa.isEmpty {
                    Text(entry.ipa).font(Typo.text(14)).foregroundStyle(Palette.muted)
                }
            }
            Text(entry.id <= Lexicon.shared.common ? "Nº \(entry.id) entre las palabras más usadas" : "Palabra extra del diccionario de Cinco")
                .font(Typo.text(13, .bold)).foregroundStyle(Palette.muted)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(Typo.text(13, .heavy)).tracking(1).foregroundStyle(Palette.accentInk)
            .padding(.bottom, 8)
    }

    private var meanings: some View {
        VStack(spacing: 0) {
            ForEach(Array(entry.senses.enumerated()), id: \.offset) { i, s in
                if i > 0 { Divider().overlay(Palette.line) }
                Button {
                    if chosen.contains(i) { if chosen.count > 1 { chosen.remove(i) } } else { chosen.insert(i) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: chosen.contains(i) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(chosen.contains(i) ? Palette.good : Palette.muted)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(s.g).font(Typo.text(16, .bold)).foregroundStyle(Palette.en)
                                    .multilineTextAlignment(.leading)
                            }
                            let labels = ([entry.pos.count > 1 ? LexEntry.posName(s.pos) : nil]
                                          + s.t.map(LexEntry.labelName)).compactMap { $0 }
                            if !labels.isEmpty {
                                Text(labels.joined(separator: " · ")).font(Typo.text(12, .heavy)).foregroundStyle(Palette.muted)
                            }
                            ForEach(s.ex, id: \.self) { ex in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ex.es).font(Typo.italic(15)).foregroundStyle(Palette.ink)
                                    Text(ex.en).font(Typo.text(13)).foregroundStyle(Palette.en)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen.contains(i) ? .isSelected : [])
            }
        }
        .panel()
    }

    private var sentenceList: some View {
        VStack(spacing: 0) {
            ForEach(Array(entry.sentences.enumerated()), id: \.offset) { i, ex in
                if i > 0 { Divider().overlay(Palette.line) }
                Button { Speaker.shared.speak(ex.es, lang: Prefs.current.voiceLang) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.sea).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.es).font(Typo.italic(16)).foregroundStyle(Palette.ink)
                            Text(ex.en).font(Typo.text(14)).foregroundStyle(Palette.en)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .panel()
    }

    private var conjugation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cada tiempo marcado será una tarjeta en Conjugación.")
                .font(Typo.text(14)).foregroundStyle(Palette.muted)
            FlowChips(items: Tense.all.filter { entry.tenses[$0.key] != nil }, selected: $tenses)
            Button { withAnimation(.snappy) { showTables.toggle() } } label: {
                HStack {
                    Text(showTables ? "Ocultar las tablas" : "Ver las tablas").font(Typo.text(15, .heavy))
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .heavy))
                        .rotationEffect(.degrees(showTables ? 180 : 0))
                }
                .foregroundStyle(Palette.accentInk)
            }
            .buttonStyle(.plain)
            if showTables {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Tense.all.filter { tenses.contains($0.key) && entry.tenses[$0.key] != nil }) { t in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(t.name).font(Typo.display(18)).foregroundStyle(Palette.mood(t.mood))
                            ConjTable(forms: TextMatch.splitForms(entry.tenses[t.key]), tense: t.key) { p in
                                Text(TextMatch.splitForms(entry.tenses[t.key])[p])
                                    .font(Typo.text(16, .heavy)).foregroundStyle(Palette.ink)
                            }
                        }
                    }
                }
                .padding(14)
                .panel()
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            field("Español", text: $es)
            Divider().overlay(Palette.line)
            field("Inglés", text: $en)
        }
        .panel()
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Typo.text(12, .heavy)).foregroundStyle(Palette.muted)
            TextField(label, text: text, axis: .vertical)
                .font(Typo.text(18, .bold)).foregroundStyle(label == "Inglés" ? Palette.en : Palette.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    @ViewBuilder
    private var addButton: some View {
        if inDeck {
            Label(message ?? "Ya está en tu mazo", systemImage: "checkmark.circle.fill")
                .font(Typo.display(20)).foregroundStyle(Palette.good)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
        } else {
            Button("Añadir a mis tarjetas") { add() }
                .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white))
                .disabled(es.trimmingCharacters(in: .whitespaces).isEmpty || en.trimmingCharacters(in: .whitespaces).isEmpty)
            if let message {
                Text(message).font(Typo.text(15, .bold)).foregroundStyle(Palette.again)
                    .frame(maxWidth: .infinity).padding(.top, 12)
            }
        }
    }

    /// Keeps the preview in step with the chosen meanings until the learner edits it by hand.
    private func refresh() {
        let r = entry.record(senses: chosenSenses, tenses: tenses)
        if es == auto.0 { es = r.es }
        if en == auto.1 { en = r.en }
        auto = (r.es, r.en)
    }

    private func add() {
        let rec = entry.record(senses: chosenSenses, tenses: tenses, es: es.trimmingCharacters(in: .whitespaces),
                               en: en.trimmingCharacters(in: .whitespaces))
        if let error = Deck.save(rec, editing: nil, ctx: ctx) {
            message = error
        } else {
            message = entry.isVerb && !tenses.isEmpty
                ? "Añadida, con \(tenses.count) \(tenses.count == 1 ? "tabla" : "tablas") en Conjugación"
                : "Añadida. La verás entre las nuevas."
        }
    }
}

/// Tense chips that wrap onto as many lines as they need; tapping one toggles it.
struct FlowChips: View {
    let items: [Tense]
    @Binding var selected: Set<String>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { t in
                let on = selected.contains(t.key)
                Button {
                    if on { selected.remove(t.key) } else { selected.insert(t.key) }
                } label: {
                    Text(t.name).font(Typo.text(14, .heavy))
                        .foregroundStyle(on ? Palette.onGood : Palette.ink)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(on ? Palette.mood(t.mood) : Palette.paper, in: .capsule)
                        .overlay(Capsule().strokeBorder(on ? .clear : Palette.edge, lineWidth: 1))
                        .softShadow(radius: on ? 5 : 3, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Lays its children out left to right, wrapping to a new line when one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var r = rows[rows.count - 1]
            r.width += (r.items.isEmpty ? 0 : spacing) + size.width
            r.height = max(r.height, size.height)
            r.items.append(i)
            rows[rows.count - 1] = r
        }
        return rows
    }
}
