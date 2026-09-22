#!/usr/bin/env python3
"""paired.py — COPY of docs/research/opus55-effort-sweep-2026-09-22/paired.py, extended for the
review-judge follow-up: 5 arms x 3 samples, two panels. The vote rule (strict majority, >=2 of 3
judges) and the exact two-sided sign test p2() are unchanged from 09-22.

  paired.py            # every table the README quotes, from the committed score files

Panels. P1 = the standing 3x claude-opus-5 @xhigh: sample 1 is the 09-22 panel's own scores (8 outputs
per prompt), samples 2/3 are judges/scores-p1.jsonl (5 outputs per prompt). P2 = one judge per model
family (o5 = claude-opus-5 @xhigh, o55 = claude-opus-5-5 @xhigh, f51 = claude-fable-5-1 @high) on
all 3 samples, judges/scores-p2.jsonl.
"""

import json, statistics
from collections import defaultdict
from math import comb
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORPUS = HERE.parents[2] / "tests/fixtures/codex-probe"
ARMS = ["o55@high", "o55@xhigh", "o5@high", "o5@max", "f51@high"]
FAMILY = {
    "o55@high": "o55",
    "o55@xhigh": "o55",
    "o5@high": "o5",
    "o5@max": "o5",
    "f51@high": "f51",
}
S = (1, 2, 3)
man = {m["id"]: m for m in json.loads((CORPUS / "manifest.json").read_text())}
DEF = [b for b in sorted(man) if man[b]["has_defect"]]
ITEMS = [(b, i) for b in DEF for i in range(1, len(man[b]["ground_truth"]) + 1)]
N = len(ITEMS)


def p2(k, n):
    return (
        min(1.0, 2 * sum(comb(n, j) for j in range(0, min(k, n - k) + 1)) / 2**n)
        if n
        else 1.0
    )


def load(path, sample=None, judges=None):
    out = []
    if not Path(path).exists():
        return out
    for line in open(path):
        if not line.strip():
            continue
        r = json.loads(line)
        if "error" in r or r.get("arm") not in ARMS:
            continue
        if sample is not None:
            r = dict(r, sample=sample)
        if judges is None or r["judge"] in judges:
            out.append(r)
    return out


def votes(rows):
    v = defaultdict(set)
    for r in rows:
        v[(r["arm"], r["sample"], r["brief_id"])]  # touch: the cell was judged
        for g in r["credited"]:
            v[(r["arm"], r["sample"], r["brief_id"], g)].add(r["judge"])
    return v


P1 = load(
    HERE.parent / "opus55-effort-sweep-2026-09-22/runs/scores.jsonl", sample=1
) + load(HERE / "judges/scores-p1.jsonl")
P2 = load(HERE / "judges/scores-p2.jsonl")
PANELS = {"P1": votes(P1), "P2": votes(P2)}


def judged(v, a, s, b):
    return (a, s, b) in v


def hit(v, a, s, b, i, t=2):
    return len(v.get((a, s, b, i), ())) >= t


def found(v, a, b, i):
    """How many of the 3 samples found item (b, i), strict majority per sample."""
    return sum(hit(v, a, s, b, i) for s in S)


def cov(v):
    return {(a, s): sum(judged(v, a, s, b) for b in DEF) for a in ARMS for s in S}


def recall_table(name, v):
    c = cov(v)
    print(f"\n### {name} — recall /{N} per sample, strict majority\n")
    print(
        "| arm | s1 | s2 | s3 | mean | items found in >=2 of 3 | in >=1 of 3 | in 3 of 3 |"
    )
    print("|---|---|---|---|---|---|---|---|")
    for a in ARMS:
        r = [sum(hit(v, a, s, b, i) for b, i in ITEMS) for s in S]
        cells = [
            f"{x}" + ("" if c[(a, s)] == len(DEF) else f" ({c[(a, s)]}/7 briefs)")
            for x, s in zip(r, S)
        ]
        f = [found(v, a, b, i) for b, i in ITEMS]
        print(
            f"| {a} | "
            + " | ".join(cells)
            + f" | {statistics.mean(r):.1f} | **{sum(x >= 2 for x in f)}** | {sum(x >= 1 for x in f)} | {sum(x == 3 for x in f)} |"
        )


