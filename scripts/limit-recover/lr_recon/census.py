"""Census, step (b) of §3: every live session in an affected scope lands in EXACTLY one bucket.

Pure over a ``T.Snapshot`` + records + facts: no subprocess, no keystroke. Also the record
bookkeeping that follows from a bucket (cohorts, origins, the §C2 actuation gate) and the §3
step-3 stale reconcile that runs before anything acts.

A focused limited pane MOVES (decision 7, ruled 2026-09-30: move focused panes;
``LR_MOVE_FOCUSED=off`` is the kill switch that holds it as HOLD-FOCUS). Idle fan-out stays off
unless ``env`` says ``LR_IDLE_FANOUT=on``: the daemon passes __main__.fanout_env, which turns it on
for the operator's file recon/idle-fanout.on (D2a, read every pass; ``LR_IDLE_FANOUT=off`` still
wins), and nothing here reads os.environ for it when ``env`` is given. A team lead with live members is HELD:team, unconditionally in v1 (decision 4, ruled
2026-09-30: hold, then continue in place at the reset; a cross-account team move is v2).
Decision 2 is SETTLED: a pane with live background work holds until the job ends.
"""

from __future__ import annotations

import dataclasses
import datetime
import json
import os
from typing import Dict, List, Mapping, Optional, Sequence, Set, Tuple

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


Binding = Tuple[
    str, Optional[float]
]  # (scope, resets_at): what a bucket, record and cohort key on


def _binding(s: T.SessionObs, fact: Optional[T.Fact], now: float) -> Binding:
    """The scope and reset that END this session's block: the later of the covering fact
    (``F.blocking``, itself the latest-resetting fact on the account) and the session's own death
    record. The death record wins only when it names ANOTHER scope, with a reset that is known,
    has not passed, and is later than the fact's (or the fact has none). In the fact's own scope
    the fact already holds the latest reset any death named (``F.merge`` only raises it), and an
    auth fact has no reset to outlast, so it always binds. Taking the covering fact outright
    filed a session newly limited by a 5h cap (resets 09:40Z) under the 7d fact left from three
    days before (resets 09:00Z), in that older cohort, with a wake 40 minutes before its real
    reset (W7h, next4 2026-10-04)."""
    if fact is None:
        return _own_scope(s)
    scope, resets = _own_scope(s) if _death(s) else ("", None)
    if (
        # A contradicted auth fact is an account that served a turn since (a re-login), and nothing
        # in the daemon expires it (no wire read reaches F.expire), so it must not outrank a new
        # death's own reset: that death would join the auth cohort with no reset to wake at (W7i).
        (fact.scope != "auth" or fact.contradicted)
        and scope
        and scope != fact.scope
        and resets is not None
        and not resets + F.GRACE_S < now
        and (fact.resets_at is None or resets > fact.resets_at)
    ):
        return scope, resets
    return fact.scope, fact.resets_at


FANOUT_SCOPES = ("5h", "7d")


def fans_out(fact: Optional[T.Fact]) -> bool:
    """The only fact a session with no death of its own is a member on: an account-wide 5h/7d
    fact that is not contradicted (§3 step 5 IDLE-ELIGIBLE; §C4: "A contradicted fact blocks idle
    fan-out, which is optional work"). ``F.blocking`` returns an auth fact for as long as its file
    exists, and no wire read reaches ``F.expire``, so a re-logged-in account kept its auth fact,
    contradicted, for good. Every healthy session there was "covered", and one that showed two
    holders for a pass, or sat in iTerm2, became an idle member of the auth cohort: 19 members of
    next3-auth-0 by 2026-10-05, 14 more at the next kitty restart (W7i)."""
    return fact is not None and fact.scope in FANOUT_SCOPES and not fact.contradicted


def in_scope(s: T.SessionObs, facts: Dict[str, T.Fact], now: float) -> bool:
    return _death(s) or fans_out(_cover(s, facts, now))


