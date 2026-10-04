#!/usr/bin/env python3
"""hook-profile-bench.py — CPU cost of the hook chain ONE Bash call fires, per hook profile.

Fix row 16, docs/research/concurrency-scale-2026-10-04/README.md (and e-per-agent-cost.md §2): every
Bash call fires the hooks registered for PreToolUse, PostToolUse and PostToolBatch whose matcher takes
"Bash" — 20 of them on 2026-10-04. This replays that chain with a NO-OP payload (`true`), one hook at a
time as Claude Code would spawn it, and sums the CPU of every process it creates (RUSAGE_CHILDREN), so
the number is the dispatch-plus-early-path floor a bulk agent pays per call, not a hook's slow path.

Three profiles, same payload otherwise:
  default   — a top-level session
  lean      — CC_HOOK_PROFILE=lean in the hook env (a headless fleet lead)
  subagent  — the payload carries "agent_id" (an in-process subagent or workflow agent)

The registrations are READ from settings.json (never written); `~/.claude/hooks/X` is mapped to
<repo>/hooks/X so the bench measures THIS checkout. The payload names a throwaway session id and a temp
cwd, so mailbox, beacon and checkpoint hooks find nothing of a real session to act on.

Usage: hook-profile-bench.py [--reps N] [--settings PATH] [--repo DIR] [--profiles default,lean,subagent]
Prints one line per profile (median CPU-s per Bash call over N reps) and, with --per-hook, a table.
"""

import argparse
import json
import os
import re
import resource
import statistics
import subprocess
import tempfile
import time

ap = argparse.ArgumentParser()
ap.add_argument("--reps", type=int, default=5)
ap.add_argument("--settings", default=os.path.expanduser("~/.claude/settings.json"))
ap.add_argument(
    "--repo", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
ap.add_argument("--profiles", default="default,lean,subagent")
ap.add_argument("--per-hook", action="store_true")
a = ap.parse_args()

with open(a.settings) as fh:
    hooks = json.load(fh).get("hooks", {})


def takes_bash(m):
    if m in (None, "", "*"):
        return True
    try:
        return (
            re.fullmatch(m, "Bash") is not None
        )  # "Bash", "^Bash$", "Bash|Write|Edit"
    except re.error:
        return False


chain = []
for ev in ("PreToolUse", "PostToolUse", "PostToolBatch"):
    for grp in hooks.get(ev, []):
        if ev != "PostToolBatch" and not takes_bash(grp.get("matcher")):
            continue
        for h in grp.get("hooks", []):
            cmd = h.get("command", "")
            for pre in ("~/.claude/hooks/", "$HOME/.claude/hooks/"):
                cmd = cmd.replace(pre, a.repo + "/hooks/")
            chain.append((ev, cmd, h.get("timeout", 60)))

cwd = tempfile.mkdtemp(prefix="hook-bench-")
sid = "hook-bench-%d" % os.getpid()


def payload(ev, sub):
    p = {
        "session_id": sid,
        "transcript_path": cwd + "/none.jsonl",
        "cwd": cwd,
        "permission_mode": "default",
        "hook_event_name": ev,
    }
    if sub:
        p["agent_id"] = "a0bench0000000000"
        p["agent_type"] = "general-purpose"
    call = {
        "tool_name": "Bash",
        "tool_input": {"command": "true", "description": "no-op"},
        "tool_use_id": "toolu_bench",
    }
    if ev == "PostToolBatch":
        p["tool_calls"] = [
            dict(call, tool_response={"stdout": "", "stderr": "", "interrupted": False})
        ]
    else:
        p.update(call)
        if ev == "PostToolUse":
            p["tool_response"] = {"stdout": "", "stderr": "", "interrupted": False}
    return json.dumps(p).encode()


def run_chain(profile):
    env = dict(os.environ)
    env.pop("CC_HOOK_PROFILE", None)
    if profile == "lean":
        env["CC_HOOK_PROFILE"] = "lean"
    per = []
    for ev, cmd, to in chain:
        r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
        try:
            subprocess.run(
                ["/bin/bash", "-c", cmd],
                input=payload(ev, profile == "subagent"),
                env=env,
                cwd=cwd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=to,
            )
        except subprocess.TimeoutExpired:
            pass
        r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
        per.append((r1.ru_utime - r0.ru_utime) + (r1.ru_stime - r0.ru_stime))
    return per


print(
    "hooks per Bash call: %d   reps: %d   load1: %.0f"
    % (len(chain), a.reps, os.getloadavg()[0])
)
for prof in a.profiles.split(","):
    runs = [run_chain(prof) for _ in range(a.reps)]
    tot = [sum(r) for r in runs]
    print(
        "%-9s median %.3f CPU-s/call  (min %.3f max %.3f)"
        % (prof, statistics.median(tot), min(tot), max(tot))
    )
    if a.per_hook:
        for i, (ev, cmd, _) in enumerate(chain):
            med = statistics.median(r[i] for r in runs)
            print("    %-13s %.3f  %s" % (ev, med, cmd.replace(a.repo + "/hooks/", "")))
