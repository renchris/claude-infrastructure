#!/usr/bin/env python3
"""probe-judge.py — stage the post-gate mechanism probes for blind judging, MIXED with the gate's own
dossiers for the same task/brief so one judge scores every arm side by side (a judge that saw only
probe dossiers would calibrate on a different population).

F1: gate runs r1-10 + probe arm `slimclose` r11-15 for T08 and T10  -> eval/gate/probes/f1/<task>/
F2: gate slots r1-8 + probe `lean+scope` r9-12 for B01 B02 B05 B06 B07 -> eval/gate/probes/f2/<brief>/
Keys (dossier -> arm, rep) go to eval/gate/probes/keys/. Prints the judge groups JSON.
The dossier text is the brief as the gate ran it; the probe's extra scope clause is not shown.
"""

import json, os, random, shutil

H = os.path.dirname(os.path.abspath(__file__))
G = os.environ.get("GATE_ROOT", "/tmp/tokeff-gate")
GATE = os.environ.get("GATE_DIR", os.path.join(os.path.dirname(H), "gate"))
rub = json.load(open(f"{H}/rubrics.json"))
P = f"{GATE}/probes"
os.makedirs(f"{P}/keys", exist_ok=True)
groups = []

runs = {
    (r["task"], r["rep"]): r for r in map(json.loads, open(f"{GATE}/f1/runs.jsonl"))
}
for t in ("T08-close-dirty", "T10-status-plan"):
    src = [
        (f"{G}/runs/{t}/r{rep}/out/dossier.md", runs[(t, rep)]["arm"], rep)
        for rep in range(1, 11)
    ]
    src += [
        (f"{G}/runs/{t}/r{rep}/out/dossier.md", "slimclose", rep)
        for rep in range(11, 16)
    ]
    random.Random(f"probe-f1-{t}").shuffle(src)
    d = f"{P}/f1/{t}"
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    keys = {}
    for k, (path, arm, rep) in enumerate(src, 1):
        shutil.copy(path, f"{d}/dossier-{k}.md")
        keys[f"dossier-{k}.md"] = {"arm": arm, "rep": rep}
    json.dump({"task": t, "dossiers": keys}, open(f"{P}/keys/{t}.json", "w"), indent=1)
    groups.append(
        {
            "id": f"probe-{t}",
            "kind": "f1",
            "dir": d,
            "n": len(src),
            "success": rub[t]["success"],
            "items": rub[t]["items"],
            "reference": "",
        }
    )

gate_groups = {
    g["id"]: g
    for g in json.load(open(os.environ.get("F2_GROUPS", f"{G}/judge-f2-groups.json")))
}
for b in ("B01", "B02", "B05", "B06", "B07"):
    gk = json.load(open(f"{GATE}/f2/keys/{b}.json"))["dossiers"]
    pk = json.load(open(f"{P}/f2-scope-collect/keys/{b}.json"))["dossiers"]
    src = [
        (f"{GATE}/f2/dossiers/{b}/{f}", v["agent_type"], v["rep"])
        for f, v in gk.items()
    ]
    src += [
        (f"{P}/f2-scope-collect/dossiers/{b}/{f}", "lean+scope", v["rep"])
        for f, v in pk.items()
    ]
    random.Random(f"probe-f2-{b}").shuffle(src)
    d = f"{P}/f2/{b}"
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    keys = {}
    for k, (path, arm, rep) in enumerate(src, 1):
        txt = open(path).read()
        # renumber the dossier heading so it matches its new file name
        txt = txt.replace(txt.split("\n", 1)[0], f"# Dossier {k}", 1)
        open(f"{d}/dossier-{k}.md", "w").write(txt)
        keys[f"dossier-{k}.md"] = {"arm": arm, "rep": rep}
    json.dump({"brief": b, "dossiers": keys}, open(f"{P}/keys/{b}.json", "w"), indent=1)
    g = dict(gate_groups[b])
    g.update(id=f"probe-{b}", dir=d, n=len(src))
    groups.append(g)
print(json.dumps({"groups": groups}))
