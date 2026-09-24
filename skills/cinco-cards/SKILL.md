---
name: cinco-cards
description: Write Spanish vocabulary flashcards as a CSV for the Cinco app (five-stage spaced repetition, imported from iCloud Drive). Use this whenever the user asks for Spanish flashcards, vocab cards, a deck, "cards for Cinco/Anki", words on a topic, or wants a word list turned into cards — even if they don't name the app or say "CSV". Decks are saved straight into the user's iCloud Drive `Spanish` folder so the phone can import them. Also use it to check or fix a CSV before importing.
---

# Cinco cards

Cinco is a personal Spanish flashcard app. Cards climb five stages: first the learner recognizes the Spanish, then recalls it from English, then **types the Spanish from English**. Everything below follows from that last stage: the Spanish field is not just displayed, it is the exact string the learner has to reproduce, and their typo tolerance is small (accents flagged, article optional, everything else must match).

## Output format

A UTF-8 CSV with this exact header, one card per row:

```csv
spanish,english,example,notes,tags,conjugation
```

- `spanish` and `english` are required. The others may be empty. `conjugation` is only for verbs; a deck without verbs can leave the column out.
- Quote any field containing a comma, a quote, or a line break (`"Hola, ¿cómo estás?"`). Double a quote inside a quoted field (`""`).
- Keep the columns in this order. The app also reads Anki tab-separated exports, but produce CSV.

The Spanish text is the card's identity. Re-importing a row with the same Spanish updates the other fields without losing progress; a changed spelling becomes a new card. So spell consistently across decks, and never emit two rows with the same Spanish.

## Writing each field

**spanish** — what the learner types. Keep it short: one word, or a phrase of at most four or five words. Nouns take their article (`la mesa`, `el problema`) so gender is learned with the word; the checker lets the learner omit it, but seeing it every time is the point. Verbs go in the infinitive. Include accents and `ñ` exactly. Regional or equivalent forms go in one field separated by ` / ` and all are accepted when typing (`el coche / el carro`). Text in parentheses is ignored by the checker, but put disambiguation in the English or notes instead, so the Spanish stays clean on the card.

**english** — the meaning, short. Several senses separated by ` / ` (`el tiempo,time / weather`). Disambiguate here when the Spanish could be typed from several English words: `bank (money)` for `el banco`.

**example** — one natural sentence, roughly 5 to 12 words, at the learner's level, using the word (conjugated is fine). It appears in italics under the card at every stage, so it carries a lot of the learning: pick something concrete, a bit memorable, and typical of how the word is really used. Use ¿ ¡ and accents properly. This field is optional but leave it empty only for words that don't need context (`sí`, `gracias`).

**notes** — only when a note earns its place: an irregular conjugation (`tengo, tienes, tiene`), a gender exception (`el agua` is feminine), a false friend, a ser/estar or saber/conocer contrast, a Spain-vs-Latin-America difference. One line, under about 80 characters. An empty notes field is the normal case; a deck where every row has a note is padded.

**tags** — one lowercase word (`food`, `verbs`, `travel`). Keep the set small and reuse tags across decks so Browse filtering stays useful.

**conjugation** — for a verb, its six present-tense forms separated by `|`, in the order yo, tú, él, nosotros, vosotros, ellos: `tengo|tienes|tiene|tenemos|tenéis|tienen`. The app keeps the verb as one vocabulary card (infinitive ↔ meaning, with the table shown on the answer) and makes a separate drill for each form in its Conjugación tab, where the learner sees `nosotros · tener` and types `tenemos`. So never write a separate row per conjugated form; put the forms here. Reflexive verbs include the pronoun (`me visto|te vistes|se viste|nos vestimos|os vestís|se visten`). Vosotros is always filled in (drilling it is a setting in the app); only leave it empty for a verb that has no vosotros form. When the verb's spanish has alternatives, give each form the same alternatives (`empiezo / comienzo|...`). Once the table is there, notes should name the pattern (`o→ue, except nosotros and vosotros`) rather than list forms. Double-check every form: a wrong form typed a hundred times is worse than none.

