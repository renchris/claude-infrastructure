"""Plan, step (c)'s decision (§3 step 6, §5): movers → ``claude-accounts --place`` → records.

``--place`` is the ONLY scorer (§C5); this module feeds it the reconciler's own census (k_work,
movers) and turns its answer into record state: PLANNED with a pinned target and a phantom seat,
or a named WAIT with its ETA. It never picks an account itself.

Invariant 13 (missing data is never headroom): an account whose k_work the census could not
measure is sent as ``null``, which --place turns into zero seats; exit 3 from --place is WAIT_DATA
for every mover, and one bounded background sweep is started so the next pass can re-plan.
Invariant 16 (rank → assign → probe is one decision): one pass, one ``--assign-many``, under
``locks/admit.lock`` whose holder a manual ``lr-fleet --one`` can see and wait on.

Operator decision 3 (no account passes the floors: wait vs least-thin) is unruled. Its switch
``LR_NO_FLOOR_POLICY`` defaults to ``wait``; the recommended ``hybrid`` needs a least-thin pick
inside --place, which W1 did not build, so ``hybrid`` is read, logged, and behaves as ``wait``.
RECOVERY_IDLE_SEATS is the constant ``active``: W0 SUMMARY item 2 measured a no-prompt --resume
writing 17 records within 7 s, so a relaunched session already counts as an active seat.
"""

from __future__ import annotations

import glob
import json
import os
import subprocess
import tempfile
import time
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

from lr_recon import store
from lr_recon import types as T

KWORK_WINDOW_S = 600  # KWORK_WINDOW_MIN = 10 (§C5)
PHANTOM_TTL_S = 1200  # §3 step 6: ttl_s=1200, refreshed every pass while non-terminal
EPS_STAY_S = 900  # §5 stay rule
FRESH_EVERY_S = 120  # at most one background --fresh sweep per 2 minutes
RECOVERY_IDLE_SEATS = "active"  # W0 SUMMARY item 2 (lead ruling 2026-09-29)
PHANTOM_PHASES = (
    "PRE-MOVE",
    "TRANSPLANTED",
    "HUSK-RETIRED",
    "EXITING",
    "EXITED",
    "RELAUNCHED",
)

RunFn = Callable[..., Any]


def accounts_bin() -> str:
    """The repo's own claude-accounts beside this package, else the live copy, else PATH."""
    env = os.environ.get("LR_ACCOUNTS_BIN")
    if env:
        return env
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.normpath(
        os.path.join(here, "..", "..", "..", "bin", "claude-accounts")
    )
    if os.path.exists(repo):
        return repo
    live = os.path.expanduser("~/.claude/bin/claude-accounts")
    return live if os.path.exists(live) else "claude-accounts"


# ── census inputs ───────────────────────────────────────────────────────────────────────────────


def _fresh(path: str, now: float, window: float) -> bool:
    try:
        return now - os.stat(path).st_mtime <= window
    except OSError:
        return False


def subagents_written(
    tx_path: str, sid: str, now: float, window: float = KWORK_WINDOW_S
) -> int:
    if not tx_path:
        return 0
    base = os.path.join(os.path.dirname(tx_path), sid, "subagents")
    pats = (
        os.path.join(base, "agent-*.jsonl"),
        os.path.join(base, "**", "agent-*.jsonl"),
    )
    seen = {p for pat in pats for p in glob.glob(pat, recursive=True)}
    return sum(1 for p in seen if _fresh(p, now, window))


def kwork(
    snap: T.Snapshot, accounts: Sequence[str], now: float
) -> Dict[str, Optional[int]]:
    """Per account: top-level + subagent transcripts written in the last 10 min (§C5). Any
    census degradation that could hide sessions makes EVERY account unmeasured (None)."""
    if "ps" in snap.degraded or "registry" in snap.degraded:
        return {a: None for a in accounts}
    out: Dict[str, Optional[int]] = {a: 0 for a in accounts}
    for s in snap.sessions.values():
        if s.acct not in out:
            continue
        n = 1 if _fresh(s.transcript.path, now, KWORK_WINDOW_S) else 0
        n += subagents_written(s.transcript.path, s.sid, now)
        out[s.acct] = (out[s.acct] or 0) + n
    return out


def mover_weight(s: T.SessionObs, now: float) -> int:
    """§5: 1 + distinct subagent transcripts written in the window before death."""
    return 1 + subagents_written(s.transcript.path, s.sid, now)


