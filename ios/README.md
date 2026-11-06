# Cinco for iOS

On the App Store and the home screen it is **Choca Cinco** ("high five"): plain "Cinco" was taken.

SwiftUI with SwiftData, syncing cards and progress through iCloud (CloudKit).

```
Cinco/Model/Card.swift        Card and DayLog, the SwiftData models (CloudKit-safe: defaults, no unique, no relationships)
Cinco/Model/Chunk.swift       Chunk, a theme from before the one library: unused, kept in the CloudKit schema
Cinco/Logic/Scheduler.swift   the five-stage schedule, pure functions
Cinco/Logic/StudySession.swift one sitting: queue, reveal steps, grading, undo
Cinco/Logic/TextMatch.swift   answer checking, and the hash(strip()) card ids
Cinco/Logic/CardRecord.swift  a card as it comes in, and CardJSON (the sample deck)
Cinco/Logic/Deck.swift        adding cards, verb tables -> conj cards, merging iCloud duplicates
Cinco/Model/Reading.swift     Reading, a pasted text for Lecturas (same CloudKit rules)
Cinco/Logic/Lectura.swift     lines, words and tapped runs of a reading; recycling old readings
Cinco/Logic/Library.swift     the one library: each word once, what to study first, feeding it pages and taps
Cinco/Logic/PageScan.swift    scanned pages back into paragraphs
Cinco/Logic/Tutor.swift       Claude through the proxy in ../proxy: a page's words, cards, levels, example sentences
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

Only two places, both behind the **+** button: **Lecturas** (words marked while reading) and **Añadir una palabra** (one
word or phrase and its meaning; Claude corrects how it's written, and its example sentence and level follow in the
background). Siri's "Add a card to Choca Cinco" saves what it's told, and the background fills in the
sentence and level. There is no bundled deck and no bulk import. `Cinco/Logic/Intents.swift`
also gives Shortcuts **Tarjetas pendientes**.

## Development

Tests: `xcodebuild test -project Cinco.xcodeproj -scheme 'Choca Cinco' -destination 'platform=iOS Simulator,name=iPhone Air' CODE_SIGNING_ALLOWED=NO`

Debug builds take launch arguments for the simulator:

- `-loadSample` loads the sample deck (`samples/deck.json`, read from the repo, not shipped) into an empty store, for the flags here.
- `-openScan` opens a sample scanned page as if just scanned; `-scanSample` makes the scan card use that page instead of the camera.
- `-demo vocab|conj <steps> [stage]` opens a verb card at a stage and advances it that many reveal steps.
- `-tutorDemo` gives Lecturas canned answers instead of Claude; `-tutorURL http://localhost:8787` uses a proxy running on the Mac.
- `-studyNewest <n>` starts a session with the n most recently added word cards; `-studyCard <spanish>` with one card.

## Home

The library by level, and one button to study it (`Library.plan`): the whole library is one pipeline, with new words
coming in foundational first. Each session starts afresh, so words just added are in it. Verbs' tables are studied by
tense from the Conjugación chips below, and those sessions can be picked up by their key (`StudyAction`, owned by RootView).

Words and phrases are one kind of card; a card is a verb only because it has tables. After an answer, «Dónde la
leíste» lists every reading the word was marked in, with its sentence, and «Más frases» a verb's own sentences.

## Lecturas

The library is fed by what's read, and each word is in it once (`Library`): a card is found by its Spanish without its
article, and by each of its alternatives.

**Scanning a book** (`ScanCard`, `Logic/PageScan.swift`): Apple's document camera takes up to 5 pages, and Vision reads
them on the phone; the photos go no further. `PageText` puts the printed lines back into paragraphs from where they sit
on the page (first-line indents, dialogue dashes, gaps, words hyphenated across lines), and sets aside the page number
and running head. Then `ReadingView.takeWords`:

1. Claude lists every different word on the page, with its dictionary form, its level and its forms there (`Tutor.words`,
   the proxy's `/words`, about 30 seconds a page). The list is kept with the reading (`Reading.pageWords`).
2. Words not in the library go in, foundational first, up to Ajustes › Palabras nuevas por escaneo (`Library.addNext`, 25
   unless changed). Each sentence on the page becomes that card's example. Once those are studied, the page offers the
   next batch; otherwise they wait for another page.
3. The page offers to study, its words first (`Library.plan(first:)`), and the session comes back to it. A new word is
   a check and the start of training in one: "Ya la sé" (`Scheduler.alreadyKnown`, Dominada, checked in a month), or "No
   la sé" (`introDone`, into stage 1). Reading is never held back.

**Tapping while reading** (`Library.record`): tap a word, or hold and slide across a phrase, and it's recorded straight
away. Yellow: it's in the library already, gains this reading as a source, and comes back for review. Green: it's new, and
a card is added. It's grey until that's settled. The page's list usually knows the form; otherwise Claude's card gives the
dictionary form, on an article too. Without Claude (declined, offline, out for the day), Apple's on-device model gives the
meaning, keeping the words as tapped.

**Words you know** (`KnownWords`) are highlighted before any tap, in a paler yellow, on scanned pages and articles alike:
every word studied or marked "Ya la sé" (stage above 0, not set aside). The highlighter in the reading's toolbar turns this
on and off. A page's list decides which word a form is; otherwise it's the spelling, then Apple's lemma (`huele` is oler).
Tapping a highlighted word records it like any other.

Readings not opened for 30 days are deleted, except pages of a book. Their words stay.

**No new CloudKit fields.** TestFlight builds use the production schema, so this reuses fields already there: the level
is a tag (`nivel2`, `Card.level`), the book's name is in `Reading.url`, the page's word list in `Reading.checkData`.
`Chunk` and `Card.chunkID`, from when the library was split into themes, stay in the schema unused.

**The article's text** (`ReadingView.readArticle`, when a reading from a link has no lines yet): `ArticleReader` loads the page in an
offscreen `WKWebView`, so sites that turn away a plain download still answer, and runs `Resources/ArticleExtract.js`
in it. That script returns two candidates: the page's own JSON-LD `articleBody`, and the paragraphs Mozilla's
Readability (`Resources/Readability.js` 0.6.0, Firefox's Reader View) finds once figures, asides and screen-reader-only
text are removed. `ArticleText.choose` takes the metadata when it's the whole article in paragraphs, else
Readability's text, and drops common news labels (PUBLICIDAD, Fuente de la imagen…). No model is involved, so a page
always gives the same text. Paragraphs already marked on the page keep their place. A page whose text can't be read is
still read on the page, its lines coming from the paragraphs marked there.

Claude is reached through the Cloudflare Worker in `../proxy`, which holds the API key; the app asks once before
sending anything, and again before sending a whole page.
