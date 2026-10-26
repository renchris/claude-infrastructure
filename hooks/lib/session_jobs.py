#!/usr/bin/env python3
"""session_jobs.py — what a main session was waiting on during an idle gap, read from its transcript.

Plan: docs/plans/USAGE_LEVERS.md § W6. Research: docs/research/usage-levers-2026-10-23/
decisions-2026-10-24/REPORT.md (guards G1 and G4; the busy-scoped keepalive). Used by the two
LOG-ONLY shadows: hooks/lib/idle_gap.py (the keepalive's would-wake row) and the idle-recycle shadow
in hooks/boundary-handoff.sh. It decides nothing; it only reports.

BUSY (G1) is classified by the tool that LAUNCHED the job, never by the text of its notice:
  busy     a background Bash (not a watcher), a background Agent, a Workflow, or a foreground Bash the
           harness moved to the background (its tool_result carries toolUseResult.backgroundTaskId)
  watcher  a Monitor, or a background Bash running cc-await-ping (never its --stand-down, and a
           foreground one only once the harness moved it). Not busy: it waits on others.
A job ends at the first <task-notification> that carries a <status> and names its tool-use id or
task id, or at a TaskStop/KillShell naming its task id. A launch whose result is an error or a
denial never ran. A job with no end in the transcript is still running (an upper bound: a job
orphaned by a restart also reads as running, so each running job's age is logged with it).

A watcher's DEADLINE is when it fires on its own: a Monitor at launch + timeout_ms (capped at 30
min, default 5 min), cc-await-ping at launch + --timeout (default 1800, 3300 with --idle-scoped).

PENDING QUESTION (G4): the session's final assistant text before the gap ends with "?", or its
last 1500 characters say "your call" / "still yours", or its last assistant record asks through
AskUserQuestion.

STATE AT (wave S6b; plan § W7+ §2 lever invariants): state_at(sid, ts) finds the session's transcript
under the four account roots and says what it was doing at ts — busy, idle, headless, pending
question — and when its next turn completed. bin/cc-lever-guard judges D1/D3 by it; S12 reuses it.

CLI (boundary-handoff.sh): session_jobs.py gap <transcript> <idle_start> <check_at> [tail_bytes]
prints one JSON object; session_jobs.py state <sid> <ts> [transcript] prints state_at's.
Fail-open: any error prints {}. Python 3.9-safe, stdlib only.
"""

import json
import os
import re
import stat
import sys
from datetime import datetime

TAIL_BYTES = 4000000
ACCOUNT_DIRS = (
    ".claude",
    ".claude-secondary",
    ".claude-tertiary",
    ".claude-quaternary",
)
HEADLESS_ENTRYPOINT = "sdk-cli"
TURN_END_SUBTYPES = ("turn_duration", "stop_hook_summary")
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
                if name == "Monitor":
                    kind = "watcher"
                elif (
                    name == "Bash"
                    and "cc-await-ping" in cmd
                    and "--stand-down" not in cmd
                ):
                    # a FOREGROUND watcher ran and ended inside its turn; it waits on others in a
                    # gap only once the harness moved it to the background (S12; a foreground
                    # `cc-await-ping --stand-down` read as a 30-min watcher and skipped D3 wakes)
                    kind = "watcher" if bg else "fg-watcher"
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
        if kind in ("fg", "fg-watcher"):
            if not moved:
                continue
            kind = "moved-bash" if kind == "fg" else "watcher"
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


def running_at(js, t, ttl_end=None):
    """→ what of jobs(recs) was running at t: busy, its kinds and oldest age, and the watchers. With
    ttl_end, watcher_fires_before_ttl says whether a running watcher fires on its own before ttl_end."""
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


