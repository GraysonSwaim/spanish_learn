---
name: cinco-cards
description: Write Spanish vocabulary flashcards as a CSV for the Cinco app (five-stage spaced repetition, imported from iCloud Drive). Use this whenever the user asks for Spanish flashcards, vocab cards, a deck, "cards for Cinco/Anki", words on a topic, or wants a word list turned into cards — even if they don't name the app or say "CSV". Decks are saved straight into the user's iCloud Drive `Spanish` folder so the phone can import them. Also use it to check or fix a CSV before importing.
---

# Cinco cards

Cinco is a personal Spanish flashcard app. Cards climb five stages: first the learner recognizes the Spanish, then recalls it from English, then **types the Spanish from English**. Everything below follows from that last stage: the Spanish field is not just displayed, it is the exact string the learner has to reproduce, and their typo tolerance is small (accents flagged, article optional, everything else must match).

## Output format

A UTF-8 CSV, one card per row. A deck without verbs uses the first five columns:

```csv
spanish,english,example,notes,tags
```

A deck with verbs adds a column per tense and then `frases`:

```csv
spanish,english,example,notes,tags,presente,preterito,imperfecto,futuro,condicional,subjuntivo,frases
```

- `spanish` and `english` are required. The others may be empty; non-verb rows in a verb deck leave the tense columns and `frases` empty. The optional tenses (below) go after `subjuntivo` and before `frases`.
- Quote any field containing a comma, a quote, or a line break (`"Hola, ¿cómo estás?"`). Double a quote inside a quoted field (`""`).
- Keep the columns in this order. The app also reads Anki tab-separated exports, but produce CSV.

The Spanish text is the card's identity. Re-importing a row with the same Spanish updates the other fields without losing progress; a changed spelling becomes a new card. So spell consistently across decks, and never emit two rows with the same Spanish.

## Writing each field

**spanish** — what the learner types. Keep it short: one word, or a phrase of at most four or five words. Nouns take their article (`la mesa`, `el problema`) so gender is learned with the word; the checker lets the learner omit it, but seeing it every time is the point. Verbs go in the infinitive. Include accents and `ñ` exactly. Regional or equivalent forms go in one field separated by ` / ` and all are accepted when typing (`el coche / el carro`). Text in parentheses is ignored by the checker, but put disambiguation in the English or notes instead, so the Spanish stays clean on the card.

**english** — the meaning, short. Several senses separated by ` / ` (`el tiempo,time / weather`). Disambiguate here when the Spanish could be typed from several English words: `bank (money)` for `el banco`.

**example** — one natural sentence, roughly 5 to 12 words, at the learner's level, using the word (conjugated is fine). It appears in italics under the card at every stage, so it carries a lot of the learning: pick something concrete, a bit memorable, and typical of how the word is really used. Use ¿ ¡ and accents properly. This field is optional but leave it empty only for words that don't need context (`sí`, `gracias`).

**notes** — only when a note earns its place: an irregular conjugation (`tengo, tienes, tiene`), a gender exception (`el agua` is feminine), a false friend, a ser/estar or saber/conocer contrast, a Spain-vs-Latin-America difference. One line, under about 80 characters. An empty notes field is the normal case; a deck where every row has a note is padded.

