import Testing
import Foundation
import SwiftData
@testable import Cinco

/// Expected values are fixed: they were taken from the original web app, and card ids must never drift from them.
struct TextMatchTests {
    @Test(arguments: [
        ("el coche / el carro", "el coche / el carro", "1gnmjdb"),
        ("¿Qué tal?", "que tal", "675jm9"),
        ("año", "año", "3776di"),
        ("Niño", "niño", "yknpzw"),
        ("tener", "tener", "4k0bib"),
        ("pequeño", "pequeño", "19suabp"),
        ("café con leche", "cafe con leche", "12sfz79"),
        ("hablar (con)", "hablar (con)", "13gu0ww"),
    ])
    func stripAndHashMatchTheWebApp(input: String, stripped: String, id: String) {
        #expect(TextMatch.strip(input) == stripped)
        #expect(TextMatch.cardID(input) == id)
    }

    @Test func checkGradesLikeTheWebApp() {
        #expect(TextMatch.check("el carro", against: "el coche / el carro") == .exact)
        #expect(TextMatch.check("El Coche!", against: "el coche / el carro") == .exact)
        #expect(TextMatch.check("cafe", against: "café") == .accent)
        #expect(TextMatch.check("coche", against: "el coche") == .article)
        #expect(TextMatch.check("hablar", against: "hablar (con)") == .exact)
        #expect(TextMatch.check("nino", against: "niño") == .wrong)
        #expect(TextMatch.check("  ", against: "niño") == .skip)
    }

    @Test func pronounsAreOptionalInTables() {
        #expect(TextMatch.dropPronoun("nosotros tuvimos", person: 3) == "tuvimos")
        #expect(TextMatch.dropPronoun("que yo tenga", person: 0) == "tenga")
        #expect(TextMatch.dropPronoun("tuvimos", person: 3) == "tuvimos")
        #expect(TextMatch.dropPronoun("ella tiene", person: 2) == "tiene")
    }

    @Test func spokenTextKeepsTheFirstAlternative() {
        #expect(TextMatch.spokenText("el coche / el carro") == "el coche")
        #expect(TextMatch.spokenText("pues…") == "pues")
    }
}

@MainActor
struct SchedulerTests {
    private func card(_ stage: Int, due: Date = .distantPast) -> Card {
        let c = Card(id: UUID().uuidString, es: "x", en: "y", order: 0)
        c.stage = stage
        c.due = due
        return c
    }

    private func stages(_ cards: [Card]) -> [Int] { cards.map(\.stage) }

    @Test func passMovesUpOnlyIntoRoom() {
        let (a, b, x, y) = (card(1), card(1), card(2), card(2))
        let pool = [a, b, x, y]
        Scheduler.pass(a, in: pool, cap: 3)
        #expect(a.stage == 2 && !a.ready)
        // Stage 2 is full now: b waits, ready.
        Scheduler.pass(b, in: pool, cap: 3)
        #expect(b.stage == 1 && b.ready)
    }

    /// A card mastered at the top lets each ready card behind it move up, all the way back to stage 1.
    @Test func aPlaceAtTheTopRipplesBack() {
        let (a, b, c, d) = (card(1), card(2), card(3), card(4))
        for x in [a, b, c] { x.ready = true }
        Scheduler.pass(d, in: [a, b, c, d], cap: 1)
        #expect(stages([a, b, c, d]) == [2, 3, 4, 5])
        #expect([a, b, c, d].allSatisfy { !$0.ready })
        #expect(Scheduler.room([a, b, c, d], cap: 1) == 1)
    }

    /// A stage 3 miss overfills stage 2, so nothing behind it moves until a stage 2 card is right again.
    @Test func aMissHoldsUpTheCardsBehindIt() {
        let (a, b, c, d) = (card(1), card(2), card(3), card(4))
        let pool = [a, b, c, d]
        Scheduler.fail(c, in: pool, cap: 1)
        #expect(stages(pool) == [1, 2, 2, 4] && c.lapses == 1)
        Scheduler.pass(a, in: pool, cap: 1)
        #expect(a.stage == 1 && a.ready)
        Scheduler.pass(b, in: pool, cap: 1)
        #expect(stages(pool) == [1, 3, 2, 4])
        #expect(Scheduler.room(pool, cap: 1) == 0)
    }

    @Test func failDropsOneStageNotBelowOne() {
        let c = card(3)
        Scheduler.fail(c, in: [], cap: 5)
        #expect(c.stage == 2 && c.lapses == 1)
        let d = card(1)
        d.ready = true
        Scheduler.fail(d, in: [], cap: 5)
        #expect(d.stage == 1 && !d.ready)
    }

