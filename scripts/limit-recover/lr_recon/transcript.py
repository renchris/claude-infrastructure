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
from typing import Any, Callable, Dict, Iterator, List, Optional, Sequence, Set, Tuple

from lr_recon import clock
from lr_recon import types as T

TAIL_BYTES = 128 * 1024
HEAD_BYTES = 8 * 1024
SUBAGENT_FRESH_S = 120.0
LIMITED_QUIET_S = (
    60.0  # a limited turn's reply lands in ~4 s; gap-3 holds read 135 s to 4 h
)
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
# A kept index re-stats every project dir once per this many passes (a 1/N slice each pass), so a
# file created where no rule below looks is still seen within N passes: the bounded full walk.
ROLL_PASSES = 30


def _stem(name: str) -> str:
    """``<sid>`` of ``<sid><indexed suffix>``."""
    for suf in INDEXED_SUFFIXES:
        if name.endswith(suf):
            return name[: -len(suf)]
    return name


class _Store:
    """One physical projects/: what each project dir held at its last read, and that read's mtime."""

    def __init__(self) -> None:
        self.mtimes: Dict[
            str, Optional[int]
        ] = {}  # dir → st_mtime_ns at its read (None: unread)
        self.held: Dict[str, Tuple[str, ...]] = {}  # dir → indexed names in it
        self.names: Dict[str, Set[str]] = {}  # name → dirs holding it
        self.unlisted: Set[str] = set()
        self.top: Optional[int] = None  # projects/'s st_mtime_ns at its last listing
        self.order: List[str] = []
        self.cursor = 0
        self.seen = -1  # the pass this store was last refreshed in
        self.full = -1  # the pass every dir of this store was last re-checked in


