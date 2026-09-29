"""The §C10 fence predicate, mirrored from ``lr-recon-fence.sh`` (same order, same reasons).

The bash file is what hooks and the poller call; this mirror is what the daemon uses for its own
reads, and the W5 rig runs both on the same state and compares verdicts. ``defers`` returns
``(True, reason)`` for DEFER (the reconciler owns the session; the caller must not act) and
``(False, reason)`` for ACT. On ``lapsed`` the caller must still take ``locks/<sid>.launch`` and
re-check H(sid) before typing (callers are wired in W4).

A malformed owned file DEFERs (``owned-unreadable``): we cannot tell whose it is, and the failure
to fail toward is "nobody acts", never "two actuators type into one pane". Liveness is injected
(``alive``) so the rule order can be tested without processes; ``proc_alive`` is the real one.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from typing import Any, Callable, Dict, List, Mapping, Optional, Tuple

from lr_recon import types as T

FRESH_S_DEFAULT = 180.0

Alive = Callable[[int, str], bool]


def _load(path: str) -> Optional[Any]:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.loads(fh.read())
    except (OSError, ValueError):
        return None


def _is_int(v: Any) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _is_num(v: Any) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _valid_sid(sid: str) -> bool:
    return bool(sid) and "/" not in sid


def read_owned(paths: T.Paths, sid: str) -> Optional[T.FenceFile]:
    """``owned/<sid>`` as a FenceFile; None when absent OR malformed (``defers`` tells them apart).

    Malformed = not a dict, empty/non-string record_id, no ``procs`` list, or a proc without an
    int pid and a string lstart — the same shape the bash parser refuses."""
    if not _valid_sid(sid):
        return None
    data = _load(os.path.join(paths.owned, sid))
    if not isinstance(data, dict):
        return None
    rid = data.get("record_id")
    procs = data.get("procs")
    if not isinstance(rid, str) or not rid or not isinstance(procs, list):
        return None
    roles: List[T.ProcRole] = []
    for p in procs:
        if not isinstance(p, dict):
            return None
        pid, lstart, role = p.get("pid"), p.get("lstart"), p.get("role", "")
        if not _is_int(pid) or pid < 0 or not isinstance(lstart, str):
            return None
        roles.append(
            T.ProcRole(
                role=role if isinstance(role, str) else "",
                pid=pid,
                lstart=lstart,
                argv_hash=str(p.get("argv_hash", "") or ""),
            )
        )
    attempt = data.get("attempt", 0)
    return T.FenceFile(
        record_id=rid, attempt=attempt if _is_int(attempt) else 0, procs=roles
    )


def read_heartbeat(paths: T.Paths) -> Optional[T.Heartbeat]:
    """``recon/heartbeat`` as a Heartbeat, or None when unreadable (no numeric progress_wall)."""
    data = _load(paths.heartbeat)
    if not isinstance(data, dict) or not _is_num(data.get("progress_wall")):
        return None
    try:
        hb = T.from_dict(T.Heartbeat, data)
    except TypeError:
        return None
    return hb if isinstance(hb, T.Heartbeat) else None


def progress_wall(paths: T.Paths) -> Optional[float]:
    """The one heartbeat field the fence reads; None when unreadable (the rule is then skipped).

    Read on its own, not through ``read_heartbeat``, so a heartbeat missing an unrelated field
    still counts — exactly what the bash side's single-field extraction does."""
    data = _load(paths.heartbeat)
    if not isinstance(data, dict) or not _is_num(data.get("progress_wall")):
        return None
    return float(data["progress_wall"])


def parse_waketime(raw: str) -> float:
    """``sysctl -n kern.waketime`` reads ``{ sec = N, usec = M } …``; unparseable ⇒ 0."""
    m = re.match(r"^\{\s*sec\s*=\s*(\d+)", raw or "")
    return float(m.group(1)) if m else 0.0


def _env_num(env: Mapping[str, str], key: str) -> Optional[float]:
    raw = env.get(key, "")
    if not re.match(r"^(\d+\.?\d*|\.\d+)$", raw or ""):
        return None
    return float(raw)


def read_waketime(env: Optional[Mapping[str, str]] = None) -> float:
    """LR_RECON_WAKETIME seam, else the kernel's last wake; unreadable ⇒ 0 (never defers alone)."""
    env = os.environ if env is None else env
    seam = _env_num(env, "LR_RECON_WAKETIME")
    if seam is not None:
        return seam
    try:
        out = subprocess.run(
            ["sysctl", "-n", "kern.waketime"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return 0.0
    return parse_waketime(out)


def fresh_s(env: Optional[Mapping[str, str]] = None) -> float:
    env = os.environ if env is None else env
    v = _env_num(env, "LR_RECON_FENCE_FRESH_S")
    return FRESH_S_DEFAULT if v is None else v


def _ps(field: str, pid: int) -> str:
    env: Dict[str, str] = dict(os.environ, TZ="UTC", LC_ALL="C")
    try:
        return subprocess.run(
            ["ps", "-o", field + "=", "-p", str(pid)],
            capture_output=True,
            text=True,
            env=env,
            timeout=5,
            check=False,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def lstart_norm(raw: str) -> str:
    """The contract lstart form: runs of spaces collapsed to one, trimmed ("Sep  9" → "Sep 9"),
    as observe.py renders it. Applied to both sides of every comparison."""
    return re.sub(" +", " ", raw or "").strip()


def lstart_of(pid: int) -> str:
    """The ProcId lstart (ps LSTART under TZ=UTC LC_ALL=C), collapsed; "" when gone."""
    return lstart_norm(_ps("lstart", pid)) if pid > 0 else ""


def proc_alive(pid: int, lstart: str) -> bool:
    """§10 #12: exact liveness — same pid AND same start time AND not a zombie."""
    want = lstart_norm(lstart)
    if pid <= 0 or not want:
        return False
    if lstart_of(pid) != want:
        return False
    stat = _ps("stat", pid)
    return bool(stat) and not stat.startswith("Z")


def defers(
    paths: T.Paths,
    sid: str,
    record_id_env: str,
    now: float,
    waketime: float,
    alive: Alive,
    fresh: Optional[float] = None,
) -> Tuple[bool, str]:
    """The §C10 predicate. ``(True, reason)`` = DEFER, ``(False, reason)`` = ACT."""
    if not os.path.exists(paths.recon_on):
        # the bash fence's W5b canary rule: a canary daemon's owned sid defers from its own tree
        croot = os.path.join(paths.lr_root, T.CANARY_ROOT)
        if not (
            _valid_sid(sid)
            and os.path.exists(os.path.join(croot, "canary.on"))
            and os.path.isfile(os.path.join(croot, "owned", sid))
        ):
            return False, "recon-off"
        paths = T.Paths(lr_root=paths.lr_root, root=croot, canary=frozenset((sid,)))
    if not _valid_sid(sid) or not os.path.isfile(os.path.join(paths.owned, sid)):
        return False, "not-owned"
    owned = read_owned(paths, sid)
    if owned is None:
        return True, "owned-unreadable"
    if record_id_env and record_id_env == owned.record_id:
        return False, "own-actuator"
    pw = progress_wall(paths)
    if pw is not None:
        limit = FRESH_S_DEFAULT if fresh is None else fresh
        if now - max(pw, waketime) <= limit:
            return True, "heartbeat-fresh"
    for p in owned.procs:
        if alive(p.pid, p.lstart):
            return True, "proc-alive:%s:%d" % (p.role, p.pid)
    return False, "lapsed"
