# Cinco — five-stage Spanish flashcards

A phone app for learning Spanish vocabulary. You write cards as a CSV in iCloud Drive, import them on your iPhone, and study a few minutes a day. Every card climbs five stages of mastery, each harder and further apart than the last.

It is a single HTML file. No accounts, no server, no App Store. It installs to your home screen from Safari and works offline.

```
index.html            the whole app (HTML, CSS, JavaScript)
manifest.webmanifest  tells iOS to treat it as an app
sw.js                 makes it work offline
icons/                home screen icons
decks/starter.csv     62 high-frequency words to begin with
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

Why this order: recognizing a word (Spanish to English) is much easier than producing it (English to Spanish), and production is what speaking requires. Early stages build recognition cheaply, later stages force production. The growing gaps between reviews are spaced repetition — you review each word just before you would forget it, so a deck of a thousand words costs only a few minutes a day.

## Setup, once

You need: a Mac, a GitHub account, an iPhone signed into iCloud.

### 1. Publish the app (done)

The repo is at https://github.com/GraysonSwaim/spanish_learn and GitHub Pages serves it from the `main` branch. The live app is:

```
https://graysonswaim.github.io/spanish_learn/
```

Every `git push` to `main` republishes it within about a minute.

### 2. Install it on your iPhone

1. Open https://graysonswaim.github.io/spanish_learn/ in **Safari** (must be Safari, not Chrome).
2. Tap the Share button, then **Add to Home Screen**, then **Add**.
3. Open Cinco from your home screen. It runs full screen and works offline.

### 3. Set up iCloud Drive as your card store

On your Mac, in Finder → iCloud Drive, make a folder called `Spanish` with four folders inside: `vocabulario` (topic decks), `verbos` (decks with tense columns), `archivo` (old decks you keep but no longer import) and `backups`. Copy `decks/starter.csv` into `vocabulario`. Anything you put here shows up in the Files app on your phone within seconds. `scripts/make_audio.py` reads decks from every folder but `backups`.

## Daily use

**Import cards:** in Cinco, tap *Import cards* → Browse → iCloud Drive → Spanish → vocabulario (or verbos) → tap the CSV. You will see "Added 62, updated 0".

**Study:** tap *Start studying*. Reviews first, then new cards. Tap the speaker to hear the Spanish; it plays automatically when a Spanish word appears (turn off in Settings).

**Back up:** tap *Back up progress* → **Save to Files** → iCloud Drive → Spanish → Save. Do this every few days; the home screen reminds you. To move to a new phone or recover, tap *Restore from backup* and pick that file.

Your progress is stored on the phone itself. The iCloud Drive backup file is the copy you own.

## Writing cards

A CSV with a header row. Only the first two columns are required.

```csv
spanish,english,example,notes,tags,presente,preterito
el coche / el carro,car,"Mi coche es rojo.",Spain says coche; Mexico says carro,transport,,
saber,to know,"No sé la respuesta.",Facts and skills; conocer is for people,verbs,sé|sabes|sabe|sabemos|sabéis|saben,supe|supiste|supo|supimos|supisteis|supieron
```

- Write it in Numbers, Excel, Google Sheets, or a text editor and export as CSV (UTF-8). Put it in iCloud Drive/Spanish/vocabulario, or verbos if it has tense columns.
- Alternatives separated by `/` are all accepted when typing. Text in parentheses is ignored when checking.
- Cards are matched on the Spanish text. Re-importing the same file updates the English, example and notes of existing cards **without losing their progress**, and adds any new rows. So you can keep one big `words.csv` and re-import it after editing.
- Anki exports work too: in Anki, File → Export → Notes in Plain Text (.txt), then import that file. Tab-separated files and files without a header row are read as Spanish, English, example, notes, tags, then the six tenses, in that order.
- **Verbs and the Conjugación tab.** A verb can have one column per tense: `presente`, `preterito`, `imperfecto`, `futuro`, `condicional`, `subjuntivo` (present subjunctive), plus optionally `subj_imperfecto`, `imperativo`, `imperativo_negativo`, `perfecto`, `pluscuamperfecto`, `futuro_perfecto`, `condicional_perfecto`, `subj_perfecto` and `subj_pluscuamperfecto`, each with its six forms separated by `|` (yo, tú, él, nosotros, vosotros, ellos). The verb stays one card on the Vocabulario tab, with its tables on the answer. Each tense becomes one card on the Conjugación tab (*saber · Pretérito*): you study the table, then say it aloud, then from stage 4 type all six forms. Imperatives leave the yo slot empty. A tense switch on that tab, grouped by mood, picks what to practice, or *Aleatorio* mixes them; each tense keeps its own progress. Vosotros forms are only asked if you turn on Settings → *Practicar vosotros*. Edit the tables on the verb's card; don't write a row per form. An older single `conjugation` column is read as `presente`.
- **Sentences instead of tables.** Settings → *Conjugación* → *Frase* asks a tense as a sentence with the verb blanked out (*Siempre ___ café con leche*, with the person in the gap) instead of the whole table, from stage 2 on; *Mezcla* alternates. The sentences are the verb's `example` plus an optional `frases` column (sentences separated by `|`, any tense). Cinco finds the form in each sentence by matching it against the verb's tables, so it knows the tense and person without markup. A tense with no sentence is asked as a table.
- **Tags for verb families.** A verb's tag can name its present-tense family after `verbs`: `verbs o-ue`, `verbs yo-go`, `verbs regular`. Searching Browse for `o-ue` lists the family.
- Column names are flexible: `spanish`/`es`/`front`, `english`/`en`/`back`, `example`/`sentence`, `notes`, `tags`, and the tense names (`conjugation` also means `presente`).

**Export:** Settings → *Export cards as CSV* gives you every card with its stage and next review date, for editing or analysis on your Mac.

## Having an AI write your cards

`skills/cinco-cards/` is a skill that teaches Claude (or, pasted as instructions, ChatGPT) to write decks in this format with good judgment about what makes a card learnable. `skills/README.md` explains how to install it in each tool and how to validate a CSV before importing. `decks/airport-a1.csv` is a deck written with it.

## Changing the app

Edit `index.html`, then:

```sh
git add . && git commit -m "describe the change" && git push
```

Bump `CACHE = 'cinco-v1'` in `sw.js` to `v2`, `v3`, … whenever you change `index.html`, so phones fetch the new version. Force-quit and reopen Cinco twice after pushing.

To try changes on your Mac before pushing:

```sh
python3 -m http.server 8080
```

then open http://localhost:8080 in Safari and use the Responsive Design Mode (Develop menu) to see it at iPhone size.

Scheduling knobs live at the top of the script in `index.html`: the `STAGES` table (names, intervals), `RELEARN_GAP` (how many cards later a miss returns), `MAX_IVL` (longest gap for mastered cards).

## Why not a native app

A Swift app that reads iCloud Drive needs the $99/year Apple Developer Program for the iCloud entitlement, and apps installed with a free account expire every seven days. The web app route is free, installs like an app, works offline, and reaches iCloud Drive through the Files picker and share sheet. If you ever want a native version, the scheduling logic in `index.html` ports directly.
