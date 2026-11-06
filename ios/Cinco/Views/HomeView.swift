import SwiftUI
import SwiftData

/// Home: the day's mosaic, the library of words, and one button to study it. Verbs' tables, when there are any, are
/// studied by tense below.
struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.study) private var study
    @Query(sort: \Card.order) private var cards: [Card]

    @Binding var session: StudySession?

    var body: some View {
        let words = cards.filter { !$0.isConj && !$0.isDropped }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The day's mosaic, with the name on a plaster plaque.
                ZStack(alignment: .bottomLeading) {
                    Mosaic(word: Mosaic.today).frame(height: 168).clipShape(.rect(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Choca Cinco").font(Typo.display(28)).foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(words.count == 1 ? "1 palabra" : "\(words.count) palabras")
                            .font(Typo.text(13)).foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Palette.bg, in: .rect(cornerRadius: 4))
                    .padding(14)
                }
                .padding(.top, 8)

                if words.isEmpty {
                    Text("Tu biblioteca empieza vacía. Toca + para escanear una página del libro que lees, y sus palabras entran aquí para que las estudies. También puedes añadirlas una a una.")
                        .font(Typo.text(17)).foregroundStyle(Palette.muted).padding(.top, 32)
                } else {
                    library.padding(.top, 18)
                }
                conjugation
                if !words.isEmpty { LibraryProgress(words: words) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        #if DEBUG
        // `-scrollBottom` opens at the end of the page, for screenshots of what's below the fold.
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-scrollBottom") ? .bottom : .top)
        #endif
        // Plaster under the clock and round the bar, so the page scrolls away behind them rather than through them.
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0).background(Palette.bg, ignoresSafeAreaEdges: .top) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bar.padding(.top, 8).frame(maxWidth: .infinity).background(Palette.bg, ignoresSafeAreaEdges: .bottom)
        }
        // Cards deleted (Explorar, or Ajustes › Borrar todos los datos) may be in a session left midway: start over.
        .onChange(of: cards.count) { old, new in if new < old { session = nil } }
        // New cards get their example sentences in the background.
        .task(id: cards.count) {
            await Library.fillLevels(ctx)
            await Examples.fill(ctx)
        }
        .background(Backdrop())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// What's waiting, and the one way into studying it.
    private var library: some View {
        let plan = Library.plan(cards)
        let pending = plan.queue.count + plan.fresh.count
        let reviews = plan.queue.count { $0.stage == 5 }
        return VStack(alignment: .leading, spacing: 14) {
            if reviews > 0 {
                Text((reviews == 1 ? "1 para repasar" : "\(reviews) para repasar")
                     + (plan.held > 0 ? ". Las \(plan.held) nuevas esperan a que repases." : ""))
                    .font(Typo.text(15, .bold)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if pending > 0 {
                Button { study(plan.pool, queue: plan.queue, label: "Biblioteca", fresh: plan.fresh) } label: {
                    Text("Estudiar · \(pending)").frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 18))
            } else {
                Text("Nada por estudiar ahora. Escanea otra página.").font(Typo.text(15, .bold)).foregroundStyle(Palette.muted)
            }
        }
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
            .background(fill, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.edge, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(name), \(count) \(count == 1 ? "tabla" : "tablas")")
    }

    private func studyTense(_ key: String, name: String) {
        let pool = cards.filter { Scheduler.inTab($0, tab: .conj, tense: key) }
        let verbs = cards.filter { !$0.isConj && $0.isVerb }
        study(pool, queue: Scheduler.dailyQueue(pool), tab: .conj, label: name, key: "conj:" + key,
              fresh: Scheduler.unseen(pool, staggerTenses: key == Tense.random, verbs: verbs))
    }

    // MARK: the bar

    private var bar: some View {
        HStack {
            NavigationLink { BrowseView() } label: { barItem("Palabras", icon: "list.bullet") }
            NavigationLink { LecturasView() } label: {
                Image(systemName: "plus").font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background { Gloss(color: Palette.accent, shape: RoundedRectangle(cornerRadius: 6), lift: 0.6) }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Añadir: una lectura o una palabra")
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
    let card: Card
    var id: String { card.id }
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

