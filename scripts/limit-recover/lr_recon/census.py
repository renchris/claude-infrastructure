"""Census, step (b) of §3: every live session in an affected scope lands in EXACTLY one bucket.

Pure over a ``T.Snapshot`` + records + facts: no subprocess, no keystroke. Also the record
bookkeeping that follows from a bucket (cohorts, origins, the §C2 actuation gate) and the §3
step-3 stale reconcile that runs before anything acts.

A focused limited pane MOVES (decision 7, ruled 2026-09-30: move focused panes;
``LR_MOVE_FOCUSED=off`` is the kill switch that holds it as HOLD-FOCUS). Idle fan-out stays off
(``LR_IDLE_FANOUT=on`` to enable). A team lead with live members is HELD:team, unconditionally in v1 (decision 4, ruled
2026-09-30: hold, then continue in place at the reset; a cross-account team move is v2).
Decision 2 is SETTLED: a pane with live background work holds until the job ends.
"""

from __future__ import annotations

import dataclasses
import os
from typing import Dict, List, Mapping, Optional, Sequence, Tuple

from lr_recon import facts as F
from lr_recon import observe_rows, transcript
from lr_recon import types as T

STAY_S = 900  # §5 stay rule: the source resets within 15 min ⇒ WAIT_RESET in place
IDLE_MIN_LEFT_S = (
    1800  # an idle session moves only with ≥30 min left on an account-wide fact
)
_ORIGIN_RANK = {o: i for i, o in enumerate(T.ORIGINS)}  # hook < census < fanout < cc-lr


def _pane(s: T.SessionObs, snap: T.Snapshot) -> Optional[T.PaneObs]:
    return snap.panes.get("%d:%d" % s.pane) if s.pane else None


_CLAUDE_ARGV0 = ("claude", "claude.exe")


def is_member_argv(args: str, sid: str) -> bool:
    """A teammate of lead ``sid``: argv[0] is claude/claude.exe and the argv carries the adjacent
    tokens ``--parent-session-id <sid>``. The Python copy of scripts/limit-recover/lr-team.sh
    (D4.1); tests/lr-team.bats pins the two equal. The old '@session-<sid8>' substring matched
    quoted prose and missed named teams."""
    toks = args.split()
    if not sid or not toks or os.path.basename(toks[0]) not in _CLAUDE_ARGV0:
        return False
    return any(
        toks[i] == "--parent-session-id" and toks[i + 1] == sid
        for i in range(1, len(toks) - 1)
    )


def live_members(sid: str, snap: T.Snapshot) -> int:
    """Live, non-zombie teammates of lead ``sid`` (see ``is_member_argv``)."""
    return sum(
        1 for r in snap.procs.values() if not r.zombie and is_member_argv(r.args, sid)
    )


def _distinct_holders(s: T.SessionObs) -> int:
    return len({(h.pid, h.lstart) for h in s.holders})


def _death(s: T.SessionObs) -> bool:
    last = s.transcript.last or {}
    return bool(last.get("limit")) and last.get("kind") == "limit"


def death_key(s: T.SessionObs) -> str:
    """uuid@ts of the death record the session sits on, or ''. A transplant copies it byte-for-byte
    and R appends nothing, so the SAME key on the target is the death this daemon already recovered.
    (uuid alone is not enough: the rig stub writes every limit with one fixture uuid.)"""
    last = s.transcript.last or {}
    return "%s@%s" % (last.get("uuid") or "", last.get("ts") or "") if _death(s) else ""


def handled_death(rec: Optional[T.Record], s: T.SessionObs) -> bool:
    """The session's current death is the one ``rec`` was opened to recover."""
    k = death_key(s)
    return bool(k) and rec is not None and rec.close.get("death") == k


def _lane(s: T.SessionObs) -> str:
    return "fable" if "fable" in (s.model or "").lower() else "general"


def _cover(s: T.SessionObs, facts: Dict[str, T.Fact], now: float) -> Optional[T.Fact]:
    return F.blocking(facts, s.acct, _lane(s), s.model, now) if s.acct else None


