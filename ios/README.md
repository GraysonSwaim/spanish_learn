# Cinco for iOS

On the App Store and the home screen it is **Choca Cinco** ("high five"): plain "Cinco" was taken.

SwiftUI with SwiftData, syncing cards and progress through iCloud (CloudKit).

```
Cinco/Model/Card.swift        Card and DayLog, the SwiftData models (CloudKit-safe: defaults, no unique, no relationships)
Cinco/Model/Chunk.swift       Chunk, a theme: words point at it by chunkID, merged chunks at their parent by parentID
Cinco/Logic/Chunks.swift      reading and changing the theme tree: words in a theme, merging, nesting, undoing
Cinco/Logic/Scheduler.swift   the five-stage schedule, pure functions
Cinco/Logic/StudySession.swift one sitting: queue, reveal steps, grading, undo
Cinco/Logic/TextMatch.swift   answer checking, and the hash(strip()) card ids
Cinco/Logic/CardRecord.swift  a card as it comes in, and CardJSON (the sample deck)
Cinco/Logic/Deck.swift        adding cards, verb tables -> conj cards, merging iCloud duplicates
Cinco/Model/Reading.swift     Reading, a pasted text for Lecturas (same CloudKit rules)
Cinco/Logic/Lectura.swift     lines, words and marked runs of a reading; recycling old readings
Cinco/Logic/Tutor.swift       Claude through the proxy in ../proxy: drafting cards, example sentences
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

- `-loadSample` loads the sample deck (`samples/deck.json`, read from the repo, not shipped) into an empty store, for the flags here;
  with `-sampleThemes` most of it is filed into themes, two of them merged.
- `-open sueltas` opens Agrupar; `-open <theme name>` opens that theme.
- `-demo vocab|conj <steps> [stage]` opens a verb card at a stage and advances it that many reveal steps.
- `-tutorDemo` gives Lecturas canned answers instead of Claude; `-tutorURL http://localhost:8787` uses a proxy running on the Mac.
- `-studyNewest <n>` starts a session with the n most recently added word cards; `-studyCard <spanish>` with one card.

## Home

How many words there are, the loose ones (Sueltas › Agrupar), and the themes on top (`Chunks.top`) as cards; one
holding smaller themes shows them stacked behind it. Tap a theme to study it (one with themes inside opens instead,
with «Todo junto» at the top); drag one onto another to merge them or put one inside the other; press and hold to
rename, take it out, or undo it. Each theme is studied as its own pipeline (`StudyAction`, owned by RootView, picks a
session left midway back up by its key). Verbs' tables are studied by tense from the Conjugación chips below.

Words and phrases are one kind of card; a card is a verb only because it has tables. After an answer, «Dónde la
leíste» lists every reading the word was marked in, with its sentence, and «Más frases» a verb's own sentences.

## Lecturas

Home › Lecturas: paste a Spanish text and it's split into one line per sentence. It's the main way words get in. Tap
the words you don't know, or hold and slide across a phrase, to mark them (each shows roughly what it means, from
Apple's translation on the phone); words already in the deck are underlined with dots. **Tarjetas** turns the marked
words into cards: Claude drafts the dictionary form, the meaning in that sentence and a note, and the sentence becomes
the example. A word already in the deck is brought forward for review instead.

New words from a reading are filed in the reading's theme (`Chunks.forReading`), and each word keeps the reading's
title and its own sentence (`Lectura.sentence`, cut from the paragraph) in `Card.sources`, which outlive the reading.

Readings not opened for 30 days are deleted.

**From a link** (Nueva lectura › Desde un enlace, or paste a link with Pegar): `ArticleReader` loads the page in an
offscreen `WKWebView`, so sites that turn away a plain download still answer, and runs `Resources/ArticleExtract.js`
in it. That script returns two candidates: the page's own JSON-LD `articleBody`, and the paragraphs Mozilla's
Readability (`Resources/Readability.js` 0.6.0, Firefox's Reader View) finds once figures, asides and screen-reader-only
text are removed. `ArticleText.choose` takes the metadata when it's the whole article in paragraphs, else
Readability's text, and drops common news labels (PUBLICIDAD, Fuente de la imagen…). No model is involved, so a page
always gives the same text. It lands in the editor to trim before Empezar; a page that won't load or holds under 200
characters asks for a copy and paste instead.

Claude is reached through the Cloudflare Worker in `../proxy`, which holds the API key; the app asks once before
sending anything. Without Claude (declined, offline, out for the day), Apple's on-device model takes a smaller job: it
gives a marked word's meaning in its sentence, keeping the words as marked.

