"""lr_recon on-disk store: records, fence file, run claims, mkdir locks, bounded logs, requests.

One writer per file and every write atomic (§C7): a reader — this daemon after a crash, or a bash
tool mid-tick — sees the old bytes or the new ones, never a torn file. JSON is always COMPACT
because bash readers pull ``"pid":N`` and ``"record_id":"…"`` out with sed (lr-lib.sh
lr_claim_holder_pid), and a space after the colon silently blinds them.

Every external effect (liveness, argv, ``ps``) is an injected seam so tests stay hermetic.
"""

from __future__ import annotations

import errno
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import tempfile
import time
import uuid
from typing import Any, Callable, Dict, List, Optional, Tuple

from lr_recon import types as T

Alive = Callable[[int, str], bool]
ArgvOf = Callable[[int], str]
OnBad = Callable[[str, str], None]

BY = "lr-reconciler"
EVENT_LINE_MAX = 1024  # bytes, newline included (§C12)
EVENTS_MAX = 8 << 20
LAUNCH_MAX = 4 << 20
RESTARTS_MAX = 1 << 20
_UUID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I
)
_PID = re.compile(r'"pid":([0-9]+)')
_ACQUIRED = ("taken", "ours", "stolen-dead", "stolen-legacy", "stolen-orphan")


# ── atomic writes (§C7) ──────────────────────────────────────────────────────────────────────────


def dumps(obj: Any) -> str:
    return json.dumps(obj, separators=(",", ":"))


def _fsync_dir(d: str) -> None:
    fd = os.open(d, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _write_tmp(path: str, text: str) -> str:
    """Write + fsync a sibling tmp file (same dir ⇒ same filesystem ⇒ rename/link is atomic)."""
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix="." + os.path.basename(path) + ".")
    try:
        os.write(fd, text.encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)
    return tmp


def atomic_write_text(path: str, text: str) -> None:
    tmp = _write_tmp(path, text)
    try:
        os.replace(tmp, path)
    except BaseException:
        _unlink(tmp)
        raise
    _fsync_dir(os.path.dirname(path) or ".")


def atomic_write_json(path: str, obj: Any) -> None:
    atomic_write_text(path, dumps(obj) + "\n")


def _unlink(path: str) -> None:
    try:
        os.unlink(path)
    except OSError:
        pass


def _read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def ensure_dirs(paths: T.Paths) -> None:
    """Create the reconciler's own tree ONLY; shared lr_root dirs are made on demand (§C7)."""
    for d in paths.reconciler_dirs():
        os.makedirs(d, 0o700, exist_ok=True)


# ── records (§4.1) ───────────────────────────────────────────────────────────────────────────────


def record_path(paths: T.Paths, sid: str) -> str:
    return os.path.join(paths.sessions, sid + ".json")


def load_record(paths: T.Paths, sid: str) -> Optional[T.Record]:
    """None when absent; raises ValueError/TypeError/OSError when the file is not a record."""
    path = record_path(paths, sid)
    try:
        data = _read_json(path)
    except FileNotFoundError:
        return None
    if not isinstance(data, dict) or data.get("sid") != sid:
        raise ValueError("not a record for sid %s" % sid)
    if not isinstance(data.get("record_id"), str) or not data["record_id"]:
        raise ValueError("record has no record_id")
    rec: T.Record = T.from_dict(T.Record, data)
    return rec


def save_record(paths: T.Paths, rec: T.Record, now: Optional[float] = None) -> None:
    rec.updated_at = time.time() if now is None else now
    atomic_write_json(record_path(paths, rec.sid), T.to_dict(rec))


def quarantine(paths: T.Paths, path: str, now: Optional[float] = None) -> str:
    """MOVE (never delete) a bad file aside so one corrupt record cannot wedge the loop (§C7)."""
    os.makedirs(paths.quarantine, 0o700, exist_ok=True)
    dest = os.path.join(
        paths.quarantine,
        "%s.%d" % (os.path.basename(path), int(time.time() if now is None else now)),
    )
    os.replace(path, dest)
    return dest


