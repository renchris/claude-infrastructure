#!/usr/bin/env python3
"""r3-probe-agg.py — tally round 3's bisect probes (GATE.md § Round 3) against the re-gate's own
slim and full runs of the same tasks. Mechanical screen only: turns, tool errors, non-ship skill
loads, ledger probes (a non-zero exit whose command looks for `scripts/wrap-ledger.sh` or a
`scripts` dir), and push attempts. Reads $GATE_ROOT/runs/<task>/r*/out/metrics.json (probe.sh) and
eval/regate/f1/runs.jsonl. Prints markdown."""

import glob, json, os, re, statistics as st
from collections import defaultdict

H = os.path.dirname(os.path.abspath(__file__))
G = os.environ.get("GATE_ROOT", "/tmp/tokeff-r3")
REGATE = os.path.join(os.path.dirname(H), "regate", "f1", "runs.jsonl")


def ledger_probes(transcript):
    try:
        recs = [json.loads(l) for l in open(transcript)]
    except OSError:
        return None
    uses = {
        b["id"]: b
        for r in recs
        if r.get("type") == "assistant"
        for b in r["message"].get("content", [])
        if b.get("type") == "tool_use"
    }
    n = 0
    for r in recs:
        c = r.get("message", {}).get("content") if r.get("type") == "user" else None
        for b in c if isinstance(c, list) else []:
            if b.get("type") == "tool_result" and b.get("is_error"):
                cmd = str(
                    uses.get(b["tool_use_id"], {}).get("input", {}).get("command", "")
                )
                t = b.get("content")
                t = (
                    " ".join(x.get("text", "") for x in t if isinstance(x, dict))
                    if isinstance(t, list)
                    else str(t)
                )
                if t.startswith("Exit code") and re.search(
                    r"wrap-ledger|ls scripts", cmd
                ):
                    n += 1
    return n


rows = defaultdict(list)
for r in map(json.loads, open(REGATE)):
    rows[(r["task"], r["arm"] + " (re-gate)")].append(r)
for p in glob.glob(f"{G}/runs/*/r*/out/metrics.json"):
    m = json.load(open(p))
    rows[(m["task"], m["arm"])].append(m)

print(
    "| task | arm | n | turns | tool errors | ledger probes | non-ship skills | push attempts | $/run |"
)
print("|---|---|---|---|---|---|---|---|---|")
for (task, arm), L in sorted(rows.items()):
    if not any(k[0] == task and not k[1].endswith("(re-gate)") for k in rows):
        continue
    lp = [ledger_probes(x["transcripts"][0]) for x in L if x.get("transcripts")]
    sk = [sum(1 for s in x.get("skills", []) if s != "ship") for x in L]
    print(
        f"| {task} | {arm} | {len(L)} | {st.mean(x['turns'] for x in L):.1f} "
        f"| {st.mean(x['tool_errors'] for x in L):.1f} | {sum(v or 0 for v in lp)} "
        f"| {sum(sk)}/{len(L)} | {st.mean(x['push_attempted'] for x in L):.1f} "
        f"| {st.mean(x['cost_usd'] for x in L):.2f} |"
    )
