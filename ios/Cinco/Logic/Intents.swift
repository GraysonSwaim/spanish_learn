import AppIntents
import SwiftData

// Siri and Shortcuts actions: adding one word, and how many cards are due. Cards otherwise come from Añadir
// and Lecturas.

/// One word, for a quick "add *la maleta*, suitcase" from Siri.
struct AddCardIntent: AppIntent {
    static let title: LocalizedStringResource = "Añadir una tarjeta"
    static let description = IntentDescription("Adds one word or phrase to the deck.")

    @Parameter(title: "Español", requestValueDialog: "¿En español?") var es: String
    @Parameter(title: "Inglés", requestValueDialog: "¿Y en inglés?") var en: String
    @Parameter(title: "Ejemplo") var ex: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Añadir \(\.$es) (\(\.$en))") { \.$ex }
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let rec = CardRecord(es: es.trimmingCharacters(in: .whitespaces), en: en.trimmingCharacters(in: .whitespaces),
                             ex: ex ?? "")
        if let clash = Deck.save(rec, editing: nil, ctx: Store.container.mainContext) {
            return .result(dialog: "\(clash)")
        }
        return .result(dialog: "Añadida: \(rec.es).")
    }
}

/// How many reviews are waiting, across both tabs.
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
    }
}
