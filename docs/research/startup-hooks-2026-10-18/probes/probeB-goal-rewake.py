#!/usr/bin/env python3
"""Probe B(1) (startup-hooks Wave 6.4, migration 0012): does a Stop hook registered with
asyncRewake defer /goal evaluation on the pinned binary?

Scratch only: HOME, CLAUDE_CONFIG_DIR, the project and the hook live under one mkdtemp dir;
--setting-sources project. The scratch config has no credentials, so the turn and any goal
evaluation fail locally ("Not logged in"); what is observed is whether the harness ATTEMPTS the
goal evaluation at the Stop, i.e. whether a goal-evaluation record reaches the transcript.

Usage: probeB-goal-rewake.py <claude-binary> <evidence-out-dir> <arm> [--keep]
  arm = none      Stop has only a sync marker hook (control)
        rewake    + a Stop hook `sleep 120` with asyncRewake:true (0012's shape)
The initial prompt is a /goal command passed on argv; nothing is typed.
"""

import faulthandler, json, os, pty, re, select, shutil, signal, sys, tempfile, time

faulthandler.dump_traceback_later(150, exit=True)

BIN, OUT, ARM = sys.argv[1], sys.argv[2], sys.argv[3]
KEEP = "--keep" in sys.argv
os.makedirs(OUT, exist_ok=True)
S = os.path.realpath(tempfile.mkdtemp(prefix="w6probeB."))
HOME, CFG, PROJ, P = (os.path.join(S, d) for d in ("home", "cfg", "proj", "p"))
for d in (HOME, CFG, PROJ + "/.claude", P):
    os.makedirs(d)
json.dump(
    {
        "hasCompletedOnboarding": True,
        "theme": "dark",
        "projects": {
            PROJ: {
                "hasTrustDialogAccepted": True,
                "hasCompletedProjectOnboarding": True,
            }
        },
    },
    open(CFG + "/.claude.json", "w"),
)
NOW = "/usr/bin/perl -MTime::HiRes=time -e 'printf \"%.3f\", time'"
open(P + "/mark.sh", "w").write(
    f'#!/bin/bash\ncat >/dev/null; echo "STOP $({NOW})" >> {P}/ev.log\n'
)
open(P + "/slow.sh", "w").write(
    f'#!/bin/bash\ncat >/dev/null; echo "REWAKE_START $({NOW})" >> {P}/ev.log\n'
    f'/bin/sleep 120\necho "REWAKE_END $({NOW})" >> {P}/ev.log\n'
)
stop = [{"type": "command", "command": f"/bin/bash {P}/mark.sh", "timeout": 5}]
if ARM == "rewake":
    stop.append(
        {
            "type": "command",
            "command": f"/bin/bash {P}/slow.sh",
            "timeout": 300,
            "asyncRewake": True,
            "rewakeMessage": "probe rewake",
            "rewakeSummary": "probe",
        }
    )
json.dump(
    {"hooks": {"Stop": [{"hooks": stop}]}},
    open(PROJ + "/.claude/settings.json", "w"),
    indent=1,
)

env = {
    k: os.environ[k]
    for k in ("PATH", "LANG", "USER", "LOGNAME", "TMPDIR")
    if k in os.environ
}
env.update(
    HOME=HOME,
    CLAUDE_CONFIG_DIR=CFG,
    TERM="xterm-256color",
    DISABLE_AUTOUPDATER="1",
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1",
    SHELL="/bin/bash",
)
GOAL = f"/goal the file {P}/never-created exists"
t0 = time.time()
pid, fd = pty.fork()
if pid == 0:
    os.chdir(PROJ)
    os.execve(BIN, [BIN, "--setting-sources", "project", GOAL], env)
buf = b""
while time.time() - t0 < 40:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            d = os.read(fd, 65536)
        except OSError:
            break
        if not d:
            break
        buf += d
os.set_blocking(fd, False)  # a pty whose child is gone must not block the teardown
for _ in range(2):
    try:
        os.write(fd, b"\x03")
    except OSError:
        pass
    time.sleep(0.5)
try:
    os.kill(pid, signal.SIGKILL)
except ProcessLookupError:
    pass
for _ in range(50):
    if os.waitpid(pid, os.WNOHANG)[0]:
        break
    time.sleep(0.1)

ev = open(P + "/ev.log").read().splitlines() if os.path.exists(P + "/ev.log") else []
recs = []
for root, _, files in os.walk(CFG + "/projects"):
    for fn in files:
        if fn.endswith(".jsonl"):
            for ln in open(os.path.join(root, fn)):
                try:
                    recs.append(json.loads(ln))
                except ValueError:
                    pass


def brief(r):
    a = r.get("attachment") or {}
    txt = json.dumps(r)
    return {
        "type": r.get("type"),
        "sub": a.get("type") or r.get("subtype"),
        "hookEvent": a.get("hookEvent"),
        "hookName": a.get("hookName"),
        "goalish": bool(re.search(r"goal", txt, re.I)),
        "excerpt": txt[:400].replace(S, "$S"),
    }


rows = [brief(r) for r in recs]
screen = re.sub(rb"\x1b\[[0-9;?<>=]*[a-zA-Z]|\x1b\][^\x07]*\x07", b"", buf).decode(
    "utf8", "replace"
)
summary = {
    "binary": BIN,
    "arm": ARM,
    "goal": GOAL.replace(S, "$S"),
    "ev_log": ev,
    "records": rows,
    "n_goal_records": sum(r["goalish"] for r in rows),
    "screen_goal_lines": [
        ln.strip()[:200] for ln in screen.splitlines() if re.search(r"goal", ln, re.I)
    ][:20],
    "load": os.getloadavg(),
}
json.dump(summary, open(os.path.join(OUT, f"result-{ARM}.json"), "w"), indent=1)
print(json.dumps({k: summary[k] for k in ("arm", "ev_log", "n_goal_records", "load")}))
for r in rows:
    if r["goalish"] or r["hookEvent"]:
        print(r["type"], r["sub"], r["hookEvent"], r["hookName"], r["excerpt"][:220])
if KEEP:
    print("scratch kept:", S)
else:
    shutil.rmtree(S, ignore_errors=True)
