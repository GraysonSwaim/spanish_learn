import Testing
import Foundation
import SwiftData
import UIKit
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

    /// 24, 48 and 96 hours, a week, then twice as long each time it's right once the wait is up. Early reviews don't stretch it.
    @Test func dominadaClimbsTheLadder() {
        let now = Date()
        let day = { (n: Int) in Calendar.current.date(byAdding: .day, value: n, to: now)! }
        let c = card(4)
        Scheduler.pass(c, in: [c], cap: 5, now: now)
        #expect(c.stage == 5 && c.interval == 1 && c.due == day(1))
        Scheduler.pass(c, in: [c], cap: 5, now: now)
        #expect(c.interval == 1 && c.due == day(1))
        var gaps = [c.interval]
        for _ in 0..<6 {
            Scheduler.pass(c, in: [c], cap: 5, now: c.due)
            gaps.append(c.interval)
        }
        #expect(gaps == [1, 2, 4, 7, 14, 28, 56])
    }

    /// The same time tomorrow needn't be to the minute.
    @Test func aCardIsDueAFewHoursEarly() {
        let now = Date()
        let c = card(5, due: now)
        c.interval = 1
        c.lastReviewed = now.addingTimeInterval(-86_400)
        c.due = now
        #expect(Scheduler.isDue(c, now: now.addingTimeInterval(-3.9 * 3600)))
        #expect(!Scheduler.isDue(c, now: now.addingTimeInterval(-4.1 * 3600)))
        Scheduler.pass(c, in: [c], cap: 5, now: now.addingTimeInterval(-3.9 * 3600))
        #expect(c.interval == 2)
    }

    /// Tapped while reading, it's due now. Right, it hasn't lost its place, and it hasn't earned a longer wait either.
    @Test func aTappedWordGotRightKeepsItsWait() {
        let now = Date()
        let c = card(5)
        c.interval = 56
        c.lastReviewed = now.addingTimeInterval(-3 * 86_400)
        c.due = now
        Scheduler.pass(c, in: [c], cap: 5, now: now)
        #expect(c.stage == 5 && c.interval == 56)
        #expect(c.due == Calendar.current.date(byAdding: .day, value: 56, to: now)!)
    }

    /// And if its wait was up anyway, it goes on.
    @Test func aTappedWordThatHadWaitedGoesOn() {
        let now = Date()
        let c = card(5)
        c.interval = 14
        c.lastReviewed = now.addingTimeInterval(-20 * 86_400)
        c.due = now
        Scheduler.pass(c, in: [c], cap: 5, now: now)
        #expect(c.interval == 28)
    }

    /// A miss moves that card alone.
    @Test func aMissLeavesOtherCardsWhereTheyAre() {
        let now = Date()
        let due = now.addingTimeInterval(86_400)
        let others = [card(5, due: due), card(5, due: due), card(3), card(4)]
        others[0].interval = 56
        others[1].interval = 1
        let missed = card(5, due: now)
        missed.interval = 28
        Scheduler.fail(missed, in: others + [missed], cap: 5, now: now)
        #expect(missed.stage == 4 && missed.interval == 0)
        #expect(stages(others) == [5, 5, 3, 4])
        #expect(others[0].interval == 56 && others[1].interval == 1 && others[0].due == due && others[1].due == due)
        #expect(others.allSatisfy { $0.lapses == 0 })
    }

    /// Mastered again after a miss, it starts over.
    @Test func aMissStartsTheLadderAgain() {
        let now = Date()
        let c = card(5, due: now)
        c.interval = 28
        Scheduler.fail(c, in: [c], cap: 5, now: now)
        Scheduler.pass(c, in: [c], cap: 5, now: now)
        #expect(c.stage == 5 && c.interval == 1)
    }

    @Test func alreadyKnownIsCheckedInAWeekAndGoesOnFromThere() {
        let now = Date()
        let c = card(0)
        Scheduler.alreadyKnown(c, now: now)
        #expect(c.stage == 5 && c.interval == 7)
        Scheduler.pass(c, in: [c], cap: 5, now: c.due)
        #expect(c.interval == 14)
    }

    @Test func theLatestForItsWaitComesFirst() {
        let now = Date()
        let threeDaysAgo = now.addingTimeInterval(-3 * 86_400)
        let long = card(5, due: threeDaysAgo.addingTimeInterval(-3600))
        long.interval = 56
        let short = card(5, due: threeDaysAgo)
        short.interval = 1
        #expect(Scheduler.dailyQueue([long, short], now: now).map(\.id) == [short.id, long.id])
    }

    /// Those from before the ladder come through a few a day. One never tested after a wait starts at 24 hours; one that's
    /// earned a longer wait keeps it, if it's right.
    @Test func oldCardsAreFedThroughSlowly() {
        let now = Date()
        let before = now.addingTimeInterval(-86_400)
        let old = { (interval: Int, offset: Double) -> Card in
            let c = self.card(5, due: now.addingTimeInterval(offset))
            c.interval = interval
            c.lastReviewed = before.addingTimeInterval(-86_400)
            return c
        }
        let crammed = (0..<3).map { old(7, Double($0) * 3600) }
        let earned = old(28, 10 * 86_400)
        let said = old(30, 20 * 86_400)
        let recent = card(5, due: now.addingTimeInterval(86_400))
        recent.interval = 7
        recent.lastReviewed = now
        let dropped = old(7, 0)
        dropped.dropped = now
        let dueLater = recent.due
        Scheduler.feedThrough(crammed + [earned, said, recent, dropped], perDay: 2, before: before, now: now)
        let day = { (n: Int) in Calendar.current.date(byAdding: .day, value: n, to: now)! }
        #expect(crammed.map(\.due) == [day(0), day(0), day(1)])
        #expect(crammed.allSatisfy { $0.interval == 1 })
        #expect(earned.due == day(1) && said.due == day(2))
        #expect(recent.interval == 7 && recent.due == dueLater && dropped.interval == 7)
        Scheduler.pass(earned, in: [earned], cap: 5, now: earned.due)
        #expect(earned.interval == 28)
        Scheduler.pass(crammed[0], in: [crammed[0]], cap: 5, now: crammed[0].due)
        #expect(crammed[0].interval == 2)
    }

    /// One a day for a week, none for a day with nothing waiting.
    @Test func theReminderSaysHowManyWillBeWaiting() {
        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let at8 = 20 * 60
        let tonight = cal.date(bySettingHour: 20, minute: 0, second: 0, of: morning)!
        #expect(Reminder.plan([], minutes: at8, now: morning).isEmpty)
        let a = card(5, due: morning.addingTimeInterval(3600))
        let b = card(5, due: cal.date(byAdding: .day, value: 2, to: tonight)!)
        let p = Reminder.plan([a, b], minutes: at8, now: morning)
        #expect(p.count == 7 && p.first?.date == tonight)
        #expect(p.map(\.count) == [1, 1, 2, 2, 2, 2, 2])
        // Past today's time, it starts tomorrow.
        let night = cal.date(bySettingHour: 21, minute: 0, second: 0, of: morning)!
        #expect(Reminder.plan([a], minutes: at8, now: night).first?.date == cal.date(byAdding: .day, value: 1, to: tonight))
        #expect(Reminder.plan([card(0)], minutes: at8, now: morning).isEmpty)
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
        ctx.insert(Chunk(name: "Tema", color: 0, order: 0))
        _ = Deck.today(ctx)
        try ctx.save()
        Deck.eraseAll(ctx)
        #expect(Deck.allCards(ctx).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<DayLog>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Reading>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Chunk>()).isEmpty)
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

    @Test func thePagePaintsEachTappedWordInItsColour() {
        let text = "Hoy el frutero nos ha regalado unas naranjas porque mi abuela le echa de menos."
        let lines = ["Otra cosa.", text]
        // "frutero" (2) is new; "naranjas" (7) is in the library; "echa de menos" (12-14) isn't settled.
        let p = Lectura.paint(text, lines: lines, marks: ["1.2-2", "1.7-7", "1.12-14"], colors: ["1.2-2": .new, "1.7-7": .seen])
        let ns = text as NSString
        let shown = { (c: MarkColor) in (p[c] ?? []).map { ns.substring(with: NSRange(location: $0[0], length: $0[1] - $0[0])) } }
        #expect(shown(.new) == ["frutero"] && shown(.seen) == ["naranjas"] && shown(.pending) == ["echa de menos"])
        // A paragraph that isn't a line has no marks.
        #expect(Lectura.paint("El frutero.", lines: lines, marks: ["1.2-2"], colors: [:]).isEmpty)
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

/// Scanning a page of a book: printed lines back into paragraphs, and what becomes of them.
struct PageScanTests {
    /// A line of a page, by its place: rows go down from the top, one row every 0.035 of the page.
    private func line(_ text: String, row: Double, indent: Double = 0, end: Double = 0.86) -> ScannedLine {
        ScannedLine(text: text, minX: 0.09 + indent, maxX: end, midY: 0.9 - row * 0.035, height: 0.025)
    }

    /// As Vision read a rendered page of a book, boxes rounded.
    private var page: [ScannedLine] {
        [line("CAPÍTULO TRES", row: 0, indent: 0.22, end: 0.55),
         line("Aquella mañana, cuando el coronel abrió la ventana, le", row: 2, indent: 0.05),
         line("pareció que el pueblo entero se había quedado dormido bajo", row: 3),
         line("el peso de la lluvia. ¿Quién iba a pensar que tanta desdi-", row: 4),
         line("cha cabría en una sola semana?", row: 5, end: 0.5),
         line("Bajó las escaleras sin hacer ruido.", row: 6, indent: 0.05, end: 0.56),
         line("—¿Adónde vas tan temprano? —le preguntó su mujer, sin", row: 7, indent: 0.05),
         line("—levantar la vista.", row: 8, end: 0.4),
         line("—A ninguna parte.", row: 9, indent: 0.05, end: 0.4),
         line("47", row: 11, indent: 0.27, end: 0.4)]
    }

    @Test func linesBecomeParagraphs() {
        let got = PageText.assemble(page)
        #expect(got.paragraphs == [
            "Aquella mañana, cuando el coronel abrió la ventana, le pareció que el pueblo entero se había quedado dormido bajo el peso de la lluvia. ¿Quién iba a pensar que tanta desdicha cabría en una sola semana?",
            "Bajó las escaleras sin hacer ruido.",
            "—¿Adónde vas tan temprano? —le preguntó su mujer, sin —levantar la vista.",
            "—A ninguna parte.",
        ])
    }

    @Test func thePageNumberAndRunningHeadAreNotText() {
        let got = PageText.assemble(page)
        #expect(got.number == 47)
        #expect(!got.paragraphs.joined().contains("CAPÍTULO"))
        // A number printed in the running head is found too.
        var head = page.dropLast().map { $0 }
        head[0].text = "47  CAPÍTULO TRES"
        #expect(PageText.assemble(head).number == 47)
    }

    @Test func piecesOfOneRowAreOneLine() {
        let got = PageText.assemble([
            ScannedLine(text: "dos piezas", minX: 0.5, maxX: 0.8, midY: 0.5, height: 0.03),
            ScannedLine(text: "Una línea en", minX: 0.1, maxX: 0.45, midY: 0.502, height: 0.03),
        ])
        #expect(got.paragraphs == ["Una línea en dos piezas"])
    }

    @Test func aParagraphRunsOverThePage() {
        let pages = [ScannedPage(paragraphs: ["Fin de una idea.", "Y luego otra desdi-"], number: 1),
                     ScannedPage(paragraphs: ["cha enorme.", "Otra."], number: 2),
                     ScannedPage(paragraphs: ["Nueva página."], number: 3)]
        #expect(PageText.joined(pages) == ["Fin de una idea.", "Y luego otra desdicha enorme.", "Otra.", "Nueva página."])
        #expect(PageText.label([47]) == "pág. 47")
        #expect(PageText.label([47, 48, 49]) == "págs. 47–49")
        #expect(PageText.label([]) == nil)
    }

    @Test @MainActor func aPageStays() throws {
        let schema = Schema([Card.self, DayLog.self, Reading.self, Chunk.self])
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = c.mainContext
        let old = Reading(title: "Mi libro · pág. 47", lines: ["Hola."])
        old.book = "Mi libro"
        #expect(old.book == "Mi libro" && old.url == "libro:Mi libro")
        old.opened = .now.addingTimeInterval(-90 * 86_400)
        ctx.insert(old)
        Lectura.recycle(ctx)
        #expect(try ctx.fetch(FetchDescriptor<Reading>()).count == 1)
    }

    @Test func aLongScanGoesInStretches() {
        let long = String(repeating: "a", count: 3000)
        #expect(Tutor.batches([long, long, "corta"]).map(\.count) == [1, 2])
        #expect(Tutor.batches(["corta"]).count == 1)
        #expect(Tutor.batches([String(repeating: "b", count: 9000)])[0][0].count == 6000)
    }

    /// The real recognizer on a drawn page.
    @Test func visionReadsAPageIntoParagraphs() {
        let size = CGSize(width: 800, height: 1000)
        let text = ["Aquella mañana, cuando el coronel abrió la ventana, le",
                    "pareció que el pueblo entero se había quedado dormido.",
                    "—¿Adónde vas tan temprano? —le preguntó su mujer."]
        let image = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 2; return f }()).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont(name: "TimesNewRomanPSMT", size: 25)!, .foregroundColor: UIColor.black]
            for (i, l) in text.enumerated() {
                (l as NSString).draw(at: CGPoint(x: i == 1 ? 70 : 110, y: 100 + CGFloat(i) * 38), withAttributes: attrs)
            }
        }
        let lines = PageScan.recognize(image)
        #expect(PageText.assemble(lines).paragraphs == [
            "Aquella mañana, cuando el coronel abrió la ventana, le pareció que el pueblo entero se había quedado dormido.",
            "—¿Adónde vas tan temprano? —le preguntó su mujer.",
        ])
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

