import SwiftUI

/// The third-party work Cinco ships with, and the license text it asks to be shown with.
struct AcknowledgementsView: View {
    private static let nunito = URL(string: "https://fonts.google.com/specimen/Nunito")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nunito").font(Typo.text(16, .heavy))
                    Text("La tipografía, de Vernon Adams, Cyreal y Jacques Le Bailly.").foregroundStyle(Palette.muted)
                    HStack(spacing: 8) {
                        Text("SIL Open Font License 1.1").font(Typo.text(12, .heavy)).foregroundStyle(Palette.accentInk)
                        Link(Self.nunito.host() ?? "", destination: Self.nunito).font(Typo.text(14))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.sunk, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line, lineWidth: 1))
                NavigationLink("Licencia de Nunito (SIL OFL 1.1)") { LicenseTextView(title: "Nunito", resource: "OFL") }
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
