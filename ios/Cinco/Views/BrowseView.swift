import SwiftUI
import SwiftData

/// Every word, or every conjugation table, searchable, with dropped ones kept apart. Words chosen here can be checked by
/// Claude Sonnet (`CheckWordsSheet`), only after the learner says yes, as it costs far more than anything else.
struct BrowseView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Card.order) private var cards: [Card]
    @AppStorage(PrefKey.tab) private var tabRaw = Tab.vocab.rawValue

    @State private var query = ""
    @State private var showDropped = false
    @State private var selecting = false
    @State private var selection = Set<String>()
    @State private var confirmDelete = false
    @State private var confirmCheck = false
    @State private var tooManyToCheck = false
    @State private var checking: CheckBatch?

    private struct CheckBatch: Identifiable {
        let id = UUID()
        let cards: [Card]
    }

    /// Choosing active words, where Claude can be asked to check them.
    private var canCheck: Bool { selecting && !showDropped && Tab(rawValue: tabRaw) != .conj && Tutor.base != nil }

    private var list: [Card] {
        let tab = Tab(rawValue: tabRaw) ?? .vocab
        let q = TextMatch.strip(query)
        return cards.filter { c in
            Scheduler.inTab(c, tab: tab, tense: Tense.random) && c.isDropped == showDropped
                && (q.isEmpty || [c.es, c.en, c.tags].contains { TextMatch.strip($0).contains(q) })
        }
    }

    var body: some View {
        let list = list
        let picked = list.filter { selection.contains($0.id) }
        List(selection: $selection) {
            if cards.contains(where: \.isConj) {
                Picker("", selection: $tabRaw) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.name).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Picker("", selection: $showDropped) {
                Text("Activas").tag(false)
                Text("Descartadas").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if canCheck { quickPicks }

            if showDropped && !list.isEmpty {
                Text("Están fuera de la rotación. Si recuperas una, vuelve en la etapa donde se quedó.")
                    .font(Typo.text(14)).foregroundStyle(Palette.muted)
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(list.prefix(500)) { c in
                    // While choosing, a plain row: a link would be greyed out.
                    Group {
                        if selecting { row(c) } else { NavigationLink { CardDetailView(card: c) } label: { row(c) } }
                    }
                        .swipeActions {
                            Button(c.isDropped ? "Recuperar" : "Descartar") {
                                c.dropped = c.isDropped ? nil : .now
                                try? ctx.save()
                            }
                            .tint(c.isDropped ? Palette.good : Palette.again)
                        }
                }
            } footer: {
                if list.isEmpty {
                    Text(query.isEmpty ? (showDropped ? "No has descartado ninguna." : "No hay tarjetas.") : "Nada coincide.")
                }
            }
            .listRowBackground(Palette.paper)
        }
        .environment(\.editMode, .constant(selecting ? .active : .inactive))
        .scrollContentBackground(.hidden)
        .background(Backdrop())
        .searchable(text: $query, prompt: "Busca en español, inglés o etiqueta")
        .navigationTitle(selecting ? (picked.isEmpty ? "Elige tarjetas" : "\(picked.count) elegidas") : "Palabras")
        .navigationBarBackButtonHidden(selecting)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Listo" : "Elegir") { withAnimation { selecting.toggle(); selection = [] } }
                    .disabled(!selecting && list.isEmpty)
            }
            if selecting {
                ToolbarItem(placement: .topBarLeading) {
                    let all = picked.count == min(list.count, 500)
                    Button(all ? "Ninguna" : "Todas") { selection = all ? [] : Set(list.prefix(500).map(\.id)) }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(showDropped ? "Recuperar" : "Descartar") {
                        for c in picked { c.dropped = showDropped ? nil : .now }
                        try? ctx.save()
                        selection = []
                    }
                    .disabled(picked.isEmpty)
                    Spacer()
                    if canCheck {
                        Button("Revisar") {
                            if picked.count > Tutor.checkLimit { tooManyToCheck = true } else { confirmCheck = true }
                        }
                        .disabled(picked.isEmpty)
                        Spacer()
                    }
                    Button("Borrar", role: .destructive) { confirmDelete = true }
                        .tint(Palette.again)
                        .disabled(picked.isEmpty)
                }
            }
        }
        .confirmationDialog(picked.count == 1 ? "¿Revisar 1 palabra con Claude?" : "¿Revisar \(picked.count) palabras con Claude?",
                            isPresented: $confirmCheck, titleVisibility: .visible) {
            Button("Revisar") {
                checking = CheckBatch(cards: picked)
                selection = []
                selecting = false
            }
        } message: {
            Text(Tutor.checkConsentMessage)
        }
        .alert("Claude revisa hasta \(Tutor.checkLimit) a la vez", isPresented: $tooManyToCheck) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Has elegido \(picked.count). Quita algunas y vuelve a tocar Revisar.")
        }
        .sheet(item: $checking) { b in CheckWordsSheet(cards: b.cards).checkSheetStyle() }
        .onChange(of: showDropped) { selection = [] }
        .onChange(of: tabRaw) { selection = [] }
        .confirmationDialog(picked.count == 1 ? "¿Borrar 1 tarjeta?" : "¿Borrar \(picked.count) tarjetas?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                Deck.delete(picked, ctx: ctx)
                selection = []
                selecting = false
            }
        } message: {
            Text(picked.first?.isConj == true
                 ? "Esas tablas se quitan de sus verbos, con su progreso, en todos tus dispositivos. No se puede deshacer."
                 : "Desaparecen del mazo, con su progreso, en todos tus dispositivos. No se puede deshacer.")
        }
    }

    /// One tap to choose the words worth checking: the ones being missed, and the ones Revisar mi biblioteca doubts.
    @ViewBuilder
    private var quickPicks: some View {
        let words = cards.filter { !$0.isConj && !$0.isDropped }
        let hard = Stats.struggling(words, limit: Tutor.checkLimit)
        let doubts = Array(MeaningReview.doubtful(words, entries: MeaningReview.entries).prefix(Tutor.checkLimit))
        if !hard.isEmpty || !doubts.isEmpty {
            HStack(spacing: 8) {
                if !hard.isEmpty { pick("Te cuestan", hard) }
                if !doubts.isEmpty { pick("En duda", doubts) }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func pick(_ name: String, _ chosen: [Card]) -> some View {
        Button { selection = Set(chosen.map(\.id)) } label: {
            HStack(spacing: 6) {
                Text(name).font(Typo.text(15, .heavy)).foregroundStyle(Palette.ink)
                Text("\(chosen.count)").font(Typo.text(14, .bold)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).frame(minHeight: 40)
            .background(Palette.sunk, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.edge, lineWidth: 1))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Elegir las que \(name == "Te cuestan" ? "te cuestan" : "están en duda"): \(chosen.count)")
    }

    private func row(_ c: Card) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.es).font(Typo.text(18, .heavy)).foregroundStyle(Palette.ink)
                Text(c.en).font(Typo.text(14)).foregroundStyle(Palette.en)
            }
            .opacity(c.isDropped ? 0.45 : 1)
            Spacer()
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(i <= c.stage ? Palette.stage(i) : Palette.line).frame(width: 6, height: 14)
                }
            }
        }
    }
}

