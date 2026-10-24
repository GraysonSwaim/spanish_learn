import SwiftUI
import SwiftData

/// Sueltas: words in no theme yet. Pick the ones that go together and make a theme of them, or add them to one.
struct GroupView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Card.order) private var cards: [Card]
    @Query(sort: \Chunk.order) private var chunks: [Chunk]
    @State private var picked = Set<String>()
    @State private var name = ""
    @FocusState private var naming: Bool

    var body: some View {
        let loose = Chunks.loose(cards, chunks: chunks)
        ScrollView {
            VStack(spacing: 0) {
                Text("Elige las que van juntas. Se recuerdan mejor las que pasan en el mismo sitio que las que son del mismo tipo.")
                    .font(Typo.text(15)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    .padding(.bottom, 16)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(loose) { c in word(c) }
                }
                if loose.isEmpty {
                    Text("No queda ninguna suelta.").font(Typo.text(17, .bold)).foregroundStyle(Palette.muted).padding(.top, 40)
                }
            }
            .padding(16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .navigationTitle(loose.count == 1 ? "1 suelta" : "\(loose.count) sueltas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let all = !loose.isEmpty && picked.count == loose.count
                Button(all ? "Ninguna" : "Todas") { picked = all ? [] : Set(loose.map(\.id)) }
                    .disabled(loose.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !picked.isEmpty { panel(loose.filter { picked.contains($0.id) }) }
        }
        .animation(.snappy(duration: 0.25), value: picked.isEmpty)
    }

    private func word(_ c: Card) -> some View {
        let on = picked.contains(c.id)
        let shape = RoundedRectangle(cornerRadius: 6)
        return Button {
            if on { picked.remove(c.id) } else { picked.insert(c.id) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Text(c.es).font(Typo.text(17, .heavy)).foregroundStyle(Palette.ink).lineLimit(2)
                    Spacer(minLength: 4)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(on ? Palette.accent : Palette.muted.opacity(0.5))
                }
                Text(c.en).font(Typo.text(14, .bold)).foregroundStyle(Palette.en).lineLimit(1)
                Text(c.sourceList.first.map { "Lectura: \($0.title)" } ?? "Añadida")
                    .font(Typo.text(12, .bold)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(12)
            .background(on ? Palette.paper : Palette.paper.opacity(0.7), in: shape)
            .overlay(shape.strokeBorder(on ? Palette.accent : Palette.edge, lineWidth: on ? 2 : 1))
            .softShadow(radius: on ? 8 : 5, y: 3)
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func panel(_ chosen: [Card]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(chosen.count == 1 ? "1 ELEGIDA" : "\(chosen.count) ELEGIDAS")
                .font(Typo.text(13, .heavy)).tracking(1).foregroundStyle(Palette.muted)
            HStack(spacing: 8) {
                TextField("Nombre del tema nuevo", text: $name)
                    .font(Typo.text(17, .heavy))
                    .focused($naming)
                    .submitLabel(.done)
                    .onSubmit { create(chosen) }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Palette.sunk, in: .rect(cornerRadius: 6))
                Button("Crear") { create(chosen) }
                    .font(Typo.text(16, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(minHeight: 48)
                    .background { Gloss(color: Palette.accent, shape: RoundedRectangle(cornerRadius: 6), lift: 0.5) }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .padding(.top, 8)
            if !chunks.isEmpty {
                Text("O añádelas a").font(Typo.text(13, .bold)).foregroundStyle(Palette.muted).padding(.top, 14)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chunks) { k in
                            Button(Chunks.path(k, in: chunks)) { file(chosen, in: k) }
                                .font(Typo.text(15, .heavy)).foregroundStyle(Palette.ink)
                                .padding(.horizontal, 12).frame(minHeight: 40)
                                .background(Palette.chunk(k.color).fill, in: .rect(cornerRadius: 6))
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Palette.paper, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .softShadow(radius: 14, y: -4)
        .transition(.move(edge: .bottom))
    }

    private func create(_ chosen: [Card]) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        file(chosen, in: Chunks.create(n, ctx: ctx))
    }

    private func file(_ chosen: [Card], in k: Chunk) {
        Chunks.file(chosen, in: k, ctx: ctx)
        picked = []
        name = ""
        naming = false
        if Chunks.loose(cards, chunks: chunks).isEmpty { dismiss() }
    }
}
