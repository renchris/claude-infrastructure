"""Replay reconstructed PreToolUse cancels against a hook, in a hermetic HOME, and say where the time went.

Usage: python3 -I a9-replay-pretooluse.py <hook-path> <cases-dir> [--repo <checkout>] [--trace <bash>]
                                          [--timeout <s>] [--json <out.json>]

<cases-dir> is cutreplay.py's output (`--event PreToolUse`): one <k>/stdin.json per cancel.
Each case runs `/bin/bash <hook> < stdin.json` (the interpreter the harness uses) with
  HOME = <cases-dir>/<k>/home, holding only .claude/{hooks,bin,scripts} symlinked to <repo>'s code,
so every log, state file and audit row the hook writes (validate-bash appends to
$HOME/.claude/logs/validate-bash-decisions.jsonl and friends) lands in the case dir, never the
live layer. CLAUDE_CONFIG_DIR is unset for the same reason. The case's cwd is used when it still
exists (git reads only), else the hermetic HOME.
--trace <bash> re-runs each case under `<bash> -x` (pass /bin/bash: the time can depend on the
interpreter — measured 2026-10-19, one validate-bash replay took 16.7 s under 3.2 and 0.3 s under 5.3)
and charges every trace line the time until the next one ARRIVES (see traced()); the report lists
the slowest source lines summed over all cases. Tracing slows a run; read its shares, not its totals.
Prints one line per case (ms, rc, decision) and the top lines; --json writes everything.
"""

import collections
import json
import os
import re
import subprocess
import sys
import time

argv = sys.argv[1:]
hook, cases = os.path.abspath(argv[0]), os.path.abspath(argv[1])
opt = {"--repo": None, "--trace": None, "--timeout": "60", "--json": None}
i = 2
while i < len(argv):
    if argv[i] in opt and i + 1 < len(argv):
        opt[argv[i]] = argv[i + 1]
        i += 2
    else:
        sys.exit("unknown argument: " + argv[i])
repo = os.path.abspath(opt["--repo"] or os.path.join(os.path.dirname(hook), ".."))
tmo = float(opt["--timeout"])


def hermetic_home(case):
    h = os.path.join(case, "home")
    c = os.path.join(h, ".claude")
    os.makedirs(c, exist_ok=True)
    for sub in ("hooks", "bin", "scripts"):
        link = os.path.join(c, sub)
        if not os.path.lexists(link):
            os.symlink(os.path.join(repo, sub), link)
    return h


def env_for(home):
    e = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE_CONFIG_DIR")}
    e["HOME"] = home
    # The live layer's bin dir points back at the real HOME; the hermetic one resolves the same code.
    e["PATH"] = ":".join(
        os.path.join(home, ".claude/bin")
        if p.rstrip("/").endswith("/.claude/bin")
        else p
        for p in e.get("PATH", "/usr/bin:/bin").split(":")
    )
    return e


def run(cmd, stdin, cwd, env):
    t = time.perf_counter()
    try:
        p = subprocess.run(
            cmd, stdin=stdin, cwd=cwd, env=env, capture_output=True, timeout=tmo
        )
        rc, out, err = p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired as x:
        rc, out, err = "timeout", x.stdout or b"", x.stderr or b""
    return (time.perf_counter() - t) * 1000, rc, out, err


def decision(out):
    try:
        o = json.loads(out.decode(errors="replace").strip().splitlines()[-1])
    except (ValueError, IndexError):
        return "allow" if not out.strip() else "unparsed"
    return (
        ((o.get("hookSpecificOutput") or {}).get("permissionDecision"))
        or o.get("decision")
        or "?"
    )


TRACE = re.compile(rb"^\++([^ :]*):(\d+) ")


def traced(bash, sp, cwd, env):
    """Run under `bash -x` and stamp each trace line as it ARRIVES on the pipe: /bin/bash 3.2 (the
    harness's interpreter, and the one where the time goes) has no clock to put in PS4. bash writes
    each trace line with its own write(2), so arrival order is real-time order, and the gap after a
    line is charged to it whichever process wrote it (a subshell's lines interleave with its parent's,
    in the order they happened)."""
    tenv = dict(env, PS4="+${BASH_SOURCE##*/}:$LINENO ")
    t0 = time.perf_counter()
    prev, n = None, 0
    with open(sp, "rb") as fh:
        p = subprocess.Popen([bash, "-x", hook], stdin=fh, cwd=cwd, env=tenv,
                             stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for ln in p.stderr:
            now = time.perf_counter()
            if now - t0 > tmo:
                p.kill()
                break
            m = TRACE.match(ln)
            if not m:
                continue
            n += 1
            if prev is not None:
                lines_ms[prev[1]] += (now - prev[0]) * 1000
                lines_n[prev[1]] += 1
            prev = (now, (m.group(1).decode(errors="replace"), int(m.group(2))))
        p.wait()
    if prev is not None:   # the last line runs until the process ends
        lines_ms[prev[1]] += (time.perf_counter() - prev[0]) * 1000
        lines_n[prev[1]] += 1
    return (time.perf_counter() - t0) * 1000, n


lines_ms = collections.Counter()
lines_n = collections.Counter()
report = []
for k in sorted((d for d in os.listdir(cases) if d.isdigit()), key=int):
    case = os.path.join(cases, k)
    sp = os.path.join(case, "stdin.json")
    if not os.path.isfile(sp):
        continue
    payload = json.load(open(sp))
    home = hermetic_home(case)
    cwd = payload.get("cwd") or ""
    cwd = cwd if os.path.isdir(cwd) else home
    env = env_for(home)
    with open(sp, "rb") as fh:
        ms, rc, out, err = run(["/bin/bash", hook], fh, cwd, env)
    row = {
        "case": k,
        "ms": round(ms),
        "rc": rc,
        "decision": decision(out),
        "command": (payload.get("tool_input") or {}).get("command", "")[:160],
    }
    if opt["--trace"]:
        tms, nlines = traced(opt["--trace"], sp, cwd, env)
        row["trace_ms"], row["trace_lines"] = round(tms), nlines
    report.append(row)
    print(
        k,
        row["ms"],
        "ms",
        "rc=%s" % rc,
        row["decision"],
        row.get("trace_ms", ""),
        row["command"][:80],
    )

srcs = {}


def src_line(fn, no):
    """The traced line's text, from the hook or a lib beside it (blank when it cannot be found)."""
    if fn not in srcs:
        hd = os.path.dirname(hook)
        cands = [
            os.path.join(hd, fn),
            os.path.join(hd, "lib", fn),
            os.path.join(repo, "scripts/lib", fn),
        ]
        path = next((c for c in cands if os.path.isfile(c)), None)
        srcs[fn] = open(path, errors="replace").read().split("\n") if path else []
    s = srcs[fn]
    return s[no - 1].strip()[:120] if 0 < no <= len(s) else ""


top = []
total = sum(lines_ms.values()) or 1
for (fn, no), v in lines_ms.most_common(15):
    top.append(
        {
            "file": fn,
            "line": no,
            "ms": round(v),
            "share": round(v / total, 3),
            "hits": lines_n[(fn, no)],
            "src": src_line(fn, no),
        }
    )
if top:
    print("top traced lines (ms summed over cases, share of traced time):")
    for t in top:
        print(
            "  %s:%d  %6d ms  %5.1f%%  x%d  %s"
            % (t["file"], t["line"], t["ms"], 100 * t["share"], t["hits"], t["src"])
        )
if opt["--json"]:
    with open(opt["--json"], "w") as fh:
        json.dump({"hook": hook, "cases": report, "top_lines": top}, fh, indent=1)