struct CardDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let card: Card
    @State private var editing: EditTarget?
    @State private var checking = false

    var body: some View {
        let verb = card.isConj ? try? ctx.fetch(FetchDescriptor<Card>(predicate: verbPredicate)).first : nil
        ScrollView {
            VStack(spacing: 10) {
                StageTiles(stage: card.stage)
                Text(card.es).font(Typo.display(40)).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                Text(card.en).font(Typo.text(26, .heavy)).foregroundStyle(Palette.en).multilineTextAlignment(.center)
                if !card.ex.isEmpty { Text(card.ex).font(Typo.sentence(18)).foregroundStyle(Palette.muted) }
                if !card.notes.isEmpty { Text(card.notes).font(Typo.text(14)).foregroundStyle(Palette.muted) }
                Button { Speaker.shared.speak(card.es, lang: Prefs.current.voiceLang) } label: { SpeakIcon() }
                if card.isConj, let verb, let t = Tense.named(card.tense) {
                    Text(verb.en).font(Typo.text(15)).foregroundStyle(Palette.en)
                    NamedTable(forms: verb.forms(t.key), tense: t).padding(.top, 8)
                    VerbTables(verb: verb, skip: card.tense, showFirst: false)
                } else if card.isVerb {
                    VerbTables(verb: card, foldedLabel: "Otros tiempos").padding(.top, 8)
                }
                facts.padding(.top, 12)
            }
            .multilineTextAlignment(.center)
            .padding(22)
            .frame(maxWidth: .infinity)
            .panel(radius: 28, shadow: 6)
            .padding(16)

            VStack(spacing: 0) {
                if card.isConj {
                    if let verb {
                        MenuRow(title: "Editar el verbo", sub: "Las tablas se cambian en la tarjeta de «\(verb.es)»") { editing = EditTarget(card: verb) }
                    }
                } else {
                    MenuRow(title: "¿Está bien?", sub: "Compara el significado con Apple Traducir y Apple Intelligence") { checking = true }
                    Divider().overlay(Palette.line)
                    MenuRow(title: "Editar tarjeta", sub: nil) { editing = EditTarget(card: card) }
                }
                Divider().overlay(Palette.line)
                MenuRow(title: card.isDropped ? "Recuperar" : "Descartar", sub: card.isDropped ? "Vuelve a la rotación en su etapa" : "Deja de programarse") {
                    card.dropped = card.isDropped ? nil : .now
                    try? ctx.save()
                }
                if !card.isConj {
                    Divider().overlay(Palette.line)
                    MenuRow(title: "Borrar", sub: "Desaparece del mazo y de todos tus dispositivos") { delete() }
                }
            }
            .buttonStyle(.plain)
            .panel()
            .padding(.horizontal, 16)
        }
        .background(Backdrop())
        .sheet(item: $editing) { t in NavigationStack { EditCardView(card: t.card) } }
        .sheet(isPresented: $checking) { CheckMeaningSheet(card: card).checkSheetStyle() }
    }

    private var verbPredicate: Predicate<Card> {
        let id = card.verbID
        return #Predicate { $0.id == id }
    }

    private var facts: some View {
        let f = Date.FormatStyle(date: .long, time: .omitted).locale(Locale(identifier: "es-MX"))
        var parts: [String] = []
        if let last = card.lastReviewed { parts.append("Último repaso: \(last.formatted(f))") }
        if card.stage == 5 { parts.append("Próximo repaso: \(card.due.formatted(f))") }
        parts.append("Repasos: \(card.reps) · Fallos: \(card.lapses)")
        if let l = card.level, let name = Library.levelNames[l] { parts.append("Nivel: \(name)") }
        if !card.visibleTags.isEmpty { parts.append("Etiquetas: \(card.visibleTags.joined(separator: " "))") }
        return Text(parts.joined(separator: "\n")).font(Typo.text(13)).foregroundStyle(Palette.muted)
    }

    private func delete() {
        Deck.delete([card], ctx: ctx)
        dismiss()
    }
}
