#!/usr/bin/env python3
"""regate-probe-judge.py — stage the 2026-09-24 re-gate bisect for blind judging, MIXED with the gate's
own dossiers for the same task, so one judge scores every arm side by side (probe-judge.py's recipe).

  T10: gate r1-10 + full control r31-35 + sctarget r36-40   (20 dossiers)
  T08: gate r1-10 + sctarget r16-20                          (15 dossiers)

The other bisect arms (scall r16-20, slimscp r21-25, fullmd r26-30, T10 only) were screened
mechanically and are not re-judged. Dossiers -> eval/regate/probes/<task>/, keys -> eval/regate/probes/keys/.
Prints the judge groups JSON (judge-workflow.js `args.groups`)."""

import json, os, random, shutil

H = os.path.dirname(os.path.abspath(__file__))
G = os.environ.get(
    "GATE_ROOT", "/tmp/tokeff-gate"
)  # the bisect ran under the gate's root
GATE = os.path.join(os.path.dirname(H), "gate")
P = os.path.join(os.path.dirname(H), "regate", "probes")
rub = json.load(open(f"{H}/rubrics.json"))
runs = {
    (r["task"], r["rep"]): r for r in map(json.loads, open(f"{GATE}/f1/runs.jsonl"))
}
extra = {
    "T10-status-plan": [("full", range(31, 36)), ("sctarget", range(36, 41))],
    "T08-close-dirty": [("sctarget", range(16, 21))],
}
os.makedirs(f"{P}/keys", exist_ok=True)
groups = []
for t, arms in extra.items():
    src = [(runs[(t, rep)]["arm"], rep) for rep in range(1, 11)]
    src += [(arm, rep) for arm, reps in arms for rep in reps]
    random.Random(f"regate-probe-{t}").shuffle(src)
    d = f"{P}/{t}"
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    keys = {}
    for k, (arm, rep) in enumerate(src, 1):
        shutil.copy(f"{G}/runs/{t}/r{rep}/out/dossier.md", f"{d}/dossier-{k}.md")
        keys[f"dossier-{k}.md"] = {"arm": arm, "rep": rep}
    json.dump({"task": t, "dossiers": keys}, open(f"{P}/keys/{t}.json", "w"), indent=1)
    groups.append(
        {
            "id": f"regate-probe-{t}",
            "kind": "f1",
            "dir": d,
            "n": len(src),
            "success": rub[t]["success"],
            "items": rub[t]["items"],
            "reference": "",
        }
    )
print(json.dumps(groups))
