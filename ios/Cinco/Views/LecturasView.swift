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
        let marked = Lectura.runs(lines: r.lines, marks: r.marks).count
        return VStack(alignment: .leading, spacing: 3) {
            Text(r.title).font(Typo.text(18, .heavy)).foregroundStyle(Palette.ink).lineLimit(1)
            Text("\(marked) \(marked == 1 ? "marcada" : "marcadas") · \(r.opened.formatted(.relative(presentation: .named)))")
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
    @State private var link = ""
    @State private var fetching = false
    @State private var fetched: Result<Article, Error>?

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("https://…", text: $link)
                        .accessibilityLabel("Enlace a un artículo")
                        .keyboardType(.URL).textContentType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.go).onSubmit(fetch)
                    if fetching {
                        ProgressView()
                    } else {
                        Button("Traer", action: fetch)
                            .font(Typo.text(16, .heavy)).tint(Palette.accentInk)
                            .disabled(ArticleText.link(in: link) == nil)
                    }
                }
            } header: {
                Text("Desde un enlace")
            } footer: {
                Text(linkNote)
            }
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
                    guard let s = strings.first else { return }
                    // A pasted link brings its article.
                    if let url = ArticleText.link(in: s) {
                        link = url.absoluteString
                        fetch()
                    } else {
                        text = s
                    }
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
                Button("Empezar", action: create).disabled(Lectura.lines(text).isEmpty && ArticleText.link(in: link) == nil)
            }
        }
    }

    private var linkNote: String {
        switch fetched {
        case nil:
            return "Lo lees en la página del artículo, y aquí abajo trae su texto principal, sin menús ni anuncios."
        case .failure(let e):
            if (e as? ArticleReader.Failure) == .empty {
                return e.localizedDescription + " Puedes empezar igual y leerla en su página, o copiar el texto en Safari y pegarlo abajo."
            }
            return e.localizedDescription + " Ábrela en Safari, copia el texto y pégalo abajo."
        case .success(let a):
            let n = a.paragraphs
            return "De \(a.site): \(n) \(n == 1 ? "párrafo" : "párrafos"). Borra abajo lo que no quieras leer."
                + (a.isSpanish ? "" : " Ojo: no parece estar en español.")
        }
    }

    private func fetch() {
        guard !fetching, let url = ArticleText.link(in: link) else { return }
        fetching = true
        fetched = nil
        Task {
            defer { fetching = false }
            do {
                let a = try await ArticleReader.read(url)
                text = a.text
                title = a.title
                fetched = .success(a)
            } catch {
                fetched = .failure(error)
            }
        }
    }

    /// A reading of the text, and of the link's page when there is one: a page whose text couldn't be read can still be
    /// read as it is.
    private func create() {
        let lines = Lectura.lines(text)
        let url = ArticleText.link(in: link)
        guard !lines.isEmpty || url != nil else { return }
        let name = title.trimmingCharacters(in: .whitespaces)
        let r = Reading(title: name.isEmpty ? lines.first.map(Self.defaultTitle) ?? url?.host() ?? "Lectura" : name, lines: lines)
        r.url = url?.absoluteString ?? ""
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
