# Cinco — five-stage Spanish flashcards

An iPhone app for learning Spanish vocabulary (on the App Store as **Choca Cinco**). Every card climbs five stages of
mastery, each harder than the last, and only a few cards are in play at once.

```
ios/       the app (SwiftUI + SwiftData, synced through iCloud); see ios/README.md
proxy/     the Cloudflare Worker that reaches Claude for the library
```

## The five stages

| Stage | Name | What you do | Holds |
|---|---|---|---|
| New | — | Not yet studied. Enters stage 1 when it has room. | — |
| 1 | Learn | You see Spanish and English together, then get quizzed a few cards later. | 5 |
| 2 | Recognize | Spanish shown, recall the English. | 5 |
| 3 | Recall | English shown, say the Spanish out loud, then reveal. | 5 |
| 4 | Produce | English shown, type the Spanish. Accents count; a near miss is flagged, not failed. | 5 |
| 5 | Mastered | Typed or recognized at random. Reviewed after 1 week, then 2, 4, 8… | no limit |

Stages 1–4 are a pipeline (the 5 is Ajustes › Tarjetas por etapa). A right answer moves a card up only if the next
stage has room; otherwise it waits, ready, and moves the moment a place opens. A new card enters only when stage 1 has
room. A miss drops a card one stage even into a full stage, so nothing behind it moves until a right answer makes room
again. Mastering a card at the top opens a place that passes all the way back and lets one new card in.

There's no waiting in stages 1–4: the session goes round them for as long as you like, with the Mastered cards that are
due mixed in. Mastered cards are the spaced repetition: a week, then the wait doubles each time one is right after its
wait is up (an early review leaves it alone). A miss sends it back to Produce.

## The library

There's one library of words, each in it once however many pages it turns up on, and one button to study it. It's built
from what you read, in three steps:

1. **Feed it pages.** Scan a page of your book in Lecturas. Claude lists every word on it in dictionary form, sorted into
   foundational, intermediate and advanced, and the new ones go into the library, foundational first, up to a limit per
   scan (25 unless changed in Ajustes).
2. **Study.** Each new word is one quick step: "Ya la sé" and it's done, or "No la sé" and its training starts here. The
   page's own words come first.
3. **Read.** Tap what you don't understand and it's recorded. Yellow: it's already in the library, and comes back for
   review. Green: it's new, and just went in.

You study what you'll actually read, so there's no starter deck: the commonest words arrive first because they're on
every page. Words can also be added one at a time with **+**, or marked on an article from a link.

Why this order: recognizing a word (Spanish to English) is much easier than producing it (English to Spanish), and
production is what speaking requires. Early stages build recognition cheaply, later stages force production. Keeping
only a few cards in each stage means you learn those well before more arrive.

Pushing to `main` builds the app in Xcode Cloud and sends it to TestFlight.
