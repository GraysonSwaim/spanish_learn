#!/usr/bin/env python3
"""Record every Cinco word with a macOS Spanish voice, so the app plays real audio instead of iOS speech.

    python3 scripts/make_audio.py            # record what's missing, delete what's no longer needed
    python3 scripts/make_audio.py --no-gc    # record only, never delete

Words come from:
  - every deck CSV in this repo's decks/ and in iCloud Drive/Spanish/
  - the newest Cinco backup (iCloud Drive/Spanish/backups/ or Shortcuts/Spanish/backups/),
    which covers cards typed in by hand on the phone and tells us which ones are dropped

Output is audio/es-MX/<key>.m4a plus audio/es-MX/index.json, the list the app checks before playing.
<key> is the app's hash(strip(text)) of the exact text the app speaks, so the two must stay in step:
see norm(), strip(), hash() and speak() in index.html.

Cleanup: a recording is deleted once its word is in no deck and no backup, or is dropped in the backup.
Mastered words keep their audio, since they still come back for review.
"""
import argparse, csv, io, json, os, re, subprocess, sys, tempfile, unicodedata
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ICLOUD = Path.home() / 'Library/Mobile Documents/com~apple~CloudDocs/Spanish'
SHORTCUTS = Path.home() / 'Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/Spanish'
VOICE, LANG, RATE = 'Paulina', 'es-MX', 165   # say's words per minute; the default is about 175
OUT = REPO / 'audio' / LANG
# Phrases the app speaks outside of cards (Ajustes › Acento and Ajustes › Probar sonido).
FIXED = ['Hola, ¿cómo estás?', 'Hola. ¿Me oyes bien?']

# ---- mirrors of the app's text functions ----
def norm(s):
    s = str(s).lower().strip()
    s = re.sub(r'[¿?¡!.,;:"“”…]', '', s)
    return re.sub(r'\s+', ' ', s)

def strip(s):
    s = norm(s).replace('ñ', '\x01')
    s = ''.join(c for c in unicodedata.normalize('NFD', s) if not 0x300 <= ord(c) <= 0x36f)
    return s.replace('\x01', 'ñ')

def jshash(s):
    h = 5381
    for unit in _units(s):   # JS charCodeAt works on UTF-16 code units
        h = ((h << 5) + h + unit) & 0xFFFFFFFF
    n, digits = h, '0123456789abcdefghijklmnopqrstuvwxyz'
    out = ''
    while True:
        n, r = divmod(n, 36)
        out = digits[r] + out
        if not n:
            return out

def _units(s):
    b = s.encode('utf-16-le')
    return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]

def spoken(text):
    """What speak() actually says: the first alternative, without ellipses."""
    return re.sub(r'\s*[/;].*$', '', text).replace('…', '').strip()

# ---- reading decks the way the app imports them ----
CONJ_HEADERS = {'conjugation', 'conjugación', 'conjugacion', 'conj', 'forms', 'formas'}
ES_HEADERS = {'spanish', 'es', 'español', 'espanol', 'front', 'word', 'term', 'palabra'}
KNOWN = ES_HEADERS | {'english', 'en', 'back', 'meaning', 'definition', 'translation', 'inglés', 'ingles',
                      'example', 'ex', 'sentence', 'ejemplo', 'context', 'notes', 'note', 'hint', 'notas',
                      'tags', 'tag', 'category', 'topic'} | CONJ_HEADERS

def csv_words(path):
    text = path.read_text(encoding='utf-8-sig', errors='replace')
    first = next((l for l in text.split('\n') if l.strip() and not l.startswith('#')), '')
    delim = '\t' if '\t' in first else (';' if first.count(';') > first.count(',') else ',')
    rows = [r for r in csv.reader(io.StringIO(text), delimiter=delim)
            if any(x.strip() for x in r) and not str(r[0]).startswith('#')]
    if not rows:
        return []
    head = [norm(h) for h in rows[0]]
    col, conj = 0, None
    if any(h in KNOWN for h in head):
        col = next((i for i, h in enumerate(head) if h in ES_HEADERS), 0)
        conj = next((i for i, h in enumerate(head) if h in CONJ_HEADERS), None)
        rows = rows[1:]
    words = []
    for r in rows:
        if len(r) > 1 and r[col].strip() and r[1].strip():
            words.append(r[col].strip())
            # Each form of a verb's conjugation column is a card of its own in the app's Conjugación tab.
            if conj is not None and conj < len(r):
                words += [f.strip() for f in r[conj].split('|') if f.strip()]
    return words

