import SwiftUI
import SwiftData

/// Adds a card by hand or edits one. A verb's tables are edited here too, six forms per tense.
struct EditCardView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let card: Card?

    @State private var rec = CardRecord()
    /// Tense key -> six forms, while editing.
    @State private var forms: [String: [String]] = [:]
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("el coche", text: $rec.es, prompt: Text("el coche")).labeled("Español")
                TextField("car", text: $rec.en).labeled("Inglés")
                TextField("Mi coche es rojo.", text: $rec.ex, axis: .vertical).labeled("Ejemplo")
                TextField("En España, coche; en México, carro", text: $rec.notes, axis: .vertical).labeled("Notas")
                TextField("transporte", text: $rec.tags).labeled("Etiquetas")
                    .textInputAutocapitalization(.never)
            }
            Section {
                TextField("Ayer tuve que trabajar.", text: $rec.frases, axis: .vertical)
            } header: {
                Text("Más frases")
            } footer: {
                Text("Solo para verbos, una por línea y en cualquier tiempo.")
            }
            Section {
                ForEach(Tense.all) { t in
                    DisclosureGroup {
                        ForEach(0..<6, id: \.self) { p in
                            TextField(Person.label(p, t.key).isEmpty ? "yo (no tiene)" : Person.label(p, t.key), text: formBinding(t.key, p))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } label: {
                        Text(t.name + ((forms[t.key] ?? []).contains { !$0.isEmpty } ? " ✓" : ""))
                    }
                }
            } header: {
                Text("Conjugación")
            } footer: {
                Text("Solo para verbos. Cada tiempo que rellenes es una tarjeta en la pestaña Conjugación.")
            }
        }
        .font(Typo.text(16))
        .navigationTitle(card == nil ? "Nueva tarjeta" : "Editar tarjeta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Guardar", action: save) }
        }
        .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onAppear(perform: load)
    }

    private func formBinding(_ tense: String, _ p: Int) -> Binding<String> {
        Binding(
            get: { (forms[tense] ?? [])[safe: p] ?? "" },
            set: { v in
                var f = forms[tense] ?? Array(repeating: "", count: 6)
                while f.count < 6 { f.append("") }
                f[p] = v
                forms[tense] = f
            })
    }

    private func load() {
        guard let c = card else { return }
        rec = CardRecord(es: c.es, en: c.en, ex: c.ex, notes: c.notes, tags: c.tags,
                         frases: c.frases.split(separator: "|").joined(separator: "\n"), tenses: c.tenses)
        forms = c.tenses.mapValues { TextMatch.splitForms($0) }
    }

    private func save() {
        var r = rec
        r.es = r.es.trimmingCharacters(in: .whitespacesAndNewlines)
        r.en = r.en.trimmingCharacters(in: .whitespacesAndNewlines)
        r.tags = r.tags.lowercased().trimmingCharacters(in: .whitespaces)
        r.frases = r.frases.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "|")
        guard !r.es.isEmpty, !r.en.isEmpty else { error = "Hacen falta el español y el inglés."; return }
        r.tenses = forms.compactMapValues { f in
            let t = f.map { $0.trimmingCharacters(in: .whitespaces) }
            return t.contains { !$0.isEmpty } ? t.joined(separator: "|") : nil
        }
        if let msg = Deck.save(r, editing: card, ctx: ctx) { error = msg; return }
        dismiss()
    }
}

private extension View {
    func labeled(_ label: String) -> some View {
        LabeledContent { self } label: { Text(label).foregroundStyle(Palette.muted) }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
