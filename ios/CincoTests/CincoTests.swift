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
        #expect(r.count > 50)
        #expect(r.allSatisfy { !$0.es.isEmpty && !$0.en.isEmpty })
    }

    /// Recording names are hash(strip(word)); the bundled index proves the ids line up.
    @Test func recordingsLineUpWithCardIDs() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../audio/es-MX")
        let index = try JSONDecoder().decode([String].self, from: Data(contentsOf: dir.appendingPathComponent("index.json")))
        let deck = CSVImport.parse(try String(contentsOf: dir.appendingPathComponent("../../decks/starter.csv"), encoding: .utf8))
        let found = deck.filter { index.contains(TextMatch.cardID(TextMatch.spokenText($0.es))) }
        #expect(found.count > deck.count / 2)
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

/// The bundled dictionary: lookups, articles, and the cards it makes.
@MainActor
struct LexiconTests {
    let lex = Lexicon.shared

    @Test func findsWordsByConjugatedFormAndByEnglish() {
        #expect(lex.isAvailable)
        #expect(lex.search("pidió").first?.word == "pedir")
        #expect(lex.search("manos").first?.word == "mano")
        #expect(lex.search("fue").map(\.word).contains("ser"))
        #expect(lex.search("fue").map(\.word).contains("ir"))
        #expect(lex.search("to ask").map(\.word).contains("pedir"))
    }

    @Test func nounsGetTheirArticle() throws {
        let mano = try #require(lex.entry("mano"))
        #expect(mano.spanish(for: mano.senses.first) == "la mano")
        let agua = try #require(lex.entry("agua"))
        #expect(agua.spanish(for: agua.senses.first) == "el agua")
        let libro = try #require(lex.entry("libro"))
        #expect(libro.spanish(for: libro.senses.first) == "el libro")
    }

    @Test func verbCardsCarryTheCheckedTables() throws {
        let pedir = try #require(lex.entry("pedir"))
        let r = pedir.record(senses: [pedir.senses[0]], tenses: LexEntry.coreTenses)
        #expect(r.es == "pedir")
        #expect(r.tenses.keys.sorted() == LexEntry.coreTenses.sorted())
        #expect(r.tenses["preterito"] == "pedí|pediste|pidió|pedimos|pedisteis|pidieron")
        #expect(r.tenses["subjuntivo"] == "pida|pidas|pida|pidamos|pidáis|pidan")
        #expect(pedir.tenses["perfecto"] == "he pedido|has pedido|ha pedido|hemos pedido|habéis pedido|han pedido")
        #expect(pedir.tenses["imperativo"] == "|pide|pida|pidamos|pedid|pidan")
        #expect(!r.frases.isEmpty)
    }

    /// The same forms as the hand-checked starter deck.
    @Test func matchesTheStarterDeck() throws {
        let url = try #require(Bundle.main.url(forResource: "starter", withExtension: "csv"))
        let recs = CSVImport.parse(try String(contentsOf: url, encoding: .utf8)).filter { !$0.tenses.isEmpty }
        #expect(recs.count >= 10)
        for rec in recs {
            let e = try #require(lex.entry(rec.es), "\(rec.es) missing")
            for (k, v) in rec.tenses where !v.isEmpty {
                let dict = e.tenses[k].map { $0.split(separator: "|", omittingEmptySubsequences: false).map { $0.split(separator: " / ").first.map(String.init) ?? "" } }
                let deck = v.split(separator: "|", omittingEmptySubsequences: false).map { $0.split(separator: " / ").first.map(String.init) ?? "" }
                #expect(dict == deck, "\(rec.es) \(k)")
            }
        }
    }
}

/// Adding dictionary words to a deck, the way the Diccionario screen does.
@MainActor
struct DictionaryAddTests {
    let lex = Lexicon.shared

    private func store() throws -> ModelContext {
        let schema = Schema([Card.self, DayLog.self])
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(c)
    }

    @Test func quickAddingSeveralWords() throws {
        let ctx = try store()
        for w in ["pedir", "mano", "chido"] {
            let e = try #require(lex.entry(w))
            #expect(Deck.save(e.record(senses: Array(e.senses.prefix(1)), tenses: LexEntry.coreTenses), editing: nil, ctx: ctx) == nil)
        }
        let cards = Deck.allCards(ctx)
        #expect(Set(cards.filter { !$0.isConj }.map(\.es)) == ["pedir", "la mano", "chido"])
        // pedir brings one Conjugación card per core tense.
        #expect(Set(cards.filter(\.isConj).map(\.tense)) == LexEntry.coreTenses)
        #expect(cards.first { $0.es == "la mano" }?.notes == "Plural: manos")
        // Adding a word twice is refused, not duplicated.
        let again = try #require(lex.entry("pedir"))
        #expect(Deck.save(again.record(senses: [again.senses[0]], tenses: []), editing: nil, ctx: ctx) != nil)
    }

    @Test func extraWordsAreSearchable() throws {
        #expect(lex.search("que onda").first?.word == "¿qué onda?")
        #expect(lex.search("güey").first?.word == "güey")
        let e = try #require(lex.entry("popote"))
        #expect(e.id > lex.common)
        #expect(e.spanish(for: e.senses.first) == "el popote")
        #expect(e.senses.first?.t == ["Mexico"])
    }
}

/// Frases: phrase cards live in their own tab, and come from a type column, the starter deck or the dictionary.
@MainActor
struct PhraseTests {
    private func store() throws -> ModelContext {
        let schema = Schema([Card.self, DayLog.self])
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(c)
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
        #expect(r.added >= 60)
        #expect(Deck.allCards(ctx).allSatisfy { $0.isPhrase })
    }

    @Test func dictionaryPhrasesGoToFrases() throws {
        let e = try #require(Lexicon.shared.entry("¿qué onda?"))
        #expect(e.record(senses: Array(e.senses.prefix(1)), tenses: []).phrase)
        let w = try #require(Lexicon.shared.entry("perro"))
        #expect(!w.record(senses: Array(w.senses.prefix(1)), tenses: []).phrase)
    }

    @Test func dictionaryHasSentencesAndOrigins() throws {
        let e = try #require(Lexicon.shared.entry("hacer"))
        #expect(!e.sentences.isEmpty)
        #expect(e.origin.contains("Latin"))
    }
}
