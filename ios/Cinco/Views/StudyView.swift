import SwiftUI

struct StudyView: View {
    let session: StudySession
    let onExit: () -> Void

    @State private var typed = ""
    @State private var grid: [Int: String] = [:]
    @State private var dragX: CGFloat = 0
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
                actions(c).padding(.top, 18)
                if session.canGrade {
                    Text("Desliza la tarjeta: → si la sabías, ← si no")
                        .font(Typo.text(13, .bold)).foregroundStyle(Palette.muted).padding(.top, 12)
                }
                Button(c.isConj ? "Descartar este tiempo de este verbo" : "Descartar esta palabra, no la necesito") {
                    session.drop()
                }
                .font(Typo.text(14, .bold)).foregroundStyle(Palette.muted).padding(.top, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Palette.bg.ignoresSafeArea())
        .onChange(of: session.current?.id) { typed = ""; grid = [:]; dragX = 0 }
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
        .panel(radius: 28, shadow: 6)
        .overlay(alignment: .topLeading) { stamp("¡La sé!", Palette.good, -12).opacity(Double(max(0, dragX) / 110)) }
        .overlay(alignment: .topTrailing) { stamp("Otra vez", Palette.again, 12).opacity(Double(max(0, -dragX) / 110)) }
        .offset(x: dragX)
        .rotationEffect(.degrees(Double(dragX) / 20))
        .contentShape(.rect)
        .onTapGesture { tap() }
        .simultaneousGesture(swipe)
    }

    /// Centred in the card when it fits, scrolling when a verb's tables make it tall.
    private func cardContent(_ c: Card) -> some View {
            VStack(spacing: 0) {
                if c.isConj { conjContent(c) } else { vocabContent(c) }
                if let hint = tapHint {
                    Text(hint).font(Typo.text(13, .bold)).foregroundStyle(Palette.muted).opacity(0.8).padding(.top, 22)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
    }

    private var tapHint: String? {
        switch session.phase {
        case .word: "Toca la tarjeta para ver el significado"
        case .prompt where [.esEn, .enEs, .recite].contains(session.mode): "Toca la tarjeta para ver la respuesta"
        case .answer where session.showsForms: "Toca la tarjeta para ver la conjugación"
        default: nil
        }
    }

    private func tap() {
        switch session.phase {
        case .word: session.showMeaning()
        case .prompt where [.esEn, .enEs, .recite].contains(session.mode): session.reveal()
        case .answer where session.showsForms: session.showForms()
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
                    session.grade(pass)
                }
            }
    }

    private func stamp(_ text: String, _ color: Color, _ angle: Double) -> some View {
        Text(text)
            .font(Typo.display(20)).foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Palette.paper, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color, lineWidth: 3))
            .rotationEffect(.degrees(angle))
            .padding(18)
            .allowsHitTesting(false)
    }

    // MARK: vocabulary

    @ViewBuilder
    private func vocabContent(_ c: Card) -> some View {
        let revealed = session.phase != .prompt
        switch session.mode {
        case .intro:
            kicker("Palabra nueva")
            word(c.es)
            english(c.en).padding(.top, 10)
            extras(c)
            speakButton()
            if c.isVerb { VerbTables(verb: c).padding(.top, 16) }
        case .esEn:
            kicker("¿Qué significa?")
            word(c.es)
            if !revealed { example(c) }
            speakButton()
            if revealed {
                answerBlock {
                    english(c.en)
                    extras(c)
                    forms(c)
                }
            }
        case .enEs:
            kicker("Dilo en español")
            english(c.en)
            if revealed {
                answerBlock {
                    word(c.es)
                    extras(c)
                    speakButton()
                    forms(c)
                }
            }
        default: // type
            kicker("Escríbelo en español")
            english(c.en)
            if revealed {
                answerBlock {
                    word(c.es)
                    VerdictTag(verdict: session.verdict ?? .skip, typed: session.typed)
                    extras(c)
                    speakButton()
                    forms(c)
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
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.edge, lineWidth: 2.5))
                    Button("Comprobar") { session.check(typed) }
                        .buttonStyle(ChunkyButtonStyle(fill: Palette.sea, text: .white, radius: 18, size: 18))
                        .fixedSize()
                }
                .padding(.top, 22)
            }
        }
    }

    /// A verb's third step.
    @ViewBuilder
    private func forms(_ c: Card) -> some View {
        if session.phase == .forms { VerbTables(verb: c).padding(.top, 16) }
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
                conjExtras(v, note: note, skip: c.tense)
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
                        .overlay(alignment: .bottom) { Rectangle().fill(Palette.edge).frame(height: 2) }
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
                conjExtras(v, note: note, skip: c.tense)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func conjExtras(_ v: Card?, note: String, skip: String) -> some View {
        if !note.isEmpty { notes(note) }
        Button { session.speakTable() } label: { SpeakIcon() }.padding(.top, 14)
        if let v { VerbTables(verb: v, skip: skip, showFirst: false).padding(.top, 14) }
    }

    // MARK: actions under the card

    @ViewBuilder
    private func actions(_ c: Card) -> some View {
        switch session.phase {
        case .intro:
            Button { session.introDone() } label: {
                BigLabel("Entendido, pregúntame luego", "Vuelve dentro de unas tarjetas")
            }
            .buttonStyle(ChunkyButtonStyle(fill: Palette.accent, text: .white))
        case .word:
            Button("Ver el significado") { session.showMeaning() }
                .buttonStyle(ChunkyButtonStyle(fill: Palette.accent, text: .white))
        case .prompt:
            switch session.mode {
            case .esEn, .enEs:
                Button("Mostrar respuesta") { session.reveal() }
                    .buttonStyle(ChunkyButtonStyle(fill: Palette.accent, text: .white))
            case .recite:
                Button("Mostrar la tabla") { session.reveal() }
                    .buttonStyle(ChunkyButtonStyle(fill: Palette.accent, text: .white))
            case .grid:
                Button("Comprobar") { session.checkGrid(grid) }
                    .buttonStyle(ChunkyButtonStyle(fill: Palette.accent, text: .white))
            default:
                EmptyView()
            }
        case .answer where session.showsForms:
            Button("Ver la conjugación") { session.showForms() }
                .buttonStyle(ChunkyButtonStyle(fill: Palette.accent, text: .white))
        default:
            HStack(spacing: 10) {
                Button { session.grade(false) } label: { BigLabel("Otra vez", "baja una etapa") }
                    .buttonStyle(ChunkyButtonStyle(fill: Palette.againSoft, text: Palette.again))
                Button { session.grade(true) } label: { BigLabel("¡La sé!", "sube una etapa") }
                    .buttonStyle(ChunkyButtonStyle(fill: Palette.good, text: Palette.onGood))
            }
        }
    }

    // MARK: pieces

    private func kicker(_ s: String) -> some View {
        Text(s).font(Typo.text(14, .heavy)).foregroundStyle(Palette.muted).padding(.bottom, 14)
    }

    private func word(_ s: String) -> some View {
        Text(s).font(Typo.display(40)).foregroundStyle(Palette.ink)
    }

    private func english(_ s: String) -> some View {
        Text(s).font(Typo.text(26, .heavy)).foregroundStyle(Palette.en)
    }

    @ViewBuilder
    private func example(_ c: Card) -> some View {
        if !c.ex.isEmpty {
            Text(c.ex).font(Typo.italic(18)).foregroundStyle(Palette.muted).padding(.top, 14)
        }
    }

    private func notes(_ s: String) -> some View {
        Text(s).font(Typo.text(14)).foregroundStyle(Palette.muted).padding(.top, 12)
    }

    @ViewBuilder
    private func extras(_ c: Card) -> some View {
        example(c)
        if !c.notes.isEmpty { notes(c.notes) }
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
            .background(Circle().fill(Palette.edge).offset(y: 3))
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

/// A horizontal line, for the dashed divider above an answer.
nonisolated struct Line: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) }
    }
}
