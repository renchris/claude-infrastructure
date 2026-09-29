#!/usr/bin/env python3
"""Build a fake $HOME for tests/cc-hook-asks.bats: transcripts in two account dirs (one a real copy,
one a symlink), a subagent and a workflow file, the permission archive, and both hook logs.

NOW is fixed (2026-09-20T12:00:00Z); every file's mtime is NOW-1h so a 7-day window sees it.
Tool-use ids name their case, so the suite can assert on them by name."""

import json
import os
import sys

HOME = sys.argv[1]
NOW = 1789905600.0  # 2026-09-20T12:00:00Z
SID = "11111111-1111-4111-8111-111111111111"  # main session with transcript asks
SID_H = (
    "22222222-2222-4222-8222-222222222222"  # session with log-only (interrupted) asks
)
SID_C = "33333333-3333-4333-8333-333333333333"  # 2.1.220-era session, curl ask with no attachment
VB = "~/.claude/hooks/validate-bash.sh"
CURL = "~/.claude/hooks/curl-gate-scope.sh"
PR = "~/.claude/hooks/pr-gate.sh"


def iso(t):
    import datetime as dt

    return dt.datetime.fromtimestamp(t, dt.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%S.000Z"
    )


def use(tid, cmd, t, sid=SID, agent=None, version="2.1.284"):
    o = {
        "type": "assistant",
        "timestamp": iso(t),
        "sessionId": sid,
        "version": version,
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
    }
    if agent:
        o["agentId"] = agent
    return o


def ask(tid, hook, reason, t, sid=SID, pretty=False):
    body = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": reason,
        }
    }
    return {
        "type": "attachment",
        "timestamp": iso(t),
        "sessionId": sid,
        "version": "2.1.284",
        "attachment": {
            "type": "hook_success",
            "hookName": "PreToolUse:Bash",
            "toolUseID": tid,
            "hookEvent": "PreToolUse",
            "stdout": json.dumps(body, indent=2 if pretty else None) + "\n",
            "exitCode": 0,
            "command": hook,
        },
    }


def result(tid, text, t, sid=SID, is_error=False):
    return {
        "type": "user",
        "timestamp": iso(t),
        "sessionId": sid,
        "message": {
            "role": "user",
            "content": [
                {
                    "type": "tool_result",
                    "tool_use_id": tid,
                    "content": text,
                    "is_error": is_error,
                }
            ],
        },
    }


def interrupt(t, sid=SID):
    return {
        "type": "user",
        "timestamp": iso(t),
        "sessionId": sid,
        "message": {
            "role": "user",
            "content": [
                {"type": "text", "text": "[Request interrupted by user for tool use]"}
            ],
        },
    }


REJ = (
    "The user doesn't want to proceed with this tool use. The tool use was rejected (eg. if it was a "
    "file edit, the new_string was NOT written to the file)."
)
RM = "rm -r on non-build-artifact target: '%s'. Verify intentional."
T0 = NOW - 6 * 3600


