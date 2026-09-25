# Cinco card-writing skill

`cinco-cards/SKILL.md` teaches an AI assistant to write decks in the format Cinco imports, with the judgment calls that matter for a five-stage typed-recall system (short typeable Spanish, articles on nouns, one alternative per regional split, examples that carry context, frequency ordering). `cinco-cards/scripts/validate_cards.py` checks any CSV before you import it.

The file follows the open [Agent Skills](https://agentskills.io) format, so the same folder works in several tools.

## Claude Code (this Mac)

Already installed: `~/.claude/skills/cinco-cards` is a symlink to this folder, so edits here take effect immediately. Just ask in any project: *"make me 30 cards about cooking verbs, intermediate"*. Claude reads the skill, writes the CSV into your iCloud Drive `Spanish` folder if it exists, and runs the validator.

## Claude.ai (web and phone)

Upload `cinco-cards.skill` at claude.ai → Settings → Capabilities → Skills. Then any chat can produce decks. Re-package after editing the skill:

```sh
python3 -m scripts.package_skill skills/cinco-cards skills   # from the skill-creator directory
```

## ChatGPT

ChatGPT doesn't read skill files, but the body of `SKILL.md` is written to stand alone as instructions.

1. In ChatGPT, create a **Project** (or a Custom GPT) called *Cinco cards*.
2. Open `cinco-cards/SKILL.md`, copy everything **below the second `---` line** (skip the frontmatter block at the top), and paste it into the project's **Instructions**.
3. Optionally attach `decks/starter.csv` to the project as an example of the format and as a duplicate check.
4. Ask for cards. ChatGPT will either give you a downloadable `.csv` or a code block; save it as `something.csv` (UTF-8) into iCloud Drive → Spanish → vocabulario (or verbos, for a verb deck).

Before importing anything ChatGPT produced, run the validator on your Mac:

```sh
python3 skills/cinco-cards/scripts/validate_cards.py ~/Library/Mobile\ Documents/com~apple~CloudDocs/Spanish/vocabulario/something.csv --existing ~/Library/Mobile\ Documents/com~apple~CloudDocs/Spanish/{vocabulario,verbos}/*.csv
```

It reports unquoted commas, missing fields, duplicates against decks you already have, and examples that don't use their word. Errors will break the import; warnings are judgment calls.

## Codex and other tools

OpenAI Codex and several other agents read the same `SKILL.md` format. Point them at `skills/cinco-cards/` or copy it into their skills directory.