/// The one library: each word once, foundational words first, fed by pages and by taps.
@MainActor
struct LibraryTests {
    /// Held for the test: a context doesn't keep its container alive.
    private let container: ModelContainer

    init() throws {
        let schema = Schema([Card.self, DayLog.self, Reading.self, Chunk.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func store() throws -> ModelContext { container.mainContext }

    private func add(_ es: String, level: Int? = nil, ctx: ModelContext) -> Card {
        Deck.importRecords([CardRecord(es: es, en: "x")], into: ctx)
        let c = Deck.cardsByID(ctx)[TextMatch.cardID(es)]!
        c.level = level
        return c
    }

    private func page(_ lines: [String], words: [PageWord], ctx: ModelContext) -> Reading {
        let r = Reading(title: "Mi libro · pág. 47", lines: lines)
        r.book = "Mi libro"
        r.pageWords = words
        ctx.insert(r)
        return r
    }

    @Test func theLevelLivesAmongTheTags() throws {
        let ctx = try store()
        let c = add("la mano", ctx: ctx)
        c.tags = "lectura"
        #expect(c.level == nil)
        c.level = 3
        #expect(c.level == 3 && c.tags == "lectura nivel3" && c.visibleTags == ["lectura"])
        c.level = 1
        #expect(c.level == 1 && c.tags == "lectura nivel1")
    }

    @Test func aWordIsFoundWithOrWithoutItsArticleAndByItsAlternatives() throws {
        let ctx = try store()
        let mano = add("la mano", ctx: ctx), coche = add("el coche / el carro", ctx: ctx)
        let index = Library.index(Deck.allCards(ctx))
        #expect(Library.find("mano", in: index) === mano)
        #expect(Library.find("LA MANO", in: index) === mano)
        #expect(Library.find("el carro", in: index) === coche)
        #expect(Library.find("tener", in: index) == nil)
    }

    @Test func aPagesNewWordsGoFoundationalFirstAndSkipTheLibrary() throws {
        let ctx = try store()
        _ = add("la mano", ctx: ctx)
        let discarded = add("el perro", ctx: ctx)
        discarded.dropped = .now
        let words = [PageWord(spanish: "la desdicha", level: 3, forms: ["desdicha"]), PageWord(spanish: "mano", level: 1, forms: ["mano"]),
                     PageWord(spanish: "el perro", level: 1, forms: ["perro"]), PageWord(spanish: "pensar", level: 2, forms: ["pensó"]),
                     PageWord(spanish: "de", level: 1, forms: ["de"]), PageWord(spanish: "que", level: 1, forms: ["que"])]
        let new = Library.newWords(words, index: Library.index(Deck.allCards(ctx)))
        #expect(new.map(\.spanish) == ["de", "que", "pensar", "la desdicha"])
    }

    @Test func aWordsPlaceIsItsFormAndItsSentence() {
        let w = PageWord(spanish: "echar de menos", level: 3, forms: ["Echó de menos"])
        let place = Library.place(of: w, in: ["Otra cosa.", "Llovía. Echó de menos a su hermano. Y lloró."])
        #expect(place.form == "Echó de menos" && place.sentence == "Echó de menos a su hermano.")
    }

    @Test func scansThatComeBackInStretchesAreOneList() {
        let merged = PageWord.merged([[PageWord(spanish: "tener", level: 1, forms: ["tengo"])],
                                      [PageWord(spanish: "la mano", level: 1, forms: ["mano"]), PageWord(spanish: "tener", level: 1, forms: ["tiene", "tengo"])]])
        #expect(merged.map(\.spanish) == ["tener", "la mano"])
        #expect(merged[0].forms == ["tengo", "tiene"])
    }

    @Test func studyPutsThePageFirstThenFoundationalWords() throws {
        let ctx = try store()
        let hard = add("la desdicha", level: 3, ctx: ctx), middle = add("el paraguas", level: 2, ctx: ctx)
        let basic = add("de", level: 1, ctx: ctx), unjudged = add("la leña", ctx: ctx)
        let working = add("la mano", level: 1, ctx: ctx), onPage = add("el pie", level: 3, ctx: ctx)
        working.stage = 2; onPage.stage = 2
        let all = Deck.allCards(ctx)
        #expect(Library.plan(all).fresh.map(\.es) == [basic.es, middle.es, unjudged.es, hard.es])
        let plan = Library.plan(all, first: [hard.id, onPage.id])
        #expect(plan.fresh.first === hard)
        #expect(plan.queue.first === onPage)
    }

    /// Past the limit new words wait, and say so, but the words of the page about to be read still come.
    @Test func newWordsWaitWhileTooManyReviewsDo() throws {
        let ctx = try store()
        let onPage = add("la desdicha", level: 1, ctx: ctx), other = add("el paraguas", level: 1, ctx: ctx)
        var reviews: [Card] = []
        for i in 0...Scheduler.reviewsFirst {
            let c = add("palabra\(i)", level: 1, ctx: ctx)
            (c.stage, c.interval, c.due) = (5, 1, .distantPast)
            reviews.append(c)
        }
        let over = Library.plan(Deck.allCards(ctx), first: [onPage.id])
        #expect(over.fresh.map(\.id) == [onPage.id] && over.held == 1)
        #expect(Library.plan(Deck.allCards(ctx)).fresh.isEmpty)
        reviews[0].due = .distantFuture
        let under = Library.plan(Deck.allCards(ctx))
        #expect(under.fresh.count == 2 && under.held == 0 && under.fresh.contains { $0 === other })
    }

    @Test func aNewWordCanBeAlreadyKnown() throws {
        let ctx = try store()
        let known = add("de", level: 1, ctx: ctx), other = add("que", level: 1, ctx: ctx)
        let plan = Library.plan(Deck.allCards(ctx))
        let s = StudySession(queue: plan.queue, tab: .vocab, pool: plan.pool, fresh: plan.fresh, continuous: true, ctx: ctx)
        #expect(s.current === known && s.mode == .intro)
        s.alreadyKnown()
        #expect(known.stage == 5 && known.interval == Scheduler.knownInterval && !Scheduler.isDue(known))
        #expect(s.current === other)
        // Saying it isn't known starts its training instead.
        s.introDone()
        #expect(other.stage == 1)
        // And it can be taken back.
        s.undo(); s.undo()
        #expect(known.stage == 0 && other.stage == 0)
    }

    @Test func aTappedWordInTheLibraryStaysOneCardAndComesBack() async throws {
        let ctx = try store()
        let tener = add("tener", ctx: ctx)
        tener.stage = 5
        tener.due = .now.addingTimeInterval(30 * 86_400)
        let r = page(["Tengo un perro."], words: [PageWord(spanish: "tener", level: 1, forms: ["Tengo"])], ctx: ctx)
        Lectura.mark(&r.marks, line: 0, first: 0, last: 0)
        #expect(r.markColors["0.0-0"] == .pending)

        // Its form is on the page's list, so this needs no call to Claude.
        let run = try #require(Library.unresolved(r).first)
        try await Library.record(run, in: r, ctx: ctx)

        #expect(r.markColors["0.0-0"] == .seen)
        #expect(Library.unresolved(r).isEmpty)
        #expect(Deck.allCards(ctx).count == 1)
        #expect(Scheduler.isDue(tener))
        #expect(tener.sourceList.map(\.title) == ["Mi libro · pág. 47"])
        // Taking the tap back leaves the card alone.
        Library.forget(run, in: r, ctx: ctx)
        #expect(Deck.allCards(ctx).count == 1 && r.glosses.isEmpty && !r.carded.contains(run.id))
    }

    @Test func aTappedWordNewToTheLibraryIsAddedAndCanBeTakenBack() async throws {
        let ctx = try store()
        let r = page(["Una desdicha enorme."], words: [PageWord(spanish: "la desdicha", level: 3, forms: ["desdicha"])], ctx: ctx)
        Lectura.mark(&r.marks, line: 0, first: 1, last: 1)
        let run = try #require(Library.unresolved(r).first)
        // As if Claude had already answered: no network in tests.
        r.glosses = [run.id: Tutor.Gloss(spanish: "la desdicha", english: "misfortune", note: "")]
        try await Library.record(run, in: r, ctx: ctx)

        #expect(r.markColors[run.id] == .new)
        let c = try #require(Library.find("desdicha", in: Library.index(Deck.allCards(ctx))))
        #expect(c.es == "la desdicha" && c.level == 3 && c.ex == "Una desdicha enorme." && c.exWord == "desdicha")
        #expect(Library.cards(on: r, in: Deck.allCards(ctx)).map(\.es) == ["la desdicha"])
        Library.forget(run, in: r, ctx: ctx)
        #expect(Deck.allCards(ctx).isEmpty)
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

/// A card's word and its meaning must come from the same answer about the same word.
struct CardWordTests {
    private func gloss(_ es: String) -> Tutor.Gloss { Tutor.Gloss(spanish: es, english: "x", note: "") }

    @MainActor @Test func anAnswerAboutTheSameWordIsKept() {
        #expect(Library.cardWord("oler", from: gloss("oler")) == "oler")
        #expect(Library.cardWord("papel", from: gloss("el papel")) == "el papel")
        #expect(Library.cardWord("el sillón", from: gloss("Sillon")) == "Sillon")
    }

    /// The bugs that made oler "paper": the list said one word, the answer was about another, and the two were paired.
    @MainActor @Test(arguments: [("oler", "el papel"), ("el papel", "oler"), ("se", "quedarse"), ("quedarse", "quedarse dormido"),
                                 ("pensar", "ir a pensar"), ("hacer", "sin hacer"), ("año", "ano")])
    func anAnswerAboutAnotherWordIsRefused(word: String, answer: String) {
        #expect(Library.cardWord(word, from: gloss(answer)) == nil)
    }
}

struct MeaningCheckTests {
    @Test(arguments: [
        ("to smell (of)", ["to smell"]),
        ("to smell", ["paper", "It smells of coffee."]),
        ("to carry out", ["carried out"]),
        ("barely; with great difficulty", ["with difficulty"]),
        ("to miss (someone)", ["She missed her brother."]),
        ("tear", ["the tears"]),
    ])
    func meaningsThatMatch(meaning: String, translations: [String]) {
        #expect(MeaningCheck.agrees(meaning: meaning, with: translations))
    }

    @Test(arguments: [
        ("paper", ["to smell", "smelled", "The kitchen smelled of coffee."]),
        ("to smell", ["the paper", "There was a folded sheet on the table."]),
        // Only filler in common.
        ("to be in", ["to the"]),
        ("role", []),
    ])
    func meaningsThatDoNot(meaning: String, translations: [String]) {
        #expect(!MeaningCheck.agrees(meaning: meaning, with: translations))
    }

    /// Only a match on the word itself counts: the sentence holds the words around it too.
    @Test func aMeaningFromElsewhereInTheSentenceIsDoubtful() {
        let sentence = "The paper smells like tobacco."
        #expect(MeaningCheck.settled(meaning: "paper", word: ["to smell", "smells"], sentence: sentence) == .doubtful)
        #expect(MeaningCheck.settled(meaning: "to smell", word: ["to smell", "smells"], sentence: sentence) == .agrees)
        #expect(MeaningCheck.settled(meaning: "to smell", word: ["the paper", "paper"], sentence: sentence) == .doubtful)
    }

    /// A word's other sense: Apple's word isn't in the sentence, so this is left to the model.
    @Test func anotherSenseIsLeftOpen() {
        #expect(MeaningCheck.settled(meaning: "role", word: ["the paper"], sentence: "He played a sad role.") == nil)
        #expect(MeaningCheck.settled(meaning: "wrist", word: ["the doll"], sentence: "The wrist broke.") == nil)
    }

    @Test func whatTheModelLeavesOpen() {
        let v = { MeaningCheck.unsettled(meaning: "role", word: $0, sentence: $1, modelAccepts: $2) }
        #expect(v(["the paper"], "He played a sad role.", true) == .modelAccepts)
        #expect(v(["the paper"], "He played a sad role.", false) == .doubtful)
        #expect(v(["the paper"], "He played a sad role.", nil) == .agrees)
        #expect(v(["the paper"], "It was sad.", nil) == .doubtful)
        #expect(v([], "", true) == .modelAccepts)
        #expect(v([], "", false) == .doubtful)
        #expect(v([], "", nil) == .noOpinion)
    }

    @Test func applesWordAsACardWouldPutIt() {
        #expect(MeaningCheck.candidate("the paper", of: "el papel") == "paper")
        #expect(MeaningCheck.candidate("The  doll ", of: "la muñeca") == "doll")
        #expect(MeaningCheck.candidate("to smell", of: "oler") == "to smell")
        // It only gave the word back: no answer at all.
        #expect(MeaningCheck.candidate("zaguán", of: "el zaguán").isEmpty)
    }
}

@MainActor
struct MeaningReviewTests {
    private func card(_ id: String, en: String = "paper", kind: Card.Kind = .word) -> Card {
        Card(id: id, kind: kind, es: id, en: en, order: 0)
    }

    @Test func onlyWordsWhoseCurrentMeaningIsUncheckedAreChecked() {
        let new = card("nueva"), same = card("igual"), changed = card("cambiada", en: "role")
        let dropped = card("descartada"), conj = card("verbo:presente", kind: .conj)
        dropped.dropped = .now
        let entries = ["igual": MeaningReview.Entry(en: "paper", doubtful: false),
                       "cambiada": MeaningReview.Entry(en: "paper", doubtful: true)]
        #expect(MeaningReview.toCheck([new, same, changed, dropped, conj], entries: entries).map(\.id) == ["nueva", "cambiada"])
    }

    @Test func aDoubtOnlyHoldsForTheMeaningThatWasChecked() {
        let doubted = card("dudosa"), fine = card("bien"), changed = card("cambiada", en: "role"), new = card("nueva")
        let entries = ["dudosa": MeaningReview.Entry(en: "paper", doubtful: true),
                       "bien": MeaningReview.Entry(en: "paper", doubtful: false),
                       "cambiada": MeaningReview.Entry(en: "paper", doubtful: true)]
        #expect(MeaningReview.doubtful([doubted, fine, changed, new], entries: entries).map(\.id) == ["dudosa"])
    }

    @Test func eachTextIsAskedForOnce() {
        let c = Card(id: "x", es: "el papel", en: "paper", order: 0)
        c.exWord = "papel"
        c.ex = " Un papel doblado. "
        #expect(MeaningReview.texts(of: c) == ["el papel", "papel", "Un papel doblado."])
        c.exWord = "EL PAPEL"
        c.ex = ""
        #expect(MeaningReview.texts(of: c) == ["el papel"])
    }

    @Test func aMatchOnTheWordAgreesWithoutAskingTheModel() async {
        let c = Card(id: "x", es: "oler", en: "to smell", order: 0)
        #expect(await MeaningReview.verdict(for: c, english: ["oler": "to smell"]) == .agrees)
    }

    @Test func aMeaningFromTheSameSentenceIsDoubted() async {
        let c = Card(id: "x", es: "oler", en: "paper", order: 0)
        c.exWord = "huele"
        c.ex = "El papel huele a tabaco."
        let english = ["oler": "to smell", "huele": "smells", "El papel huele a tabaco.": "The paper smells like tobacco."]
        #expect(await MeaningReview.verdict(for: c, english: english) == .doubtful)
    }
}

struct AddWordTests {
    private func gloss(_ es: String) -> Tutor.Gloss { Tutor.Gloss(spanish: es, english: "from Claude", note: "") }

    @Test(arguments: [("cafe", "el café"), ("muneca", "la muñeca"), ("ano", "el año"), ("Mesa", "la mesa"), ("tener", "tener")])
    func claudeCorrectsHowItsWritten(typed: String, answer: String) {
        #expect(Library.corrected(typed, by: gloss(answer)) == answer)
    }

    @Test func claudeCantSwapTheWordForAnother() {
        #expect(Library.corrected("olía", by: gloss("oler")) == "olía")
    }

    @MainActor @Test func withoutClaudeItsSavedAsTypedAndOnlyOnce() async throws {
        let schema = Schema([Card.self, DayLog.self, Reading.self, Chunk.self])
        let ctx = ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)))

        guard case .new(let c) = await Library.addWord(es: "el papel", en: "paper", claude: false, ctx: ctx) else {
            Issue.record("not added")
            return
        }
        #expect(c.es == "el papel" && c.en == "paper" && c.ex.isEmpty && c.stage == 0)
        // The same word without its article is the same word.
        guard case .already(let same) = await Library.addWord(es: "papel", en: "role", claude: false, ctx: ctx) else {
            Issue.record("added twice")
            return
        }
        #expect(same === c && c.en == "paper")
        #expect(Deck.allCards(ctx).count == 1)
    }
}

struct KnownWordsTests {
    /// The words of a line that `spans` found, as written there.
    private func found(_ known: KnownWords, _ line: String, page: [PageWord] = [], lemmas: [String?]? = nil) -> [String] {
        let ws = Lectura.words(line)
        return known.spans(in: line, page: page, lemmas: lemmas).map { String(line[ws[$0.lowerBound].lowerBound..<ws[$0.upperBound].upperBound]) }
    }

    /// No lemmas, as on a phone without them.
    private func plain(_ line: String) -> [String?] { Lectura.words(line).map { _ in nil } }

    @Test func aWordIsFoundWithoutItsArticleAndWithoutAccents() {
        let known = KnownWords([("el papel", ""), ("el café", "")])
        let line = "El papel y el cafe."
        #expect(found(known, line, lemmas: plain(line)) == ["papel", "cafe"])
    }

    @Test func aFormIsFoundByItsLemma() {
        let line = "El papel huele a tabaco"
        let lemmas: [String?] = ["el", "papel", "oler", "a", "tabaco"]
        #expect(found(KnownWords([("oler", "")]), line, lemmas: lemmas) == ["huele"])
        #expect(found(KnownWords([("oler", "")]), line, lemmas: plain(line)) == [])
    }

    @Test func theFormItWasMetInCountsWithoutLemmas() {
        let line = "El papel huele a tabaco"
        #expect(found(KnownWords([("oler", "huele")]), line, lemmas: plain(line)) == ["huele"])
    }

    @Test func aPhraseIsFoundAsOneAndInItsForms() {
        let known = KnownWords([("echar de menos", "")])
        let line = "Mi abuela le echa de menos hoy"
        let lemmas: [String?] = ["mi", "abuela", "usted", "echar", "de", "menos", "hoy"]
        #expect(found(known, line, lemmas: lemmas) == ["echa de menos"])
        // Punctuation between its words makes it something else.
        let cut = "Lo echa, de menos"
        #expect(found(known, cut, lemmas: ["lo", "echar", "de", "menos"]) == [])
    }

    @Test func aLongerPhraseWinsOverAWordInIt() {
        let known = KnownWords([("la casa", ""), ("casa de campo", "")])
        let line = "Una casa de campo"
        #expect(found(known, line, lemmas: plain(line)) == ["casa de campo"])
    }

    @Test func aReflexiveVerbIsFoundWithoutItsPronoun() {
        let line = "Se sentía cansada"
        #expect(found(KnownWords([("sentirse", "")]), line, lemmas: ["usted", "sentir", "cansado"]) == ["sentía"])
        // Words that only end like one aren't cut down.
        #expect(found(KnownWords([("la clase", "")]), "Cla", lemmas: [nil]) == [])
    }

    @Test func pronounsDontPassForTheirLemmasButArticlesDo() {
        let line = "Se fue a la casa"
        let lemmas: [String?] = ["usted", "ir", "a", "el", "casa"]
        #expect(found(KnownWords([("usted", "")]), line, lemmas: lemmas) == [])
        #expect(found(KnownWords([("el", "")]), line, lemmas: lemmas) == ["la"])
    }

    @Test func aScannedPagesListDecidesWhichWordAFormIs() {
        let line = "Como la sopa"
        let page = [PageWord(spanish: "como", level: 1, forms: ["Como"]), PageWord(spanish: "la sopa", level: 1, forms: ["sopa"]),
                    PageWord(spanish: "el", level: 1, forms: ["la"])]
        let lemmas: [String?] = ["comer", "el", "sopa"]
        // Apple says comer, the page says como, which isn't known.
        #expect(found(KnownWords([("comer", "")]), line, page: page, lemmas: lemmas) == [])
        // And "la" is el here, which is.
        #expect(found(KnownWords([("el", "")]), line, page: page, lemmas: lemmas) == ["la"])
    }

    @Test func wordsNextToEachOtherStaySeparate() {
        let line = "mi casa vieja"
        #expect(found(KnownWords([("la casa", ""), ("viejo", "vieja")]), line, lemmas: plain(line)) == ["casa", "vieja"])
    }

    @Test func thePageIsToldWhereInUTF16() {
        let text = "Ayer 🙂 el niño compró papel."
        let ns = text as NSString
        let shown = KnownWords([("el papel", ""), ("el niño", "")]).stretches(in: text)
            .map { ns.substring(with: NSRange(location: $0[0], length: $0[1] - $0[0])) }
        #expect(shown == ["niño", "papel"])
    }

    @Test func noWordsFindNothing() {
        #expect(found(KnownWords([]), "El papel", lemmas: [nil, nil]) == [])
    }

    @Test @MainActor func onlyWhatsBeenStudiedCounts() throws {
        let schema = Schema([Card.self, DayLog.self, Reading.self, Chunk.self])
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = c.mainContext
        let make = { (es: String, stage: Int) -> Card in
            let card = Card(id: TextMatch.cardID(es), es: es, en: "x", order: 0)
            card.stage = stage
            ctx.insert(card)
            return card
        }
        let cards = [make("nuevo", 0), make("estudiado", 1), make("dominado", 5), make("descartado", 3)]
        cards[3].dropped = .now
        let verb = make("tenido", 3)
        verb.kind = .conj
        let line = "nuevo estudiado dominado descartado tenido"
        #expect(found(Library.known(cards + [verb]), line, lemmas: plain(line)) == ["estudiado", "dominado"])
    }
}
