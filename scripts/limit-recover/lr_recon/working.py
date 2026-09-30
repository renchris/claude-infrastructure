"""working.py: is a transcript a WORKING session right now (D1.8, the reconciler half).

The reconciler's k_work census and bin/claude-accounts' k_work census must count the same thing,
or --place scores one population while the reconciler feeds it another. This is the Python copy of
claude-accounts' ``_file_working`` / ``_session_settled`` (W6c); tests/test_working.py pins the
two equal by loading claude-accounts itself.

The rule, judged on the newest timestamped user/assistant record (not the file's mtime):
  1. a user record, or an assistant record, inside the 10-min window ⇒ working;
  2. an assistant tool_use is the model WAITING on a tool ⇒ working for up to 30 min
     (CC_ROUTE_KWORK_TOOLWAIT_MIN);
  3. a subagent counts only while UNFINISHED: its final answer is written, or its workflow journal
     holds a result/failed row for its agentId, or its parent recorded a task-notification for it
     at/after its last record ⇒ finished.
A file with no parseable turn record is judged by the old mtime rule. Records after ``now`` are
ignored, so a census can be replayed at a past instant. Kill switch: CC_ROUTE_KWORK_TURNS=off.
"""

import json
import os
import re
from datetime import datetime, timezone
from typing import Callable, Dict, List, Optional, Tuple

KWORK_TOOLWAIT_MIN = 30.0
KWORK_TAIL_BYTES = (64 * 1024, 1024 * 1024)  # tail read, then one wider retry
_RE_TS = re.compile(rb'"timestamp":"([0-9][0-9:.TZ+-]*)"')
_RE_NOTIF = re.compile(
    rb'"(?:content|prompt)":"<task-notification>\\n<task-id>([A-Za-z0-9_-]+)</task-id>'
)

TurnState = Tuple[Optional[float], bool, bool]  # (ts, waiting_on_tool, answered)


def _env_min(name: str, default: float) -> float:
    """A malformed or negative value is ignored, never fatal and never zero (claude-accounts'
    _cliff_env)."""
    raw = os.environ.get(name)
    if raw:
        try:
            v = float(raw)
            if v >= 0:
                return v
        except ValueError:
            pass
    return default


def turns_enabled() -> bool:
    return os.environ.get("CC_ROUTE_KWORK_TURNS", "on") != "off"


def _iso_epoch(s: object) -> Optional[float]:
    if isinstance(s, bytes):
        s = s.decode("ascii", "replace")
    try:
        t = datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)
    return t.timestamp()


def _tail_lines(path: str, size: int, nbytes: int) -> Tuple[List[bytes], bool]:
    """Complete lines of the last ``nbytes``, newest first, and whether the read reached the start."""
    with open(path, "rb") as f:
        off = max(0, size - nbytes)
        f.seek(off)
        data = f.read(nbytes)
    lines = data.split(b"\n")
    if off > 0:
        lines = lines[1:]  # the first piece is a partial line
    return lines[::-1], off == 0


def _turn_state(lines: List[bytes], now: Optional[float] = None) -> Optional[TurnState]:
    for ln in lines:
        if b'"type":"assistant"' not in ln and b'"type":"user"' not in ln:
            continue
        try:
            rec = json.loads(ln)
        except ValueError:
            continue  # a line still being written
        if not isinstance(rec, dict) or rec.get("type") not in ("user", "assistant"):
            continue
        ts = _iso_epoch(rec.get("timestamp"))
        if now is not None and ts is not None and ts > now:
            continue
        if rec["type"] == "user":
            return ts, False, False
        content = (rec.get("message") or {}).get("content")
        tool = isinstance(content, list) and any(
            isinstance(b, dict) and b.get("type") == "tool_use" for b in content
        )
        return ts, tool, not tool
    return None


def last_turn(path: str, size: int, now: Optional[float] = None) -> Optional[TurnState]:
    for nbytes in KWORK_TAIL_BYTES:
        lines, whole = _tail_lines(path, size, nbytes)
        st = _turn_state(lines, now)
        if st is not None or whole:
            return st
    return None


def session_settled(sdir: str, now: Optional[float] = None) -> Dict[str, float]:
    """Agent ids under session dir ``sdir`` the harness recorded as ended: {id: ts_or_0}."""
    out: Dict[str, float] = {}
    wroot = os.path.join(sdir, "subagents", "workflows")
    try:
        runs = list(os.scandir(wroot))
    except OSError:
        runs = []
    for run in runs:
        try:
            with open(os.path.join(run.path, "journal.jsonl"), "rb") as f:
                for ln in f:
                    if b'"type":"result"' not in ln and b'"type":"failed"' not in ln:
                        continue
                    m = re.search(rb'"agentId":"([A-Za-z0-9_-]+)"', ln)
                    if not m:
                        continue
                    t = _RE_TS.search(ln)
                    ts = _iso_epoch(t.group(1)) if t else None
                    if now is not None and ts is not None and ts > now:
                        continue
                    out[m.group(1).decode()] = 0.0
        except OSError:
            continue
    parent = sdir + ".jsonl"
    try:
        size = os.path.getsize(parent)
        lines, _whole = _tail_lines(parent, size, KWORK_TAIL_BYTES[-1])
    except OSError:
        lines = []
    for ln in lines:
        if (
            b'"origin":{"kind":"task-notification"}' not in ln
            and b'"type":"queue-operation"' not in ln
            and b'"type":"queued_command"' not in ln
        ):
            continue
        m = _RE_NOTIF.search(ln)
        if not m:
            continue
        t = _RE_TS.search(ln)
        ts = _iso_epoch(t.group(1)) if t else None
        if ts is None or (now is not None and ts > now):
            continue
        aid = m.group(1).decode()
        if out.get(aid) != 0.0:
            out[aid] = max(out.get(aid) or 0.0, ts)
    return out


def file_working(
    path: str,
    mtime: float,
    size: int,
    now: float,
    window_s: float,
    sub: bool = False,
    settled: Optional[Callable[[], Dict[str, float]]] = None,
    turns: bool = True,
) -> bool:
    """THE predicate. ``settled`` is a thunk returning session_settled for this file's session,
    called only when a subagent is otherwise live."""
    age = now - mtime
    if not turns:
        return age <= window_s
    horizon_s = max(
        window_s, 60.0 * _env_min("CC_ROUTE_KWORK_TOOLWAIT_MIN", KWORK_TOOLWAIT_MIN)
    )
    if age > horizon_s:
        return False
    st = last_turn(path, size, now)
    if st is None:
        return age <= window_s  # no record to judge by: the old rule
    ts, waiting, answered = st
    if sub and answered:
        return False
    if ts is None:
        live = waiting or age <= window_s
    else:
        live = now - ts <= (horizon_s if waiting else window_s)
    if not live or not sub or settled is None:
        return live
    aid = os.path.basename(path)[len("agent-") : -len(".jsonl")]
    stop = settled().get(aid)
    if stop is None:
        return True
    return not (stop == 0.0 or ts is None or ts <= stop)


def path_working(
    path: str,
    now: float,
    window_s: float,
    sub: bool = False,
    settled: Optional[Callable[[], Dict[str, float]]] = None,
) -> bool:
    """file_working over a path; an unreadable file is not working."""
    try:
        st = os.stat(path)
    except OSError:
        return False
    try:
        return file_working(
            path,
            st.st_mtime,
            st.st_size,
            now,
            window_s,
            sub=sub,
            settled=settled,
            turns=turns_enabled(),
        )
    except OSError:
        return now - st.st_mtime <= window_s
