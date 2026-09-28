import SwiftUI

/// Ajustes › Atajos y Siri: what each Shortcuts action takes, and the one-word → full-card shortcut
/// (Translate, then ChatGPT, then Añadir tarjetas) with its prompt ready to copy.
struct ShortcutsGuideView: View {
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Escribe una palabra en español o en inglés y el atajo la traduce, deja que ChatGPT rellene todo lo demás y la añade a tus tarjetas. Si es un sustantivo trae el artículo, el género y el plural; si es un verbo, sus quince tiempos en Conjugación.")

                heading("Crear el atajo «Añadir a Cinco»")
                step(1, "Atajos › + › **Ask for Input** (Solicitar entrada): tipo Texto, pregunta «¿Qué palabra?».")
                step(2, "**Translate Text** (Traducir texto): de *Detectar idioma* a **Español**. Toca el resultado y renómbralo «Español».")
                step(3, "Otro **Translate Text** con la misma entrada: de *Detectar idioma* a **Inglés**. Renómbralo «Inglés».")
                step(4, "**Use Model** (Usar modelo): elige **ChatGPT**. Pega el prompt de abajo y cambia cada [ENTRADA], [ESPAÑOL] e [INGLÉS] por la variable del paso 1, 2 y 3.")
                step(5, "**Añadir tarjetas** (de Cinco): en Texto pon la *Respuesta* del paso 4.")
                Text("Ponle nombre y ya puedes decir «Oye Siri, Añadir a Cinco» o lanzarlo desde la hoja de compartir. La tarjeta aparece en Vocabulario (o en Frases), y los tiempos de un verbo en Conjugación.")
                    .foregroundStyle(Palette.muted)
                Text("Si la palabra ya está en tus tarjetas (con o sin artículo), no se duplica: Cinco te dice qué traería de nuevo (un ejemplo, una mnemotecnia, tiempos que faltan, otro significado) y solo lo cambia si dices que sí. Si no hay nada nuevo, te lo dice y no toca nada.")
                    .foregroundStyle(Palette.muted)
                Text("Si el paso 2 o 3 falla porque la palabra ya está en ese idioma, bórralo: ChatGPT traduce también. Si un verbo está en el diccionario de Cinco, sus tablas salen del diccionario, que están revisadas, en lugar de las de ChatGPT.")
                    .foregroundStyle(Palette.muted)

                promptBox

                heading("Lo que puede llevar una tarjeta")
                Text("Solo el español y el inglés son obligatorios; todo lo demás es opcional y se aprovecha si llega. Añadir tarjetas acepta JSON (lo que pide el prompt) o CSV.")
                field("spanish", "Obligatorio", "La palabra, con artículo si es sustantivo: *la maleta*.")
                field("english", "Obligatorio", "El significado corto: *suitcase*; verbos con *to*.")
                field("example", "Opcional", "Una frase de ejemplo en español.")
                field("notes", "Opcional", "Género y plural, femenino de un adjetivo, irregularidades de un verbo.")
                field("mnemonic", "Opcional", "Un truco para recordarla. No sustituye uno que ya hayas escrito.")
                field("tags", "Opcional", "Temas: *viaje*, *comida*.")
                field("type", "Opcional", "*phrase* manda la tarjeta a Frases.")
                field("frases", "Opcional", "Más frases con un verbo, en una lista.")
                field("tenses", "Solo verbos", "Cada tiempo con sus seis formas (yo, tú, él, nosotros, vosotros, ellos). Cada tiempo es una tarjeta en Conjugación.")

