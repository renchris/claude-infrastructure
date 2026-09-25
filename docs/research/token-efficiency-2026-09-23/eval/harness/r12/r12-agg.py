#!/usr/bin/env python3
"""r12-agg.py [G] — aggregate the rank-12 gate (hooks/bash-output-offload.sh on vs off).

Per run: success (the task's verify.sh; O2/O4 are re-verified from the saved answer so a verifier fix
applies to every run alike), list $ and turns from result.json, offloads the hook made, and whether any
Bash call printed more than 8,000 chars of stdout WITHOUT a read verb (i.e. the hook was eligible), read
from the transcript's tool results. Prints a per-task table and per-arm totals.
"""

import glob, json, os, re, statistics as st, subprocess, sys

G = sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/tokeff-r12gate"
H = os.path.dirname(os.path.abspath(__file__))
READ = re.compile(
    r"(^|[\s;&|(`$])(cat|sed|head|tail|awk|less|more|nl|bat|jq|grep|egrep|rg|diff)(\s|$)|git\s+(-C\s+\S+\s+)?(show|diff|log|blame)\b"
)


def tx_for(sid):
    for base in glob.glob(os.path.expanduser("~/.claude*/projects")):
        hit = glob.glob(f"{os.path.realpath(base)}/*/{sid}.jsonl")
        if hit:
            return hit[0]
    return None


rows = []
for run in sorted(glob.glob(f"{G}/runs/*/r*")):
    out, task = f"{run}/out", os.path.basename(os.path.dirname(run))
    try:
        res = json.load(open(f"{out}/result.json"))
    except (OSError, ValueError):
        continue
    arm = open(f"{out}/arm").read().strip()
    if task.startswith(("O2", "O4")):
        v = subprocess.run(
            ["bash", f"{H}/r12tasks/{task}/verify.sh", f"{out}/answer.txt"],
            capture_output=True,
            text=True,
        ).stdout
    else:
        v = open(f"{out}/verify.txt").read()
    ok = v.strip().splitlines()[-1:] == ["PASS"]
    eligible = 0
    tx = tx_for(res.get("session_id", ""))
    if tx:
        cmds = {}
        for line in open(tx, errors="replace"):
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get("type") == "assistant":
                for c in r["message"].get("content") or []:
                    if (
                        isinstance(c, dict)
                        and c.get("type") == "tool_use"
                        and c.get("name") == "Bash"
                    ):
                        cmds[c["id"]] = (c.get("input") or {}).get("command", "")
            tur = r.get("toolUseResult")
            if (
                r.get("type") == "user"
                and isinstance(tur, dict)
                and len(tur.get("stdout") or "") > 8000
            ):
                for c in (r.get("message") or {}).get("content") or []:
                    if (
                        isinstance(c, dict)
                        and c.get("type") == "tool_result"
                        and not READ.search(cmds.get(c.get("tool_use_id"), ""))
                    ):
                        eligible += 1
    rows.append(
        dict(
            task=task,
            arm=arm,
            ok=ok,
            cost=res.get("total_cost_usd", 0),
            turns=res.get("num_turns", 0),
            offloads=int(open(f"{out}/offloads").read().strip() or 0),
            eligible=eligible,
            tx=bool(tx),
        )
    )

print(
    "| task | arm | n | success | offloads | runs with an eligible >8k non-read result | $ / run | turns |"
)
print("|---|---|---:|---:|---:|---:|---:|---:|")
for task in sorted({r["task"] for r in rows}):
    for arm in ("off", "on"):
        rs = [r for r in rows if r["task"] == task and r["arm"] == arm]
        if rs:
            print(
                f"| {task} | {arm} | {len(rs)} | {sum(r['ok'] for r in rs)}/{len(rs)} | {sum(r['offloads'] for r in rs)} | "
                f"{sum(1 for r in rs if r['eligible'])} | {st.mean(r['cost'] for r in rs):.3f} | {st.mean(r['turns'] for r in rs):.1f} |"
            )
for arm in ("off", "on"):
    rs = [r for r in rows if r["arm"] == arm]
    if rs:
        print(
            f"\n**{arm}** (n={len(rs)}): success {sum(r['ok'] for r in rs)}/{len(rs)}, offloads {sum(r['offloads'] for r in rs)}, "
            f"eligible runs {sum(1 for r in rs if r['eligible'])}, ${st.mean(r['cost'] for r in rs):.3f}/run, "
            f"turns {st.mean(r['turns'] for r in rs):.1f}, missing transcripts {sum(not r['tx'] for r in rs)}"
        )