def write(path, recs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        for r in recs:
            fh.write(json.dumps(r) + "\n")
    os.utime(path, (NOW - 3600, NOW - 3600))


proj = os.path.join(HOME, ".claude", "projects", "-proj")
main = [
    # ran, with an archive row proving it was shown and how long it waited
    use("toolu_ran", "rm -rf build-x && echo ok", T0),
    ask("toolu_ran", VB, RM % "build-x", T0 + 1),
    result("toolu_ran", "ok", T0 + 43),
    # rejected, with the operator's feedback
    use("toolu_rej", "git reset --hard HEAD~1", T0 + 100),
    ask(
        "toolu_rej",
        VB,
        "git reset --hard can destroy uncommitted work. Verify intentional.",
        T0 + 101,
        pretty=True,
    ),
    result(
        "toolu_rej",
        REJ + " To tell you how to proceed, the user said:\nnot now, stash first",
        T0 + 130,
        is_error=True,
    ),
    # interrupted: the No is followed by the interrupt marker
    use("toolu_int", "rm -rf /tmp/scratch-int", T0 + 200),
    ask("toolu_int", VB, RM % "/tmp/scratch-int", T0 + 201),
    result("toolu_int", REJ, T0 + 260, is_error=True),
    interrupt(T0 + 260),
    # auto-denied: denied inside a second, no archive row
    use("toolu_auto", "rm -rf /tmp/scratch-auto", T0 + 290),
    ask("toolu_auto", VB, RM % "/tmp/scratch-auto", T0 + 301),
    result(
        "toolu_auto",
        "Permission to use Bash with command rm -rf /tmp/scratch-auto has been denied.",
        T0 + 301.4,
        is_error=True,
    ),
    # pending: curl ask with no result yet
    use("toolu_pend", "curl -X POST https://api.example.com/x", T0 + 400),
    ask("toolu_pend", CURL, "POST to api.example.com — confirm intent", T0 + 401),
    # pr-gate ran
    use("toolu_pr", "gh pr create --fill", T0 + 500),
    ask("toolu_pr", PR, "PR necessity: no reviewer", T0 + 501),
    result("toolu_pr", "https://github.com/o/r/pull/1", T0 + 520),
]
write(os.path.join(proj, SID + ".jsonl"), main)
# A second account dir holding a real COPY of the same session (the ids sit in 2-3 dirs live).
write(
    os.path.join(HOME, ".claude-secondary", "projects", "-proj", SID + ".jsonl"), main
)
# ~/.claude-next/projects is a symlink to ~/.claude/projects.
os.makedirs(os.path.join(HOME, ".claude-next"), exist_ok=True)
os.symlink(
    os.path.join(HOME, ".claude", "projects"),
    os.path.join(HOME, ".claude-next", "projects"),
)

# Subagent and workflow agents of the same session.
write(
    os.path.join(proj, SID, "subagents", "agent-asub.jsonl"),
    [
        use("toolu_sub", "rm -rf out-sub", T0 + 600, agent="asub"),
        ask("toolu_sub", VB, RM % "out-sub", T0 + 601),
        result("toolu_sub", "done", T0 + 610),
    ],
)
write(
    os.path.join(proj, SID, "subagents", "workflows", "wf_1", "agent-awf.jsonl"),
    [
        use("toolu_wf", "rm -rf out-wf", T0 + 700, agent="awf"),
        ask("toolu_wf", VB, RM % "out-wf", T0 + 701),
        result("toolu_wf", "done", T0 + 705),
    ],
)

# Log-only asks: two workflow agents asked the SAME thing 2 s apart and both were interrupted; no
# attachment survived. The log rows lag (TH+3, TH+4), so a nearest-time join would give the FIRST row
# to toolu_h2; only time-order assignment gets both right. A decoy call in the window lacks the target
# and is unresolved too, so only the target narrowing keeps it out.
TH = T0 + 1000
write(
    os.path.join(proj, SID_H + ".jsonl"),
    [
        use("toolu_decoy", "ls /tmp", TH - 1, sid=SID_H),
    ],
)
write(
    os.path.join(proj, SID_H, "subagents", "workflows", "wf_2", "agent-aone.jsonl"),
    [
        use("toolu_h1", "rm -rf /tmp/same-dir && make", TH, sid=SID_H, agent="aone"),
        result("toolu_h1", REJ, TH + 90, sid=SID_H, is_error=True),
        interrupt(TH + 90, sid=SID_H),
    ],
)
write(
    os.path.join(proj, SID_H, "subagents", "workflows", "wf_2", "agent-atwo.jsonl"),
    [
        use(
            "toolu_h2", "rm -rf /tmp/same-dir && make", TH + 2, sid=SID_H, agent="atwo"
        ),
        result("toolu_h2", REJ, TH + 91, sid=SID_H, is_error=True),
        interrupt(TH + 91, sid=SID_H),
    ],
)

# 2.1.220-era session: the curl ask left no attachment; only curl-audit (with tool_use_id) holds it.
write(
    os.path.join(proj, SID_C + ".jsonl"),
    [
        use(
            "toolu_c220",
            "curl -H 'Authorization: Bearer sk-live-SECRET' https://api.example.com",
            T0 + 1200,
            sid=SID_C,
            version="2.1.220",
        ),
        result("toolu_c220", "{}", T0 + 1230, sid=SID_C),
    ],
)

# Permission archive: the shown-and-granted proof for toolu_ran.
arch = os.path.join(HOME, ".claude", "autonomy", "permission-archive")
os.makedirs(arch, exist_ok=True)
with open(os.path.join(arch, "2026-09.jsonl"), "w") as fh:
    fh.write(
        json.dumps(
            {
                "session_id": SID,
                "ts": int(T0 + 1),
                "waited_s": 42,
                "resolved_by": "Stop",
                "cleared_tool_use_id": "toolu_ran",
            }
        )
        + "\n"
    )

logs = os.path.join(HOME, ".claude", "logs")
os.makedirs(logs, exist_ok=True)
with open(os.path.join(logs, "validate-bash-decisions.jsonl"), "w") as fh:
    for t, sid, reason in [
        (T0 + 1, SID, RM % "build-x"),  # matched by its attachment: must not duplicate
        (TH + 3, SID_H, RM % "/tmp/same-dir"),
        (TH + 4, SID_H, RM % "/tmp/same-dir"),
        (TH + 2, "00000000-0000-0000-0000-000000000000", RM % "/tmp/x"),  # synthetic
        (TH + 3, "test-sid", RM % "/tmp/x"),  # synthetic
    ]:
        fh.write(
            json.dumps({"ts": int(t), "sid": sid, "decision": "ask", "reason": reason})
            + "\n"
        )
    fh.write(
        json.dumps({"ts": int(TH), "sid": SID_H, "decision": "allow", "reason": "ok"})
        + "\n"
    )

reso = os.path.join(HOME, ".reso")
os.makedirs(reso, exist_ok=True)
with open(os.path.join(reso, "curl-audit.jsonl"), "w") as fh:
    fh.write(
        json.dumps(
            {
                "ts": iso(T0 + 1201)[:19] + "Z",
                "decision": "ask",
                "reason": "credential in header",
                "cmd_redacted": "curl -H 'Authorization: Bearer <REDACTED>' https://api.example.com",
                "session_id": SID_C,
                "tool_use_id": "toolu_c220",
            }
        )
        + "\n"
    )
    fh.write(
        json.dumps(
            {
                "ts": iso(T0 + 401)[:19] + "Z",
                "decision": "ask",
                "reason": "POST to api.example.com — confirm intent",
                "cmd_redacted": "curl -X POST https://api.example.com/x",
                "session_id": SID,
                "tool_use_id": "toolu_pend",
            }
        )
        + "\n"
    )
    # the 2026-09-10-style replay row: tool_use_id "unknown"
    fh.write(
        json.dumps(
            {
                "ts": iso(T0 + 402)[:19] + "Z",
                "decision": "ask",
                "reason": "No URL parsed",
                "session_id": SID,
                "tool_use_id": "unknown",
            }
        )
        + "\n"
    )
