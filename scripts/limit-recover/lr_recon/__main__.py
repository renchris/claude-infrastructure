"""``python3 -m lr_recon`` — the reconciler daemon's main loop (§C2, §3, §4).

Modes (recon/mode; absent ⇒ observe): ``observe`` writes census and plan to recon/shadow/ and owns
nothing; ``plan`` records plans and pages; ``act`` also claims, charges and spawns — and only when
the operator's cutover file ``recon.on`` exists (act.may_actuate). ``--mode`` can only LOWER the
file's mode, never raise it. ``--once`` runs one pass and prints the census: the W3 proof.

Startup order (§C2): flock → load records (quarantine the corrupt) → re-stamp owned claims →
adopt live actuators by argv → heartbeat. The loop wakes within ~1 s of a new request, fact,
StopFailure marker or ctl file (a 1 s stat poll; the first unattended recovery lost 5 of its 6
minutes waiting for the legacy poller's next pass) and runs a full pass every 3 s while any record
is moving, 5 s while any is open, and on each 20 s timeout while DORMANT.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

from lr_recon import (
    act,
    census,
    classify,
    evidence,
    observe,
    plan,
    report,
    settle,
    store,
    transcript,
)
from lr_recon import facts as F
from lr_recon import types as T
from lr_recon.admit import Admission, BootSlots
from lr_recon.clock import Caffeinate, Clock, Heartbeat, shift_record

MOVING = ("TRANSPLANTED", "EXITING", "HUSK-RETIRED", "EXITED", "RELAUNCHED")
IN_FLIGHT_MAX_S = 600.0  # a relaunch gap longer than this is unowned (the watcher --await caps at 1200)
SENTINEL_S = 300.0  # §3 step 13: CLOSED after the 5-minute sentinel
ACTIVE_FAST_S, ACTIVE_S, DORMANT_S = 3.0, 5.0, 20.0
RESTART_PAGE_WINDOW_S = 600.0
C_GRACE_S = (
    60.0  # quiet time after the last live actuator/launcher/watcher before C may type
)
RECORD_TYPES = (
    "LIMITED",
    "STAY",
    "IDLE-ELIGIBLE",
    "HOLD-DRAFT",
    "HOLD-BGWORK",
    "HOLD-SUBAGENTS",
    "HOLD-FOCUS",
    "HOLD:iterm",
    "HELD:team",
    "LAUNCHER-ROOTED",
    "SPLIT-BRAIN",
)


def read_mode(paths: T.Paths, cap: Optional[str]) -> str:
    try:
        with open(paths.mode_file, encoding="utf-8") as fh:
            m = fh.read().strip()
    except OSError:
        m = "observe"
    m = m if m in T.MODES else "observe"
    if cap in T.MODES and T.MODES.index(cap) < T.MODES.index(m):
        m = cap
    return m


class Ctx:
    """Everything one daemon process holds across passes."""

    def __init__(self, paths: T.Paths, mode_cap: Optional[str], home: str) -> None:
        self.paths, self.mode_cap, self.home = paths, mode_cap, home
        self.clock = Clock()
        self.admission = Admission()
        self.boots = BootSlots()
        self.records: Dict[str, T.Record] = {}
        self.reporter: Optional[report.Reporter] = None
        self.actuations = 0
        self.degraded_streak = 0
        self.last_summary: Dict[str, Any] = {}
        self.rig_refused: set = set()
        self.actions: Dict[
            str, str
        ] = {}  # sid → the action this pass's derive_phase chose


def _alive(pid: int, lstart: str) -> bool:
    return bool(lstart) and store.proc_lstart(pid) == lstart


def _event(
    paths: T.Paths, ev: str, sid: str = "", rid: str = "", detail: str = ""
) -> None:
    store.append_event(
        paths, T.Event(t=time.time(), ev=ev, sid=sid, record_id=rid, detail=detail)
    )


def _accounts(home: str) -> List[str]:
    try:
        with open(
            os.path.join(home, ".claude", "accounts.json"), encoding="utf-8"
        ) as fh:
            data = json.load(fh)
        return [a["name"] for a in data.get("accounts", []) if a.get("name")]
    except (OSError, ValueError, KeyError, AttributeError):
        return []


def _amap(home: str) -> Dict[str, str]:
    """account name → its config dir, from accounts.json."""
    try:
        with open(
            os.path.join(home, ".claude", "accounts.json"), encoding="utf-8"
        ) as fh:
            return {
                a["name"]: os.path.normpath(os.path.expanduser(a["config_dir"]))
                for a in json.load(fh).get("accounts", [])
            }
    except (OSError, ValueError, KeyError, AttributeError):
        return {}


def _cfg_of(home: str) -> Any:
    amap = _amap(home)
    return lambda acct: amap.get(acct, "")


# ── one pass ────────────────────────────────────────────────────────────────────────────────────


def _facts(ctx: Ctx, snap: T.Snapshot, now: float) -> Dict[str, T.Fact]:
    """Step (a): census death rows add facts; expiry and contradiction from the census's turns."""
    paths = ctx.paths
    for s in snap.sessions.values():
        mv = ctx.records.get(s.sid)
        if (
            mv is not None
            and mv.open
            and mv.target_acct == s.acct
            and mv.timeline.submitted is None
        ):
            # a move's copied transcript ends in the SOURCE's death: read as the target's, it
            # blocked every freshly moved-to account until engagement (W5 rig, target-auth)
            continue
        if mv is not None and s.acct != mv.source_acct and census.handled_death(mv, s):
            # the SOURCE's death, still carried in the copied transcript once the move closed (R
            # never types): written as the target's, it was a false fact (W5 rig 80294ba4)
            continue
        f = (
            F.fact_from_death(s.acct, s.sid, s.transcript.last or {}, now, "census")
            if s.acct
            and (
                (s.transcript.last or {}).get("limit")
                # an auth cliff is an account fact too (scope "auth"): without it a TARGET-AUTH
                # hop had no evidence to move on and placement kept choosing the dead account
                or (s.transcript.last or {}).get("kind") == "auth_cliff"
            )
            else None
        )
        if f is not None:
            F.write_fact(paths, f)
    facts = F.load_facts(paths)
    turns = [
        (
            s.acct,
            s.model,
            "fable" if "fable" in (s.model or "").lower() else "general",
            s.transcript.last_assistant_ok_at,
        )
        for s in snap.sessions.values()
        if s.acct and s.transcript.last_assistant_ok_at
    ]
    for key in F.contradict(facts, turns):
        F.write_fact(paths, facts[key])
    gone = F.expire(facts, now, [], turns)
    F.reap(paths, gone)
    for k in gone:
        facts.pop(k, None)
    return facts


