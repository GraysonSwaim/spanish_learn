# Cinco for iOS

On the App Store and the home screen it is **Choca Cinco** ("high five"): plain "Cinco" was taken.

SwiftUI with SwiftData, syncing cards and progress through iCloud (CloudKit).

```
Cinco/Model/Card.swift        Card and DayLog, the SwiftData models (CloudKit-safe: defaults, no unique, no relationships)
Cinco/Logic/Scheduler.swift   the five-stage schedule, pure functions
Cinco/Logic/StudySession.swift one sitting: queue, reveal steps, grading, undo
Cinco/Logic/TextMatch.swift   answer checking, and the hash(strip()) card ids
Cinco/Logic/CardRecord.swift  a card as it comes in, and CardJSON (the sample deck)
Cinco/Logic/Deck.swift        adding cards, verb tables -> conj cards, merging iCloud duplicates
Cinco/Model/Reading.swift     Reading, a pasted text for Lecturas (same CloudKit rules)
Cinco/Logic/Lectura.swift     lines, words and marked runs of a reading; recycling old readings
Cinco/Logic/Tutor.swift       Claude through the proxy in ../proxy: checking translations, drafting cards
Cinco/Views/                  the screens
CincoTests/                   tests
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

## Where cards come from

Only two places: **Añadir** (one word or phrase, typed in; Siri's "Add a card to Choca Cinco" does the same) and
**Lecturas** (words marked while reading). There is no bundled deck and no bulk import. `Cinco/Logic/Intents.swift`
also gives Shortcuts **Tarjetas pendientes**.

## Development

Tests: `xcodebuild test -project Cinco.xcodeproj -scheme 'Choca Cinco' -destination 'platform=iOS Simulator,name=iPhone Air' CODE_SIGNING_ALLOWED=NO`

Debug builds take launch arguments for the simulator:

- `-loadSample` loads the sample deck (`samples/deck.json`, read from the repo, not shipped) into an empty store, for the flags here.
- `-demo vocab|conj <steps> [stage]` opens a verb card at a stage and advances it that many reveal steps.
- `-openTenses` opens the Conjugación tense picker.
- `-tutorDemo` gives Lecturas canned answers instead of Claude; `-tutorURL http://localhost:8787` uses a proxy running on the Mac.
- `-studyNewest <n>` starts a session with the n most recently added word cards; `-studyCard <spanish>` with one card.

## Tabs

Vocabulario (every word and phrase, verbs included, as Spanish ↔ meaning) and Conjugación (one card per verb tense).
There is no separate kind for phrases: a card is a verb only because it has tables. After an answer, «En una frase»
shows the card's own example and sentences.

## Lecturas

Home › Lecturas: paste a Spanish text and it's split into one line per sentence. Tap the words you don't know (neighbours
join into one phrase) and write your English under each line; words already in the deck are underlined with dots.
**Revisar** sends the reading to Claude, which grades each line (Bien, Casi, No del todo), says what went wrong, lists
words you seem to have missed (a tap marks them) and adds a few notes on the text. **Inglés → español** is Al revés: write
the Spanish back from the English, then compare with the original. **Tarjetas** turns the marked words into cards:
Claude drafts the dictionary form, the meaning in that sentence and a note, and the sentence becomes the example. A word
already in the deck is brought forward for review instead. Readings not opened for 30 days are deleted.

**From a link** (Nueva lectura › Desde un enlace, or paste a link with Pegar): `ArticleReader` loads the page in an
offscreen `WKWebView`, so sites that turn away a plain download still answer, and runs `Resources/ArticleExtract.js`
in it. That script returns two candidates: the page's own JSON-LD `articleBody`, and the paragraphs Mozilla's
Readability (`Resources/Readability.js` 0.6.0, Firefox's Reader View) finds once figures, asides and screen-reader-only
text are removed. `ArticleText.choose` takes the metadata when it's the whole article in paragraphs, else
Readability's text, and drops common news labels (PUBLICIDAD, Fuente de la imagen…). No model is involved, so a page
always gives the same text. It lands in the editor to trim before Empezar; a page that won't load or holds under 200
characters asks for a copy and paste instead.

Claude is reached through the Cloudflare Worker in `../proxy`, which holds the API key; the app asks once before
sending anything. Without Claude (declined, offline, out for the day), Apple's on-device model takes a smaller job, since
in testing it graded translations badly: it translates each line for you to compare with, and gives a marked word's
meaning in its sentence. Al revés without Claude shows the original to compare with yourself.

