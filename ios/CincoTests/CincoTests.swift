import Testing
import Foundation
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
