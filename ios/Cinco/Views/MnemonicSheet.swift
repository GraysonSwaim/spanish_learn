import SwiftUI
import SwiftData

/// Comes up the moment a card is missed: a box for a memory trick, filled in if the card already has one.
/// Turned off with the switch at its foot, or in Ajustes › Pedir mnemotecnias.
struct MnemonicSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let card: Card
    let meaning: String

    @AppStorage(PrefKey.askMnemonics) private var askMnemonics = true
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let tense = card.isConj ? Tense.named(card.tense) : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(card.mnemonic.isEmpty ? "¿Quieres añadir una mnemotecnia?" : "¿Mejoras tu mnemotecnia?")
                    .font(Typo.display(24)).foregroundStyle(Palette.ink)
                    .padding(.top, 26)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.es).font(Typo.display(card.isPhrase ? 20 : 24)).foregroundStyle(Palette.ink)
                    if let tense {
                        Text(tense.name).font(Typo.text(13, .heavy)).foregroundStyle(Palette.mood(tense.mood))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Palette.moodSoft(tense.mood), in: .capsule)
                    }
                    Spacer(minLength: 0)
                    if !meaning.isEmpty { Text(meaning).font(Typo.text(17, .heavy)).foregroundStyle(Palette.en) }
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.stage(2)).padding(.top, 13)
                    TextField("", text: $text, prompt: Text("Un truco para recordarla"), axis: .vertical)
                        .font(Typo.text(16, .bold))
                        .focused($focused)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Palette.sunk, in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(focused ? Palette.sea.opacity(0.6) : Palette.edge, lineWidth: 1.5))
                }
                HStack(spacing: 10) {
                    Button("Ahora no") { dismiss() }
                        .buttonStyle(SoftButtonStyle(fill: Palette.paper, text: Palette.ink, size: 17))
                    Button("Guardar", action: save)
                        .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 17))
                }
                .padding(.top, 8)
                Toggle(isOn: $askMnemonics) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preguntar cada vez que fallo").font(Typo.text(15, .bold)).foregroundStyle(Palette.ink)
                        Text(askMnemonics ? "También en Ajustes" : "Ya no saldrá. Actívalo aquí o en Ajustes.")
                            .font(Typo.text(13)).foregroundStyle(Palette.muted)
                    }
                }
                .tint(Palette.good)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Palette.sunk, in: .rect(cornerRadius: 16))
                .padding(.top, 10)
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .onAppear {
            text = card.mnemonic
            focused = true
        }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if card.modelContext != nil && t != card.mnemonic {
            card.mnemonic = t
            try? ctx.save()
        }
        dismiss()
    }
}
