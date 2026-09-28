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
        Source(name: "verbecc",
               use: "Conjugaciones, para comprobar las de Wiktionary.",
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

    /// The same file the app ships, outside the App Store's DRM, as CC BY-SA asks.
    private static let dictionaryURL = URL(string: "https://github.com/GraysonSwaim/spanish_learn/blob/main/ios/Cinco/Resources/dictionary.sqlite")!

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
                NavigationLink("Licencia de Nunito (SIL OFL 1.1)") { LicenseTextView(title: "Nunito", resource: "OFL") }
                    .font(Typo.text(16, .heavy)).tint(Palette.accentInk)
                VStack(alignment: .leading, spacing: 6) {
                    Text("El diccionario de Cinco es una obra derivada de Wiktionary y se comparte con la misma licencia, CC BY-SA 4.0. Puedes descargarlo libremente, sin restricciones:")
                    Link("dictionary.sqlite en GitHub", destination: Self.dictionaryURL).font(Typo.text(14))
                }
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

/// A license bundled as a text file, shown in full.
struct LicenseTextView: View {
    let title: String
    let resource: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .navigationTitle(title)
    }

    private var text: String {
        Bundle.main.url(forResource: resource, withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }
}