def find_transcript(sid, home=None):
    """→ the main transcript <root>/<project>/<sid>.jsonl under the four account roots, or None. A
    cross-account copy resolves to the most recently written one (the live session); only a regular
    file counts, so a FIFO or a directory never blocks a reader."""
    if not sid or "/" in sid or sid in (".", ".."):
        return None
    home = home or os.environ.get("HOME") or os.path.expanduser("~")
    best = None
    for d in ACCOUNT_DIRS:
        root = os.path.join(home, d, "projects")
        try:
            projects = os.listdir(root)
        except OSError:
            continue
        for p in projects:
            f = os.path.join(root, p, sid + ".jsonl")
            try:
                st = os.stat(f)
            except OSError:
                continue
            if stat.S_ISREG(st.st_mode) and (best is None or st.st_mtime > best[0]):
                best = (st.st_mtime, f)
    return best[1] if best else None


def _is_prompt(r):
    """A main-thread user record that starts a turn: text, not only tool results."""
    if r.get("type") != "user" or r.get("isMeta"):
        return False
    c = _content(r)
    if isinstance(c, str):
        return bool(c.strip())
    return isinstance(c, list) and any(
        isinstance(b, dict) and b.get("type") == "text" for b in c
    )


def state_at(sid, ts, transcript=None, tail_bytes=TAIL_BYTES, home=None):
    """→ what session `sid` was doing at epoch `ts`, read from the tail of its transcript:
      found                 a transcript was read (every other field is None when it was not)
      headless              a `-p` session (entrypoint sdk-cli)
      busy, busy_kinds, watcher_running   the background jobs running at ts (running_at above)
      idle                  no turn in flight at ts: the last turn start at or before ts has a turn
                            end at or before ts
      pending_question, pq_why            G4 for the final assistant message at or before ts
      turn_completed_after  epoch of the first turn end strictly after ts, or None
    A turn ends at a system turn_duration or stop_hook_summary record (the harness writes one at
    every Stop). The guard's lever invariants (bin/cc-lever-guard) read this; so does wave S12.
    Never raises: an unreadable or absent transcript is found=False."""
    out = dict(
        sid=sid,
        found=False,
        transcript=None,
        headless=None,
        busy=None,
        busy_kinds=None,
        watcher_running=None,
        idle=None,
        pending_question=None,
        pq_why=None,
        turn_completed_after=None,
    )
    try:
        path = transcript or find_transcript(sid, home)
        if not path or not stat.S_ISREG(os.stat(path).st_mode):
            return out
        recs = records(path, tail_bytes)
    except (OSError, ValueError):
        return out
    if not recs:
        return out
    out.update(found=True, transcript=path)
    eps = [r.get("entrypoint") for r in recs if isinstance(r.get("entrypoint"), str)]
    out["headless"] = (HEADLESS_ENTRYPOINT in eps) if eps else None
    run = running_at(jobs(recs), ts)
    out.update(
        busy=run["busy"],
        busy_kinds=run["busy_kinds"],
        watcher_running=run["watcher_running"],
    )
    last_start = last_end = after = None
    for r in recs:
        t = _ts(r)
        if t is None:
            continue
        end = r.get("type") == "system" and r.get("subtype") in TURN_END_SUBTYPES
        if t <= ts:
            if end:
                last_end = t
            elif _is_prompt(r):
                last_start = t
        elif end and after is None:
            after = t
    out["idle"] = (
        None
        if last_start is None and last_end is None
        else last_end is not None and (last_start is None or last_end >= last_start)
    )
    out["turn_completed_after"] = after
    out["pending_question"], out["pq_why"] = pending_question(recs, ts)
    return out


def gap(path, idle_start, check_at, tail_bytes=TAIL_BYTES):
    recs = records(path, tail_bytes)
    st = running_at(jobs(recs), check_at)
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
        elif argv[:1] == ["state"] and len(argv) in (3, 4):
            row = state_at(argv[1], float(argv[2]), argv[3] if len(argv) == 4 else None)
        else:
            row = {}
    except Exception:  # fail-open: a log-only caller must never fail on this
        row = {}
    sys.stdout.write(json.dumps(row, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
