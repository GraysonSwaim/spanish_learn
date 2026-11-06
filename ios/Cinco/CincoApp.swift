import SwiftUI
import SwiftData

/// Starts a session over some cards. RootView owns the session; Home and the readings call this.
struct StudyAction {
    var run: (_ pool: [Card], _ queue: [Card], _ tab: Tab, _ label: String, _ key: String, _ fresh: [Card]) -> Void = { _, _, _, _, _, _ in }

    func callAsFunction(_ pool: [Card], queue: [Card], tab: Tab = .vocab, label: String, key: String = "", fresh: [Card]) {
        run(pool, queue, tab, label, key, fresh)
    }
}

extension EnvironmentValues {
    @Entry var study = StudyAction()
    /// A study session is covering the screen. Nothing can be seen under it, and what's under it depends on every card, so
    /// redoing it after each answer is what makes the next card slow to come: Home and the readings hold still until it closes.
    @Entry var sessionCovers = false
}

@main
struct CincoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Store.container)
    }
}

/// The one card store, shared by the app and its Siri actions (Intents.swift).
@MainActor
enum Store {
    static let container: ModelContainer = {
        let schema = Schema([Card.self, DayLog.self, Reading.self, Chunk.self])
        // .automatic syncs through the iCloud container in the entitlements, and stays local when there is
        // none (an unsigned simulator build) or no one is signed into iCloud.
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic))
        } catch {
            print("CloudKit store failed, using a local one:", error)
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        }
    }()
}

struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PrefKey.theme) private var theme = "auto"

    @State private var session: StudySession?
    @State private var studying = false
    @State private var covered = false
    #if DEBUG
    @State private var demoReading: Reading?
    @State private var demoLecturas = false
    @State private var demoReview = false
    @State private var demoSettings = false
    @State private var demoNew: Reading?
    #endif

    var body: some View {
        NavigationStack {
            HomeView(session: $session)
                #if DEBUG
                .navigationDestination(item: $demoNew) { ReadingView(reading: $0, isNew: true) }
                #endif
        }
        .environment(\.study, StudyAction(run: start))
        .environment(\.sessionCovers, covered)
        // Once the session has finished sliding up, so nothing changes under it as it comes.
        .task(id: studying) {
            guard studying else { return }
            try? await Task.sleep(for: .seconds(0.6))
            if !Task.isCancelled { covered = true }
        }
        .tint(Palette.accentInk)
        // Capturing the session makes this view depend on it. Without that, a session created in the same
        // tap that opens the cover (a theme) wasn't seen yet and the cover came up empty until a redraw.
        .fullScreenCover(isPresented: $studying) { [current = session] in
            Group {
                if let s = current, !s.isFinished {
                    StudyView(session: s) { closeStudy() }
                } else if let s = current {
                    DoneView(done: s.done, onUndo: s.canUndo ? { s.undo() } : nil) { closeStudy(); session = nil }
                }
            }
            .preferredColorScheme(scheme)
        }
        .preferredColorScheme(scheme)
        .onChange(of: scenePhase, initial: true) { _, p in
            // Merge anything a second device created with the same id, and let old readings go.
            if p == .active {
                Deck.dedupe(ctx)
                Deck.trimOnce(ctx)
                Deck.feedThroughOnce(ctx)
                Lectura.recycle(ctx)
            }
            // The reminder says how many are waiting, so it's written again whenever that may have changed.
            if p != .inactive { Task { await Reminder.refresh(ctx) } }
        }
        #if DEBUG
        .sheet(item: $demoReading) { r in
            NavigationStack { ReadingView(reading: r, isNew: ProcessInfo.processInfo.arguments.contains("-openScan")) }
                .preferredColorScheme(scheme)
        }
        .sheet(isPresented: $demoLecturas) { NavigationStack { LecturasView() }.preferredColorScheme(scheme) }
        .sheet(isPresented: $demoReview) { NavigationStack { ReviewLibraryView() }.preferredColorScheme(scheme) }
        .sheet(isPresented: $demoSettings) { NavigationStack { SettingsView() }.preferredColorScheme(scheme) }
        .task { startDemo() }
        #endif
    }

    /// In one go, so what's underneath is up to date before it starts to show.
    private func closeStudy() {
        covered = false
        studying = false
    }

    /// Starts a session going round stages 1–4, with new cards coming in as there's room. A tense picks up the session
    /// left midway on it (`key`); the library always starts afresh, so words just added are in it.
    private func start(_ pool: [Card], queue: [Card], tab: Tab, label: String, key: String, fresh: [Card]) {
        if !key.isEmpty, let s = session, !s.isFinished, s.key == key { studying = true; return }
        let s = StudySession(queue: queue, tab: tab, label: label, key: key, pool: pool, fresh: fresh, continuous: true, ctx: ctx)
        guard !s.isFinished else { return }
        session = s
        studying = true
    }

    #if DEBUG
    private static func fakeProgress(_ ctx: ModelContext) {
        let extra = (0..<240).map { CardRecord(es: "palabra\($0)", en: "word \($0)", tags: "nivel\($0 % 7 == 0 ? 3 : $0 % 3 == 0 ? 2 : 1)") }
        Deck.importRecords(extra, into: ctx)
        let now = Date.now
        let spread = [(1, 0), (1, 1), (2, 2), (4, 1), (4, 3), (7, 2), (7, 5), (14, 9), (28, 12)]
        for (i, c) in Deck.allCards(ctx).filter({ !$0.isConj }).enumerated() {
            c.stage = 0
            guard i < 130 else { continue }
            if i % 12 == 0 { c.stage = 1 + i % 4; c.lapses = i % 5; c.reps = 4; continue }
            let (interval, days) = spread[i % spread.count]
            (c.stage, c.interval, c.reps, c.lapses) = (5, interval, 6, 0)
            c.due = Calendar.current.date(byAdding: .day, value: days, to: now)!
            c.lastReviewed = Calendar.current.date(byAdding: .day, value: -interval, to: c.due)
        }
        for back in 0..<14 where back % 5 != 3 {
            let date = Calendar.current.date(byAdding: .day, value: -back, to: now)!
            let log = Deck.today(ctx, date: date)
            log.reviewed = 20 + back * 7 % 40
            log.correct = log.reviewed * (70 + back) / 100
        }
        RecallLog.clear()
        for back in 0..<28 {
            let date = Calendar.current.date(byAdding: .day, value: -back, to: now)!
            for i in 0..<4 { RecallLog.add(right: i < 3 || back % (back < 14 ? 3 : 2) == 0, on: date) }
        }
    }

    /// Development: `-demo vocab|conj <taps> [stage]` opens a verb card at that stage and moves it forward
    /// `taps` steps, so each phase can be screenshotted in the simulator.
    private func startDemo() {
        let args = ProcessInfo.processInfo.arguments
        // `-loadSample` fills an empty deck with the sample cards, for the flags below.
        if args.contains("-loadSample") && Deck.allCards(ctx).isEmpty {
            _ = Deck.loadSample(ctx)
        }
        // `-dueSample` makes every word a Dominada card waiting to be tested, for Home's count of reviews.
        if args.contains("-dueSample") {
            for c in Deck.allCards(ctx) where !c.isConj {
                (c.stage, c.interval, c.due) = (5, 1, .distantPast)
            }
        }
        // `-progressSample` gives the library a history, for Home's progress.
        if args.contains("-progressSample") { Self.fakeProgress(ctx) }
        // `-openNew <url>` makes a new reading of that article, as pasting its link does.
        if let i = args.firstIndex(of: "-openNew"), i + 1 < args.count, let url = URL(string: args[i + 1]) {
            let r = Reading(title: ArticleText.site(url), lines: [])
            r.url = url.absoluteString
            ctx.insert(r)
            demoNew = r
            return
        }
        // `-openSettings` opens Ajustes.
        if args.contains("-openSettings") {
            demoSettings = true
            return
        }
        // `-openLecturas` opens Lecturas.
        if args.contains("-openLecturas") {
            demoLecturas = true
            return
        }
        // `-openReview` opens Revisar mi biblioteca, with the first few words in doubt.
        if args.contains("-openReview") {
            demoReview = true
            return
        }
        // `-openScan` opens a sample scanned page, as if just scanned.
        if args.contains("-openScan") {
            let r = Reading(title: "Mi libro · pág. 47", lines: ScanCard.sample)
            r.book = "Mi libro"
            ctx.insert(r)
            demoReading = r
            return
        }
        // `-openReading` opens a sample reading, some of it marked.
        if args.contains("-openReading") {
            let r = Reading(title: "En el mercado", lines: Lectura.lines("""
                Los sábados por la mañana voy al mercado con mi abuela. Ella conoce a todos los vendedores. Siempre compra más de lo que necesita.
                Hoy el frutero nos ha regalado unas naranjas porque mi abuela le echa de menos cuando no viene.
                Al final, volvemos a casa cargadas de bolsas y con ganas de cocinar.
                """))
            r.marks = ["0.6-6", "1.12-14", "2.7-7"]
            ctx.insert(r)
            // `-knowSample` adds words already studied, for the highlighting of words you know.
            if args.contains("-knowSample") {
                Deck.importRecords(["el mercado", "conocer", "comprar", "regalar", "volver", "la casa", "la bolsa", "cocinar"]
                    .map { CardRecord(es: $0, en: "(demo)") }, into: ctx)
                for c in Deck.allCards(ctx) { c.stage = 3 }
            }
            demoReading = r
            return
        }
        // `-openPage <url>` opens a reading of that article's own page.
        if let i = args.firstIndex(of: "-openPage"), i + 1 < args.count {
            let r = Reading(title: "Página", lines: [])
            r.url = args[i + 1]
            ctx.insert(r)
            demoReading = r
            return
        }
        // `-studyCard <spanish>` studies that one card.
        if let i = args.firstIndex(of: "-studyCard"), i + 1 < args.count,
           let c = Deck.allCards(ctx).first(where: { !$0.isConj && TextMatch.noArticle($0.es) == TextMatch.noArticle(args[i + 1]) }) {
            session = StudySession(queue: [c], tab: .vocab, ctx: ctx)
            studying = true
            return
        }
        // `-studyNewest <n>` studies the n most recently added word cards.
        if let i = args.firstIndex(of: "-studyNewest"), i + 1 < args.count, let n = Int(args[i + 1]) {
            let newest = Deck.allCards(ctx).filter { !$0.isConj }.sorted { $0.added > $1.added }.prefix(n)
            session = StudySession(queue: Array(newest), tab: .vocab, ctx: ctx)
            studying = true
            return
        }
        guard let i = args.firstIndex(of: "-demo"), i + 2 < args.count, let taps = Int(args[i + 2]) else { return }
        let tab = Tab(rawValue: args[i + 1]) ?? .vocab
        let stage = i + 3 < args.count ? Int(args[i + 3]) ?? 2 : 2
        let all = Deck.allCards(ctx)
        guard let c = tab == .conj ? all.first(where: { $0.isConj && $0.tense == "preterito" }) : all.first(where: \.isVerb) else { return }
        c.stage = stage
        UserDefaults.standard.set(false, forKey: PrefKey.autoSpeak)
        let s = StudySession(queue: [c], tab: tab, ctx: ctx)
        for _ in 0..<taps {
            switch s.phase {
            case .word: s.showMeaning()
            case .prompt: s.mode == .grid ? s.checkGrid([0: "tuve", 1: "tuviste", 2: "tuvo", 3: "tubimos", 5: "tuvieron"]) : s.reveal()
            default: break
            }
        }
        session = s
        studying = true
    }
    #endif

    private var scheme: ColorScheme? {
        switch theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

struct DoneView: View {
    let done: Int
    /// Brings back the last card, when the session's final swipe was a slip.
    var onUndo: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Mosaic(word: Mosaic.today).frame(height: 140).clipShape(.rect(cornerRadius: 6)).padding(.top, 8)
            Spacer()
            Text("¡Listo!").font(Typo.display(52)).foregroundStyle(Palette.accent)
            Text(done == 0 ? "Sesión terminada." : "Repasaste \(done) \(done == 1 ? "tarjeta" : "tarjetas").")
                .font(Typo.text(19, .bold)).foregroundStyle(Palette.ink)
            Text("No queda nada por repasar ahora.").font(Typo.text(16)).foregroundStyle(Palette.muted)
            Spacer()
            if let onUndo {
                Button("Deshacer la última", systemImage: "arrow.uturn.backward", action: onUndo)
                    .font(Typo.text(16, .heavy)).tint(Palette.accentInk)
            }
            Button("Volver al inicio", action: onClose)
                .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Backdrop())
    }
}
