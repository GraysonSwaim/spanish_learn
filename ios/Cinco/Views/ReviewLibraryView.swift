import SwiftUI
import SwiftData
import Translation

/// Ajustes › Revisar mi biblioteca: `MeaningCheck` over every word, on the phone. It only lists what's in doubt; each one
/// opens in `CheckMeaningSheet`, where it's the learner who decides.
struct ReviewLibraryView: View {
    @Query(sort: \Card.order) private var cards: [Card]

    @State private var entries = MeaningReview.entries
    @State private var config: TranslationSession.Configuration?
    @State private var queue: [Card] = []
    /// The cards whose translations are being fetched.
    @State private var batch: [Card] = []
    @State private var done = 0
    @State private var total = 0
    @State private var running = false
    @State private var problem: String?
    @State private var looking: Card?

    /// A batch's work is saved when it's done, so leaving loses at most this many.
    private static let batchSize = 25

    private var pending: Int { MeaningReview.toCheck(cards, entries: entries).count }
    private var doubts: [Card] { MeaningReview.doubtful(cards, entries: entries) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Compara el significado de cada palabra con Apple Traducir y Apple Intelligence, para encontrar los que estén mal. Todo se hace en el iPhone. Apple también se equivoca, sobre todo con palabras raras, así que aquí nada cambia sin que lo decidas tú.")
                    .font(Typo.text(15)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                status
                if !doubts.isEmpty { doubtList }
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .navigationTitle("Revisar mi biblioteca")
        .navigationBarTitleDisplayMode(.inline)
        .translationTask(config) { @Sendable session in
            while let texts = await nextBatch() {
                await take(try? await MeaningCheck.translate(texts, with: session))
            }
        }
        .sheet(item: $looking, onDismiss: { entries = MeaningReview.entries }) { c in
            CheckMeaningSheet(card: c).checkSheetStyle()
        }
        // A long review shouldn't stop because the screen went dark.
        .onChange(of: running) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        .onDisappear {
            running = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
        #if DEBUG
        .task {
            // The simulator has neither Apple Translate nor the on-device model.
            guard CommandLine.arguments.contains("-openReview") else { return }
            for c in MeaningReview.toCheck(cards, entries: entries).prefix(3) {
                entries[c.id] = MeaningReview.Entry(en: c.en, doubtful: true)
            }
        }
        #endif
    }

    @ViewBuilder
    private var status: some View {
        if running {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(done), total: Double(max(total, 1))).tint(Palette.accent)
                Text("Revisando \(done) de \(total)…").font(Typo.text(15, .bold)).foregroundStyle(Palette.ink)
                Text("Si sales, sigue donde lo dejó.").font(Typo.text(13)).foregroundStyle(Palette.muted)
            }
        } else {
            if let problem {
                Text(problem).font(Typo.text(14, .bold)).foregroundStyle(Palette.again)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if pending > 0 {
                Button(action: start) {
                    Text(pending == 1 ? "Revisar 1 palabra" : "Revisar \(pending) palabras").frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 18))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.good)
                    Text(doubts.isEmpty ? "Toda tu biblioteca está revisada, y nada parece estar mal." : "Toda tu biblioteca está revisada.")
                        .font(Typo.text(16, .bold)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var doubtList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(doubts.count == 1 ? "1 para mirar" : "\(doubts.count) para mirar").font(Typo.display(20)).foregroundStyle(Palette.ink)
            VStack(spacing: 0) {
                ForEach(doubts) { c in
                    if c.id != doubts.first?.id { Divider().overlay(Palette.line) }
                    Button { looking = c } label: {
                        MenuRowLabel(title: c.es, sub: c.en)
                    }
                    .buttonStyle(.plain)
                }
            }
            .panel()
        }
    }

    // MARK: going through the library

    private func start() {
        problem = nil
        queue = MeaningReview.toCheck(cards, entries: entries)
        total = queue.count
        done = 0
        running = true
        // Each new configuration, or invalidated one, runs `translationTask` again.
        if config == nil {
            config = TranslationSession.Configuration(source: Locale.Language(identifier: "es"), target: Locale.Language(identifier: "en"))
        } else {
            config?.invalidate()
        }
    }

    /// The next cards' texts, or nil when the review is over.
    private func nextBatch() -> [String]? {
        guard running, !queue.isEmpty else {
            running = false
            return nil
        }
        batch = Array(queue.prefix(Self.batchSize))
        queue.removeFirst(batch.count)
        return batch.flatMap(MeaningReview.texts)
    }

    /// Apple Translate's answers for the batch. Without any, this phone has no opinion yet, which is no doubt about the
    /// words: the review stops and they stay to be checked.
    private func take(_ english: [String: String]?) async {
        guard let english, !english.isEmpty else {
            if running { problem = "Apple Traducir no pudo responder. Prueba otra vez; puede que primero tenga que descargar el español." }
            queue = []
            running = false
            return
        }
        var found = entries
        for c in batch where c.modelContext != nil {
            let verdict = await MeaningReview.verdict(for: c, english: english)
            if verdict != .noOpinion { found[c.id] = MeaningReview.Entry(en: c.en, doubtful: verdict == .doubtful) }
            done += 1
        }
        entries = found
        MeaningReview.entries = found
    }
}