def _mk(
    s: T.SessionObs,
    name: str,
    reason: str,
    kind: str,
    bind: Binding,
    detail: str = "",
) -> T.Bucket:
    scope, resets = bind
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
    bind = _binding(s, fact, now)
    kind = "limited" if _death(s) else "idle"
    if s.transcript.teammate:
        return _mk(s, "TEAMMATE", "lead-owned (invariant 1)", kind, bind)
    if kind == "idle" and not fans_out(fact):
        # Before the structural buckets: SPLIT-BRAIN and HOLD:iterm are record types, and a session
        # reaches here on a closed record of its own even when in_scope says no (W7i).
        return _mk(s, "WORKING", "no fact an idle session moves on", kind, bind)
    if _distinct_holders(s) > 1:
        return _mk(
            s, "SPLIT-BRAIN", "%d live holders" % _distinct_holders(s), kind, bind
        )
    if s.registry_name.startswith("iterm:"):
        return _mk(
            s, "HOLD:iterm", "iTerm2 pane: detached osascript fails 3/3", kind, bind
        )
    if not s.transcript.path:
        return _mk(s, "IMPOSSIBLE", "no-transcript", kind, bind)
    if s.cwd and not os.path.isdir(s.cwd):
        return _mk(s, "IMPOSSIBLE", "cwd-gone", kind, bind)
    if not s.pane and not s.registry_name:
        return _mk(s, "IMPOSSIBLE", "headless", kind, bind)
    if live_members(s.sid, snap) > 0:
        return _mk(
            s,
            "HELD:team",
            "lead with live members: hold; continued in place at reset (decision 4)",
            kind,
            bind,
        )
    pane = _pane(s, snap)
    focused = bool(pane and pane.is_focused)
    work = [b for b in s.bg_work if not b.watcher_only]
    if kind == "limited":
        # The holds and the stay rule come before LAUNCHER-ROOTED: R retires the pane, so a refusable
        # read goes first (invariant 3), and a source resetting inside 15 min is continued in place
        # on any pane (§5 stay rule). Checked first, a launcher-rooted session was never held (W7g).
        if focused and env.get("LR_MOVE_FOCUSED", "on") == "off":
            return _mk(
                s, "HOLD-FOCUS", "focused pane (LR_MOVE_FOCUSED=off)", kind, bind
            )
        ship = any(b.ship_land for b in s.bg_work)
        # A launcher-rooted pane is released too. Pane 12 was one (2026-10-13): R recycled it in
        # place and the watcher carried its job. Where R replaces the pane instead, the daemon's
        # own record of the jobs (__main__._record_jobs) is what survives.
        if work and (ship or not source_rejected(fact)):
            return _mk(
                s,
                "HOLD-BGWORK",
                "background work (decision 2)",
                kind,
                bind,
                detail="ship-land" if ship else "",
            )
        if s.composer == "draft":
            # §7.2 HOLD row: "foreign draft … No keystroke over a draft", and invariant 7. Before
            # STAY and the movers, since the wake and every move type into this composer. Only an
            # affirmative draft holds here: an unreadable composer ("unknown", or not read) stays
            # with the actuator's precheck, which tells a parked menu from a failed read (W7h).
            return _mk(s, "HOLD-DRAFT", "operator draft in the composer", kind, bind)
        resets = bind[1]
        if resets is not None and resets - now < STAY_S:
            return _mk(s, "STAY", "source resets within 15 min", kind, bind)
        if pane is not None and pane.root_shape == "launcher":
            return _mk(s, "LAUNCHER-ROOTED", "launcher-rooted pane ⇒ R", kind, bind)
        return _mk(s, "LIMITED", "last assistant record is the limit", kind, bind)
    any_bg = bool(s.bg_work) and (
        any(b.ship_land for b in s.bg_work) or not source_rejected(fact)
    )
    return _idle(s, fact, focused, any_bg, now, env)


def source_rejected(fact: Optional[T.Fact]) -> bool:
    """The account's own API said rejected for its 5h or 7d window, and no healthy turn has
    contradicted it. A session there cannot take a turn until the reset, so a background job is
    not a reason to keep it there: nothing the job produces can be used, and a job that never ends
    held its session for good (operator ruling 2026-10-13, superseding decision 2 for this case
    only). The jobs end with the exit, and the recycle watcher records each one and names them to
    the successor (handoff-fire.sh rcy_jobs_capture). A ship-land job still holds: a land killed
    between rebase and push costs more than the wait, and it ends by itself. ``F.blocking`` has
    already dropped a fact whose reset has passed."""
    return (
        fact is not None
        and fact.scope in FANOUT_SCOPES
        and fact.status == "rejected"
        and not fact.contradicted
    )


