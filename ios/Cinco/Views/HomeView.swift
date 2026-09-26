import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Card.order) private var cards: [Card]
    @Query private var logs: [DayLog]

    @AppStorage(PrefKey.tab) private var tabRaw = Tab.vocab.rawValue
    @AppStorage(PrefKey.tense) private var tense = "presente"
    @AppStorage(PrefKey.newPerDay) private var newPerDay = 15

    @Binding var session: StudySession?
    @Binding var studying: Bool
    @State private var importing = false
    @State private var message: String?
    @State private var editing: EditTarget?

    private var tab: Tab { Tab(rawValue: tabRaw) ?? .vocab }
    private var tabCards: [Card] { cards.filter { Scheduler.inTab($0, tab: tab, tense: tense) } }
    private var verbs: [Card] { cards.filter { !$0.isConj && $0.isVerb } }
    private var todayLog: DayLog? { logs.first { $0.key == DayLog.key() } }
    private var newRoom: Int {
        max(0, newPerDay - (tab == .conj ? todayLog?.newConj ?? 0 : todayLog?.newVocab ?? 0))
    }
    /// A session left midway in this tab picks up where it stopped.
    private var resumable: Bool { session.map { !$0.isFinished && $0.tab == tab } ?? false }
    private var stagger: Bool { tab == .conj && tense == Tense.random }

    var body: some View {
        let n = Scheduler.counts(tabCards)
        let newToday = min(newRoom, n.unseen)
        let streak = Scheduler.streak(Dictionary(logs.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }))
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if streak > 0 {
                        Text("Racha: \(streak) \(streak == 1 ? "día" : "días")")
                            .font(Typo.text(13, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(Palette.stage(5), in: .capsule)
                    }
                    Spacer()
                    NavigationLink("Cómo funciona") { HowView() }
                        .font(Typo.text(16, .heavy)).tint(Palette.accentInk)
                }
                .frame(minHeight: 44)

                (Text("Cin").foregroundColor(Palette.accent) + Text("co").foregroundColor(Palette.sea))
                    .font(Typo.display(52))
                    .shadow(color: Palette.edge, radius: 0, x: 3, y: 3)
                    .padding(.top, 14).padding(.bottom, 6)

                tabPicker
                if tab == .conj { TenseSwitch(cards: cards, selection: $tense).padding(.bottom, 12) }

                lede(n, newToday: newToday).padding(.bottom, 18)
                if cards.isEmpty {
                    Button("Cargar el mazo de inicio") { message = Deck.loadStarter(ctx)?.summary }
                        .buttonStyle(ChunkyButtonStyle(fill: Palette.sea, text: .white, size: 19))
                        .padding(.bottom, 22)
                }
                ladder(n)
                Text(newLine(n))
                    .font(Typo.text(14)).foregroundStyle(Palette.muted).padding(.top, 6).padding(.bottom, 8)
                Button("\(n.unseen) nuevas esperando") { startFresh() }
                    .font(Typo.text(15, .heavy)).tint(Palette.accentInk).disabled(n.unseen == 0)
                    .padding(.bottom, 20)

                Button(resumable ? "Seguir la sesión" : "¡Vamos!") { startDaily(newToday: newToday) }
                    .buttonStyle(ChunkyButtonStyle(fill: Palette.accent, text: .white))
                    .disabled(n.due + newToday == 0 && !resumable)
                    .opacity(n.due + newToday == 0 && !resumable ? 0.5 : 1)
                    .padding(.bottom, 22)

                menu
                Text("Tus tarjetas y tu progreso se guardan en iCloud y se sincronizan entre tus dispositivos.")
                    .font(Typo.text(13)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 20)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text],
                      allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .alert("Importar", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
        .sheet(item: $editing) { t in
            NavigationStack { EditCardView(card: t.card) }
        }
    }

    private var tabPicker: some View {
        ChunkySegmented(options: Tab.allCases.map { ($0.rawValue, $0.name) }, selection: $tabRaw)
            .padding(.top, 2).padding(.bottom, 16)
    }

    @ViewBuilder
    private func lede(_ n: DeckCounts, newToday: Int) -> some View {
        let text: Text = if n.total == 0 {
            Text(tab == .conj
                 ? "Aún no hay verbos con conjugación. Importa un CSV con columnas de tiempos (presente, preterito…) o añádelas al editar un verbo."
                 : "Importa un CSV de palabras para empezar.")
        } else if n.due + newToday == 0 {
            Text("Nada pendiente. " + ((todayLog?.reviewed ?? 0) > 0 ? "Hoy repasaste \(todayLog!.reviewed)." : "Vuelve mañana."))
        } else {
            Text("Hoy te tocan ") + Text("\(n.due)").foregroundColor(Palette.ink).bold() + Text(" por repasar")
                + (newToday > 0 ? Text(" y ") + Text("\(newToday)").foregroundColor(Palette.ink).bold() + Text(" nuevas") : Text(""))
                + Text(".")
        }
        text.font(Typo.text(17)).foregroundStyle(Palette.muted)
    }

    private func newLine(_ n: DeckCounts) -> String {
        let what = tab == .conj ? (n.total == 1 ? "tabla" : "tablas") : "en el mazo"
        return "\(n.total) \(what)" + (n.dropped > 0 ? ", \(n.dropped) descartadas" : "") + ". Toca una etapa para practicar solo esas tarjetas."
    }

    private func ladder(_ n: DeckCounts) -> some View {
        let total = max(1, n.total)
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    Button { startStage(i) } label: {
                        ZStack(alignment: .bottom) {
                            Palette.sunk
                            GeometryReader { g in
                                VStack { Spacer(minLength: 0); Palette.stage(i).frame(height: g.size.height * CGFloat(n.byStage[i]) / CGFloat(total)) }
                            }
                            VStack {
                                Text("\(n.byStage[i])").font(Typo.display(22)).foregroundStyle(Palette.ink).padding(.top, 8)
                                Spacer()
                            }
                        }
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.edge, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .disabled(n.byStage[i] == 0)
                    .opacity(n.byStage[i] == 0 ? 0.55 : 1)
                    .accessibilityLabel("Estudiar las \(n.byStage[i]) tarjetas de la etapa \(i), \(StageInfo.all[i].name)")
                }
            }
            .frame(height: 150)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    VStack(spacing: 0) {
                        Text("\(i)").font(Typo.display(15)).foregroundStyle(Palette.ink)
                        Text(StageInfo.all[i].name).font(Typo.text(11.5, .bold)).foregroundStyle(Palette.muted)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var menu: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Importar tarjetas", sub: "CSV de iCloud Drive o exportado de Anki") { importing = true }
            Divider().overlay(Palette.line)
            MenuRow(title: "Añadir una tarjeta", sub: "Escríbela a mano") { editing = EditTarget(card: nil) }
            Divider().overlay(Palette.line)
            NavigationLink { BrowseView() } label: { MenuRowLabel(title: "Explorar tarjetas", sub: nil) }
            Divider().overlay(Palette.line)
            NavigationLink { SettingsView() } label: { MenuRowLabel(title: "Ajustes", sub: nil) }
        }
        .buttonStyle(.plain)
        .panel()
    }

    // MARK: starting sessions

    private func startDaily(newToday: Int) {
        if resumable { studying = true; return }
        let q = Scheduler.dailyQueue(tabCards, newRoom: newRoom, staggerTenses: stagger, verbs: verbs)
        guard !q.isEmpty else { return }
        session = StudySession(queue: q, tab: tab, ctx: ctx)
        studying = true
    }

    private func startStage(_ i: Int) {
        let q = Scheduler.stageQueue(tabCards, stage: i)
        guard !q.isEmpty else { return }
        session = StudySession(queue: q, tab: tab, label: "Etapa \(i)", ctx: ctx)
        studying = true
    }

    private func startFresh() {
        let q = Array(Scheduler.unseen(tabCards, staggerTenses: stagger, verbs: verbs).prefix(newPerDay))
        guard !q.isEmpty else { return }
        session = StudySession(queue: q, tab: tab, label: "Nuevas", ctx: ctx)
        studying = true
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var total = ImportResult()
        for url in urls {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let r = Deck.importRecords(CSVImport.parse(text), into: ctx)
            total.added += r.added; total.updated += r.updated; total.skipped += r.skipped; total.verbs += r.verbs
        }
        message = total.summary
    }
}