def _census(
    ctx: Ctx,
    snap: T.Snapshot,
    facts: Dict[str, T.Fact],
    reqs: List[T.Request],
    mode: str,
    now: float,
) -> Tuple[List[T.Bucket], List[Tuple[str, str, str]]]:
    paths = ctx.paths
    req_by_sid = {r.sid: r for r in reqs}
    # Every configured account store: a dead session has no live holder, so its own store is unknown
    # and the reconcile must look in all of them (the parameter existed; nothing passed it, W5 rig).
    amap = _amap(ctx.home)
    stores = list(amap.values())
    stale = census.stale_reconcile(
        ctx.records, reqs, snap, ctx.clock.boottime(), now, stores=stores
    )
    stale_sids = {sid for sid, verdict, _r in stale if verdict == "NOT_NEEDED"}
    for sid, verdict, reason in stale:
        _event(paths, "stale", sid, detail="%s %s" % (verdict, reason))
        if mode == "act" and sid in req_by_sid and verdict == "NOT_NEEDED":
            store.claim_request(paths, req_by_sid[sid], verdict, reason)
            if sid not in ctx.records:
                ctx.records[sid] = census.not_needed_record(
                    sid,
                    snap.sessions.get(sid),
                    facts,
                    req_by_sid[sid].origin,
                    reason,
                    now,
                    stores=stores,
                    amap=amap,
                )
    autorecover = os.path.exists(paths.autorecover_on)
    buckets: List[T.Bucket] = []
    for s in snap.sessions.values():
        if not (
            census.in_scope(s, facts, now)
            or s.sid in req_by_sid
            or s.sid in ctx.records
        ):
            continue
        old = ctx.records.get(s.sid)
        if old is not None and not old.open and census.handled_death(old, s):
            # the death this closed record already recovered, not a new one: R resumes without
            # typing, so the copied limit record stays last and re-opened the sid over its terminal
            # outcome (W5 rig 80294ba4: REPLACED-NEW-WINDOW overwritten by LAUNCHER-ROOTED)
            continue
        _read_composer(s, snap, facts, now)
        b = census.bucket(s, snap, facts, now)
        buckets.append(b)
        if b.name not in RECORD_TYPES or s.sid in stale_sids:
            continue
        req = req_by_sid.get(s.sid)
        origin = req.origin if req else ("fanout" if b.kind == "idle" else "census")
        pane = snap.panes.get("%d:%d" % s.pane) if s.pane else None
        if old is not None and old.open and not act.live_procs(old, snap):
            if settle.rebucket(old, b.name, now):
                _event(paths, "rebucket", s.sid, old.record_id, b.name)
        census.upsert(
            ctx.records,
            b,
            s,
            pane,
            origin,
            census.cohort_id(b.acct, b.scope, b.resets_at),
            autorecover,
            now,
        )
    return buckets, stale


