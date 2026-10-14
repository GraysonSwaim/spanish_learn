import Testing
import Foundation
import SwiftData
@testable import Cinco

/// Expected values come from running the web app's own functions in node, so the two apps stay in step.
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

struct CSVTests {
    @Test func headerAndQuotes() {
        let csv = """
        spanish,english,example,tags,presente
        "hola, amigo",hello,"Dijo ""hola"".",saludos,
        tener,to have,,verbs,tengo|tienes|tiene|tenemos|tenéis|tienen
        # a comment
        """
        let r = CSVImport.parse(csv)
        #expect(r.count == 2)
        #expect(r[0].es == "hola, amigo")
        #expect(r[0].ex == "Dijo \"hola\".")
        #expect(r[0].tags == "saludos")
        #expect(r[1].tenses["presente"] == "tengo|tienes|tiene|tenemos|tenéis|tienen")
    }

    @Test func headerlessSemicolons() {
        let r = CSVImport.parse("gato;cat;El gato duerme.\nperro;dog\n")
        #expect(r.map(\.es) == ["gato", "perro"])
        #expect(r[0].ex == "El gato duerme.")
    }

    @Test func starterDeckParses() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../decks/starter.csv")
        let r = CSVImport.parse(try String(contentsOf: url, encoding: .utf8))
        #expect(r.count == 20)
        #expect(r.allSatisfy { !$0.es.isEmpty && !$0.en.isEmpty })
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

    @Test func passClimbsAndSpacesOut() {
        let now = Date()
        let c = card(1)
        Scheduler.pass(c, now: now)
        #expect(c.stage == 2 && c.interval == 1)
        #expect(c.due == Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)))
        c.stage = 5; c.interval = 21
        Scheduler.pass(c, now: now)
        #expect(c.stage == 5 && c.interval == 42)
        c.interval = 100
        Scheduler.pass(c, now: now)
        #expect(c.interval == Scheduler.maxInterval)
    }

    @Test func failDropsOneStageNotBelowOne() {
        let c = card(3)
        Scheduler.fail(c)
        #expect(c.stage == 2 && c.lapses == 1 && c.interval == 0)
        let d = card(1)
        Scheduler.fail(d)
        #expect(d.stage == 1)
    }

    @Test func reviewsComeBeforeNewCards() {
        let now = Date()
        let fresh = card(0)
        let late = card(2, due: now.addingTimeInterval(-3600))
        let later = card(3, due: now.addingTimeInterval(-7200))
        let future = card(4, due: now.addingTimeInterval(86400))
        let q = Scheduler.dailyQueue([fresh, late, later, future], newRoom: 5, staggerTenses: false, verbs: [], now: now)
        #expect(q.map(\.id) == [later.id, late.id, fresh.id])
    }

    @Test func newRoomCapsNewCards() {
        let q = Scheduler.dailyQueue((0..<10).map { _ in card(0) }, newRoom: 3, staggerTenses: false, verbs: [])
        #expect(q.count == 3)
    }
}

/// Frases: phrase cards live in their own tab, and come from a type column or the starter deck.
@MainActor
struct PhraseTests {
    private func store() throws -> ModelContext {
        let schema = Schema([Card.self, DayLog.self])
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(c)
    }

    @Test func rowsSortThemselves() throws {
        let csv = "spanish,english,type,presente\n¿Dónde está el baño?,Where is the bathroom?,,\nno hay de qué,you're welcome,,\nla conferencia de prensa,press conference,,\nhablar,to speak,,hablo|hablas|habla|hablamos|habláis|hablan\nel gato,cat,word,\n"
        let recs = CSVImport.parse(csv)
        #expect(recs.map(\.phrase) == [true, true, false, false, false])
        let ctx = try store()
        Deck.importRecords([CardRecord(es: "no hay de qué", en: "old")], into: ctx)
        Deck.importRecords(recs, into: ctx)
        #expect(Deck.allCards(ctx).first { $0.es == "no hay de qué" }?.isPhrase == false)
    }

    @Test func typeColumnMakesPhrases() throws {
        let recs = CSVImport.parse("spanish,english,type\n¿Qué tal?,How's it going?,phrase\nel gato,cat,\n")
        #expect(recs.map(\.phrase) == [true, false])
        let ctx = try store()
        Deck.importRecords(recs, into: ctx)
        let cards = Deck.allCards(ctx)
        #expect(cards.filter { Scheduler.inTab($0, tab: .phrases, tense: "presente") }.map(\.es) == ["¿Qué tal?"])
        #expect(cards.filter { Scheduler.inTab($0, tab: .vocab, tense: "presente") }.map(\.es) == ["el gato"])
    }

    @Test func starterPhrasesLoad() throws {
        let ctx = try store()
        let r = try #require(Deck.loadStarter(ctx, deck: "frases-inicio"))
        #expect(r.added == 20)
        #expect(Deck.allCards(ctx).allSatisfy { $0.isPhrase })
    }

