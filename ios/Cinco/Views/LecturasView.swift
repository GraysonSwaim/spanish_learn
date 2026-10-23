import SwiftUI
import SwiftData

/// Saved readings, newest first, and a link to read a new one.
struct LecturasView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Reading.opened, order: .reverse) private var readings: [Reading]
    @State private var open: Reading?

    var body: some View {
        List {
            Section {
                NewReadingCard { open = $0 }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Se abre la página tal cual. Toca las palabras que no conoces, o selecciona una frase; al terminar, lo que marques pasa a tus tarjetas.")
            }

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

/// A link to an article, and nothing else: it opens straight on the article's own page. Its text is read meanwhile
/// (`ReadingView.readArticle`).
struct NewReadingCard: View {
    @Environment(\.modelContext) private var ctx
    let onCreate: (Reading) -> Void

    @State private var link = ""
    @FocusState private var focused: Bool

    private var url: URL? { ArticleText.link(in: link) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background { Gloss(color: Palette.sea, shape: RoundedRectangle(cornerRadius: 15), lift: 0.6) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nueva lectura").font(Typo.display(22)).foregroundStyle(Palette.ink)
                    Text("Lee un artículo en español donde se publicó.")
                        .font(Typo.text(15)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "link").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(focused ? Palette.accentInk : Palette.muted)
                    TextField("Pega un enlace…", text: $link)
                        .accessibilityLabel("Enlace a un artículo")
                        .font(Typo.text(17, .bold)).foregroundStyle(Palette.ink)
                        .keyboardType(.URL).textContentType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.go).onSubmit(start)
                        .focused($focused)
                    if !link.isEmpty {
                        Button { link = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Borrar el enlace")
                    }
                }
                .padding(.horizontal, 14).frame(height: 50)
                .background(Palette.sunk, in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(focused ? Palette.accent.opacity(0.6) : Palette.line, lineWidth: focused ? 2 : 1)
                }
                .contentShape(.rect)
                .onTapGesture { focused = true }

                if link.isEmpty {
                    // The system's own paste button, so iOS doesn't ask permission each time. A link opens as it
                    // lands (`onChange`).
                    PasteButton(payloadType: String.self) { strings in
                        if let s = strings.first { link = s }
                    }
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(Palette.accent)
                    .labelStyle(.titleAndIcon)
                } else {
                    Button(action: start) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 19, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background { Gloss(color: Palette.accent, shape: Circle(), lift: url == nil ? 0.3 : 0.8) }
                    }
                    .buttonStyle(.plain)
                    .disabled(url == nil)
                    .opacity(url == nil ? 0.4 : 1)
                    .accessibilityLabel("Abrir")
                    .transition(.scale.combined(with: .opacity))
                }
            }

            if !link.isEmpty, url == nil, !focused {
                Text("Eso no parece un enlace.").font(Typo.text(14, .bold)).foregroundStyle(Palette.again)
            }
        }
        .padding(18)
        .panel()
        .animation(.snappy(duration: 0.2), value: link.isEmpty)
        .animation(.snappy(duration: 0.2), value: focused)
        // A whole link arriving at once was pasted: open it.
        .onChange(of: link) { old, new in
            if old.isEmpty, new.count > 8, ArticleText.link(in: new) != nil { start() }
        }
    }

    /// A reading of the link's page, opened on it. Its lines come as the article's text is read, and as paragraphs
    /// are marked on the page.
    private func start() {
        guard let url else { return }
        let r = Reading(title: ArticleText.site(url), lines: [])
        r.url = url.absoluteString
        ctx.insert(r)
        try? ctx.save()
        link = ""
        focused = false
        onCreate(r)
    }
}
