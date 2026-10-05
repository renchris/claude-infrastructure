#!/usr/bin/env python3
"""Measure the three classifier configurations on the TUNING set (never a sealed set), for wave E1c's
pre-registered choice rule (docs/plans/RESEARCH_PROGRAM_BUILD.md, wave E1c).

  e1c-tune.py REPS OUT.json

Arms, one cold `claude -p` call per tuning row and repeat, the three arms started at the same instant
so they see the same machine load:
  on-pre    the router as built on trunk (thinking on)
  on-e1b    wave E1b's patch (../router-classifier-e1b-2026-10-04/e1b-classifier.patch), thinking on
  off-e1b   the same patch with thinking off

Each call gets 30 s. The label and the wall time are recorded apart, so one pass gives both what the
arm labels (with time to answer) and whether it would have answered inside the router's 9 s limit.
Results are keyed by tuning row index; no prompt text is written.
"""

import concurrent.futures as cf
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
PATCH = (
    Path(__file__).resolve().parent.parent
    / "router-classifier-e1b-2026-10-04/e1b-classifier.patch"
)
H = Path.home() / ".claude/autonomy/research/router-heldout"
NO_THINK = ["--settings", '{"alwaysThinkingEnabled":false}']


def load_router(kit_dir: Path, name: str):
    sys.path.insert(0, str(kit_dir / "lib"))
    sys.path.insert(0, str(kit_dir))
    spec = importlib.util.spec_from_file_location(name, kit_dir / "router.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def arms():
    pre = load_router(KIT, "router_pre")
    copy = Path(tempfile.mkdtemp(prefix="e1c-router-")) / "repo"
    shutil.copytree(KIT, copy / "scripts/research-kit")
    subprocess.run(
        ["git", "apply", "--include=scripts/research-kit/router.py", str(PATCH)],
        cwd=copy,
        check=True,
    )
    e1b = load_router(copy / "scripts/research-kit", "router_e1b")
    return pre.ROUTES, {
        "on-pre": (pre.classifier_argv(), pre.CLASSIFIER_BRIEF),
        "on-e1b": (e1b.classifier_argv(), e1b.CLASSIFIER_BRIEF),
        "off-e1b": (e1b.classifier_argv() + NO_THINK, e1b.CLASSIFIER_BRIEF),
    }


def call(argv, brief, prompt, routes):
    d = tempfile.mkdtemp(prefix="e1c-call-")
    t0 = time.time()
    try:
        p = subprocess.run(
            argv,
            input=brief.format(cert="(none rendered)", prompt=prompt),
            capture_output=True,
            text=True,
            timeout=30,
            cwd=d,
            env=dict(os.environ, CC_RESEARCH_ROUTER_INNER="1"),
        )
        words = p.stdout.replace(",", " ").split()
        lab = (
            words[0]
            if p.returncode == 0 and len(words) == 1 and words[0] in routes
            else "INVALID"
        )
    except subprocess.TimeoutExpired:
        lab = "TIMEOUT"
    finally:
        shutil.rmtree(d, ignore_errors=True)
    return lab, round(time.time() - t0, 2)


def main():
    reps, out = int(sys.argv[1]), Path(sys.argv[2])
    rows = [json.loads(l) for l in open(H / "tuning.jsonl")]
    routes, A = arms()
    res = {a: {} for a in A}
    with cf.ThreadPoolExecutor(len(A)) as ex:
        for rep in range(reps):
            for k, row in enumerate(rows):
                load = os.getloadavg()[0]
                futs = {
                    a: ex.submit(call, A[a][0], A[a][1], row["prompt"], routes)
                    for a in A
                }
                for a, f in futs.items():
                    lab, wall = f.result()
                    res[a].setdefault(str(k), []).append(
                        {"label": lab, "wall_s": wall, "load": round(load, 1)}
                    )
            out.write_text(
                json.dumps(
                    {"reps_done": rep + 1, "rows": len(rows), "arms": res},
                    sort_keys=True,
                )
            )
    print(f"{reps} repeat(s) x {len(rows)} tuning row(s) x {len(A)} arm(s) -> {out}")


if __name__ == "__main__":
    main()
