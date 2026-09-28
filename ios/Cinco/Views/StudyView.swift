import SwiftUI

struct StudyView: View {
    let session: StudySession
    let onExit: () -> Void

    @State private var typed = ""
    @State private var grid: [Int: String] = [:]
    @State private var dragX: CGFloat = 0
    /// Whether the card's sentences are open under the answer.
    @State private var showSentences = false
    /// The card just missed, while its mnemonic sheet is up.
    @State private var mnemonicFor: Card?
    /// A short note after a card is set aside, with a way to take it back.
    @State private var droppedNote: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case answer, cell(Int) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let c = session.current {
                StageTiles(stage: c.stage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                card(c)
                if !session.canGrade { actions(c).padding(.top, 18) }
            }
        }
        .overlay(alignment: .bottom) {
            if let note = droppedNote {
                HStack(spacing: 14) {
                    Text(note).font(Typo.text(14, .bold)).foregroundStyle(Palette.ink)
                    Button("Deshacer") { session.undo(); droppedNote = nil }
                        .font(Typo.text(14, .heavy)).tint(Palette.accentInk)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .panel(radius: 20, shadow: 3)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: note) {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { droppedNote = nil }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Backdrop())
        .animation(.snappy(duration: 0.25), value: session.canGrade)
        .onChange(of: session.step, initial: true) {
            typed = ""; grid = [:]; dragX = 0; showSentences = false
        }
        .sheet(item: $mnemonicFor) { c in
            MnemonicSheet(card: c, meaning: c.isConj ? session.verb(of: c)?.en ?? "" : c.en)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.bg)
                .presentationCornerRadius(28)
        }
        .onChange(of: session.phase) { _, p in
            if p == .prompt, let c = session.current {
                if session.mode == .type { focus = .answer }
                if session.mode == .grid { focus = session.asked(session.forms(of: c)).first.map(Field.cell) }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button("‹ Inicio", action: onExit)
            Spacer()
            Text((session.label.isEmpty ? "" : session.label + " · ") + (session.remaining == 1 ? "Queda 1" : "Quedan \(session.remaining)"))
                .font(Typo.display(20)).foregroundStyle(Palette.ink)
            Spacer()
            Button("Deshacer") { session.undo() }.disabled(!session.canUndo)
        }
        .font(Typo.text(16, .heavy))
        .tint(Palette.accentInk)
        .frame(minHeight: 44)
    }

    // MARK: the card

    private func card(_ c: Card) -> some View {
        GeometryReader { g in
            ScrollView {
                cardContent(c).frame(maxWidth: .infinity, minHeight: g.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // A faint daisy in the corner, in the card's stage colour, like the cutouts in the icon.
        .background(alignment: .topTrailing) {
            Daisy().fill(Palette.stage(c.stage).opacity(0.1))
                .frame(width: 96, height: 96)
                .offset(x: 26, y: -26)
        }
        .clipShape(.rect(cornerRadius: 28))
        .panel(radius: 28, shadow: 6)
        .overlay(alignment: .topLeading) { dropButton(c).opacity(dragX == 0 ? 1 : 0) }
        .overlay(alignment: .bottom) {
            if session.canGrade { gradeTabs.transition(.opacity.combined(with: .offset(y: 12))) }
            else if let hint = tapHint { tapPill(hint).opacity(dragX == 0 ? 1 : 0).transition(.opacity) }
        }
        .overlay(alignment: .topLeading) { stamp("¡La sé!", Palette.good, -12).opacity(Double(max(0, dragX) / 110)) }
        .overlay(alignment: .topTrailing) { stamp("Otra vez", Palette.again, 12).opacity(Double(max(0, -dragX) / 110)) }
        .offset(x: dragX)
        .rotationEffect(.degrees(Double(dragX) / 20))
        .contentShape(.rect)
        .onTapGesture { tap() }
        .simultaneousGesture(swipe)
    }

    /// Sets the card aside for good: hidden from study, but kept in Explorar, where it can come back.
    private func dropButton(_ c: Card) -> some View {
        Button {
            let note = c.isConj ? "Tiempo descartado · en Explorar" : "Descartada · en Explorar"
            session.drop()
            withAnimation(.snappy) { droppedNote = note }
        } label: {
            Image(systemName: "eye.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .padding(6)
        .accessibilityLabel(c.isConj ? "Descartar este tiempo de este verbo" : "Descartar esta palabra")
        .accessibilityHint("Deja de salir al estudiar. Puedes recuperarla en Explorar.")
    }

    /// Centred in the card when it fits, scrolling when a verb's tables make it tall.
    private func cardContent(_ c: Card) -> some View {
            VStack(spacing: 0) {
                if c.isConj { conjContent(c) } else { vocabContent(c) }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
            // Room for the tap pill, so tall content never slides under it.
            .padding(.bottom, session.canGrade ? 84 : tapHint == nil ? 0 : 44)
    }

    /// The two grades, along the foot of the card, each pointing the way its swipe goes. Dragging the card
    /// leans on the one it's heading for: that one grows, the other fades.
    private var gradeTabs: some View {
        let toward = min(1, abs(dragX) / 110)
        return HStack(spacing: 10) {
            Button { grade(false) } label: { BigLabel("Otra vez", "baja una etapa").padding(.leading, 12) }
                .buttonStyle(GradeTabStyle(color: Palette.again, text: .white, right: false))
                .scaleEffect(dragX < 0 ? 1 + 0.06 * toward : 1)
                .opacity(dragX > 0 ? 1 - 0.6 * toward : 1)
                .accessibilityLabel("Otra vez, baja una etapa")
            Button { grade(true) } label: { BigLabel("¡La sé!", "sube una etapa").padding(.trailing, 12) }
                .buttonStyle(GradeTabStyle(color: Palette.good, text: Palette.onGood, right: true))
                .scaleEffect(dragX > 0 ? 1 + 0.06 * toward : 1)
                .opacity(dragX < 0 ? 1 - 0.6 * toward : 1)
                .accessibilityLabel("La sé, sube una etapa")
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    /// Pinned to the foot of the card: a hand that taps now and then, and what a tap will show.
    private func tapPill(_ hint: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .foregroundStyle(Palette.accentInk)
                .symbolEffect(.bounce, options: .repeat(.periodic(delay: 2.5)))
            Text(hint).foregroundStyle(Palette.muted)
        }
        .font(Typo.text(14, .bold))
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Palette.sunk, in: .capsule)
        .padding(.bottom, 18)
        .allowsHitTesting(false) // a tap on it is a tap on the card
        .accessibilityHidden(true)
    }

    private var tapHint: String? {
        switch session.phase {
        case .word: "Toca para ver el significado"
        case .prompt where [.esEn, .enEs, .recite].contains(session.mode): "Toca para ver la respuesta"
        default: nil
        }
    }

    /// Grades the card; a first miss this session asks for a mnemonic (Ajustes › Pedir mnemotecnias).
    private func grade(_ pass: Bool) {
        guard let c = session.current, session.canGrade else { return }
        let firstMiss = !pass && !session.missed.contains { $0 === c }
        droppedNote = nil // its Deshacer would now undo this grade instead
        session.grade(pass)
        if firstMiss && session.prefs.askMnemonics { mnemonicFor = c }
    }

    private func tap() {
        switch session.phase {
        case .word: session.showMeaning()
        case .prompt where [.esEn, .enEs, .recite].contains(session.mode): session.reveal()
        default: break
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { v in
                guard session.canGrade, abs(v.translation.width) > abs(v.translation.height) else { return }
                dragX = v.translation.width
            }
            .onEnded { v in
                guard session.canGrade, abs(dragX) > 110 else {
                    withAnimation(.easeOut(duration: 0.2)) { dragX = 0 }
                    return
                }
                let pass = dragX > 0
                withAnimation(.easeIn(duration: 0.2)) { dragX = pass ? 600 : -600 }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    grade(pass)
                }
            }
    }

    private func stamp(_ text: String, _ color: Color, _ angle: Double) -> some View {
        Text(text)
            .font(Typo.display(20)).foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Palette.paper, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color, lineWidth: 2.5))
            .softShadow(radius: 6, y: 3)
            .rotationEffect(.degrees(angle))
            .padding(18)
            .allowsHitTesting(false)
    }

    // MARK: vocabulary

    /// Vocabulario and Frases: the Spanish and its meaning, nothing else unless asked for.
    @ViewBuilder
    private func vocabContent(_ c: Card) -> some View {
        let revealed = session.phase != .prompt
        switch session.mode {
        case .intro:
            kicker(c.isPhrase ? "Frase nueva" : "Palabra nueva")
            word(c.es, phrase: c.isPhrase)
            english(c.en).padding(.top, 10)
            notesIfAny(c)
            speakButton()
            moreAbout(c)
        case .esEn:
            kicker(c.isPhrase ? "¿Qué quiere decir?" : "¿Qué significa?")
            word(c.es, phrase: c.isPhrase)
            speakButton()
            if revealed {
                answerBlock {
                    english(c.en)
                    notesIfAny(c)
                    moreAbout(c)
                }
            }
        case .enEs:
            kicker("Dilo en español")
            english(c.en)
            if revealed {
                answerBlock {
                    word(c.es, phrase: c.isPhrase)
                    notesIfAny(c)
                    speakButton()
                    moreAbout(c)
                }
            }
        default: // type
            kicker("Escríbelo en español")
            english(c.en)
            if revealed {
                answerBlock {
                    word(c.es, phrase: c.isPhrase)
                    VerdictTag(verdict: session.verdict ?? .skip, typed: session.typed)
                    notesIfAny(c)
                    speakButton()
                    moreAbout(c)
                }
            } else {
                HStack(spacing: 8) {
                    TextField("…", text: $typed)
                        .font(Typo.text(22, .bold))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .answer)
                        .submitLabel(.done)
                        .onSubmit { session.check(typed) }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Palette.sunk, in: .rect(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(focus == .answer ? Palette.sea.opacity(0.6) : Palette.edge, lineWidth: 1.5))
                    Button("Comprobar") { session.check(typed) }
                        .buttonStyle(SoftButtonStyle(fill: Palette.sea, text: .white, radius: 18, size: 18))
                        .fixedSize()
                }
                .padding(.top, 22)
            }
        }
    }

    // MARK: in a sentence

    /// The card's own example and sentences.
    private func sentences(_ c: Card) -> [String] {
        var seen = Set<String>()
        return ([c.ex] + c.frases.split(separator: "|").map(String.init))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert(TextMatch.strip($0)).inserted }
            .prefix(3).map { $0 }
    }

    /// An optional extra under the answer: the word in a sentence.
    @ViewBuilder
    private func moreAbout(_ c: Card) -> some View {
        let list = sentences(c)
        if !list.isEmpty {
            moreChip("En una frase", icon: "text.bubble.fill")
                .padding(.top, 18)
            if showSentences {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(list, id: \.self) { es in
                        Button { session.speak(es) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "speaker.wave.2.fill").font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Palette.sea).padding(.top, 4)
                                Text(es).font(Typo.italic(18)).foregroundStyle(Palette.ink)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(es)
                        .accessibilityHint("Toca para escucharla")
                    }
                }
                .multilineTextAlignment(.leading)
                .morePanel()
            }
        }
    }

    private func moreChip(_ title: String, icon: String) -> some View {
        let on = showSentences
        return Button {
            withAnimation(.snappy(duration: 0.25)) { showSentences.toggle() }
        } label: {
            Label(title, systemImage: icon)
                .font(Typo.text(14, .heavy))
                .foregroundStyle(on ? Palette.onGood : Palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(on ? Palette.sea : Palette.paper, in: .capsule)
                .overlay(Capsule().strokeBorder(on ? .clear : Palette.edge, lineWidth: 1))
                .softShadow(radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: conjugation

    @ViewBuilder
    private func conjContent(_ c: Card) -> some View {
        let v = session.verb(of: c)
        let f = session.forms(of: c)
        let asked = session.asked(f)
        let tense = Tense.named(c.tense)
        // A verb's note describes its present (o→ue, yo-go…), so it would mislead under any other tense.
        let note = c.tense == "presente" ? (v?.notes ?? "") : ""
        let kick = switch session.mode {
        case .intro: "Conjugación nueva"
        case .recite: "Conjúgalo en voz alta"
        default: "Escribe la tabla"
        }

        kicker(kick)
        word(c.es)
        if session.phase != .word, let v { english(v.en).padding(.top, 6) }
        if let tense {
            Text(tense.name)
                .font(Typo.text(15, .heavy)).foregroundStyle(Palette.mood(tense.mood))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Palette.moodSoft(tense.mood), in: .capsule)
                .padding(.top, 14)
        }

        if session.phase != .word {
            switch (session.mode, session.phase) {
            case (.intro, _), (.recite, .answer):
                ConjTable(forms: f, tense: c.tense).padding(.top, 16)
                conjExtras(c, v, note: note)
            case (.grid, .prompt):
                ConjTable(forms: f, tense: c.tense, hidden: { !asked.contains($0) }) { p in
                    TextField("", text: Binding(get: { grid[p] ?? "" }, set: { grid[p] = $0 }))
                        .font(Typo.text(18, .bold))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .cell(p))
                        .submitLabel(p == asked.last ? .done : .next)
                        .onSubmit {
                            if let i = asked.firstIndex(of: p), i + 1 < asked.count { focus = .cell(asked[i + 1]) } else { session.checkGrid(grid) }
                        }
                        .padding(.vertical, 2)
                        .overlay(alignment: .bottom) { Capsule().fill(Palette.line).frame(height: 2) }
                        .accessibilityLabel(Person.label(p, c.tense))
                }
                .padding(.top, 16)
            case (.grid, .answer):
                let res = session.cells
                let right = asked.filter { res[$0]?.verdict == .exact }.count
                let near = asked.filter { res[$0]?.verdict.isNear == true }.count
                if right == asked.count {
                    Pill(text: "¡Todo correcto!", fill: Palette.goodSoft, ink: Palette.good)
                } else {
                    Pill(text: "\(right) de \(asked.count) bien" + (near > 0 ? ", \(near) casi (acentos)" : ""),
                         fill: right + near == asked.count ? Palette.near : Palette.againSoft,
                         ink: right + near == asked.count ? Color(white: 0.1) : Palette.again)
                }
                ConjTable(forms: f, tense: c.tense, hidden: { !asked.contains($0) },
                          tint: { res[$0].map { CellTint($0.verdict) } }) { p in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(f[p]).font(Typo.text(17, .heavy)).foregroundStyle(res[p]?.verdict.isNear == true ? Color(white: 0.1) : Palette.ink)
                        if let r = res[p], r.verdict != .exact {
                            Text(r.typed.isEmpty ? "—" : r.typed).strikethrough()
                                .font(Typo.text(14, .bold)).foregroundStyle(Palette.again)
                        }
                    }
                }
                .padding(.top, 16)
                conjExtras(c, v, note: note)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func conjExtras(_ c: Card, _ v: Card?, note: String) -> some View {
        if !note.isEmpty { notes(note) }
        mnemonicIfAny(c)
        Button { session.speakTable() } label: { SpeakIcon() }.padding(.top, 14)
        if let v { VerbTables(verb: v, skip: c.tense, showFirst: false).padding(.top, 14) }
    }

    // MARK: actions under the card

    @ViewBuilder
    private func actions(_ c: Card) -> some View {
        switch session.phase {
        case .intro:
            Button { session.introDone() } label: {
                BigLabel("Entendido, pregúntame luego", "Vuelve dentro de unas tarjetas")
            }
            .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white))
        case .word:
            Button("Ver el significado") { session.showMeaning() }
                .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white))
        case .prompt:
            switch session.mode {
            case .esEn, .enEs:
                Button("Mostrar respuesta") { session.reveal() }
                    .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white))
            case .recite:
                Button("Mostrar la tabla") { session.reveal() }
                    .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white))
            case .grid:
                Button("Comprobar") { session.checkGrid(grid) }
                    .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white))
            default:
                EmptyView()
            }
        default:
            // Grading happens on the card itself (gradeTabs).
            EmptyView()
        }
    }

    // MARK: pieces

    private func kicker(_ s: String) -> some View {
        Text(s).font(Typo.text(14, .heavy)).foregroundStyle(Palette.muted).padding(.bottom, 14)
    }

    private func word(_ s: String, phrase: Bool = false) -> some View {
        Text(s).font(Typo.display(phrase ? 32 : 40)).foregroundStyle(Palette.ink)
    }

    private func english(_ s: String) -> some View {
        Text(s).font(Typo.text(26, .heavy)).foregroundStyle(Palette.en)
    }

    private func notes(_ s: String) -> some View {
        Text(s).font(Typo.text(14)).foregroundStyle(Palette.muted).padding(.top, 12)
    }

    @ViewBuilder
    private func notesIfAny(_ c: Card) -> some View {
        if !c.notes.isEmpty { notes(c.notes) }
        mnemonicIfAny(c)
    }

    @ViewBuilder
    private func mnemonicIfAny(_ c: Card) -> some View {
        if !c.mnemonic.isEmpty {
            Label(c.mnemonic, systemImage: "lightbulb.fill")
                .font(Typo.text(15, .bold)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Palette.stageSoft(2), in: .rect(cornerRadius: 14))
                .padding(.top, 14)
                .accessibilityLabel("Mnemotecnia: \(c.mnemonic)")
        }
    }

    private func speakButton() -> some View {
        Button { session.speak() } label: { SpeakIcon() }.padding(.top, 14)
    }

    private func answerBlock<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 0) {
            Line().stroke(Palette.line, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5])).frame(height: 2.5)
                .padding(.vertical, 22)
            content()
        }
    }
}