## Choosing and ordering words

The app introduces new cards in file order, about 15 a day. So order rows from most useful to least: high-frequency words and the phrases that unlock conversation first, rarer words later. Within a topic, put the words the example sentences depend on before the sentences that use them.

Prefer chunks over isolated words when the chunk is how people actually speak: `tener que`, `por supuesto`, `me gustaría`, `¿cuánto cuesta?`. A learner who types `hay que` from "one has to" has learned more than one who types `haber`.

One idea per card. If a word has two unrelated senses that would be tested differently, prefer the common one and mention the other in notes, or make two cards only if both senses are genuinely worth learning. Don't split one sense into several cards to pad the deck.

Default to neutral Latin American Spanish, and when Spain differs in a way the learner will meet, put the Spain form as a ` / ` alternative or in notes. Follow the user if they say which variety they want.

Match the level. For a beginner, examples use present tense and vocabulary from the deck itself. For an intermediate learner, examples can use past and subjunctive and the words can be less frequent.

Default deck size is 20 to 40 cards unless the user asks for something else. At 15 new cards a day that is two or three days of new material, which is about right for one topic.

## Before handing it over

1. Check for duplicate Spanish values within the file. If the user shared their existing deck or export, check against that too.
2. Read every example and confirm it contains the card's word and would make sense to the learner without the English.
3. If you can run code, run `scripts/validate_cards.py path/to/file.csv`. It checks the header, required fields, quoting, duplicates, and that each example contains its word. Fix what it reports.
4. Save the file into the user's iCloud Drive `Spanish` folder, which is the app's import location. On a Mac that is:

   ```
   ~/Library/Mobile Documents/com~apple~CloudDocs/Spanish/
   ```

   Save there by default, without asking, whenever that folder exists; the whole point is that the deck shows up in Cinco's import picker on the phone a few seconds later. Use a descriptive filename (`restaurant-a1.csv`, `verbs-irregular-present.csv`) and never overwrite a deck that is already there unless the user asked for an edit to that file. If the folder isn't reachable (a different machine, or no file access), save where you're working and tell the user to move the file into iCloud Drive › Spanish. If you can't save files at all, put the CSV in a single code block so it can be copied whole.

5. Before writing, glance at the existing `.csv` files in that folder and pass them to the validator with `--existing`, so new decks don't repeat words the user already has.

6. Record the audio. The app plays a recording of each word instead of iOS speech, which is too quiet on the phone. If you are on the user's Mac and the Cinco repo exists at `~/Documents/github/spanish_learn`, run:

   ```sh
   cd ~/Documents/github/spanish_learn && python3 scripts/make_audio.py && git add audio && git commit -m "Audio for <deck name>" && git push
   ```

   The script records only the words that don't have audio yet (and removes recordings for words that are no longer in any deck), so it is safe to run every time. Pushing is what gets the recordings to the phone. If you can't run commands there, tell the user the new words will use the phone's built-in voice until the script is run.

Tell the user the filename, where it was saved, how many cards, and the tags used. Don't explain the CSV format back to them; they know it.

## Example

Request: "cards for ordering at a restaurant, I'm a beginner"

```csv
spanish,english,example,notes,tags
la mesa,table,"Una mesa para dos, por favor.",,restaurant
el menú / la carta,menu,"¿Me trae el menú, por favor?",Spain usually says la carta,restaurant
pedir,to order / to ask for,"¿Qué vas a pedir?",Irregular: pido, pides, pide,restaurant
la cuenta,the bill / the check,"La cuenta, por favor.",,restaurant
la propina,tip,"Dejamos una propina del diez por ciento.",,restaurant
quisiera,I would like,"Quisiera un café con leche.",Politer than quiero,restaurant
sin,without,"Un agua sin gas, por favor.",,restaurant
picante,spicy,"¿Es muy picante este plato?",,restaurant
```

Note what's there: articles on nouns, one alternative where the two regions really differ, a note only where it helps, examples that are lines you would actually say at a table, ordered so the first cards are the ones needed first.