def sign(v, a, b, label):
    A = {it for it in ITEMS if found(v, a, *it) >= 2}
    B = {it for it in ITEMS if found(v, b, *it) >= 2}
    ao, bo = len(A - B), len(B - A)
    # secondary: every (item, sample) cell, discordant cells only — samples are not independent
    ca = sum(
        1 for it in ITEMS for s in S if hit(v, a, s, *it) and not hit(v, b, s, *it)
    )
    cb = sum(
        1 for it in ITEMS for s in S if hit(v, b, s, *it) and not hit(v, a, s, *it)
    )
    print(
        f"| {label} | {a} vs {b} | {len(A)} | {len(B)} | {ao} | {bo} | **{p2(ao, ao + bo):.2f}** | {ca} / {cb} | {p2(ca, ca + cb):.3f} |"
    )


def q1():
    print("\n### Q1 — paired sign tests (item = found in >=2 of 3 samples)\n")
    print(
        "| panel | A vs B | A items | B items | A only | B only | p (items) | cells A only / B only (x3 samples) | p (cells, NOT independent) |"
    )
    print("|---|---|---|---|---|---|---|---|---|")
    for pn, v in PANELS.items():
        for a, b in [
            ("o5@max", "o55@xhigh"),
            ("o5@max", "f51@high"),
            ("o55@xhigh", "f51@high"),
            ("o5@max", "o5@high"),
            ("o55@xhigh", "o55@high"),
        ]:
            sign(v, a, b, pn)


def q2():
    O = "o55@high"
    print(f"\n### Q2 — complement to {O}\n")
    print(
        "| panel | X | pooled: mean X-only over 9 sample pairings | pooled: mean union | item-level (>=2/3) X-only | item-level union | O alone (item-level) |"
    )
    print("|---|---|---|---|---|---|---|")
    for pn, v in PANELS.items():
        Oset = {it for it in ITEMS if found(v, O, *it) >= 2}
        for X in ["f51@high", "o5@high", "o55@xhigh", "o5@max"]:
            xo, un = [], []
            for i in S:
                for j in S:
                    Xi = {it for it in ITEMS if hit(v, X, i, *it)}
                    Oj = {it for it in ITEMS if hit(v, O, j, *it)}
                    xo.append(len(Xi - Oj))
                    un.append(len(Xi | Oj))
            Xset = {it for it in ITEMS if found(v, X, *it) >= 2}
            print(
                f"| {pn} | {X} | {statistics.mean(xo):.2f} (range {min(xo)}–{max(xo)}) | {statistics.mean(un):.2f} | {len(Xset - Oset)} | {len(Xset | Oset)} | {len(Oset)} |"
            )
    print(
        "\n**Head-to-head, f51@high vs o5@high as complements.** Per item, the number of the 9 sample pairings in which"
    )
    print(
        "X found it and o55@high missed it; items where f51 scores higher vs lower, exact sign test.\n"
    )
    print(
        "| panel | items f51 > o5 | items f51 < o5 | p | complement items, f51 only (item-level) | o5 only (item-level) | p (item-level) |"
    )
    print("|---|---|---|---|---|---|---|")
    for pn, v in PANELS.items():

        def c(X, it):
            return sum(
                hit(v, X, i, *it) and not hit(v, O, j, *it) for i in S for j in S
            )

        d = [c("f51@high", it) - c("o5@high", it) for it in ITEMS]
        w, l = sum(x > 0 for x in d), sum(x < 0 for x in d)
        Oset = {it for it in ITEMS if found(v, O, *it) >= 2}
        F = {it for it in ITEMS if found(v, "f51@high", *it) >= 2} - Oset
        G = {it for it in ITEMS if found(v, "o5@high", *it) >= 2} - Oset
        print(
            f"| {pn} | {w} | {l} | {p2(w, w + l):.2f} | {len(F - G)} | {len(G - F)} | {p2(len(F - G), len(F ^ G)):.2f} |"
        )
        print(
            f"|  | f51 complement items: {sorted(f'{b}#{i}' for b, i in F)} · o5@high: {sorted(f'{b}#{i}' for b, i in G)} | | | | | |"
        )


