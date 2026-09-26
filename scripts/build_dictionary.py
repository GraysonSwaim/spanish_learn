#!/usr/bin/env python3
"""Builds the dictionary Cinco ships with: ios/Cinco/Resources/dictionary.sqlite.

Sources (downloaded into --cache on first run):
  - Wiktionary's Spanish entries, as extracted by wiktextract (kaikki.org), CC BY-SA:
    meanings, gender, plurals, pronunciation, examples and conjugations.
  - Fred Jehle's conjugation database (637 verbs), CC BY-NC-SA.
  - verbecc, a rule-based conjugator (pip install verbecc), LGPL. Only its output is used.
  - FrequencyWords (OpenSubtitles 2018, top 50k), CC BY-SA: which words are common.

Every conjugated form is voted on by the three conjugation sources. A form goes into the
dictionary only when at least two of them agree; a tense with any unresolved person is left out.
Disagreements are written to scripts/dictionary_report.md.

  python3 scripts/build_dictionary.py --cache ~/Library/Caches/cinco-dictionary [--words 10000]
"""
import argparse
import csv
import json
import logging
import os
import re
import sqlite3
import unicodedata
import urllib.request
from collections import defaultdict
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ios", "Cinco", "Resources", "dictionary.sqlite")
REPORT = os.path.join(ROOT, "scripts", "dictionary_report.md")

SOURCES = {
    "kaikki-es.jsonl": "https://kaikki.org/dictionary/Spanish/kaikki.org-dictionary-Spanish.jsonl",
    "jehle.csv": "https://raw.githubusercontent.com/ghidinelli/fred-jehle-spanish-verbs/master/jehle_verb_database.csv",
    "freq.txt": "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/es/es_50k.txt",
}

# Cinco's tense keys (same as the CSV columns). Simple tenses are voted on form by form;
# compound ones are built from haber's voted tables plus the voted participle.
SIMPLE = ["presente", "preterito", "imperfecto", "futuro", "condicional", "subjuntivo",
          "subj_imperfecto", "imperativo", "imperativo_negativo"]
COMPOUND = {"perfecto": "presente", "pluscuamperfecto": "imperfecto", "futuro_perfecto": "futuro",
            "condicional_perfecto": "condicional", "subj_perfecto": "subjuntivo"}
IMPERATIVES = {"imperativo", "imperativo_negativo"}
# haber as the auxiliary of the compound tenses (its own presente has impersonal "hay" too).
HABER = {"presente": "he has ha hemos habéis han", "imperfecto": "había habías había habíamos habíais habían",
         "futuro": "habré habrás habrá habremos habréis habrán", "condicional": "habría habrías habría habríamos habríais habrían",
         "subjuntivo": "haya hayas haya hayamos hayáis hayan",
         "subj_imperfecto": "hubiera / hubiese|hubieras / hubieses|hubiera / hubiese|hubiéramos / hubiésemos|hubierais / hubieseis|hubieran / hubiesen"}
HABER = {k: v.split("|") if "|" in v else v.split(" ") for k, v in HABER.items()}

KEEP_POS = {"noun", "verb", "adj", "adv", "pron", "prep", "conj", "intj", "det", "num", "article", "contraction", "phrase"}
DROP_SENSE_TAGS = {"form-of", "alt-of", "misspelling", "obsolete", "archaic", "abbreviation", "initialism", "nonstandard"}
# Labels worth showing a learner; the rest of Wiktionary's tags are grammar bookkeeping.
SHOW_TAGS = {"Mexico", "Spain", "Latin-America", "Caribbean", "Central-America", "Argentina", "Rioplatense",
             "colloquial", "slang", "vulgar", "derogatory", "formal", "informal", "figuratively", "literary",
             "rare", "dated", "reflexive", "pronominal"}


def fold(s):
    """Lowercase without accents (ñ kept), the way the app searches."""
    s = s.lower().replace("ñ", "\0")
    s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    return s.replace("\0", "ñ")


def fetch(cache):
    os.makedirs(cache, exist_ok=True)
    for name, url in SOURCES.items():
        path = os.path.join(cache, name)
        if not os.path.exists(path):
            print(f"downloading {name}…")
            urllib.request.urlretrieve(url, path)
    return {n: os.path.join(cache, n) for n in SOURCES}


# ---------- Wiktionary ----------