def _idle(
    s: T.SessionObs,
    fact: Optional[T.Fact],
    focused: bool,
    any_bg: bool,
    now: float,
    env: Mapping[str, str],
) -> T.Bucket:
    """IDLE-ELIGIBLE needs every condition; optional work, so any doubt leaves it WORKING."""
    bind = _binding(s, fact, now)
    if env.get("LR_IDLE_FANOUT", "off") != "on" or fact is None:
        return _mk(s, "WORKING", "no idle fan-out", "idle", bind)
    if (
        fact.scope not in ("5h", "7d")
        or fact.contradicted
        or fact.resets_at is None
        or fact.resets_at - now < IDLE_MIN_LEFT_S
        or not s.transcript.at_rest
        or any_bg
        or focused
    ):
        return _mk(s, "WORKING", "idle move not eligible", "idle", bind)
    if s.transcript.live_subagents:
        return _mk(s, "HOLD-SUBAGENTS", "live subagents on an idle move", "idle", bind)
    if s.composer == "draft":
        return _mk(s, "HOLD-DRAFT", "operator draft in the composer", "idle", bind)
    if s.composer != "empty":
        return _mk(s, "WORKING", "composer not affirmatively empty", "idle", bind)
    return _mk(s, "IDLE-ELIGIBLE", "uncontradicted account-wide fact", "idle", bind)


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


# LAUNCHER-ROOTED is a mover like LIMITED: placed by --place, then act.choose turns its move into R
# (§C8 R row). As its own substate it was never placed, and a record born with it had no wait (W7g).
_SUBSTATE = {
    "LIMITED": "DETECTED",
    "LAUNCHER-ROOTED": "DETECTED",
    "STAY": "WAIT_RESET",
    "IDLE-ELIGIBLE": "DETECTED",
}


def _bind(rec: T.Record, where: Optional[Tuple[int, int]], pane: T.PaneObs) -> None:
    rec.pane = where
    rec.root_shape = pane.root_shape
    rec.identity = T.Identity(
        kitty_pid=pane.kitty_pid,
        kitty_lstart=pane.kitty_lstart,
        window_id=pane.window_id,
        tty=pane.tty,
        root_pid=pane.root_pid,
        root_lstart=pane.root_lstart,
    )


