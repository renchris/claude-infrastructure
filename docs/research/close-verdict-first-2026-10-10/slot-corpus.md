# Slot corpus: question (d). Do verdict closes lead with a line 1 that reads as done?

**Measured 2026-10-10T16:25Z** by `python3 -I /tmp/cvf-corpus/measure.py --days 30 --json /tmp/cvf-corpus/rows.json`
(the script is copied in full at the end, sha256 `c526422b…66dee3`).
**Window:** closes with message timestamp from 2026-09-10T16:25Z to 2026-10-10T16:25Z. The closes actually found run from 2026-09-10T16:42Z to 2026-10-10T16:15Z.
Every figure below is **measured** by that command unless it is labelled otherwise, and it decays with the corpus. Re-run the script; do not quote these numbers later.

## 1. Where the close-shape.sh figures came from

- `hooks/lib/close-shape.sh` (header at lines ~46 and ~60, plus the `close_shape_reason` printf) cites "613 closes", "73.4%", "48 of 313 ✅ answer no", "17.6% no rung glyph", "90.7% last line" and "1.1% at position ≤3". It points to `docs/research/close-shape-2026-08-23.md § M3`, but **there is no § M3**. The figures sit in **§ R4** (lines 110-135) and in the falsifier and "not built" sections (lines 221 and 243). All of them landed in commit `eff291df6` (2026-08-23, "W3: slots and a store").
- **The committed instrument cannot reproduce them.** `scripts/measure-closes.py` (1349 lines) has no verdict parsing, no rung-to-verdict cross-tab and no verdict-position metric. It measures act lines, length, structure and ACTED/ASKED. `git grep "73.4\|rung predicts" -- scripts` returns nothing. The R4 figures came from an uncommitted lane script, and §R4 states neither the window nor the denominator. In particular it does not say whether "73.4%" counts closes with no glyph as misses. The R4 figures are therefore unreproducible, which is the failure the doc itself warned about ("re-run it, do not quote it").
- `measure-closes.py` also walks only **four** roots and misses `~/.claude-next4/projects`. Today that root has only 2 in-window files (measured), so the effect is negligible, but the root list is stale.
- "613 currently-compliant closes" was the August population, before the template moved the verdict to line 2. The header's premise ("only 1.1% put the verdict at position ≤3, so the window ships OFF") **has since inverted** (see §3).

## 2. Method (what measure.py does)

- **Roots:** `~/.claude`, `-secondary`, `-tertiary`, `-quaternary`, `-next4` `/projects`, deduped by realpath. `~/.claude-next/projects` resolves to `~/.claude/projects` and is skipped. Files are `<root>/<project>/*.jsonl` with mtime in the window: 1575 + 517 + 1268 + 1559 + 2 = **4,921 transcripts**.
- **Records:** main chain only (`isSidechain` true is skipped). Consecutive assistant records that share one `message.id` are merged and their text blocks joined.
- **Close:** a message group with text, no `tool_use` and a non-`<synthetic>` model, whose next main-chain record is neither an assistant record nor a tool_result. Its timestamp must fall in the window.
- **Verdict close:** an unfenced line matches `/good\s+to\s+close\s*:/i` with a value that is not a `<placeholder>`. The first such line counts. Verdict is `yes` or `no` when the value, stripped of `*` and backticks, starts with `yes|yep|yeah` or `no|not`; anything else is `other`.
- **Dedup:** global by `message.id`. **194** duplicates were dropped, because transcripts are copied between account roots.
- **Line 1:** the first non-blank unfenced line. Its leading glyph is checked after stripping the markdown lead (`#>*-•` and backticks).
- **Done-tokens:** checked on line 1. **Raw** means any of `\bcomplete`, `nothing to do`, `safe to close`, `\ball done\b`, `\blanded\b`, or a leading yes-word after the glyph. **Strict** additionally drops a hit when a negator (`not|no|none|never|nothing|yet to|n't`) appears in the 30 characters before it. Sampling showed raw `landed` is mostly "Committed, not landed" or "None … landed yet". Raw over-counts; strict is the honest figure.
- **Position:** the 1-based index of the verdict line among non-blank unfenced lines. "Last" means it equals the line count.
- **Rung predicts verdict:** ✅ predicts `yes`; any other rung glyph (⛔📤🔧📦🚀👤) predicts `no`. The 4 `other` verdicts are excluded, and so are closes with no rung glyph. Their rate is reported separately and is not scored as a miss. Two rung sources are reported: (a) line 1's leading glyph, and (b) the first rung glyph anywhere in the text (`measure-closes.py` `rung_of`, which is the August method).
- **Two populations:** ALL turn-final closes, and UNBLOCKED closes, meaning those whose next record is not a `Stop hook feedback:` message. The operator sees both kinds, because a blocked close is still rendered.

