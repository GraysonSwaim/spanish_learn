import AppIntents
import SwiftData

// Shortcuts and Siri actions. The main use is a shortcut that asks a model (Shortcuts' "Use Model" action,
// on-device or ChatGPT) for a card as JSON and hands the answer to "Añadir tarjetas". Atajos in Ajustes
// (ShortcutsGuideView) walks through building it and copies the prompt.

/// Takes cards as text: JSON (CardJSON), or the same CSV the Importar screen reads, with or without a header.
struct AddCardsIntent: AppIntent {
    static let title: LocalizedStringResource = "Añadir tarjetas"
    static let description = IntentDescription(
        "Adds cards from JSON or CSV text. JSON: {\"spanish\", \"english\", \"example\", \"notes\", \"tags\", \"type\", \"mnemonic\", \"frases\", \"tenses\": {\"presente\": [six forms], …}}, one object or a list. CSV: spanish,english[,example,notes,tags], one card per line. Only spanish and english are required; cards already in the deck are updated without losing their progress.")

    @Parameter(title: "Texto", description: "JSON or CSV.", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Tags", description: "Added to cards that don't have tags of their own.")
    var tags: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Añadir tarjetas de \(\.$text)") { \.$tags }
    }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let body = Self.unfence(text)
        var recs = CardJSON.parse(body) ?? CSVImport.parse(body)
        if let tags, !tags.isEmpty {
            for i in recs.indices where recs[i].tags.isEmpty { recs[i].tags = tags }
        }
        guard recs.contains(where: { !$0.es.isEmpty && !$0.en.isEmpty }) else {
            throw $text.needsValueError("No encontré tarjetas. Cada línea necesita español y inglés, separados por coma.")
        }
        recs = recs.filter { !$0.es.isEmpty && !$0.en.isEmpty }
        let ctx = Store.container.mainContext
        let cards = Deck.allCards(ctx)
        // New words go straight in; words already in the deck are only changed once the learner agrees.
        var fresh: [CardRecord] = [], updates: [(rec: CardRecord, card: Card, changes: [String])] = [], same: [String] = []
        for var rec in recs {
            guard let c = Deck.existing(rec, in: cards) else { fresh.append(rec); continue }
            rec.es = c.es
            let ch = Deck.changes(rec, to: c)
            if ch.isEmpty { same.append(c.es) } else { updates.append((rec, c, ch)) }
        }
        var lines: [String] = []
        if !fresh.isEmpty {
            let r = Deck.importRecords(fresh, into: ctx)
            if fresh.count == 1, let c = fresh.first {
                let tables = c.tenses.count
                lines.append("Añadida en \(c.phrase ? "Frases" : "Vocabulario"): \(c.es), \(c.en)."
                    + (tables > 0 ? " Con \(tables) \(tables == 1 ? "tiempo" : "tiempos") en Conjugación." : ""))
            } else {
                let p = fresh.filter(\.phrase).count
                lines.append("Añadidas: \(r.added)" + (p == 0 ? " en Vocabulario." : p == fresh.count ? " en Frases." : " (\(p) en Frases)."))
            }
        }
        if !updates.isEmpty {
            let ask = updates.count == 1
                ? "«\(updates[0].card.es)» ya está en tus tarjetas. Traigo: \(updates[0].changes.joined(separator: "; ")). ¿La actualizo?"
                : "\(updates.count) ya están en tus tarjetas y traen algo nuevo: "
                    + updates.map { "\($0.card.es) (\($0.changes.joined(separator: ", ")))" }.joined(separator: "; ") + ". ¿Las actualizo?"
            do {
                try await requestConfirmation(actionName: .set, dialog: IntentDialog(stringLiteral: ask))
                Deck.importRecords(updates.map(\.rec), into: ctx)
                lines.append(updates.count == 1 ? "Actualizada: \(updates[0].card.es)." : "Actualizadas: \(updates.count).")
            } catch {
                // Declining leaves those cards as they were; anything new above is already in.
                guard lines.isEmpty else { lines.append("Las que ya tenías, sin cambios."); return Self.done(lines) }
                throw error
            }
        }
        if !same.isEmpty {
            lines.append(same.count == 1 ? "«\(same[0])» ya está en tus tarjetas, sin nada nuevo." : "\(same.count) ya estaban, sin nada nuevo.")
        }
        return Self.done(lines)
    }

    private static func done(_ lines: [String]) -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let msg = lines.joined(separator: " ")
        return .result(value: msg, dialog: "\(msg)")
    }

    /// Models like to wrap CSV in ``` fences; drop those lines.
    static func unfence(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .joined(separator: "\n")
    }
}

/// One word, for a quick "add *la maleta*, suitcase" from Siri.
struct AddCardIntent: AppIntent {
    static let title: LocalizedStringResource = "Añadir una tarjeta"
    static let description = IntentDescription("Adds one word or phrase to the deck.")

    @Parameter(title: "Español", requestValueDialog: "¿En español?") var es: String
    @Parameter(title: "Inglés", requestValueDialog: "¿Y en inglés?") var en: String
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
        AppShortcut(intent: AddCardIntent(), phrases: [
            "Add a word to \(.applicationName)",
            "Add a card to \(.applicationName)",
            "Añadir una palabra a \(.applicationName)",
            "Añadir una tarjeta a \(.applicationName)",
        ], shortTitle: "Añadir una tarjeta", systemImageName: "plus.rectangle.on.rectangle")
        AppShortcut(intent: AddCardsIntent(), phrases: [
            "Add cards to \(.applicationName)",
            "Añadir tarjetas a \(.applicationName)",
        ], shortTitle: "Añadir tarjetas", systemImageName: "rectangle.stack.badge.plus")
    }
}