def per_item():
    print(f"\n### Per item — samples (of 3) in which each arm found it, P1 / P2\n")
    print("| item | " + " | ".join(ARMS) + " |")
    print("|---|" + "---|" * len(ARMS))
    for b, i in ITEMS:
        cells = [
            f"{found(PANELS['P1'], a, b, i)} / {found(PANELS['P2'], a, b, i)}"
            for a in ARMS
        ]
        if any(c != "0 / 0" for c in cells):
            print(f"| {b}#{i} | " + " | ".join(cells) + " |")
    zero = [
        f"{b}#{i}"
        for b, i in ITEMS
        if all(found(PANELS[p], a, b, i) == 0 for p in PANELS for a in ARMS)
    ]
    print(
        f"\nFound by no arm in any sample under either panel ({len(zero)}): {', '.join(zero)}"
    )


def fisher(a, b, c, d):
    """Two-sided Fisher exact on [[a,b],[c,d]] (sum of tables no more probable than observed)."""
    n, r1, c1 = a + b + c + d, a + b, a + c

    def pr(x):
        return comb(c1, x) * comb(n - c1, r1 - x) / comb(n, r1)

    po = pr(a)
    return min(
        1.0,
        sum(
            pr(x)
            for x in range(max(0, r1 + c1 - n), min(r1, c1) + 1)
            if pr(x) <= po * (1 + 1e-9)
        ),
    )


def lean():
    rows = [r for r in P2]
    J = ["o5", "o55", "f51"]
    cred = defaultdict(set)
    judged_cells = defaultdict(set)
    for r in rows:
        judged_cells[(r["arm"], r["sample"], r["brief_id"])].add(r["judge"])
        for g in r["credited"]:
            cred[(r["arm"], r["sample"], r["brief_id"], g)].add(r["judge"])
    print("\n### P2 — each judge's recall per arm, summed over 3 samples (/108)\n")
    print("| judge | " + " | ".join(ARMS) + " | total |")
    print("|---|" + "---|" * len(ARMS) + "---|")
    for j in J:
        xs = [
            sum(j in cred.get((a, s, b, i), ()) for s in S for b, i in ITEMS)
            for a in ARMS
        ]
        print(f"| {j} | " + " | ".join(map(str, xs)) + f" | {sum(xs)} |")
    print(
        "\n**Own-model lean test.** A judge's SOLO credit = it credits a cell neither other judge credits; SOLO miss ="
    )
    print(
        "both others credit and it does not. Own-family arms vs the rest, Fisher exact on solo credit vs solo miss.\n"
    )
    print(
        "| judge | own arms: solo credit / solo miss | other arms: solo credit / solo miss | p |"
    )
    print("|---|---|---|---|")
    for j in J:
        o = [0, 0]
        x = [0, 0]
        others = [k for k in J if k != j]
        for a in ARMS:
            t = o if FAMILY[a] == j else x
            for s in S:
                for b, i in ITEMS:
                    if judged_cells.get((a, s, b)) != set(J):
                        continue
                    cs = cred.get((a, s, b, i), set())
                    if j in cs and not any(k in cs for k in others):
                        t[0] += 1
                    if j not in cs and all(k in cs for k in others):
                        t[1] += 1
        print(
            f"| {j} | {o[0]} / {o[1]} | {x[0]} / {x[1]} | {fisher(o[0], o[1], x[0], x[1]):.2f} |"
        )
    # P1-vs-P2 agreement on the majority verdict, samples 2/3 (the cells both panels judged)
    agree = tot = 0
    for a in ARMS:
        for s in (2, 3):
            for b, i in ITEMS:
                if judged(PANELS["P1"], a, s, b) and judged(PANELS["P2"], a, s, b):
                    tot += 1
                    agree += hit(PANELS["P1"], a, s, b, i) == hit(
                        PANELS["P2"], a, s, b, i
                    )
    print(
        f"\nP1 vs P2 majority verdicts agree on {agree}/{tot} (arm, sample, item) cells, samples 2-3."
    )