def newest_backup():
    found = [p for d in (ICLOUD / 'backups', SHORTCUTS / 'backups') if d.is_dir()
             for p in d.iterdir() if p.suffix in ('.json', '.txt') and 'cinco' in p.name.lower()]
    for p in sorted(found, key=lambda p: p.stat().st_mtime, reverse=True):
        try:
            data = json.loads(p.read_text(encoding='utf-8-sig').strip())
            if isinstance(data, dict) and 'cards' in data:
                return p, data
        except (ValueError, OSError):
            continue
    return None, None

def record(text, dest):
    with tempfile.TemporaryDirectory() as tmp:
        src, aiff = Path(tmp) / 'in.txt', Path(tmp) / 'out.aiff'
        src.write_text(text, encoding='utf-8')          # -f avoids text that starts with "-" being read as an option
        # say occasionally hangs forever on a phrase it read fine a moment earlier, so time out and retry.
        for attempt in range(3):
            try:
                subprocess.run(['say', '-v', VOICE, '-r', str(RATE), '-f', str(src), '-o', str(aiff)], check=True, timeout=15)
                break
            except subprocess.TimeoutExpired:
                print(f'    say hung on "{text}", retrying')
        else:
            raise SystemExit(f'say kept hanging on "{text}". Run the script again; finished recordings are kept.')
        subprocess.run(['afconvert', '-f', 'm4af', '-d', 'aac', '-b', '48000', str(aiff), str(dest)], check=True, timeout=30)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--no-gc', action='store_true', help='never delete recordings')
    args = ap.parse_args()

    words, sources = {}, []
    for d in (REPO / 'decks', ICLOUD):
        for p in sorted(d.glob('*.csv')) if d.is_dir() else []:
            for w in csv_words(p):
                words.setdefault(w, p.name)
            sources.append(str(p.relative_to(REPO) if p.is_relative_to(REPO) else p.name))
    backup, data = newest_backup()
    dropped = set()
    if data:
        for c in data['cards'].values():
            es = str(c.get('es', '')).strip()
            if not es:
                continue
            if c.get('dropped'):
                dropped.add(es)
            else:
                words.setdefault(es, 'backup')
        sources.append(f'backup {backup.name} ({len(data["cards"])} cards)')
    for es in dropped:
        words.pop(es, None)

    want = {}
    for w in list(words) + FIXED:
        t = spoken(w)
        if t:
            want.setdefault(jshash(strip(t)), t)

    OUT.mkdir(parents=True, exist_ok=True)
    have = {p.stem for p in OUT.glob('*.m4a')}
    missing = [k for k in want if k not in have]
    print(f'Sources: {", ".join(sources) or "none"}')
    print(f'{len(want)} phrases, {len(missing)} to record with {VOICE}')
    for i, k in enumerate(missing, 1):
        record(want[k], OUT / f'{k}.m4a')
        print(f'  {i}/{len(missing)}  {want[k]}')

    removed = []
    if not args.no_gc:
        if not data or len(want) <= len(FIXED):
            print('Skipping cleanup: no backup found, so words added on the phone could be deleted by mistake.')
        else:
            for k in sorted(have - set(want)):
                (OUT / f'{k}.m4a').unlink()
                removed.append(k)
            if removed:
                print(f'Removed {len(removed)} recordings no longer in any deck or backup')

    keys = sorted(p.stem for p in OUT.glob('*.m4a'))
    (OUT / 'index.json').write_text(json.dumps(keys, separators=(',', ':')) + '\n')
    print(f'{len(keys)} recordings in audio/{LANG}/')
    if not data:
        print('No backup found. Words added by hand on the phone need a backup before they get audio.')

if __name__ == '__main__':
    sys.exit(main())
