import SwiftUI
import SwiftData

/// Home's picture of the library: how much has been learned, how well it's staying, and what's coming up.
struct LibraryProgress: View {
    let words: [Card]
    @Query private var logs: [DayLog]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("TU BIBLIOTECA") { library }
            section("CÓMO VAS") { howWell }
            section("LO QUE VIENE") { coming }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(Palette.line).frame(height: 1)
            Text(title).font(Typo.text(13, .heavy)).tracking(1).foregroundStyle(Palette.muted)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.top, 28)
    }

    // MARK: how much

    private var library: some View {
        let standings = words.map(Stats.standing)
        let count = { (s: Stats.Standing) in standings.count { $0 == s } }
        let rungs = Stats.rungs(words).map { "\($0.name) \($0.count)" }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 14) {
            headline("\(count(.longTerm))", "a largo plazo", sub: "de \(words.count == 1 ? "1 palabra" : "\(words.count) palabras")")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Stats.levels(words), id: \.name) { levelRow($0) }
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                ForEach(Stats.Standing.allCases, id: \.self) { s in
                    Swatch(color: color(s), label: s.name, count: count(s))
                }
            }
            if !rungs.isEmpty {
                note("En repaso: \(rungs)")
            }
        }
    }

    private func levelRow(_ l: Stats.Level) -> some View {
        let order = Stats.Standing.allCases
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l.name).font(Typo.text(15, .bold)).foregroundStyle(Palette.ink)
                Spacer()
                Text("\(l.count(.longTerm)) de \(l.total)").font(Typo.text(14)).foregroundStyle(Palette.muted)
            }
            SplitBar(parts: order.map { (l.count($0), color($0)) })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(l.name): " + order.map { "\(l.count($0)) \($0.name)" }.joined(separator: ", "))
    }

    private func color(_ s: Stats.Standing) -> Color {
        switch s {
        case .longTerm: Palette.longTerm
        case .reviewing: Palette.reviewing
        case .learning: Palette.learning
        case .fresh: Palette.notBegun
        }
    }

    // MARK: how well

    @ViewBuilder
    private var howWell: some View {
        let recall = RecallLog.tally()
        let days = Stats.behind(logs)
        let right = days.reduce(0) { $0 + $1.right }
        let answers = days.reduce(0) { $0 + $1.right + $1.wrong }
        let hard = Stats.struggling(words).map(\.es).joined(separator: ", ")
        VStack(alignment: .leading, spacing: 14) {
            if recall.total > 0 {
                headline("\(percent(recall.right, recall.total))%", "recordadas al volver", sub: recallDetail(recall))
            } else {
                note("Cuando una palabra vuelva tras su espera, aquí verás si la recuerdas.")
            }
            if answers > 0 {
                HStack(spacing: 16) {
                    Swatch(color: Palette.answerRight, label: "Bien")
                    Swatch(color: Palette.answerWrong, label: "Mal")
                }
                DayColumns(columns: days.map(column),
                           summary: "\(answers == 1 ? "1 respuesta" : "\(answers) respuestas") en 14 días, \(percent(right, answers))% bien.")
            }
            if !hard.isEmpty {
                note("Te cuestan: \(hard).")
            }
        }
    }

    private func recallDetail(_ now: (right: Int, total: Int)) -> String {
        var out = "\(now.right) de \(now.total) tras su espera, en 14 días."
        let before = RecallLog.tally(back: 14)
        // Too few answers and the difference is only noise.
        if now.total >= 10, before.total >= 10 {
            let diff = percent(now.right, now.total) - percent(before.right, before.total)
            let points = abs(diff) == 1 ? "1 punto" : "\(abs(diff)) puntos"
            out += diff == 0 ? " Igual que los 14 anteriores." : " \(points) \(diff > 0 ? "más" : "menos") que los 14 anteriores."
        }
        return out
    }

    private func column(_ d: Stats.DayBehind) -> DayColumn {
        let total = d.right + d.wrong
        let detail = total == 0 ? "no estudiaste." : "\(total == 1 ? "1 respuesta" : "\(total) respuestas"), \(d.right) bien y \(d.wrong) mal."
        return DayColumn(date: d.date, parts: [(d.right, Palette.answerRight), (d.wrong, Palette.answerWrong)], detail: detail)
    }

    // MARK: what's coming

    @ViewBuilder
    private var coming: some View {
        let days = Stats.ahead(words)
        if days.allSatisfy({ $0.tests == 0 }) {
            note("Las palabras que domines volverán a las 24, 48 y 96 horas. Aquí verás cuándo.")
        } else {
            let now = words.count { $0.stage == 5 && Scheduler.isDue($0) }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 22) {
                    figure(days[0].tests, now > 0 && now != days[0].tests ? "Hoy, \(now) ya" : "Hoy")
                    figure(days[1].tests, "Mañana")
                    figure(days.prefix(7).reduce(0) { $0 + $1.tests }, "En 7 días")
                }
                HStack(spacing: 16) {
                    Swatch(color: Palette.reviewing, label: "Repasos")
                    Swatch(color: Palette.longTerm, label: "Llegan a largo plazo")
                }
                DayColumns(columns: days.map(column), summary: arrivals(days))
            }
        }
    }

    private func figure(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(Typo.display(22)).foregroundStyle(Palette.ink)
            Text(label).font(Typo.text(13, .bold)).foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private func arrivals(_ days: [Stats.DayAhead]) -> String {
        let week = days.prefix(7).reduce(0) { $0 + $1.arrivals }
        let all = days.reduce(0) { $0 + $1.arrivals }
        guard all > 0 else { return "Contando con que aciertes todo." }
        return week == all ? "Si aciertas, \(all) a largo plazo en 7 días." : "Si aciertas, \(week) a largo plazo en 7 días y \(all) en 14."
    }

    private func column(_ d: Stats.DayAhead) -> DayColumn {
        let tests = d.tests == 1 ? "1 repaso" : "\(d.tests) repasos"
        let detail = d.tests == 0 ? "nada por repasar." : d.arrivals == 0 ? "\(tests)." : "\(tests), \(d.arrivals) \(d.arrivals == 1 ? "llega" : "llegan") a largo plazo."
        return DayColumn(date: d.date, parts: [(d.arrivals, Palette.longTerm), (d.tests - d.arrivals, Palette.reviewing)], detail: detail)
    }

    // MARK: parts

    private func headline(_ value: String, _ label: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value).font(Typo.display(34)).foregroundStyle(Palette.ink)
                Text(label).font(Typo.text(16, .bold)).foregroundStyle(Palette.ink)
            }
            Text(sub).font(Typo.text(14)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Typo.text(14)).foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func percent(_ part: Int, _ whole: Int) -> Int {
        whole == 0 ? 0 : Int((Double(part) / Double(whole) * 100).rounded())
    }
}