def _own_scope(s: T.SessionObs) -> Tuple[str, Optional[float]]:
    """The session's own death record decides its scope when no fact covers it yet."""
    last = s.transcript.last or {}
    scope = F.scope_of(last) or ""
    ra = last.get("resets_at")
    return scope, (float(ra) if isinstance(ra, (int, float)) else None)


def in_scope(s: T.SessionObs, facts: Dict[str, T.Fact], now: float) -> bool:
    return _death(s) or _cover(s, facts, now) is not None


def _mk(
    s: T.SessionObs,
    name: str,
    reason: str,
    kind: str,
    fact: Optional[T.Fact],
    detail: str = "",
) -> T.Bucket:
    scope, resets = (fact.scope, fact.resets_at) if fact else _own_scope(s)
    return T.Bucket(
        sid=s.sid,
        name=name,
        reason=reason,
        kind=kind,
        acct=s.acct,
        scope=scope,
        resets_at=resets,
        detail=detail,
    )


def bucket(
    s: T.SessionObs,
    snap: T.Snapshot,
    facts: Dict[str, T.Fact],
    now: float,
    env: Optional[Mapping[str, str]] = None,
) -> T.Bucket:
    """§3 step 5, checked in the order that makes each bucket exclusive."""
    env = os.environ if env is None else env
    fact = _cover(s, facts, now)
    kind = "limited" if _death(s) else "idle"
    if s.transcript.teammate:
        return _mk(s, "TEAMMATE", "lead-owned (invariant 1)", kind, fact)
    if _distinct_holders(s) > 1:
        return _mk(
            s, "SPLIT-BRAIN", "%d live holders" % _distinct_holders(s), kind, fact
        )
    if s.registry_name.startswith("iterm:"):
        return _mk(
            s, "HOLD:iterm", "iTerm2 pane: detached osascript fails 3/3", kind, fact
        )
    if not s.transcript.path:
        return _mk(s, "IMPOSSIBLE", "no-transcript", kind, fact)
    if s.cwd and not os.path.isdir(s.cwd):
        return _mk(s, "IMPOSSIBLE", "cwd-gone", kind, fact)
    if not s.pane and not s.registry_name:
        return _mk(s, "IMPOSSIBLE", "headless", kind, fact)
    if live_members(s.sid, snap) > 0:
        return _mk(
            s,
            "HELD:team",
            "lead with live members: hold; continued in place at reset (decision 4)",
            kind,
            fact,
        )
    pane = _pane(s, snap)
    focused = bool(pane and pane.is_focused)
    work = [b for b in s.bg_work if not b.watcher_only]
    if kind == "limited":
        if pane is not None and pane.root_shape == "launcher":
            return _mk(s, "LAUNCHER-ROOTED", "launcher-rooted pane ⇒ R", kind, fact)
        if focused and env.get("LR_MOVE_FOCUSED", "on") == "off":
            return _mk(
                s, "HOLD-FOCUS", "focused pane (LR_MOVE_FOCUSED=off)", kind, fact
            )
        if work:
            ship = any(b.ship_land for b in s.bg_work)
            return _mk(
                s,
                "HOLD-BGWORK",
                "background work (decision 2)",
                kind,
                fact,
                detail="ship-land" if ship else "",
            )
        resets = fact.resets_at if fact else _own_scope(s)[1]
        if resets is not None and resets - now < STAY_S:
            return _mk(s, "STAY", "source resets within 15 min", kind, fact)
        return _mk(s, "LIMITED", "last assistant record is the limit", kind, fact)
    return _idle(s, fact, focused, bool(s.bg_work), now, env)


def _idle(
    s: T.SessionObs,
    fact: Optional[T.Fact],
    focused: bool,
    any_bg: bool,
    now: float,
    env: Mapping[str, str],
) -> T.Bucket:
    """IDLE-ELIGIBLE needs every condition; optional work, so any doubt leaves it WORKING."""
    if env.get("LR_IDLE_FANOUT", "off") != "on" or fact is None:
        return _mk(s, "WORKING", "no idle fan-out", "idle", fact)
    if (
        fact.scope not in ("5h", "7d")
        or fact.contradicted
        or fact.resets_at is None
        or fact.resets_at - now < IDLE_MIN_LEFT_S
        or not s.transcript.at_rest
        or any_bg
        or focused
    ):
        return _mk(s, "WORKING", "idle move not eligible", "idle", fact)
    if s.transcript.live_subagents:
        return _mk(s, "HOLD-SUBAGENTS", "live subagents on an idle move", "idle", fact)
    if s.composer == "draft":
        return _mk(s, "HOLD-DRAFT", "operator draft in the composer", "idle", fact)
    if s.composer != "empty":
        return _mk(s, "WORKING", "composer not affirmatively empty", "idle", fact)
    return _mk(s, "IDLE-ELIGIBLE", "uncontradicted account-wide fact", "idle", fact)


