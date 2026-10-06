#!/usr/bin/env python3
"""Score e1h live calls and E1c tune-2reps.json arms with e1c-choose.py's definitions, plus over-flag counts.
  stronger-model-score.py CALLS.json"""
import json, sys
from pathlib import Path
H = Path.home() / ".claude/autonomy/research/router-heldout"
REPO = Path("/Users/chrisren/Development/.worktrees/wt-cc-024434-55635")
RELAYED = ("completeness", "pushback"); LIMIT_S = 9.0; COLD = (2.0, 4.0)
strata = [json.loads(l)["stratum"] for l in open(H / "tuning.jsonl")]
lab = [{int(r["id"][1:]): r["label"] for r in map(json.loads, open(H / f"tuning-labels-{v}.jsonl"))}
       for v in ("anthropic", "openai")]
agreed = {k: lab[0][k] for k in lab[0] if lab[1].get(k) == lab[0][k]}
border = [k for k in lab[0] if k in lab[1] and lab[0][k] != lab[1][k]
          and (lab[0][k] in RELAYED or lab[1][k] in RELAYED)]

def q(xs, p):
    xs = sorted(xs); return xs[min(len(xs) - 1, int(len(xs) * p))]

def score(rows, rows_done=None):
    calls = [(int(k), c) for k, cs in rows.items() for c in cs]
    n_rep = max(len(cs) for cs in rows.values())
    fb = sum(1 for _, c in calls if c["label"] in ("INVALID", "TIMEOUT") or c["wall_s"] > LIMIT_S)
    inv = sum(1 for _, c in calls if c["label"] in ("INVALID", "TIMEOUT"))
    rec = [(c["label"] in RELAYED) for k, c in calls if strata[k] != "other" and agreed.get(k) in RELAYED]
    oth = [(c["label"] == agreed[k]) for k, c in calls if strata[k] == "other" and k in agreed]
    oth_relay = sum(1 for k, c in calls if strata[k] == "other" and k in agreed
                    and agreed[k] not in RELAYED and c["label"] in RELAYED)
    oth_nonrelay_n = sum(1 for k, c in calls if strata[k] == "other" and k in agreed and agreed[k] not in RELAYED)
    neg = [(c["label"] in RELAYED) for k, c in calls if k in agreed and agreed[k] not in RELAYED]
    bor = [(c["label"] in RELAYED) for k, c in calls if k in border]
    walls = [c["wall_s"] for _, c in calls]
    loads = [c["load"] for _, c in calls]
    return {
        "calls": len(calls), "reps": n_rep,
        "recall_n": f"{sum(rec)}/{len(rec)}", "recall": round(sum(rec) / max(1, len(rec)), 3),
        "other_n": f"{sum(oth)}/{len(oth)}", "other": round(sum(oth) / max(1, len(oth)), 3),
        "relays_on_agreed_other_stratum_nonrelay_gold": f"{oth_relay}/{oth_nonrelay_n}",
        "relays_on_all_agreed_nonrelay_rows": f"{sum(neg)}/{len(neg)}",
        "borderline_n": f"{sum(bor)}/{len(bor)}",
        "fallback_at_9s": f"{fb}/{len(calls)}", "invalid_or_timeout": inv,
        "wall_median": q(walls, 0.5), "wall_p90": q(walls, 0.9), "wall_max": max(walls),
        "warm_est_median": f"{max(0, q(walls, .5) - COLD[1]):.2f}-{max(0, q(walls, .5) - COLD[0]):.2f}",
        "warm_est_p90": f"{max(0, q(walls, .9) - COLD[1]):.2f}-{max(0, q(walls, .9) - COLD[0]):.2f}",
        "load_min_max": f"{min(loads)}-{max(loads)}",
    }

def per_row_firsts(rows):  # e1c 2-rep data -> rep 1 only, for a like-for-like 1-rep comparison
    return {k: cs[:1] for k, cs in rows.items()}

new = json.load(open(sys.argv[1]))
old = json.load(open(REPO / "docs/research/router-classifier-e1c-2026-10-04/tune-2reps.json"))
done = new.get("meta", {}).get("rows_done")
print(f"agreed rows {len(agreed)}; borderline rows {len(border)}; e1h rows done {done}")
out = {}
for a, rows in new["arms"].items():
    out["e1h:" + a] = score(rows)
for a in ("off-e1b", "on-pre", "on-e1b"):
    out["e1c:" + a + " (2 reps)"] = score(old["arms"][a])
    out["e1c:" + a + " (rep 1)"] = score(per_row_firsts(old["arms"][a]))
for a, m in out.items():
    print(a, json.dumps(m))
# per-row disagreements vs agreed gold, row index only (no prompt text)
print("\nper-row errors on agreed rows (row: gold -> labels by arm)")
for k in sorted(agreed):
    labs = {a: new["arms"][a].get(str(k), [{}])[0].get("label") for a in new["arms"]}
    labs["e1c:off-e1b"] = "/".join(c["label"] for c in old["arms"]["off-e1b"][str(k)])
    labs["e1c:on-pre"] = "/".join(c["label"] for c in old["arms"]["on-pre"][str(k)])
    g = agreed[k]
    def wrong(l):
        return l is not None and any((x in RELAYED) != (g in RELAYED) or (strata[k] == "other" and x != g)
                                     for x in l.split("/"))
    if any(wrong(l) for l in labs.values()):
        print(f"  row {k} [{strata[k]}] gold={g}: " + ", ".join(f"{a}={l}" for a, l in labs.items()))
print("\nborderline rows (row: rater labels -> labels by arm)")
for k in border:
    labs = {a: new["arms"][a].get(str(k), [{}])[0].get("label") for a in new["arms"]}
    print(f"  row {k} [{strata[k]}] {lab[0][k]}|{lab[1][k]}: " + ", ".join(f"{a}={l}" for a, l in labs.items())
          + f", e1c:off-e1b={'/'.join(c['label'] for c in old['arms']['off-e1b'][str(k)])}"
          + f", e1c:on-pre={'/'.join(c['label'] for c in old['arms']['on-pre'][str(k)])}")
