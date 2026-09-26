import SwiftUI

/// How a typed cell went.
enum CellTint {
    case ok, near, no

    init(_ v: Verdict) { self = v == .exact ? .ok : v.isNear ? .near : .no }

    var color: Color {
        switch self {
        case .ok: Palette.goodSoft
        case .near: Palette.near
        case .no: Palette.againSoft
        }
    }
}

/// One tense as a 3×2 table, persons down the columns like a textbook:
/// yo | nosotros, tú | vosotros, él | ellos.
struct ConjTable<Cell: View>: View {
    let forms: [String]
    let tense: String
    /// Cells left blank (a person the tense lacks, or one not being asked).
    var hidden: (Int) -> Bool = { _ in false }
    var tint: (Int) -> CellTint? = { _ in nil }
    @ViewBuilder let cell: (Int) -> Cell

    @AppStorage(PrefKey.vosotros) private var vosotros = false

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    box(row)
                    box(row + 3)
                }
            }
        }
        .frame(maxWidth: 340)
    }

    @ViewBuilder
    private func box(_ p: Int) -> some View {
        let has = p < forms.count && !forms[p].isEmpty
        if has && !hidden(p) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Person.label(p, tense))
                    .font(Typo.text(12, .bold))
                    .foregroundStyle(tint(p) == .near ? Color(white: 0.1) : Palette.muted)
                cell(p)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(tint(p)?.color ?? Palette.sunk, in: .rect(cornerRadius: 12))
            .opacity(p == Person.vosotros && !vosotros ? 0.45 : 1)
        } else {
            Color.clear.gridCellUnsizedAxes(.vertical)
        }
    }
}

extension ConjTable where Cell == AnyView {
    /// A plain table showing the forms.
    init(forms: [String], tense: String) {
        self.init(forms: forms, tense: tense) { p in
            AnyView(Text(forms[p]).font(Typo.text(17, .heavy)).foregroundStyle(Palette.ink))
        }
    }
}

/// A tense's name above its table.
struct NamedTable: View {
    let forms: [String]
    let tense: Tense

    var body: some View {
        VStack(spacing: 8) {
            Text(tense.name).font(Typo.text(14, .heavy)).foregroundStyle(Palette.mood(tense.mood))
            ConjTable(forms: forms, tense: tense.key)
        }
    }
}

/// A verb's tables. The first shows; the rest fold under a disclosure.
struct VerbTables: View {
    let verb: Card
    var skip: String? = nil
    var foldedLabel = "Otros tiempos"
    var showFirst = true

    @State private var open = false

    var body: some View {
        let list = verb.tenseList.filter { $0.key != skip }
        let first = showFirst ? list.first : nil
        let rest = showFirst ? Array(list.dropFirst()) : list
        VStack(spacing: 14) {
            if let first { NamedTable(forms: verb.forms(first.key), tense: first) }
            if !rest.isEmpty {
                DisclosureGroup(isExpanded: $open) {
                    VStack(spacing: 16) {
                        ForEach(rest) { t in NamedTable(forms: verb.forms(t.key), tense: t) }
                    }
                    .padding(.top, 10)
                } label: {
                    Text(foldedLabel).font(Typo.text(14, .heavy)).foregroundStyle(Palette.muted)
                }
                .tint(Palette.muted)
            }
        }
    }
}