def load_all(paths: T.Paths, on_bad: OnBad) -> Dict[str, T.Record]:
    """Every loadable record; never raises. Corrupt files are quarantined, then reported."""
    out: Dict[str, T.Record] = {}
    try:
        names = sorted(os.listdir(paths.sessions))
    except OSError:
        return out
    for name in names:
        if not name.endswith(".json") or name.startswith("."):
            continue
        sid = name[: -len(".json")]
        path = os.path.join(paths.sessions, name)
        try:
            rec = load_record(paths, sid)
            if rec is not None:
                out[sid] = rec
        except Exception as exc:  # noqa: BLE001 — per-record isolation is the point
            reason = "%s: %s" % (type(exc).__name__, exc)
            try:
                quarantine(paths, path)
            except OSError as qexc:
                reason += " (quarantine failed: %s)" % qexc
            try:
                on_bad(path, reason)
            except Exception:  # noqa: BLE001
                pass
    return out


# ── fence file owned/<sid> (§C7/§C10: the only file other tools read) ───────────────────────────


def fence_path(paths: T.Paths, sid: str) -> str:
    return os.path.join(paths.owned, sid)


def read_fence(paths: T.Paths, sid: str) -> Optional[T.FenceFile]:
    try:
        data = _read_json(fence_path(paths, sid))
        if not isinstance(data, dict) or not isinstance(data.get("record_id"), str):
            return None
        fence: T.FenceFile = T.from_dict(T.FenceFile, data)
        return fence
    except (OSError, ValueError, TypeError):
        return None


def own(paths: T.Paths, sid: str, fence: T.FenceFile) -> bool:
    """Exclusive create via link(2) of a complete tmp file: no reader ever sees an empty fence.
    Re-entry by the same record_id is a no-op True; any other owner ⇒ False."""
    path = fence_path(paths, sid)
    os.makedirs(paths.owned, 0o700, exist_ok=True)
    tmp = _write_tmp(path, dumps(T.to_dict(fence)) + "\n")
    try:
        os.link(tmp, path)
    except FileExistsError:
        cur = read_fence(paths, sid)
        return cur is not None and cur.record_id == fence.record_id
    finally:
        _unlink(tmp)
    _fsync_dir(paths.owned)
    return True


def update_fence(paths: T.Paths, sid: str, fence: T.FenceFile) -> bool:
    cur = read_fence(paths, sid)
    if cur is None or cur.record_id != fence.record_id:
        return False
    atomic_write_json(fence_path(paths, sid), T.to_dict(fence))
    return True


def release_fence(paths: T.Paths, sid: str, record_id: str) -> bool:
    cur = read_fence(paths, sid)
    if cur is None or cur.record_id != record_id:
        return False
    _unlink(fence_path(paths, sid))
    return True


# ── the rename-verify steal shared by run claims and mkdir locks (lr-lib.sh lr_claim_take) ───────


def _steal(d: str, judged: Any, reread: Callable[[str], Any]) -> bool:
    """Rename ``d`` to a tomb, confirm the tomb holds what we judged dead, then re-create ``d``.
    A peer that stole and re-stamped in between is moved back and wins (verdict lost-race)."""
    tomb = "%s.stolen.%d.%d" % (d, os.getpid(), random.randint(0, 1 << 30))
    try:
        os.rename(d, tomb)
    except OSError:
        return False
    if reread(tomb) != judged:
        try:
            os.rename(tomb, d)
        except OSError:
            shutil.rmtree(tomb, ignore_errors=True)
        return False
    shutil.rmtree(tomb, ignore_errors=True)
    try:
        os.mkdir(d)
    except OSError:
        return False
    return True


def _orphan_grace() -> int:
    raw = os.environ.get("LR_CLAIM_ORPHAN_GRACE_S", "10")
    return int(raw) if raw.isdigit() else 10


def _dir_age(d: str, now: float) -> Optional[float]:
    try:
        return now - os.stat(d).st_mtime
    except OSError:
        return None


# ── run claims runs/by-sid/<sid>.active (interop with the landed bash claim) ─────────────────────


def claim_dir(paths: T.Paths, sid: str) -> str:
    return os.path.join(paths.runs_by_sid, sid + ".active")


def _claim_key(h: Optional[T.RunClaimHolder]) -> Optional[Tuple[int, str, str]]:
    return None if h is None else (h.pid, h.lstart, h.record_id)


