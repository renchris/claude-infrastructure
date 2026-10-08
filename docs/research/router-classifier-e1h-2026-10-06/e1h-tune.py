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

Wave E1j (2026-10-08) made every arm explicit, because `haiku_latest` moved to claude-haiku-5-5 and the
E1h arms silently followed it (R.haiku_model()):

  e1h-tune.py OUT.json --arm NAME,KIND,MODEL,EFFORT,CLAUDE_BIN [--arm ...] [--limit N]
              [--max-load 40] [--preflight-only]

  KIND        fast or careful: which of the router's frozen command lines and briefs the arm runs
  MODEL       the --model value, written in full (no alias, no model-config lookup)
  EFFORT      the --effort value, or `-` for no --effort flag (the as-built daemon's command line)
  CLAUDE_BIN  the claude binary, by path; its `--version` is recorded per arm

Before any tuning row, a one-call preflight per arm (`--output-format json`, a made-up prompt, never a
tuning row) prints the model the binary SERVED (the result's `modelUsage`) and aborts (exit 4) when
it is not the arm's MODEL. A row starts only while the 1-min load is at most --max-load (default 40);
above it the run pauses between rows, and every call records the load at its start. An INVALID call
records why (exit code, the first 60 characters of what it answered, the tail of its stderr). It
refuses to write tune.json, E1h's record.

Wave E1m (2026-10-08): an arm may name a brief file as a sixth field, NAME,KIND,MODEL,EFFORT,CLAUDE_BIN,
BRIEF_FILE: the file is the whole brief, a format string with {cert} and {prompt} as the router's are,
and its sha256 is recorded per arm. Without it the arm runs the router's frozen brief for its KIND. It
also refuses to write tune-h55.json, E1j's record.
"""

import argparse
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
H = Path(
    os.environ.get("E1H_TUNING_BASE")
    or Path.home() / ".claude/autonomy/research/router-heldout"
)
PAUSE_POLL_S = float(os.environ.get("E1H_PAUSE_POLL_S") or 20)
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


PREFLIGHT_PROMPT = "is the classifier answering?"  # made up; never a tuning row


def argv(kind: str, model: str, effort: str, claude_bin: str) -> list:
    """The router's frozen command line for KIND with only --model replaced and --effort added."""
    f = list(R.classifier_flags(kind))
    f[f.index("--model") + 1] = model
    if "--effort" in f:  # a kind the router pins an effort for: the arm's EFFORT replaces it
        i = f.index("--effort")
        del f[i : i + 2]
    if effort != "-":
        f[1:1] = ["--effort", effort]
    return [claude_bin] + f


def parse_arm(spec: str) -> tuple:
    parts = spec.split(",")
    if len(parts) not in (5, 6) or parts[1] not in R.KINDS:
        raise SystemExit(
            f"--arm wants NAME,KIND,MODEL,EFFORT,CLAUDE_BIN[,BRIEF_FILE]; got {spec!r}"
        )
    name, kind, model, effort, claude_bin = parts[:5]
    if not os.access(claude_bin, os.X_OK):
        raise SystemExit(f"--arm {name}: {claude_bin} is not an executable")
    arm = {
        "kind": kind,
        "model": model,
        "effort": effort,
        "claude_bin": claude_bin,
    }
    if len(parts) == 6:
        text = Path(parts[5]).read_text()
        if "{prompt}" not in text or "{cert}" not in text:
            raise SystemExit(f"--arm {name}: {parts[5]} has no {{cert}} or {{prompt}} field")
        arm["brief_file"] = parts[5]
        arm["brief_sha256"] = hashlib.sha256(text.encode()).hexdigest()
    return name, arm


def arms(specs: list) -> dict:
    out = {}
    for spec in specs:
        name, a = parse_arm(spec)
        a["argv"] = argv(a["kind"], a["model"], a["effort"], a["claude_bin"])
        a["brief"] = (
            Path(a["brief_file"]).read_text() if "brief_file" in a else R.BRIEFS[a["kind"]]
        )
        out[name] = a
    return out


def version(claude_bin: str) -> str:
    p = subprocess.run(
        [claude_bin, "--version"], capture_output=True, text=True, timeout=30
    )
    return p.stdout.strip()


def preflight(A: dict) -> dict:
    """One call per arm with --output-format json: {arm: served model ids}. Exits 4 on a mismatch."""
    served, bad = {}, []
    for name, a in sorted(A.items()):
        d = tempfile.mkdtemp(prefix="e1j-preflight-")
        try:
            p = subprocess.run(
                a["argv"] + ["--output-format", "json"],
                input=a["brief"].format(
                    cert="(none rendered)", prompt=PREFLIGHT_PROMPT
                ),
                capture_output=True,
                text=True,
                timeout=60,
                cwd=d,
                env=dict(os.environ, CC_RESEARCH_ROUTER_INNER="1"),
            )
            out = json.loads(p.stdout or "{}")
        except (subprocess.TimeoutExpired, ValueError) as e:
            out = {"error": e.__class__.__name__}
        finally:
            shutil.rmtree(d, ignore_errors=True)
        models = sorted((out.get("modelUsage") or {}).keys())
        served[name] = models
        ok = any(m == a["model"] or m.startswith(a["model"] + "-") for m in models)
        print(
            f"preflight {name}: {a['version']} --model {a['model']} --effort {a['effort']}: "
            f"served {models or 'nothing'}; answered {str(out.get('result', ''))[:40]!r}; "
            + ("ok" if ok else "MISMATCH")
        )
        if not ok:
            bad.append(name)
    if bad:
        print(f"ABORT: the served model is not the arm's model for {', '.join(bad)}")
        sys.exit(4)
    return served


def call(cmd: list, brief: str, prompt: str) -> dict:
    d = tempfile.mkdtemp(prefix="e1h-call-")
    t0 = time.time()
    rc = None
    why = ""
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
        if lab == "INVALID":
            why = f"rc={rc}; answered {p.stdout.strip()[:60]!r}; stderr {p.stderr.strip()[-120:]!r}"
    except subprocess.TimeoutExpired:
        lab, why = "TIMEOUT", "no answer in 30 s"
    finally:
        shutil.rmtree(d, ignore_errors=True)
    got = {"label": lab, "wall_s": round(time.time() - t0, 2), "rc": rc}
    if why:
        got["why"] = why
    return got


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


def wait_for_load(max_load: float, pauses: dict) -> None:
    """Return once the 1-min load is at most max_load; count the pause in `pauses`."""
    t0 = None
    while os.getloadavg()[0] > max_load:
        if t0 is None:
            t0 = time.time()
            print(
                f"paused at load {os.getloadavg()[0]:.1f} (> {max_load:g}) "
                + time.strftime("%H:%M:%S"),
                flush=True,
            )
        time.sleep(PAUSE_POLL_S)
    if t0 is not None:
        pauses["n"] = pauses.get("n", 0) + 1
        pauses["s"] = round(pauses.get("s", 0) + time.time() - t0)
        print("resumed " + time.strftime("%H:%M:%S"), flush=True)


def main() -> int:
    ap = argparse.ArgumentParser(prog="e1h-tune.py")
    ap.add_argument("out")
    ap.add_argument("--arm", action="append", required=True)
    ap.add_argument("--limit", type=int)
    ap.add_argument("--max-load", type=float, default=40.0)
    ap.add_argument("--preflight-only", action="store_true")
    a = ap.parse_args()
    out = Path(a.out)
    if out.name in ("tune.json", "tune-h55.json"):
        print(f"refused: {out.name} is an earlier wave's record; write a new file")
        return 2
    A = arms(a.arm)
    for arm in A.values():
        arm["version"] = version(arm["claude_bin"])
    served = preflight(A)
    if a.preflight_only:
        return 0
    todo = rows()[: a.limit]
    data = json.loads(out.read_text()) if out.exists() else {"calls": {}, "meta": {}}
    data["meta"].update(
        classifier_config=R.classifier_config(),
        rows=len(todo),
        arms=sorted(A),
        arm_spec={
            n: {k: v for k, v in arm.items() if k not in ("argv", "brief")}
            | {"served": served[n]}
            for n, arm in A.items()
        },
        max_load=a.max_load,
    )
    data["meta"].setdefault("started", time.strftime("%Y-%m-%dT%H:%M:%S%z"))
    pauses = data["meta"].setdefault("pauses", {})
    dead = 0
    with cf.ThreadPoolExecutor(len(A)) as ex:
        for n, (key, prompt, reps) in enumerate(todo):
            have = data["calls"].get(key) or {}
            while min((len(have.get(x, [])) for x in A), default=0) < reps:
                wait_for_load(a.max_load, pauses)
                load = round(os.getloadavg()[0], 1)
                futs = {
                    x: ex.submit(call, A[x]["argv"], A[x]["brief"], prompt) for x in A
                }
                got = {x: dict(f.result(), load=load) for x, f in futs.items()}
                for x in A:
                    have.setdefault(x, []).append(got[x])
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