def tokens():
    def rows(p, eff):
        rs = [json.loads(l) for l in open(p) if l.strip()] if Path(p).exists() else []
        last = {}
        for r in rs:
            if r.get("effort") == eff and r.get("brief_id") in DEF:
                last[r["brief_id"]] = r
        return list(last.values())

    FACT = {"o55": (1.1, 0.78, 1.72), "o5": (1.0, 1.0, 1.0), "f51": (3.45, 3.2, 3.7)}
    src = {
        "o55@high": [
            (
                HERE.parent / "opus55-effort-sweep-2026-09-22/runs/o55/index.jsonl",
                "high",
            )
        ],
        "o55@xhigh": [
            (
                HERE.parent / "opus55-effort-sweep-2026-09-22/runs/o55/index.jsonl",
                "xhigh",
            )
        ],
        "o5@high": [
            (HERE.parent / "opus55-effort-sweep-2026-09-22/runs/o5/index.jsonl", "high")
        ],
        "o5@max": [],  # W2 arm D recorded no token counts
        "f51@high": [
            (HERE.parent / "fable51-effort-sweep-2026-09-10/runs/index.jsonl", "high")
        ],
    }
    print("\n### Tokens and quota per arm\n")
    print(
        "Per 7-brief sample, mean over the samples that carry token counts. W-pp = weekly plan points at the"
    )
    print(
        "Opus-5 margin (1 W-pp ~ 360K output or 3.4M cache_creation), x the model's per-token draw (Opus 5.5 1.1"
    )
    print(
        "[0.78-1.72], Fable 5.1 3.2-3.7; 09-22 and 09-16 records). [$list] shown for reference only.\n"
    )
    print(
        "| arm | samples with tokens | median out / cell | out / sample | cache_create / sample | est W-pp / sample [range] | vs o55@high | cells failed (no review) | [$list] / sample |"
    )
    print("|---|---|---|---|---|---|---|---|---|")
    base = None
    for a in ARMS:
        sub, eff = {"o55": "o55", "o5": "o5", "f51": "f51"}[FAMILY[a]], a.split("@")[1]
        per = []
        for p, e in src[a]:
            per.append(rows(p, e))
        for s in (2, 3):
            per.append(rows(HERE / "runs" / sub / f"s{s}" / "index.jsonl", eff))
        per = [x for x in per if x]
        allc = [r for x in per for r in x]
        ok = [
            r
            for r in allc
            if not r.get("is_error") and r.get("output_tokens") is not None
        ]
        fails = [r for r in allc if r not in ok]
        out = statistics.mean(sum(r.get("output_tokens") or 0 for r in x) for x in per)
        cc = statistics.mean(sum(r.get("cache_create") or 0 for r in x) for x in per)
        usd = statistics.mean(sum(r.get("cost_usd") or 0 for r in x) for x in per)
        f, lo, hi = FACT[FAMILY[a]]
        w = out / 360e3 + cc / 3.4e6
        base = base or w * f
        med = statistics.median(r["output_tokens"] for r in ok) if ok else "-"
        print(
            f"| {a} | {len(per)} | {med:,.0f} | {out:,.0f} | {cc:,.0f} | {w * f:.2f} [{w * lo:.2f}–{w * hi:.2f}] | {w * f / base:.1f}x | {len(fails)} | {usd:.2f} |"
        )


if __name__ == "__main__":
    for pn in PANELS:
        recall_table(pn, PANELS[pn])
    q1()
    q2()
    per_item()
    lean()
    tokens()