def summary(buckets: List[T.Bucket]) -> Dict[str, int]:
    out: Dict[str, int] = {}
    for b in buckets:
        out[b.name] = out.get(b.name, 0) + 1
    return out


# ── cohorts, origins, records ───────────────────────────────────────────────────────────────────


def cohort_id(acct: str, scope: str, resets_at: Optional[float]) -> str:
    safe = (scope or "none").replace(":", "_").replace("/", "_")
    return "%s-%s-%d" % (acct or "unknown", safe, int(resets_at or 0))


def cohort_resets(cid: str) -> Optional[float]:
    """The reset a cohort id is keyed on (cohort_id's suffix); None for a cohort keyed on none."""
    tail = cid.rsplit("-", 1)[-1]
    return float(tail) if tail.isdigit() and int(tail) > 0 else None


def cohorts_for(buckets: List[T.Bucket], now: float) -> Dict[str, T.Cohort]:
    out: Dict[str, T.Cohort] = {}
    for b in buckets:
        cid = cohort_id(b.acct, b.scope, b.resets_at)
        c = out.setdefault(
            cid,
            T.Cohort(
                cid=cid,
                acct=b.acct,
                scope=b.scope,
                resets_at=b.resets_at,
                opened_at=now,
            ),
        )
        c.members.append(b.sid)
    return out


def origin_rank(o: str) -> int:
    return _ORIGIN_RANK.get(o, 0)


def merge_origin(rec: T.Record, new_origin: str, autorecover_on: bool) -> None:
    """Origin is the maximum seen; cc-lr is sticky and promotes PLAN-ONLY to acting (§C2)."""
    if origin_rank(new_origin) > origin_rank(rec.origin):
        rec.origin = new_origin
    rec.plan_only = not autorecover_on and rec.origin != "cc-lr"


_SUBSTATE = {"LIMITED": "DETECTED", "STAY": "WAIT_RESET", "IDLE-ELIGIBLE": "DETECTED"}


def new_record(
    b: T.Bucket,
    s: T.SessionObs,
    pane: Optional[T.PaneObs],
    cid: str,
    origin: str,
    autorecover_on: bool,
    now: float,
) -> T.Record:
    rec = T.Record(
        sid=s.sid,
        record_id=T.make_record_id(cid, s.sid, 1),
        kind=b.kind,
        lane=_lane(s),
        scope=b.scope,
        pane=s.pane,
        source_acct=s.acct,
        source_cfg=s.cfg,
        source_pid=s.pid,
        source_lstart=s.lstart,
        cwd=s.cwd,
        cohort_id=cid,
        origin=origin,
    )
    if pane is not None:
        rec.root_shape = pane.root_shape
        rec.identity = T.Identity(
            kitty_pid=pane.kitty_pid,
            kitty_lstart=pane.kitty_lstart,
            window_id=pane.window_id,
            tty=pane.tty,
            root_pid=pane.root_pid,
            root_lstart=pane.root_lstart,
        )
    rec.substate = _SUBSTATE.get(b.name, b.name)
    if b.name in T.MAX_AGE_S or b.name == "STAY":
        rec.wait = T.Wait(
            reason=rec.substate or b.name,
            since=now,
            max_age_s=T.MAX_AGE_S.get(b.name),
            eta=b.resets_at,
            detail=b.detail,
        )
    if b.kind == "limited":
        rec.close["death"] = death_key(
            s
        )  # which death this record recovers (handled_death)
    rec.timeline.detected = now
    rec.updated_at = now
    merge_origin(rec, origin, autorecover_on)
    return rec


