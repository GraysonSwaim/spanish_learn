import SwiftUI

/// Home's proof from the pruebas: how much of what's been mastered is holding, by the random sample on each sheet, and
/// the last few sheets.
struct PruebaProgress: View {
    @AppStorage(PruebaLog.key) private var data = Data()

    var body: some View {
        let records = PruebaLog.decode(data)
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Rectangle().fill(Palette.line).frame(height: 1)
                Text("TUS PRUEBAS").font(Typo.text(13, .heavy)).tracking(1).foregroundStyle(Palette.muted)
                    .accessibilityAddTraits(.isHeader)
                if let held = PruebaLog.held(records) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(pct(held.share)).font(Typo.display(34)).foregroundStyle(Palette.ink)
                            Text("lo recuerdas").font(Typo.text(16, .bold)).foregroundStyle(Palette.ink)
                        }
                        Text("de tus palabras dominadas, según las preguntas al azar de tus pruebas de los últimos 30 días (\(held.asked)).")
                            .font(Typo.text(14)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(records.suffix(5).reversed().enumerated()), id: \.offset) { _, r in row(r) }
                }
            }
            .padding(.top, 28)
        }
    }

    private func row(_ r: PruebaRecord) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(r.date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "es"))))
                .font(Typo.text(15)).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer()
            if let c = r.cost, c > 0 {
                Text(CostLog.format(c)).font(Typo.text(13)).foregroundStyle(Palette.muted)
            }
            if r.learned > 0 {
                Text(r.learned == 1 ? "1 aprendida" : "\(r.learned) aprendidas").font(Typo.text(13)).foregroundStyle(Palette.good)
            }
            Text("\(r.right)/\(r.total)").font(Typo.text(15, .bold)).foregroundStyle(Palette.ink)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
}