struct EditTarget: Identifiable {
    let card: Card?
    var id: String { card?.id ?? "new" }
}

struct MenuRowLabel: View {
    let title: String
    let sub: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.text(16, .bold)).foregroundStyle(Palette.ink)
                if let sub { Text(sub).font(Typo.text(13)).foregroundStyle(Palette.muted) }
            }
            Spacer()
            Text("›").font(Typo.text(24, .heavy)).foregroundStyle(Palette.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .contentShape(.rect)
    }
}

struct MenuRow: View {
    let title: String
    let sub: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) { MenuRowLabel(title: title, sub: sub) }
    }
}

/// The tense picker in the Conjugación tab, grouped by mood, with Aleatorio for all of them.
struct TenseSwitch: View {
    let cards: [Card]
    @Binding var selection: String

    var body: some View {
        let have = Set(cards.filter(\.isConj).map(\.tense))
        let current = Tense.named(selection)
        Menu {
            ForEach(Mood.allCases, id: \.self) { m in
                Section(m.name) {
                    ForEach(Tense.all.filter { $0.mood == m }) { t in
                        Button { selection = t.key } label: {
                            if t.key == selection { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                        }
                        .disabled(!have.contains(t.key))
                    }
                }
            }
            Divider()
            Button { selection = Tense.random } label: {
                if selection == Tense.random { Label("Aleatorio · todos los tiempos", systemImage: "checkmark") } else { Text("Aleatorio · todos los tiempos") }
            }
        } label: {
            HStack {
                Circle().fill(current.map { Palette.mood($0.mood) } ?? Palette.stage(3)).frame(width: 10, height: 10)
                Text(current?.name ?? "Aleatorio · todos los tiempos").font(Typo.text(16, .heavy)).foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(current.map { Palette.moodSoft($0.mood) } ?? Palette.sunk, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.edge, lineWidth: 2))
        }
    }
}
