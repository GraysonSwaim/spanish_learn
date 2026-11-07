# Choca Cinco tutor proxy

A Cloudflare Worker between the app and Claude, for Lecturas (readings and scanned book pages), example sentences on cards,
and checking the meanings of words the learner picks. The API key lives only here, never in
the app.

| Route | The app sends | Claude returns |
|---|---|---|
| `POST /check` | up to 15 cards picked in Palabras (Spanish, meaning, and their sentence when they have one) | for each, `right` or `fix` with the meaning to use, and a short note; `none` when Claude skipped it. Only ever sent when the learner says yes |
| `POST /gloss` | the words and phrases marked while reading, each with its sentence, and the dictionary form when the page's word list has decided it | a card for each: dictionary form, meaning in context, a short note. Answers are joined by item number, and one about another word than the one asked for comes back without a meaning, so no card is made of it |
| `POST /examples` | flashcards (Spanish, meaning, and their sentence when they have one) | for each, a short example sentence (their own, untouched, when they have one), its English, and the card's words as they appear in it |
| `POST /words` | up to about a page of scanned text | every different word in it, once: dictionary form, level (1 foundational, 2 intermediate, 3 advanced), and its forms as they stand in the text |
| `POST /levels` | up to 40 words from the library | each one's level |

All take a `device`: a random ID the phone makes once, so each phone's allowance is counted on its own.

The model is `MODEL` in `wrangler.toml` (Claude Haiku 5.5), except for `/check`, which uses `CHECK_MODEL` (Claude Sonnet
5.5, 20 times the price). With Sonnet or Opus, declined requests are handed on to another model with server-side fallbacks
(`fallbacks: "default"`); Haiku has none, so a request it declines comes back as a 422.

## Caps

Each call sets aside its whole `max_tokens` (thinking counts as output) and a token per character of its input plus
2,000, then keeps only what it really used. The daily caps are in `wrangler.toml`: per phone at most about 9 cents a day,
everyone together about 18 cents, if someone found the URL and spent it all. Real use is far below: a gloss of 20 words costs about
0.1 cents, a scanned page about 0.2.

The caps are counted in Haiku's tokens, and `/check`'s Sonnet tokens count `CHECK_COST_WEIGHT` (20) times, so the cents above
hold whatever the model. A check of 15 words costs about 2 to 4 cents, and sets aside most of an ordinary phone's day: about one
a day there, about 12 on the owner's.

The owner's phones get their own, larger caps: at most about 90 cents a day per phone. They're counted apart, so they aren't
held back by everyone's cap and don't use it up. Their device IDs are in a secret rather than in the repo, because knowing an ID
is all it takes to spend from its allowance. To add a phone, see "Day to day".

The backstop is the workspace's spend limit in the Anthropic Console. The owner's caps can pass a low one over a month, and then
every call fails until it's raised.

## Set up (once)

1. **Anthropic Console** (console.anthropic.com)
   - Settings > Workspaces: create a workspace "Choca Cinco" with a monthly spend limit (e.g. $10).
   - In that workspace, create an API key.
2. **Cloudflare**
   ```sh
   cd proxy
   npm install
   npx wrangler secret put ANTHROPIC_API_KEY   # paste the key from step 1
   npm run deploy
   ```
   It prints `https://choca-cinco-tutor.<you>.workers.dev`, which goes in `Tutor.deployed`
   (`ios/Cinco/Logic/Tutor.swift`).

## Day to day

- `npx wrangler tail` streams each call's model and its input and output token counts.
- Local run: put `ANTHROPIC_API_KEY=...` in `proxy/.dev.vars` (git-ignored), `npm run dev`, then launch the app in the
  simulator with `-tutorURL http://localhost:8787`.
- Change a cap or the model in `wrangler.toml`, then `npm run deploy`.
- To give a phone the owner's caps: run `npx wrangler tail`, use Claude on that phone (tap a word, say), and copy the `device`
  from the log. Then run `npx wrangler secret put OWNER_DEVICES` and paste the IDs, separated by commas, including any already
  there, as it replaces the old list. It takes effect straight away. Deleting the app makes a new ID.

## Errors the app sees

| Status | Body | Meaning |
|---|---|---|
| 400 | `bad_request` | Over the request limits (15 cards to check, 40 marked words or cards, 6,000 characters of a page) |
| 429 | `budget` | This phone, or everyone, is out for today. An owner's phone runs out of only its own caps |
| 422 | `refused` | Claude declined |
| 502 | `too_long`, `bad_reply`, `upstream` | Reply cut off or malformed, or the API call failed |
| 503 | `busy` | Anthropic rate limit or overload |

When Claude can't answer (any error but a 422, or offline), the app falls back to Apple's on-device model, on phones
that have Apple Intelligence, for translations and meanings only, not grading (see `Tutor.swift`).

## Not yet

- **App Attest.** Anyone who finds the URL can call it, inside the caps above. Before Lecturas with Claude goes to
  everyone on the App Store, the Worker should check App Attest so only the real app on a real phone gets through.
