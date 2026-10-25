#!/usr/bin/env python3
"""predicate.py — run the REAL D4 shadow hook over cases and read back its verdicts (plan § W7+ §2
D4 "Offline"; the replay_pred.py method of conv-test 3df527edd333).

Each case becomes the PreToolUse payload validate-bash.sh would pipe to
hooks/subagent-long-bash-shadow.sh (agent_id, ids, tool_input.command / timeout /
run_in_background — decision-time fields ONLY), run under /bin/bash (the interpreter the hook is
deployed under: bash 3.2 on macOS) with CC_SUBAGENT_LONG_BASH=shadow and its log redirected by
CC_SUBAGENT_LONG_BASH_LOG into a scratch dir. The row it logs, joined back by tool_use_id, IS the
verdict; no row means the hook did not judge the call (timeout <= 270 s, backgrounded, no timeout).

FAIL CLOSED. A hook that cannot run (no jq, a syntax error, a path typo) logs nothing, which would
read as "nothing to deny" — the exact verdict a population gate must never reach by accident. So
every replay first sends a planted poll loop that the hook must log as would_deny_class=poll-loop;
if it does not, replay() raises PlumbingError and no verdict is computed.

Verdicts are cached per (hook sha256, case_id) for the life of the process: a round scores both
read ends for candidate and baseline, and the hook is deterministic in its payload.
"""

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import threading

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
HOOK = os.path.join(REPO, "hooks", "subagent-long-bash-shadow.sh")
BASH = "/bin/bash"
WORKERS = int(os.environ.get("CC_LEVER_D4_WORKERS", "8"))
CONTROL_ID = "d4-positive-control"
CONTROL_CMD = "while ! test -f /nonexistent/done; do sleep 10; done; echo done"
_cache = {}
_lock = threading.Lock()


class PlumbingError(RuntimeError):
    pass


def payload(g):
    """The hook's input for case g: decision-time fields only, never an outcome."""
    ti = {"command": g["cmd"]}
    if g.get("timeout_ms") is not None:
        ti["timeout"] = g["timeout_ms"]
    if g.get("bg"):
        ti["run_in_background"] = True
    return {
        "agent_id": g.get("agent_id") or "replay",
        "agent_type": "lever-eval",
        "session_id": g.get("sid") or "lever-eval",
        "tool_use_id": g["case_id"],
        "transcript_path": "-",
        "tool_input": ti,
    }


def hook_sha(hook):
    with open(hook, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def _run_chunk(hook, chunk, log, env):
    env = dict(env, CC_SUBAGENT_LONG_BASH_LOG=log)
    for g in chunk:
        subprocess.run(
            [BASH, hook],
            input=json.dumps(payload(g)),
            text=True,
            env=env,
            capture_output=True,
            timeout=30,
        )


def replay(cases, hook=None):
    """→ {case_id: the hook's logged row, or None when it did not judge the call}. hook=None reads
    HOOK at CALL time (a default bound at import would ignore a later reassignment of HOOK)."""
    hook = hook or HOOK
    if not os.path.isfile(hook):
        raise PlumbingError("hook not found: %s" % hook)
    sha = hook_sha(hook)
    todo = [g for g in cases if (sha, g["case_id"]) not in _cache]
    if todo:
        control = dict(
            case_id=CONTROL_ID,
            cmd=CONTROL_CMD,
            timeout_ms=600000,
            bg=False,
            agent_id="control",
            sid="control",
        )
        tmp = tempfile.mkdtemp(prefix="lev-d4-")
        try:
            env = dict(os.environ, CC_SUBAGENT_LONG_BASH="shadow")
            n = max(1, min(WORKERS, len(todo)))
            chunks = [todo[i::n] for i in range(n)]
            chunks[0] = [control] + chunks[0]
            th = [
                threading.Thread(
                    target=_run_chunk,
                    args=(hook, c, os.path.join(tmp, "log%d.jsonl" % i), env),
                )
                for i, c in enumerate(chunks)
            ]
            for t in th:
                t.start()
            for t in th:
                t.join()
            rows = {}
            for fn in sorted(os.listdir(tmp)):
                if not fn.endswith(".jsonl"):
                    continue  # the hook's <log>.pending marker dirs (follow pipe, plan § W7+ S3)
                with open(os.path.join(tmp, fn)) as fh:
                    for ln in fh:
                        try:
                            r = json.loads(ln)
                        except ValueError:
                            raise PlumbingError(
                                "hook wrote a non-JSON log line: %r" % ln[:120]
                            )
                        # a d4_follow row shares its call's tool_use_id: only the verdict row counts
                        if r.get("kind", "subagent_bash") == "subagent_bash":
                            rows[r.get("tool_use_id")] = r
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        c = rows.pop(CONTROL_ID, None)
        if not c or c.get("would_deny_class") != "poll-loop":
            raise PlumbingError(
                "positive control not logged as a poll-loop would-deny (row: %r): the hook "
                "did not run, or no longer recognises a canonical while-sleep loop, so its "
                "verdicts are no verdict" % (c,)
            )
        with _lock:
            for g in todo:
                _cache[(sha, g["case_id"])] = rows.get(g["case_id"])
    return {g["case_id"]: _cache[(sha, g["case_id"])] for g in cases}


def would_deny(row):
    """The D4 target: a judged, non-exempt call the hook puts in the poll-loop class."""
    return bool(row) and row.get("would_deny_class") == "poll-loop"


def exempt(row):
    return bool(row) and bool(row.get("exempt"))