## 3. Results

| figure | ALL | UNBLOCKED |
|---|---|---|
| verdict closes | **5,017** | 3,709 |
| verdict = yes / no / other | 1,724 / **3,289** / 4 | 1,401 / 2,304 / 4 |
| **verdict=no AND line 1 leads with ✅** (the screenshot defect) | **264 / 3,289 = 8.0%** | 220 / 2,304 = 9.5% |
| verdict=no AND any raw done-token in line 1 | 800 / 3,289 = 24.3% | 558 / 2,304 = 24.2% |
| verdict=no AND a strict (non-negated) done-token in line 1 | **510 / 3,289 = 15.5%** | 398 / 2,304 = 17.3% |
| verdict=no AND (✅ OR strict done-token) | **534 / 3,289 = 16.2%** | 413 / 2,304 = 17.9% |
| verdict position 1 / 2 / 3 / 4+ | 32 (0.6%) / **4,054 (80.8%)** / 385 (7.7%) / 546 (10.9%) | 28 / 3,042 (82.0%) / 251 / 388 |
| verdict is the last non-blank line | 645 = 12.9% | 454 = 12.2% |
| verdict at position ≤3 | **4,471 = 89.1%** | 3,321 = 89.5% |
| rung predicts verdict, line-1 glyph | **3,343 / 4,005 = 83.5%** (no glyph: 1,008 / 5,013 = 20.1%) | 2,487 / 3,006 = 82.7% (18.9%) |
| rung predicts verdict, first glyph anywhere | 3,716 / 4,461 = 83.3% (no glyph: 552 / 5,013 = 11.0%) | 2,709 / 3,289 = 82.4% (11.2%) |
| ✅ closes (line-1 glyph) answering no | **264 / 1,315 = 20.1%** | 220 / 1,114 = 19.7% |
| **verdict=yes whose line 1 starts with neither ✅ nor a yes-word** | **640 / 1,724 = 37.1%** | 482 / 1,401 = 34.4% |

**Line-1 leading glyph by verdict (ALL):**
- verdict=no: 📦 866, none 703, ⛔ 696, 🔧 453, 👤 264, ✅ 264, other glyph 30, 🚀 13.
- verdict=yes: ✅ 1051, none 269, 👤 237, 🔧 64, 📦 57, ⛔ 38, other 6, 🚀 2.
- The 640 verdict=yes closes that do not lead with yes break down as: none 245, 👤 229, 🔧 64, 📦 57, ⛔ 37, other 6, 🚀 2.

**Raw done-token breakdown, verdict=no line 1 (ALL):** landed 592, complete 237, nothing to do 37, leading yes 12, safe to close 7.
**Strict breakdown:** landed 312, complete 232, nothing to do 37, leading yes 12.

**Secondary cuts** (measured by a one-off `python3 -I -c` over `rows.json`, which is not part of measure.py):
- Of the 264 ✅/no closes, **261 have the verdict at position 2**. They are exactly the shape the rule asks for, and the screenshot defect is that shape working as specified. 186 of the 264 contain "Complete & live" and 37 contain "nothing to do".
- Of the 510 strict-done verdict=no closes, 240 lead with ✅ and **135 with 👤**. 113 of the 510 match `my side is (done|landed)`, which is the wrap-ledger 👤 readout wording.

**Validation (sampled by hand, estimated):**
- 12 random ✅/no closes were all genuine "git clean, but something is still pending" closes, the same pattern as the screenshot.
- 4 `other` verdicts: 2 are "✅ Yes, it's good to close: …" (a yes, misclassified because the colon follows "close"), and 2 are prose with no verdict value. The effect is negligible.

