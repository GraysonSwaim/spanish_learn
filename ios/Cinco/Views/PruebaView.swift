import SwiftUI

/// A prueba on paper: the whole sheet at once, answered in any order, and nothing marked until it's handed in. Then the
/// red pen goes over it: a tick or a cross by each question, the right answer beside a wrong one, and the score circled.
struct PruebaView: View {
    @Bindable var prueba: Prueba
    let onDone: () -> Void

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
        .task {
            await prueba.fillGaps()
            #if DEBUG
            // `-handIn` answers about half right, half wrong, and hands it in, to see the red pen.
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
    }

    @ViewBuilder
    private var score: some View {
        let total = prueba.items.count
        if prueba.state == .marked {
            Text("\(prueba.score)/\(total)")
                .font(Typo.display(28)).foregroundStyle(Self.pen)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(Ellipse().stroke(Self.pen, lineWidth: 2.5).padding(-4))
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
            Text(hint).font(Typo.text(13)).foregroundStyle(Palette.muted)
        }
    }

    // MARK: I. writing

    private var writeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("I", "Escribe en español", "Con el artículo si es un sustantivo.")
            ForEach(prueba.section(.write)) { item in writeRow(item) }
        }
    }

    private func writeRow(_ item: PruebaItem) -> some View {
        let mark = prueba.marks[item.id]
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
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
                if let mark { correction(mark, answer: item.spanish) }
            }
            tick(mark)
        }
    }

    private func focusNext(after id: String) {
        let ids = prueba.section(.write).map(\.id)
        guard let i = ids.firstIndex(of: id) else { return }
        focus = i + 1 < ids.count ? ids[i + 1] : nil
    }

    // MARK: II. matching

    private var matchSection: some View {
        let words = prueba.section(.match)
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("II", "Une cada palabra con su significado", "Toca una palabra y luego su significado.")
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
            if prueba.state == .marked {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(words.filter { prueba.marks[$0.id]?.right == false }) { item in
                        Text("\(prueba.number(item.id)). \(item.spanish): \(item.english)")
                            .font(Typo.sentence(15)).italic().foregroundStyle(Self.pen)
                    }
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
            guard prueba.state == .answering else { return }
            picking = picked ? nil : item.id
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Once marked, the pen's tick takes the number's place: the column is narrow.
                if let mark = prueba.marks[item.id] { tick(mark) } else { number(item.id) }
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
        .accessibilityHint(prueba.state == .answering ? "Tócala y luego toca su significado" : "")
    }

    private func meaning(_ id: String) -> String { prueba.meanings.first { $0.id == id }?.english ?? "" }

    private func matchMeaning(_ m: PruebaItem) -> some View {
        let taken = prueba.matched.values.contains(m.id)
        return Button {
            guard prueba.state == .answering, let w = picking else { return }
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
            ForEach(prueba.section(.cloze)) { item in clozeRow(item) }
        }
    }

    private func clozeRow(_ item: PruebaItem) -> some View {
        let mark = prueba.marks[item.id]
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            number(item.id)
            VStack(alignment: .leading, spacing: 10) {
                Text("«\(item.gapped)»").font(Typo.sentence(17)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                FlowRow(spacing: 8) {
                    ForEach(item.options, id: \.self) { o in option(o, item: item) }
                }
                if mark != nil, !item.sentenceEnglish.isEmpty {
                    Text(item.sentenceEnglish).font(Typo.text(14)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            tick(mark)
        }
    }

    private func option(_ o: String, item: PruebaItem) -> some View {
        let picked = prueba.chosen[item.id] == o
        let marked = prueba.state == .marked
        let isAnswer = o == item.form
        return Button {
            guard prueba.state == .answering else { return }
            prueba.chosen[item.id] = picked ? nil : o
        } label: {
            Text(o).font(Typo.text(16, .bold)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .overlay {
                    if picked && !marked {
                        Capsule().strokeBorder(Palette.ink, lineWidth: 2)
                    } else if marked && isAnswer {
                        // The red pen rings the right one.
                        Ellipse().stroke(Self.pen, lineWidth: 2).padding(-2)
                    } else {
                        Capsule().strokeBorder(Palette.line, lineWidth: 1)
                    }
                }
                .overlay(alignment: .center) {
                    if marked && picked && !isAnswer {
                        Rectangle().fill(Self.pen).frame(height: 2).padding(.horizontal, 8)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(o)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    // MARK: the pen

    private func number(_ id: String) -> some View {
        Text("\(prueba.number(id)).").font(Typo.text(15, .heavy)).foregroundStyle(Palette.muted)
            .frame(minWidth: 24, alignment: .trailing)
    }

    @ViewBuilder
    private func tick(_ mark: PruebaMark?) -> some View {
        if let mark {
            Image(systemName: mark.right ? "checkmark" : "xmark")
                .font(.system(size: 20, weight: .heavy)).foregroundStyle(Self.pen)
                .rotationEffect(.degrees(mark.right ? -8 : 0))
                .frame(width: 24)
                .accessibilityLabel(mark.right ? "Bien" : "Mal")
        }
    }

    @ViewBuilder
    private func correction(_ mark: PruebaMark, answer: String) -> some View {
        if !mark.right || mark.near || !mark.note.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if !mark.right || mark.near { Text(answer).font(Typo.sentence(17)).italic() }
                if !mark.note.isEmpty { Text(mark.note).font(Typo.text(13)) }
            }
            .foregroundStyle(Self.pen)
            .fixedSize(horizontal: false, vertical: true)
        }
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
            VStack(alignment: .leading, spacing: 14) {
                if !prueba.learned.isEmpty {
                    Text(prueba.learned.count == 1 ? "1 palabra aprendida: \(prueba.learned[0])."
                         : "\(prueba.learned.count) palabras aprendidas: \(prueba.learned.joined(separator: ", ")).")
                        .font(Typo.sentence(17)).foregroundStyle(Self.pen)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let missed = prueba.items.count - prueba.score
                if missed > 0 {
                    Text(missed == 1 ? "La que fallaste vuelve a tus repasos." : "Las \(missed) que fallaste vuelven a tus repasos.")
                        .font(Typo.text(14)).foregroundStyle(Palette.muted)
                }
                if prueba.cost > 0 {
                    Text("Claude en esta prueba: \(CostLog.format(prueba.cost))")
                        .font(Typo.text(13)).foregroundStyle(Palette.muted)
                }
                Button(action: onDone) { Text("Listo").frame(maxWidth: .infinity) }
                    .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 18))
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