                heading("Las acciones de Cinco")
                action("Añadir tarjetas", "Texto (obligatorio): JSON o CSV, una tarjeta o muchas. Etiquetas (opcional): para las que no traigan. Una palabra nueva entra directa; si ya la tienes, te pregunta antes de cambiarla y nunca pierde su progreso.")
                action("Añadir palabra", "Palabra (obligatoria), Idioma (opcional: Detectar, Español, Inglés). La rellena con el diccionario de Cinco, sin internet ni IA. Siri: «Añadir una palabra a Cinco».")
                action("Añadir una tarjeta", "Español e Inglés (obligatorios), Ejemplo y Frase (opcionales). Tal cual, sin rellenar nada.")
                action("Palabras del mazo", "Sin entradas. Devuelve el español de todas tus tarjetas, para pedirle a un modelo palabras que aún no tengas.")
                action("Tarjetas pendientes", "Sin entradas. Cuántos repasos te esperan. Siri: «¿Cuántas tarjetas tengo en Cinco?».")
            }
            .font(Typo.text(16))
            .foregroundStyle(Palette.ink)
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .navigationTitle("Atajos y Siri")
    }

    private var promptBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("El prompt para ChatGPT").font(Typo.text(15, .heavy))
                Spacer()
                Button {
                    UIPasteboard.general.string = Self.prompt
                    copied = true
                } label: {
                    Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(Typo.text(14, .heavy))
                }
                .buttonStyle(.borderedProminent).tint(Palette.sea)
            }
            Text(Self.prompt)
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
                .lineLimit(8)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(Palette.sunk, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line, lineWidth: 1))
    }

    private func heading(_ s: String) -> some View {
        Text(s).font(Typo.display(21)).padding(.top, 10)
    }

    private func step(_ n: Int, _ s: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(Typo.display(16)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(Palette.stage(n), in: .rect(cornerRadius: 8))
            Text(s)
        }
    }

    private func field(_ key: String, _ need: String, _ s: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(key).font(.system(size: 15, weight: .semibold, design: .monospaced))
                Text(need).font(Typo.text(12, .heavy))
                    .foregroundStyle(need == "Obligatorio" ? Palette.accentInk : Palette.muted)
            }
            Text(s).foregroundStyle(Palette.muted)
        }
    }

    private func action(_ name: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(Typo.text(16, .heavy))
            Text(s).foregroundStyle(Palette.muted)
        }
    }

    /// Asks for one JSON card: noun fields for a noun, all fifteen tables for a verb, in the forms
    /// Cinco's own tables use (six slots, "" for imperative yo, "no …" in the negative imperative).
    static let prompt = """
    Make a Spanish flashcard (Latin American Spanish) for a learner.
    They typed: [ENTRADA]
    Apple Translate suggests Spanish "[ESPAÑOL]" and English "[INGLÉS]". These can be wrong or just repeat the input; fix them.

    Reply with only one JSON object: no other text, no code fences. Keys:
    "spanish": the Spanish. A noun with its article (el/la; el/la for both genders), an adjective in the masculine singular, a verb in the infinitive.
    "english": a short meaning; a verb starts with "to". Two meanings: "suitcase / bag".
    "type": "phrase" if it is several words or an expression, otherwise "word".
    "example": one short, natural Spanish sentence using it.
    "notes": a noun: its gender and plural, like "Femenino. Plural: las maletas". An adjective: its feminine, like "Femenino: bonita". A verb: its irregularity, like "o → ue" or "yo: tengo"; "" if regular. Otherwise "".
    "mnemonic": a short, vivid memory trick in English linking the Spanish sound to the meaning.
    "tags": one or two lowercase English topic words, like "travel".
    "tenses": only for a verb; leave it out for anything else. An object with these 15 keys, each a list of exactly 6 forms without pronouns, in the order yo, tú, él/ella/usted, nosotros, vosotros, ellos/ellas/ustedes:
    presente, preterito, imperfecto, futuro, condicional, subjuntivo, subj_imperfecto, imperativo, imperativo_negativo, perfecto, pluscuamperfecto, futuro_perfecto, condicional_perfecto, subj_perfecto, subj_pluscuamperfecto.
    imperativo and imperativo_negativo have "" for yo; imperativo_negativo forms start with "no" ("no hables"). subj_imperfecto gives both endings ("hablara / hablase"). Compound tenses use haber ("he hablado"). A reflexive verb keeps its pronoun ("me levanto").
    """
}
