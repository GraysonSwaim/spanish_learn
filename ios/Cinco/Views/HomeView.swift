import SwiftUI
import SwiftData

/// Home: how many words there are, the loose ones waiting for a theme, and the themes. Tapping a theme studies it;
/// there's no one big button. Verbs' tables, when there are any, are studied by tense below.
struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.study) private var study
    @Query(sort: \Card.order) private var cards: [Card]
    @Query(sort: \Chunk.order) private var chunks: [Chunk]

    @Binding var session: StudySession?
    @State private var editing: EditTarget?
    #if DEBUG
    @State private var debugChunk: Chunk?
    @State private var debugGroup = false
    #endif

    var body: some View {
        let words = cards.filter { !$0.isConj && !$0.isDropped }
        let loose = Chunks.loose(cards, chunks: chunks)
        let top = Chunks.top(chunks)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Wordmark(flag: 30)
                    Spacer()
                    Text(words.count == 1 ? "1 palabra" : "\(words.count) palabras")
                        .font(Typo.text(15, .heavy)).foregroundStyle(Palette.muted)
                }
                .padding(.top, 8)

                if words.isEmpty {
                    Text("Tu diccionario empieza vacío. Añade palabras una a una con +, o márcalas mientras lees en Lecturas. Después las juntas en temas.")
                        .font(Typo.text(17)).foregroundStyle(Palette.muted).padding(.top, 32)
                }
                if !loose.isEmpty {
                    NavigationLink { GroupView() } label: { looseRow(loose) }
                        .buttonStyle(PressStyle())
                        .padding(.top, 22)
                }
                if !top.isEmpty {
                    ChunkGrid(shown: top, chunks: chunks, cards: cards).padding(.top, 14)
                    Text(top.count > 1 ? "Toca un tema para estudiarlo. Arrastra uno sobre otro para juntarlos." : "Toca el tema para estudiarlo.")
                        .font(Typo.text(13, .bold)).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }
                conjugation
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { bar }
        // Cards deleted (Explorar, or Ajustes › Borrar todos los datos) may be in a session left midway: start over.
        .onChange(of: cards.count) { old, new in if new < old { session = nil } }
        // New cards get their example sentences in the background.
        .task(id: cards.count) { await Examples.fill(ctx) }
        .background(Backdrop())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { t in
            NavigationStack { EditCardView(card: t.card) }
        }
        #if DEBUG
        // Development: `-open sueltas` opens Agrupar, `-open <theme name>` that theme, for screenshots.
        .navigationDestination(item: $debugChunk) { ChunkView(chunk: $0) }
        .navigationDestination(isPresented: $debugGroup) { GroupView() }
        .task {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-open"), i + 1 < args.count else { return }
            try? await Task.sleep(for: .milliseconds(300))
            if args[i + 1] == "sueltas" { debugGroup = true } else { debugChunk = chunks.first { $0.name == args[i + 1] } }
        }
        #endif
    }

    private func looseRow(_ loose: [Card]) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(loose.count == 1 ? "1 suelta" : "\(loose.count) sueltas").font(Typo.text(17, .heavy)).foregroundStyle(Palette.ink)
                Text(loose.prefix(4).map(\.es).joined(separator: ", ") + (loose.count > 4 ? "…" : ""))
                    .font(Typo.text(14, .bold)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer()
            Text("Agrupar ›").font(Typo.text(15, .heavy)).foregroundStyle(Palette.accentInk)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.muted.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .contentShape(.rect)
    }

    // MARK: conjugation

    /// Each tense the verbs have, and all of them together: tap one to study its tables.
    @ViewBuilder
    private var conjugation: some View {
        let conj = cards.filter { $0.isConj && !$0.isDropped }
        if !conj.isEmpty {
            var have: [String: Int] = [:]
            let _ = conj.forEach { have[$0.tense, default: 0] += 1 }
            let tenses = Tense.all.filter { have[$0.key] != nil }
            Text("CONJUGACIÓN").font(Typo.text(13, .heavy)).tracking(1).foregroundStyle(Palette.muted)
                .padding(.top, 28).padding(.bottom, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if tenses.count > 1 { tenseChip(Tense.random, name: "Todos", count: conj.count, fill: Palette.sunk) }
                    ForEach(tenses) { t in tenseChip(t.key, name: t.name, count: have[t.key] ?? 0, fill: Palette.moodSoft(t.mood)) }
                }
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
        }
    }

    private func tenseChip(_ key: String, name: String, count: Int, fill: Color) -> some View {
        Button { studyTense(key, name: name) } label: {
            HStack(spacing: 6) {
                Text(name).font(Typo.text(15, .heavy)).foregroundStyle(Palette.ink)
                Text("\(count)").font(Typo.text(14, .bold)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(fill, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.edge, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(name), \(count) \(count == 1 ? "tabla" : "tablas")")
    }

    private func studyTense(_ key: String, name: String) {
        let pool = cards.filter { Scheduler.inTab($0, tab: .conj, tense: key) }
        let verbs = cards.filter { !$0.isConj && $0.isVerb }
        study(pool, tab: .conj, label: name, key: "conj:" + key,
              fresh: Scheduler.unseen(pool, staggerTenses: key == Tense.random, verbs: verbs))
    }

    // MARK: the bar

    private var bar: some View {
        HStack {
            NavigationLink { BrowseView() } label: { barItem("Palabras", icon: "list.bullet") }
            NavigationLink { LecturasView() } label: { barItem("Lecturas", icon: "book.fill") }
            Button { editing = EditTarget(card: nil) } label: {
                Image(systemName: "plus").font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background { Gloss(color: Palette.accent, shape: RoundedRectangle(cornerRadius: 18), lift: 0.6) }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Añadir una palabra")
            NavigationLink { SettingsView() } label: { barItem("Ajustes", icon: "gearshape.fill") }
        }
        .buttonStyle(PressStyle())
        .padding(8)
        .panel(radius: 28, shadow: 6)
        .padding(.horizontal, 16).padding(.bottom, 4)
        .frame(maxWidth: 560)
    }

    private func barItem(_ title: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 19, weight: .bold)).frame(height: 24)
            Text(title).font(Typo.text(12, .heavy))
        }
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(.rect)
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