def _read_composer(
    s: T.SessionObs, snap: T.Snapshot, facts: Dict[str, T.Fact], now: float
) -> None:
    """An idle fan-out candidate needs an affirmatively EMPTY composer (census._idle); nothing else
    ever reads it, so the one kitty read per pass is spent only there, and only with fan-out on."""
    if (
        os.environ.get("LR_IDLE_FANOUT", "off") != "on"
        or not s.pane
        or not s.transcript.at_rest
        or (s.transcript.last or {}).get("limit")
        or census._cover(s, facts, now) is None
    ):
        return
    pane = snap.panes.get("%d:%d" % s.pane)
    if pane is not None and pane.state == "claude":
        s.composer = observe.composer_state(pane.sock, pane.window_id)


def _rearm_inputs(rec: T.Record, snap: T.Snapshot) -> Dict[str, str]:
    """What an ESCALATED record re-arms on besides the 15-minute clock (§7.2): the pane's current
    root process and the session's holder set. Either changing means the world the escalation was
    judged in is gone."""
    pane = snap.panes.get("%d:%d" % rec.pane) if rec.pane else None
    s = snap.sessions.get(rec.sid)
    return {
        "pane": "%d:%s" % (pane.root_pid, pane.root_lstart) if pane else "gone",
        "holders": ",".join(
            sorted("%d:%s" % (h.pid, h.lstart) for h in (s.holders if s else []))
        ),
    }


def _derive(
    ctx: Ctx,
    snap: T.Snapshot,
    now: float,
    facts: Optional[Dict[str, T.Fact]] = None,
) -> None:
    """Level-triggered confirm (§3 step 10): the derived phase replaces the cached one."""
    for rec in ctx.records.values():
        if not rec.open:
            continue
        act.adopt(rec, snap)
        if rec.escalated:
            inputs = _rearm_inputs(rec, snap)
            prev = rec.close.get("rearm_inputs") or {}
            if classify.should_rearm(rec, now, inputs, prev):
                classify.rearm(rec, now)
                _event(
                    ctx.paths,
                    "rearm",
                    rec.sid,
                    rec.record_id,
                    "15 min or an input changed",
                )
            rec.close["rearm_inputs"] = inputs
        for pr, rc in settle.dead_actuators(act.prune_dead(rec, snap), act.EXIT_CODES):
            text = settle.tail(settle.actlog(ctx.paths, rec, pr.argv_hash))
            detail = settle.settle_exit(rec, pr, rc, text, now)
            if detail:
                _event(ctx.paths, "exit", rec.sid, rec.record_id, detail)
        if not rec.open:
            continue
        if settle.note_watcher_hold(ctx.home, rec, now):
            _event(ctx.paths, "hold", rec.sid, rec.record_id, rec.last_error.detail)
        if settle.reprobe(rec, now):
            _event(ctx.paths, "reprobe", rec.sid, rec.record_id, "hold re-probed")
        if settle.replaced_elsewhere(rec, snap, now):
            _event(ctx.paths, "replaced", rec.sid, rec.record_id, rec.terminal.proof)
            continue
        if settle.replacement_unproven(rec, now):
            _event(
                ctx.paths, "r-unproven", rec.sid, rec.record_id, rec.last_error.detail
            )
        settle.note_confirm(rec)
        un = settle.note_unconfirm(ctx.paths, rec, now)
        if un:
            _event(ctx.paths, "unconfirmed", rec.sid, rec.record_id, un)
        if settle.mark_in_flight(rec):
            _event(
                ctx.paths, "in-flight", rec.sid, rec.record_id, "transplant confirmed"
            )
        out = evidence.derive(
            ctx.paths,
            rec,
            snap,
            readiness=(lambda r: settle.readiness(ctx.home, r))
            if rec.kind == "idle"
            else evidence._no_readiness,
        )
        res = out["result"]
        ev = out["evidence"]
        assert isinstance(res, T.PhaseResult) and isinstance(ev, T.Evidence)
        if ev.token_record_offset is not None and ev.token_is_this_attempt:
            rec.timeline.submitted = (
                rec.timeline.submitted or now
            )  # rows 4 and 7 read it
        if act.live_procs(rec, snap) or ev.live_launcher or ev.live_watcher:
            rec.close["busy_at"] = now
        rec.phase = res.phase
        ctx.actions[rec.sid] = res.action
        _note_close(rec, res, snap, now)
        if res.phase != "PRE-MOVE" or res.substate == "HOLD-MENU":
            rec.substate = res.substate
        elif settle.mark_in_flight(
            rec
        ):  # this pass entered the relaunch gap: owned, not orphaned
            _event(ctx.paths, "in-flight", rec.sid, rec.record_id, "relaunch gap")
        if (
            rec.phase == "PRE-MOVE"
            and rec.substate == "IN-FLIGHT"
            and not ev.holders
            and not rec.escalated
            and now - (rec.timeline.confirmed or rec.updated_at or now)
            >= IN_FLIGHT_MAX_S
        ):
            # §4.4: a relaunch gap past its bound with no holder is a failure, not a flag. The
            # lr-fire-resume relay lives as long as its child, so live_launcher cannot bound it (W5
            # rig 0c95685d sat IN-FLIGHT, flagged every pass, nothing acting). It spawns nothing.
            detail = "IN-FLIGHT %ds with no holder for the sid" % IN_FLIGHT_MAX_S
            fp = classify.fingerprint(rec.phase, "DETERMINISTIC", "!! " + detail, 0, "")
            d = classify.apply_failure(rec, "DETERMINISTIC", fp, detail, now)
            _event(
                ctx.paths,
                "in-flight-expired",
                rec.sid,
                rec.record_id,
                "%s → %s" % (detail, d),
            )
        # after the substate write: a hop turns this record into a fresh PRE-MOVE/DETECTED
        src_auth = (facts or {}).get("%s.auth" % rec.source_acct)
        if (
            rec.close.get("hop") == "auth"
            and res.phase == "PRE-MOVE"
            and src_auth is not None
            and src_auth.contradicted
            and not act.live_procs(rec, snap)
        ):
            # the auth hop fired on a fact another session contradicted before this attempt
            # confirmed: the account serves, so undo the hop and re-engage in place (W5 rig r2
            # target-auth: A refused the dead evidence to ESCALATED)
            hop_assign = rec.assign_id or rec.record_id
            if settle.undo_hop(rec):
                plan.unassign(hop_assign)  # free the seat the hop was placed on
                if rec.escalated:
                    classify.rearm(rec, now)
                ctx.actions[rec.sid] = "C-retry"
                _event(
                    ctx.paths,
                    "unhop",
                    rec.sid,
                    rec.record_id,
                    "auth on %s contradicted before the move confirmed: re-engage in place"
                    % rec.target_acct,
                )
                continue
        auth = (facts or {}).get("%s.auth" % rec.target_acct)
        if res.phase == "TARGET-AUTH" and auth is not None and auth.contradicted:
            # another session served a healthy turn on that account since: it is proven to serve,
            # so re-engage in place (and A would refuse the contradicted fact as evidence anyway)
            ctx.actions[rec.sid] = "C-retry"
            continue
        if (
            res.phase in ("TARGET-LIMITED", "TARGET-AUTH")
            and not act.live_procs(rec, snap)
            # the previous move's watcher holds the pane lock: a hop now is DEFERRED into STRANDED
            and not ev.live_watcher
        ):
            why = "auth" if res.phase == "TARGET-AUTH" else "limit"
            old_target = rec.target_acct
            settle.new_attempt(rec, settle.target_holder(rec, snap), why, now)
            plan.unassign(rec.record_id)
            ctx.actions[rec.sid] = "plan"
            _event(
                ctx.paths,
                "hop",
                rec.sid,
                rec.record_id,
                "%s on %s: attempt %d moves FROM it"
                % (res.phase, old_target, rec.attempt),
            )
            continue
        if res.phase in ("ENGAGED", "MOVED"):
            if rec.sentinel_until is None:
                rec.sentinel_until = now + SENTINEL_S
                rec.timeline.engaged = rec.timeline.engaged or now
            elif now >= rec.sentinel_until:
                rec.terminal = T.Terminal(outcome="CLOSED", proof=res.reason, at=now)
        elif res.phase == "PANE-GONE" and res.substate == "NOT_NEEDED":
            rec.terminal = T.Terminal(
                outcome="NOT_NEEDED", proof="handed-to-resume-debt", at=now
            )


