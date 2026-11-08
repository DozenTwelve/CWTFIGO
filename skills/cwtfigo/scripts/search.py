#!/usr/bin/env python3
"""Search the owner's own cases from past visits, plus the archive of facts extracted from public bug threads
(GitHub issues and discussions) if one was built here, ranked together by BM25 against the query, own cases boosted.
Runs on the operator machine, reads only local files.

  search.py [-n N] <words...>      N threads or cases (default 5), each with its facts and link

Each hit shows its tracker state and the ending derived from its facts (fixed, worked around, stopped,
duplicate), e.g. `completed → stopped`. Each fact shows who said it: `P<n> #<k>`, P0 the reporter,
#0 the opening post. A root cause only the opening post states is marked unconfirmed.

Archive: $CWTFIGO_ARCHIVE, default ~/.cwtfigo/archive/archive.jsonl (one JSON line per thread).
Cases: $CWTFIGO_HOME/hosts/*/cases.jsonl, same line shape; the last line per source wins.
No hit says so and appends a line to $CWTFIGO_HOME/misses.jsonl (cw miss logs the hits that didn't fit).
"""
import datetime, json, math, os, re, sys, unicodedata
from collections import Counter
from pathlib import Path


def tokens(s):
    """ASCII words, plus overlapping character pairs for CJK runs (Chinese and Japanese have no spaces): kana, ideographs,
    Hangul. NFKC first, so full-width letters and digits (ＩＰｖ６) match their ASCII forms."""
    out = []
    for w in re.findall(r"[a-z0-9_]+|[぀-ヿ㐀-鿿가-힯]+", unicodedata.normalize("NFKC", s or "").lower()):
        out += [w] if w.isascii() else [w[i:i + 2] for i in range(max(len(w) - 1, 1))]
    return out


def bm25(docs, query, k1=1.2, b=0.75, boost=None):
    """docs: {id: [tokens]}; returns ids sorted by score, best first. boost: {id: factor} on the score."""
    n = len(docs)
    avg = sum(len(d) for d in docs.values()) / max(n, 1)
    df = Counter(t for d in docs.values() for t in set(d))
    q = set(query)
    scores = {}
    for i, d in docs.items():
        tf = Counter(d)
        s = 0.0
        for t in q:
            if t in tf:
                idf = math.log(1 + (n - df[t] + 0.5) / (df[t] + 0.5))
                s += idf * tf[t] * (k1 + 1) / (tf[t] + k1 * (1 - b + b * len(d) / avg))
        scores[i] = s * (boost or {}).get(i, 1)
    return sorted(scores, key=scores.get, reverse=True)


FIXED = re.compile(r"\b(fixed|merged|released|shipped|landed|resolved in|fix(?:ed)? in)\b", re.I)
FIXPR = re.compile(r"\b(fix(?:ing)? (?:PR|pull request|commit)|linked (?:a|the) (?:fix|pull request)|"
                   r"closed (?:as completed )?by (?:PR|pull request|a commit|commit))", re.I)
NOTFIX = re.compile(r"\b(not (?:yet )?(?:fixed|merged|released)|no fix|unfixed|unresolved|never)\b", re.I)
MIXED = re.compile(  # a fix or workaround that held for some people and not for others
    r"\b(works?|worked|fixe[sd]|helped|help)( it| this| the problem)? (only )?for (one|some|a few|several|another|a second|one other|other|many) "
    r"|(did not|didn't|does not|doesn't|never) (work|help|fix\w*)( it| this| the problem)? for (one|another|some|other|a second|a third|them|everyone|all|the reporter|every)"
    r"|not for (everyone|all|others)|for others\b|others (still|reported|say|said)"
    r"|\b(another|a second|a third|other) (user|commenter|reporter)s? (still|said|says|report\w*|saw|sees|hit)\b.{0,60}\b(not|no|didn't|did not|still|without|same)\b"
    r"|mixed results|inconsistent results", re.I)
OWN_BOOST = 1.3  # relevant own cases score just under the top threads (measured); weak own matches stay far below
CASE_END = {"fixed": "fixed", "worked around": "worked around", "parked": "stopped"}


def ending(t):
    """fixed / worked around / stopped / duplicate from the thread's facts; None for a request or no facts.
    Cases say it in their state. Same rules as the 2026-11-05 corpus analysis (q5 outcome)."""
    if "host" in t:
        return CASE_END.get((t.get("state") or "").lower())
    items, kinds = t["items"], Counter(f.get("kind") for f in t["items"])
    if not items or not (kinds["symptom"] or kinds["error message"] or kinds["root cause"] or kinds["regression"]):
        return None
    fs = [f["text"] for f in items if f.get("kind") in ("fix status", "thread outcome")]
    res = [f["text"] for f in items if f.get("kind") == "resolution"
           and not (re.search(r"duplicate", f["text"], re.I) and not re.search(r"\bfix", f["text"], re.I))]
    if res or t.get("state") == "MERGED" or any((FIXED.search(x) or FIXPR.search(x)) and not NOTFIX.search(x) for x in fs):
        return "fixed"
    if kinds["workaround"]:
        return "worked around"
    return "duplicate" if t.get("state") == "DUPLICATE" or kinds["duplicate"] else "stopped"


def order(f):
    """`from` is "P<n> #<k>": k is the post, 0 the opening post. None for anything else (cases)."""
    m = re.match(r"P\d+ #(\d+)", f.get("from") or "")
    return int(m[1]) if m else None