class ProjectsIndex:
    """Every ``<cfg>/projects/*/<name>`` the reconciler asks about, without a walk per lookup.

    A ``projects/*/<sid>.jsonl`` glob lists projects/ and then lstats one candidate in EVERY
    project dir. With ~18,300 dirs per store (one per worktree path ever opened) one such glob took
    3.32 s at load 600 and a pass made ~1,500 of them, so the live reconciler spent ~80 min a pass
    in lstat (2026-10-19, pid 78642, heartbeat max_step_gap_s 1926). The first pass lists each store
    once: projects/, then each project dir, keeping only names with an indexed suffix.

    That sweep alone was still ~73,000 directory reads a pass over four stores (2026-10-20, 10.6 s
    at load 196 in the foreground, minutes in the daemon's background band), so the daemon keeps
    the index across passes (``begin_pass``) and each later pass re-reads only a project dir whose
    mtime moved, a create, unlink or rename in it being what moves it. At a store's first lookup in
    a pass it stats: projects/ (a new or removed project dir relists it, and a new dir is read at
    once); every dir a lookup of the previous or this pass touched, or the slug-direct path found a
    transcript in (``touch``), which is where a live session's ``.handed-off`` or ``.HANDOFF.json``
    appears; and a rolling 1/``ROLL_PASSES`` slice of all dirs, so a file appearing anywhere else (a
    new transcript in an old dir under a cwd the census does not know) is seen within that many
    passes. That last case is the one incremental rule that lags the full walk.

    It gives the glob's answer: ``*`` matches the same entries (no dot-names; directories, symlinks
    followed), a name matches iff it is listed (glob's ``lexists``, so a dangling symlink counts),
    paths are spelled with the caller's own cfg (callers split them on ``/projects/``), and hits
    come back sorted. Two cfgs over one physical projects/ (``.claude`` and ``.claude-next``) share
    one store. A project dir that cannot be listed is lexists-probed per lookup, as glob would.
    Every hit is re-checked with lexists before it is returned, so a file a mover took away since is
    never served."""

    def __init__(
        self,
        scandir_fn: Callable[[str], Any] = os.scandir,
        lexists_fn: Callable[[str], bool] = os.path.lexists,
        step_fn: Optional[Callable[[], None]] = None,
        stat_fn: Callable[[str], os.stat_result] = os.stat,
        roll_passes: int = ROLL_PASSES,
    ) -> None:
        self._scandir = scandir_fn
        self._lexists = lexists_fn
        self._step = step_fn if step_fn is not None else clock.step
        self._stat = stat_fn
        self._roll = max(1, roll_passes)
        self._stores: Dict[str, _Store] = {}
        self._keys: Dict[
            str, str
        ] = {}  # base → realpath, this pass (realpath lstats each part)
        self._pass = 0
        self._hot: Set[str] = set()  # project dir names touched last pass
        self._touched: Set[str] = set()  # ... and this pass
        self._reads = 0  # dir reads since the last step()
        self._rechecked: Set[Tuple[str, str]] = (
            set()
        )  # (store, name) a recheck already answered

    def begin_pass(self) -> None:
        self._pass += 1
        self._keys = {}
        self._hot, self._touched = self._touched, set()

    def touch(self, project: str) -> None:
        """Mark a project dir NAME (every store) for an mtime check at the next refresh."""
        self._touched.add(project)

    def _tick(self) -> None:
        self._reads += 1
        if self._reads % SWEEP_STEP_DIRS == 0:
            self._step()

    def _put(self, st: _Store, d: str, held: Tuple[str, ...]) -> None:
        for n in st.held.get(d, ()):
            s = st.names.get(n)
            if s is not None:
                s.discard(d)
                if not s:
                    del st.names[n]
        st.held[d] = held
        for n in held:
            st.names.setdefault(n, set()).add(d)

    def _drop(self, st: _Store, d: str) -> None:
        self._put(st, d, ())
        st.held.pop(d, None)
        st.mtimes.pop(d, None)
        st.unlisted.discard(d)

    def _read(self, proj: str, st: _Store, d: str, mtime: Optional[int]) -> None:
        """List one project dir; ``mtime`` was taken BEFORE the read, so a change racing the read
        leaves a stale mtime and is re-read at the next check."""
        try:
            with self._scandir(os.path.join(proj, d)) as it:
                held = tuple(e.name for e in it if e.name.endswith(INDEXED_SUFFIXES))
        except OSError:
            st.unlisted.add(d)
            st.mtimes[d] = None
            self._put(st, d, ())
            return
        st.unlisted.discard(d)
        st.mtimes[d] = mtime
        self._put(st, d, held)

    def _check(self, proj: str, st: _Store, d: str) -> None:
        self._tick()
        try:
            m: Optional[int] = self._stat(os.path.join(proj, d)).st_mtime_ns
        except (FileNotFoundError, NotADirectoryError):
            self._drop(st, d)
            return
        except OSError:
            m = None
        if m is None or m != st.mtimes.get(d):
            self._read(proj, st, d, m)

    def _list(self, proj: str) -> Optional[List[str]]:
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
            return None
        return dirs

    def _refresh(self, proj: str, st: _Store) -> None:
        if st.seen == self._pass:
            return
        st.seen = self._pass
        self._reads = 0
        try:
            top: Optional[int] = self._stat(proj).st_mtime_ns
        except OSError:
            top = None
        fresh: Set[str] = set()
        if top is None or top != st.top:
            listing = self._list(proj)
            if listing is None and top is None:  # no store here (any more)
                for d in list(st.mtimes):
                    self._drop(st, d)
                st.order, st.top = [], None
            elif listing is None:
                pass  # a listing that failed on a store that is there: kept, retried next pass
            else:
                st.top = top
                now_in = set(listing)
                for d in [d for d in st.mtimes if d not in now_in]:
                    self._drop(st, d)
                for d in listing:
                    if d not in st.mtimes:
                        fresh.add(d)
                        self._check(proj, st, d)
                st.order = listing
                st.cursor %= max(1, len(listing))
        visit = [d for d in self._hot | self._touched if d in st.mtimes]
        n = len(st.order)
        k = -(-n // self._roll) if n else 0
        visit += [st.order[(st.cursor + j) % n] for j in range(k)]
        st.cursor = (st.cursor + k) % n if n else 0
        for d in visit:
            if d in st.mtimes and d not in fresh:
                fresh.add(d)
                self._check(proj, st, d)
        self._step()

    def _store(self, cfg: str) -> Tuple[str, str, _Store]:
        base = os.path.join(cfg, "projects")
        key = self._keys.get(base)
        if key is None:
            key = self._keys[base] = os.path.realpath(base)
        st = self._stores.get(key)
        if st is None:
            st = self._stores[key] = _Store()
        self._refresh(key, st)
        return base, key, st

    def recheck(self, cfg: str, name: str) -> List[str]:
        """``find`` after an mtime check of EVERY dir in the store, done the first time a name is
        asked for this way and at most once per store per pass. For a live session's transcript the
        slug-direct path missed: the one case where the rolling slice could leave a session the full
        walk would catch without a transcript for up to ROLL_PASSES passes. A warm session that has
        not written one yet is asked about every pass, hence once per name."""
        if not name.endswith(INDEXED_SUFFIXES) or os.sep in name:
            return self.find(cfg, name)
        _, key, st = self._store(cfg)
        if (key, name) not in self._rechecked:
            self._rechecked.add((key, name))
            self._walk(key, st)
        return self.find(cfg, name)

    def _walk(self, key: str, st: _Store) -> None:
        """An mtime check of every dir in the store, at most once per store per pass."""
        if st.full != self._pass:
            st.full = self._pass
            self._reads = 0
            for d in list(st.order):
                if d in st.mtimes:
                    self._check(key, st, d)
            self._step()

    def exact(self, cfg: str, name: str) -> List[str]:
        """``find`` after this pass's full walk of the store, asked for or not before: ``recheck``
        without its once-per-name gate (B4 R1, the review's "exact every pass" variant). So the
        answer is the glob's as of that walk, and a copy that appeared in an untouched dir since the
        last pass is seen now, not within ROLL_PASSES. Cost: at most one walk per store per pass in
        which it is asked. A file created after this pass's walk is seen next pass."""
        if not name.endswith(INDEXED_SUFFIXES) or os.sep in name:
            return self.find(cfg, name)
        _, key, st = self._store(cfg)
        self._walk(key, st)
        return self.find(cfg, name)

    def find(self, cfg: str, name: str) -> List[str]:
        """Sorted ``<cfg>/projects/*/<name>`` paths that exist (lexists), spelled with ``cfg``."""
        if not name.endswith(INDEXED_SUFFIXES) or os.sep in name:
            return sorted(
                glob.glob(os.path.join(glob.escape(cfg), "projects", "*", name))
            )
        base, key, st = self._store(cfg)
        stem = _stem(name)
        for suf in (
            INDEXED_SUFFIXES
        ):  # where any file of this sid lives: its next one lands there
            self._touched.update(st.names.get(stem + suf, ()))
        dirs = st.names.get(name, set()) | st.unlisted
        return sorted(
            p for p in (os.path.join(base, d, name) for d in dirs) if self._lexists(p)
        )


_ACTIVE: Optional[Tuple[ProjectsIndex, int]] = (
    None  # (index, ident of the thread it serves)
)


@contextlib.contextmanager
def pass_index(index: Optional[ProjectsIndex] = None) -> Iterator[ProjectsIndex]:
    """Serve ``in_projects`` on this thread from one index for the block's duration (one pass). A
    kept index (the daemon's, across passes) refreshes incrementally; a fresh one sweeps."""
    global _ACTIVE
    prev = _ACTIVE
    idx = index if index is not None else ProjectsIndex()
    idx.begin_pass()
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


def exact_in_projects(cfg: str, name: str) -> Optional[List[str]]:
    """``<cfg>/projects/*/<name>`` from this thread's pass index after the pass's full walk of the
    store (``ProjectsIndex.exact``). None when no index is open on this thread: the caller must not
    glob in its own loop, and must not touch an index another thread is serving (B4 R1)."""
    active = _ACTIVE
    if active is None or active[1] != threading.get_ident():
        return None
    return active[0].exact(cfg, name)


def find_transcript(cfg_dirs: Sequence[str], cwd: str, sid: str) -> Optional[str]:
    """Slug-direct first (cheap, exact), then every project dir (``in_projects``): a session whose
    cwd moved (worktree hop, recycle) still has exactly one ``<sid>.jsonl``."""
    if not sid:
        return None
    if cwd:
        for cfg in cfg_dirs:
            p = os.path.join(cfg, "projects", slug(cwd), sid + ".jsonl")
            if os.path.isfile(p):
                active = _ACTIVE
                if active is not None and active[1] == threading.get_ident():
                    active[0].touch(
                        slug(cwd)
                    )  # its .handed-off / .HANDOFF.json land here
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


def _limited_and_quiet(
    last: Dict[str, Any],
    last_asst: Optional[Dict[str, Any]],
    newest: Optional[float],
    now: Optional[float],
) -> bool:
    """gap-3 E1, physics instead of shapes: on a session whose last assistant record is the limit
    error, any prompt gets the limit back within ~4 s (handoff-fire.sh, the fallback-C timing), so
    trailing user records with nothing written for LIMITED_QUIET_S are not a turn in flight. One
    exception: a trailing `<bash-input>` (a local `!` command, which needs no API) may still run.

    handoff-fire's precheck already releases every measured shape (the replayed goal since
    c82a349ce, the dead-source notification since 10-13); this copy had none of them, and its
    at_rest feeds the admission's active count and idle fan-out eligibility."""
    if now is None or last_asst is None or newest is None:
        return False
    if not _P.classify_record(last_asst).get("limit"):
        return False
    if _text(last).lstrip().startswith("<bash-input>"):
        return False
    return now - newest >= LIMITED_QUIET_S


def _at_rest(data: bytes, now: Optional[float] = None) -> bool:
    """The last user/assistant record decides: an assistant record not waiting on a tool (or an
    error/limit record, or the synthetic no-op) is at rest; a trailing user record is not, unless
    it follows a limit error and the session has been quiet since (_limited_and_quiet)."""
    last: Optional[Dict[str, Any]] = None
    last_asst: Optional[Dict[str, Any]] = None
    newest: Optional[float] = None
    for rec in _records(data):
        if rec.get("type") in ("user", "assistant") and not rec.get("isSidechain"):
            last = rec
            if rec.get("type") == "assistant":
                last_asst = rec
            ts = _ts(rec)
            if ts is not None and (newest is None or ts > newest):
                newest = ts
    if last is None:
        return False
    if last.get("type") != "assistant":
        return _limited_and_quiet(last, last_asst, newest, now)
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
        at_rest=_at_rest(tail, now),
        teammate=bool(_P.is_teammate_head(head)),
        live_subagents=live_subagents(path, now),
    )


def observe(cfg: str, cwd: str, sid: str) -> T.TranscriptObs:
    """The injected seam observe.py and main use; empty when no transcript is found."""
    path = find_transcript([cfg], cwd, sid)
    active = _ACTIVE
    if not path and cfg and active is not None and active[1] == threading.get_ident():
        hits = active[0].recheck(
            cfg, sid + ".jsonl"
        )  # never lag the full walk on a live session
        path = hits[0] if hits else None
    return observe_transcript(path) if path else T.TranscriptObs()


def ok_turns_since(path: str, since_ts: float) -> List[float]:
    """Healthy assistant-turn timestamps after ``since_ts``, from the tail (fact contradiction)."""
    try:
        tail = _read(path, head=False, n=TAIL_BYTES)
    except OSError:
        return []
    return [ts for ts in _ok_turn_ts(tail) if ts > since_ts]
