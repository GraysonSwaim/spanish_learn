#!/usr/bin/env python3
"""Validate a Cinco flashcard CSV before importing it.

Usage: validate_cards.py deck.csv [--existing other.csv ...]

Checks the header, required fields, quoting/column counts, duplicate Spanish
(within the file and against any --existing decks), and that each example
contains its word. Exit code 1 if there are errors; warnings don't fail.
"""
import csv, io, re, sys, unicodedata

REQUIRED = ["spanish", "english"]
COLUMNS = ["spanish", "english", "example", "notes", "tags"]

def strip(s):
    s = s.lower().strip().replace("ñ", "\x01")
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return s.replace("\x01", "ñ")

def key(spanish):
    return strip(re.sub(r"[¿?¡!.,;:\"“”]", "", spanish))

def stem(word):
    """Crude stem so 'pedir' is found in 'pido' loosely: first 3 letters of the headword."""
    w = strip(re.sub(r"^(el|la|los|las|un|una)\s+", "", word.split("/")[0].split("(")[0]).strip())
    return w[:3] if len(w) > 3 else w

def read(path):
    raw = open(path, "rb").read()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        return None, ["file is not UTF-8 (re-export as CSV UTF-8 so accents survive)"]
    return text, []

def load_existing(paths):
    seen = set()
    for p in paths:
        text, _ = read(p)
        if not text:
            continue
        for row in csv.DictReader(io.StringIO(text)):
            if row.get("spanish"):
                seen.add(key(row["spanish"]))
    return seen

def main(argv):
    if len(argv) < 2:
        print(__doc__); return 2
    path = argv[1]
    existing = load_existing([a for a in argv[3:]] if len(argv) > 2 and argv[2] == "--existing" else [])
    text, errors = read(path)
    if text is None:
        print("ERROR:", errors[0]); return 1
    warnings = []
    rows = list(csv.reader(io.StringIO(text)))
    rows = [r for r in rows if any(c.strip() for c in r) and not (r and r[0].startswith("#"))]
    if not rows:
        print("ERROR: file is empty"); return 1
    header = [h.strip().lower() for h in rows[0]]
    if header[:2] != REQUIRED:
        errors.append(f"header must start with 'spanish,english' (got {','.join(rows[0])})")
        idx = {c: i for i, c in enumerate(COLUMNS)}
        body = rows
    else:
        idx = {c: header.index(c) for c in COLUMNS if c in header}
        body = rows[1:]
        for extra in set(header) - set(COLUMNS):
            warnings.append(f"unknown column '{extra}' will be ignored")
    seen, tags = {}, {}
    for n, r in enumerate(body, start=2):
        if len(r) > len(header if header[:2] == REQUIRED else COLUMNS):
            errors.append(f"line {n}: {len(r)} fields, expected {len(header)}. A comma inside a field needs quotes.")
            continue
        g = lambda c: r[idx[c]].strip() if c in idx and idx[c] < len(r) else ""
        es, en, ex, notes, tag = (g(c) for c in COLUMNS)
        if not es or not en:
            errors.append(f"line {n}: spanish and english are both required ({es!r}, {en!r})"); continue
        k = key(es)
        if k in seen:
            errors.append(f"line {n}: duplicate spanish '{es}' (also line {seen[k]})")
        seen[k] = n
        if k in existing:
            warnings.append(f"line {n}: '{es}' already exists in the deck you passed with --existing (re-import will update it, not add it)")
        if len(es.split()) > 6:
            warnings.append(f"line {n}: spanish is long ({len(es.split())} words); the learner has to type this")
        if ex and stem(es) not in strip(ex):
            warnings.append(f"line {n}: example may not contain '{es}' (fine if the verb is irregular): {ex}")
        if notes and len(notes) > 100:
            warnings.append(f"line {n}: note is {len(notes)} chars; keep notes to one line")
        if tag:
            if tag != tag.lower() or " " in tag:
                warnings.append(f"line {n}: tag '{tag}' should be one lowercase word")
            tags[tag] = tags.get(tag, 0) + 1
    for e in errors: print("ERROR:", e)
    for w in warnings: print("warning:", w)
    print(f"{len(seen)} cards" + (f", tags: {', '.join(f'{t} ({c})' for t, c in sorted(tags.items()))}" if tags else "") + (", no errors" if not errors else f", {len(errors)} error(s)"))
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
