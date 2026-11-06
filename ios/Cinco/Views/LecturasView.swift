import SwiftUI
import SwiftData

/// What the + button opens: a new reading first, from a link or a scanned page, then one word typed in, and below them the
/// saved readings, newest first, so a long list never buries the rest.
struct LecturasView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Reading.opened, order: .reverse) private var readings: [Reading]
    @State private var open: Reading?
    /// The reading just made: its words go in and are studied before it's read.
    @State private var justMade: String?

    var body: some View {
        List {
            Section {
                NewReadingCard { r in
                    justMade = r.id
                    open = r
                }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if ScanCard.available {
                Section {
                    ScanCard { r in
                        justMade = r.id
                        open = r
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                AddWordCard()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
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
            } header: {
                if !readings.isEmpty { Text("Tus lecturas") }
            } footer: {
                if !readings.isEmpty {
                    Text("Una lectura que no abras en \(Lectura.keepDays) días se borra sola. Sus palabras se quedan en tu biblioteca, y las páginas de un libro también.")
                }
            }
            .listRowBackground(Palette.paper)
        }
        .font(Typo.text(16))
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Backdrop())
        .navigationTitle("Añadir")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $open) { ReadingView(reading: $0, isNew: $0.id == justMade) }
    }

    private func row(_ r: Reading) -> some View {
        let marked = Lectura.runs(lines: r.lines, marks: r.marks).count
        return VStack(alignment: .leading, spacing: 3) {
            Text(r.title).font(Typo.text(18, .heavy)).foregroundStyle(Palette.ink).lineLimit(1)
            Text("\(marked) \(marked == 1 ? "tocada" : "tocadas") · \(r.opened.formatted(.relative(presentation: .named)))")
                .font(Typo.text(14)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

/// One word and its meaning, and the rest of the card fills itself in (`Library.addWord`). It clears for the next word.
struct AddWordCard: View {
    @Environment(\.modelContext) private var ctx

    private enum Field { case spanish, english }

    @State private var spanish = ""
    @State private var english = ""
    @State private var working = false
    @State private var done: (text: String, isNew: Bool)?
    @State private var askConsent = false
    @FocusState private var focus: Field?

    private func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var ready: Bool { !clean(spanish).isEmpty && !clean(english).isEmpty && !working }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background { Gloss(color: Palette.blue, shape: RoundedRectangle(cornerRadius: 6), lift: 0.6) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Añadir una palabra").font(Typo.display(22)).foregroundStyle(Palette.ink)
                    Text("Escríbela con su significado. Lo demás se rellena solo.")
                        .font(Typo.text(15)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 4)

            box("Español", text: $spanish, field: .spanish, submit: .next) { focus = .english }
            box("Inglés", text: $english, field: .english, submit: .done, onSubmit: add)

            Button(action: add) {
                HStack(spacing: 10) {
                    if working { ProgressView().tint(.white) }
                    Text(working ? "Preparando la tarjeta…" : "Añadir").frame(maxWidth: working ? nil : .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 18))
            .disabled(!ready)
            .opacity(ready || working ? 1 : 0.5)

            if let done {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: done.isNew ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(done.isNew ? Palette.good : Palette.muted)
                    Text(done.text).font(Typo.text(15, .bold)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .panel()
        .alert(Tutor.consentTitle, isPresented: $askConsent) {
            Button("Enviar") {
                Tutor.consented = true
                save(claude: true)
            }
            Button("Solo guardarla") { save(claude: false) }
            Button("Cancelar", role: .cancel) {}
        } message: { Text(Tutor.addConsentMessage) }
    }

    private func box(_ label: String, text: Binding<String>, field: Field, submit: SubmitLabel, onSubmit: @escaping () -> Void) -> some View {
        TextField(label, text: text)
            .font(Typo.text(17, .bold)).foregroundStyle(Palette.ink)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .submitLabel(submit).onSubmit(onSubmit)
            .focused($focus, equals: field)
            .padding(.horizontal, 14).frame(height: 50)
            .background(Palette.sunk, in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(focus == field ? Palette.accent.opacity(0.6) : Palette.line, lineWidth: focus == field ? 2 : 1)
            }
    }

    private func add() {
        guard ready else { return }
        if Tutor.needsConsent { askConsent = true } else { save(claude: Tutor.base != nil) }
    }

    private func save(claude: Bool) {
        working = true
        done = nil
        Task {
            let added = await Library.addWord(es: clean(spanish), en: clean(english), claude: claude, ctx: ctx)
            working = false
            switch added {
            case .new(let c):
                done = ("Añadida: \(c.es) = \(c.en)", true)
                spanish = ""
                english = ""
                focus = .spanish
                await Library.fillLevels(ctx)
                await Examples.fill(ctx)
            case .already(let c):
                done = ("«\(c.es)» ya está en tu biblioteca: \(c.en)", false)
            case nil:
                done = ("No se pudo guardar. Prueba otra vez.", false)
            }
        }
    }
}

/// A link to an article, and nothing else. Like a scanned page, its words go into the library and are studied, and then
/// it's read on the article's own page (`ReadingView.begin`).
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
                    .background { Gloss(color: Palette.sea, shape: RoundedRectangle(cornerRadius: 6), lift: 0.6) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nueva lectura").font(Typo.display(22)).foregroundStyle(Palette.ink)
                    Text("Sus palabras entran en tu biblioteca: las estudias y luego lo lees donde se publicó.")
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
                .background(Palette.sunk, in: .rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
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

    /// A reading of the link's page. Its lines come as the article's text is read, and as paragraphs are marked on the page.
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
