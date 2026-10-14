# Cinco — five-stage Spanish flashcards

An iPhone app for learning Spanish vocabulary (on the App Store as **Choca Cinco**). You study a few minutes a day,
and every card climbs five stages of mastery, each harder and further apart than the last.

```
ios/       the app (SwiftUI + SwiftData, synced through iCloud); see ios/README.md
proxy/     the Cloudflare Worker that reaches Claude for Lecturas
```

## The five stages

| Stage | Name | What you do | Comes back after |
|---|---|---|---|
| New | — | Not yet studied. Introduced at your daily limit (default 15). | — |
| 1 | Learn | You see Spanish and English together, then get quizzed a few cards later in the same session. | same session |
| 2 | Recognize | Spanish shown, recall the English. | 1 day |
| 3 | Recall | English shown, say the Spanish out loud, then reveal. | 3 days |
| 4 | Produce | English shown, type the Spanish. Accents count; a near miss is flagged, not failed. | 7 days |
| 5 | Mastered | Typed or recognized at random. | 21 days, then doubling, up to 120 |

Got it moves a card up one stage. Again drops it one stage and brings it back five cards later. Reviews come before new cards, so a backlog never gets buried under new material.

Why this order: recognizing a word (Spanish to English) is much easier than producing it (English to Spanish), and production is what speaking requires. Early stages build recognition cheaply, later stages force production. The growing gaps between reviews are spaced repetition: you review each word just before you would forget it, so a deck of a thousand words costs only a few minutes a day.

Pushing to `main` builds the app in Xcode Cloud and sends it to TestFlight.