def _note_close(
    rec: T.Record, res: T.PhaseResult, snap: T.Snapshot, now: float
) -> None:
    """The cohort DoD's per-member evidence: every phase/substate passed through, and — once, at
    the first ENGAGED or MOVED — whether the holder is in the SAME window (the pane the record was
    detected in) and is this sid (same uuid: a holder under the target cfg in the sid's own row)."""
    seen = rec.close.setdefault("seen", [])
    for name in (res.phase, rec.substate or ""):
        if name and name not in seen:
            seen.append(name)
    if res.phase not in ("ENGAGED", "MOVED") or rec.close.get("via"):
        return
    s = snap.sessions.get(rec.sid)
    bound = [
        h
        for h in (s.holders if s else [])
        if not h.bg
        and h.pane is not None
        and rec.pane
        and tuple(h.pane) == tuple(rec.pane)
    ]
    rec.close.update(
        via=res.phase,
        at=now,
        pane=list(bound[0].pane) if bound else None,
        same_window=bool(bound),
        same_uuid=bool(bound) and settle_same_cfg(bound[0].cfg, rec.target_cfg),
    )
    rec.timeline.engaged = rec.timeline.engaged or now


def settle_same_cfg(a: str, b: str) -> bool:
    return bool(a and b) and os.path.realpath(a) == os.path.realpath(b)