def upsert(
    records: Dict[str, T.Record],
    b: T.Bucket,
    s: T.SessionObs,
    pane: Optional[T.PaneObs],
    origin: str,
    cid: str,
    autorecover_on: bool,
    now: float,
) -> Tuple[T.Record, bool]:
    """A request or census hit for a sid with an OPEN record updates it; never a second record."""
    rec = records.get(s.sid)
    if rec is not None and rec.open:
        merge_origin(rec, origin, autorecover_on)
        rec.updated_at = now
        # Nothing has moved yet, so the source is where the session is observed NOW. A record
        # created by a daemon that read a `next` row through the ~/.claude alias kept source_cfg
        # ~/.claude, and every move of it was refused before planning (W5b canary 1); the same
        # account's routable dir replaces it. Past PRE-MOVE, settle owns the source/target swap.
        if (
            rec.phase == "PRE-MOVE"
            and s.cfg
            and s.cfg != rec.source_cfg
            and (not s.acct or s.acct == rec.source_acct)
        ):
            rec.source_cfg = s.cfg
        return rec, False
    rec = new_record(b, s, pane, cid, origin, autorecover_on, now)
    records[s.sid] = rec
    return rec, True


def not_needed_record(
    sid: str,
    s: Optional[T.SessionObs],
    facts: Dict[str, T.Fact],
    origin: str,
    reason: str,
    now: float,
    stores: Sequence[str] = (),
    amap: Optional[Mapping[str, str]] = None,
) -> T.Record:
    """A terminal NOT_NEEDED member for a request the stale reconcile closed before any record
    existed (a dead session, a session live elsewhere): the cohort counts it, so the operator sees
    that the request was answered rather than silently dropped (W5 rig, stale-request fault)."""
    if s is None or not s.acct or not s.transcript.path:
        # A dead session has no live holder, so observe left cfg/acct/transcript empty: resolve
        # them from the store that holds its transcript, so the member joins its REAL cohort.
        _tp, _h, s = _in_store(sid, s, list(stores), amap)
    acct = s.acct if s else ""
    fact = _cover(s, facts, now) if s else None
    scope, resets = (
        (fact.scope, fact.resets_at) if fact else (_own_scope(s) if s else ("", None))
    )
    cid = cohort_id(acct, scope, resets)
    rec = T.Record(
        sid=sid,
        record_id=T.make_record_id(cid, sid, 1),
        scope=scope,
        source_acct=acct,
        source_cfg=s.cfg if s else "",
        cwd=s.cwd if s else "",
        cohort_id=cid,
        origin=origin,
    )
    rec.timeline.detected = now
    rec.updated_at = now
    rec.terminal = T.Terminal(
        outcome="NOT_NEEDED", proof="stale request: " + reason, at=now
    )
    return rec


# ── §3 step 3: stale reconcile ──────────────────────────────────────────────────────────────────


def _in_store(
    sid: str,
    s: Optional[T.SessionObs],
    order: Sequence[str],
    amap: Optional[Mapping[str, str]],
) -> Tuple[str, bool, Optional[T.SessionObs]]:
    """``transcript.locate`` over ``order`` (deduped, empties dropped). When it finds a live
    transcript ``s`` did not carry, also an obs with that store's cfg, account and transcript —
    what observe could not attach to a session with no live holder."""
    seen: List[str] = []
    for c in order:
        if c and c not in seen:
            seen.append(c)
    tp, handed = transcript.locate(seen, s.cwd if s else "", sid)
    if not tp or handed:
        return tp, handed, s
    cfg = os.path.dirname(os.path.dirname(os.path.dirname(tp)))
    base = s if s is not None else T.SessionObs(sid=sid)
    return (
        tp,
        False,
        dataclasses.replace(
            base,
            cfg=base.cfg or cfg,
            acct=base.acct or observe_rows.acct_of_cfg(cfg, dict(amap or {})),
            transcript=transcript.observe_transcript(tp),
        ),
    )


