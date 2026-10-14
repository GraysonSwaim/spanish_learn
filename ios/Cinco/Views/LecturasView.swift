import SwiftUI
import SwiftData

/// Saved readings, newest first, and a way to paste a new one.
struct LecturasView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Reading.opened, order: .reverse) private var readings: [Reading]
    @State private var adding = false
    @State private var open: Reading?

    var body: some View {
        List {
            Section {
                Button { adding = true } label: {
                    Label("Nueva lectura", systemImage: "doc.on.clipboard")
                        .font(Typo.text(17, .heavy)).foregroundStyle(Palette.accentInk)
                }
            } footer: {
                Text("Pega un texto en español, toca las palabras que no conoces y tradúcelo línea a línea. Al terminar, las palabras marcadas pasan a tus tarjetas.")
            }
            .listRowBackground(Palette.paper)

            Section {
                ForEach(readings) { r in
                    Button { open = r } label: { row(r) }
                        .swipeActions {
                            Button("Borrar", role: .destructive) {
                                ctx.delete(r)
                                try? ctx.save()
                            }
                        }
                }
            } footer: {
                if !readings.isEmpty {
                    Text("Una lectura que no abras en \(Lectura.keepDays) días se borra sola. Las tarjetas que hiciste con ella se quedan.")
                }
            }
            .listRowBackground(Palette.paper)
        }
        .font(Typo.text(16))
        .scrollContentBackground(.hidden)
        .background(Backdrop())
        .navigationTitle("Lecturas")
        .navigationDestination(item: $open) { ReadingView(reading: $0) }
        .sheet(isPresented: $adding) {
            NavigationStack { NewReadingView { open = $0 } }
        }
    }

    private func row(_ r: Reading) -> some View {
        let done = r.english.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let marked = Lectura.runs(lines: r.lines, marks: r.marks).count
        return VStack(alignment: .leading, spacing: 3) {
            Text(r.title).font(Typo.text(18, .heavy)).foregroundStyle(Palette.ink).lineLimit(1)
            Text("\(done) de \(r.lines.count) líneas · \(marked) \(marked == 1 ? "marcada" : "marcadas") · \(r.opened.formatted(.relative(presentation: .named)))")
                .font(Typo.text(14)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

/// Paste a text and give it a name.
struct NewReadingView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let onCreate: (Reading) -> Void

    @State private var title = ""
    @State private var text = ""

    var body: some View {
        Form {
            Section {
                TextField("Título (opcional)", text: $title)
            }
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 240)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Pega aquí el texto en español…").foregroundStyle(Palette.muted)
                                .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
                // The system's own paste button, so iOS doesn't ask permission each time.
                PasteButton(payloadType: String.self) { strings in
                    if let s = strings.first { text = s }
                }
                .tint(Palette.accentInk)
            } footer: {
                Text("Cada línea del texto, con todas sus frases, se traduce debajo de ella.")
            }
        }
        .font(Typo.text(16))
        .navigationTitle("Nueva lectura")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Empezar", action: create).disabled(Lectura.lines(text).isEmpty)
            }
        }
    }

    private func create() {
        let lines = Lectura.lines(text)
        guard !lines.isEmpty else { return }
        let name = title.trimmingCharacters(in: .whitespaces)
        let r = Reading(title: name.isEmpty ? Self.defaultTitle(lines[0]) : name, lines: lines)
        ctx.insert(r)
        try? ctx.save()
        dismiss()
        onCreate(r)
    }

    /// The first few words of the text.
    static func defaultTitle(_ first: String) -> String {
        let words = first.split(separator: " ")
        return words.prefix(5).joined(separator: " ") + (words.count > 5 ? "…" : "")
    }
}