def _plan(
    ctx: Ctx, snap: T.Snapshot, facts: Dict[str, T.Fact], mode: str, now: float
) -> int:
    paths, recs = ctx.paths, ctx.records
    mvs = plan.movers(list(recs.values()), snap, now)
    if not mvs:
        return 0
    kw = plan.kwork(snap, _accounts(ctx.home), now)
    placed: Dict[str, T.Placement] = {}
    for lane in ("general", "fable"):
        lane_mvs = [m for m in mvs if recs[m.sid].lane == lane]
        got, rc = plan.place(lane, lane_mvs, paths.facts, kw)
        if (
            rc == 3 and mode != "observe"
        ):  # a sweep hits the usage endpoint: never in shadow
            plan.start_fresh_sweep(paths, now)
        placed.update(got)
    if mode == "act":
        placed = {
            sid: p for sid, p in placed.items() if not recs[sid].plan_only or not p.acct
        }
    plan.apply(recs, placed, facts, _cfg_of(ctx.home), now)
    for cid in {recs[s].cohort_id for s in placed}:
        plan.write_plan(
            paths,
            mode,
            cid,
            {s: p for s, p in placed.items() if recs[s].cohort_id == cid},
            now,
        )
    return len(placed)


def _own_and_charge(ctx: Ctx, now: float) -> None:
    """act mode only: claims + owned/ + one --assign-many for everything holding a phantom."""
    me = T.RunClaimHolder(
        pid=os.getpid(), lstart=store.proc_lstart(os.getpid()), owner="lr-reconciler"
    )
    for rec in ctx.records.values():
        if (
            rec.open
            and not rec.plan_only
            and rec.substate == "PLANNED"
            and store.read_fence(ctx.paths, rec.sid) is None
        ):
            me.record_id = rec.record_id
            verdict = store.take_ownership(
                ctx.paths, rec, me, _alive, lambda pid: "", now
            )
            _event(ctx.paths, "own", rec.sid, rec.record_id, verdict)
    plan.assign_many(plan.phantom_rows(list(ctx.records.values())))


def _dispatch(ctx: Ctx, snap: T.Snapshot, mode: str, now: float) -> int:
    n = 0
    running = act.running_count(ctx.records, snap)
    wake_ok = ctx.clock.wake_guard_ok()
    for rec in sorted(
        ctx.records.values(),
        key=lambda r: (r.kind != "limited", r.timeline.detected or now),
    ):
        res = T.PhaseResult(
            phase=rec.phase,
            substate=rec.substate,
            action=ctx.actions.get(rec.sid, ""),
        )
        which = act.choose(res, rec)
        if which is None:
            continue
        if which == "C" and now - float(rec.close.get("busy_at", 0)) < C_GRACE_S:
            # The move's own launcher types the prompt, and its user record lands 1.6-11 s after
            # the Enter (W0) with re-sends up to 45 s: C only after that whole chain is quiet, or
            # it types a SECOND prompt into a session that already has one (W5 rig).
            continue
        ok, why = act.may_actuate(
            ctx.paths, mode, rec, which, snap, now, wake_ok, running, act.workers_cap()
        )
        if not ok:
            continue
        if (
            which in settle.MOVE_ACTUATORS
            and rec.close.get("move_attempt") == rec.attempt
        ):
            # ONE MOVE SPAWN PER ATTEMPT (the launch-log audit's invariant). A failed exit already
            # bumps the attempt; an exit with no code, or a phase change the move itself caused
            # (A's /exit closed the pane, so R rescues), did not, and R went out under A's attempt:
            # a double typer by the audit (W5 rig N=30, pane-closed-after-exit).
            rec.attempt += 1
        argv = _command(ctx, rec, which)
        if not argv:
            continue
        pane = snap.panes.get("%d:%d" % rec.pane) if rec.pane else None
        pid = act.spawn(
            ctx.paths,
            rec,
            which,
            argv,
            act.actuator_env(rec, ctx.paths, pane.sock if pane else ""),
            now,
        )
        if which in settle.MOVE_ACTUATORS:
            rec.close["move_attempt"] = rec.attempt
        if which in settle.MOVE_ACTUATORS + ("C", "C-retry"):
            store.append_launch(
                ctx.paths,
                "%d\t%s\trecon-%s\tspawn\tpid=%d\tattempt=%d\trecord=%s"
                % (now, rec.sid, which, pid, rec.attempt, rec.record_id),
            )
        running += 1
        n += 1
    return n


