# Cinco — five-stage Spanish flashcards

An iPhone app for learning Spanish vocabulary (on the App Store as **Choca Cinco**). Every card climbs five stages of
mastery, each harder than the last, and only a few cards are in play at once.

```
ios/       the app (SwiftUI + SwiftData, synced through iCloud); see ios/README.md
proxy/     the Cloudflare Worker that reaches Claude for Lecturas
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

## Themes

You build the dictionary yourself, from **Añadir** (one word at a time) and **Lecturas** (words marked while reading),
and you chunk it into themes. A reading's words arrive together in a theme named after it; a word marked that's
already in the dictionary keeps its theme and gains the reading, and its sentence, as another source to remember it by.
Words added by hand wait in Sueltas until you group them. Drag one theme onto another to make a bigger one: the
smaller ones stay inside, as deep as you like. Tapping a theme studies it, with its own pipeline; there's no single
"study" button.

Grouping follows the research on learning words in sets (Tinkham 1993, 1997; Waring 1997): new words of the same kind
(fruits, colours, opposites) learned together interfere with each other, while words that belong to one scene (on the
platform: the train, the suitcase, the delay) are learned more easily together.

Why this order: recognizing a word (Spanish to English) is much easier than producing it (English to Spanish), and
production is what speaking requires. Early stages build recognition cheaply, later stages force production. Keeping
only a few cards in each stage means you learn those well before more arrive.

Pushing to `main` builds the app in Xcode Cloud and sends it to TestFlight.