/// Two lines on a big button: what it does, and a small note.
/// A grade button shaped like an arrow tab, pointing the way the card swipes for that grade.
private struct GradeTabStyle: ButtonStyle {
    let color: Color
    let text: Color
    let right: Bool

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .font(Typo.display(19))
            .foregroundStyle(text)
            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background { Gloss(color: color, shape: ArrowTab(right: right), lift: down ? 0.2 : 0.7) }
            .offset(y: down ? 1.5 : 0)
            .animation(.spring(duration: 0.18), value: down)
            .contentShape(ArrowTab(right: right))
    }
}

/// A rounded tab whose outer end comes to a soft point.
nonisolated struct ArrowTab: Shape {
    var right = true

    func path(in r: CGRect) -> Path {
        let d = min(22, r.height * 0.4)
        var pts = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX - d, y: r.minY), CGPoint(x: r.maxX, y: r.midY),
                   CGPoint(x: r.maxX - d, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        if !right { pts = pts.map { CGPoint(x: r.minX + r.maxX - $0.x, y: $0.y) } }
        let radii: [CGFloat] = [16, 12, 7, 12, 16]
        var p = Path()
        let n = pts.count
        p.move(to: CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2))
        for i in 0..<n {
            p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % n], radius: radii[i])
        }
        p.closeSubpath()
        return p
    }
}

