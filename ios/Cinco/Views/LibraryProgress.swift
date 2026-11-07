import SwiftUI

/// Home's picture of the library: how much of it has been learned, level by level.
struct LibraryProgress: View {
    let words: [Card]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(Palette.line).frame(height: 1)
            Text("TU BIBLIOTECA").font(Typo.text(13, .heavy)).tracking(1).foregroundStyle(Palette.muted)
                .accessibilityAddTraits(.isHeader)
            library
        }
        .padding(.top, 28)
    }

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

/// A colour's name beside a small square of it, and how many.
private struct Swatch: View {
    let color: Color
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(Typo.text(13)).foregroundStyle(Palette.muted)
            Text("\(count)").font(Typo.text(13, .bold)).foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}
