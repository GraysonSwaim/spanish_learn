import SwiftUI
import SwiftData

/// Starts (or picks up) a session over some cards. RootView owns the session; Home and the theme screens call this.
struct StudyAction {
    var run: (_ pool: [Card], _ tab: Tab, _ label: String, _ key: String, _ fresh: [Card]) -> Void = { _, _, _, _, _ in }

    func callAsFunction(_ pool: [Card], tab: Tab = .vocab, label: String, key: String, fresh: [Card]? = nil) {
        run(pool, tab, label, key, fresh ?? Scheduler.unseen(pool, staggerTenses: false, verbs: []))
    }
}

extension EnvironmentValues {
    @Entry var study = StudyAction()
}

/// A theme as one line: its colour, its name and what's in it, and what's due on the right.
struct ChunkRow: View {
    let chunk: Chunk
    let words: [Card]
    let inside: Int
    var targeted = false

    var body: some View {
        let live = words.filter { !$0.isDropped }
        let due = live.filter { $0.stage == 5 && Scheduler.isDue($0) }.count
        let color = Palette.chunk(chunk.color)
        HStack(spacing: 14) {
            // The theme's own mosaic, from its name.
            Mosaic(word: chunk.name).frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(chunk.name).font(Typo.text(18, .heavy)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Text(subtitle(live.count)).font(Typo.text(13, .bold)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            if due > 0 {
                Text("\(due) por repasar").font(Typo.text(12, .heavy)).foregroundStyle(Palette.accentInk)
            }
            // Only a theme holding smaller ones opens; the rest start studying.
            if inside > 0 {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 6)
        .background(targeted ? color.fill : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .animation(.snappy(duration: 0.2), value: targeted)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ n: Int) -> String {
        let w = n == 1 ? "1 palabra" : "\(n) palabras"
        return inside == 0 ? w : "\(inside) \(inside == 1 ? "tema" : "temas") · \(w)"
    }
}

/// Themes as a list. Tap one to study it (or, when it holds smaller themes, to open it); drag one onto another
/// to put them together; press and hold for the rest.
struct ChunkList: View {
    let shown: [Chunk]
    let chunks: [Chunk]
    let cards: [Card]

    @Environment(\.modelContext) private var ctx
    @Environment(\.study) private var study
    @State private var open: Chunk?
    @State private var target: String?
    @State private var merging: MergePair?
    @State private var renaming: Chunk?
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            ForEach(shown) { c in
                row(c)
                if c !== shown.last { Divider().overlay(Palette.line) }
            }
        }
        .navigationDestination(item: $open) { ChunkView(chunk: $0) }
        .sheet(item: $merging) { m in
            MergeSheet(pair: m).presentationDetents([.medium]).presentationBackground(Palette.bg).presentationCornerRadius(28)
        }
        .alert("Nombre del tema", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $newName)
            Button("Guardar") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if let c = renaming, !n.isEmpty { c.name = n; try? ctx.save() }
                renaming = nil
            }
            Button("Cancelar", role: .cancel) { renaming = nil }
        }
    }

    private func row(_ c: Chunk) -> some View {
        let words = Chunks.words(in: c.id, cards: cards, chunks: chunks)
        let inside = Chunks.children(of: c.id, in: chunks).count
        let parent = chunks.first { $0.id == c.parentID }
        return Button { tap(c, words: words, inside: inside) } label: {
            ChunkRow(chunk: c, words: words, inside: inside, targeted: target == c.id)
        }
        .buttonStyle(PressStyle())
        .draggable(c.id) {
            ChunkRow(chunk: c, words: words, inside: inside).frame(width: 300).padding(.horizontal, 8)
                .background(Palette.paper, in: .rect(cornerRadius: 6))
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, let a = chunks.first(where: { $0.id == id }), a !== c else { return false }
            merging = MergePair(a: a, b: c)
            return true
        } isTargeted: { on in
            if on { target = c.id } else if target == c.id { target = nil }
        }
        .contextMenu {
            Button("Ver qué hay dentro", systemImage: "square.stack") { open = c }
            Button("Cambiar el nombre", systemImage: "pencil") { newName = c.name; renaming = c }
            if let parent {
                Button("Sacar de «\(parent.name)»", systemImage: "arrow.up.left") { Chunks.lift(c, ctx: ctx) }
            }
            Button(inside > 0 ? "Separar sus temas" : "Devolver sus palabras a Sueltas", systemImage: "square.split.2x2") {
                Chunks.dissolve(c, ctx: ctx)
            }
        }
        .accessibilityHint(inside > 0 || words.isEmpty ? "Toca para abrirlo" : "Toca para estudiarlo")
    }

    private func tap(_ c: Chunk, words: [Card], inside: Int) {
        if inside > 0 || words.allSatisfy(\.isDropped) { open = c } else { study(words, label: c.name, key: c.id) }
    }
}

struct MergePair: Identifiable {
    let a: Chunk, b: Chunk
    var id: String { a.id + b.id }
}

