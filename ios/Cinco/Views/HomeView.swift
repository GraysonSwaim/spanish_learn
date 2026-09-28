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
        let used = switch tab {
        case .vocab: todayLog?.newVocab ?? 0
        case .conj: todayLog?.newConj ?? 0
        case .phrases: todayLog?.newPhrase ?? 0
        }
        return max(0, newPerDay - used)
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
                Wordmark()
                    .padding(.top, 12).padding(.bottom, 44)

                tabPicker
                if tab == .conj { TenseSwitch(cards: cards, selection: $tense).padding(.bottom, 12) }

                if n.total == 0 {
                    Text(Self.emptyLede[tab] ?? "").font(Typo.text(17)).foregroundStyle(Palette.muted).padding(.bottom, 18)
                } else {
                    Spacer().frame(height: 18)
                }
                if cards.isEmpty {
                    Button("Cargar el mazo de inicio") { message = Deck.loadStarter(ctx)?.summary }
                        .buttonStyle(SoftButtonStyle(fill: Palette.sea, text: .white, size: 19))
                        .padding(.bottom, 22)
                } else if tab == .phrases && tabCards.isEmpty {
                    Button("Cargar las frases de inicio") { message = Deck.loadStarter(ctx, deck: "frases-inicio")?.summary }
                        .buttonStyle(SoftButtonStyle(fill: Palette.sea, text: .white, size: 19))
                        .padding(.bottom, 22)
                }
                ladder(n)
                Button("\(n.unseen) nuevas esperando") { startFresh() }
                    .font(Typo.text(15, .heavy)).tint(Palette.accentInk).disabled(n.unseen == 0)
                    .padding(.top, 12).padding(.bottom, 20)

                Button(resumable ? "Seguir la sesión" : "¡Vamos!") { startDaily(newToday: newToday) }
                .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white))
                .disabled(n.due + newToday == 0 && !resumable)
                .opacity(n.due + newToday == 0 && !resumable ? 0.5 : 1)
                .padding(.bottom, 22)

                menu
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
                .padding(.top, 14)
                Text("Tus tarjetas y tu progreso se guardan en iCloud y se sincronizan entre tus dispositivos.")
                    .font(Typo.text(13)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text],
                      allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .alert("Importar", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
        .sheet(item: $editing) { t in
            NavigationStack { EditCardView(card: t.card, draft: t.phrase ? CardRecord(phrase: true) : nil) }
        }
        #if DEBUG
        // Development: `-lookup <query>` or `-entry <word>` opens the dictionary at launch for screenshots.
        .navigationDestination(item: $debugPage) { page in
            if page.hasPrefix("entry:"), let e = Lexicon.shared.entry(String(page.dropFirst(6))) { EntryView(entry: e) }
            else { LookupView(initial: String(page.dropFirst(7))) }
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            for (flag, prefix) in [("-lookup", "lookup:"), ("-entry", "entry:")] {
                if let i = args.firstIndex(of: flag), i + 1 < args.count { debugPage = prefix + args[i + 1] }
            }
        }
        #endif
    }

    #if DEBUG
    @State private var debugPage: String?
    #endif

    private var tabPicker: some View {
        SoftSegmented(options: Tab.allCases.map { ($0.rawValue, $0.name) }, selection: $tabRaw)
            .padding(.top, 2).padding(.bottom, 16)
    }

    private static let emptyLede: [Tab: String] = [
        .conj: "Aún no hay verbos con conjugación. Importa un CSV con columnas de tiempos (presente, preterito…) o añádelas al editar un verbo.",
        .phrases: "Frases hechas para armar conversaciones: saludos, pedir en un restaurante, preguntar direcciones… Carga las de inicio, añade las tuyas o impórtalas.",
        .vocab: "Importa un CSV de palabras para empezar.",
    ]

    private func ladder(_ n: DeckCounts) -> some View {
        let total = max(1, n.total)
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    Button { if n.byStage[i] > 0 { startStage(i) } } label: {
                        ZStack(alignment: .bottom) {
                            LinearGradient(colors: [Palette.stageSoft(i).opacity(0.9), Palette.stageSoft(i)], startPoint: .top, endPoint: .bottom)
                            GeometryReader { g in
                                VStack { Spacer(minLength: 0); Palette.stage(i).opacity(0.3).frame(height: g.size.height * CGFloat(n.byStage[i]) / CGFloat(total)) }
                            }
                            VStack(spacing: 8) {
                                Text("\(n.byStage[i])").font(Typo.display(22)).foregroundStyle(n.byStage[i] == 0 ? Palette.muted : Palette.ink).padding(.top, 10)
                                Daisy().fill(Palette.stage(i)).frame(width: 16, height: 16)
                                Spacer()
                            }
                        }
                        .clipShape(Scalloped())
                        .overlay(Scalloped().stroke(.white.opacity(0.5), lineWidth: 1))
                        .softShadow(radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
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

    /// Five tiles in a row, lined up with the five stages above.
    private var menu: some View {
        HStack(spacing: 8) {
            NavigationLink { LookupView() } label: { MenuTile(title: "Diccionario", icon: "book.closed.fill", tint: Palette.stage(1)) }
            NavigationLink { BrowseView() } label: { MenuTile(title: "Explorar", icon: "rectangle.stack.fill", tint: Palette.stage(2)) }
            Button { editing = EditTarget(card: nil, phrase: tab == .phrases) } label: {
                MenuTile(title: "Añadir", icon: "plus", tint: Palette.stage(3))
            }
            .accessibilityLabel(tab == .phrases ? "Añadir una frase" : "Añadir una tarjeta")
            NavigationLink { SettingsView() } label: { MenuTile(title: "Ajustes", icon: "gearshape.fill", tint: Palette.stage(4)) }
            Button { importing = true } label: { MenuTile(title: "Importar", icon: "square.and.arrow.down.fill", tint: Palette.stage(5)) }
        }
        .buttonStyle(TileStyle())
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
            // Importing while Frases is open files every row there.
            var recs = CSVImport.parse(text)
            if tab == .phrases { for i in recs.indices { recs[i].phrase = true } }
            let r = Deck.importRecords(recs, into: ctx)
            total.added += r.added; total.updated += r.updated; total.skipped += r.skipped; total.verbs += r.verbs
        }
        message = total.summary
    }
}

struct EditTarget: Identifiable {
    let card: Card?
    /// A new card starts as a phrase (added from the Frases tab).
    var phrase = false
    var id: String { card?.id ?? "new" }
}

/// One of the Home tiles: an icon in its colour over a short name.
private struct MenuTile: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundStyle(tint)
                .frame(height: 24)
            Text(title).font(Typo.text(12, .bold)).foregroundStyle(Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 4)
    }
}

