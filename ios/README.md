# Cinco for iOS

The native version of Cinco: SwiftUI with SwiftData, syncing cards and progress through iCloud (CloudKit).
It follows the same rules as the web app: the same five stages, CSV format and card ids. The Mac
recordings in `../audio/es-MX` and `../decks/starter.csv` are bundled straight from the repo.

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

`Cinco/Logic/Intents.swift` gives the Shortcuts app five actions: **Añadir palabra** (a word in Spanish or English,
filled in from the dictionary like Diccionario's quick add; Siri: "Add a word to Cinco"), **Añadir tarjetas** (JSON
or CSV text; ``` fences from a model are ignored), **Añadir una tarjeta**, **Palabras del mazo** (the deck's Spanish,
to tell a model what to skip) and **Tarjetas pendientes**.

Ajustes › Atajos y Siri (`ShortcutsGuideView`) walks through a one-word shortcut, with no API key: Ask for Input →
Translate Text to Spanish and to English → Use Model (ChatGPT) with the prompt the screen copies → Añadir tarjetas.
The prompt asks for one JSON card (`CardJSON`): noun fields for a noun, all fifteen tables for a verb. Only
`spanish` and `english` are required; a verb Cinco's dictionary knows keeps the dictionary's tables, and an import
never replaces a mnemonic the learner wrote. A word already in the deck (matched with or without its article) isn't
duplicated: the action lists what would change (`Deck.changes`) and asks before updating it.

## Development

Tests: `xcodebuild test -project Cinco.xcodeproj -scheme Cinco -destination 'platform=iOS Simulator,name=iPhone Air' CODE_SIGNING_ALLOWED=NO`

Debug builds take launch arguments for the simulator:

- `-importCSV <path>` loads a deck file from the Mac at launch.
- `-demo vocab|conj <steps> [stage]` opens a verb card at a stage and advances it that many reveal steps.
- `-lookup <query>` opens the dictionary with that search; `-entry <word>` opens one word's page.
- `-openTenses` opens the Conjugación tense picker.
- `-studyNewest <n>` starts a session with the n most recently added word cards; `-studyCard <spanish>` with one card.

## Tabs

Vocabulario (words, verbs included, as word ↔ meaning), Conjugación (one card per verb tense) and Frases
(whole expressions). After an answer, «En una frase» shows the word in example sentences and «Origen» where it
comes from, both from the dictionary. Frases can be loaded from `decks/frases-inicio.csv`, added by hand, or
imported: a `type` column set to `phrase`, or any file imported while the Frases tab is open.

## Dictionary

Diccionario (on the home screen) looks up the 10,000 most common Spanish words, including by conjugated form
(pidió finds pedir) or English meaning, and adds one to the deck with its conjugation tables.
Its data is `Cinco/Resources/dictionary.sqlite`, built by `scripts/build_dictionary.py` from Wiktionary,
Fred Jehle's verb database and verbecc, with word frequency from OpenSubtitles and example sentences from Tatoeba. Conjugated forms are kept only
where two of the three sources agree; `scripts/dictionary_report.md` lists the rest. To rebuild:

    python3 -m venv /tmp/dict-venv && /tmp/dict-venv/bin/pip install verbecc
    /tmp/dict-venv/bin/python scripts/build_dictionary.py        # downloads ~1 GB to ~/Library/Caches the first time

To add words beyond the common 10,000 (slang, regional words, phrases), list them in
`scripts/dictionary_extra.csv` and rebuild; its header explains the columns. Words it doesn't have can still be
written by hand from the Diccionario screen.

Jehle's data is licensed for non-commercial use only; replace it before selling the app.

## Not yet in the native app

Frase (fill-in-the-sentence) conjugation mode, importing a backup from the web app, CSV export.
