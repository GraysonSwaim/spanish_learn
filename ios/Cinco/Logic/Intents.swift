import AppIntents
import SwiftData

// Shortcuts and Siri actions. The main use is a shortcut that asks a model (Shortcuts' "Use Model" action,
// on-device or ChatGPT) for cards as CSV and hands the answer to "Añadir tarjetas".

/// Takes a deck as text: the same CSV the Importar screen reads, with or without a header.
struct AddCardsIntent: AppIntent {
    static let title: LocalizedStringResource = "Añadir tarjetas"
    static let description = IntentDescription(
        "Adds cards from CSV text: spanish,english[,example,notes,tags], one card per line. A header row is optional, and cards already in the deck are updated without losing their progress.")

    @Parameter(title: "CSV", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Tags", description: "Added to cards that don't have tags of their own.")
    var tags: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Añadir tarjetas de \(\.$text)") { \.$tags }
    }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        var recs = CSVImport.parse(Self.unfence(text))
        if let tags, !tags.isEmpty {
            for i in recs.indices where recs[i].tags.isEmpty { recs[i].tags = tags }
        }
        guard recs.contains(where: { !$0.es.isEmpty && !$0.en.isEmpty }) else {
            throw $text.needsValueError("No encontré tarjetas. Cada línea necesita español y inglés, separados por coma.")
        }
        let r = Deck.importRecords(recs, into: Store.container.mainContext)
        return .result(value: r.summary, dialog: "\(r.summary)")
    }

    /// Models like to wrap CSV in ``` fences; drop those lines.
    static func unfence(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .joined(separator: "\n")
    }
}

/// A word in Spanish or English, filled in from the dictionary the way Diccionario's quick add does it:
/// article, meaning, example, notes, and for a verb the six core conjugation tables.
struct AddWordIntent: AppIntent {
    static let title: LocalizedStringResource = "Añadir palabra"
    static let description = IntentDescription(
        "Looks up a word in Spanish or English in Cinco's dictionary and adds it as a card, with its meaning, an example and, for verbs, conjugation tables.")

    @Parameter(title: "Palabra", requestValueDialog: "¿Qué palabra? (What word?)")
    var word: String

    @Parameter(title: "Idioma", default: .auto)
    var language: IntentLanguage

    static var parameterSummary: some ParameterSummary {
        Summary("Añadir \(\.$word)") { \.$language }
    }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let (entry, sense) = Lexicon.shared.find(word, in: language.value) else {
            return .result(value: "", dialog: "«\(word)» no está en el diccionario. Usa «Añadir una tarjeta» para escribirla a mano.")
        }
        let rec = entry.record(senses: sense.map { [$0] } ?? [], tenses: LexEntry.coreTenses)
        if let clash = Deck.save(rec, editing: nil, ctx: Store.container.mainContext) {
            return .result(value: rec.es, dialog: "\(clash)")
        }
        let tab = rec.phrase ? "Frases" : entry.isVerb ? "Vocabulario, con sus tablas en Conjugación" : "Vocabulario"
        return .result(value: rec.es, dialog: "Añadida: \(rec.es), \(rec.en). La verás en \(tab).")
    }
}

enum IntentLanguage: String, AppEnum {
    case auto, spanish, english

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Idioma"
    static let caseDisplayRepresentations: [IntentLanguage: DisplayRepresentation] = [
        .auto: "Detectar", .spanish: "Español", .english: "Inglés",
    ]

    var value: WordLanguage {
        switch self {
        case .auto: .auto
        case .spanish: .spanish
        case .english: .english
        }
    }
}

/// One word, for a quick "add *la maleta*, suitcase" from Siri.
struct AddCardIntent: AppIntent {
    static let title: LocalizedStringResource = "Añadir una tarjeta"
    static let description = IntentDescription("Adds one word or phrase to the deck.")

    @Parameter(title: "Español") var es: String
    @Parameter(title: "Inglés") var en: String
    @Parameter(title: "Ejemplo") var ex: String?
    @Parameter(title: "Frase", description: "Study it in Frases rather than Vocabulario.", default: false)
    var phrase: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Añadir \(\.$es) (\(\.$en))") { \.$ex; \.$phrase }
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let rec = CardRecord(es: es.trimmingCharacters(in: .whitespaces), en: en.trimmingCharacters(in: .whitespaces),
                             ex: ex ?? "", phrase: phrase)
        if let clash = Deck.save(rec, editing: nil, ctx: Store.container.mainContext) {
            return .result(dialog: "\(clash)")
        }
        return .result(dialog: "Añadida: \(rec.es).")
    }
}

/// The deck's Spanish, so a shortcut can tell a model which words to leave out.
struct ListWordsIntent: AppIntent {
    static let title: LocalizedStringResource = "Palabras del mazo"
    static let description = IntentDescription("Returns the Spanish of every word and phrase card, one per item.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let words = Deck.allCards(Store.container.mainContext).filter { !$0.isConj && !$0.isDropped }.map(\.es)
        return .result(value: words)
    }
}

/// How many reviews are waiting, across all three tabs.
struct CardsDueIntent: AppIntent {
    static let title: LocalizedStringResource = "Tarjetas pendientes"
    static let description = IntentDescription("Returns how many cards are due for review now.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let n = Scheduler.counts(Deck.allCards(Store.container.mainContext)).due
        return .result(value: n, dialog: n == 0 ? "Nada pendiente. ¡Bien hecho!" : "Tienes \(n) \(n == 1 ? "tarjeta pendiente" : "tarjetas pendientes").")
    }
}

/// Siri phrases, and the actions shown under Cinco in the Shortcuts app without any setup.
struct CincoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CardsDueIntent(), phrases: [
            "How many cards are due in \(.applicationName)",
            "¿Cuántas tarjetas tengo en \(.applicationName)?",
        ], shortTitle: "Pendientes", systemImageName: "clock")
        AppShortcut(intent: AddWordIntent(), phrases: [
            "Add a word to \(.applicationName)",
            "Add a card to \(.applicationName)",
            "Añadir una palabra a \(.applicationName)",
            "Añadir una tarjeta a \(.applicationName)",
        ], shortTitle: "Añadir palabra", systemImageName: "plus.rectangle.on.rectangle")
        AppShortcut(intent: AddCardsIntent(), phrases: [
            "Add cards to \(.applicationName)",
            "Añadir tarjetas a \(.applicationName)",
        ], shortTitle: "Añadir tarjetas", systemImageName: "rectangle.stack.badge.plus")
    }
}