    /// A week, then twice as long each time it's right once the wait is up. Early reviews don't stretch it.
    @Test func dominadaDoublesFromAWeek() {
        let now = Date()
        let day = { (n: Int) in Calendar.current.date(byAdding: .day, value: n, to: Calendar.current.startOfDay(for: now))! }
        let c = card(4)
        Scheduler.pass(c, in: [c], cap: 5, now: now)
        #expect(c.stage == 5 && c.interval == 7 && c.due == day(7))
        Scheduler.pass(c, in: [c], cap: 5, now: now)
        #expect(c.interval == 7 && c.due == day(7))
        let later = day(7).addingTimeInterval(3600)
        Scheduler.pass(c, in: [c], cap: 5, now: later)
        #expect(c.interval == 14)
        Scheduler.pass(c, in: [c], cap: 5, now: c.due)
        #expect(c.interval == 28)
    }

    /// A Dominada miss goes back to Producir, even when it's full.
    @Test func aDominadaMissOverfillsProducir() {
        let full = (0..<2).map { _ in card(4) }
        let c = card(5)
        c.interval = 28
        Scheduler.fail(c, in: full + [c], cap: 2)
        #expect(c.stage == 4 && c.interval == 0)
        #expect(Scheduler.counts(full + [c]).byStage[4] == 3)
    }

    @Test func dailyQueueIsStagesOneToFourAndDueDominadas() {
        let now = Date()
        let fresh = card(0)
        let w1 = card(2), w2 = card(4)
        w1.lastReviewed = now.addingTimeInterval(-60)
        w2.lastReviewed = now.addingTimeInterval(-600)
        let due = card(5, due: now.addingTimeInterval(-3600))
        let notYet = card(5, due: now.addingTimeInterval(86400))
        let q = Scheduler.dailyQueue([fresh, w1, w2, due, notYet], now: now)
        #expect(q.map(\.id) == [w2.id, due.id, w1.id])
        #expect(Scheduler.counts([fresh, w1, w2, due, notYet], now: now).due == 3)
    }

    /// Stages 1 and 2 keep the cards known best; the rest go back to the front of the new cards.
    @Test func trimSendsTheOverflowBackToNew() {
        let ones = (0..<4).map { i in let c = card(1); c.order = Double(10 + i); c.reps = i; return c }
        let new = card(0)
        new.order = 1
        let threes = (0..<4).map { _ in card(3) }
        Scheduler.trim(ones + [new] + threes, cap: 2)
        #expect(stages(ones) == [0, 0, 1, 1])
        #expect(ones[0].order < new.order && ones[1].order < new.order)
        #expect(stages(threes) == [3, 3, 3, 3])
    }
}

/// The daily session: new cards fill stage 1 to the cap, and it keeps going round.
@MainActor
struct PipelineSessionTests {
    @Test func newCardsFillStageOneToTheCap() throws {
        let schema = Schema([Card.self, DayLog.self, Chunk.self])
        let ctx = ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        let cards = (0..<7).map { i in let c = Card(id: "\(i)", es: "w\(i)", en: "e\(i)", order: Double(i)); ctx.insert(c); return c }
        var prefs = Prefs(); prefs.autoSpeak = false; prefs.direction = .esEn; prefs.stageCap = 3
        let s = StudySession(queue: [], tab: .vocab, pool: cards, fresh: cards, continuous: true, ctx: ctx, prefs: prefs)
        #expect(s.queue.map(\.es) == ["w0", "w1", "w2"])
        s.introDone()
        #expect(s.queue.count == 3 && cards[0].stage == 1)
        // Introduced, w0 is asked again later and moves up; stage 1 has room, so w3 comes in.
        while s.current !== cards[0] { s.introDone() }
        s.reveal(); s.grade(true)
        #expect(cards[0].stage == 2)
        #expect(s.queue.contains { $0 === cards[3] } && s.queue.contains { $0 === cards[0] })
        #expect(!s.queue.contains { $0 === cards[4] })
    }
}

/// The example sentence on a card: its words picked out, and what Claude's reply fills in.
@MainActor
struct ExampleTests {
    private func card(_ es: String, ex: String, word: String = "") -> Card {
        let c = Card(id: es, es: es, en: "x", order: 0)
        c.ex = ex
        c.exWord = word
        return c
    }

    @Test func findsTheCardInItsSentence() {
        let tener = card("tener", ex: "Tengo dos hermanos.", word: "Tengo")
        #expect(String(Examples.marked(tener, blank: true).characters) == "＿＿＿ dos hermanos.")
        // No word given: the Spanish itself, without its article, as a whole word whatever the accents.
        let casa = card("la casa", ex: "Mi casa está cerca del parque.")
        #expect(Examples.range(in: casa).map { String(casa.ex[$0]) } == "casa")
        let dia = card("el dia", ex: "Hoy es un buen día.")
        #expect(Examples.range(in: dia).map { String(dia.ex[$0]) } == "día")
        // "sé" isn't in "sé" inside "pasé".
        #expect(Examples.range(in: card("sé", ex: "Ayer pasé por aquí.")) == nil)
    }

