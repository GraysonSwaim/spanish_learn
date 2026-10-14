import SwiftUI

/// The third-party work Cinco ships with, and the license text it asks to be shown with.
struct AcknowledgementsView: View {
    private static let nunito = URL(string: "https://fonts.google.com/specimen/Nunito")!
    private static let readability = URL(string: "https://github.com/mozilla/readability")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Credit(name: "Nunito", blurb: "La tipografía, de Vernon Adams, Cyreal y Jacques Le Bailly.",
                       license: "SIL Open Font License 1.1", link: Self.nunito)
                NavigationLink("Licencia de Nunito (SIL OFL 1.1)") { LicenseTextView(title: "Nunito", resource: "OFL") }
                    .font(Typo.text(16, .heavy)).tint(Palette.accentInk)
                Credit(name: "Readability.js", blurb: "De Mozilla, el modo lectura de Firefox: saca el texto de un artículo para una lectura nueva.",
                       license: "Apache License 2.0", link: Self.readability)
                NavigationLink("Licencia de Readability.js (Apache 2.0)") {
                    LicenseTextView(title: "Readability.js", resource: "Readability-LICENSE")
                }
                .font(Typo.text(16, .heavy)).tint(Palette.accentInk)
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

/// One piece of third-party work: its name, what it does here, and its license.
private struct Credit: View {
    let name: String
    let blurb: String
    let license: String
    let link: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(Typo.text(16, .heavy))
            Text(blurb).foregroundStyle(Palette.muted)
            HStack(spacing: 8) {
                Text(license).font(Typo.text(12, .heavy)).foregroundStyle(Palette.accentInk)
                Link(link.host() ?? "", destination: link).font(Typo.text(14))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.sunk, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line, lineWidth: 1))
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
