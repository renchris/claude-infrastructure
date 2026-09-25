#!/usr/bin/env python3
"""ext-pool.py — input plumbing for the round-4 F1 extension (GATE.md § R4.5). No statistic lives here.

agg.py joins a verdict to a run by (group id == task, rep) and reads one GATE_DIR. The extension has
20 runs per task and pools with round 4, so three data-only steps sit around it:

  prep  <task>...         stage blind dossiers like prep-judge.py f1, but split each task's 20 shuffled
                          dossiers into two judge groups of 10 (h1, h2), so every judge reads exactly as
                          many dossiers as a round-4 judge did. Writes GATE_DIR/f1/{dossiers,keys} and
                          prints the judge groups (ids "<task>~h1", "<task>~h2").
  merge                   fold GATE_DIR/f1/verdicts-halves.json (save-verdicts.py output) into per-task
                          groups in GATE_DIR/f1/verdicts.json, dossier names "h1/dossier-3.md".
  pool  <out> <dir>...    concatenate several GATE_DIRs' f1 inputs into <out>/f1 (runs.jsonl, keys,
                          verdicts.json). Dossier names get a "<i>:" prefix so they cannot collide; reps
                          must already be distinct per task (sched.py plan --rep-offset), and this refuses
                          if they are not.
Then `GATE_DIR=<dir> python3 agg.py f1` runs the unchanged rule.
"""

import json, os, random, shutil, sys

H = os.path.dirname(os.path.abspath(__file__))
G = os.environ.get("GATE_ROOT", "/tmp/tokeff-gate")
GATE = os.environ.get("GATE_DIR", os.path.join(os.path.dirname(H), "gate"))


def prep(tasks):
    rub = json.load(open(f"{H}/rubrics.json"))
    sched = json.load(open(f"{G}/schedule.json"))
    groups = []
    for t in tasks:
        cells = [c for c in sched if c["task"] == t]
        if not cells or any(c["state"] != "done" for c in cells):
            print(f"skip {t}: not all reps done", file=sys.stderr)
            continue
        order = sorted(cells, key=lambda c: c["rep"])
        random.Random(f"f1ext-{t}").shuffle(order)
        base = f"{GATE}/f1/dossiers/{t}"
        shutil.rmtree(base, ignore_errors=True)
        os.makedirs(f"{GATE}/f1/keys", exist_ok=True)
        keys = {}
        half = (len(order) + 1) // 2
        for h, part in (("h1", order[:half]), ("h2", order[half:])):
            d = f"{base}/{h}"
            os.makedirs(d)
            for k, c in enumerate(part, 1):
                shutil.copy(
                    f"{G}/runs/{t}/r{c['rep']}/out/dossier.md", f"{d}/dossier-{k}.md"
                )
                keys[f"{h}/dossier-{k}.md"] = {
                    "rep": c["rep"],
                    "arm": c["arm"],
                    "account": c["account"],
                }
            groups.append(
                {
                    "id": f"{t}~{h}",
                    "kind": "f1",
                    "dir": d,
                    "n": len(part),
                    "success": rub[t]["success"],
                    "items": rub[t]["items"],
                    "reference": "",
                }
            )
        json.dump(
            {"task": t, "dossiers": keys},
            open(f"{GATE}/f1/keys/{t}.json", "w"),
            indent=1,
        )
    print(json.dumps(groups))


def merge():
    halves = json.load(open(f"{GATE}/f1/verdicts-halves.json"))
    out = {}
    for g in halves:
        t, h = g["id"].split("~")
        grp = out.setdefault(t, {"id": t, "verdicts": [], "judge_agent": []})
        grp["judge_agent"].append(g["judge_agent"])
        for v in g["verdicts"]:
            grp["verdicts"].append(dict(v, dossier=f"{h}/{v['dossier']}"))
    json.dump(
        sorted(out.values(), key=lambda g: g["id"]),
        open(f"{GATE}/f1/verdicts.json", "w"),
        indent=1,
    )
    print(
        f"merged {len(halves)} half-groups into {len(out)} tasks, "
        f"{sum(len(g['verdicts']) for g in out.values())} verdicts"
    )


def pool(dst, srcs):
    os.makedirs(f"{dst}/f1/keys", exist_ok=True)
    runs, keys, verd, seen = [], {}, {}, set()
    for i, s in enumerate(srcs):
        for line in open(f"{s}/f1/runs.jsonl"):
            r = json.loads(line)
            if (r["task"], r["rep"]) in seen:
                sys.exit(f"refusing: {r['task']} rep {r['rep']} appears in two sources")
            seen.add((r["task"], r["rep"]))
            runs.append(line if line.endswith("\n") else line + "\n")
        for g in json.load(open(f"{s}/f1/verdicts.json")):
            k = json.load(open(f"{s}/f1/keys/{g['id']}.json"))["dossiers"]
            kk = keys.setdefault(g["id"], {"task": g["id"], "dossiers": {}})["dossiers"]
            vv = verd.setdefault(g["id"], {"id": g["id"], "verdicts": []})["verdicts"]
            for name, meta in k.items():
                kk[f"{i}:{name}"] = meta
            for v in g["verdicts"]:
                vv.append(dict(v, dossier=f"{i}:{v['dossier']}"))
    open(f"{dst}/f1/runs.jsonl", "w").writelines(runs)
    for t, k in keys.items():
        json.dump(k, open(f"{dst}/f1/keys/{t}.json", "w"), indent=1)
    json.dump(
        sorted(verd.values(), key=lambda g: g["id"]),
        open(f"{dst}/f1/verdicts.json", "w"),
        indent=1,
    )
    json.dump({"sources": srcs}, open(f"{dst}/f1/SOURCES.json", "w"), indent=1)
    print(
        f"pooled {len(runs)} runs, {sum(len(g['verdicts']) for g in verd.values())} verdicts from {srcs}"
    )


if __name__ == "__main__":
    cmd, rest = sys.argv[1], sys.argv[2:]
    if cmd == "prep":
        prep(rest)
    elif cmd == "merge":
        merge()
    elif cmd == "pool":
        pool(rest[0], rest[1:])
    else:
        sys.exit(__doc__)
