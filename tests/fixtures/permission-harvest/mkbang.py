#!/usr/bin/env python3
"""Fixture for tests/cc-permission-harvest-bang.bats: transcript stores holding `!` commands.

Usage: mkbang.py HOME

Writes under HOME:
  .claude/projects/p1/<sid>.jsonl      the primary store, five sessions across three ISO weeks
  .claude-next/projects -> .claude/projects   a SYMLINKED mirror (realpath dedupe)
  .claude-tertiary/projects/p1/copy.jsonl     a COPIED mirror of one session (uuid dedupe)
  .claude/projects/p1/<sid>/subagents/x.jsonl a subagent file carrying the marker (never a bang)
  .claude/settings.json                 one fleet file, json.dumps default (\\u escapes), auto mode
  corpus.log                            an empty widening corpus

The population every arm keys on, by bucket (16 unique bangs; one quote and one subagent marker that
must not count):
  read_only      cc-decide list --open (sessions A, B, C — weeks 1, 2, 3) · cc-do --list (A, B)
                 · cc-custody list (A only — a one-shot, refused on MIN_EVIDENCE)
  consent_gate   bash /tmp/go-live.sh --confirm prod
  privilege      sudo pmset -a sleep 0
  production     aws amplify start-job --app-id x --branch-name main --job-type RELEASE
                 · git -C ~/Development/x push origin main
  live_session   kitten @ close-window --match id:3
  operator_queue cc-do 1a2b3c4d5e6f
  gui_view       open ~/Development/x/index.html
  classifier     fleet-sync now   (the agent's own attempt was classifier-denied, [Self-Modification])
  one_shot       bash ~/.claude/scripts/fixture-one.sh
  compound       cd /tmp/w && git status
"""

import json
import os
import sys

HOME = sys.argv[1]
P = os.path.join(HOME, ".claude", "projects", "p1")
os.makedirs(P, exist_ok=True)
N = [0]


def uid():
    N[0] += 1
    return "u-%04d" % N[0]


def ts(day, sec=0):
    # Weeks: day 1 = 2026-09-01 (ISO week 36), day 9 = week 37, day 16 = week 38.
    return "2026-09-%02dT10:%02d:%02d.000Z" % (day, sec // 60, sec % 60)


def asst(sid, day, sec, text):
    return {
        "type": "assistant",
        "uuid": uid(),
        "sessionId": sid,
        "timestamp": ts(day, sec),
        "message": {"role": "assistant", "content": [{"type": "text", "text": text}]},
    }


def bang(sid, day, sec, cmd, cwd="/Users/x/Development/proj"):
    return {
        "type": "user",
        "uuid": uid(),
        "sessionId": sid,
        "timestamp": ts(day, sec),
        "cwd": cwd,
        "message": {
            "role": "user",
            "content": "<bash-input>%s</bash-input>" % cmd.replace("&", "&amp;"),
        },
    }


def handed(sid, day, sec, cmd, marker=True):
    if marker:
        text = "Done.\n\n▶ Run this:\n\n`%s`\n" % cmd
    else:
        text = "You can check with `%s` if you like." % cmd
    return [asst(sid, day, sec, text), bang(sid, day, sec + 30, cmd)]


def denied_attempt(sid, day, sec, cmd, category):
    tid = "toolu_%s" % uid()
    return [
        {
            "type": "assistant",
            "uuid": uid(),
            "sessionId": sid,
            "timestamp": ts(day, sec),
            "message": {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "id": tid,
                        "name": "Bash",
                        "input": {"command": cmd},
                    }
                ],
            },
        },
        {
            "type": "user",
            "uuid": uid(),
            "sessionId": sid,
            "timestamp": ts(day, sec + 5),
            "message": {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": tid,
                        "is_error": True,
                        "content": "Permission for this action was denied by the Claude Code auto mode "
                        "classifier. Reason: %s. If you have other tasks…" % category,
                    }
                ],
            },
        },
    ]


def quote_record(sid, day, sec):
    # A tool result that QUOTES the marker: a grep over transcripts, never an operator command.
    return {
        "type": "user",
        "uuid": uid(),
        "sessionId": sid,
        "timestamp": ts(day, sec),
        "toolUseResult": {"stdout": "x"},
        "message": {
            "role": "user",
            "content": [
                {
                    "type": "tool_result",
                    "tool_use_id": "toolu_q",
                    "content": "match: <bash-input>rm -rf /</bash-input>",
                }
            ],
        },
    }


def write(path, recs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        for r in recs:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")


A, B, C, D, E = ("sess-a", "sess-b", "sess-c", "sess-d", "sess-e")
sa = (
    handed(A, 1, 0, "cc-decide list --open")
    + handed(A, 1, 100, "cc-do --list")
    + handed(A, 1, 200, "cc-custody list")
    + handed(A, 1, 300, "bash /tmp/go-live.sh --confirm prod")
    + handed(A, 1, 400, "sudo pmset -a sleep 0")
    + [quote_record(A, 1, 500)]
)
sb = (
    handed(B, 9, 0, "cc-decide list --open")
    + handed(B, 9, 100, "cc-do --list")
    + handed(
        B,
        9,
        200,
        "aws amplify start-job --app-id x --branch-name main --job-type RELEASE",
    )
    + handed(B, 9, 300, "kitten @ close-window --match id:3")
    + handed(B, 9, 400, "git -C ~/Development/x push origin main")
)
sc = (
    handed(C, 16, 0, "cc-decide list --open", marker=False)
    + handed(C, 16, 100, "cc-do 1a2b3c4d5e6f")
    + handed(C, 16, 200, "open ~/Development/x/index.html")
)
sd = (
    denied_attempt(D, 16, 0, "fleet-sync now", "[Self-Modification]")
    + handed(D, 16, 100, "fleet-sync now")
    + handed(D, 16, 200, "bash ~/.claude/scripts/fixture-one.sh")
)
se = [bang(E, 16, 0, "cd /tmp/w && git status")]  # typed unprompted: no hand-off
for sid, recs in ((A, sa), (B, sb), (C, sc), (D, sd), (E, se)):
    write(os.path.join(P, sid + ".jsonl"), recs)
write(
    os.path.join(P, A, "subagents", "agent-x.jsonl"),
    [bang(A, 1, 900, "cc-decide list --all")],
)

os.makedirs(os.path.join(HOME, ".claude-next"), exist_ok=True)
os.symlink(
    os.path.join(HOME, ".claude", "projects"),
    os.path.join(HOME, ".claude-next", "projects"),
)
write(os.path.join(HOME, ".claude-tertiary", "projects", "p1", "copy.jsonl"), sb)

settings = {
    "permissions": {
        "defaultMode": "auto",
        "allow": ["Bash(git status:*)"],
        "deny": ["Bash(rm -rf:*)"],
    },
    "autoMode": {
        "soft_deny": [
            "Production Deploy: deploying to production — or "
            "running production migrations"
        ]
    },
}
with open(os.path.join(HOME, ".claude", "settings.json"), "w") as fh:
    fh.write(json.dumps(settings, indent=2) + "\n")
open(os.path.join(HOME, "corpus.log"), "w").close()
