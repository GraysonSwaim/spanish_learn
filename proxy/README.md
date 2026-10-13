# Choca Cinco tutor proxy

A Cloudflare Worker between the app and Claude, for Lecturas (pasted readings). The API key lives only here, never in
the app.

| Route | The app sends | Claude returns |
|---|---|---|
| `POST /check` | a reading's lines and the learner's translations, `es-en` or `en-es` (Al revés) | per line a verdict (`good`, `close`, `off`, `blank`), a comment and a better version; words they missed; up to 3 notes on the text |
| `POST /gloss` | the words and phrases marked while reading, each with its sentence | a card for each: dictionary form, meaning in context, word or phrase, a short note |

Both take a `device`: a random ID the phone makes once, so each phone's allowance is counted on its own.

The model is `MODEL` in `wrangler.toml` (Claude Opus 5.5). Declined requests are handed on to another model with
server-side fallbacks (`fallbacks: "default"`); a request that's declined anyway comes back as a 422.

## Caps

Each call sets aside its whole `max_tokens` (thinking counts as output) and a token per character of its input plus
2,000, then keeps only what it really used. The daily caps are in `wrangler.toml`: per phone at most about $3.60 a day,
everyone together about $7.20, if someone found the URL and spent it all. Real use is far below: checking a 30-line
reading costs about 7 cents, a gloss of 20 words about 4.

The backstop is the workspace's spend limit in the Anthropic Console.

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

## Errors the app sees

| Status | Body | Meaning |
|---|---|---|
| 400 | `bad_request` | Over the request limits (80 lines of 600 characters, 40 marked words) |
| 429 | `budget` | This phone, or everyone, is out for today |
| 422 | `refused` | Claude declined |
| 502 | `too_long`, `bad_reply`, `upstream` | Reply cut off or malformed, or the API call failed |
| 503 | `busy` | Anthropic rate limit or overload |

When Claude can't answer (any error but a 422, or offline), the app asks Apple's on-device model instead, on phones
that have Apple Intelligence.

## Not yet

- **App Attest.** Anyone who finds the URL can call it, inside the caps above. Before Lecturas with Claude goes to
  everyone on the App Store, the Worker should check App Attest so only the real app on a real phone gets through.