def _command(ctx: Ctx, rec: T.Record, which: str) -> List[str]:
    if which == "A":
        rec.submit_token = act.new_token()  # a fresh token per spawn of the move
        if (
            rec.close.get("hop") == "auth"
        ):  # TARGET-AUTH hop: the source's auth fact admits it
            return act.cmd_move(
                rec,
                os.path.join(ctx.paths.facts, "%s.auth.json" % rec.source_acct),
                voluntary=True,
            )
        return act.cmd_move(
            rec,
            os.path.join(ctx.paths.facts, "%s.%s.json" % (rec.source_acct, rec.scope)),
        )
    if which in ("A-husk", "B"):
        rec.bundle = rec.bundle or settle.bundle_launcher(ctx.home, rec)
        if not rec.bundle:
            # handoff-fire aborts on `--resume-launcher ""` before any gate: a certain DETERMINISTIC
            # failure, so WAIT for the move's bundle instead of spending the retry budget on it
            rec.next_eligible_at = time.time() + settle.WAIT_RETRY_S
            _event(
                ctx.paths,
                "no-launcher",
                rec.sid,
                rec.record_id,
                "%s waits: no bundle launcher" % which,
            )
            return []
    if which == "A-husk":
        return act.cmd_husk(rec)
    if which == "B":
        os.makedirs(ctx.paths.p("work"), exist_ok=True)
        ident = ctx.paths.p("work", rec.sid + ".identity.json")
        store.atomic_write_json(ident, T.to_dict(rec.identity))
        return act.cmd_relaunch_at_shell(rec, ident)
    if which == "UNCONFIRM":
        return act.cmd_transplant(rec, "unconfirm")
    if which == "R":
        return act.cmd_replace(rec)
    if which in ("C", "C-retry"):
        rec.submit_token = act.new_token()
        os.makedirs(ctx.paths.p("work"), exist_ok=True)
        payload = ctx.paths.p("work", rec.sid + ".prompt.txt")
        store.atomic_write_text(payload, act.continue_prompt(rec, rec.scope, "") + "\n")
        return act.cmd_engage(rec, payload)
    return []  # SPLIT needs a bg job id the census does not carry yet: it pages instead


def _report(ctx: Ctx, mode: str, now: float) -> None:
    rep = ctx.reporter or report.Reporter(
        ctx.paths, "observe" if mode == "observe" else mode
    )
    ctx.reporter = rep
    by_cid: Dict[str, List[T.Record]] = {}
    for r in ctx.records.values():
        by_cid.setdefault(r.cohort_id, []).append(r)
    for cid, recs in by_cid.items():
        r0 = recs[0]
        cohort = T.Cohort(
            cid=cid, acct=r0.source_acct, scope=r0.scope, members=[r.sid for r in recs]
        )
        try:
            rep.open_page(cohort, recs, {})
            rep.delta_page(cohort, recs)
            if all(not r.open for r in recs):
                rep.close_page(cohort, recs)
            for r in recs:
                rep.immediate_pages(cohort, r)
                rep.max_age_page(cohort, r)
            report.write_cohort(ctx.paths, cohort, recs, now)
        except Exception as e:  # a surface failure never stops the loop
            _event(ctx.paths, "report-error", detail=repr(e)[:200])
    try:
        # operator-readout.sh reads this one file instead of loading every record: a Stop hook
        # has a ~2-3 s budget and no python on its path. Empty file ⇒ nothing open ⇒ no line.
        store.atomic_write_text(
            ctx.paths.p("readout.line"),
            report.readout_line(ctx.paths, now, list(ctx.records.values())),
        )
    except Exception as e:
        _event(ctx.paths, "report-error", detail=repr(e)[:200])


REFIRE_SUFFIX = ".refire.json"


def _refire(ctx: Ctx, now: float) -> int:
    """The daemon side of ``cc-lr cohort refire`` (§C11): each ``ctl/<sid>.refire.json`` re-arms one
    OPEN member's budget through classify.rearm — the same entry point the 15-minute re-arm uses, so
    a refire can never grant more than the clock would — then moves to ``ctl/done/`` so neither the
    next pass nor a restart re-applies it. A sid with no open record is moved too, and logged."""
    try:
        names = sorted(
            n for n in os.listdir(ctx.paths.ctl) if n.endswith(REFIRE_SUFFIX)
        )
    except OSError:
        return 0
    done = os.path.join(ctx.paths.ctl, "done")
    n = 0
    for name in names:
        src = os.path.join(ctx.paths.ctl, name)
        sid, by = name[: -len(REFIRE_SUFFIX)], "?"
        try:
            with open(src, encoding="utf-8") as fh:
                doc = json.load(fh)
            sid, by = str(doc.get("sid") or sid), str(doc.get("by") or by)
        except (OSError, ValueError, AttributeError):
            pass  # a torn or foreign body still names its sid in the file name
        rec = ctx.records.get(sid)
        if rec is not None and rec.open:
            classify.rearm(rec, now)
            _event(ctx.paths, "refire", sid, rec.record_id, "by=%s" % by)
            n += 1
        else:
            _event(ctx.paths, "refire-unknown", sid, detail="by=%s" % by)
        try:
            os.makedirs(done, 0o700, exist_ok=True)
            os.replace(src, os.path.join(done, name))
        except OSError as e:
            _event(ctx.paths, "refire-error", sid, detail=repr(e)[:200])
    return n