/// A paper tile that presses in a little.
private struct TileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 18)
        configuration.label
            .background(Palette.paper, in: shape)
            .overlay(shape.strokeBorder(Palette.edge, lineWidth: 1))
            .softShadow(radius: down ? 3 : 8, y: down ? 1 : 4)
            .scaleEffect(down ? 0.95 : 1)
            .animation(.spring(duration: 0.18), value: down)
            .contentShape(shape)
    }
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

/// The tense picker in the Conjugación tab: a soft button that opens a sheet of tense chips,
/// grouped by mood, with Aleatorio for all of them.
struct TenseSwitch: View {
    let cards: [Card]
    @Binding var selection: String
    @State private var open = false

    var body: some View {
        let current = Tense.named(selection)
        Button { open = true } label: {
            HStack {
                Circle().fill(current.map { Palette.mood($0.mood) } ?? Palette.stage(3)).frame(width: 10, height: 10)
                Text(current?.name ?? "Aleatorio · todos los tiempos").font(Typo.text(16, .heavy)).foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 14, weight: .heavy)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(current.map { Palette.moodSoft($0.mood) } ?? Palette.sunk, in: .rect(cornerRadius: 16))
            .softShadow(radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tiempo verbal: \(current?.name ?? "Aleatorio")")
        .sheet(isPresented: $open) {
            TensePicker(cards: cards, selection: $selection)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.bg)
                .presentationCornerRadius(28)
        }
        #if DEBUG
        // Development: `-openTenses` opens the sheet at launch so it can be screenshotted.
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-openTenses") { open = true } }
        #endif
    }
}

/// The sheet behind `TenseSwitch`. Each tense is a chip in its mood's colour showing how many
/// verbs have it; tenses no verb has yet are faded and can't be picked.
private struct TensePicker: View {
    let cards: [Card]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let conj = cards.filter { $0.isConj && !$0.isDropped }
        var have: [String: Int] = [:]
        for c in conj { have[c.tense, default: 0] += 1 }
        let total = Set(conj.map(\.verbID)).count
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("¿Qué tiempo practicas?").font(Typo.display(26)).foregroundStyle(Palette.ink)
                    .padding(.top, 26).padding(.bottom, 16)

                chip(Tense.random, label: "Aleatorio · todos los tiempos", count: total,
                     fill: Palette.stage(3))
                    .padding(.bottom, 8)

                ForEach(Mood.allCases, id: \.self) { m in
                    Text(m.name.uppercased()).font(Typo.text(13, .heavy)).tracking(1)
                        .foregroundStyle(Palette.mood(m))
                        .padding(.top, 18).padding(.bottom, 8)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                        ForEach(Tense.all.filter { $0.mood == m }) { t in
                            chip(t.key, label: chipName(t), count: have[t.key] ?? 0,
                                 fill: Palette.mood(m))
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
    }

    /// The mood heading already says "subjuntivo" or "imperativo", so the chip drops it.
    private func chipName(_ t: Tense) -> String {
        let n = t.name.replacingOccurrences(of: " de subjuntivo", with: "")
            .replacingOccurrences(of: "Imperativo ", with: "")
        return n.prefix(1).uppercased() + n.dropFirst()
    }

    private func chip(_ key: String, label: String, count: Int, fill: Color) -> some View {
        let on = key == selection
        return Button {
            selection = key
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(Typo.text(15, .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                Text(count == 0 ? "sin verbos" : "\(count) \(count == 1 ? "verbo" : "verbos")")
                    .font(Typo.text(12, .bold)).opacity(on ? 0.85 : 1)
                    .foregroundStyle(on ? AnyShapeStyle(Palette.onGood) : AnyShapeStyle(Palette.muted))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(on ? Palette.onGood : Palette.ink)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .buttonStyle(ChipStyle(fill: on ? fill : Palette.paper))
        .disabled(count == 0)
        .opacity(count == 0 ? 0.45 : 1)
        .accessibilityLabel("\(label), \(count) \(count == 1 ? "verbo" : "verbos")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A small soft chip that presses in a little.
private struct ChipStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 14)
        configuration.label
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Palette.edge, lineWidth: 1))
            .softShadow(radius: down ? 3 : 6, y: down ? 1 : 3)
            .scaleEffect(down ? 0.96 : 1)
            .animation(.spring(duration: 0.18), value: down)
    }
}