    @Test func aReplyFillsOnlyWhatsMissing() {
        let c = card("tener", ex: "")
        Examples.apply(Tutor.Example(sentence: "Tengo frío.", english: "I'm cold.", word: "Tengo"), to: c, asked: "")
        #expect(c.ex == "Tengo frío." && c.exEn == "I'm cold." && c.exWord == "Tengo")
        // The sentence was edited while Claude was answering: the reply is for another sentence.
        let d = card("comer", ex: "Vamos a comer.")
        Examples.apply(Tutor.Example(sentence: "Como pan.", english: "I eat bread.", word: "Como"), to: d, asked: "Como pan.")
        #expect(d.exEn.isEmpty)
    }

    @Test func jsonCarriesTheExampleEnglishAndWord() throws {
        let r = try #require(CardJSON.parse("""
            {"spanish": "tener", "english": "to have", "example": "Tengo dos hermanos.", "example_english": "I have two brothers.", "example_word": "Tengo"}
            """)?.first)
        #expect(r.exEn == "I have two brothers." && r.exWord == "Tengo")
    }
}

/// One Vocabulario for words and phrases alike; verbs also get Conjugación.
@MainActor
struct SampleDeckTests {
    private func store() throws -> ModelContext {
        let schema = Schema([Card.self, DayLog.self, Chunk.self])
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(c)
    }

    /// Forty words and phrases, ten of them verbs with their six core tables for Conjugación.
    @Test func sampleDeckLoads() throws {
        let ctx = try store()
        let r = try #require(Deck.loadSample(ctx))
        #expect(r.added == 40)
        #expect(r.verbs == 10)
        let cards = Deck.allCards(ctx)
        #expect(cards.filter(\.isConj).count == 60)
        #expect(cards.filter { Scheduler.inTab($0, tab: .vocab, tense: "presente") }.count == 40)
    }

    /// Cards saved when phrases had a tab of their own study in Vocabulario.
    @Test func oldPhraseCardsAreWords() {
        let c = Card(id: "x", es: "¿Qué tal?", en: "How's it going?", order: 0)
        c.kindRaw = "phrase"
        #expect(c.kind == .word && !c.isConj)
        #expect(Scheduler.inTab(c, tab: .vocab, tense: "presente"))
    }
}

/// The cards a session remembers missing (a mnemonic is asked for on the first miss), and the mnemonic an edit keeps.
@MainActor
struct MnemonicTests {
    private func store() throws -> ModelContext {
        let schema = Schema([Card.self, DayLog.self, Chunk.self])
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(c)
    }

    private func cards(_ ctx: ModelContext, _ words: [String]) -> [Card] {
        words.enumerated().map { i, w in
            let c = Card(id: w, es: w, en: w, order: Double(i))
            c.stage = 1
            ctx.insert(c)
            return c
        }
    }

    @Test func missedCardsAreListedOnceAndUndoTakesThemBack() throws {
        let ctx = try store()
        var prefs = Prefs(); prefs.autoSpeak = false; prefs.direction = .esEn
        let s = StudySession(queue: cards(ctx, ["uno", "dos"]), tab: .vocab, ctx: ctx, prefs: prefs)
        func answer(_ pass: Bool) { s.reveal(); s.grade(pass) }
        answer(false)                       // uno missed, comes back later
        #expect(s.missed.map(\.es) == ["uno"])
        answer(true)                        // dos
        answer(false)                       // uno again: still listed once
        #expect(s.missed.map(\.es) == ["uno"])
        s.undo()                            // uno's second miss
        s.undo()                            // dos
        #expect(s.current?.es == "dos")
        #expect(s.answered == 1)
        #expect(s.missed.map(\.es) == ["uno"])
        answer(true)                        // dos
        answer(true)                        // uno right this time; it's still a card that was missed
        #expect(s.missed.map(\.es) == ["uno"])
        while s.canUndo { s.undo() }
        #expect(s.current?.es == "uno")
        #expect(s.missed.isEmpty)
    }

    @Test func undoingTheOnlyMissForgetsIt() throws {
        let ctx = try store()
        var prefs = Prefs(); prefs.autoSpeak = false; prefs.direction = .esEn
        let s = StudySession(queue: cards(ctx, ["uno"]), tab: .vocab, ctx: ctx, prefs: prefs)
        s.reveal(); s.grade(false)
        s.undo()
        #expect(s.missed.isEmpty)
    }

    @Test func editingKeepsTheMnemonic() throws {
        let ctx = try store()
        #expect(Deck.save(CardRecord(es: "el coche", en: "car"), editing: nil, ctx: ctx) == nil)
        let c = try #require(Deck.allCards(ctx).first)
        c.mnemonic = "suena a «coach»"
        var r = CardRecord(es: "el coche", en: "the car", mnemonic: c.mnemonic)
        #expect(Deck.save(r, editing: c, ctx: ctx) == nil)
        #expect(c.mnemonic == "suena a «coach»")
        r.mnemonic = ""
        #expect(Deck.save(r, editing: c, ctx: ctx) == nil)
        #expect(c.mnemonic.isEmpty)
    }
}

/// Deleting from Explorar, and Ajustes › Borrar todos los datos.
@MainActor
struct DeleteTests {
    private func store() throws -> ModelContext {
        let schema = Schema([Card.self, DayLog.self, Reading.self, Chunk.self])
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(c)
    }

    private func verb(_ ctx: ModelContext) {
        var r = CardRecord(es: "tener", en: "to have")
        r.tenses = ["presente": "tengo|tienes|tiene|tenemos|tenéis|tienen", "preterito": "tuve|tuviste|tuvo|tuvimos|tuvisteis|tuvieron"]
        Deck.importRecords([r, CardRecord(es: "la casa", en: "house")], into: ctx)
    }

    @Test func aVerbTakesItsTablesWithIt() throws {
        let ctx = try store()
        verb(ctx)
        #expect(Deck.allCards(ctx).count == 4)
        let tener = try #require(Deck.allCards(ctx).first { $0.es == "tener" && !$0.isConj })
        Deck.delete([tener], ctx: ctx)
        #expect(Deck.allCards(ctx).map(\.es) == ["la casa"])
    }

    @Test func aTableComesOffItsVerb() throws {
        let ctx = try store()
        verb(ctx)
        let pret = try #require(Deck.allCards(ctx).first { $0.isConj && $0.tense == "preterito" })
        Deck.delete([pret], ctx: ctx)
        let tener = try #require(Deck.allCards(ctx).first { $0.es == "tener" && !$0.isConj })
        #expect(tener.tenseList.map(\.key) == ["presente"])
        #expect(Deck.allCards(ctx).filter(\.isConj).map(\.tense) == ["presente"])
    }

    @Test func eraseAllLeavesNothing() throws {
        let ctx = try store()
        verb(ctx)
        ctx.insert(Reading(title: "x", lines: ["Hola."]))
        Chunks.create("Tema", ctx: ctx)
        _ = Deck.today(ctx)
        try ctx.save()
        Deck.eraseAll(ctx)
        #expect(Deck.allCards(ctx).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<DayLog>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Reading>()).isEmpty)
        #expect(Chunks.all(ctx).isEmpty)
    }
}

/// The JSON the sample deck is written in.
@MainActor
struct CardJSONTests {
    private func store() throws -> ModelContext {
        let schema = Schema([Card.self, DayLog.self, Chunk.self])
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(c)
    }

    @Test func aNounCard() throws {
        let recs = try #require(CardJSON.parse("""
            {"spanish": "la maleta", "english": "suitcase", "type": "word", "example": "Mi maleta es azul.",
             "notes": "Femenino. Plural: las maletas", "mnemonic": "A mallet smashing a suitcase", "tags": ["travel"]}
            """))
        #expect(recs == [CardRecord(es: "la maleta", en: "suitcase", ex: "Mi maleta es azul.", notes: "Femenino. Plural: las maletas",
                                    tags: "travel", mnemonic: "A mallet smashing a suitcase")])
    }

    /// A phrase exactly as ChatGPT sent it from the shortcut, with the "type" older prompts asked for.
    @Test func aPhraseFromChatGPT() throws {
        let r = try #require(CardJSON.parse("""
            {"type": "phrase", "spanish": "¡Qué meningitis!", "english": "No way! / You're kidding!", "example": "—Me ganaste la lotería. —¡Qué meningitis!",
            "notes": "Casual (tú), México.", "mnemonic": "Think of meningitis as a wild surprise that shocks you.", "tags": "slang, surprise"}
            """)?.first)
        #expect(r.es == "¡Qué meningitis!" && r.en == "No way! / You're kidding!")
        #expect(r.ex == "—Me ganaste la lotería. —¡Qué meningitis!")
        #expect(r.mnemonic.hasPrefix("Think of meningitis"))
        #expect(r.tags == "slang surprise")
    }

    @Test func aVerbWithEveryTense() throws {
        let text = """
            {"spanish": "bailar", "english": "to dance", "tenses": {
              "presente": ["bailo", "bailas", "baila", "bailamos", "bailáis", "bailan"],
              "imperativo_negativo": ["", "no bailes", "no baile", "no bailemos", "no bailéis", "no bailen"],
              "subj_imperfecto": "bailara / bailase|bailaras / bailases|bailara / bailase|bailáramos / bailásemos|bailarais / bailaseis|bailaran / bailasen",
              "made_up": ["x"]}}
            """
        let r = try #require(CardJSON.parse(text)?.first)
        #expect(r.es == "bailar")
        #expect(Set(r.tenses.keys) == ["presente", "imperativo_negativo", "subj_imperfecto"])
        #expect(r.tenses["imperativo_negativo"] == "|no bailes|no baile|no bailemos|no bailéis|no bailen")
    }

    @Test func aListOrWrappedCards() throws {
        #expect(CardJSON.parse(#"[{"es": "uno", "en": "one"}, {"es": "dos", "en": "two"}]"#)?.map(\.es) == ["uno", "dos"])
        #expect(CardJSON.parse(#"{"cards": [{"spanish": "uno", "english": "one", "mnemonic": "one → uno"}]}"#)?.first?.mnemonic == "one → uno")
        #expect(CardJSON.parse("spanish,english\nuno,one") == nil)
    }

    @Test func importKeepsTheLearnersMnemonic() throws {
        let ctx = try store()
        Deck.importRecords([CardRecord(es: "uno", en: "one", mnemonic: "del modelo")], into: ctx)
        let c = try #require(Deck.allCards(ctx).first)
        #expect(c.mnemonic == "del modelo")
        c.mnemonic = "mío"
        Deck.importRecords([CardRecord(es: "uno", en: "one", mnemonic: "otro")], into: ctx)
        #expect(c.mnemonic == "mío")
    }
}

/// Añadir tarjetas on a word the deck already has: it's found without its article, and the confirmation
/// lists exactly what would change.
@MainActor
struct ExistingCardTests {
    private func store() throws -> ModelContext {
        let schema = Schema([Card.self, DayLog.self, Chunk.self])
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(c)
    }

    @Test func foundWithOrWithoutTheArticle() throws {
        let ctx = try store()
        Deck.importRecords([CardRecord(es: "la maleta", en: "suitcase")], into: ctx)
        let cards = Deck.allCards(ctx)
        #expect(Deck.existing(CardRecord(es: "maleta", en: "x"), in: cards)?.es == "la maleta")
        #expect(Deck.existing(CardRecord(es: "La Maleta", en: "x"), in: cards)?.es == "la maleta")
        #expect(Deck.existing(CardRecord(es: "el maletín", en: "x"), in: cards) == nil)
    }

    @Test func changesListWhatsNewAndKeepsTheMnemonic() throws {
        let ctx = try store()
        Deck.importRecords([CardRecord(es: "hablar", en: "to speak", tenses: ["presente": "hablo|hablas|habla|hablamos|habláis|hablan"])], into: ctx)
        let c = try #require(Deck.allCards(ctx).first { !$0.isConj })
        c.mnemonic = "mío"
        #expect(Deck.changes(CardRecord(es: "hablar", en: "to speak"), to: c).isEmpty)
        let rec = CardRecord(es: "hablar", en: "to talk", ex: "Hablo inglés.", tenses: [
            "presente": "hablo|hablas|habla|hablamos|habláis|hablan", "futuro": "hablaré|hablarás|hablará|hablaremos|hablaréis|hablarán",
        ], mnemonic: "otro")
        #expect(Deck.changes(rec, to: c) == ["inglés: «to speak» → «to talk»", "ejemplo", "1 tiempo nuevo en Conjugación"])
    }
}

struct LecturaTests {
    @Test func oneLinePerLineOfTheText() {
        let text = "Ayer quedamos en el café. ¿Vienes mañana?\nTe echo de menos.\n\n  ¡Hasta luego!  "
        #expect(Lectura.lines(text) == ["Ayer quedamos en el café. ¿Vienes mañana?", "Te echo de menos.", "¡Hasta luego!"])
    }

    @Test func wordsSkipPunctuation() {
        let line = "¿Vienes mañana, María?"
        #expect(Lectura.words(line).map { String(line[$0]) } == ["Vienes", "mañana", "María"])
    }

    @Test func oldOneWordMarksJoinTheirNeighbours() {
        let lines = ["Te echo de menos, de verdad.", "Quedamos mañana."]
        // echo de menos (1-3) is one run; "de" after the comma (4) stands alone; line 2's "Quedamos" too.
        let runs = Lectura.runs(lines: lines, marks: ["0.1", "0.2", "0.3", "0.4", "1.0"])
        #expect(runs.map(\.text) == ["echo de menos", "de", "Quedamos"])
        #expect(runs.map(\.id) == ["0.1-3", "0.4-4", "1.0-0"])
    }

    @Test func tappedWordsStayApartAndASlideMakesAPhrase() {
        let lines = ["Te echo de menos, de verdad."]
        var marks: [String] = []
        Lectura.mark(&marks, line: 0, first: 1, last: 1)
        Lectura.mark(&marks, line: 0, first: 2, last: 2)
        #expect(Lectura.runs(lines: lines, marks: marks).map(\.text) == ["echo", "de"])
        // A slide across both, and a word past the comma, takes their place as one phrase.
        Lectura.mark(&marks, line: 0, first: 1, last: 4)
        #expect(Lectura.runs(lines: lines, marks: marks).map(\.text) == ["echo de menos, de"])
        #expect(Lectura.marked(marks, line: 0) == [1, 2, 3, 4])
        Lectura.unmark(&marks, line: 0, text: lines[0], word: 3)
        #expect(marks.isEmpty)
    }

    @Test func findsMissedWordsIgnoringCaseAndAccents() {
        #expect(Lectura.find("echo de menos", in: "Te echo de menos.") == [1, 2, 3])
        #expect(Lectura.find("cafe", in: "Ayer quedamos en el Café.") == [4])
        #expect(Lectura.find("perro", in: "Ayer quedamos en el café.") == nil)
    }

    @Test func aStretchOfThePageIsTheWholeWordsItTouches() {
        let text = "¿Te echo de menos? Sí, mañana."
        // UTF-16 places: "echo" is 4..<8, "menos" 12..<17.
        #expect(Lectura.words(in: text, from: 5, to: 6) == 1...1)
        #expect(Lectura.words(in: text, from: 6, to: 14) == 1...3)
        // A space, or punctuation, is no word.
        #expect(Lectura.words(in: text, from: 3, to: 4) == nil)
        #expect(Lectura.words(in: text, from: 17, to: 18) == nil)
    }

    @Test func thePagePaintsMarksAndWordsAlreadyInTheDeck() {
        let text = "Hoy el frutero nos ha regalado unas naranjas porque mi abuela le echa de menos."
        let lines = ["Otra cosa.", text]
        // "frutero" (2) marked, "echa de menos" (12-14) a phrase.
        let p = Lectura.paint(text, lines: lines, marks: ["1.2-2", "1.12-14"], known: ["abuela", "frutero"])
        let ns = text as NSString
        #expect(p.marked.map { ns.substring(with: NSRange(location: $0[0], length: $0[1] - $0[0])) } == ["frutero", "echa de menos"])
        // A marked word isn't underlined as well.
        #expect(p.known.map { ns.substring(with: NSRange(location: $0[0], length: $0[1] - $0[0])) } == ["abuela"])
        // A paragraph that isn't a line has no marks; a short one, no underlines.
        #expect(Lectura.paint("El frutero.", lines: lines, marks: ["1.2-2"], known: ["frutero"]) == ([], []))
    }

    @Test func aGlossMakesTheCardAndTheSentenceIsItsExample() {
        let run = Run(line: 0, first: 1, last: 3, text: "echo de menos")
        let gloss = Tutor.Gloss(spanish: "echar de menos", english: "to miss (someone)", note: "echo: presente, yo")
        let rec = Lectura.record(run, gloss: gloss, sentence: "Te echo de menos.")
        #expect(rec.es == "echar de menos" && rec.en == "to miss (someone)" && rec.ex == "Te echo de menos.")
        #expect(rec.notes == "echo: presente, yo" && rec.tags == "lectura")
        // Without a gloss: the words as written, no meaning yet.
        let plain = Lectura.record(run, gloss: nil, sentence: "Te echo de menos.")
        #expect(plain.es == "echo de menos" && plain.en.isEmpty)
    }

    @Test @MainActor func oldReadingsAreRecycled() throws {
        let schema = Schema([Card.self, DayLog.self, Reading.self, Chunk.self])
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = c.mainContext
        let now = Date.now
        let fresh = Reading(title: "nueva", lines: ["Hola."])
        let stale = Reading(title: "vieja", lines: ["Adiós."])
        stale.opened = now.addingTimeInterval(-31 * 86_400)
        ctx.insert(fresh); ctx.insert(stale)
        Lectura.recycle(ctx, now: now)
        let left = try ctx.fetch(FetchDescriptor<Reading>()).map(\.title)
        #expect(left == ["nueva"])
    }
}

/// Reading an article from a link (Nueva lectura › Desde un enlace).
struct ArticleTextTests {
    private let para = String(repeating: "El mercado abre temprano los sábados. ", count: 4)

    @Test func findsTheLinkInAShortPaste() {
        #expect(ArticleText.link(in: "https://elpais.com/a.html")?.host() == "elpais.com")
        #expect(ArticleText.link(in: "Mira esto: https://www.bbc.com/mundo/articles/x")?.host() == "www.bbc.com")
        #expect(ArticleText.link(in: "elpais.com/opinion")?.absoluteString == "https://elpais.com/opinion")
        #expect(ArticleText.link(in: "hola") == nil)
        #expect(ArticleText.link(in: "mailto:a@b.com") == nil)
        #expect(ArticleText.link(in: "https://a.com https://b.com") == nil)
        // A pasted text that happens to hold a link is a text.
        #expect(ArticleText.link(in: String(repeating: "Un texto largo. ", count: 40) + "https://a.com") == nil)
    }

    @Test func prefersTheWholeArticleInTheMetadata() {
        let meta = [para, para + "Y más."].joined(separator: "\n")
        let r = ArticleText.choose(paragraphs: [para], metadata: meta)
        #expect(r.fromMetadata && r.lines.count == 2)
    }

    @Test func aTeaserInTheMetadataLosesToTheArticle() {
        let r = ArticleText.choose(paragraphs: [para, para + "Dos.", para + "Tres."], metadata: "Resumen.\nCorto.")
        #expect(!r.fromMetadata && r.lines.count == 3)
    }

    @Test func oneLongMetadataBlockIsSplitIntoSentences() {
        let block = (1...12).map { "Esta es la frase número \($0) del artículo, con bastante texto para que pese." }.joined(separator: " ")
        let r = ArticleText.choose(paragraphs: [], metadata: block)
        #expect(r.fromMetadata && r.lines.count == 4)
    }

    @Test func tooLittleTextIsNoArticle() {
        #expect(ArticleText.choose(paragraphs: ["Example Domain", "More information..."], metadata: "").lines.isEmpty)
    }

    @Test func labelsAndRepeatsAreDropped() {
        let lines = ArticleText.clean(["PUBLICIDAD", "Fuente de la imagen, Getty Images", "Autor, Cecilia Barría",
                                       "Autoridades cubanas anunciaron cambios.", "Más leídas", "  Dos   espacios ", "Dos espacios", "—"])
        #expect(lines == ["Autoridades cubanas anunciaron cambios.", "Dos espacios"])
    }
}

/// Themes: words filed in chunks, chunks merged into bigger ones, and readings that become themes and sources.
@MainActor
struct ChunkTests {
    private func store() throws -> ModelContext {
        let schema = Schema([Card.self, DayLog.self, Reading.self, Chunk.self])
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(c)
    }

    private func words(_ es: [String], ctx: ModelContext) -> [Card] {
        Deck.importRecords(es.map { CardRecord(es: $0, en: $0 + " (en)") }, into: ctx)
        let byID = Deck.cardsByID(ctx)
        return es.map { byID[TextMatch.cardID($0)]! }
    }

    @Test func aMergedThemeHoldsBothAndItsWords() throws {
        let ctx = try store()
        let w = words(["el andén", "la maleta", "la llave", "la habitación", "harto"], ctx: ctx)
        let station = Chunks.create("Estación", ctx: ctx)
        let hotel = Chunks.create("Hotel", ctx: ctx)
        Chunks.file(Array(w[0...1]), in: station, ctx: ctx)
        Chunks.file(Array(w[2...3]), in: hotel, ctx: ctx)
        let trip = try #require(Chunks.merge(station, hotel, name: "Viaje", ctx: ctx))
        let all = Chunks.all(ctx)
        #expect(Chunks.top(all).map(\.name) == ["Viaje"])
        #expect(Set(Chunks.children(of: trip.id, in: all).map(\.name)) == ["Estación", "Hotel"])
        #expect(Chunks.words(in: trip.id, cards: w, chunks: all).count == 4)
        #expect(Chunks.words(in: hotel.id, cards: w, chunks: all).map(\.es).sorted() == ["la habitación", "la llave"])
        #expect(Chunks.loose(w, chunks: all).map(\.es) == ["harto"])
        #expect(Chunks.path(hotel, in: all) == "Viaje › Hotel")
        // Merged again, as many times as you like.
        let feelings = Chunks.create("Sentirse", ctx: ctx)
        Chunks.file([w[4]], in: feelings, ctx: ctx)
        let big = try #require(Chunks.merge(feelings, trip, name: "Mi vida", ctx: ctx))
        #expect(Chunks.words(in: big.id, cards: w, chunks: Chunks.all(ctx)).count == 5)
    }

    @Test func aThemeCantGoInsideItself() throws {
        let ctx = try store()
        let a = Chunks.create("A", ctx: ctx)
        let b = Chunks.create("B", ctx: ctx)
        #expect(Chunks.nest(b, in: a, ctx: ctx))
        #expect(!Chunks.nest(a, in: b, ctx: ctx))
        #expect(Chunks.merge(a, b, name: "C", ctx: ctx) == nil)
        Chunks.lift(b, ctx: ctx)
        #expect(b.parentID.isEmpty)
    }

    @Test func undoingAThemeMovesEverythingUpALevel() throws {
        let ctx = try store()
        let w = words(["uno", "dos", "tres"], ctx: ctx)
        let a = Chunks.create("A", ctx: ctx)
        let b = Chunks.create("B", ctx: ctx)
        Chunks.file([w[0]], in: a, ctx: ctx)
        Chunks.file([w[1]], in: b, ctx: ctx)
        let ab = try #require(Chunks.merge(a, b, name: "AB", ctx: ctx))
        Chunks.file([w[2]], in: ab, ctx: ctx)
        Chunks.dissolve(ab, ctx: ctx)
        let all = Chunks.all(ctx)
        #expect(Set(Chunks.top(all).map(\.name)) == ["A", "B"])
        #expect(Chunks.loose(w, chunks: all).map(\.es) == ["tres"])
        Chunks.dissolve(a, ctx: ctx)
        #expect(Set(Chunks.loose(w, chunks: Chunks.all(ctx)).map(\.es)) == ["uno", "tres"])
    }

    @Test func coloursGoRoundBeforeRepeating() throws {
        let ctx = try store()
        var colours: [Int] = []
        for i in 0..<Palette.chunkCount { colours.append(Chunks.create("\(i)", ctx: ctx).color) }
        #expect(Set(colours).count == Palette.chunkCount)
    }

    @Test func aReadingMakesItsThemeAndEveryWordKeepsItsSources() throws {
        let ctx = try store()
        let old = words(["la abuela"], ctx: ctx)[0]
        let home = Chunks.create("Familia", ctx: ctx)
        Chunks.file([old], in: home, ctx: ctx)

        let r = Reading(title: "En el mercado", lines: ["Voy al mercado con mi abuela. Ella conoce a todos."])
        ctx.insert(r)
        Lectura.save(r, new: [(CardRecord(es: "el mercado", en: "market"), "Voy al mercado con mi abuela.")],
                     existing: [(old, "Voy al mercado con mi abuela.")], ctx: ctx)
        let market = try #require(Deck.cardsByID(ctx)[TextMatch.cardID("el mercado")])
        let theme = try #require(Chunks.all(ctx).first { $0.readingID == r.id })
        #expect(theme.name == "En el mercado" && market.chunkID == theme.id)
        #expect(market.sourceList == [Source(title: "En el mercado", sentence: "Voy al mercado con mi abuela.")])
        // A word already in the deck stays in its theme and gains this reading.
        #expect(old.chunkID == home.id)
        #expect(old.sourceList.map(\.title) == ["En el mercado"])

        // A second reading: the same words gain a second source, and the first theme is reused for the first reading.
        let r2 = Reading(title: "La visita", lines: ["Mi abuela llega el lunes."])
        ctx.insert(r2)
        Lectura.save(r2, new: [], existing: [(old, "Mi abuela llega el lunes.")], ctx: ctx)
        #expect(old.sourceList.map(\.title) == ["En el mercado", "La visita"])
        #expect(Chunks.forReading(r, ctx: ctx) === theme)
    }

    @Test func aMarkedWordKeepsJustItsSentence() {
        let line = "Los sábados voy al mercado. Mi abuela conoce a todos los vendedores. Siempre compra más."
        let run = Run(line: 0, first: 11, last: 11, text: "vendedores")
        #expect(Lectura.sentence(of: run, in: line) == "Mi abuela conoce a todos los vendedores.")
    }
}

/// Expected values were taken from the design canvas's Mosaico.dc.html, run in Node: a word must draw the same
/// mosaic in the app as on the canvas, and the same on every device.
struct MosaicTests {
    @Test(arguments: [
        ("la maleta", 19, (0.0, 0.0, 128.70, 99.08), (43.0, 73.0, 84.5), 0.66),
        ("madrugar", 19, (0.0, 0.0, 132.60, 110.73), (264.0, 46.0, 53.3), 0.38),
        ("Viajes", 8, (0.0, 0.0, 120.90, 159.80), (151.0, 28.0, 83.8), 0.39),
    ])
    func matchesTheCanvas(word: String, count: Int, first: (Double, Double, Double, Double),
                          hsl: (Double, Double, Double), shadowX: Double) {
        let plan = MosaicPlan(word: word, aspect: 470.0 / 390)
        #expect(plan.pieces.count == count)
        let p = plan.pieces[0]
        let r = (p.rect.minX * 390, p.rect.minY * 390, p.rect.width * 390, p.rect.height * 390)
        #expect(abs(r.0 - first.0) < 0.01 && abs(r.1 - first.1) < 0.01 && abs(r.2 - first.2) < 0.01 && abs(r.3 - first.3) < 0.01)
        #expect(p.hsl.h == hsl.0 && p.hsl.s == hsl.1 && abs(p.hsl.l - hsl.2) < 0.001)
        #expect(abs(plan.shadow[2].x - shadowX) < 0.001)
    }

    @Test func caseAndSpacesDontChangeIt() {
        let a = MosaicPlan(word: "La Maleta ", aspect: 1.2), b = MosaicPlan(word: "la maleta", aspect: 1.2)
        #expect(a.pieces.map(\.rect) == b.pieces.map(\.rect))
    }
}