def _invariant(ctx: Ctx, snap: T.Snapshot, now: Optional[float] = None) -> int:
    """§4.4: every non-terminal record has a live process, a next_eligible_at, or a named wait."""
    bad = 0
    for r in ctx.records.values():
        r.close.pop("defect", None)
        if (
            not r.open
            or r.phase == "PRE-MOVE"
            and r.substate in ("DETECTED", "PLANNED")
        ):
            continue
        # A confirmed move in its relaunch gap is owned by the phase table (rows 10-11 dispatch B or
        # R if the relaunch fails) — for a bounded time. Past IN_FLIGHT_MAX_S it is a defect again.
        if (
            r.phase == "PRE-MOVE"
            and r.substate == "IN-FLIGHT"
            and (now or time.time()) - (r.timeline.confirmed or r.updated_at or 0)
            < IN_FLIGHT_MAX_S
        ):
            continue
        if act.live_procs(r, snap) or r.next_eligible_at or (r.wait and r.wait.reason):
            continue
        if r.phase in ("ENGAGED", "MOVED"):
            continue
        if (
            r.phase in ("EXITING", "PRE-MOVE")
            and r.substate is None
            and (now or time.time()) - float(r.close.get("busy_at", 0)) < ACTIVE_FAST_S
        ):
            # this pass's derive saw the move's live watcher or launcher (busy_at): it is owned by
            # a process we did not adopt, not orphaned (W5 rig 0f71c0d5: a spurious EXITING/None page)
            continue
        r.close["defect"] = True
        bad += 1
        _event(
            ctx.paths,
            "RECON-DEFECT",
            r.sid,
            r.record_id,
            "%s/%s" % (r.phase, r.substate),
        )
    return bad


def run_pass(ctx: Ctx, force_observe: bool = False) -> Dict[str, Any]:
    paths = ctx.paths
    store.ensure_dirs(paths)  # cheap, and a wiped root must never crash the loop
    act.reap_children()  # before ps, so an exited actuator is gone AND its exit code is kept
    mode = "observe" if force_observe else read_mode(paths, ctx.mode_cap)
    now = time.time()
    # rig_keep: a sid the daemon holds a record for stays visible mid-move (observe._sessions)
    snap = observe.observe(
        paths,
        ctx.home,
        transcript_fn=transcript.observe,
        now=now,
        rig_keep=frozenset(ctx.records),
    )
    ctx.degraded_streak = ctx.degraded_streak + 1 if snap.degraded else 0
    for sid in (
        snap.rig_refused
    ):  # rig/canary mode: logged once per sid per process, never acted on
        if sid not in ctx.rig_refused:
            ctx.rig_refused.add(sid)
            if paths.canary:
                _event(paths, "canary-refuse", sid, detail="not in LR_RECON_CANARY")
            else:
                _event(
                    paths, "rig-refuse", sid, detail="no registry row carries rig:true"
                )
    facts = _facts(ctx, snap, now)
    reqs = store.list_requests(paths)
    buckets, stale = _census(ctx, snap, facts, reqs, mode, now)
    _derive(ctx, snap, now, facts)
    for rec in (
        ctx.records.values()
    ):  # the fold audit's evidence (plan § W5): cheap, never raises
        if evidence.fold_witness(paths, rec) == "fold":
            _event(paths, "fold-witness", rec.sid)
    # before planning, so a re-armed member is placed and dispatched this pass
    _refire(ctx, now)
    placed = _plan(ctx, snap, facts, mode, now)
    spawned = 0
    if mode == "act" and os.path.exists(paths.recon_on):
        _own_and_charge(ctx, now)
        spawned = _dispatch(ctx, snap, mode, now)
        ctx.actuations += spawned
    _report(ctx, mode, now)
    defects = _invariant(ctx, snap, now)
    for rec in ctx.records.values():
        store.save_record(paths, rec, now)
    act.reap_children()
    summary = {
        "mode": mode,
        "census": observe.census_line(snap),
        "buckets": census.summary(buckets),
        "open": sum(1 for r in ctx.records.values() if r.open),
        "stale": len(stale),
        "placed": placed,
        "actuations": spawned,
        "defects": defects,
        "degraded": list(snap.degraded),
        "facts": len(facts),
    }
    if mode == "observe":
        store.atomic_write_json(os.path.join(paths.shadow, "last-pass.json"), summary)
    ctx.last_summary = summary
    return summary


# ── the daemon ──────────────────────────────────────────────────────────────────────────────────


def _signature(paths: T.Paths, home: str) -> Tuple[Tuple[str, float, int], ...]:
    dirs = (
        paths.requests,
        paths.facts,
        paths.ctl,
        os.path.join(home, ".claude", "autonomy", "stop-failure"),
    )
    out = []
    for d in dirs:
        try:
            st = os.stat(d)
            out.append((d, st.st_mtime, len(os.listdir(d))))
        except OSError:
            out.append((d, 0.0, -1))
    return tuple(out)


