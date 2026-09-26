import SwiftUI
import SwiftData

@main
struct CincoApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Card.self, DayLog.self])
        // .automatic syncs through the iCloud container in the entitlements, and stays local when there is
        // none (an unsigned simulator build) or no one is signed into iCloud.
        do {
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic))
        } catch {
            print("CloudKit store failed, using a local one:", error)
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
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
        .fullScreenCover(isPresented: $studying) {
            Group {
                if let s = session, !s.isFinished {
                    StudyView(session: s) { studying = false }
                } else if let s = session {
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
            case .answer: s.showForms()
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
            Spacer()
            Text("¡Listo!").font(Typo.display(52)).foregroundStyle(Palette.accent)
                .shadow(color: Palette.edge, radius: 0, x: 3, y: 3)
            Text(done == 0 ? "Sesión terminada." : "Repasaste \(done) \(done == 1 ? "tarjeta" : "tarjetas").")
                .font(Typo.text(19, .bold)).foregroundStyle(Palette.ink)
            Text("Vuelve mañana para lo siguiente.").font(Typo.text(16)).foregroundStyle(Palette.muted)
            Spacer()
            Button("Volver al inicio", action: onClose)
                .buttonStyle(ChunkyButtonStyle(fill: Palette.accent, text: .white))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }
}
