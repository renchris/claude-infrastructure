"""prep_replay.py - turn the seed authors' raw output into seed files, and write the reviewer job lists.

Steps (each re-runnable):
  seeds   parse seedwork/out/<id>.last (JSON, possibly fenced) into seeds/<id>.json
  jobs    write replay/codex-jobs.json (the two OpenAI slots per plan: full, plan-only) and
          replay/opus-slots.json (the four Anthropic slots per plan: A full, A plan, D full, D plan)
usage: python3 prep_replay.py <cache_dir> seeds|jobs
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def parse_json(txt):
    m = re.search(r"```(?:json)?\s*(\{.*\})\s*```", txt, re.S)
    if m:
        txt = m.group(1)
    i, j = txt.find("{"), txt.rfind("}")
    return json.loads(txt[i : j + 1])


def seeds(C):
    os.makedirs(os.path.join(C, "seeds"), exist_ok=True)
    for fn in sorted(os.listdir(os.path.join(C, "seedwork", "out"))):
        if not fn.endswith(".last"):
            continue
        pid = fn[:-5]
        try:
            sd = parse_json(open(os.path.join(C, "seedwork", "out", fn)).read())[
                "seeds"
            ]
        except Exception as e:  # noqa: BLE001 - a malformed seed set is recorded, not guessed
            print("%-32s UNPARSEABLE %s" % (pid, e))
            continue
        for k, s in enumerate(sd):
            s["seed_id"] = "%s-S%d" % (pid, k + 1)
        json.dump(sd, open(os.path.join(C, "seeds", pid + ".json"), "w"), indent=1)
        print(
            "%-32s %d seeds, omission=%d"
            % (pid, len(sd), sum(1 for s in sd if s.get("omission")))
        )


def jobs(C):
    brief = open(os.path.join(HERE, "briefs", "reviewer.md")).read()
    codex, opus = [], []
    for pid in sorted(os.listdir(os.path.join(C, "bundles"))):
        for strat in ("full", "plan"):
            cwd = os.path.join(C, "bundles", pid, strat)
            codex.append(dict(id="%s__B_%s" % (pid, strat), cwd=cwd, prompt=brief))
            for fam in ("A", "D"):
                opus.append(
                    dict(
                        id="%s__%s_%s" % (pid, fam, strat),
                        plan=pid,
                        family=fam,
                        strategy=strat,
                        cwd=cwd,
                    )
                )
    os.makedirs(os.path.join(C, "replay"), exist_ok=True)
    json.dump(codex, open(os.path.join(C, "replay", "codex-jobs.json"), "w"))
    json.dump(opus, open(os.path.join(C, "replay", "opus-slots.json"), "w"))
    print("codex jobs %d, opus slots %d" % (len(codex), len(opus)))


if __name__ == "__main__":
    {"seeds": seeds, "jobs": jobs}[sys.argv[2]](sys.argv[1])
