"""Transcript reads for observe, facts and phase (§C3.6-7).

One place that turns a session id into its jsonl and a bounded read of it: the tail verdict and
the head teammate test are delegated to ``lr_predicate`` (§11 #10: one predicate copy), and this
module adds only what the reconciler needs on top — the last healthy turn, whether the session is
at rest, and how many subagents are still writing.
"""

from __future__ import annotations

import contextlib
import datetime
import glob
import importlib
import json
import os
import sys
import threading
import time
from typing import Any, Callable, Dict, Iterator, List, Optional, Sequence, Tuple

from lr_recon import clock
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


INDEXED_SUFFIXES = (".jsonl", ".jsonl.handed-off", ".HANDOFF.json")
SWEEP_STEP_DIRS = 256  # project dirs listed between two clock.step() calls


class ProjectsIndex:
    """Every ``<cfg>/projects/*/<name>`` the reconciler asks about, from ONE sweep per store.

    A ``projects/*/<sid>.jsonl`` glob lists projects/ and then lstats one candidate in EVERY
    project dir. With ~18,300 dirs per store (one per worktree path ever opened) one such glob took
    3.32 s at load 600 and a pass made ~1,500 of them, so the live reconciler spent ~80 min a pass
    in lstat (2026-10-19, pid 78642, heartbeat max_step_gap_s 1926). This lists each store once:
    projects/, then each project dir, keeping only names with an indexed suffix, which is O(dirs)
    directory reads per pass in place of O(lookups x dirs) lstats.

    It gives the glob's answer: ``*`` matches the same entries (no dot-names; directories, symlinks
    followed), a name matches iff it is listed (glob's ``lexists``, so a dangling symlink counts),
    paths are spelled with the caller's own cfg (callers split them on ``/projects/``), and hits
    come back sorted. Two cfgs over one physical projects/ (``.claude`` and ``.claude-next``) share
    one sweep. A project dir that cannot be listed is lexists-probed per lookup, as glob would.
    The listing is a snapshot taken at a store's first lookup in the pass; every hit is re-checked
    with lexists before it is returned, so a file a mover took away since is never served, and one
    created since is seen next pass."""

    def __init__(
        self,
        scandir_fn: Callable[[str], Any] = os.scandir,
        lexists_fn: Callable[[str], bool] = os.path.lexists,
        step_fn: Optional[Callable[[], None]] = None,
    ) -> None:
        self._scandir = scandir_fn
        self._lexists = lexists_fn
        self._step = step_fn if step_fn is not None else clock.step
        self._stores: Dict[str, Tuple[Dict[str, List[str]], List[str]]] = {}

    def _sweep(self, proj: str) -> Tuple[Dict[str, List[str]], List[str]]:
        names: Dict[str, List[str]] = {}
        unlisted: List[str] = []
        dirs: List[str] = []
        try:
            with self._scandir(proj) as it:
                for e in it:
                    if e.name.startswith("."):
                        continue
                    try:
                        if e.is_dir():
                            dirs.append(e.name)
                    except OSError:
                        continue
        except OSError:
            return names, unlisted
        for i, d in enumerate(dirs):
            if i and i % SWEEP_STEP_DIRS == 0:
                self._step()
            try:
                with self._scandir(os.path.join(proj, d)) as it:
                    for e in it:
                        if e.name.endswith(INDEXED_SUFFIXES):
                            names.setdefault(e.name, []).append(d)
            except OSError:
                unlisted.append(d)
        self._step()
        return names, unlisted

    def find(self, cfg: str, name: str) -> List[str]:
        """Sorted ``<cfg>/projects/*/<name>`` paths that exist (lexists), spelled with ``cfg``."""
        base = os.path.join(cfg, "projects")
        if not name.endswith(INDEXED_SUFFIXES) or os.sep in name:
            return sorted(
                glob.glob(os.path.join(glob.escape(cfg), "projects", "*", name))
            )
        key = os.path.realpath(base)
        got = self._stores.get(key)
        if got is None:
            got = self._stores[key] = self._sweep(key)
        names, unlisted = got
        cands = [os.path.join(base, d, name) for d in names.get(name, [])]
        cands += [os.path.join(base, d, name) for d in unlisted]
        return sorted(p for p in cands if self._lexists(p))


_ACTIVE: Optional[Tuple[ProjectsIndex, int]] = (
    None  # (index, ident of the thread it serves)
)


@contextlib.contextmanager
def pass_index(index: Optional[ProjectsIndex] = None) -> Iterator[ProjectsIndex]:
    """Serve ``in_projects`` on this thread from one index for the block's duration (one pass)."""
    global _ACTIVE
    prev = _ACTIVE
    idx = index if index is not None else ProjectsIndex()
    _ACTIVE = (idx, threading.get_ident())
    try:
        yield idx
    finally:
        _ACTIVE = prev


def in_projects(cfg: str, name: str, escape: bool = True) -> List[str]:
    """Sorted ``<cfg>/projects/*/<name>``: from the pass's index when one is open on this thread,
    else the glob (``escape=False`` keeps a caller that never escaped its cfg exactly as it was)."""
    active = _ACTIVE
    if active is not None and active[1] == threading.get_ident():
        return active[0].find(cfg, name)
    base = glob.escape(cfg) if escape else cfg
    return sorted(glob.glob(os.path.join(base, "projects", "*", name)))


def find_transcript(cfg_dirs: Sequence[str], cwd: str, sid: str) -> Optional[str]:
    """Slug-direct first (cheap, exact), then every project dir (``in_projects``): a session whose
    cwd moved (worktree hop, recycle) still has exactly one ``<sid>.jsonl``."""
    if not sid:
        return None
    if cwd:
        for cfg in cfg_dirs:
            p = os.path.join(cfg, "projects", slug(cwd), sid + ".jsonl")
            if os.path.isfile(p):
                return p
    for cfg in cfg_dirs:
        hits = in_projects(cfg, sid + ".jsonl")
        if hits:
            return hits[0]
    return None


def handed_off_path(path: str) -> str:
    return path + ".handed-off"


def locate(cfg_dirs: Sequence[str], cwd: str, sid: str) -> Tuple[str, bool]:
    """``(path, handed_off)`` across EVERY store, store by store, as the poller's
    ``rq_stale_reason`` looks (lr-reset-poller.sh:796-801): a live ``<sid>.jsonl`` or the path a
    ``.handed-off`` tombstone retired. ``("", False)`` only when no store holds either."""
    for cfg in cfg_dirs:
        p = find_transcript([cfg], cwd, sid)
        if p:
            return p, os.path.exists(handed_off_path(p))
        hits = in_projects(cfg, handed_off_path(sid + ".jsonl"))
        if hits:
            return hits[0][: -len(".handed-off")], True
    return "", False


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
