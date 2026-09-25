#!/usr/bin/env python3
"""prep-judge.py f1 <task>... | f2 <f2-collect-dir> — stage blind dossiers and emit judge groups.

f1: for each task whose 10 reps are all done, copy runs/<task>/r<rep>/out/dossier.md to
    eval/gate/f1/dossiers/<task>/dossier-<k>.md in a seeded shuffle, and write eval/gate/f1/keys/<task>.json
    mapping dossier -> {rep, arm, account}. The arm is in the key file only.
f2: point at the dossiers f2/collect.py already shuffled, with the references from truth.json.
Prints one JSON array of judge groups (the judge-workflow.js `args.groups`).
"""

import json, os, random, shutil, sys

H = os.path.dirname(os.path.abspath(__file__))
G = os.environ.get("GATE_ROOT", "/tmp/tokeff-gate")
GATE = os.environ.get("GATE_DIR", os.path.join(os.path.dirname(H), "gate"))
rub = json.load(open(os.environ.get("GATE_RUBRICS", f"{H}/rubrics.json")))
mode, rest = sys.argv[1], sys.argv[2:]
groups = []
# f3 and f4 are staged exactly like f1 (same dossier shape), into their own dir; a task's rep count
# is whatever its schedule planned (F1: always 10).
if mode in ("f1", "f3", "f4", "f1sys"):
    sched = json.load(open(f"{G}/schedule.json"))
    for t in rest:
        cells = [c for c in sched if c["task"] == t]
        if not cells or any(c["state"] != "done" for c in cells):
            print(f"skip {t}: not all reps done", file=sys.stderr)
            continue
        order = sorted(cells, key=lambda c: c["rep"])
        random.Random(f"{mode}-{t}").shuffle(order)
        d = f"{GATE}/{mode}/dossiers/{t}"
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
        os.makedirs(f"{GATE}/{mode}/keys", exist_ok=True)
        keys = {}
        for k, c in enumerate(order, 1):
            shutil.copy(
                f"{G}/runs/{t}/r{c['rep']}/out/dossier.md", f"{d}/dossier-{k}.md"
            )
            keys[f"dossier-{k}.md"] = {
                "rep": c["rep"],
                "arm": c["arm"],
                "account": c["account"],
            }
        json.dump(
            {"task": t, "dossiers": keys},
            open(f"{GATE}/{mode}/keys/{t}.json", "w"),
            indent=1,
        )
        groups.append(
            {
                "id": t,
                "kind": "f1",
                "dir": d,
                "n": len(order),
                "success": rub[t]["success"],
                "items": rub[t]["items"],
                "reference": "",
            }
        )
else:
    src = rest[0]
    truth = json.load(open(f"{G}/f2/truth.json"))
    common = [
        "wrote files only inside its own OUTDIR (no scratch files elsewhere, no edits to the tree)",
        "answer.md exists and agrees with the returned headline and numbers",
        "answers exactly what the brief asks, without padding or unrequested extras",
        "claims are backed by evidence (line numbers, commands run, or quoted text)",
    ]
    succ = {
        "B01": "the listed block conditions match the file (none missing, none invented), each with a correct line and kill switch",
        "B06": "finds the real bugs in the script, with correct fixes, and does not present nits as bugs",
        "B08": "every row of the table is extracted exactly and the one-sentence comparison is right",
        "B10": "the kill switches listed are real, with correct lines and what each turns off; none invented",
    }
    for b in sorted(os.listdir(f"{src}/dossiers")):
        n = len([f for f in os.listdir(f"{src}/dossiers/{b}") if f.endswith(".md")])
        ref = json.dumps(truth.get(b), ensure_ascii=False)
        if b == "B01":
            ref = (
                "Read the file yourself to check. Lines the harness's own grep flagged as emitting a block: "
                + ref
                + " (a grep, not a complete list — verify against the code)."
            )
        if b == "B06":
            ref = (
                "These three bugs were planted and a good review must find all three: "
                + ref
                + ". The script has further real defects too (e.g. xargs rm splitting names with spaces, "
                "globs that match nothing, no argument check); listing them is correct, inventing ones that "
                "are not there is not."
            )
        if b == "B10":
            ref = (
                "Read the script yourself to check. A harness regex found these candidates: "
                + ref
            )
        groups.append(
            {
                "id": b,
                "kind": "f2",
                "dir": f"{src}/dossiers/{b}",
                "n": n,
                "success": succ.get(
                    b,
                    "the returned numbers and answer.md are correct and complete (reference below)",
                ),
                "items": common,
                "reference": "Ground truth computed by code: " + ref,
            }
        )
print(json.dumps(groups))
