#!/usr/bin/env python3
"""Wave E1h's tuning run: every candidate classifier call, to completion, on the tuning base (never
a sealed set). RULE 1 in docs/plans/RESEARCH_PROGRAM_BUILD.md (wave E1h) was committed before this ran;
e1h-score.py is that rule as code.

  e1h-tune.py OUT.json [--limit N]

The tuning base, all outside the repo in ~/.claude/autonomy/research/router-heldout/:
  fresh   tuning-v4.jsonl     drawn by `heldout.py draw`            1 call per arm
  v2      retired-v2.jsonl    written by `heldout.py --set v2 retire`  1 call per arm
  v1      tuning.jsonl        wave B1's tuning split                 2 calls per arm

Arms, one cold `claude -p` call each, the four started at the same instant for a row so they see the
same machine load; rows run one after another:
  haiku-off    the live fast call: wave E1b's brief and system prompt, thinking off, haiku_latest
  haiku-on     the live careful call: the brief as built, thinking on, haiku_latest
  sonnet-off   the fast call's exact command line and brief with the model swapped to Sonnet 5.5
  sonnet-on    the careful call's exact command line and brief with the model swapped to Sonnet 5.5
The briefs are the router's own, frozen: nothing here edits a word of them.

Each call gets 30 s. The label and the wall time are recorded apart, so the offline replay can apply
any join rule and the router's 9 s limit afterwards. Results are keyed by source and heldout.py item
id; no prompt text is written. The run can be stopped and started again: a row already in OUT is kept.
It stops itself when four rows in a row get no valid label from any arm (a logged-out or limited
account would otherwise fill the file with failures).
"""

import concurrent.futures as cf
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
KIT = REPO / "scripts/research-kit"
H = Path.home() / ".claude/autonomy/research/router-heldout"
SONNET = "claude-sonnet-5-5"
SOURCES = (
    ("fresh", "tuning-v4.jsonl", 1),
    ("v2", "retired-v2.jsonl", 1),
    ("v1", "tuning.jsonl", 2),
)

sys.path.insert(0, str(KIT / "lib"))
sys.path.insert(0, str(KIT))
spec = importlib.util.spec_from_file_location("router_e1h", KIT / "router.py")
R = importlib.util.module_from_spec(spec)
spec.loader.exec_module(R)


def argv(kind: str, model: str) -> list:
    f = list(R.classifier_flags(kind))
    f[f.index("--model") + 1] = model
    return [shutil.which("claude")] + f


def arms() -> dict:
    haiku = R.haiku_model()
    return {
        "haiku-off": (argv("fast", haiku), R.BRIEFS["fast"]),
        "haiku-on": (argv("careful", haiku), R.BRIEFS["careful"]),
        "sonnet-off": (argv("fast", SONNET), R.BRIEFS["fast"]),
        "sonnet-on": (argv("careful", SONNET), R.BRIEFS["careful"]),
    }


def call(cmd: list, brief: str, prompt: str) -> dict:
    d = tempfile.mkdtemp(prefix="e1h-call-")
    t0 = time.time()
    rc = None
    try:
        p = subprocess.run(
            cmd,
            input=brief.format(cert="(none rendered)", prompt=prompt),
            capture_output=True,
            text=True,
            timeout=30,
            cwd=d,
            env=dict(os.environ, CC_RESEARCH_ROUTER_INNER="1"),
        )
        rc = p.returncode
        words = p.stdout.replace(",", " ").split()
        lab = (
            words[0]
            if rc == 0 and len(words) == 1 and words[0] in R.ROUTES
            else "INVALID"
        )
    except subprocess.TimeoutExpired:
        lab = "TIMEOUT"
    finally:
        shutil.rmtree(d, ignore_errors=True)
    return {"label": lab, "wall_s": round(time.time() - t0, 2), "rc": rc}


def rows() -> list:
    out = []
    for src, name, reps in SOURCES:
        seen = set()
        for line in open(H / name):
            r = json.loads(line)
            k = hashlib.sha256(r["prompt"].encode()).hexdigest()[:12]
            if k in seen:
                continue
            seen.add(k)
            out.append((f"{src}:{k}", r["prompt"], reps))
    return out


def main() -> int:
    out = Path(sys.argv[1])
    limit = (
        int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else None
    )
    A = arms()
    todo = rows()[:limit]
    data = json.loads(out.read_text()) if out.exists() else {"calls": {}, "meta": {}}
    data["meta"].update(
        haiku_model=R.haiku_model(),
        sonnet_model=SONNET,
        classifier_config=R.classifier_config(),
        rows=len(todo),
        arms=sorted(A),
    )
    data["meta"].setdefault("started", time.strftime("%Y-%m-%dT%H:%M:%S%z"))
    dead = 0
    with cf.ThreadPoolExecutor(len(A)) as ex:
        for n, (key, prompt, reps) in enumerate(todo):
            have = data["calls"].get(key) or {}
            while min((len(have.get(a, [])) for a in A), default=0) < reps:
                load = round(os.getloadavg()[0], 1)
                futs = {a: ex.submit(call, A[a][0], A[a][1], prompt) for a in A}
                got = {a: dict(f.result(), load=load) for a, f in futs.items()}
                for a in A:
                    have.setdefault(a, []).append(got[a])
                data["calls"][key] = have
                dead = (
                    dead + 1
                    if all(g["label"] in ("INVALID", "TIMEOUT") for g in got.values())
                    else 0
                )
                data["meta"].update(
                    rows_done=n + 1, updated=time.strftime("%Y-%m-%dT%H:%M:%S%z")
                )
                out.write_text(json.dumps(data, sort_keys=True))
                if dead >= 4:
                    print(
                        f"STOPPED at row {n + 1}: four rows in a row with no valid label from any arm"
                    )
                    return 3
    data["meta"]["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    out.write_text(json.dumps(data, sort_keys=True))
    print(f"DONE {len(todo)} row(s) x {len(A)} arm(s) -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