/// One theme dropped on another: make a bigger theme holding both, or put the first inside the second.
private struct MergeSheet: View {
    let pair: MergePair
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Juntar «\(pair.a.name)» y «\(pair.b.name)»").font(Typo.display(22)).foregroundStyle(Palette.ink)
            Text("Los dos siguen dentro como temas pequeños: puedes estudiar uno solo o todo junto.")
                .font(Typo.text(15)).foregroundStyle(Palette.muted).padding(.top, 6)
            TextField("Nombre del tema grande", text: $name)
                .font(Typo.text(18, .heavy))
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(merge)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Palette.sunk, in: .rect(cornerRadius: 6))
                .padding(.top, 16)
            Button("Juntar", action: merge)
                .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, radius: 18, size: 18))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.top, 14)
            Button("O mete «\(pair.a.name)» dentro de «\(pair.b.name)»") {
                Chunks.nest(pair.a, in: pair.b, ctx: ctx)
                dismiss()
            }
            .font(Typo.text(16, .heavy)).tint(Palette.accentInk)
            .frame(maxWidth: .infinity).padding(.top, 14)
        }
        .padding(20)
        .onAppear { focused = true }
    }

    private func merge() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Chunks.merge(pair.a, pair.b, name: n, ctx: ctx)
        dismiss()
    }
}

/// Presses in a little.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}

/// Inside a theme: study all of it, the smaller themes in it, and the words filed straight in it.
struct ChunkView: View {
    let chunk: Chunk
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.study) private var study
    @Query(sort: \Card.order) private var cards: [Card]
    @Query(sort: \Chunk.order) private var chunks: [Chunk]
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let kids = Chunks.children(of: chunk.id, in: chunks)
        let words = Chunks.words(in: chunk.id, cards: cards, chunks: chunks).filter { !$0.isDropped }
        let own = words.filter { $0.chunkID == chunk.id }.sorted { $0.es.localizedCompare($1.es) == .orderedAscending }
        let parent = chunks.first { $0.id == chunk.parentID }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(chunk.name).font(Typo.display(32)).foregroundStyle(Palette.ink)
                Text(kids.isEmpty ? count(words.count) : "\(kids.count) \(kids.count == 1 ? "tema" : "temas") · \(count(words.count))")
                    .font(Typo.text(15, .bold)).foregroundStyle(Palette.muted)

                if !words.isEmpty {
                    studyAll(words, mixed: !kids.isEmpty).padding(.top, 18)
                }
                if !kids.isEmpty {
                    kicker("Dentro")
                    ChunkList(shown: kids, chunks: chunks, cards: cards)
                }
                if !own.isEmpty {
                    kicker(kids.isEmpty ? "Palabras" : "Sueltas en «\(chunk.name)»")
                    VStack(spacing: 0) {
                        ForEach(own) { c in
                            NavigationLink { CardDetailView(card: c) } label: { row(c) }
                                .buttonStyle(.plain)
                                .contextMenu { moveMenu(c) }
                            if c !== own.last { Divider().overlay(Palette.line) }
                        }
                    }
                    .panel()
                }
                if words.isEmpty && kids.isEmpty {
                    Text("No le queda ninguna palabra. Añádele algunas desde Sueltas.")
                        .font(Typo.text(16)).foregroundStyle(Palette.muted).padding(.top, 18)
                }
            }
            .padding(16)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Cambiar el nombre", systemImage: "pencil") { newName = chunk.name; renaming = true }
                    if let parent {
                        Button("Sacar de «\(parent.name)»", systemImage: "arrow.up.left") { Chunks.lift(chunk, ctx: ctx) }
                    }
                    Button(kids.isEmpty ? "Devolver sus palabras a Sueltas" : "Separar sus temas", systemImage: "square.split.2x2") {
                        dismiss()
                        Chunks.dissolve(chunk, ctx: ctx)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Más")
            }
        }
        .alert("Nombre del tema", isPresented: $renaming) {
            TextField("Nombre", text: $newName)
            Button("Guardar") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { chunk.name = n; try? ctx.save() }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func count(_ n: Int) -> String { n == 1 ? "1 palabra" : "\(n) palabras" }

    private func kicker(_ s: String) -> some View {
        Text(s.uppercased()).font(Typo.text(13, .heavy)).tracking(1).foregroundStyle(Palette.muted)
            .padding(.top, 24).padding(.bottom, 10)
    }

    private func studyAll(_ words: [Card], mixed: Bool) -> some View {
        let color = Palette.chunk(chunk.color)
        return Button { study(words, label: chunk.name, key: chunk.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(mixed ? "Todo junto" : "Estudiar «\(chunk.name)»").font(Typo.display(19))
                Text(mixed ? "Las \(words.count) mezcladas: así se conectan entre sí." : "Toca para empezar.")
                    .font(Typo.text(14, .bold)).opacity(0.9)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background { Gloss(color: color.mark, shape: RoundedRectangle(cornerRadius: 6), lift: 0.6) }
        }
        .buttonStyle(PressStyle())
    }

    private func row(_ c: Card) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.es).font(Typo.text(17, .heavy)).foregroundStyle(Palette.ink)
                Text(c.en).font(Typo.text(14)).foregroundStyle(Palette.en)
            }
            Spacer()
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(i <= c.stage ? Palette.stage(i) : Palette.line).frame(width: 6, height: 14)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(.rect)
    }

    @ViewBuilder
    private func moveMenu(_ c: Card) -> some View {
        Menu("Mover a…", systemImage: "folder") {
            ForEach(chunks.filter { $0 !== chunk }) { k in
                Button(Chunks.path(k, in: chunks)) { Chunks.file([c], in: k, ctx: ctx) }
            }
        }
        Button("Devolver a Sueltas", systemImage: "tray") { Chunks.file([c], in: nil, ctx: ctx) }
    }
}
