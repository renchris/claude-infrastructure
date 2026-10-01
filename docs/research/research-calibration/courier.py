"""courier.py - run OpenAI (codex) jobs for the A3 replay, in parallel, and relay their raw output verbatim.

A job is {"id", "cwd", "prompt"}. Each runs as
  codex exec -s read-only --skip-git-repo-check --ephemeral --ignore-rules -m <pinned> \
             -c model_reasoning_effort=high -C <cwd> -o <out>/<id>.last <prompt>
The responding model id and the token count are read from codex's own log; a mismatch with the pin voids
the job. An integrity grep voids any job whose output names an absolute path outside its bundle.

usage: python3 courier.py <jobs.json> <out_dir> [concurrency]
"""

import concurrent.futures as cf
import json
import os
import re
import subprocess
import sys
import time

CODEX = os.path.expanduser("~/.local/bin/codex")
PIN = "gpt-5.6-sol"


def run(job, out_dir):
    last = os.path.join(out_dir, job["id"] + ".last")
    log = os.path.join(out_dir, job["id"] + ".log")
    if os.path.exists(last) and os.path.getsize(last) > 0:
        return dict(id=job["id"], skipped=True)
    t0 = time.time()
    cmd = [
        CODEX,
        "exec",
        "-s",
        "read-only",
        "--skip-git-repo-check",
        "--ephemeral",
        "--ignore-rules",
        "-m",
        PIN,
        "-c",
        "model_reasoning_effort=high",
        "-C",
        job["cwd"],
        "-o",
        last,
        job["prompt"],
    ]
    attempts = 0
    while True:
        attempts += 1
        with open(log, "w") as fh:
            p = subprocess.run(
                cmd, stdout=fh, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL
            )
        txt = open(log, errors="replace").read()
        ok = p.returncode == 0 and os.path.exists(last) and os.path.getsize(last) > 0
        if ok or attempts >= 3:
            break
        time.sleep(20 * attempts)
    model = (re.search(r"^model: (\S+)", txt, re.M) or [None, None])[1]
    tok = re.search(r"tokens used\s*\n\s*([\d,]+)", txt)
    tokens = int(tok.group(1).replace(",", "")) if tok else None
    bundle = os.path.realpath(job["cwd"])
    # integrity: only what codex EXECUTED counts (a plan may quote absolute paths in its own text, and a
    # reviewer quoting them is not a leak); a command run elsewhere or naming an outside path voids the job
    execs = "\n".join(re.findall(r"^/bin/(?:zsh|bash|sh) -lc .*$", txt, re.M))
    leaks = sorted(
        {
            m
            for m in re.findall(r"/Users/[\w.-]+/[\w./-]+", execs)
            if not os.path.realpath(m).startswith(bundle)
        }
    )
    void = None
    if not ok:
        void = "no-output rc=%s" % p.returncode
    elif model != PIN:
        void = "model-mismatch %s" % model
    elif leaks:
        void = "integrity: " + ", ".join(leaks[:5])
    rec = dict(
        id=job["id"],
        rc=p.returncode,
        attempts=attempts,
        seconds=round(time.time() - t0, 1),
        model=model,
        tokens=tokens,
        void=void,
        leaks=leaks[:20],
    )
    json.dump(rec, open(os.path.join(out_dir, job["id"] + ".meta.json"), "w"))
    return rec


if __name__ == "__main__":
    jobs = json.load(open(sys.argv[1]))
    out_dir = sys.argv[2]
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    os.makedirs(out_dir, exist_ok=True)
    with cf.ThreadPoolExecutor(n) as ex:
        for rec in ex.map(lambda j: run(j, out_dir), jobs):
            print(json.dumps(rec), flush=True)