    /// Twenty words, ten of them verbs with their six core tables for Conjugación.
    @Test func starterWordsLoad() throws {
        let ctx = try store()
        let r = try #require(Deck.loadStarter(ctx))
        #expect(r.added == 20)
        #expect(r.verbs == 10)
        let conj = Deck.allCards(ctx).filter(\.isConj)
        #expect(conj.count == 60)
    }

}

struct IntentTests {
    /// What a model typically hands back to "Añadir tarjetas".
    @Test func fencedModelOutput() {
        let reply = "```csv\nspanish,english,example\nla maleta,suitcase,Mi maleta es azul.\nel vuelo,flight,\n```"
        let recs = CSVImport.parse(AddCardsIntent.unfence(reply))
        #expect(recs.map(\.es) == ["la maleta", "el vuelo"])
        #expect(recs[0].ex == "Mi maleta es azul.")
    }
}

/// The cards a session remembers missing (a mnemonic is asked for on the first miss), and the mnemonic an edit keeps.
@MainActor
struct MnemonicTests {
    private func store() throws -> ModelContext {
        let schema = Schema([Card.self, DayLog.self])
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
        s.undo()
        s.undo()
        #expect(s.missed.map(\.es) == ["uno"])
        answer(true)                        // uno right this time; it's still a card that was missed
        #expect(s.missed.map(\.es) == ["uno"])
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

/// The JSON a model sends to Añadir tarjetas.
@MainActor
struct CardJSONTests {
    private func store() throws -> ModelContext {
        let schema = Schema([Card.self, DayLog.self])
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

    /// A phrase exactly as ChatGPT sent it from the shortcut.
    @Test func aPhraseFromChatGPT() throws {
        let r = try #require(CardJSON.parse("""
            {"type": "phrase", "spanish": "¡Qué meningitis!", "english": "No way! / You're kidding!", "example": "—Me ganaste la lotería. —¡Qué meningitis!",
            "notes": "Casual (tú), México.", "mnemonic": "Think of meningitis as a wild surprise that shocks you.", "tags": "slang, surprise"}
            """)?.first)
        #expect(r.phrase)
        #expect(r.es == "¡Qué meningitis!" && r.en == "No way! / You're kidding!")
        #expect(r.ex == "—Me ganaste la lotería. —¡Qué meningitis!")
        #expect(r.mnemonic.hasPrefix("Think of meningitis"))
        #expect(r.tags == "slang surprise")
    }

    @Test func aVerbInFencesWithEveryTense() throws {
        let text = AddCardsIntent.unfence("""
            ```json
            {"spanish": "bailar", "english": "to dance", "tenses": {
              "presente": ["bailo", "bailas", "baila", "bailamos", "bailáis", "bailan"],
              "imperativo_negativo": ["", "no bailes", "no baile", "no bailemos", "no bailéis", "no bailen"],
              "subj_imperfecto": "bailara / bailase|bailaras / bailases|bailara / bailase|bailáramos / bailásemos|bailarais / bailaseis|bailaran / bailasen",
              "made_up": ["x"]}}
            ```
            """)
        let r = try #require(CardJSON.parse(text)?.first)
        #expect(r.es == "bailar")
        #expect(Set(r.tenses.keys) == ["presente", "imperativo_negativo", "subj_imperfecto"])
        #expect(r.tenses["imperativo_negativo"] == "|no bailes|no baile|no bailemos|no bailéis|no bailen")
    }

    @Test func aListAndCSVStillWorks() throws {
        #expect(CardJSON.parse(#"[{"es": "uno", "en": "one"}, {"es": "dos", "en": "two"}]"#)?.map(\.es) == ["uno", "dos"])
        #expect(CardJSON.parse("spanish,english\nuno,one") == nil)
        #expect(CSVImport.parse("spanish,english,mnemonic\nuno,one,one → uno").first?.mnemonic == "one → uno")
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
        let schema = Schema([Card.self, DayLog.self])
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

    @Test func aGlossMakesTheCardAndTheSentenceIsItsExample() {
        let run = Run(line: 0, first: 1, last: 3, text: "echo de menos")
        let gloss = Tutor.Gloss(spanish: "echar de menos", english: "to miss (someone)", phrase: false, note: "echo: presente, yo")
        let rec = Lectura.record(run, gloss: gloss, sentence: "Te echo de menos.")
        #expect(rec.es == "echar de menos" && rec.en == "to miss (someone)" && rec.ex == "Te echo de menos.")
        #expect(rec.notes == "echo: presente, yo" && rec.tags == "lectura" && !rec.phrase)
        // Without a gloss: the words as written, no meaning yet.
        let plain = Lectura.record(run, gloss: nil, sentence: "Te echo de menos.")
        #expect(plain.es == "echo de menos" && plain.en.isEmpty)
    }

    @Test @MainActor func oldReadingsAreRecycled() throws {
        let schema = Schema([Card.self, DayLog.self, Reading.self])
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
