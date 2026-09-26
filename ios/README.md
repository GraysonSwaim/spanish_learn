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

## Development

Tests: `xcodebuild test -project Cinco.xcodeproj -scheme Cinco -destination 'platform=iOS Simulator,name=iPhone Air' CODE_SIGNING_ALLOWED=NO`

Debug builds take launch arguments for the simulator:

- `-importCSV <path>` loads a deck file from the Mac at launch.
- `-demo vocab|conj <steps> [stage]` opens a verb card at a stage and advances it that many reveal steps.

## Not yet in the native app

Frase (fill-in-the-sentence) conjugation mode, importing a backup from the web app, CSV export.