### What this says about the designs (inference from the counts, not measured)

- The defect is **not** a placement violation. The verdict is already on line 2 in 81% of closes. The problem is that line 1 is a rung, and a ✅ rung under a "no" verdict reads as done. That happens to 1 in 5 ✅ closes and to 1 in 12 "no" verdicts.
- **Design B** (forbid a done-reading line 1 when the verdict is no) using a token list would also catch the ledger's own 👤 readout, "My side is done & landed" (113 hits), and negated phrasing like "not landed" (282 raw-only hits, 592 − 312 by the raw/strict counts above). That is a false-FAIL surface on honest closes. A glyph-only B check, "✅ on line 1 AND verdict=no → block", has a clean 264-close target and no token ambiguity.
- **Design A or C** (verdict first) would move the verdict from position 2 to position 1 for about 4,054 closes. That is a template change, not a hook relaxation. The current D6 `line-1-rung` arm (line 1 must contain `$RUNG`) would have to accept the rung on line 2 or inside a `ledger:` clause, or it would false-FAIL every verdict-first close.
- 37% of "yes" closes do not lead with ✅ or yes (229 of them lead with 👤). A verdict-first line would make those readable at a glance too.

## 4. Recommendation for hooks/lib/close-shape.sh

Replace the 613-close numbers. Do not re-quote new ones in the hook's runtime reason string.

1. **The `close_shape_reason` printf**, which is shown to the model on every block: remove all corpus numbers. Keep only the claims about the mechanism, for example: "the verdict is not derivable from the rung: a ✅ close can still be 'no', and that is the case the operator misreads." A number inside a block message decays with every close and cannot be re-checked by the reader. The current one is already wrong in both directions (73% has become 83%, and "90.7% bury it last" has become 12.9%).
2. **The header comments:** re-scope with a date and the instrument, for example "Measured 2026-10-10 over 5,017 verdict closes, 2026-09-10..10-10, five roots: rung predicts verdict 83.5% (line-1 glyph); 264/1,315 ✅ closes answer no; the verdict is already at position 2 in 80.8% and ≤3 in 89.1%. Re-run: scripts/<committed copy of measure.py> --days 30." Also fix the dead pointer from `§ M3` to `§ R4`.
3. **The `CC_VERDICT_WINDOW` rationale** ("only 1.1% … at ≤3, so it ships OFF") is now false: 89.1% of verdict closes are at ≤3. Either delete the rationale, or re-justify the OFF default on new grounds. Turning a window of 3 on today would still fail about 546 of 5,017 closes (10.9%, the 4+ bucket, measured). Whether those are honest is not measured.
4. **Commit `measure.py`** (for example as `scripts/measure-close-verdicts.py`), or fold its verdict cross-tab into `scripts/measure-closes.py`. Add `~/.claude-next4/projects` to that script's `ROOTS`. Then every remaining figure has an instrument in the tree, unlike §R4.

## 5. Script (verbatim copy of /tmp/cvf-corpus/measure.py)

```python
#!/usr/bin/env python3
"""
cvf slot-corpus measure — "Good to close:" verdict closes vs their line 1.

Re-derives (does not quote) the close-shape.sh figures over the CURRENT corpus.

Population: turn-final main-agent assistant text messages (text blocks joined
within one message.id; no tool_use in the group; next main-chain assistant/user
record is neither an assistant record nor a tool_result), whose UNFENCED text
contains a line matching /good\s+to\s+close\s*:/i with a non-placeholder value.
Closes are deduped globally by message.id (a transcript copied between account
roots must not double-count).

Usage: python3 -I measure.py [--days 30] [--json out.json]
"""

import argparse, calendar, glob, json, os, re, sys, time
from collections import Counter
from multiprocessing import Pool

ROOTS = [
    "~/.claude/projects",
    "~/.claude-secondary/projects",
    "~/.claude-tertiary/projects",
    "~/.claude-quaternary/projects",
    "~/.claude-next4/projects",
    "~/.claude-next/projects",
]
GLYPHS = ["✅", "👤", "⛔", "📦", "🚀", "🔧"]
RUNG_ALL = (
    "⛔📤🔧📦🚀👤✅"  # measure-closes.py RUNGS, used for the anywhere-rung variant
)
RE_FENCE = re.compile(r"^\s*```")
RE_VERDICT = re.compile(r"good\s+to\s+close\s*:\s*(.*)$", re.I)
RE_LEAD_MD = re.compile(r"^[\s>#*_\-•·`|]+")
DONE_TOKENS = {
    "complete": re.compile(r"\bcomplete", re.I),
    "nothing to do": re.compile(r"nothing\s+to\s+do", re.I),
    "safe to close": re.compile(r"safe\s+to\s+close", re.I),
    "all done": re.compile(r"\ball\s+done\b", re.I),
    "landed": re.compile(r"\blanded\b", re.I),
}
RE_LEADING_YES = re.compile(r"^(yes|yep|yeah)\b", re.I)


