import SwiftUI
import SwiftData
import Translation

/// "¿Está bien?": for when a card's meaning looks wrong. Apple Translate and, if they disagree, Apple Intelligence give a
/// second opinion on the phone, Claude can be asked again, and one tap puts any of their answers on the card.
/// Apple is wrong more often than Claude on rare words, so nothing here changes a card by itself (`MeaningCheck`).
struct CheckMeaningSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let card: Card

    @State private var checking = true
    @State private var verdict = MeaningCheck.Verdict.noOpinion
    /// Apple Translate, each as Spanish and English.
    @State private var translated: [Translated] = []
    /// The on-device model's meaning, when it was asked.
    @State private var modelMeaning: String?
    @State private var claudeAnswer: Tutor.Gloss?
    @State private var askingClaude = false
    @State private var claudeProblem: String?

    private struct Translated: Hashable {
        let spanish: String
        let english: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("¿Está bien?").font(Typo.display(24)).foregroundStyle(Palette.ink)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(card.es).font(Typo.text(20, .heavy)).foregroundStyle(Palette.ink)
                        Text(card.en).font(Typo.text(18, .heavy)).foregroundStyle(Palette.en)
                    }
                }
                if checking {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Comparando…").font(Typo.text(15, .bold)).foregroundStyle(Palette.muted)
                    }
                } else {
                    verdictLine
                    opinions
                    choices
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 20)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .translationTask(source: Locale.Language(identifier: "es"), target: Locale.Language(identifier: "en")) { @Sendable [texts = MeaningReview.texts(of: card)] session in
            await check(english: try? await MeaningCheck.translate(texts, with: session))
        }
        #if DEBUG
        .task {
            // The simulator has neither Apple Translate nor the on-device model.
            guard CommandLine.arguments.contains("-checkDemo") else { return }
            translated = [Translated(spanish: card.es, english: "to smell"),
                          Translated(spanish: card.ex, english: "The kitchen smelled of freshly made coffee.")]
            modelMeaning = "to smell"
            verdict = .doubtful
            checking = false
        }
        #endif
    }

    // MARK: what's shown

    private var verdictLine: some View {
        let (icon, color, text): (String, Color, String) = switch verdict {
        case .agrees: ("checkmark.circle.fill", Palette.good, "Apple Traducir dice lo mismo.")
        case .modelAccepts: ("checkmark.circle", Palette.good, "Apple Traducir dice otra cosa, pero Apple Intelligence la da por buena.")
        case .doubtful: ("exclamationmark.triangle.fill", Palette.again, "No coinciden. Puede estar mal, aunque con palabras raras a veces se equivoca Apple.")
        case .noOpinion: ("questionmark.circle.fill", Palette.muted, "Este iPhone no pudo comprobarla.")
        }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(color)
            Text(text).font(Typo.text(16, .bold)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var opinions: some View {
        if !translated.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Apple Traducir").font(Typo.text(13, .heavy)).foregroundStyle(Palette.muted)
                ForEach(translated, id: \.self) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.spanish).font(Typo.sentence(16)).foregroundStyle(Palette.ink)
                        Text(t.english).font(Typo.text(15)).foregroundStyle(Palette.en)
                    }
                }
            }
        }
        if let modelMeaning {
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Intelligence, en esta frase").font(Typo.text(13, .heavy)).foregroundStyle(Palette.muted)
                Text(modelMeaning).font(Typo.text(15)).foregroundStyle(Palette.en)
            }
        }
    }

    private var choices: some View {
        VStack(spacing: 10) {
            ForEach(candidates, id: \.english) { c in
                useButton(c.english, from: c.source, note: c.note)
            }
            if let claudeProblem {
                Text(claudeProblem).font(Typo.text(14, .bold)).foregroundStyle(Palette.again)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if claudeAnswer == nil, Tutor.base != nil, Tutor.consented {
                Button(action: askClaude) {
                    HStack(spacing: 10) {
                        if askingClaude { ProgressView() }
                        Text(askingClaude ? "Preguntando…" : "Preguntar a Claude otra vez").frame(maxWidth: askingClaude ? nil : .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle(fill: Palette.paper, text: Palette.ink, size: 17))
                .disabled(askingClaude)
            }
            Button("Dejarla así") {
                MeaningReview.settle(card)
                dismiss()
            }
                .buttonStyle(SoftButtonStyle(fill: Palette.paper, text: Palette.ink, size: 17))
        }
    }

    /// What could go on the card, best first: each different answer once, and none that's what it already says.
    private var candidates: [(english: String, source: String, note: String?)] {
        let word = translated.first.map { MeaningCheck.candidate($0.english, of: card.es) } ?? ""
        let all: [(english: String, source: String, note: String?)] = [
            (claudeAnswer?.english ?? "", "Claude", claudeAnswer?.note),
            (word, "Apple Traducir", nil),
            (modelMeaning ?? "", "Apple Intelligence", nil),
        ]
        var seen = Set<String>()
        return all.filter { !$0.english.isEmpty && !same($0.english) && seen.insert(TextMatch.strip($0.english)).inserted }
    }

    private func useButton(_ english: String, from source: String, note: String? = nil) -> some View {
        Button { use(english, note: note) } label: {
            VStack(spacing: 2) {
                Text("Usar «\(english)»").multilineTextAlignment(.center)
                Text(source).font(Typo.text(13, .bold)).opacity(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 17))
    }

    private func same(_ english: String) -> Bool { TextMatch.strip(english) == TextMatch.strip(card.en) }

    // MARK: asking

    /// Apple Translate has answered, or couldn't. The on-device model is only asked what that leaves open.
    private func check(english: [String: String]?) async {
        guard checking else { return }
        let answers = english ?? [:]
        translated = MeaningReview.texts(of: card).compactMap { t in answers[t].map { Translated(spanish: t, english: $0) } }
        verdict = await MeaningReview.verdict(for: card, english: answers)
        if verdict != .agrees { modelMeaning = (try? await Tutor.gloss([question], claude: false))?.first?.english }
        checking = false
    }

    private var question: Tutor.GlossInput {
        Tutor.GlossInput(text: card.exWord.isEmpty ? card.es : card.exWord, sentence: card.ex.isEmpty ? card.es : card.ex, word: card.es)
    }

    private func askClaude() {
        askingClaude = true
        claudeProblem = nil
        let asked = question
        Task {
            do throws(Tutor.Failure) {
                let g = try await Tutor.gloss([asked]).first
                if let g, !g.english.isEmpty, Library.cardWord(card.es, from: g) != nil {
                    claudeAnswer = g
                    if same(g.english) { claudeProblem = "Claude dice lo mismo que la tarjeta." }
                } else {
                    claudeProblem = Tutor.Failure.server.message
                }
            } catch {
                claudeProblem = error.message
            }
            askingClaude = false
        }
    }

    /// A note only comes with Claude's answer, written for this meaning: the card's old one may be about the wrong word.
    private func use(_ english: String, note: String?) {
        card.en = english
        if let note { card.notes = note }
        try? ctx.save()
        MeaningReview.settle(card)
        dismiss()
    }
}

extension View {
    func checkSheetStyle() -> some View {
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.bg)
            .presentationCornerRadius(28)
    }
}