# TODO(W4): swap for lr-reset-poller.sh rq_stale_reason once it is extracted into lr-lib.sh.
def stale_reason(
    sid: str, s: Optional[T.SessionObs], transcript_path: str, handed_off: bool
) -> Optional[str]:
    """Same contract as the poller's drain-time ``rq_stale_reason`` (lr-reset-poller.sh:745):
    a reason when the request is STALE, None while it is still a limited, movable session."""
    if not transcript_path and not handed_off:
        return "no transcript for this sid in any account store"
    if handed_off:
        return "transplanted — the source transcript is tombstoned"
    if s is not None and s.transcript.path and not os.path.exists(s.transcript.path):
        return "the transcript is gone"
    if s is not None and s.transcript.teammate:
        return "a teammate — lead-owned, never a recovery target"
    if s is not None and not _death(s):
        return "no longer LIMITED — its last assistant record is not the limit"
    return None


def stale_reconcile(
    records: Dict[str, T.Record],
    requests: List[T.Request],
    snap: T.Snapshot,
    boottime: Optional[float],
    now: float,
    stores: Sequence[str] = (),
) -> List[Tuple[str, str, str]]:
    """Check every request and parked record against evidence before anything acts. ``stores``
    is every configured account dir: a sid with no transcript in its own store is looked up in
    all of them (a ``.handed-off`` tombstone counts as moving, never as absent)."""
    out: List[Tuple[str, str, str]] = []
    for req in requests:
        rec = records.get(req.sid)
        if (
            rec is not None
            and rec.open
            and (
                rec.timeline.planned
                or rec.phase != "PRE-MOVE"
                or rec.substate == "IN-FLIGHT"
            )
        ):
            # A move this daemon owns: its phase machine decides (§3 step 3, invariant 25 —
            # a source tombstone is not target-side evidence). The request retires once the
            # record is terminal.
            continue
        s = snap.sessions.get(req.sid)
        src = str(req.raw.get("config_dir") or req.raw.get("cfg") or "")
        tp = (s.transcript.path if s else "") or str(
            req.raw.get("transcript_path") or ""
        )
        handed = bool(tp) and os.path.exists(tp + ".handed-off")
        judged = s
        if not tp:
            order = [s.cfg if s else "", src] + list(stores)
            tp, handed, judged = _in_store(req.sid, s, order, None)
        elif s is not None and not s.transcript.path and not handed:
            judged = dataclasses.replace(
                s, transcript=transcript.observe_transcript(tp)
            )
        if (
            s is not None
            and src
            and s.cfg
            and os.path.realpath(s.cfg) != os.path.realpath(src)
            and s.holders
        ):
            out.append((req.sid, "NOT_NEEDED", "live on %s already" % s.cfg))
            continue
        why = stale_reason(req.sid, judged, tp, handed)
        if why:
            out.append((req.sid, "NOT_NEEDED", why))
        elif s is None or not s.holders:
            out.append((req.sid, "NOT_NEEDED", "dead-before-claim"))
    for sid, rec in records.items():
        born = rec.timeline.planned or rec.timeline.detected
        if rec.open and boottime and born and born < boottime and not parked(rec):
            park(rec, now)
            out.append((sid, "PARKED-REBOOT", "planned before kern.boottime"))
    return out


def parked(rec: T.Record) -> bool:
    """Parked with its own wait. An older daemon set the substate alone, which left a record with
    no wait (a §4.4 defect every pass) or with its old HOLD:iterm wait (paged hourly as that)."""
    return (
        rec.substate == "PARKED-REBOOT"
        and rec.wait is not None
        and rec.wait.reason == "PARKED-REBOOT"
    )


def park(rec: T.Record, now: float) -> None:
    """A plan made before kern.boottime opens no new window: boot-resume, which honours
    PARKED-REBOOT (boot-resume-launch.sh), is the one path that relaunches it. The census owns this
    state and the phase table defers to it (``__main__._derive``); re-derived, the dead pane read
    PANE-GONE/R and un-parked it every pass (W5b2 cd3bd860). PRE-MOVE, because a record parked in
    a moving phase kept its phantom seat; a named wait, so §4.4 reads it as owned."""
    rec.phase, rec.substate = "PRE-MOVE", "PARKED-REBOOT"
    rec.wait = T.Wait(
        reason="PARKED-REBOOT", since=now, detail="planned before kern.boottime"
    )
