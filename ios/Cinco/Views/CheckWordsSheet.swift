import SwiftUI
import SwiftData

/// Palabras › Elegir › Revisar: Claude Sonnet checks the meanings of the words the learner picked. It's asked once, when
/// this opens; each answer that says a meaning is wrong is only offered, and it's the learner who changes the card.
struct CheckWordsSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let cards: [Card]

    @State private var results: [Tutor.CheckResult]?
    @State private var problem: String?
    /// What the learner did with each "fix", by card id: true for the new meaning, false for keeping the card's.
    @State private var decided: [String: Bool] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Revisar con Claude").font(Typo.display(24)).foregroundStyle(Palette.ink)
                if let results {
                    summary(results)
                    VStack(spacing: 0) {
                        ForEach(Array(zip(cards, results).enumerated()), id: \.offset) { i, pair in
                            if i > 0 { Divider().overlay(Palette.line) }
                            row(pair.0, pair.1)
                        }
                    }
                    .panel()
                    Button("Listo") { dismiss() }
                        .buttonStyle(SoftButtonStyle(fill: Palette.paper, text: Palette.ink, size: 17))
                } else if let problem {
                    Text(problem).font(Typo.text(15, .bold)).foregroundStyle(Palette.again)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Cerrar") { dismiss() }
                        .buttonStyle(SoftButtonStyle(fill: Palette.paper, text: Palette.ink, size: 17))
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(cards.count == 1 ? "Revisando 1 palabra…" : "Revisando \(cards.count) palabras…")
                            .font(Typo.text(15, .bold)).foregroundStyle(Palette.muted)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 20)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await check() }
    }

    private func summary(_ results: [Tutor.CheckResult]) -> some View {
        let fixes = results.count { $0.verdict == .fix }
        let text = fixes == 0 ? "Todos los significados están bien."
            : fixes == 1 ? "1 significado puede estar mal. Decide tú si lo cambias."
            : "\(fixes) significados pueden estar mal. Decide tú si los cambias."
        return Text(text).font(Typo.text(16, .bold)).foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ c: Card, _ r: Tutor.CheckResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                icon(r.verdict)
                Text(c.es).font(Typo.text(17, .heavy)).foregroundStyle(Palette.ink)
                Text(c.en).font(Typo.text(15)).foregroundStyle(Palette.en)
            }
            switch r.verdict {
            case .right:
                if !r.note.isEmpty { note(r.note) }
            case .none:
                note("Claude no dijo nada de esta.")
            case .fix:
                Text("Claude: \(r.english)").font(Typo.text(16, .bold)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !r.note.isEmpty { note(r.note) }
                switch decided[c.id] {
                case true?: note("Cambiada.")
                case false?: note("Se queda como estaba.")
                case nil:
                    VStack(spacing: 8) {
                        Button { use(r, on: c) } label: {
                            Text("Usar «\(r.english)»").multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 15))
                        Button { keep(c) } label: { Text("Dejarla así").frame(maxWidth: .infinity) }
                            .buttonStyle(SoftButtonStyle(fill: Palette.paper, text: Palette.ink, size: 15))
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func icon(_ v: Tutor.CheckResult.Verdict) -> some View {
        let (name, color): (String, Color) = switch v {
        case .right: ("checkmark.circle.fill", Palette.good)
        case .fix: ("exclamationmark.triangle.fill", Palette.again)
        case .none: ("questionmark.circle.fill", Palette.muted)
        }
        return Image(systemName: name).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Typo.text(14)).foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: asking, and acting on the answers

    private func check() async {
        guard results == nil, problem == nil else { return }
        let items = cards.map { Tutor.CheckInput(spanish: $0.es, english: $0.en, sentence: $0.ex) }
        do throws(Tutor.Failure) {
            let answers = try await Tutor.check(items)
            // A meaning Claude has confirmed isn't doubted again by Ajustes › Revisar mi biblioteca.
            for (c, r) in zip(cards, answers) where r.verdict == .right { MeaningReview.settle(c) }
            results = answers
        } catch {
            problem = error.message
        }
    }

    /// The note is written for the new meaning, so it replaces the card's, which may be about the wrong sense.
    private func use(_ r: Tutor.CheckResult, on c: Card) {
        c.en = r.english
        if !r.note.isEmpty { c.notes = r.note }
        try? ctx.save()
        MeaningReview.settle(c)
        decided[c.id] = true
    }

    private func keep(_ c: Card) {
        MeaningReview.settle(c)
        decided[c.id] = false
    }
}
