#!/usr/bin/env python3
"""session_jobs.py — what a main session was waiting on during an idle gap, read from its transcript.

Plan: docs/plans/USAGE_LEVERS.md § W6. Research: docs/research/usage-levers-2026-10-23/
decisions-2026-10-24/REPORT.md (guards G1 and G4; the busy-scoped keepalive). Used by the two
LOG-ONLY shadows: hooks/lib/idle_gap.py (the keepalive's would-wake row) and the idle-recycle shadow
in hooks/boundary-handoff.sh. It decides nothing; it only reports.

BUSY (G1) is classified by the tool that LAUNCHED the job, never by the text of its notice:
  busy     a background Bash (not a watcher), a background Agent, a Workflow, or a foreground Bash the
           harness moved to the background (its tool_result carries toolUseResult.backgroundTaskId)
  watcher  a Monitor, or a background Bash running cc-await-ping. Not busy: it waits on others.
A job ends at the first <task-notification> that carries a <status> and names its tool-use id or
task id, or at a TaskStop/KillShell naming its task id. A launch whose result is an error or a
denial never ran. A job with no end in the transcript is still running (an upper bound: a job
orphaned by a restart also reads as running, so each running job's age is logged with it).

A watcher's DEADLINE is when it fires on its own: a Monitor at launch + timeout_ms (capped at 30
min, default 5 min), cc-await-ping at launch + --timeout (default 1800, 3300 with --idle-scoped).

PENDING QUESTION (G4): the session's final assistant text before the gap ends with "?", or its
last 1500 characters say "your call" / "still yours", or its last assistant record asks through
AskUserQuestion.

CLI (boundary-handoff.sh): session_jobs.py gap <transcript> <idle_start> <check_at> [tail_bytes]
prints one JSON object. Fail-open: any error prints {}. Python 3.9-safe, stdlib only.
"""

import json
import os
import re
import sys
from datetime import datetime

TAIL_BYTES = 4000000
MONITOR_DEFAULT_MS, MONITOR_CAP_MS = 300000, 1800000
TUID = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>")
TID = re.compile(r"<task-id>([^<]+)</task-id>")
RESULT_ID = re.compile(
    r"(?:with ID|Task ID|task_id|agentId|agent ID)[:=]?\s*`?\"?([A-Za-z0-9_-]{5,40})"
)
AWAIT_TIMEOUT = re.compile(r"--timeout[= ]+([0-9]+)")
ENDS_Q = re.compile(r"\?[\s*_`)\]]*$")
PHRASE = re.compile(r"\b(your call|still yours)\b", re.I)


def _ts(rec):
    s = rec.get("timestamp")
    if not isinstance(s, str):
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def records(path, tail_bytes=TAIL_BYTES):
    """Main-thread records from the transcript's tail, in file order."""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            if size > tail_bytes:
                fh.seek(size - tail_bytes)
            raw = fh.read()
    except OSError:
        return []
    lines = raw.split(b"\n")
    if size > tail_bytes:
        lines = lines[1:]  # partial first line
    out = []
    for ln in lines:
        try:
            r = json.loads(ln)
        except ValueError:
            continue
        if isinstance(r, dict) and not r.get("isSidechain"):
            out.append(r)
    return out


def _content(r):
    m = r.get("message")
    c = m.get("content") if isinstance(m, dict) else None
    return c


def _watch_deadline(name, inp, t):
    if name == "Monitor":
        ms = inp.get("timeout_ms")
        ms = ms if isinstance(ms, (int, float)) and ms > 0 else MONITOR_DEFAULT_MS
        return t + min(ms, MONITOR_CAP_MS) / 1000.0
    cmd = str(inp.get("command", ""))
    m = AWAIT_TIMEOUT.search(cmd)
    if m:
        return t + int(m.group(1))
    return t + (3300 if "--idle-scoped" in cmd else 1800)