def person_slot(tags):
    t = set(tags)
    if "vos-form" in t or "combined-form" in t:
        return None
    num = 0 if "singular" in t else 3 if "plural" in t else None
    if num is None:
        return None
    if "first-person" in t:
        return num
    if "third-person" in t:
        return num + 2
    if "second-person" in t:
        return num + 1
    return None


def wikt_tense(tags):
    t = set(tags)
    if "combined-form" in t:
        return None
    if "imperative" in t:
        return "imperativo_negativo" if "negative" in t else "imperativo"
    if "subjunctive" in t:
        if "present" in t:
            return "subjuntivo"
        if "imperfect" in t:
            return "subj_imperfecto:se" if "imperfect-se" in t else "subj_imperfecto"
        return None
    if "indicative" in t:
        for tag, key in (("present", "presente"), ("preterite", "preterito"), ("imperfect", "imperfecto"), ("future", "futuro")):
            if tag in t:
                return key
    if "conditional" in t:
        return "condicional"
    return None


def wikt_tables(forms):
    """{tense: [set per person]} plus the participle, from a Wiktionary verb entry's forms."""
    tables = defaultdict(lambda: [set() for _ in range(6)])
    part = set()
    for f in forms:
        form, tags = f.get("form", ""), f.get("tags", [])
        # Reflexive forms keep their pronoun ("me levanto"); other multi-word forms are periphrases.
        if not form or form == "-" or " " in form and not form.startswith(("me ", "te ", "se ", "nos ", "os ", "no ")):
            continue
        if "participle" in tags and "past" in tags and (set(tags) == {"participle", "past"} or {"masculine", "singular"} <= set(tags)):
            part.add(form)
            continue
        k = wikt_tense(tags)
        p = person_slot(tags)
        if k and p is not None:
            if k == "imperativo_negativo" and not form.startswith("no "):
                form = "no " + form
            tables[k][p].add(form)
    return dict(tables), part


def clean_gloss(g):
    return re.sub(r"\s+", " ", g).strip()


def read_wiktionary(path, wanted):
    """Lemma entries for the words in `wanted`, plus form-of links (form -> lemmas) for ranking and lookup."""
    lemmas = defaultdict(list)       # word -> [entry dict per part of speech]
    form_of = defaultdict(set)       # inflected form -> lemma words
    with open(path, encoding="utf-8") as f:
        for line in f:
            d = json.loads(line)
            if d.get("lang_code") != "es":
                continue
            word, pos = d.get("word", ""), d.get("pos", "")
            if word not in wanted:
                continue
            senses = []
            for s in d.get("senses", []):
                tags = set(s.get("tags") or [])
                if s.get("form_of"):
                    for t in s["form_of"]:
                        if t.get("word") and t["word"] != word:
                            form_of[word].add(t["word"])
                    continue
                # Short forms learners meet constantly (mi, tu, gran, buen) are "alt-of" entries; keep them.
                short_form = bool(tags & {"apocopic", "contraction"})
                if not s.get("glosses") or not short_form and (tags & DROP_SENSE_TAGS or s.get("alt_of")):
                    continue
                gloss = clean_gloss(s["glosses"][-1])
                if short_form:
                    gloss = re.sub(r"^(apocopic form|contraction) of ([^,;:(“]+)[,;:]?\s*", lambda m: "" if m.end() < len(gloss) else f"short for {m.group(2).strip()}", gloss)
                    gloss = re.sub(r"^\(“(.*)”\)$", r"\1", gloss) or gloss
                # Letter names ("the name of the letter D") would make "de" a noun.
                if not gloss or re.match(r"(the )?name of the (Latin[- ]script )?letter", gloss, re.I):
                    continue
                # Short words are also letter and note names (mi: the Greek letter mu; la: the note A).
                if pos == "noun" and len(word) <= 3 and (gloss == word or re.search(r"\bletter\b|musical note|\bsolf", gloss, re.I)):
                    continue
                exs = [(e["text"], e.get("translation") or e.get("english"))
                       for e in (s.get("examples") or [])
                       if e.get("type", "example") == "example" and (e.get("translation") or e.get("english"))
                       and len(e["text"]) <= 110 and "collocation" not in (e.get("tags") or [])]
                senses.append({"g": gloss, "t": sorted(tags & SHOW_TAGS), "ex": exs[:2],
                               "gender": "f" if "feminine" in tags and "masculine" not in tags
                               else "m" if "masculine" in tags and "feminine" not in tags
                               else "mf" if {"masculine", "feminine"} <= tags else ""})
            if pos not in KEEP_POS or not senses or word != word.lower() and pos != "pron":
                continue
            forms = d.get("forms", [])
            ipa = next((s["ipa"] for s in d.get("sounds", []) if s.get("ipa", "").startswith("/")), "")
            plural = next((f["form"] for f in forms if f.get("tags") == ["plural"]), "")
            fem = next((f["form"] for f in forms if set(f.get("tags", [])) == {"feminine"} or set(f.get("tags", [])) == {"feminine", "singular"}), "")
            e = {"pos": pos, "senses": senses, "ipa": ipa, "plural": plural, "fem": fem}
            if pos == "verb":
                e["tables"], e["part"] = wikt_tables(forms)
            lemmas[word].append(e)
    return lemmas, form_of