def _read_holder(d: str) -> Optional[T.RunClaimHolder]:
    try:
        with open(os.path.join(d, "holder"), "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return None
    try:
        data = json.loads(text)
        if isinstance(data, dict) and isinstance(data.get("pid"), int):
            return T.RunClaimHolder(
                pid=data["pid"],
                lstart=str(data.get("lstart") or ""),
                owner=str(data.get("owner") or ""),
                record_id=str(data.get("record_id") or ""),
            )
    except ValueError:
        pass
    # The bash reader's sed rule, so both sides agree on a torn holder.
    m = _PID.search(text)
    return T.RunClaimHolder(pid=int(m.group(1))) if m else None


def read_claim(paths: T.Paths, sid: str) -> Optional[T.RunClaimHolder]:
    return _read_holder(claim_dir(paths, sid))


def _claim_stamp(d: str, sid: str, h: T.RunClaimHolder, now: float) -> None:
    obj = {
        "sid": sid,
        "pane": "-",
        "pid": h.pid,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
        "by": BY,
        "lstart": h.lstart,
        "owner": h.owner or BY,
        "record_id": h.record_id,
    }
    atomic_write_json(os.path.join(d, "holder"), obj)


def claim_take(
    paths: T.Paths,
    sid: str,
    holder: T.RunClaimHolder,
    alive: Alive,
    argv_of: ArgvOf,
    now: Optional[float] = None,
) -> str:
    """taken | ours | held | stolen-dead | stolen-legacy | stolen-orphan | lost-race.
    A legacy (lstart-less) holder is alive only if its argv is a recovery driver naming the sid,
    because a bare pid may have been reused by anything since it was stamped."""
    now = time.time() if now is None else now
    d = claim_dir(paths, sid)
    os.makedirs(paths.runs_by_sid, exist_ok=True)
    try:
        os.mkdir(d)
        verdict = "taken"
    except FileExistsError:
        cur = _read_holder(d)
        if cur is not None:
            if cur.record_id and cur.record_id == holder.record_id:
                return "ours"
            if cur.lstart:
                if alive(cur.pid, cur.lstart):
                    return "held"
                verdict = "stolen-dead"
            else:
                argv = argv_of(cur.pid)
                if ("lr-fleet" in argv or "cc-lr" in argv) and sid in argv:
                    return "held"
                verdict = "stolen-legacy"
        else:
            age = _dir_age(d, now)
            if age is None:
                return "lost-race"
            if age < _orphan_grace():
                return "held"
            verdict = "stolen-orphan"
        if not _steal(d, _claim_key(cur), lambda p: _claim_key(_read_holder(p))):
            return "lost-race"
    try:
        _claim_stamp(d, sid, holder, now)
    except OSError:
        shutil.rmtree(d, ignore_errors=True)
        raise
    return verdict


def claim_release(paths: T.Paths, sid: str, record_id: str) -> bool:
    cur = read_claim(paths, sid)
    if cur is None or not record_id or cur.record_id != record_id:
        return False
    shutil.rmtree(claim_dir(paths, sid), ignore_errors=True)
    return True


def claim_restamp(
    paths: T.Paths, sid: str, record_id: str, pid: int, lstart: str
) -> bool:
    cur = read_claim(paths, sid)
    if cur is None or not record_id or cur.record_id != record_id:
        return False
    h = T.RunClaimHolder(
        pid=pid, lstart=lstart, owner=cur.owner or BY, record_id=record_id
    )
    _claim_stamp(claim_dir(paths, sid), sid, h, time.time())
    return True


# ── generic mkdir locks under lr_root/locks (§C7 lock pattern) ───────────────────────────────────


def _sha1(s: str) -> str:
    return hashlib.sha1(s.encode("utf-8")).hexdigest()


def launch_lock(paths: T.Paths, sid: str) -> str:
    return os.path.join(paths.locks, sid + ".launch")


def recycle_lock(paths: T.Paths, sock: str, window_id: Any) -> str:
    return os.path.join(
        paths.locks, "pane-%s.recycle" % _sha1("%s:%s" % (sock, window_id))
    )


def git_lock(paths: T.Paths, git_common_dir: str) -> str:
    return os.path.join(paths.locks, "git-" + _sha1(git_common_dir))


def lock_path(paths: T.Paths, kind: str, key: str) -> str:
    """kind: launch (key=sid) · recycle (key="<sock>:<window_id>") · git (key=git common dir)."""
    if kind == "launch":
        return launch_lock(paths, key)
    if kind == "recycle":
        sock, _, win = key.rpartition(":")
        return recycle_lock(paths, sock, win)
    if kind == "git":
        return git_lock(paths, key)
    raise ValueError("unknown lock kind %r" % kind)


def lock_holder(dirpath: str) -> Optional[T.LockHolder]:
    try:
        data = _read_json(os.path.join(dirpath, "holder"))
        if not isinstance(data, dict):
            return None
        h: T.LockHolder = T.from_dict(T.LockHolder, data)
        return h
    except (OSError, ValueError, TypeError):
        return None


def _lock_key(h: Optional[T.LockHolder]) -> Optional[Tuple[int, str, str]]:
    return None if h is None else (h.pid, h.lstart, h.record_id)


def lock_take(dirpath: str, holder: T.LockHolder, alive: Alive) -> str:
    """taken | held | stolen-dead | lost-race. A holder-less lock older than the orphan grace is
    treated as dead: its taker died between mkdir and stamp, and nothing else would ever free it."""
    os.makedirs(os.path.dirname(dirpath), exist_ok=True)
    try:
        os.mkdir(dirpath)
        verdict = "taken"
    except FileExistsError:
        cur = lock_holder(dirpath)
        if cur is not None:
            if alive(cur.pid, cur.lstart):
                return "held"
        else:
            age = _dir_age(dirpath, time.time())
            if age is None:
                return "lost-race"
            if age < _orphan_grace():
                return "held"
        if not _steal(dirpath, _lock_key(cur), lambda p: _lock_key(lock_holder(p))):
            return "lost-race"
        verdict = "stolen-dead"
    try:
        atomic_write_json(os.path.join(dirpath, "holder"), T.to_dict(holder))
    except OSError:
        shutil.rmtree(dirpath, ignore_errors=True)
        raise
    return verdict


def lock_release(dirpath: str, record_id: str) -> bool:
    cur = lock_holder(dirpath)
    if cur is None or cur.record_id != record_id:
        return False
    shutil.rmtree(dirpath, ignore_errors=True)
    return True


def proc_lstart(pid: int, run: Callable[..., Any] = subprocess.run) -> str:
    """ps LSTART under TZ=UTC LC_ALL=C, so (pid, lstart) is an exact identity (§10 #12)."""
    env = dict(os.environ, TZ="UTC", LC_ALL="C")
    try:
        cp = run(
            ["ps", "-o", "lstart=", "-p", str(pid)],
            capture_output=True,
            text=True,
            env=env,
        )
    except OSError:
        return ""
    # Collapse runs of spaces ("Sep  9" → "Sep 9"): the one rendering observe.py, the fence and the
    # watchdog all compare, so a padded day never reads as a different process.
    return " ".join(str(cp.stdout or "").split()) if cp.returncode == 0 else ""


# ── §4.5 write order: claim → owned/<sid> → record-with-intent ───────────────────────────────────


def take_ownership(
    paths: T.Paths,
    rec: T.Record,
    holder: T.RunClaimHolder,
    alive: Alive,
    argv_of: ArgvOf,
    now: Optional[float] = None,
) -> str:
    """Returns the claim verdict on success, the claim verdict alone when the claim was not
    acquired (nothing else written), or "owned-by-other" (the claim we just took is released)."""
    now = time.time() if now is None else now
    if not holder.record_id:
        holder = T.RunClaimHolder(
            holder.pid, holder.lstart, holder.owner, rec.record_id
        )
    verdict = claim_take(paths, rec.sid, holder, alive, argv_of, now)
    if verdict not in _ACQUIRED:
        return verdict
    if not own(paths, rec.sid, T.FenceFile(rec.record_id, rec.attempt, procs=[])):
        if verdict != "ours":
            claim_release(paths, rec.sid, holder.record_id)
        return "owned-by-other"
    if rec.intent is None:
        rec.intent = T.Intent(nonce=uuid.uuid4().hex, at=now)
    save_record(paths, rec, now)
    return verdict


# ── bounded append-only logs (§C12) ──────────────────────────────────────────────────────────────


def _max_bytes(default: int) -> int:
    raw = os.environ.get("LR_RECON_LOG_MAX_BYTES", "")
    return int(raw) if raw.isdigit() and int(raw) > 0 else default


def append_bounded(path: str, line: str, max_bytes: int) -> None:
    """One os.write on O_APPEND. Rotates to ``<path>.1`` (one generation) BEFORE a write that
    would cross the bound, so the live file stays ≤ max_bytes plus at most one line."""
    data = (line.rstrip("\n") + "\n").encode("utf-8")
    try:
        if os.path.getsize(path) + len(data) > max_bytes:
            os.replace(path, path + ".1")
    except FileNotFoundError:
        pass
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)


