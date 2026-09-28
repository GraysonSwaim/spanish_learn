# Cinco for iOS

On the App Store and the home screen it is **Choca Cinco** ("high five"): plain "Cinco" was taken.

The native version of Cinco: SwiftUI with SwiftData, syncing cards and progress through iCloud (CloudKit).
It follows the same rules as the web app: the same five stages, CSV format and card ids.
`../decks/starter.csv` is bundled straight from the repo.

```
Cinco/Model/Card.swift        Card and DayLog, the SwiftData models (CloudKit-safe: defaults, no unique, no relationships)
Cinco/Logic/Scheduler.swift   the five-stage schedule, pure functions
Cinco/Logic/StudySession.swift one sitting: queue, reveal steps, grading, undo
Cinco/Logic/TextMatch.swift   answer checking, and hash(strip()) ids that match the web app
Cinco/Logic/CSVImport.swift   deck parsing (same columns and aliases as the web app)
Cinco/Logic/Deck.swift        import, verb tables -> conj cards, merging iCloud duplicates
Cinco/Views/                  the screens
CincoTests/                   parity tests against values from the web app
```

## Run it

1. Open `Cinco.xcodeproj` in Xcode.
2. Target Cinco › Signing & Capabilities: pick your Team. Check that iCloud › CloudKit lists the container
   `iCloud.com.graysonswaim.cinco` (tap + to create it the first time) and that Push Notifications and
   Background Modes › Remote notifications are on.
3. Run on your iPhone. Sign into the same Apple Account on each device and they share one deck.

CloudKit needs a paid Apple Developer account. Without signing (or without an iCloud account) the app still
works, storing everything on the device only.

Before shipping to the App Store, deploy the CloudKit schema to Production in the CloudKit Console.

## Shortcuts and Siri

`Cinco/Logic/Intents.swift` gives the Shortcuts app four actions: **Añadir tarjetas** (JSON or CSV text; ``` fences
from a model are ignored), **Añadir una tarjeta** (Siri: "Add a card to Choca Cinco"; "Cinco" works too), **Palabras del mazo** (the deck's
Spanish, to tell a model what to skip) and **Tarjetas pendientes**.

Atajos on the home screen (`ShortcutsGuideView`, also in Ajustes) walks through a one-word shortcut, with no API key: Ask for Input →
Translate Text to Spanish and to English → Use Model (ChatGPT) with the prompt the screen copies → Añadir tarjetas.
The prompt asks for one JSON card (`CardJSON`): noun fields for a noun, all fifteen tables for a verb. Only
`spanish` and `english` are required, and an import never replaces a mnemonic the learner wrote. A word already in the deck (matched with or without its article) isn't
duplicated: the action lists what would change (`Deck.changes`) and asks before updating it.

## Development

Tests: `xcodebuild test -project Cinco.xcodeproj -scheme Cinco -destination 'platform=iOS Simulator,name=iPhone Air' CODE_SIGNING_ALLOWED=NO`

Debug builds take launch arguments for the simulator:

- `-importCSV <path>` loads a deck file from the Mac at launch.
- `-demo vocab|conj <steps> [stage]` opens a verb card at a stage and advances it that many reveal steps.
- `-openTenses` opens the Conjugación tense picker.
- `-studyNewest <n>` starts a session with the n most recently added word cards; `-studyCard <spanish>` with one card.

## Tabs

Vocabulario (words, verbs included, as word ↔ meaning), Conjugación (one card per verb tense) and Frases
(whole expressions). After an answer, «En una frase» shows the card's own example and sentences.
The starter deck (`decks/starter.csv`: 20 words, 10 of them verbs with their core tables, and
`decks/frases-inicio.csv`: 20 phrases) loads with one button on an empty deck. After that, cards come from Añadir,
the Shortcuts actions, or an import. An imported card goes to Frases when its `type` column is `phrase`, or when
the file is imported while the Frases tab is open.

## Not yet in the native app

Frase (fill-in-the-sentence) conjugation mode, importing a backup from the web app, CSV export.