def unfenced_nonblank(text):
    out, fence = [], False
    for raw in text.split("\n"):
        if RE_FENCE.match(raw):
            fence = not fence
            continue
        if fence or not raw.strip():
            continue
        out.append(raw)
    return out


def strip_lead(line):
    """Drop markdown lead (#, >, *, -, bullets, backticks) and whitespace."""
    return RE_LEAD_MD.sub("", line).strip()


def lead_glyph(line):
    s = strip_lead(line)
    for g in GLYPHS:
        if s.startswith(g):
            return g
    if s and not s[0].isalnum() and ord(s[0]) > 0x2000:
        return "other:" + s[0]
    return "none"


def after_glyph(line):
    s = strip_lead(line)
    if s and not s[0].isalnum():
        s = s[1:].lstrip("️").strip()
        s = RE_LEAD_MD.sub("", s).strip()
    return s


def verdict_value(v):
    v = v.replace("*", "").replace("`", "").strip()
    if re.match(r"^<.*>$", v):
        return None  # template placeholder — a mention, not a use
    lv = v.lower()
    if re.match(r"^(yes|yep|yeah)\b", lv):
        return "yes"
    if re.match(r"^(no|not)\b", lv):
        return "no"
    return "other"


def rung_anywhere(text):
    best, bp = None, None
    for g in RUNG_ALL:
        p = text.find(g)
        if p >= 0 and (bp is None or p < bp):
            best, bp = g, p
    return best


def msg_text(rec):
    c = (rec.get("message") or {}).get("content")
    if isinstance(c, str):
        return c, False, False
    if not isinstance(c, list):
        return "", False, False
    t, tool, tr = [], False, False
    for b in c:
        if not isinstance(b, dict):
            continue
        ty = b.get("type")
        if ty == "text":
            t.append(b.get("text") or "")
        elif ty == "tool_use":
            tool = True
        elif ty == "tool_result":
            tr = True
    return "\n".join(t), tool, tr


