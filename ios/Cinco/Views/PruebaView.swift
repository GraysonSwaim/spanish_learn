import SwiftUI

/// A prueba on paper: the whole sheet at once, answered in any order, and nothing marked until it's handed in. Marked,
/// each answer turns green or red: a miss shows what was answered beside the right answer, and why, with a way to
/// remember it. Then a new sheet can ask the misses again, with words no sheet has asked yet.
struct PruebaView: View {
    @Bindable var prueba: Prueba
    let onDone: () -> Void
    /// A new sheet: the misses of this one (their ids) first, then words not asked yet.
    let onRefresh: ([String]) -> Void

    /// Section II: the Spanish word picked, waiting for its meaning.
    @State private var picking: String?
    @FocusState private var focus: String?

    private static let pen = Palette.again

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                sheet
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            #if DEBUG
            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-scrollBottom") ? .bottom : .top)
            #endif
        }
        .background(Backdrop())
        .animation(.easeInOut(duration: 0.25), value: prueba.state)
        .animation(.easeInOut(duration: 0.25), value: prueba.tips)
        .task {
            await prueba.fillGaps()
            #if DEBUG
            // `-handIn` answers about half right, half wrong, and hands it in, to see it marked.
            if ProcessInfo.processInfo.arguments.contains("-handIn") {
                for (i, item) in prueba.items.enumerated() {
                    let right = i % 2 == 0
                    switch item.format {
                    case .write: prueba.typed[item.id] = right ? item.spanish : "algo"
                    case .match: prueba.matched[item.id] = right ? item.id : prueba.meanings.first { $0.id != item.id }?.id
                    case .cloze: prueba.chosen[item.id] = right ? item.form : item.options.first { $0 != item.form }
                    }
                }
                await prueba.handIn()
            }
            #endif
        }
    }

    private var topBar: some View {
        HStack {
            if prueba.state == .answering {
                Button("Ahora no", action: onDone)
                    .font(Typo.text(16, .heavy)).tint(Palette.accentInk)
                    .frame(minHeight: 44)
            }
            Spacer()
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        // Plaster under the clock, so the sheet scrolls away behind it rather than through it.
        .background(Palette.bg, ignoresSafeAreaEdges: .top)
        .zIndex(1)
    }

    private var marked: Bool { prueba.state == .marked }

    // MARK: the sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 26) {
            header
            if !prueba.section(.write).isEmpty { writeSection }
            if !prueba.section(.match).isEmpty { matchSection }
            if !prueba.section(.cloze).isEmpty { clozeSection }
            footer
        }
        .padding(.horizontal, 20).padding(.vertical, 24)
        .background {
            ZStack(alignment: .leading) {
                Palette.paper
                // The margin rule of a school sheet.
                Rectangle().fill(Self.pen.opacity(0.28)).frame(width: 1).padding(.leading, 12)
            }
        }
        .clipShape(.rect(cornerRadius: 3))
        .shadow(color: Palette.shadow, radius: 8, y: 3)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PRUEBA").font(Typo.text(14, .heavy)).tracking(2).foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(prueba.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es"))))
                        .font(Typo.text(14)).foregroundStyle(Palette.muted)
                }
                Spacer()
                score
            }
            if marked {
                let wrong = prueba.items.count - prueba.score
                HStack(spacing: 16) {
                    Label("\(prueba.score) bien", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.good)
                    if wrong > 0 {
                        Label("\(wrong) por repasar", systemImage: "xmark.circle.fill").foregroundStyle(Self.pen)
                    }
                }
                .font(Typo.text(15, .heavy))
            }
        }
    }

    @ViewBuilder
    private var score: some View {
        let total = prueba.items.count
        if marked {
            let good = Double(prueba.score) >= 0.8 * Double(total)
            let ink = good ? Palette.good : Self.pen
            Text("\(prueba.score)/\(total)")
                .font(Typo.display(28)).foregroundStyle(ink)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(Ellipse().stroke(ink, lineWidth: 2.5).padding(-4))
                .rotationEffect(.degrees(-6))
                .padding(.trailing, 6).padding(.top, 2)
                .accessibilityLabel("\(prueba.score) de \(total)")
        } else {
            Text("___ / \(total)").font(Typo.text(18, .bold)).foregroundStyle(Palette.muted)
                .accessibilityLabel("\(total) preguntas")
        }
    }

    private func sectionTitle(_ numeral: String, _ title: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(numeral). \(title)").font(Typo.text(17, .heavy)).foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if !marked { Text(hint).font(Typo.text(13)).foregroundStyle(Palette.muted) }
        }
    }

    // MARK: I. writing

    private var writeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("I", "Escribe en español", "Solo la palabra: el artículo no hace falta.")
            ForEach(prueba.section(.write)) { item in
                if let mark = prueba.marks[item.id] { writeResult(item, mark) } else { writeRow(item) }
            }
        }
    }

    private func writeRow(_ item: PruebaItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            number(item.id)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.english).font(Typo.text(16)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("", text: binding(\.typed, item.id), prompt: Text("…").foregroundStyle(Palette.muted.opacity(0.5)))
                    .font(Typo.sentence(18)).foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: item.id)
                    .onSubmit { focusNext(after: item.id) }
                    .disabled(prueba.state != .answering)
                    .padding(.bottom, 4)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.edge).frame(height: 1) }
                    .accessibilityLabel("\(prueba.number(item.id)). \(item.english), en español")
            }
        }
    }

    private func writeResult(_ item: PruebaItem, _ mark: PruebaMark) -> some View {
        let typed = prueba.answer(item)
        return result(item, mark) {
            Text(item.english).font(Typo.text(15)).foregroundStyle(Palette.muted)
            if mark.right {
                Text(typed).font(Typo.sentence(19)).foregroundStyle(Palette.good)
                // The card's own form, for its article and spelling: shown, never marked.
                if TextMatch.norm(typed) != TextMatch.norm(item.spanish) {
                    Text(item.spanish).font(Typo.text(14)).foregroundStyle(Palette.muted)
                }
                if !mark.note.isEmpty {
                    Text(mark.note).font(Typo.text(14)).foregroundStyle(Palette.good)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                answered(typed, wrong: true)
                Text(item.spanish).font(Typo.sentence(19)).fontWeight(.bold).foregroundStyle(Palette.ink)
            }
        }
    }

    private func focusNext(after id: String) {
        let ids = prueba.section(.write).map(\.id)
        guard let i = ids.firstIndex(of: id) else { return }
        focus = i + 1 < ids.count ? ids[i + 1] : nil
    }

    // MARK: II. matching

    @ViewBuilder
    private var matchSection: some View {
        let words = prueba.section(.match)
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("II", "Une cada palabra con su significado", "Toca una palabra y luego su significado.")
            if marked {
                ForEach(words) { item in
                    if let mark = prueba.marks[item.id] {
                        result(item, mark) {
                            Text(item.spanish).font(Typo.sentence(19)).fontWeight(.bold).foregroundStyle(mark.right ? Palette.good : Palette.ink)
                            if !mark.right { answered(prueba.answer(item), wrong: true) }
                            Text(item.english).font(Typo.text(16, .bold)).foregroundStyle(Palette.ink)
                        }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(words) { item in matchWord(item) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(prueba.meanings) { m in matchMeaning(m) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The letter a meaning goes by, so a pair can be told at a glance: a, b, c…
    private func letter(_ id: String) -> String {
        let i = prueba.meanings.firstIndex { $0.id == id } ?? 0
        return String(UnicodeScalar(UInt8(97 + i % 26)))
    }

    private func matchWord(_ item: PruebaItem) -> some View {
        let pair = prueba.matched[item.id]
        let picked = picking == item.id
        return Button {
            picking = picked ? nil : item.id
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                number(item.id)
                Text(item.spanish).font(Typo.text(16, .bold)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                Text(pair.map(letter) ?? "_").font(Typo.text(16, .heavy))
                    .foregroundStyle(pair == nil ? Palette.muted : Palette.accentInk)
            }
            .padding(.horizontal, 8).padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(picked ? Palette.sunk : .clear, in: .rect(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(picked ? Palette.accentInk : Palette.line, lineWidth: picked ? 1.5 : 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(prueba.number(item.id)). \(item.spanish)" + (pair.map { ", unida con \(meaning($0))" } ?? ""))
        .accessibilityHint("Tócala y luego toca su significado")
    }

    private func meaning(_ id: String) -> String { prueba.meanings.first { $0.id == id }?.english ?? "" }

    private func matchMeaning(_ m: PruebaItem) -> some View {
        let taken = prueba.matched.values.contains(m.id)
        return Button {
            guard let w = picking else { return }
            // A meaning goes with one word: taking it from another word frees that one.
            for (k, v) in prueba.matched where v == m.id { prueba.matched[k] = nil }
            prueba.matched[w] = m.id
            picking = nil
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(letter(m.id)).font(Typo.text(15, .heavy)).foregroundStyle(Palette.accentInk)
                Text(m.english).font(Typo.text(15)).foregroundStyle(taken && picking == nil ? Palette.muted : Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(picking != nil ? Palette.accentInk.opacity(0.5) : Palette.line, lineWidth: 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(letter(m.id)): \(m.english)")
    }

    // MARK: III. gaps

    private var clozeSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("III", "Completa la frase", "Frases de tu libro. Elige la palabra que falta.")
            ForEach(prueba.section(.cloze)) { item in
                if let mark = prueba.marks[item.id] {
                    result(item, mark) {
                        filled(item, right: mark.right)
                        if !mark.right { answered(prueba.answer(item), wrong: true) }
                        if !item.sentenceEnglish.isEmpty {
                            Text(item.sentenceEnglish).font(Typo.text(14)).foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    clozeRow(item)
                }
            }
        }
    }

    private func clozeRow(_ item: PruebaItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            number(item.id)
            VStack(alignment: .leading, spacing: 10) {
                Text("«\(item.gapped)»").font(Typo.sentence(17)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                FlowRow(spacing: 8) {
                    ForEach(item.options, id: \.self) { o in option(o, item: item) }
                }
            }
        }
    }

    /// The sentence with the right word back in its gap, picked out.
    private func filled(_ item: PruebaItem, right: Bool) -> some View {
        var text = AttributedString("«\(item.sentence)»")
        if let r = text.range(of: item.form, options: .caseInsensitive) {
            text[r].foregroundColor = right ? Palette.good : Palette.ink
            text[r].font = Typo.sentence(17).bold()
            text[r].underlineStyle = .single
        }
        return Text(text).font(Typo.sentence(17)).foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func option(_ o: String, item: PruebaItem) -> some View {
        let picked = prueba.chosen[item.id] == o
        return Button {
            prueba.chosen[item.id] = picked ? nil : o
        } label: {
            Text(o).font(Typo.text(16, .bold)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .overlay {
                    Capsule().strokeBorder(picked ? Palette.ink : Palette.line, lineWidth: picked ? 2 : 1)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(o)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    // MARK: marked

    /// One marked question: green when right, red when not, and a miss explained underneath.
    private func result<Content: View>(_ item: PruebaItem, _ mark: PruebaMark, @ViewBuilder content: () -> Content) -> some View {
        let ink = mark.right ? Palette.good : Self.pen
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: mark.right ? "checkmark" : "xmark")
                    .font(.system(size: 17, weight: .heavy)).foregroundStyle(ink)
                    .frame(width: 22)
                    .accessibilityLabel(mark.right ? "Bien" : "Mal")
                VStack(alignment: .leading, spacing: 4) { content() }
                Spacer(minLength: 0)
                Text("\(prueba.number(item.id))").font(Typo.text(13, .heavy)).foregroundStyle(Palette.muted)
            }
            .accessibilityElement(children: .combine)
            if !mark.right { explanation(item, mark) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mark.right ? Palette.goodSoft : Palette.againSoft, in: .rect(cornerRadius: 6))
    }

    /// What was answered, crossed out when it was wrong.
    private func answered(_ text: String, wrong: Bool) -> some View {
        Group {
            if text.isEmpty {
                Text("Sin contestar")
            } else {
                Text("Pusiste ") + Text(text).strikethrough(wrong, color: Self.pen)
            }
        }
        .font(Typo.text(15)).foregroundStyle(Self.pen)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Why, and how to remember it: Claude's tip, then what the card itself says (its sentence, note and mnemonic).
    private func explanation(_ item: PruebaItem, _ mark: PruebaMark) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !mark.note.isEmpty {
                Text(mark.note).font(Typo.text(14)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let tip = prueba.tips[item.id] {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Palette.near)
                    Text(tip).font(Typo.text(15)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if prueba.explaining {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Claude está preparando cómo recordarla…").font(Typo.text(14)).foregroundStyle(Palette.muted)
                }
            }
            if item.format != .cloze, !item.example.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("«\(item.example)»").font(Typo.sentence(16)).italic().foregroundStyle(Palette.ink)
                    if !item.exampleEnglish.isEmpty {
                        Text(item.exampleEnglish).font(Typo.text(14)).foregroundStyle(Palette.muted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if !item.note.isEmpty {
                Text(item.note).font(Typo.text(14)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.mnemonic.isEmpty {
                Text("Tu mnemotecnia: \(item.mnemonic)").font(Typo.text(14, .bold)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else if prueba.tips[item.id] != nil {
                Button { prueba.keepTip(item.id) } label: {
                    Label("Guardarla como mnemotecnia", systemImage: "bookmark")
                        .font(Typo.text(14, .heavy)).frame(minHeight: 44)
                }
                .tint(Palette.accentInk)
            }
        }
        .padding(.leading, 32)
    }

    private func number(_ id: String) -> some View {
        Text("\(prueba.number(id)).").font(Typo.text(15, .heavy)).foregroundStyle(Palette.muted)
            .frame(minWidth: 24, alignment: .trailing)
    }

    // MARK: handing in

    @ViewBuilder
    private var footer: some View {
        switch prueba.state {
        case .answering:
            let blank = prueba.items.count { !answered($0) }
            VStack(spacing: 8) {
                Button {
                    focus = nil
                    Task { await prueba.handIn() }
                } label: { Text("Entregar").frame(maxWidth: .infinity) }
                .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 18))
                if blank > 0 {
                    Text(blank == 1 ? "Queda 1 sin contestar: cuenta como mal." : "Quedan \(blank) sin contestar: cuentan como mal.")
                        .font(Typo.text(13)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.top, 6)
        case .marking:
            HStack(spacing: 10) {
                ProgressView()
                Text("Corrigiendo…").font(Typo.text(16, .bold)).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity).padding(.top, 6)
        case .marked:
            let missed = prueba.missed
            VStack(alignment: .leading, spacing: 14) {
                if !prueba.learned.isEmpty {
                    Label(prueba.learned.count == 1 ? "1 palabra aprendida: \(prueba.learned[0])."
                          : "\(prueba.learned.count) palabras aprendidas: \(prueba.learned.joined(separator: ", ")).",
                          systemImage: "star.fill")
                        .font(Typo.text(16, .bold)).foregroundStyle(Palette.good)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !missed.isEmpty {
                    Text(missed.count == 1 ? "La que fallaste vuelve también a tus repasos." : "Las \(missed.count) que fallaste vuelven también a tus repasos.")
                        .font(Typo.text(14)).foregroundStyle(Palette.muted)
                }
                if prueba.cost > 0 {
                    Text("Claude en esta prueba: \(CostLog.format(prueba.cost))")
                        .font(Typo.text(13)).foregroundStyle(Palette.muted)
                }
                Button { onRefresh(missed) } label: {
                    VStack(spacing: 2) {
                        Label("Nueva prueba", systemImage: "arrow.clockwise")
                        Text(missed.isEmpty ? "con palabras que aún no te han preguntado"
                             : "\(missed.count == 1 ? "tu fallo" : "tus \(missed.count) fallos") y palabras que aún no te han preguntado")
                            .font(Typo.text(13)).opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 18))
                Button(action: onDone) { Text("Listo").frame(maxWidth: .infinity) }
                    .buttonStyle(SoftButtonStyle(fill: Palette.paper, text: Palette.ink, size: 17))
            }
            .padding(.top, 6)
        }
    }

    private func answered(_ item: PruebaItem) -> Bool {
        switch item.format {
        case .write: !TextMatch.norm(prueba.typed[item.id] ?? "").isEmpty
        case .match: prueba.matched[item.id] != nil
        case .cloze: prueba.chosen[item.id] != nil
        }
    }

    private func binding(_ path: ReferenceWritableKeyPath<Prueba, [String: String]>, _ id: String) -> Binding<String> {
        Binding(get: { prueba[keyPath: path][id] ?? "" }, set: { prueba[keyPath: path][id] = $0 })
    }
}

/// Choices laid out like words on a line, wrapping when they run out of room.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + s.width <= width {
                rows[rows.count - 1].items.append(i)
                rows[rows.count - 1].width += spacing + s.width
                rows[rows.count - 1].height = max(last.height, s.height)
            } else {
                rows.append(([i], s.width, s.height))
            }
        }
        return rows
    }
}
