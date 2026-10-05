#!/usr/bin/env python3
"""Apply wave E1c's pre-registered configuration-choice rule to e1c-tune.py's output. The rule is in
docs/plans/RESEARCH_PROGRAM_BUILD.md (wave E1c) and was committed before this ran; this script is
that rule as code, and prints the measures and the one chosen arm.

  e1c-choose.py TUNE.json

Reads the tuning set's two-rater labels (outside the repo); never a sealed set.
"""

import json
import sys
from pathlib import Path

H = Path.home() / ".claude/autonomy/research/router-heldout"
RELAYED = ("completeness", "pushback")
LIMIT_S = 9.0  # the router's limit (ruling 4bf73c4e55d5); not a parameter of this rule
MIN_RECALL, MIN_OTHER, MAX_FALLBACK = 0.95, 0.90, 0.10  # gate row 15's own thresholds
TIE_ROWS = 2  # borderline relays within this many calls of the best are a tie
PREFER = (
    "on-pre",
    "on-e1b",
    "off-e1b",
)  # last tie-break: the smaller change from trunk first


def main():
    data = json.load(open(sys.argv[1]))
    strata = [json.loads(l)["stratum"] for l in open(H / "tuning.jsonl")]
    lab = []
    for vendor in ("anthropic", "openai"):
        lab.append(
            {
                int(r["id"][1:]): r["label"]
                for r in map(json.loads, open(H / f"tuning-labels-{vendor}.jsonl"))
            }
        )
    agreed = {k: lab[0][k] for k in lab[0] if lab[1].get(k) == lab[0][k]}
    border = [
        k
        for k in lab[0]
        if k in lab[1]
        and lab[0][k] != lab[1][k]
        and (lab[0][k] in RELAYED or lab[1][k] in RELAYED)
    ]
    m = {}
    for arm, rows in data["arms"].items():
        calls = [(int(k), c) for k, cs in rows.items() for c in cs]
        fb = sum(
            1
            for _, c in calls
            if c["label"] in ("INVALID", "TIMEOUT") or c["wall_s"] > LIMIT_S
        )
        rec = [
            (c["label"] in RELAYED)
            for k, c in calls
            if strata[k] != "other" and agreed.get(k) in RELAYED
        ]
        oth = [
            (c["label"] == agreed[k])
            for k, c in calls
            if strata[k] == "other" and k in agreed
        ]
        bor = [(c["label"] in RELAYED) for k, c in calls if k in border]
        walls = sorted(c["wall_s"] for _, c in calls)
        m[arm] = {
            "fallback_at_9s": fb / len(calls),
            "fallbacks": fb,
            "calls": len(calls),
            "recall": sum(rec) / len(rec),
            "recall_n": f"{sum(rec)}/{len(rec)}",
            "other": sum(oth) / len(oth),
            "other_n": f"{sum(oth)}/{len(oth)}",
            "borderline": sum(bor),
            "borderline_n": f"{sum(bor)}/{len(bor)}",
            "wall_median": walls[len(walls) // 2],
            "wall_p90": walls[int(len(walls) * 0.9)],
        }
        print(arm, json.dumps(m[arm], sort_keys=True))
    eligible = [
        a for a in m if m[a]["recall"] >= MIN_RECALL and m[a]["other"] >= MIN_OTHER
    ]
    if not eligible:
        print(
            "step 1: no arm meets recall and other on the agreed rows; taking the best recall, then other"
        )
        best = max(m, key=lambda a: (m[a]["recall"], m[a]["other"], -PREFER.index(a)))
    else:
        print(f"step 1: eligible on agreed rows: {', '.join(sorted(eligible))}")
        top = max(m[a]["borderline"] for a in eligible)
        tied = [a for a in eligible if top - m[a]["borderline"] <= TIE_ROWS]
        print(
            f"step 2: borderline relays, best {top}; tied within {TIE_ROWS}: {', '.join(sorted(tied))}"
        )
        best = min(tied, key=lambda a: (m[a]["fallback_at_9s"], PREFER.index(a)))
        print(
            "step 3: lowest fallback share at 9 s among the tied, then the smaller change from trunk"
        )
    over = m[best]["fallback_at_9s"] > MAX_FALLBACK
    print(
        f"CHOSEN: {best}; tuning fallback share at 9 s {m[best]['fallback_at_9s']:.2f} "
        f"({'above' if over else 'within'} the {MAX_FALLBACK} cap)"
    )


if __name__ == "__main__":
    main()
