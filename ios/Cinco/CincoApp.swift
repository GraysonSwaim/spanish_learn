import SwiftUI
import SwiftData

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
    #if DEBUG
    @State private var demoReading: Reading?
    @State private var demoLecturas = false
    #endif

    var body: some View {
        NavigationStack {
            HomeView(session: $session)
        }
        .environment(\.study, StudyAction { pool, tab, label, key, fresh in start(pool, tab: tab, label: label, key: key, fresh: fresh) })
        .tint(Palette.accentInk)
        // Capturing the session makes this view depend on it. Without that, a session created in the same
        // tap that opens the cover (a theme) wasn't seen yet and the cover came up empty until a redraw.
        .fullScreenCover(isPresented: $studying) { [current = session] in
            Group {
                if let s = current, !s.isFinished {
                    StudyView(session: s) { studying = false }
                } else if let s = current {
                    DoneView(done: s.done, onUndo: s.canUndo ? { s.undo() } : nil) { studying = false; session = nil }
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
                Lectura.recycle(ctx)
            }
        }
        #if DEBUG
        .sheet(item: $demoReading) { r in NavigationStack { ReadingView(reading: r) }.preferredColorScheme(scheme) }
        .sheet(isPresented: $demoLecturas) { NavigationStack { LecturasView() }.preferredColorScheme(scheme) }
        .task { startDemo() }
        #endif
    }

    /// Studies a theme or a tense: the session left midway on it, or a new one going round its stages 1–4, with its new
    /// cards coming in as there's room.
    private func start(_ pool: [Card], tab: Tab, label: String, key: String, fresh: [Card]) {
        if let s = session, !s.isFinished, s.key == key { studying = true; return }
        let s = StudySession(queue: Scheduler.dailyQueue(pool), tab: tab, label: label, key: key, pool: pool, fresh: fresh,
                             continuous: true, ctx: ctx)
        guard !s.isFinished else { return }
        session = s
        studying = true
    }

    #if DEBUG
    /// Development: `-demo vocab|conj <taps> [stage]` opens a verb card at that stage and moves it forward
    /// `taps` steps, so each phase can be screenshotted in the simulator.
    private func startDemo() {
        let args = ProcessInfo.processInfo.arguments
        // `-loadSample` fills an empty deck with the sample cards, for the flags below.
        if args.contains("-loadSample") && Deck.allCards(ctx).isEmpty {
            Deck.loadSample(ctx)
            // `-sampleThemes` also files most of them into themes, a couple merged, the rest left loose.
            if args.contains("-sampleThemes") {
                let words = Deck.allCards(ctx).filter { !$0.isConj }
                var made: [Chunk] = []
                for (i, name) in ["Saludos", "En el café", "Por la ciudad", "Mi día", "La familia", "Cómo me siento"].enumerated() {
                    let c = Chunks.create(name, ctx: ctx)
                    Chunks.file(Array(words.dropFirst(i * 6).prefix(6)), in: c, ctx: ctx)
                    made.append(c)
                }
                Chunks.merge(made[1], made[2], name: "Salir", ctx: ctx)
            }
        }
        // `-openLecturas` opens Lecturas.
        if args.contains("-openLecturas") {
            demoLecturas = true
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