def wait_for_change(
    paths: T.Paths, home: str, timeout: float, hb: Optional[Heartbeat]
) -> bool:
    """1 s stat poll of the wake dirs; returns True on a change, False on timeout."""
    sig = _signature(paths, home)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        time.sleep(1.0)
        if hb is not None:
            hb.advance()  # progress inside a wait: the loop is alive, just idle (§C2)
        if _signature(paths, home) != sig:
            return True
    return False


def _startup(ctx: Ctx) -> None:
    paths = ctx.paths

    def bad(path: str, reason: str) -> None:
        _event(paths, "quarantine", detail="%s %s" % (os.path.basename(path), reason))

    ctx.records = store.load_all(paths, bad)
    me = store.proc_lstart(os.getpid())
    for rec in ctx.records.values():
        claim = store.read_claim(paths, rec.sid)
        if rec.open and claim is not None and claim.record_id == rec.record_id:
            store.claim_restamp(paths, rec.sid, rec.record_id, os.getpid(), me)
    now = time.time()
    store.append_restart(paths, {"t": now, "pid": os.getpid(), "lstart": me})
    try:
        with open(paths.restarts, encoding="utf-8") as fh:
            recent = [json.loads(ln).get("t", 0) for ln in fh.readlines()[-3:]]
        if sum(1 for t in recent if now - float(t) < RESTART_PAGE_WINDOW_S) >= 2:
            _event(paths, "restart-loop", detail="second restart within 10 minutes")
    except (OSError, ValueError):
        pass


def daemon(ctx: Ctx) -> int:
    paths = ctx.paths
    store.ensure_dirs(paths)
    lockf = open(paths.lock, "a+")
    try:
        fcntl.flock(lockf.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print(
            "lr_recon: another reconciler holds %s — exiting" % paths.lock,
            file=sys.stderr,
        )
        return 0
    _startup(ctx)
    hb = Heartbeat(
        paths.heartbeat, os.getpid(), store.proc_lstart(os.getpid()), ctx.clock
    )
    hb.write_now()
    hb.start()
    caf = Caffeinate(os.getpid())
    try:
        while True:
            slept = ctx.clock.tick()
            if slept:
                for rec in ctx.records.values():
                    shift_record(rec, slept)
            summary = run_pass(ctx, force_observe=ctx.clock.take_observe_only())
            hb.advance()
            moving = any(
                r.open and r.phase in MOVING or r.substate == "PLANNED"
                for r in ctx.records.values()
            )
            caf.set_hold(moving)
            if moving:
                wait_for_change(paths, ctx.home, ACTIVE_FAST_S, hb)
            elif summary["open"]:
                wait_for_change(paths, ctx.home, ACTIVE_S, hb)
            else:
                wait_for_change(paths, ctx.home, DORMANT_S, hb)
    finally:
        caf.close()
        hb.stop()


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="lr_recon", description=__doc__.splitlines()[0])
    ap.add_argument(
        "--mode", choices=T.MODES, help="cap the mode (can only lower recon/mode)"
    )
    ap.add_argument(
        "--once", action="store_true", help="one pass, print the census, exit"
    )
    ap.add_argument("--root", help="reconciler state root (default LR_RECON_ROOT)")
    a = ap.parse_args(argv)
    paths = T.Paths.from_env(root=a.root)
    if paths.canary_in_live_root:
        print(
            "lr_recon: REFUSED — LR_RECON_CANARY is set and the root is the live reconciler's "
            "(%s); a canary runs in its own tree (default %s)"
            % (paths.root, os.path.join(paths.lr_root, T.CANARY_ROOT)),
            file=sys.stderr,
        )
        return 2
    if os.environ.get("LR_RECON_CANARY", "").strip() and not paths.canary:
        print(
            "lr_recon: REFUSED — LR_RECON_CANARY is set but names no session id",
            file=sys.stderr,
        )
        return 2
    ctx = Ctx(paths, a.mode, os.environ.get("HOME", os.path.expanduser("~")))
    if not a.once:
        return daemon(ctx)
    store.ensure_dirs(paths)
    ctx.records = store.load_all(paths, lambda p, r: None)
    s = run_pass(ctx)
    print(s["census"])
    print(
        "buckets: "
        + (", ".join("%s=%d" % kv for kv in sorted(s["buckets"].items())) or "none")
    )
    print(
        "records open: %d · stale requests: %d · placed: %d · facts: %d · defects: %d"
        % (s["open"], s["stale"], s["placed"], s["facts"], s["defects"])
    )
    print(
        "mode=%s actuations=%d recon.on=%s"
        % (
            s["mode"],
            s["actuations"],
            "present" if os.path.exists(paths.recon_on) else "absent",
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