# ---------- Jehle and verbecc ----------

JEHLE = {("Indicativo", "Presente"): "presente", ("Indicativo", "Pretérito"): "preterito",
         ("Indicativo", "Imperfecto"): "imperfecto", ("Indicativo", "Futuro"): "futuro",
         ("Indicativo", "Condicional"): "condicional", ("Subjuntivo", "Presente"): "subjuntivo",
         ("Subjuntivo", "Imperfecto"): "subj_imperfecto",
         ("Imperativo Afirmativo", "Presente"): "imperativo", ("Imperativo Negativo", "Presente"): "imperativo_negativo",
         ("Indicativo", "Pretérito perfecto"): "perfecto", ("Indicativo", "Pluscuamperfecto"): "pluscuamperfecto",
         ("Indicativo", "Futuro perfecto"): "futuro_perfecto", ("Indicativo", "Condicional perfecto"): "condicional_perfecto",
         ("Subjuntivo", "Pretérito perfecto"): "subj_perfecto", ("Subjuntivo", "Pluscuamperfecto"): "subj_pluscuamperfecto"}


def read_jehle(path):
    verbs = defaultdict(lambda: {"tables": {}, "part": set(), "en": ""})
    with open(path, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            k = JEHLE.get((r["mood"], r["tense"]))
            if not k:
                continue
            v = verbs[r["infinitive"]]
            v["en"] = r["infinitive_english"]
            v["tables"][k] = [{x.strip()} if x.strip() else set() for x in
                              (r[c] for c in ("form_1s", "form_2s", "form_3s", "form_1p", "form_2p", "form_3p"))]
            v["part"] = {r["pastparticiple"].strip()}
    return verbs


VERBECC = {("indicativo", "presente"): "presente", ("indicativo", "pretérito-perfecto-simple"): "preterito",
           ("indicativo", "pretérito-imperfecto"): "imperfecto", ("indicativo", "futuro"): "futuro",
           ("condicional", "presente"): "condicional", ("subjuntivo", "presente"): "subjuntivo",
           ("subjuntivo", "pretérito-imperfecto-1"): "subj_imperfecto",
           ("subjuntivo", "pretérito-imperfecto-2"): "subj_imperfecto:se",
           ("imperativo", "afirmativo"): "imperativo", ("imperativo", "negativo"): "imperativo_negativo"}
PRONOUN_SLOT = {"yo": 0, "tú": 1, "él": 2, "usted": 2, "nosotros": 3, "vosotros": 4, "ellos": 5, "ustedes": 5}


class Verbecc:
    def __init__(self):
        logging.disable(logging.CRITICAL)
        from verbecc import CompleteConjugator
        self.c = CompleteConjugator(lang="es")

    def tables(self, verb):
        try:
            d = json.loads(json.dumps(self.c.conjugate(verb).get_data(), default=lambda o: getattr(o, "__dict__", str(o))))
        except Exception:
            return {}, set(), False
        out = {}
        for (m, t), key in VERBECC.items():
            rows = d["moods"].get(m, {}).get(t)
            if not rows:
                continue
            slots = [set() for _ in range(6)]
            for r in rows:
                p = PRONOUN_SLOT.get(r.get("pr"))
                if p is None:
                    continue
                for c in r["c"]:
                    words = c.split(" ")
                    if words[0] == r.get("pr"):
                        words = words[1:]
                    slots[p].add(" ".join(words))
            out[key] = slots
        part = {x for x in d["moods"].get("participo", {}).get("participo", [{}])[0].get("c", [])[:1]}
        return out, part, d["verb"].get("predicted", False)


# ---------- voting ----------

def vote(cands):
    """cands: {source: set of forms}. Returns (form or None, unanimous)."""
    present = {s: f for s, f in cands.items() if f}
    count = defaultdict(set)
    for s, forms in present.items():
        for f in forms:
            count[f].add(s)
    agreed = [f for f, ss in count.items() if len(ss) >= 2]
    if not agreed:
        return None, False
    # Prefer Jehle's spelling when it is confirmed, then the most-backed form.
    agreed.sort(key=lambda f: (-len(count[f]), "jehle" not in count[f], f))
    return agreed[0], len(present) == 3 and len(count[agreed[0]]) == 3


def ra_to_se(f):
    return re.sub(r"ra(s|mos|is|n)?$", lambda m: "se" + (m.group(1) or ""), f).replace("ramos", "semos")


def build_verb(word, wikt, jehle, vbc, stats, issues):
    """Voted tables in Cinco's format ("a|b|c|d|e|f"), or {} when nothing could be confirmed."""
    w_tab, w_part = wikt
    v_tab, v_part, predicted = vbc
    j = jehle or {"tables": {}, "part": set()}
    out = {}
    for key in SIMPLE + ["subj_imperfecto:se"]:
        forms, ok = [], True
        for p in range(6):
            if key in IMPERATIVES and p == 0:
                forms.append("")
                continue
            if key == "subj_imperfecto:se":
                ra = out.get("subj_imperfecto", [""] * 6)[p]
                jehle_side = {ra_to_se(ra)} if ra else set()
            else:
                jehle_side = j["tables"].get(key, [set()] * 6)[p]
            cands = {"jehle": jehle_side,
                     "wiktionary": w_tab.get(key, [set()] * 6)[p],
                     "verbecc": v_tab.get(key, [set()] * 6)[p]}
            if not any(cands.values()):
                ok = False
                break
            f, unanimous = vote(cands)
            stats["slots"] += 1
            if f is None:
                stats["unresolved"] += 1
                issues.append((word, key, p, cands, None))
                ok = False
                forms.append("")
                continue
            dissent = any(c and f not in c for c in cands.values())
            if unanimous:
                stats["unanimous"] += 1
            elif dissent:
                stats["majority"] += 1
                issues.append((word, key, p, cands, f))
            else:
                stats["two"] += 1
            forms.append(f)
        if ok:
            out[key] = forms
    se = out.pop("subj_imperfecto:se", None)
    if "subj_imperfecto" in out and se:
        out["subj_imperfecto"] = [f"{a} / {b}" if a and b else a for a, b in zip(out["subj_imperfecto"], se)]
    # Some verbs have two participles (bendecido/bendito, imprimido/impreso) and the other sources may
    # list only the adjective; Jehle gives the one the compound tenses use.
    jp = next(iter(j["tables"].get("perfecto", [set()])[0]), "")
    if jp.startswith("he "):
        part = jp.removeprefix("he ")
    elif j["part"]:
        part = next(iter(j["part"]))
    else:
        part, _ = vote({"jehle": j["part"], "wiktionary": w_part, "verbecc": v_part})
    return out, part


REFLEXIVE = ["me", "te", "se", "nos", "os", "se"]


def compound(verb, tables, part, haber):
    """haber + participle; reflexive verbs put their pronoun first (me he levantado)."""
    if not part or "presente" not in tables:
        return
    pro = REFLEXIVE if verb.endswith("se") else [""] * 6
    def form(p, h):
        return " / ".join(f"{pro[p]} {x} {part}".strip() for x in h.split(" / "))
    for key, base in list(COMPOUND.items()) + [("subj_pluscuamperfecto", "subj_imperfecto")]:
        tables[key] = [form(p, h) for p, h in enumerate(haber[base])]


# ---------- main ----------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.expanduser("~/Library/Caches/cinco-dictionary"))
    ap.add_argument("--words", type=int, default=10000)
    a = ap.parse_args()
    src = fetch(a.cache)

    freq = {}
    with open(src["freq.txt"], encoding="utf-8") as f:
        for line in f:
            w, n = line.rsplit(" ", 1)
            freq.setdefault(w, int(n))
    print(f"frequency list: {len(freq)} words")

    lemmas, form_of = read_wiktionary(src["kaikki-es.jsonl"], set(freq) | {"haber"})
    print(f"wiktionary: {len(lemmas)} lemmas, {len(form_of)} inflected forms in the frequency list")

    # A word's score is its own count plus its share of its inflected forms' counts.
    score = defaultdict(float)
    for w, n in freq.items():
        if w in lemmas:
            score[w] += n
        elif form_of.get(w):
            targets = [t for t in form_of[w] if t in lemmas]
            for t in targets:
                score[t] += n / len(targets)
    ranked = sorted((w for w in score if w in lemmas), key=lambda w: -score[w])[: a.words]
    rank = {w: i + 1 for i, w in enumerate(ranked)}
    print(f"kept the top {len(ranked)} words")

    jehle = read_jehle(src["jehle.csv"])
    vbc = Verbecc()
    stats = defaultdict(int)
    issues = []
    verb_tables = {}
    verbs = [w for w in ranked if any(e["pos"] == "verb" for e in lemmas[w])]
    if "haber" not in verbs:
        verbs.insert(0, "haber")
    for w in ["haber"] + [v for v in verbs if v != "haber"]:
        wikt = next(((e["tables"], e["part"]) for e in lemmas.get(w, []) if e["pos"] == "verb" and e["tables"]), ({}, set()))
        tables, part = build_verb(w, wikt, jehle.get(w), vbc.tables(w), stats, issues)
        compound(w, tables, part, HABER)
        if "presente" in tables:
            verb_tables[w] = tables
    print(f"verbs: {len(verb_tables)} of {len(verbs)} have confirmed tables; slots {dict(stats)}")

    # Jehle's own compound tables check the ones built from haber.
    compound_mismatch = []
    for w, t in verb_tables.items():
        for key in list(COMPOUND) + ["subj_pluscuamperfecto"]:
            jt = jehle.get(w, {}).get("tables", {}).get(key)
            if jt and key in t:
                for p in range(6):
                    mine = t[key][p].split(" / ")[0]
                    if jt[p] and mine and mine not in jt[p]:
                        compound_mismatch.append((w, key, p, mine, next(iter(jt[p]))))

    if os.path.exists(OUT):
        os.remove(OUT)
    db = sqlite3.connect(OUT)
    db.executescript("""
        CREATE TABLE entry(id INTEGER PRIMARY KEY, word TEXT NOT NULL, fold TEXT NOT NULL, rank INTEGER NOT NULL,
                           pos TEXT NOT NULL, gender TEXT, plural TEXT, fem TEXT, ipa TEXT,
                           senses TEXT NOT NULL, tenses TEXT, en_fold TEXT NOT NULL);
        CREATE TABLE form(fold TEXT NOT NULL, entry INTEGER NOT NULL);
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
    """)
    n_forms = 0
    for w in ranked:
        entries = lemmas[w]
        senses = []
        for e in entries:
            for s in e["senses"][:6]:
                senses.append({"pos": e["pos"], "g": s["g"], "t": s["t"], "gender": s["gender"],
                               "ex": [{"es": es, "en": en} for es, en in s["ex"]]})
        noun = next((e for e in entries if e["pos"] == "noun"), None)
        gender = next((s["gender"] for s in senses if s["pos"] == "noun" and s["gender"]), "")
        first = entries[0]
        tables = verb_tables.get(w)
        db.execute("INSERT INTO entry VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                   (rank[w], w, fold(w), rank[w], ",".join(dict.fromkeys(e["pos"] for e in entries)), gender,
                    noun["plural"] if noun else "", next((e["fem"] for e in entries if e["pos"] == "adj"), ""),
                    first["ipa"] or next((e["ipa"] for e in entries if e["ipa"]), ""),
                    json.dumps(senses, ensure_ascii=False, separators=(",", ":")),
                    json.dumps({k: "|".join(v) for k, v in tables.items()}, ensure_ascii=False, separators=(",", ":")) if tables else None,
                    fold(" ; ".join(s["g"] for s in senses))))
        # Inflected forms that lead back here: conjugations, plurals, feminines.
        fs = set()
        if tables:
            for key in SIMPLE:
                for f in tables.get(key, []):
                    for alt in f.split(" / "):
                        fs.add(fold(alt.removeprefix("no ").split(" ")[-1]))
        for e in entries:
            if e["plural"]:
                fs.add(fold(e["plural"]))
            if e["fem"]:
                fs.add(fold(e["fem"]))
        fs.discard(fold(w))
        fs.discard("")
        db.executemany("INSERT INTO form VALUES (?,?)", [(f, rank[w]) for f in fs])
        n_forms += len(fs)
    db.executescript("""
        CREATE INDEX entry_fold ON entry(fold);
        CREATE INDEX form_fold ON form(fold);
    """)
    db.executemany("INSERT INTO meta VALUES (?,?)", [
        ("built", date.today().isoformat()),
        ("credits", "Definiciones: Wiktionary (CC BY-SA), vía kaikki.org. Conjugaciones: Fred Jehle (CC BY-NC-SA), "
                    "Wiktionary y verbecc, contrastadas entre sí. Frecuencia: FrequencyWords / OpenSubtitles (CC BY-SA)."),
    ])
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"wrote {OUT}: {len(ranked)} entries, {n_forms} forms, {os.path.getsize(OUT) / 1e6:.1f} MB")

    write_report(stats, issues, compound_mismatch, len(verb_tables), len(verbs), [v for v in verbs if v not in verb_tables])