struct BigLabel: View {
    let title: String, sub: String
    init(_ title: String, _ sub: String) { self.title = title; self.sub = sub }

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
            Text(sub).font(Typo.text(13, .bold)).opacity(0.85)
        }
    }
}

struct SpeakIcon: View {
    var body: some View {
        Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(Palette.sea, in: .circle)
            .shadow(color: Palette.sea.opacity(0.35), radius: 8, y: 4)
            .accessibilityLabel("Escúchala")
    }
}

struct Pill: View {
    let text: String, fill: Color, ink: Color

    var body: some View {
        Text(text).font(Typo.text(15, .heavy)).foregroundStyle(ink)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(fill, in: .capsule)
            .padding(.top, 14)
    }
}

struct VerdictTag: View {
    let verdict: Verdict
    let typed: String

    var body: some View {
        switch verdict {
        case .exact: Pill(text: "¡Correcto!", fill: Palette.goodSoft, ink: Palette.good)
        case .accent: near("Casi, revisa los acentos")
        case .article: near("Bien la palabra, revisa el artículo")
        case .wrong:
            Pill(text: "No exactamente", fill: Palette.againSoft, ink: Palette.again)
            wrote
        case .skip: Pill(text: "Sin respuesta", fill: Palette.againSoft, ink: Palette.again)
        }
    }

    @ViewBuilder
    private func near(_ s: String) -> some View {
        Pill(text: s, fill: Palette.near, ink: Color(white: 0.1))
        wrote
    }

    private var wrote: some View {
        (Text("Escribiste ") + Text(typed).strikethrough().foregroundColor(Palette.again))
            .font(Typo.text(15)).foregroundStyle(Palette.muted).padding(.top, 6)
    }
}

private extension View {
    /// The sunk box the sentences open in.
    func morePanel() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.sunk, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line, lineWidth: 1))
            .padding(.top, 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// A horizontal line, for the dashed divider above an answer.
nonisolated struct Line: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) }
    }
}
