import SwiftUI
import SwiftData

/// After a session, before ¡Listo!: each card swiped left, with a box for a memory trick.
/// A card that already has one shows it, ready to edit. Turned off in Ajustes › Pedir mnemotecnias.
struct MnemonicsView: View {
    @Environment(\.modelContext) private var ctx
    let cards: [Card]
    /// The verb a conj card drills, for its meaning.
    let verb: (Card) -> Card?
    let onDone: () -> Void

    @State private var texts: [String: String] = [:]
    @FocusState private var focus: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("¿Una mnemotecnia?").font(Typo.display(30)).foregroundStyle(Palette.ink)
                        .padding(.top, 24)
                    Text(cards.count == 1 ? "Fallaste esta tarjeta. Un truco para recordarla la próxima vez:"
                                          : "Fallaste estas \(cards.count) tarjetas. Un truco para recordar cada una la próxima vez:")
                        .font(Typo.text(16)).foregroundStyle(Palette.muted)
                        .padding(.bottom, 6)
                    ForEach(cards, id: \.persistentModelID) { row($0) }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: 10) {
                Button("Guardar", action: save)
                    .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white))
                Button("Ahora no", action: onDone)
                    .font(Typo.text(15, .heavy)).tint(Palette.muted)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Backdrop())
        .onAppear { for c in cards { texts[c.id] = c.mnemonic } }
    }

    private func row(_ c: Card) -> some View {
        let tense = c.isConj ? Tense.named(c.tense) : nil
        let meaning = c.isConj ? verb(c)?.en ?? "" : c.en
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(c.es).font(Typo.display(c.isPhrase ? 20 : 24)).foregroundStyle(Palette.ink)
                if let tense {
                    Text(tense.name).font(Typo.text(13, .heavy)).foregroundStyle(Palette.mood(tense.mood))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Palette.moodSoft(tense.mood), in: .capsule)
                }
            }
            if !meaning.isEmpty { Text(meaning).font(Typo.text(17, .heavy)).foregroundStyle(Palette.en) }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.stage(2)).padding(.top, 13)
                TextField("", text: Binding(get: { texts[c.id] ?? "" }, set: { texts[c.id] = $0 }),
                          prompt: Text("¿Quieres añadir una mnemotecnia?"), axis: .vertical)
                    .font(Typo.text(16, .bold))
                    .focused($focus, equals: c.id)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Palette.sunk, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(focus == c.id ? Palette.sea.opacity(0.6) : Palette.edge, lineWidth: 1.5))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(radius: 20)
    }

    private func save() {
        for c in cards where c.modelContext != nil {
            let t = (texts[c.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if t != c.mnemonic { c.mnemonic = t }
        }
        try? ctx.save()
        onDone()
    }
}
