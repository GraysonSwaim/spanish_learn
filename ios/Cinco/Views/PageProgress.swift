import SwiftUI

/// Home's proof from the book: how much of each new page was already known, tested, before it was studied.
struct PageProgress: View {
    @AppStorage(PageScores.key) private var data = Data()

    var body: some View {
        let scores = PageScores.decode(data)
        if let last = scores.last {
            VStack(alignment: .leading, spacing: 14) {
                Rectangle().fill(Palette.line).frame(height: 1)
                Text("TUS PÁGINAS").font(Typo.text(13, .heavy)).tracking(1).foregroundStyle(Palette.muted)
                    .accessibilityAddTraits(.isHeader)
                headline(last)
                if let t = PageScores.trend(scores) {
                    note(scores.count < 6
                         ? "Primera página \(pct(t.first)) → última \(pct(t.last))"
                         : "Primeras páginas \(pct(t.first)) → últimas \(pct(t.last))")
                }
                if last.claimed > 0 {
                    note("Otro \(pct(last.claimedShare)) eran palabras marcadas «Ya la sé», aún sin comprobar.")
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(scores.suffix(5).reversed(), id: \.id) { row($0) }
                }
            }
            .padding(.top, 28)
        }
    }

    private func headline(_ s: PageScore) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(pct(s.share)).font(Typo.display(34)).foregroundStyle(Palette.ink)
                Text("ya lo sabías").font(Typo.text(16, .bold)).foregroundStyle(Palette.ink)
            }
            Text("del texto de \(s.title), antes de estudiar sus palabras. Solo cuentan las palabras comprobadas.")
                .font(Typo.text(14)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ s: PageScore) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(s.title).font(Typo.text(15)).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer()
            Text(s.newWords == 1 ? "1 nueva" : "\(s.newWords) nuevas").font(Typo.text(13)).foregroundStyle(Palette.muted)
            Text(pct(s.share)).font(Typo.text(15, .bold)).foregroundStyle(Palette.ink)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Typo.text(14)).foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
}
