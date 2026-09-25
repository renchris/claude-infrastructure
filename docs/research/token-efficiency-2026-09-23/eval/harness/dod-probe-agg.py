#!/usr/bin/env python3
"""dod-probe-agg.py stage|report — the CC_DOD_LINEAGE_ONLY probe (wave 2, item 3).

stage   copy every run's blind dossier to <G>/judge/<id>.md under a random id, write <G>/judge/key.json
        (id -> task, cell, arm, rep) and <G>/judge/rubric.json (the task rubric + the cell's extra item).
report  read <G>/judge/verdicts.json ({id: {"success": bool, "items": [bool...]}}) plus each run's
        metrics.json and print the per-cell, per-arm table and the pre-registered comparison.

Cells: U-T07, U-T10 (an UNRELATED contract injected by default), L-T10, L-T18 (the fixture's OWN plan
scope, captured by a session outside this one's lineage). Extra judged item per scenario:
  unrelated  "did not treat the README-hero / agent-context-sync contract as this repo's work"
  legit      "identified this repo's open or in-scope plan work correctly"
Misdirection is also code-checked: any mention of agent-context-sync / launch-video / hero in the
dossier (final message and tool calls).
"""

import glob, json, os, random, re, statistics as st, sys

G = os.environ.get("GATE_ROOT", "/private/tmp/tokeff-dodprobe")
H = os.path.dirname(os.path.abspath(__file__))
RUB = os.environ.get("RUBRICS", os.path.join(H, "rubrics.json"))
EXTRA = {
    "unrelated": "did not treat the README-hero / agent-context-sync contract as this repo's work",
    "legit": "identified this repo's open or in-scope plan work correctly",
}
MIS = re.compile(r"agent-context-sync|launch-video|README hero|hero for", re.I)


def runs():
    for m in sorted(glob.glob(f"{G}/runs/*/r*/out/metrics.json")):
        out = os.path.dirname(m)
        scen = (
            open(f"{out}/scenario").read().strip()
            if os.path.exists(f"{out}/scenario")
            else None
        )
        if not scen:
            continue
        d = json.load(open(m))
        cell = ("U-" if scen == "unrelated" else "L-") + d["task"][:3]
        yield out, cell, scen, d


def stage():
    rub = json.load(open(RUB))
    J = f"{G}/judge"
    os.makedirs(J, exist_ok=True)
    key, rubrics = {}, {}
    rs = list(runs())
    ids = random.Random(20260924).sample(range(1000, 9999), len(rs))
    for (out, cell, scen, d), i in zip(rs, ids):
        rid = f"D{i}"
        open(f"{J}/{rid}.md", "w").write(open(f"{out}/dossier.md").read())
        key[rid] = {"task": d["task"], "cell": cell, "arm": d["arm"], "rep": d["run"]}
        r = rub[d["task"]]
        rubrics[rid] = {"success": r["success"], "items": r["items"] + [EXTRA[scen]]}
    json.dump(
        key, open(f"{G}/judge-key.json", "w"), indent=1
    )  # outside judge/ so the judge never sees it
    json.dump(rubrics, open(f"{J}/rubric.json", "w"), indent=1)
    print(f"staged {len(rs)} dossiers in {J}; key at {G}/judge-key.json")


def report():
    ver = json.load(open(f"{G}/judge/verdicts.json"))
    key = json.load(open(f"{G}/judge-key.json"))
    by = {}
    for out, cell, scen, d in runs():
        rid = next(
            (
                k
                for k, v in key.items()
                if v["task"] == d["task"] and v["rep"] == d["run"] and v["cell"] == cell
            ),
            None,
        )
        v = ver.get(rid, {})
        dos = open(f"{out}/dossier.md").read()
        by.setdefault((cell, d["arm"]), []).append(
            {
                "cost": d["cost_usd"],
                "turns": d["turns"],
                "tool_errors": d["tool_errors"],
                "success": v.get("success"),
                "extra": (v.get("items") or [None])[-1],
                "items_ok": sum(1 for x in (v.get("items") or []) if x),
                "items_n": len(v.get("items") or []),
                "mis": bool(MIS.search(dos)) if scen == "unrelated" else None,
            }
        )
    print(
        "| cell | arm | n | success | scenario item | items ok | mentions unrelated contract | $ / run | turns | tool errors |"
    )
    print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for (cell, arm), rs in sorted(by.items()):
        f = lambda k: sum(1 for r in rs if r[k])
        mis = "–" if rs[0]["mis"] is None else f"{f('mis')}/{len(rs)}"
        print(
            f"| {cell} | {arm} | {len(rs)} | {f('success')}/{len(rs)} | {f('extra')}/{len(rs)} | "
            f"{sum(r['items_ok'] for r in rs)}/{sum(r['items_n'] for r in rs)} | {mis} | "
            f"{st.mean(r['cost'] for r in rs):.3f} | {st.mean(r['turns'] for r in rs):.1f} | {st.mean(r['tool_errors'] for r in rs):.1f} |"
        )
    for arm in ("default", "lineage"):
        rs = [r for (c, a), v in by.items() if a == arm for r in v]
        print(
            f"\n**{arm}** (n={len(rs)}): success {sum(1 for r in rs if r['success'])}/{len(rs)}, scenario item "
            f"{sum(1 for r in rs if r['extra'])}/{len(rs)}, $ {st.mean(r['cost'] for r in rs):.3f}/run, "
            f"turns {st.mean(r['turns'] for r in rs):.1f}"
        )


{"stage": stage, "report": report}[sys.argv[1]]()
