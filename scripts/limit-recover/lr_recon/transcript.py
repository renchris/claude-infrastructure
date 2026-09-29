"""Transcript reads for observe, facts and phase (§C3.6-7).

One place that turns a session id into its jsonl and a bounded read of it: the tail verdict and
the head teammate test are delegated to ``lr_predicate`` (§11 #10: one predicate copy), and this
module adds only what the reconciler needs on top — the last healthy turn, whether the session is
at rest, and how many subagents are still writing.
"""

from __future__ import annotations

import datetime
import glob
import importlib
import json
import os
import sys
import time
from typing import Any, Dict, Iterator, List, Optional, Sequence

from lr_recon import types as T

TAIL_BYTES = 128 * 1024
HEAD_BYTES = 8 * 1024
SUBAGENT_FRESH_S = 120.0
_NO_RESPONSE = "No response requested."
_STOP_AT_REST = ("end_turn", "stop_sequence", "max_tokens", "refusal")


def _load_predicate() -> Any:
    """``lr_predicate`` lives in the package's parent dir; add it to sys.path only if needed."""
    try:
        return importlib.import_module("lr_predicate")
    except ImportError:
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        return importlib.import_module("lr_predicate")


_P: Any = _load_predicate()


def slug(cwd: str) -> str:
    """Claude Code's projects-dir name for a cwd: '/' and '.' both become '-'."""
    return cwd.replace("/", "-").replace(".", "-")


def find_transcript(cfg_dirs: Sequence[str], cwd: str, sid: str) -> Optional[str]:
    """Slug-direct first (cheap, exact), then a glob across every project dir: a session whose
    cwd moved (worktree hop, recycle) still has exactly one ``<sid>.jsonl``."""
    if not sid:
        return None
    if cwd:
        for cfg in cfg_dirs:
            p = os.path.join(cfg, "projects", slug(cwd), sid + ".jsonl")
            if os.path.isfile(p):
                return p
    for cfg in cfg_dirs:
        hits = sorted(
            glob.glob(os.path.join(glob.escape(cfg), "projects", "*", sid + ".jsonl"))
        )
        if hits:
            return hits[0]
    return None


def handed_off_path(path: str) -> str:
    return path + ".handed-off"


def _read(path: str, head: bool, n: int) -> bytes:
    with open(path, "rb") as f:
        if not head:
            size = os.fstat(f.fileno()).st_size
            f.seek(max(0, size - n))
        return f.read(n)


def _records(data: bytes) -> Iterator[Dict[str, Any]]:
    """Parseable dict records of a tail; the first line is routinely partial and is skipped."""
    for line in data.decode("utf-8", "replace").splitlines():
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if isinstance(rec, dict):
            yield rec


def _ts(rec: Dict[str, Any]) -> Optional[float]:
    v = rec.get("timestamp")
    if not isinstance(v, str) or not v:
        return None
    try:
        dt = datetime.datetime.fromisoformat(v.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return dt.timestamp()


def _msg(rec: Dict[str, Any]) -> Dict[str, Any]:
    m = rec.get("message")
    return m if isinstance(m, dict) else {}


def _text(rec: Dict[str, Any]) -> str:
    content = _msg(rec).get("content")
    if isinstance(content, str):
        return content
    parts = [
        b["text"]
        for b in content or []
        if isinstance(b, dict) and isinstance(b.get("text"), str)
    ]
    return " ".join(parts)


def _is_error(rec: Dict[str, Any]) -> bool:
    return bool(rec.get("isApiErrorMessage") or rec.get("error"))


def _is_ok_turn(rec: Dict[str, Any]) -> bool:
    """A real, healthy assistant turn: not an error/limit record and not the synthetic no-op."""
    return (
        rec.get("type") == "assistant"
        and not _is_error(rec)
        and _text(rec).strip() != _NO_RESPONSE
    )


def _ok_turn_ts(data: bytes) -> List[float]:
    out = []
    for rec in _records(data):
        if _is_ok_turn(rec):
            ts = _ts(rec)
            if ts is not None:
                out.append(ts)
    return out


def _at_rest(data: bytes) -> bool:
    """The last user/assistant record decides: an assistant record not waiting on a tool (or an
    error/limit record, or the synthetic no-op) is at rest; a trailing user record is not."""
    last: Optional[Dict[str, Any]] = None
    for rec in _records(data):
        if rec.get("type") in ("user", "assistant") and not rec.get("isSidechain"):
            last = rec
    if last is None or last.get("type") != "assistant":
        return False
    if _is_error(last) or _text(last).strip() == _NO_RESPONSE:
        return True
    msg = _msg(last)
    content = msg.get("content")
    if isinstance(content, list) and any(
        isinstance(b, dict) and b.get("type") == "tool_use" for b in content
    ):
        return False
    return msg.get("stop_reason") in _STOP_AT_REST


def live_subagents(path: str, now: float) -> int:
    """Subagent transcripts (workflow slots included) written in the last 120 s. Mirrors the intent
    of handoff-fire.sh live_subagents_of: a session with a subagent still writing is not idle."""
    base = path[: -len(".jsonl")] if path.endswith(".jsonl") else path
    pattern = os.path.join(glob.escape(base), "subagents", "**", "agent-*.jsonl")
    n = 0
    for p in glob.glob(pattern, recursive=True):
        try:
            if now - os.stat(p).st_mtime <= SUBAGENT_FRESH_S:
                n += 1
        except OSError:
            continue
    return n


def observe_transcript(path: str, now: Optional[float] = None) -> T.TranscriptObs:
    """One bounded read of a transcript: last 128 KiB for the verdict, first 8 KiB for the head."""
    now = time.time() if now is None else now
    try:
        st = os.stat(path)
        tail = _read(path, head=False, n=TAIL_BYTES)
        head = _read(path, head=True, n=HEAD_BYTES)
    except OSError:
        return T.TranscriptObs(path=path)
    oks = _ok_turn_ts(tail)
    return T.TranscriptObs(
        path=path,
        size=st.st_size,
        mtime=st.st_mtime,
        last=dict(_P.classify_tail(tail)),
        last_assistant_ok_at=oks[-1] if oks else None,
        at_rest=_at_rest(tail),
        teammate=bool(_P.is_teammate_head(head)),
        live_subagents=live_subagents(path, now),
    )


def observe(cfg: str, cwd: str, sid: str) -> T.TranscriptObs:
    """The injected seam observe.py and main use; empty when no transcript is found."""
    path = find_transcript([cfg], cwd, sid)
    return observe_transcript(path) if path else T.TranscriptObs()


def ok_turns_since(path: str, since_ts: float) -> List[float]:
    """Healthy assistant-turn timestamps after ``since_ts``, from the tail (fact contradiction)."""
    try:
        tail = _read(path, head=False, n=TAIL_BYTES)
    except OSError:
        return []
    return [ts for ts in _ok_turn_ts(tail) if ts > since_ts]