def scan(args):
    path, root, cutoff = args
    try:
        data = open(path, "rb").read()
    except Exception:
        return []
    if not re.search(rb"(?i)good\s+to\s+close", data):
        return []
    recs = []
    for line in data.split(b"\n"):
        if not line.strip():
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("type") in ("assistant", "user") and r.get("isSidechain") is not True:
            recs.append(r)
    # group consecutive assistant records by message.id
    seq, i = [], 0
    while i < len(recs):
        r = recs[i]
        if r["type"] == "user":
            t, _, tr = msg_text(r)
            seq.append(("user", t, tr, r))
            i += 1
            continue
        mid = (r.get("message") or {}).get("id")
        j = i + 1
        while (
            mid is not None
            and j < len(recs)
            and recs[j]["type"] == "assistant"
            and (recs[j].get("message") or {}).get("id") == mid
        ):
            j += 1
        texts, tool = [], False
        for k in range(i, j):
            t, tu, _ = msg_text(recs[k])
            if t:
                texts.append(t)
            tool = tool or tu
        seq.append(("assistant", "\n".join(texts), tool, recs[j - 1]))
        i = j
    out = []
    for k, (kind, text, tool, raw) in enumerate(seq):
        if kind != "assistant" or tool or not text.strip():
            continue
        if (raw.get("message") or {}).get("model") == "<synthetic>":
            continue
        nxt = seq[k + 1] if k + 1 < len(seq) else None
        if nxt is not None and (nxt[0] == "assistant" or nxt[2]):
            continue
        blocked = bool(nxt and nxt[1].lstrip().startswith("Stop hook feedback"))
        ts = raw.get("timestamp") or ""
        try:
            tsec = calendar.timegm(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S"))
        except Exception:
            tsec = os.path.getmtime(path)
        if tsec < cutoff:
            continue
        lines = unfenced_nonblank(text)
        if not lines:
            continue
        vpos, verdict = None, None
        for n, ln in enumerate(lines, 1):
            m = RE_VERDICT.search(ln)
            if not m:
                continue
            vv = verdict_value(m.group(1))
            if vv is None:
                continue
            vpos, verdict = n, vv
            break
        if vpos is None:
            continue
        l1 = lines[0]
        out.append(
            {
                "id": (raw.get("message") or {}).get("id") or raw.get("uuid"),
                "file": path,
                "root": root,
                "ts": ts,
                "blocked": blocked,
                "verdict": verdict,
                "vpos": vpos,
                "nlines": len(lines),
                "l1": l1[:300],
                "l1_glyph": lead_glyph(l1),
                "l1_tokens": [t for t, rx in DONE_TOKENS.items() if rx.search(l1)]
                + (["leading yes"] if RE_LEADING_YES.match(after_glyph(l1)) else []),
                "l1_tokens_strict": strict_tokens(l1),
                "rung_any": rung_anywhere(text),
            }
        )
    return out


RE_NEG = re.compile(r"\b(not|no|none|never|nothing|yet to)\b|n't\b", re.I)


def strict_tokens(l1):
    """Done-tokens that are NOT negated: no negator in the 30 chars before the
    hit ('not landed', 'None ... landed yet', 'isn't complete' drop out), and
    'nothing to do' / 'safe to close' only when not preceded by a negator."""
    out = []
    for t, rx in DONE_TOKENS.items():
        for m in rx.finditer(l1):
            if not RE_NEG.search(l1[max(0, m.start() - 30) : m.start()]):
                out.append(t)
                break
    if RE_LEADING_YES.match(after_glyph(l1)):
        out.append("leading yes")
    return out


def pct(a, b):
    return "%d/%d = %.1f%%" % (a, b, 100.0 * a / b) if b else "%d/0" % a


def report(rows, label):
    print("\n=== %s ===" % label)
    N = len(rows)
    vc = Counter(r["verdict"] for r in rows)
    print(
        "verdict closes: %d   yes %d  no %d  other %d"
        % (N, vc["yes"], vc["no"], vc["other"])
    )
    no = [r for r in rows if r["verdict"] == "no"]
    yes = [r for r in rows if r["verdict"] == "yes"]
    print(
        "verdict=no with ✅ leading line 1 (screenshot defect): "
        + pct(sum(r["l1_glyph"] == "✅" for r in no), len(no))
    )
    print(
        "verdict=no with ANY done-token in line 1: "
        + pct(sum(bool(r["l1_tokens"]) for r in no), len(no))
    )
    print(
        "verdict=no with ✅ on line 1 OR any done-token: "
        + pct(sum(r["l1_glyph"] == "✅" or bool(r["l1_tokens"]) for r in no), len(no))
    )
    tc = Counter(t for r in no for t in r["l1_tokens"])
    print("  done-token breakdown (verdict=no line 1):", dict(tc.most_common()))
    print(
        "verdict=no with a NON-NEGATED done-token in line 1 (strict): "
        + pct(sum(bool(r["l1_tokens_strict"]) for r in no), len(no))
    )
    print(
        "verdict=no with ✅ on line 1 OR a strict done-token: "
        + pct(
            sum(r["l1_glyph"] == "✅" or bool(r["l1_tokens_strict"]) for r in no),
            len(no),
        )
    )
    tc = Counter(t for r in no for t in r["l1_tokens_strict"])
    print("  strict done-token breakdown (verdict=no line 1):", dict(tc.most_common()))
    for v, grp in (("no", no), ("yes", yes)):
        gc = Counter(
            r["l1_glyph"] if not r["l1_glyph"].startswith("other") else "other-glyph"
            for r in grp
        )
        print("line-1 leading glyph, verdict=%s:" % v, dict(gc.most_common()))

    def bucket(r):
        return str(r["vpos"]) if r["vpos"] <= 3 else "4+"

    pc = Counter(bucket(r) for r in rows)
    print(
        "verdict line position (non-blank, unfenced): "
        + "  ".join("%s:%s" % (b, pct(pc[b], N)) for b in ("1", "2", "3", "4+"))
    )
    print(
        "verdict is the LAST non-blank line: "
        + pct(sum(r["vpos"] == r["nlines"] for r in rows), N)
    )
    print("verdict at position <=3: " + pct(sum(r["vpos"] <= 3 for r in rows), N))
    # rung predicts verdict: ✅ -> yes, any other rung -> no; 'other' verdicts excluded
    for key, nm in (
        ("l1_glyph", "line-1 leading glyph"),
        ("rung_any", "first rung glyph anywhere (measure-closes rung_of)"),
    ):
        yn = [r for r in rows if r["verdict"] in ("yes", "no")]
        has = [r for r in yn if r[key] and r[key] in RUNG_ALL]
        hit = sum((r[key] == "✅") == (r["verdict"] == "yes") for r in has)
        print(
            "rung predicts verdict [%s]: %s  (no rung glyph: %s of yes/no closes)"
            % (nm, pct(hit, len(has)), pct(len(yn) - len(has), len(yn)))
        )
        ok = [r for r in has if r[key] == "✅"]
        print(
            "   ✅ closes answering no: %s"
            % pct(sum(r["verdict"] == "no" for r in ok), len(ok))
        )
    nonyes = [
        r
        for r in yes
        if not (r["l1_glyph"] == "✅" or RE_LEADING_YES.match(after_glyph(r["l1"])))
    ]
    print(
        "verdict=yes whose line 1 starts with neither ✅ nor a yes-word: "
        + pct(len(nonyes), len(yes))
    )
    print(
        "  their line-1 glyphs:",
        dict(
            Counter(
                r["l1_glyph"]
                if not r["l1_glyph"].startswith("other")
                else "other-glyph"
                for r in nonyes
            ).most_common()
        ),
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=float, default=30)
    ap.add_argument("--json")
    a = ap.parse_args()
    now = time.time()
    cutoff = now - a.days * 86400
    seen, jobs = set(), []
    print(
        "window: closes with timestamp >= %s UTC (%g days before %s UTC)"
        % (
            time.strftime("%Y-%m-%dT%H:%MZ", time.gmtime(cutoff)),
            a.days,
            time.strftime("%Y-%m-%dT%H:%MZ", time.gmtime(now)),
        )
    )
    for r in ROOTS:
        rp = os.path.realpath(os.path.expanduser(r))
        if rp in seen or not os.path.isdir(rp):
            print(
                "  %-30s skipped (%s)"
                % (r, "alias of " + rp if rp in seen else "missing")
            )
            continue
        seen.add(rp)
        fs = [
            f
            for f in glob.glob(os.path.join(rp, "*", "*.jsonl"))
            if os.path.getmtime(f) >= cutoff
        ]
        print("  %-30s files in window: %d" % (r, len(fs)))
        jobs += [(f, r, cutoff) for f in fs]
    with Pool(8) as p:
        res = p.map(scan, jobs, chunksize=4)
    rows, ids, dup = [], set(), 0
    for lst in res:
        for row in lst:
            if row["id"] in ids:
                dup += 1
                continue
            ids.add(row["id"])
            rows.append(row)
    print(
        "transcripts scanned: %d   verdict closes: %d   duplicates dropped by message.id: %d"
        % (len(jobs), len(rows), dup)
    )
    if rows:
        print(
            "close timestamps: %s .. %s"
            % (min(r["ts"] for r in rows), max(r["ts"] for r in rows))
        )
    report(rows, "ALL turn-final verdict closes (incl. those a Stop hook then blocked)")
    report(
        [r for r in rows if not r["blocked"]],
        "UNBLOCKED only (next record is not 'Stop hook feedback')",
    )
    if a.json:
        json.dump(rows, open(a.json, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
```
