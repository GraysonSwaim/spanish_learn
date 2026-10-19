import SwiftUI
import SwiftData

/// The words marked in a reading, as cards to look over before they go into the deck. Claude drafts each one (dictionary
/// form, the meaning in this sentence, a note); the sentence it came from is the card's example, and the new cards are
/// filed in the reading's own theme. A word already in the deck isn't added again: it gains this reading as a source,
/// and comes up for review.
struct ReadingCardsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Bindable var reading: Reading
    @Query private var cards: [Card]

    struct Draft: Identifiable {
        let run: Run
        var rec: CardRecord
        /// The card this word already is, when it is one.
        var existing: Card?
        var include = true
        var id: String { run.id }
    }

    @State private var drafts: [Draft] = []
    @State private var loading = false
    @State private var error: String?
    @State private var askConsent = false

    private var pending: [Run] {
        Lectura.runs(lines: reading.lines, marks: reading.marks).filter { !reading.carded.contains($0.id) }
    }
    private var newCount: Int { drafts.filter { $0.include && $0.existing == nil && ready($0.rec) }.count }
    private var forwardCount: Int { drafts.filter { $0.include && $0.existing != nil }.count }

    var body: some View {
        Form {
            if loading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Preparando las tarjetas…").foregroundStyle(Palette.muted)
                    }
                }
            } else if drafts.isEmpty {
                Section { Text("Todas las palabras marcadas ya están en tus tarjetas.").foregroundStyle(Palette.muted) }
            } else {
                if let error {
                    Section { Text(error).foregroundStyle(Palette.again) }
                }
                if Tutor.available, needsGloss {
                    Section {
                        Button(Tutor.base == nil ? "Rellenarlas en el iPhone" : "Pedir a Claude que las rellene", systemImage: "sparkles") { fetch() }
                    } footer: {
                        Text("O escribe tú el significado de cada una.")
                    }
                }
                ForEach($drafts) { $d in section($d) }
            }
        }
        .font(Typo.text(16))
        .navigationTitle("Tarjetas nuevas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save).disabled(loading || newCount + forwardCount == 0)
            }
        }
        .alert(Tutor.consentTitle, isPresented: $askConsent) {
            Button("Enviar") { Tutor.consented = true; fetch() }
            if Tutor.onDeviceAvailable { Button("Solo en el iPhone") { fetch(claude: false) } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text(Tutor.consentMessage) }
        .onAppear {
            build()
            if Tutor.available, !Tutor.needsConsent, needsGloss { fetch() }
        }
    }

    private var needsGloss: Bool {
        let g = reading.glosses
        return drafts.contains { $0.existing == nil && g[$0.id] == nil }
    }

    @ViewBuilder
    private func section(_ d: Binding<Draft>) -> some View {
        let draft = d.wrappedValue
        Section {
            Toggle(isOn: d.include) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.run.text).font(Typo.text(18, .heavy)).foregroundStyle(Palette.ink)
                    if let c = draft.existing {
                        Text("Ya está en el mazo: \(c.es) · \(c.stage > 0 ? "etapa \(c.stage)" : "nueva")")
                            .font(Typo.text(13)).foregroundStyle(Palette.muted)
                    }
                }
            }
            if let c = draft.existing {
                if d.wrappedValue.include {
                    Text((c.stage > 0 ? "Se repasa en la próxima sesión" : "Aún no la has estudiado") + ", y guarda esta lectura entre sus fuentes.")
                        .font(Typo.text(14)).foregroundStyle(Palette.muted)
                }
            } else if draft.include {
                TextField("Español", text: d.rec.es).labeledRow("Español")
                TextField("Significado", text: d.rec.en).labeledRow("Inglés")
                    .foregroundStyle(Palette.en)
                TextField("Nota", text: d.rec.notes, axis: .vertical).labeledRow("Nota")
            }
        } footer: {
            if draft.include, draft.existing == nil {
                Text(reading.lines[safe: draft.run.line] ?? "").font(Typo.italic(13))
            }
        }
    }

    private func ready(_ r: CardRecord) -> Bool {
        !r.es.trimmingCharacters(in: .whitespaces).isEmpty && !r.en.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// One draft per pending run, from Claude's gloss when there is one. Edits already made are kept.
    private func build() {
        let glosses = reading.glosses
        let old = Dictionary(drafts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        drafts = pending.map { run in
            let rec = Lectura.record(run, gloss: glosses[run.id], sentence: sentence(run))
            let surface = CardRecord(es: run.text)
            let existing = Deck.existing(rec, in: cards) ?? Deck.existing(surface, in: cards)
            if var d = old[run.id] {
                // A fresh gloss fills a draft the learner hasn't written a meaning for yet.
                if d.rec.en.isEmpty, glosses[run.id] != nil { d.rec = rec }
                d.existing = existing
                return d
            }
            return Draft(run: run, rec: rec, existing: existing)
        }
    }

    private func fetch() { fetch(claude: true) }

    private func fetch(claude: Bool) {
        if claude && Tutor.needsConsent { askConsent = true; return }
        let have = reading.glosses
        let want = drafts.filter { $0.existing == nil && have[$0.id] == nil }.map(\.run)
        guard !want.isEmpty else { return }
        let items = want.map { run in
            let english = reading.english[safe: run.line] ?? ""
            let fallback = reading.check?.lines[safe: run.line]?.better ?? ""
            return Tutor.GlossInput(text: run.text, sentence: reading.lines[safe: run.line] ?? "",
                                    english: english.trimmingCharacters(in: .whitespaces).isEmpty ? fallback : english)
        }
        loading = true
        error = nil
        Task {
            do throws(Tutor.Failure) {
                let got = try await Tutor.gloss(items, claude: claude)
                var g = reading.glosses
                for (run, gloss) in zip(want, got) { g[run.id] = gloss }
                reading.glosses = g
                try? ctx.save()
            } catch {
                self.error = error.message
            }
            build()
            loading = false
        }
    }

    private func sentence(_ run: Run) -> String {
        Lectura.sentence(of: run, in: reading.lines[safe: run.line] ?? "")
    }

    private func save() {
        let new = drafts.filter { $0.include && $0.existing == nil && ready($0.rec) }.map { d in
            var r = d.rec
            r.es = r.es.trimmingCharacters(in: .whitespacesAndNewlines)
            r.en = r.en.trimmingCharacters(in: .whitespacesAndNewlines)
            r.notes = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return (rec: r, sentence: sentence(d.run))
        }
        let existing = drafts.compactMap { d in d.include ? d.existing.map { (card: $0, sentence: sentence(d.run)) } : nil }
        Lectura.save(reading, new: new, existing: existing, ctx: ctx)
        let done = drafts.filter { $0.include && ($0.existing != nil || ready($0.rec)) }.map(\.id)
        reading.carded.append(contentsOf: done.filter { !reading.carded.contains($0) })
        try? ctx.save()
        dismiss()
    }
}

private extension View {
    func labeledRow(_ label: String) -> some View {
        LabeledContent { self } label: { Text(label).foregroundStyle(Palette.muted) }
    }
}