def write_report(stats, issues, compound_mismatch, n_ok, n_verbs, missing):
    names = ["yo", "tú", "él", "nosotros", "vosotros", "ellos"]
    total = stats["slots"] or 1
    L = ["# Dictionary cross-check", "",
         f"Built {date.today().isoformat()} by `scripts/build_dictionary.py`. Each conjugated form was voted on by "
         "Fred Jehle's database, Wiktionary and verbecc, and kept only when two agree. For the -se imperfect "
         "subjunctive, which Jehle lacks, the third vote is the -ra form with its ending swapped. Compound tenses are "
         "haber plus the voted participle, then compared with Jehle's own.", "",
         f"- Verbs with confirmed tables: **{n_ok}** of {n_verbs}",
         f"- Forms checked: **{stats['slots']}**",
         f"- All three agreed: **{stats['unanimous']}** ({100 * stats['unanimous'] / total:.1f}%)",
         f"- Only two sources had the form, and they agreed: **{stats['two']}** ({100 * stats['two'] / total:.1f}%)",
         f"- Two agreed, the third differed (majority kept): **{stats['majority']}** ({100 * stats['majority'] / total:.1f}%)",
         f"- No two agreed (tense left out): **{stats['unresolved']}** ({100 * stats['unresolved'] / total:.1f}%)",
         f"- Compound tenses that differ from Jehle's: **{len(compound_mismatch)}**",
         f"- Verbs left without tables (their present tense wasn't confirmed): {', '.join(sorted(missing)) or 'none'}", ""]
    unresolved = [i for i in issues if i[4] is None]
    outvoted = [i for i in issues if i[4] is not None]
    by_source = defaultdict(int)
    for w, k, p, c, f in outvoted:
        for s, forms in c.items():
            if forms and f not in forms:
                by_source[s] += 1
    L += ["## Which source was outvoted", ""] + [f"- {s}: {n}" for s, n in sorted(by_source.items(), key=lambda x: -x[1])] + [""]

    def row(w, k, p, c):
        return f"| {w} | {k} | {names[p]} | " + " | ".join(", ".join(sorted(c[s])) or "—" for s in ("jehle", "wiktionary", "verbecc")) + " |"

    L += ["## No agreement (left out of the dictionary)", "", "| verb | tense | person | Jehle | Wiktionary | verbecc |", "|---|---|---|---|---|---|"]
    L += [row(w, k, p, c) for w, k, p, c, _ in unresolved[:400]]
    if len(unresolved) > 400:
        L.append(f"\n…and {len(unresolved) - 400} more.")
    L += ["", "## Jehle outvoted (the Jehle verbs only)", "", "| verb | tense | person | Jehle | Wiktionary | verbecc | kept |", "|---|---|---|---|---|---|---|"]
    L += [row(w, k, p, c) + f" {f} |" for w, k, p, c, f in outvoted if c["jehle"] and f not in c["jehle"]]
    L += ["", "## Compound tenses differing from Jehle's", "", "| verb | tense | person | built | Jehle |", "|---|---|---|---|---|"]
    L += [f"| {w} | {k} | {names[p]} | {m} | {j} |" for w, k, p, m, j in compound_mismatch[:200]]
    with open(REPORT, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print(f"wrote {REPORT}")


if __name__ == "__main__":
    main()
