import SwiftUI

/// Home's running total of what Claude has cost: today and since counting began. Tapping it opens the detail.
struct CostLine: View {
    @AppStorage(CostLog.key) private var data = Data()

    var body: some View {
        let days = CostLog.decode(data)
        NavigationLink { CostView() } label: {
            HStack(spacing: 6) {
                Text("Coste de la API").font(Typo.text(14, .heavy)).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text("hoy \(CostLog.format(CostLog.total(days, on: DayLog.key()).dollars))")
                    .font(Typo.text(14, .bold)).foregroundStyle(Palette.ink)
                Text("·").foregroundStyle(Palette.muted)
                Text("total \(CostLog.format(CostLog.total(days).dollars))")
                    .font(Typo.text(14)).foregroundStyle(Palette.muted)
                Text("›").font(Typo.text(18, .heavy)).foregroundStyle(Palette.accent)
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Coste de la API: hoy \(CostLog.format(CostLog.total(days, on: DayLog.key()).dollars)), en total \(CostLog.format(CostLog.total(days).dollars))")
    }
}

/// What each kind of call to Claude has cost, today and in all.
struct CostView: View {
    @AppStorage(CostLog.key) private var data = Data()

    var body: some View {
        let days = CostLog.decode(data)
        let today = DayLog.key()
        List {
            Section {
                summary("Hoy", CostLog.total(days, on: today))
                ForEach(CostLog.byRoute(days, on: today), id: \.route) { row($0.route, $0.entry) }
            } header: { Text("Hoy") }
            Section {
                summary("En total", CostLog.total(days))
                ForEach(CostLog.byRoute(days), id: \.route) { row($0.route, $0.entry) }
            } header: { Text("Desde \(since(days))") }
            Section {
                Text("Lo que cuesta cada llamada, según el proxy: Claude Haiku cuesta $0.10 por millón de tokens leídos y $0.50 por millón escritos; Claude Sonnet, 20 veces más ($2 y $10). Lo que Claude piensa cuenta como escrito. Solo cuentan las llamadas de este iPhone desde que se instaló esta versión; la factura completa, con las de otros, está en la consola de Anthropic.")
                    .font(Typo.text(14)).foregroundStyle(Palette.muted)
            }
        }
        .navigationTitle("Coste de la API")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func since(_ days: CostLog.Days) -> String {
        guard let first = CostLog.since(days), let d = dayDate(first) else { return "que se empezó a contar" }
        return "el " + d.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es")))
    }

    private func dayDate(_ key: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar.current
        return f.date(from: key)
    }

    private func summary(_ label: String, _ e: CostEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CostLog.format(e.dollars)).font(Typo.display(28)).foregroundStyle(Palette.ink)
                Text("\(e.calls == 1 ? "1 llamada" : "\(e.calls) llamadas") · \(tokens(e.input)) leídos · \(tokens(e.output)) escritos")
                    .font(Typo.text(13)).foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(CostLog.format(e.dollars)), \(e.calls) llamadas")
    }

    private func row(_ route: String, _ e: CostEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CostLog.name(route)).font(Typo.text(15, .bold)).foregroundStyle(Palette.ink)
                Text(e.calls == 1 ? "1 llamada" : "\(e.calls) llamadas").font(Typo.text(13)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Text(CostLog.format(e.dollars)).font(Typo.text(15, .bold)).foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    /// 12.3k, 1.2M.
    private func tokens(_ n: Int) -> String {
        switch n {
        case ..<1000: "\(n)"
        case ..<1_000_000: String(format: "%.1fk", Double(n) / 1000)
        default: String(format: "%.1fM", Double(n) / 1_000_000)
        }
    }
}