**tags** — one lowercase word (`food`, `verbs`, `travel`). Keep the set small and reuse tags across decks so Browse filtering stays useful. A verb with tense columns also gets its present-tense family after `verbs`, so a family can be pulled up and drilled together instead of learning each verb as a one-off: `verbs regular`, `verbs e-ie`, `verbs o-ue` (jugar's u→ue too), `verbs e-i`, `verbs yo-go`, `verbs yo-zco`, `verbs spelling` (recojo, construyo), `verbs accent` (envío, continúo), `verbs irregular` (ser, estar, ir, saber). A verb in two families gets both: `verbs yo-go e-ie` (tener, venir).

**presente, preterito, imperfecto, futuro, condicional, subjuntivo** (and optionally **subj_imperfecto, imperativo, imperativo_negativo, perfecto, pluscuamperfecto, futuro_perfecto, condicional_perfecto, subj_perfecto, subj_pluscuamperfecto**) — for a verb, one column per tense, each holding its six forms separated by `|` in the order yo, tú, él, nosotros, vosotros, ellos: `tengo|tienes|tiene|tenemos|tenéis|tienen`. `subjuntivo` is the present subjunctive, written without "que" (`tenga|tengas|…`). The app keeps the verb as one vocabulary card (infinitive ↔ meaning, with its tables on the answer) and makes one conjugation card per tense in its Conjugación tab, where the learner conjugates the whole table (`tener · Pretérito`), each tense with its own progress. So never write a separate row per conjugated form or per tense; fill the columns. Fill all six tenses for a verb unless the user asks for fewer; a verb with no presente gets a warning. Reflexive verbs include the pronoun (`me visto|te vistes|…`). Always fill vosotros (drilling it is a setting); leave it empty only for a verb without one. When the verb's spanish has alternatives, give each form the same alternatives (`empiezo / comienzo|…`). Notes describe the present tense only (`o→ue, except nosotros and vosotros`), since the app shows them only on the present card. Check every form, especially irregular preterites, -ir stem changes in the preterite (pidió, durmieron) and subjunctive (durmamos), and spelling changes (jugué, empecé, busque): a wrong form typed a hundred times is worse than none. The imperatives have no yo form, so their first slot stays empty (`|ten|tenga|tengamos|tened|tengan`), and the negative one includes "no" (`|no tengas|no tenga|…`); leave imperatives out for verbs without a natural command (poder, costar). The imperfect and pluperfect subjunctive give both endings as alternatives (`tuviera / tuviese`). Older decks with a single `conjugation` column are read as `presente`.

**frases** — for a verb, extra sentences separated by `|`, used when the learner sets Conjugación to Frase: the app finds the verb's form in a sentence by matching it against the tense columns, blanks it out (`Siempre ___ café con leche`, with the person in the gap) and asks for it. So every sentence must contain one of the forms exactly as written in the columns (reflexives with their pronoun: `Me vestí rápido`). The example counts as one sentence already, so write frases for the other tenses, at least one in the preterite: `Ayer tuve que trabajar hasta tarde.` If the example uses the infinitive (`Tengo que devolver este libro`), add a present-tense frase too. Prefer persons whose form belongs to only one tense: nosotros in -ar and -ir is the same in present and preterite (`hablamos`), and a sentence opening with the él form of the present (`Sigue derecho`) also reads as a tú command. Give the sentence enough context to point to the tense (`ayer`, `anoche`, `el año pasado`). No `|` inside a sentence.

## Choosing and ordering words

The app introduces new cards in file order, about 15 a day. So order rows from most useful to least: high-frequency words and the phrases that unlock conversation first, rarer words later. Within a topic, put the words the example sentences depend on before the sentences that use them.

Prefer chunks over isolated words when the chunk is how people actually speak: `tener que`, `por supuesto`, `me gustaría`, `¿cuánto cuesta?`. A learner who types `hay que` from "one has to" has learned more than one who types `haber`.

One idea per card. If a word has two unrelated senses that would be tested differently, prefer the common one and mention the other in notes, or make two cards only if both senses are genuinely worth learning. Don't split one sense into several cards to pad the deck.

Default to neutral Latin American Spanish, and when Spain differs in a way the learner will meet, put the Spain form as a ` / ` alternative or in notes. Follow the user if they say which variety they want.

Match the level. For a beginner, examples use present tense and vocabulary from the deck itself. For an intermediate learner, examples can use past and subjunctive and the words can be less frequent.

## Verb decks

Spanish verbs are mostly patterns, and a deck should teach the pattern before the exceptions, so a verb is learned as one of a family instead of as a one-off.

- **Order by family.** Regular verbs first, a few each of -ar, -er and -ir, so the endings become automatic; 10 to 15 is enough, since they all share the same endings. Then the stem-changers, one family at a time (e→ie, o→ue, e→i), then yo-go and yo-zco, then the truly irregular (ser, estar, ir, haber). Within a family, most frequent first. The first verb of a family carries the pattern in its note (`-ar: o, as, a, amos, áis, an`; `e→ie, except nosotros and vosotros`), and its tag names the family (see **tags**).
- **Back every table with sentences.** Each verb gets an example and at least one preterite frase, so it can be practised in context (Conjugación › Frase) and not only as a table.
- **Strong preterites are their own family.** tener → tuv-, estar → estuv-, poder → pud-, poner → pus-, saber → sup-, querer → quis-, hacer → hic- (hizo), venir → vin-, decir → dij-, traer → traj-, conducir → conduj-, all with the same unaccented endings: -e, -iste, -o, -imos, -isteis, -ieron (-eron after j: dijeron). Check these forms twice. When the user wants preterite practice, a deck of short chunks in the preterite works alongside the verbs' tables: `tuve que` (I had to), `no pude`, `¿qué hiciste?`, `me dijo que`, `fui`, tagged `preterito`, no tense columns. That doesn't break the rule against a row per form: a chunk is a phrase with its own meaning, not a slice of a table.
- **Don't repeat verbs.** A verb already in another deck is updated, not added, on import, so check the user's decks and leave it out, or edit that deck if the user asked for it.

Default deck size is 20 to 40 cards unless the user asks for something else. At 15 new cards a day that is two or three days of new material, which is about right for one topic.

## Before handing it over

1. Check for duplicate Spanish values within the file. If the user shared their existing deck or export, check against that too.
2. Read every example and confirm it contains the card's word and would make sense to the learner without the English.
3. If you can run code, run `scripts/validate_cards.py path/to/file.csv`. It checks the header, required fields, quoting, duplicates, and that each example contains its word. Fix what it reports.
4. Save the file into the user's iCloud Drive `Spanish` folder, which is the app's import location. On a Mac that is:

   ```
   ~/Library/Mobile Documents/com~apple~CloudDocs/Spanish/
   ```

   The folder is sorted into subfolders; put the deck in the one that fits and never loose at the top:

   - `vocabulario/` — topic decks: words and phrases, no tense columns (`vocabulario/restaurant-a1.csv`).
   - `verbos/` — decks with tense columns, or verb chunks like the strong preterites (`verbos/o-ue.csv`, `verbos/preterito-fuerte.csv`). Name a verb deck after its family or tense, since that is how verbs are organized (see **Verb decks**).
   - `archivo/` — superseded decks the user keeps but no longer imports. Never save here; move a deck here only when the user replaces it with a newer version.
   - `backups/` — the app's progress backups. Never save decks here.

   Filenames are lowercase words joined by hyphens, a topic plus the level when it helps (`restaurant-a1.csv`), without the folder's name repeated (`verbos/regulares.csv`, not `verbos/verbos-regulares.csv`). Save there by default, without asking, whenever the folder exists; the whole point is that the deck shows up in Cinco's import picker on the phone a few seconds later. Never overwrite a deck that is already there unless the user asked for an edit to that file. If the folder isn't reachable (a different machine, or no file access), save where you're working and tell the user to move the file into iCloud Drive › Spanish › vocabulario or verbos. If you can't save files at all, put the CSV in a single code block so it can be copied whole.

5. Before writing, glance at the existing decks in `vocabulario/` and `verbos/` and pass them to the validator with `--existing`, so new decks don't repeat words the user already has: `--existing "$DIR"/vocabulario/*.csv "$DIR"/verbos/*.csv`.

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
pedir,to order / to ask for,"¿Qué vas a pedir?","Irregular: pido, pides, pide",restaurant
la cuenta,the bill / the check,"La cuenta, por favor.",,restaurant
la propina,tip,"Dejamos una propina del diez por ciento.",,restaurant
quisiera,I would like,"Quisiera un café con leche.",Politer than quiero,restaurant
sin,without,"Un agua sin gas, por favor.",,restaurant
picante,spicy,"¿Es muy picante este plato?",,restaurant
```

Note what's there: articles on nouns, one alternative where the two regions really differ, a note only where it helps, examples that are lines you would actually say at a table, ordered so the first cards are the ones needed first.

Request: "verbs for talking about my day, beginner"

```csv
spanish,english,example,notes,tags,presente,preterito,imperfecto,futuro,condicional,subjuntivo,frases
hablar,to speak / to talk,Hablo un poco de español.,"-ar: o, as, a, amos, áis, an",verbs regular,hablo|hablas|habla|hablamos|habláis|hablan,hablé|hablaste|habló|hablamos|hablasteis|hablaron,hablaba|hablabas|hablaba|hablábamos|hablabais|hablaban,hablaré|hablarás|hablará|hablaremos|hablaréis|hablarán,hablaría|hablarías|hablaría|hablaríamos|hablaríais|hablarían,hable|hables|hable|hablemos|habléis|hablen,Ayer hablé con mi hermano por teléfono.
pensar,to think,¿Qué piensas del plan?,"e→ie, except nosotros and vosotros",verbs e-ie,pienso|piensas|piensa|pensamos|pensáis|piensan,pensé|pensaste|pensó|pensamos|pensasteis|pensaron,pensaba|pensabas|pensaba|pensábamos|pensabais|pensaban,pensaré|pensarás|pensará|pensaremos|pensaréis|pensarán,pensaría|pensarías|pensaría|pensaríamos|pensaríais|pensarían,piense|pienses|piense|pensemos|penséis|piensen,Anoche pensé mucho en el viaje.
tener,to have,Tengo dos hermanos.,"Yo-go, then e→ie: tengo, tienes, tiene",verbs yo-go e-ie,tengo|tienes|tiene|tenemos|tenéis|tienen,tuve|tuviste|tuvo|tuvimos|tuvisteis|tuvieron,tenía|tenías|tenía|teníamos|teníais|tenían,tendré|tendrás|tendrá|tendremos|tendréis|tendrán,tendría|tendrías|tendría|tendríamos|tendríais|tendrían,tenga|tengas|tenga|tengamos|tengáis|tengan,Ayer tuve que trabajar hasta tarde.|El año pasado tuvimos mucha suerte.
tener que,to have to,Tengo que salir temprano.,Tener que + infinitive,verbs,,,,,,,
```

Note what's there: the regular verb first, then one family at a time, each verb tagged with its family and its first note naming the pattern; every table backed by a preterite frase (`tuvimos`, not `hablamos`, whose nosotros is the same in the present); and the chunk `tener que` as a plain card with no tables of its own.