def stones(t, end):
    """Stone-zone lines: where a fix may not come or may not hold here."""
    out = []
    if end and any(f.get("kind") in ("workaround", "caveat", "ruled out", "reproducibility", "resolution", "comparison")
                   and MIXED.search(f["text"]) for f in t["items"]):
        out.append("stone zone: a fix/workaround here worked for some and not others")
    try:
        span = (datetime.date.fromisoformat((t.get("closed") or datetime.date.today().isoformat())[:10])
                - datetime.date.fromisoformat(t["created"][:10])).days
    except ValueError:
        span = 0
    people = {f["from"].split(" #")[0] for f in t["items"] if order(f) is not None}
    if (t["source"].startswith("https://github.com/") and end in ("stopped", "worked around") and span >= 365
            and len(people) >= 3 and not any(f.get("kind") == "fix status"
                                             and re.search(r"\b(fixed|merged|released|shipped|landed)\b", f["text"], re.I)
                                             for f in t["items"])):
        out.append("stone zone: open/unfixed for over a year with several people")
    return out


def rows(f, host=None):
    """JSON lines of f, missing text fields filled in as empty. Hand-appended by the model: one broken line must
    not hide the rest or crash the search."""
    out = []
    for no, l in enumerate(f.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if not l.strip():
            continue
        try:
            t = json.loads(l)
            # A fact whose from, kind or anchor isn't text (a number, a list) is skipped: order() and Counter need text.
            t["items"] = [x for x in t.get("items") or [] if isinstance(x, dict) and isinstance(x.get("text"), str)
                          and all(x.get(k) is None or isinstance(x[k], str) for k in ("from", "kind", "anchor"))]
            t.update({k: "" for k in ("title", "created", "closed", "state") if not isinstance(t.get(k), str)})
            if not isinstance(t["source"], str):
                raise TypeError
            out.append(dict(t, host=host) if host else t)
        except (ValueError, KeyError, TypeError, AttributeError):
            print(f"search: skipping bad line {f}:{no}", file=sys.stderr)
    return out


def main(argv):
    # Windows Python writes \r\n in text mode, and in the locale's code page: every line would end in \r for whoever
    # reads it (cw, tests, the TUI), and a title the code page lacks would crash. The files are UTF-8 too.
    for s in (sys.stdout, sys.stderr):
        s.reconfigure(encoding="utf-8", newline="\n")
    n = 5
    if argv[:1] == ["-n"]:
        if len(argv) < 2 or not argv[1].isdecimal() or int(argv[1]) < 1:
            sys.exit("search: -n wants a number of hits, 1 or more")
        n, argv = int(argv[1]), argv[2:]
    if not argv:
        sys.exit(__doc__.strip())
    path = Path(os.environ.get("CWTFIGO_ARCHIVE", Path.home() / ".cwtfigo" / "archive" / "archive.jsonl"))
    threads = rows(path) if path.exists() else []
    rec = Path(os.environ.get("CWTFIGO_HOME", Path.home() / ".cwtfigo"))
    cases = {c["source"]: c for f in sorted(rec.glob("hosts/*/cases.jsonl")) for c in rows(f, f.parent.name)}
    threads += cases.values()
    if not threads:
        sys.exit("nothing to search yet: no cases in the record, no archive here")
    docs = {i: tokens(t["title"] + " " + " ".join(f["text"] + " " + str(f.get("anchor") or "") for f in t["items"]))
            for i, t in enumerate(threads)}
    query = tokens(" ".join(argv))
    own = {i: OWN_BOOST for i, t in enumerate(threads) if "host" in t}
    hits = [i for i in bm25(docs, query, boost=own) if set(docs[i]) & set(query)][:n]
    if not hits:
        try:  # the miss log must never break search
            with open(rec / "misses.jsonl", "a", encoding="utf-8") as f:
                f.write(json.dumps({"date": datetime.date.today().isoformat(), "query": " ".join(argv),
                                    "reason": "no hit", "upstream": "", "host": ""}) + "\n")
            print("no match (logged to misses.jsonl)")
        except OSError:
            print("no match")
    ends = []
    for rank, i in enumerate(hits, 1):
        t = threads[i]
        state, end = (t.get("state") or "").lower(), ending(t)
        ends.append(end)
        meta = [state if end in (None, state) else f"{state} → {end}" if state else end,
                t["created"] and f"opened {t['created']}", t["closed"] and f"closed {t['closed']}"]
        print(f"{rank}. {t['title']}  ({', '.join(m for m in meta if m)})\n   {t['source']}" + (f"  (your own visit on {t['host']})" if "host" in t else ""))
        for line in stones(t, end):
            print("   " + line)
        later = any(f.get("kind") in ("root cause", "resolution") and (order(f) or 0) > 0 for f in t["items"])
        for f in t["items"]:
            who = f.get("from") or ""
            if f.get("kind") == "root cause" and order(f) == 0 and not later:
                who += ", opening post, unconfirmed"
            tag = f.get("kind") or f.get("label")
            print(f"   - {f'[{tag}] ' if tag else ''}{f['text']}" + (f"  `{f['anchor']}`" if f.get("anchor") else "")
                  + (f"  ({who})" if who else ""))
        print()
    if sum(e in ("stopped", "worked around") for e in ends[:5]) >= 3:
        print("most matches ended stopped/around: expect a workaround or a park, not a fix")


if __name__ == "__main__":
    main(sys.argv[1:])