def movers(records: Sequence[T.Record], snap: T.Snapshot, now: float) -> List[T.Mover]:
    """PRE-MOVE records that want a target, LIMITED before IDLE, then oldest death first."""
    rows: List[Tuple[int, float, T.Mover]] = []
    for rec in records:
        if (
            not rec.open
            or rec.phase != "PRE-MOVE"
            or rec.target_acct
            and rec.substate == "PLANNED"
        ):
            continue
        if rec.substate not in (
            "DETECTED",
            "WAIT_SLOT",
            "WAIT_DATA",
            "WAIT_CAPACITY",
            "BACKOFF",
        ):
            continue
        s = snap.sessions.get(rec.sid)
        w = mover_weight(s, now) if s else rec.weight
        death = rec.timeline.detected or now
        m = T.Mover(
            sid=rec.sid,
            src=rec.source_cfg or rec.source_acct,
            kind=rec.kind,
            w=w,
            model=(s.model if s and s.model else None),
            death_ts=death,
        )
        rows.append((0 if rec.kind == "limited" else 1, death, m))
    rows.sort(key=lambda r: (r[0], r[1], r[2].sid))
    return [m for _k, _d, m in rows]


# ── the --place driver ──────────────────────────────────────────────────────────────────────────


def place(
    lane: str,
    mvs: Sequence[T.Mover],
    facts_dir: str,
    kw: Dict[str, Optional[int]],
    run: RunFn = subprocess.run,
    timeout: float = 30.0,
) -> Tuple[Dict[str, T.Placement], int]:
    """Run --place once for a lane. Exit 3 (or anything unparseable) ⇒ every mover WAIT_DATA."""
    if not mvs:
        return {}, 0
    tmp = tempfile.mkdtemp(prefix="lr-recon-place-")
    mf, kf = os.path.join(tmp, "movers.jsonl"), os.path.join(tmp, "kwork.json")
    with open(mf, "w", encoding="utf-8") as fh:
        for m in mvs:
            row = {k: v for k, v in T.to_dict(m).items() if v is not None}
            fh.write(json.dumps(row, separators=(",", ":")) + "\n")
    with open(kf, "w", encoding="utf-8") as fh:
        json.dump(kw, fh, separators=(",", ":"))
    argv = [
        accounts_bin(),
        "--place",
        "--lane",
        lane,
        "--recovery",
        "--movers",
        mf,
        "--facts",
        facts_dir,
        "--kwork",
        kf,
        "--json",
    ]
    wait = {m.sid: T.Placement(acct=None, reason="wait-data", weight=m.w) for m in mvs}
    try:
        cp = run(argv, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return wait, 124
    finally:
        for p in (mf, kf):
            try:
                os.unlink(p)
            except OSError:
                pass
        try:
            os.rmdir(tmp)
        except OSError:
            pass
    if cp.returncode != 0:
        return wait, int(cp.returncode)
    try:
        data = json.loads(cp.stdout or "{}")
    except ValueError:
        return wait, 65
    out: Dict[str, T.Placement] = {}
    for m in mvs:
        row = data.get(m.sid) if isinstance(data, dict) else None
        out[m.sid] = (
            T.from_dict(T.Placement, row) if isinstance(row, dict) else wait[m.sid]
        )
    return out, 0


def start_fresh_sweep(
    paths: T.Paths, now: float, popen: Callable[..., Any] = subprocess.Popen
) -> bool:
    """One detached, self-bounded ``claude-accounts --json --fresh --max-wait 60`` off the critical
    path (§3 step 4); a stamp file limits it to one per FRESH_EVERY_S."""
    stamp = paths.p("fresh.stamp")
    if _fresh(stamp, now, FRESH_EVERY_S):
        return False
    store.atomic_write_text(stamp, "%f\n" % now)
    try:
        popen(
            [accounts_bin(), "--json", "--fresh", "--max-wait", "60"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        return False
    return True


# ── placements → record state ───────────────────────────────────────────────────────────────────


def _source_resets(rec: T.Record, facts: Dict[str, T.Fact]) -> Optional[float]:
    f = facts.get("%s.%s" % (rec.source_acct, rec.scope))
    return f.resets_at if f else None


def apply(
    records: Dict[str, T.Record],
    placed: Dict[str, T.Placement],
    facts: Dict[str, T.Fact],
    cfg_of: Callable[[str], str],
    now: float,
) -> None:
    """PLANNED with a pinned target, or a named WAIT with its ETA (§5 ETA and stay rules)."""
    for sid, p in placed.items():
        rec = records.get(sid)
        if rec is None or not rec.open:
            continue
        rec.weight = p.weight or rec.weight
        if p.acct:
            rec.target_acct, rec.target_cfg = p.acct, cfg_of(p.acct)
            rec.substate, rec.wait = "PLANNED", None
            rec.assign_id = rec.record_id
            rec.timeline.planned = rec.timeline.planned or now
            continue
        eta = now + p.eta_s if p.eta_s is not None else None
        resets = _source_resets(rec, facts)
        if (
            rec.kind == "limited"
            and resets is not None
            and (eta is None or resets < eta)
        ):
            reason = "WAIT_RESET"
            eta = resets
        elif p.reason == "wait-data":
            reason = "WAIT_DATA"
        elif "capacity" in (p.reason or ""):
            reason = "WAIT_CAPACITY"
        else:
            reason = "WAIT_SLOT"
        since = rec.wait.since if rec.wait and rec.wait.reason == reason else now
        max_age = T.MAX_AGE_S.get(reason)
        rec.substate = reason
        rec.wait = T.Wait(
            reason=reason,
            since=since,
            eta=eta,
            detail=p.reason or "",
            max_age_s=max_age,
            wakes=["phantom-void", "reset", "sweep"],
        )


# ── phantoms (§5) and the admit lock (invariant 16) ─────────────────────────────────────────────


def phantom_rows(records: Sequence[T.Record]) -> List[Dict[str, Any]]:
    """PLANNED through RELAUNCHED hold a live phantom, refreshed every pass; PLAN-ONLY never."""
    rows = []
    for r in records:
        if (
            not r.open
            or r.plan_only
            or not r.target_acct
            or r.phase not in PHANTOM_PHASES
        ):
            continue
        if r.phase == "PRE-MOVE" and r.substate != "PLANNED":
            continue
        rows.append(
            {
                "acct": r.target_acct,
                "id": r.assign_id or r.record_id,
                "sid": r.sid,
                "w": max(1, int(r.weight)),
                "ttl_s": PHANTOM_TTL_S,
            }
        )
    return rows


def assign_many(rows: Sequence[Dict[str, Any]], run: RunFn = subprocess.run) -> int:
    if not rows:
        return 0
    fd, path = tempfile.mkstemp(prefix="lr-recon-assign-", suffix=".jsonl")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            for r in rows:
                fh.write(json.dumps(r, separators=(",", ":")) + "\n")
        cp = run(
            [accounts_bin(), "--assign-many", path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        return int(cp.returncode)
    except (OSError, subprocess.TimeoutExpired):
        return 124
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def unassign(assign_id: str, run: RunFn = subprocess.run) -> int:
    """Void a phantom (close, park, ABORT, re-place, terminal failure); keyed by id, repeatable."""
    try:
        cp = run(
            [accounts_bin(), "--unassign", assign_id],
            capture_output=True,
            text=True,
            timeout=30,
        )
        return int(cp.returncode)
    except (OSError, subprocess.TimeoutExpired):
        return 124


def admit_lock_take(
    paths: T.Paths,
    holder: T.LockHolder,
    alive: store.Alive,
    tries: int = 20,
    pause: float = 0.25,
) -> bool:
    """Bounded wait (≤5 s) for ``locks/admit.lock``; a dead holder is stolen by lock_take."""
    d = os.path.join(paths.locks, "admit.lock")
    os.makedirs(paths.locks, exist_ok=True)
    for _ in range(tries):
        if store.lock_take(d, holder, alive) in ("taken", "stolen-dead"):
            return True
        time.sleep(pause)
    return False


def admit_lock_release(paths: T.Paths, record_id: str) -> None:
    store.lock_release(os.path.join(paths.locks, "admit.lock"), record_id)


def write_plan(
    paths: T.Paths, mode: str, cid: str, placed: Dict[str, T.Placement], now: float
) -> str:
    """plan mode ⇒ recon/plans/<cid>.json; observe mode ⇒ recon/shadow/<cid>.json."""
    d = paths.shadow if mode == "observe" else paths.plans
    path = os.path.join(d, cid + ".json")
    store.atomic_write_json(
        path,
        {
            "cid": cid,
            "at": now,
            "mode": mode,
            "placements": {k: T.to_dict(v) for k, v in placed.items()},
        },
    )
    return path


def no_floor_policy() -> str:
    """Decision 3 switch; only ``wait`` is implemented (see module docstring)."""
    return os.environ.get("LR_NO_FLOOR_POLICY", "wait")