def event_line(ev: T.Event, limit: int = EVENT_LINE_MAX) -> str:
    """Compact JSON ≤ limit-1 bytes (newline makes limit). Only ``detail`` is cut, whole
    characters at a time, so the line is always valid JSON."""
    obj = T.to_dict(ev)
    detail = str(obj.get("detail") or "")
    k = len(detail)
    while True:
        obj["detail"] = detail[:k]
        s = dumps(obj)
        excess = len(s.encode("utf-8")) - (limit - 1)
        if excess <= 0 or k == 0:
            return s
        k = max(0, k - excess)  # each dropped char frees ≥1 byte


def append_event(paths: T.Paths, ev: T.Event) -> None:
    append_bounded(paths.events, event_line(ev), _max_bytes(EVENTS_MAX))


def append_launch(paths: T.Paths, line: str) -> None:
    append_bounded(paths.launch_log, line.replace("\n", " "), _max_bytes(LAUNCH_MAX))


def append_restart(paths: T.Paths, obj: Dict[str, Any]) -> None:
    append_bounded(paths.restarts, dumps(obj), _max_bytes(RESTARTS_MAX))


# ── requests (§C2 origins, §7.3 moved never deleted) ─────────────────────────────────────────────


def list_requests(paths: T.Paths) -> List[T.Request]:
    """Dispatch on SHAPE, never the glob: the dir also holds retire-husk-<sid>.json breadcrumbs."""
    out: List[T.Request] = []
    try:
        names = sorted(os.listdir(paths.requests))
    except OSError:
        return out
    for name in names:
        if name.endswith(".cc-lr.json"):
            stem, origin = name[: -len(".cc-lr.json")], "cc-lr"
        elif name.endswith(".json"):
            stem, origin = name[: -len(".json")], "hook"
        else:
            continue
        if not _UUID.match(stem):
            continue
        path = os.path.join(paths.requests, name)
        try:
            raw = _read_json(path)
            st = os.stat(path)
        except (OSError, ValueError):
            continue
        if not isinstance(raw, dict) or raw.get("sid") != stem:
            continue
        at = raw.get("at")
        when = float(at) if isinstance(at, (int, float)) else st.st_mtime
        out.append(T.Request(sid=stem, origin=origin, path=path, at=when, raw=raw))
    return out


def claim_request(
    paths: T.Paths,
    req: T.Request,
    outcome: str,
    detail: str = "",
    now: Optional[float] = None,
) -> str:
    """MOVE the request into claimed/ under its own basename (the poller's convention), then
    record ``recon_outcome`` in the moved copy. Returns the new path, "" if it was already gone."""
    now = time.time() if now is None else now
    os.makedirs(paths.claimed, exist_ok=True)
    dest = os.path.join(paths.claimed, os.path.basename(req.path))
    if os.path.exists(dest):
        dest = "%s.%d" % (dest, int(now * 1000))
    try:
        os.rename(req.path, dest)
    except OSError as exc:
        if exc.errno == errno.ENOENT:
            return ""
        raise
    try:
        raw = _read_json(dest)
        if not isinstance(raw, dict):
            raw = dict(req.raw)
    except (OSError, ValueError):
        raw = dict(req.raw)
    raw["recon_outcome"] = {"outcome": outcome, "detail": detail, "at": now}
    atomic_write_json(dest, raw)
    return dest
