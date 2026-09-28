import SwiftUI

/// Where the dictionary, sentences and fonts come from, with the attribution their licenses ask for.
struct AcknowledgementsView: View {
    private struct Source {
        let name: String
        let use: String
        let license: String
        let url: String
    }

    private let sources = [
        Source(name: "Wiktionary",
               use: "Significados, origen de las palabras y tablas de conjugación, extraídos con Wiktextract (kaikki.org). Cinco los ha resumido y combinado con las demás fuentes.",
               license: "CC BY-SA 4.0",
               url: "https://es.wiktionary.org"),
        Source(name: "Tatoeba",
               use: "Frases de ejemplo y sus traducciones.",
               license: "CC BY 2.0 FR",
               url: "https://tatoeba.org"),
        Source(name: "Base de datos de verbos de Fred Jehle",
               use: "Conjugaciones, para comprobar las demás fuentes.",
               license: "CC BY-NC-SA 3.0",
               url: "https://github.com/ghidinelli/fred-jehle-spanish-verbs"),
        Source(name: "verbecc",
               use: "Conjugaciones, para comprobar las demás fuentes.",
               license: "LGPL 3.0",
               url: "https://github.com/bretttolbert/verbecc"),
        Source(name: "FrequencyWords, de Hermit Dave",
               use: "Frecuencia de las palabras, a partir de subtítulos de OpenSubtitles.",
               license: "CC BY-SA 4.0",
               url: "https://github.com/hermitdave/FrequencyWords"),
        Source(name: "Nunito",
               use: "La tipografía, de Vernon Adams, Cyreal y Jacques Le Bailly.",
               license: "SIL Open Font License 1.1",
               url: "https://fonts.google.com/specimen/Nunito"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Cinco se apoya en el trabajo abierto de mucha gente. Gracias.")
                ForEach(sources, id: \.name) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.name).font(Typo.text(16, .heavy))
                        Text(s.use).foregroundStyle(Palette.muted)
                        HStack(spacing: 8) {
                            Text(s.license).font(Typo.text(12, .heavy)).foregroundStyle(Palette.accentInk)
                            if let url = URL(string: s.url) {
                                Link(url.host() ?? s.url, destination: url).font(Typo.text(14))
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.sunk, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line, lineWidth: 1))
                }
                Text("El diccionario de Cinco es una obra derivada de Wiktionary y se comparte con la misma licencia, CC BY-SA 4.0.")
                    .font(Typo.text(13)).foregroundStyle(Palette.muted)
            }
            .font(Typo.text(16))
            .foregroundStyle(Palette.ink)
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .navigationTitle("Créditos")
    }
}