def rebind_pane(rec: T.Record, s: T.SessionObs, snap: T.Snapshot) -> bool:
    """An open record born on a degraded kitty read has pane None and an empty identity, and
    nothing set them again: its pane evidence read "unknown" for life, so no row past row 8 could
    match and it stalled into RECON-DEFECT every pass (186452ed, born 04:05:46Z on 2026-10-10 at
    load ~400 in pane 168 of kitty 64211). The first healthy read binds them, but only through the
    record's own source holder (pid + lstart) sitting in that window: any other holder may be a
    relaunch in a different pane, which settle owns."""
    if not rec.open or rec.pane or not s.pane or not rec.source_pid:
        return False
    pane = _pane(s, snap)
    if pane is None:
        return False
    if not any(
        h.pid == rec.source_pid
        and h.lstart == rec.source_lstart
        and h.pane == s.pane
        and not h.bg
        for h in s.holders
    ):
        return False
    _bind(rec, s.pane, pane)
    return True


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
        _bind(rec, s.pane, pane)
    rec.substate = _SUBSTATE.get(b.name, b.name)
    if b.name in T.MAX_AGE_S or b.name == "STAY":
        rec.wait = T.Wait(
            reason=rec.substate or b.name,
            since=now,
            max_age_s=T.MAX_AGE_S.get(b.name),
            # a draft the census sees is released by the census, the pass it reads empty: with
            # an eta, settle.reprobe handed it to the plan as a mover at that time (W7h)
            eta=None if b.name == "HOLD-DRAFT" else b.resets_at,
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
        if rec.phase == "PRE-MOVE" and pane is not None:
            # act.replaces keys on the pane the session is in NOW; a hop can change it
            rec.root_shape = pane.root_shape
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
    scope, resets = _binding(s, _cover(s, facts, now), now) if s else ("", None)
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


def impossible_record(
    b: T.Bucket, s: T.SessionObs, cid: str, origin: str, now: float
) -> T.Record:
    """A terminal IMPOSSIBLE(reason) member for a LIMITED session the census cannot recover (§3
    step 5: "HEADLESS / CWD-GONE / NO-TRANSCRIPT: IMPOSSIBLE with the reason"; an immediate page).
    Without a record the session was in no cohort and no event named it: d425afab, limited at
    07:59:47Z on 2026-10-04 with a session row as its only holder (no pane, no registry row), sat
    56 minutes as IMPOSSIBLE/headless and read as a census miss (W7h defect 3). The death key
    makes it one record per death (``handled_death``)."""
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
    rec.close["death"] = death_key(s)
    rec.close["impossible"] = (
        b.reason
    )  # report pages these once per cohort, not per record
    rec.timeline.detected = now
    rec.updated_at = now
    rec.terminal = T.Terminal(outcome="IMPOSSIBLE", proof="census: " + b.reason, at=now)
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


def _store_key(cfg: str) -> str:
    """The PHYSICAL path of a store's projects/ — lr-lib.sh lr_store_key (one store, however spelled)."""
    return os.path.realpath(os.path.join(cfg.rstrip("/"), "projects"))


def _has_copy(cfg: str, sid: str) -> bool:
    return bool(transcript.in_projects(cfg, sid + ".jsonl"))


def successor_state(
    sid: str,
    src: str,
    s: Optional[T.SessionObs],
    env: Optional[Mapping[str, str]] = None,
) -> Optional[str]:
    """Who carries a session MOVED off ``src`` now — lr-lib.sh ``lr_successor_state`` over the census's
    own evidence (2026-10-10, docs/research/lr-stranded-husk-2026-10-10/ROOT-CAUSE.md): 186452ed's
    request was retired as 'tombstoned' while no successor ever started and its source pane still
    held it. Holder evidence is ``s.holders[].cfg`` (an empty cfg is unknown); session-row holders
    are not counted, as in the shell. Tokens: successor · husk · unknown · unmoved · none, and None
    for no durable move off ``src`` or ``LR_SUCCESSOR_GATE=off``. No ``in-flight``: the census has no
    handoffs log, and a recycle in flight is kept as a husk is. Parity with the shell predicate is
    pinned by tests/fixtures/lr-stale-parity/cases.json."""
    env = os.environ if env is None else env
    if not sid or not src or env.get("LR_SUCCESSOR_GATE", "on") == "off":
        return None
    skey = _store_key(src)
    ho = bool(transcript.in_projects(src, sid + ".jsonl.handed-off"))
    tomb, to = "", ""
    for f in transcript.in_projects(src, sid + ".HANDOFF.json"):
        try:
            with open(f) as fh:
                cand = str(json.load(fh).get("handed_off_to") or "")
        except (OSError, ValueError, AttributeError):
            continue
        if cand and _store_key(cand) != skey:
            tomb, to = f, cand
            break
    if not tomb or not _has_copy(to, sid):
        # No durable move the census can SEE: never moved, a mirror, a round trip, or a move known
        # only by its transplant lock (the census does not read locks; the shell does). Callers keep
        # today's read, which for a bare .handed-off is still 'tombstoned'.
        return None
    unk, src_holder, src_pane = False, False, False
    for h in s.holders if s is not None else []:
        if h.src == "session-row":
            continue
        if not h.cfg:
            unk = True
            continue
        if _store_key(h.cfg) != skey:
            return "successor"
        src_holder = True
        src_pane = src_pane or h.src == "registry" or h.pane is not None
    if unk:
        return "unknown"
    if not ho:
        try:
            with open(tomb) as fh:
                phase = str(json.load(fh).get("phase") or "")
        except (OSError, ValueError, AttributeError):
            phase = ""
        if phase == "admit" and os.path.exists(
            tomb[: -len(".HANDOFF.json")] + ".jsonl"
        ):
            return "unmoved"  # the inverse of hooks/handed-off-session-guard.sh: never retired
    if not src_holder or env.get("LR_HUSK_RETIRE", "on") == "off":
        return "none"
    return "husk" if src_pane else "unknown"


STRANDED_QUIET_S = (
    600.0  # h defect 5: N minutes with no new successor bytes (default 10)
)
_COPY_SLACK_S = 5.0


def stranded_tombstone(
    sid: str,
    src: str,
    s: Optional[T.SessionObs],
    now: float,
    quiet_s: Optional[float] = None,
    env: Optional[Mapping[str, str]] = None,
    amap: Optional[Mapping[str, str]] = None,
) -> Optional[Dict[str, str]]:
    """lr-wake h defect 5: a transplant whose relaunch never happened, as a first-class STRANDED
    state. 3e929a81 (2026-10-18 03:03Z): the next4→next3 transplant wrote ``<sid>.HANDOFF.json`` and
    renamed the next4 transcript ``.jsonl.handed-off``, the next3 successor never started (its copy
    stayed byte-identical, 4,040,651 bytes, mtime 02:56), and the old next4 process stayed in pane 23
    behind the handed-off guard for ~10 h while three dispatchers re-drove it.

    STRANDED = ``successor_state`` reads ``husk`` (tombstone, a copy on the target, the old process
    alive in a pane on ``src``, no holder on the target) AND the successor transcript has gained no
    bytes: its size is at most the tombstone's ``confirm_len`` (when recorded) and its mtime is no
    later than the tombstone, for ``quiet_s`` (LR_STRANDED_QUIET_S, default 600 s) since it.

    The remedy is the one that worked by hand, in the SAME pane: ``/exit`` (only with no background
    work and an empty composer), then ``lr-fire-resume.sh <target> <cwd> <sid>``. Never a recycle,
    never a new pane. Returns the remedy plan (sid, pane, src, target, target_acct, cwd, since,
    command) or None."""
    env = os.environ if env is None else env
    if successor_state(sid, src, s, env) != "husk" or s is None:
        return None
    if quiet_s is None:
        try:
            quiet_s = float(env.get("LR_STRANDED_QUIET_S", "") or STRANDED_QUIET_S)
        except ValueError:
            quiet_s = STRANDED_QUIET_S
    for tomb in transcript.in_projects(src, sid + ".HANDOFF.json"):
        try:
            with open(tomb) as fh:
                t = json.load(fh)
        except (OSError, ValueError):
            continue
        if not isinstance(t, dict):
            continue
        to = str(t.get("handed_off_to") or "")
        ts = _iso(t.get("ts"))
        if not to or ts is None or now - ts < quiet_s:
            continue
        succ = str(t.get("target_transcript") or "")
        if not succ or not os.path.exists(succ):
            hits = transcript.in_projects(to, sid + ".jsonl")
            succ = hits[0] if hits else ""
        try:
            st = os.stat(succ)
        except OSError:
            continue
        confirm = t.get("confirm_len")
        if (
            isinstance(confirm, int)
            and not isinstance(confirm, bool)
            and st.st_size > confirm
        ):
            return None  # the successor wrote: it ran
        if st.st_mtime > ts + _COPY_SLACK_S:
            return None
        pane = next(
            (
                h.pane
                for h in s.holders
                if not h.bg
                and h.pane is not None
                and h.cfg
                and _store_key(h.cfg) == _store_key(src)
            ),
            None,
        )
        acct = observe_rows.acct_of_cfg(to, dict(amap or {}))
        cwd = s.cwd or ""
        return {
            "sid": sid,
            "pane": "%d:%d" % pane if pane else "",
            "src": src,
            "target": to,
            "target_acct": acct,
            "cwd": cwd,
            "since": t.get("ts") or "",
            "command": "bash ~/.claude/scripts/limit-recover/lr-unstrand.sh --sid %s"
            % sid,
        }
    return None


def _iso(v: object) -> Optional[float]:
    if not isinstance(v, str) or not v:
        return None
    try:
        dt = datetime.datetime.fromisoformat(v.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return dt.timestamp()


# TODO(W4): swap for lr-reset-poller.sh rq_stale_reason once it is extracted into lr-lib.sh.
def stale_reason(
    sid: str,
    s: Optional[T.SessionObs],
    transcript_path: str,
    handed_off: bool,
    succ: Optional[str] = None,
) -> Optional[str]:
    """Same contract as the poller's drain-time ``rq_stale_reason`` (lr-reset-poller.sh):
    a reason when the request is STALE, None while it is still a limited, movable session.
    ``succ`` is ``successor_state``: a successor retires it, a husk or an unknown holder KEEPS it
    (the poller drives the husk), and an unmoved admit is judged as the session it still is."""
    if not transcript_path and not handed_off:
        return "no transcript for this sid in any account store"
    if succ == "successor":
        return "transplanted — a live successor holds it"
    if succ in ("husk", "unknown"):
        return None
    if succ == "unmoved":
        handed_off = False
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
    husk_sids: Optional[Set[str]] = None,
    env: Optional[Mapping[str, str]] = None,
) -> List[Tuple[str, str, str]]:
    """Check every request and parked record against evidence before anything acts. ``stores``
    is every configured account dir: a sid with no transcript in its own store is looked up in
    all of them (a ``.handed-off`` tombstone counts as moving, never as absent). A request over a
    STRANDED HUSK (``successor_state`` = husk) is kept, not retired, and its sid is added to
    ``husk_sids`` so the caller opens no competing record: the poller's husk recovery owns it."""
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
        succ = (
            successor_state(req.sid, tp.split("/projects/")[0], s, env) if tp else None
        )
        if succ == "husk" and husk_sids is not None:
            husk_sids.add(req.sid)
        why = stale_reason(req.sid, judged, tp, handed, succ)
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
