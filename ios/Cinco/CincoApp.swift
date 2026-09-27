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

/// The one card store, shared by the app and its Shortcuts actions (Intents.swift).
@MainActor
enum Store {
    static let container: ModelContainer = {
        let schema = Schema([Card.self, DayLog.self])
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

    var body: some View {
        NavigationStack {
            HomeView(session: $session, studying: $studying)
        }
        .tint(Palette.accentInk)
        // Capturing the session makes this view depend on it. Without that, a session created in the same
        // tap that opens the cover (¡Vamos!) wasn't seen yet and the cover came up empty until a redraw.
        .fullScreenCover(isPresented: $studying) { [current = session] in
            Group {
                if let s = current, !s.isFinished {
                    StudyView(session: s) { studying = false }
                } else if let s = current {
                    DoneView(done: s.done) { studying = false; session = nil }
                }
            }
            .preferredColorScheme(scheme)
        }
        .preferredColorScheme(scheme)
        .onChange(of: scenePhase, initial: true) { _, p in
            // Merge anything a second device created with the same id.
            if p == .active { Deck.dedupe(ctx) }
        }
        #if DEBUG
        .task {
            Deck.importFromLaunchArguments(ctx)
            startDemo()
        }
        #endif
    }

    #if DEBUG
    /// Development: `-demo vocab|conj <taps> [stage]` opens a verb card at that stage and moves it forward
    /// `taps` steps, so each phase can be screenshotted in the simulator.
    private func startDemo() {
        let args = ProcessInfo.processInfo.arguments
        // `-studyCard <spanish>` studies that one card.
        if let i = args.firstIndex(of: "-studyCard"), i + 1 < args.count,
           let c = Deck.allCards(ctx).first(where: { !$0.isConj && TextMatch.noArticle($0.es) == TextMatch.noArticle(args[i + 1]) }) {
            session = StudySession(queue: [c], tab: c.isPhrase ? .phrases : .vocab, ctx: ctx)
            studying = true
            return
        }
        // `-studyNewest <n>` studies the n most recently added word cards, e.g. ones from the dictionary.
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
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Bunting(count: 7, flag: 38, spacing: 8).padding(.top, 8)
            Spacer()
            Text("¡Listo!").font(Typo.display(52)).foregroundStyle(Palette.accent)
            Text(done == 0 ? "Sesión terminada." : "Repasaste \(done) \(done == 1 ? "tarjeta" : "tarjetas").")
                .font(Typo.text(19, .bold)).foregroundStyle(Palette.ink)
            Text("Vuelve mañana para lo siguiente.").font(Typo.text(16)).foregroundStyle(Palette.muted)
            Spacer()
            Button("Volver al inicio", action: onClose)
                .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Backdrop())
    }
}
