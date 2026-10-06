#!/usr/bin/env python3
"""Score e1g-tune.py's output against wave E1g's pre-registered pass rule, with e1c-choose.py's
definitions (../router-classifier-e1c-2026-10-04/e1c-choose.py): relay recall on the agreed
relay-gold rows of the three completeness strata, exact label on the agreed `other` rows, relays on
the borderline rows (the raters split and one said completeness or pushback), fallback share at 9 s.

  e1g-score.py TUNE.json

Pass, fixed in the plan before this ran: recall >= 0.95 and other >= 0.90 on agreed rows, fallback
<= 0.10 at 9 s, borderline relays >= 17 of 26. Reads the tuning set's two-rater labels (outside the
repo); never a sealed set. Exit 0 on pass, 1 on fail.
"""

import json
import sys
from collections import Counter
from pathlib import Path

H = Path.home() / ".claude/autonomy/research/router-heldout"
RELAYED = ("completeness", "pushback")
LIMIT_S = 9.0
MIN_RECALL, MIN_OTHER, MAX_FALLBACK, MIN_BORDERLINE = 0.95, 0.90, 0.10, 17


def main() -> int:
    data = json.load(open(sys.argv[1]))
    strata = [json.loads(line)["stratum"] for line in open(H / "tuning.jsonl")]
    lab = []
    for vendor in ("anthropic", "openai"):
        rows = map(json.loads, open(H / f"tuning-labels-{vendor}.jsonl"))
        lab.append({int(r["id"][1:]): r["label"] for r in rows})
    agreed = {k: lab[0][k] for k in lab[0] if lab[1].get(k) == lab[0][k]}
    border = [
        k
        for k in lab[0]
        if k in lab[1]
        and lab[0][k] != lab[1][k]
        and (lab[0][k] in RELAYED or lab[1][k] in RELAYED)
    ]
    rows = data["arms"]["union"]
    calls = [(int(k), c) for k, cs in rows.items() for c in cs]
    fb = sum(
        1
        for _, c in calls
        if c["label"] in ("INVALID", "TIMEOUT") or c["wall_s"] > LIMIT_S
    )
    rec = [
        c["label"] in RELAYED
        for k, c in calls
        if strata[k] != "other" and agreed.get(k) in RELAYED
    ]
    oth = [
        c["label"] == agreed[k]
        for k, c in calls
        if strata[k] == "other" and k in agreed
    ]
    bor = [c["label"] in RELAYED for k, c in calls if k in border]
    walls = sorted(c["wall_s"] for _, c in calls)
    loads = [c["load"] for _, c in calls]
    flipped = sum(1 for cs in rows.values() if len({c["label"] for c in cs}) > 1)
    paths = Counter()
    for _, c in calls:
        why = c.get("why") or ""
        if c["label"] in ("INVALID", "TIMEOUT"):
            paths["no label (" + c["label"].lower() + ")"] += 1
        else:
            kind = "fast" if why.startswith("classifier (fast") else "careful"
            path = "resident" if "call, resident)" in why.split(";")[0] else "cold"
            paths[f"{kind} call, {path}"] += 1
    n = len(calls)
    checks = [
        (
            "relay recall, agreed relay rows",
            sum(rec),
            len(rec),
            sum(rec) / len(rec) >= MIN_RECALL,
            f">= {MIN_RECALL}",
        ),
        (
            "`other`, agreed rows",
            sum(oth),
            len(oth),
            sum(oth) / len(oth) >= MIN_OTHER,
            f">= {MIN_OTHER}",
        ),
        (
            "borderline relays",
            sum(bor),
            len(bor),
            sum(bor) >= MIN_BORDERLINE,
            f">= {MIN_BORDERLINE} of 26",
        ),
        ("fallback share at 9 s", fb, n, fb / n <= MAX_FALLBACK, f"<= {MAX_FALLBACK}"),
    ]
    print("| measure | reading | rule | |")
    print("|---|---|---|---|")
    for name, a, b, ok, rule in checks:
        print(
            f"| {name} | {a}/{b} = {a / b:.2f} | {rule} | {'pass' if ok else 'FAIL'} |"
        )
    print(
        f"calls {n} ({len(rows)} rows x {data['reps_done']} reps); wall median "
        f"{walls[n // 2]} s, p90 {walls[int(n * 0.9)]} s, max {walls[-1]} s; "
        f"load {min(loads)}-{max(loads)}; rows whose two reps differ {flipped}/{len(rows)}"
    )
    print("answered by: " + " · ".join(f"{k} {v}" for k, v in sorted(paths.items())))
    ok = all(c[3] for c in checks)
    print("VERDICT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
