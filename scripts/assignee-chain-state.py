#!/usr/bin/env python3
"""chain-state — read-only census of the assignee self-close chain, per live member.

Renders, for every member of every team config on this box, the state of each link between
"assignee finished" and "kitty window is gone". Pure measurement: opens no pane, closes nothing.

Links:
  L-done     lead marked it done            (config .members[].isActive == false)
  L-pane     a pane id is recorded          (.tmuxPaneId)
  L-alive    that kitty window still exists  (kitty @ ls)
  L-ident    that window's process set contains --agent-id <member>@<team>   [content-verified]
  L-ladder   defer counter vs MAX_DEFERS     (~/.claude/watchdog/defer-<sid>-<member>.count)
  L-closed   the outcome                     (lifecycle log '✓ closed pane')
"""

import glob
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
MAX_DEFERS = int(os.environ.get("TEAMMATE_MAX_DEFERS", "3"))
LIFECYCLE = os.path.join(HOME, ".claude/logs/teammate-lifecycle.log")


def kitty_windows():
    """{window_id: [cmdline strings of every process in that window]} — {} if unreachable."""
    listen = os.environ.get("KITTY_LISTEN_ON", "")
    cmd = ["kitty", "@"] + (["--to", listen] if listen else []) + ["ls"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        if out.returncode != 0:
            return None
        data = json.loads(out.stdout)
    except Exception:
        return None
    wins = {}
    for osw in data:
        for tab in osw.get("tabs", []):
            for w in tab.get("windows", []):
                procs = [
                    " ".join(p.get("cmdline", []))
                    for p in w.get("foreground_processes", [])
                ]
                procs.append(" ".join(w.get("cmdline", []) or []))
                wins[str(w.get("id"))] = procs
    return wins


def defer_count(sid, member):
    for f in glob.glob(
        os.path.join(HOME, ".claude/watchdog", f"defer-{sid}-{member}.count")
    ):
        try:
            return int(open(f).read().strip())
        except Exception:
            return None
    for f in glob.glob(
        os.path.join(HOME, ".claude/watchdog", f"defer-*-{member}.count")
    ):
        try:
            return int(open(f).read().strip())
        except Exception:
            return None
    return None


def main():
    wins = kitty_windows()
    if wins is None:
        print(
            "kitty remote control UNREACHABLE — L-alive/L-ident are UNKNOWN, not false",
            file=sys.stderr,
        )
        wins = {}

    configs = sorted(
        glob.glob(os.path.join(HOME, ".claude*/teams/*/config.json")),
        key=os.path.getmtime,
        reverse=True,
    )

    rows, stuck = [], 0
    for cfg in configs:
        try:
            d = json.load(open(cfg))
        except Exception:
            continue
        team = os.path.basename(os.path.dirname(cfg))
        for m in d.get("members", []):
            name = m.get("name", "?")
            pane = m.get("tmuxPaneId")
            if not pane or pane == "leader":
                continue
            done = m.get("isActive") is False
            alive = pane in wins
            ident = "n/a"
            if alive:
                needle = f"--agent-id {name}@{team}"
                ident = "OK" if any(needle in p for p in wins[pane]) else "MISMATCH"
            if not alive:
                continue  # only live windows are actionable
            n = defer_count(d.get("leadSessionId", ""), name)
            ladder = f"{n}/{MAX_DEFERS}" if n is not None else "-"
            rows.append((team[-8:], name, pane, done, ident, ladder))
            if done and ident == "OK":
                stuck += 1

    print(
        f"{'team':<10} {'member':<16} {'win':<5} {'lead-done':<10} {'identity':<9} {'ladder'}"
    )
    print("-" * 62)
    for r in rows:
        print(f"{r[0]:<10} {r[1]:<16} {r[2]:<5} {str(r[3]):<10} {r[4]:<9} {r[5]}")

    closes = 0
    last = ""
    if os.path.exists(LIFECYCLE):
        for line in open(LIFECYCLE, errors="replace"):
            if "✓ closed pane" in line:
                closes += 1
                last = line.strip()[:60]

    print()
    print(f"LIVE assignee windows        : {len(rows)}")
    print(f"STUCK (lead-done + identity-verified + window still open): {stuck}")
    print(f"'✓ closed pane' all-time     : {closes}")
    print(f"last close                   : {last or '<none>'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