/// One whole split in order: a thin bar with a small gap between parts.
private struct SplitBar: View {
    let parts: [(count: Int, color: Color)]

    var body: some View {
        GeometryReader { geo in
            let shown = parts.filter { $0.count > 0 }
            let total = CGFloat(shown.reduce(0) { $0 + $1.count })
            // Every part gets enough to see, and the rest is shared out, so the parts always add up to the width.
            let least: CGFloat = 3
            let room = max(0, geo.size.width - CGFloat(max(0, shown.count - 1)) * 2 - least * CGFloat(shown.count))
            HStack(spacing: 2) {
                ForEach(shown.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(shown[i].color)
                        .frame(width: least + room * CGFloat(shown[i].count) / max(1, total))
                }
            }
        }
        .frame(height: 8)
    }
}

/// A colour's name beside a small square of it, and how many if that's wanted.
private struct Swatch: View {
    let color: Color
    let label: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(Typo.text(13)).foregroundStyle(Palette.muted)
            if let count {
                Text("\(count)").font(Typo.text(13, .bold)).foregroundStyle(Palette.ink)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DayColumn: Identifiable {
    let date: Date
    /// From the baseline up.
    let parts: [(count: Int, color: Color)]
    /// What the day holds, said after its name.
    let detail: String

    var id: Date { date }
    var total: Int { parts.reduce(0) { $0 + $1.count } }
}

/// One column per day on one scale. Tap a day to read it, and again to go back to the summary.
struct DayColumns: View {
    let columns: [DayColumn]
    let summary: String
    @State private var picked: Date?

    private static let es = Locale(identifier: "es")
    private let height: CGFloat = 72

    var body: some View {
        let top = max(1, columns.map(\.total).max() ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(columns) { column($0, top: top) }
            }
            Text(readout).font(Typo.text(14)).foregroundStyle(Palette.ink)
                .lineLimit(2, reservesSpace: true)
                .accessibilityHidden(true)
        }
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-pickDay"), i + 1 < args.count, let n = Int(args[i + 1]), columns.indices.contains(n) {
                picked = columns[n].date
            }
        }
        #endif
    }

    private var readout: String {
        guard let day = columns.first(where: { $0.date == picked }) else { return summary }
        return "\(name(day.date)): \(day.detail)"
    }

    private func column(_ day: DayColumn, top: Int) -> some View {
        let today = Calendar.current.isDateInToday(day.date)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { picked = picked == day.date ? nil : day.date }
        } label: {
            VStack(spacing: 4) {
                VStack(spacing: 2) {
                    ForEach(day.parts.indices.reversed(), id: \.self) { i in
                        if day.parts[i].count > 0 {
                            UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                                .fill(day.parts[i].color)
                                .frame(height: max(3, height * CGFloat(day.parts[i].count) / CGFloat(top)))
                        }
                    }
                }
                .frame(maxWidth: 16)
                .frame(maxWidth: .infinity)
                .frame(height: height + 4, alignment: .bottom)
                .opacity(picked == nil || picked == day.date ? 1 : 0.35)
                Rectangle().fill(Palette.edge).frame(height: 1)
                Text(today ? "hoy" : day.date.formatted(.dateTime.weekday(.narrow).locale(Self.es)))
                    .font(Typo.text(11, today || picked == day.date ? .heavy : .medium))
                    .foregroundStyle(today || picked == day.date ? Palette.ink : Palette.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name(day.date)): \(day.detail)")
    }

    private func name(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Hoy" }
        if cal.isDateInTomorrow(date) { return "Mañana" }
        if cal.isDateInYesterday(date) { return "Ayer" }
        let weekday = date.formatted(.dateTime.weekday(.wide).locale(Self.es))
        return weekday.prefix(1).uppercased() + weekday.dropFirst() + " \(cal.component(.day, from: date))"
    }
}