def jobs(recs):
    """→ list of dict(kind, launch, end, deadline) for every background job launched in recs."""
    launch, result, ended_tu, ended_tid, stops = {}, {}, {}, {}, {}
    for r in recs:
        t = _ts(r)
        typ = r.get("type")
        c = _content(r)
        if typ in ("user", "queue-operation") and t is not None:
            s = c if isinstance(c, str) else json.dumps(c) if c is not None else ""
            if typ == "queue-operation" and not s:
                s = str(r.get("content") or "")
            if "<task-notification>" in s and "<status>" in s:
                for x in TUID.findall(s):
                    ended_tu.setdefault(x, t)
                for x in TID.findall(s):
                    ended_tid.setdefault(x, t)
        if not isinstance(c, list):
            continue
        for b in c:
            if not isinstance(b, dict):
                continue
            if typ == "assistant" and b.get("type") == "tool_use" and t is not None:
                name = b.get("name")
                inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                if name in ("TaskStop", "KillShell", "KillBash"):
                    k = inp.get("task_id") or inp.get("shell_id") or inp.get("id")
                    if k:
                        stops.setdefault(str(k), t)
                    continue
                bg = bool(inp.get("run_in_background"))
                cmd = str(inp.get("command", ""))
                if name == "Monitor" or (name == "Bash" and "cc-await-ping" in cmd):
                    kind = "watcher"
                elif name == "Bash":
                    kind = (
                        "bash" if bg else "fg"
                    )  # fg: busy only if the harness moved it
                elif name in ("Agent", "Task") and bg:
                    kind = "agent"
                elif name == "Workflow":
                    kind = "workflow"
                else:
                    continue
                if b.get("id"):
                    launch.setdefault(b["id"], (t, kind, name, inp))
            elif (
                typ == "user"
                and b.get("type") == "tool_result"
                and b.get("tool_use_id")
            ):
                cc = b.get("content")
                cs = cc if isinstance(cc, str) else json.dumps(cc)
                tr = (
                    r.get("toolUseResult")
                    if isinstance(r.get("toolUseResult"), dict)
                    else {}
                )
                m = RESULT_ID.search(cs)
                tid = tr.get("backgroundTaskId") or (m.group(1) if m else None)
                bad = (
                    bool(b.get("is_error"))
                    or "Permission for this action was denied" in cs[:300]
                    or "<tool_use_error>" in cs[:200]
                )
                result[b["tool_use_id"]] = (tid, bad, bool(tr.get("backgroundTaskId")))
    out = []
    for tu, (t, kind, name, inp) in launch.items():
        tid, bad, moved = result.get(tu, (None, False, False))
        if bad:
            continue
        if kind == "fg":
            if not moved:
                continue
            kind = "moved-bash"
        ends = [
            e
            for e in (ended_tu.get(tu), ended_tid.get(tid), stops.get(tid))
            if e is not None
        ]
        out.append(
            dict(
                kind=kind,
                launch=t,
                end=min(ends) if ends else None,
                deadline=_watch_deadline(name, inp, t) if kind == "watcher" else None,
            )
        )
    return out


def state_at(js, t, ttl_end=None):
    """→ what was running at t: busy, its kinds and oldest age, and the watchers. With ttl_end,
    watcher_fires_before_ttl says whether a running watcher fires on its own before ttl_end."""
    run = [j for j in js if j["launch"] <= t and (j["end"] is None or j["end"] > t)]
    busy = [j for j in run if j["kind"] != "watcher"]
    watch = [j for j in run if j["kind"] == "watcher"]
    row = dict(
        busy=bool(busy),
        busy_kinds=sorted({j["kind"] for j in busy}),
        busy_oldest_s=round(t - min(j["launch"] for j in busy)) if busy else None,
        watcher_running=bool(watch),
    )
    if ttl_end is not None:
        dl = [j["deadline"] for j in watch if j["deadline"] is not None]
        row["watcher_deadline_s"] = round(min(dl) - t) if dl else None
        row["watcher_fires_before_ttl"] = bool(dl) and min(dl) <= ttl_end
    return row


def pending_question(recs, before):
    """→ (bool, why) for the final assistant message at or before `before` (epoch seconds)."""
    text, ask = "", False
    for r in recs:
        t = _ts(r)
        if r.get("type") != "assistant" or t is None or t >= before + 1:
            continue
        c = _content(r)
        if not isinstance(c, list):
            continue
        tx = " ".join(
            b.get("text", "")
            for b in c
            if isinstance(b, dict) and b.get("type") == "text"
        ).strip()
        uses = [b for b in c if isinstance(b, dict) and b.get("type") == "tool_use"]
        if tx:
            text, ask = tx, False
        if uses:
            ask = any(b.get("name") == "AskUserQuestion" for b in uses)
    if ask:
        return True, "ask-user-question"
    if ENDS_Q.search(text):
        return True, "question-mark"
    m = PHRASE.search(text[-1500:])
    if m:
        return True, m.group(1).lower().replace(" ", "-")
    return False, None


def gap(path, idle_start, check_at, tail_bytes=TAIL_BYTES):
    recs = records(path, tail_bytes)
    st = state_at(jobs(recs), check_at)
    pq, why = pending_question(recs, idle_start)
    return dict(
        busy_tool=st["busy"],
        busy_kinds=st["busy_kinds"],
        busy_oldest_s=st["busy_oldest_s"],
        watcher_running=st["watcher_running"],
        pending_question=pq,
        pq_why=why,
    )


def main(argv):
    try:
        if argv[:1] == ["gap"] and len(argv) in (4, 5):
            tb = int(argv[4]) if len(argv) == 5 else TAIL_BYTES
            row = gap(argv[1], float(argv[2]), float(argv[3]), tb)
        else:
            row = {}
    except Exception:  # fail-open: a log-only caller must never fail on this
        row = {}
    sys.stdout.write(json.dumps(row, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
