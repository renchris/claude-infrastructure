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
import calendar
import fcntl
import json
import os
import re
import signal
import subprocess
import sys
import time
from typing import Any, Callable, Dict, List, Mapping, Optional, Set, Tuple

from lr_recon import (
    act,
    admit,
    capped,
    census,
    clock,
    classify,
    evidence,
    observe,
    observe_rows,
    plan,
    report,
    settle,
    store,
    tokens,
    transcript,
)
from lr_recon import facts as F
from lr_recon import types as T
from lr_recon.admit import Admission, BootSlots, jitter_s

try:
    from lr_recon import band
except (
    ImportError
):  # a live layer advanced before install.sh linked the new file: run without it
    band = None  # type: ignore[assignment]
# B6, guarded wider than band: a new ~900-line module can fail its import under the deployment
# interpreter with a SyntaxError or NameError, not only ImportError, and an unguarded failure here
# crash-loops every restart. The daemon then runs without it and says so in one event.
_TELEMETRY_IMPORT_ERROR = ""
try:
    from lr_recon import telemetry
except Exception as _e:  # noqa: BLE001
    telemetry = None  # type: ignore[assignment]
    _TELEMETRY_IMPORT_ERROR = repr(_e)[:200]
from lr_recon.clock import (
    Caffeinate,
    Clock,
    Heartbeat,
    bind_child_hook,
    bind_step_hook,
    bind_steps,
    run_bounded,
    set_phase,
    shift_record,
    step,
)

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
        # One slot store with `cc-lr move` (admit.py BootSlots). Kill switch LR_BOOT_SLOTS_SHARED=off.
        self.boots = BootSlots(
            store=""
            if os.environ.get("LR_BOOT_SLOTS_SHARED", "on") == "off"
            else os.path.join(paths.lr_root, "locks", "swap-slots")
        )
        self.records: Dict[str, T.Record] = {}
        self.reporter: Optional[report.Reporter] = None
        self.actuations = 0
        self.degraded_streak = 0
        self.last_nclaude: Optional[int] = (
            None  # the last ps reading's claude count (W7a)
        )
        self.abstain_streak = 0
        self.last_summary: Dict[str, Any] = {}
        self.rig_refused: set = set()
        self.actions: Dict[
            str, str
        ] = {}  # sid → the action this pass's derive_phase chose
        # sid → substate before this pass's census (plan.keep_waits); lane → consecutive
        # transient --place non-answers
        self.pre_census: Dict[str, str] = {}
        self.place_misses: Dict[str, int] = {}
        self.band_paged = (
            False  # band.py: one page per daemon process when below priority 31
        )
        # kept across passes so each pass re-reads only the project dirs that changed
        # (transcript.ProjectsIndex): a fresh sweep was ~73,000 directory reads a pass
        self.projects = transcript.ProjectsIndex()
        # A6 (c): the claim keeper runs only in daemon(), after its flock — never in --once or a
        # test pass, which would stamp a process that exits seconds later (S-2)
        self.keeper = False
        # B6: only daemon() builds the writer (P3); --once and test passes leave it None and write
        # no telemetry. pass_seq counts every pass for the heartbeat even while telemetry is off.
        self.telem: Any = None
        self.pass_seq = 0
        self.slept = 0.0
        # B7 kill switch (recon/pass-clock), re-read every pass by read_pass_clock
        self.pass_clock = "wall"
        # C2 E5 T4: the last kitty-degraded event's key, so an outage writes one event, not one a pass
        self.kitty_degraded: Optional[str] = None
        # W9 (B2 stage 1) kill switches, re-read every pass by _w9_switches: the page outbox and the
        # per-pass caps (composer reads, sends, draft snapshots, claim argv reads, the assign memo)
        self.page_outbox = True
        self.pass_caps = True
        self.composer_gate: Optional[ComposerGate] = None
        self.composer_last: Dict[
            str, int
        ] = {}  # sid → pass_seq of its last composer read
        self.composer_want: List[
            str
        ] = []  # the sids that asked for a read last pass, in order
        # D2a: idle composer verdicts kept 60 s per session, at most 4 idle reads per pass
        self.idle_composer = IdleComposer()
        # --assign-many memo: re-assert only on a changed row set, a failed call, or every 120 s
        self.assign_key: Optional[Tuple[Tuple[str, str, int], ...]] = None
        self.assign_at = 0.0
        self.assign_rc = 0
        self.pass_mints = 0
        self.zombies: Dict[
            int, int
        ] = {}  # unregistered zombie child pid → consecutive passes seen
        self.orphans_paged = False
        self.pass_exc_streak = 0
        self.pass_exc_paged_at = 0.0
        # W11 (B3): the deadline's mode (recon/deadline.off|.shadow, re-read every pass), the lane's
        # occupancy (recounted at each dispatch, incremented per admission: never pass-scoped), the
        # slot-priority lease the move lane obeys, and the last pass's length that sizes it
        self.deadline = "on"
        self.deadline_used = 0
        self.deadline_per_acct: Dict[str, int] = {}
        self.slot_priority_want = ""
        self.slot_priority_at = 0.0
        self.last_pass_s = 0.0
        self.hard_paged: Optional[float] = None

    def wall(self) -> float:
        """B7 R2: the instant a decision or an action is taken (``now`` is the census instant).
        Under the kill switch it reads -inf, so every max(now, wall) is the pass ``now`` again."""
        return time.time() if self.pass_clock != "pass" else float("-inf")


PASS_CLOCK = "pass-clock"  # under recon/: `pass` turns B7's decision-time readings off


def read_pass_clock(paths: T.Paths) -> str:
    """``recon/pass-clock`` holding ``pass`` reverts B7's t_dec and wall pacer ("pass"); anything else,
    or no file, is "wall". It does NOT restore the old busy-stamp position (B7 review efficacy 4)."""
    try:
        with open(paths.p(PASS_CLOCK), encoding="utf-8") as fh:
            return "pass" if fh.read().strip() == "pass" else "wall"
    except OSError:
        return "wall"


def _own(ctx: Any, key: str, default: Any) -> Any:
    """An attribute the Ctx itself holds (never one a test's stand-in ctx manufactures)."""
    try:
        return vars(ctx).get(key, default)
    except TypeError:
        return default


def _tel(ctx: Ctx) -> Any:
    return _own(ctx, "telem", None)


def _ph(ctx: Ctx, name: str) -> None:
    """A phase mark: the heartbeat directly (true while telemetry is paused or off), then the
    writer's phase ledger."""
    set_phase(name, _own(ctx, "pass_seq", 0))
    tel = _tel(ctx)
    if tel is not None:
        tel.phase(name)


def _alive(pid: int, lstart: str) -> bool:
    """A claim holder is dead only on evidence: no such process, or another process's lstart. A
    read we could not make (our own ps timeout) keeps it alive — read as dead, it handed a live
    driver's claim to a second driver (W9, B2 review C8: the claim-steal split-brain)."""
    if not lstart:
        return False
    cur = store.proc_lstart(pid, unknown=store.UNKNOWN)
    return cur == store.UNKNOWN or cur == lstart


BOUNDED_PASS_OFF = (
    "bounded-pass.off"  # under recon/: subprocess.run and the waitpid(-1) reaper
)
INPROC_LSTART_OFF = "inproc-lstart.off"  # under recon/: lstart through ps only
PAGE_OUTBOX_OFF = "page-outbox.off"  # under recon/: pages sent inline as they latch
PASS_CAPS_OFF = (
    "pass-caps.off"  # under recon/: no composer, send, snapshot, argv or assign cap
)


def _w9_switches(ctx: Ctx) -> None:
    """W9's kill switches, re-read every pass (no reload)."""
    p = ctx.paths.p
    clock.BOUNDED_PASS = not os.path.exists(p(BOUNDED_PASS_OFF))
    store.INPROC_LSTART = not os.path.exists(p(INPROC_LSTART_OFF))
    ctx.page_outbox = not os.path.exists(p(PAGE_OUTBOX_OFF))
    ctx.pass_caps = not os.path.exists(p(PASS_CAPS_OFF))


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


def zero_human(paths: T.Paths) -> bool:
    """D1.9: the reconciler may act on a record nobody asked for (origin hook/census/fanout) only
    when BOTH autorecover.on and its own recon/autorecover.on exist. Separates its scope from the
    poller's hook lane, which answers to autorecover.on alone."""
    return os.path.exists(paths.autorecover_on) and os.path.exists(
        paths.recon_autorecover_on
    )


def fanout_env(paths: T.Paths) -> Mapping[str, str]:
    """D2a: the effective idle fan-out switch is ``LR_IDLE_FANOUT=on`` OR the operator's file
    recon/idle-fanout.on, whose absence keeps today's behaviour. An explicit LR_IDLE_FANOUT=off
    still wins (the hard kill). Computed once per pass (_census) and handed to census.bucket and
    _read_composer, which read nothing else."""
    if (
        os.path.exists(paths.idle_fanout_on)
        and os.environ.get("LR_IDLE_FANOUT", "") != "off"
    ):
        return dict(os.environ, LR_IDLE_FANOUT="on")
    return os.environ


def _census(
    ctx: Ctx,
    snap: T.Snapshot,
    facts: Dict[str, T.Fact],
    reqs: List[T.Request],
    mode: str,
    now: float,
) -> Tuple[List[T.Bucket], List[Tuple[str, str, str]]]:
    paths = ctx.paths
    # One request per sid, the highest origin: a hook <sid>.json sorts after the operator's
    # <sid>.cc-lr.json, so last-wins shadowed cc-lr and left the record plan_only (D2, 2026-10-11).
    req_by_sid: Dict[str, T.Request] = {}
    for r in reqs:
        cur = req_by_sid.get(r.sid)
        if cur is None or census.origin_rank(r.origin) >= census.origin_rank(
            cur.origin
        ):
            req_by_sid[r.sid] = r
    # Every configured account store: a dead session has no live holder, so its own store is unknown
    # and the reconcile must look in all of them (the parameter existed; nothing passed it, W5 rig).
    amap = _amap(ctx.home)
    stores = list(amap.values())
    # A stranded husk (moved, no successor runs, the source pane still holds it) is the poller's husk
    # recovery's to drive (2026-10-10, docs/research/lr-stranded-husk-2026-10-10/ROOT-CAUSE.md): its
    # request is kept, and this pass opens no record that would compete with that recovery.
    husk_sids: Set[str] = set()
    stale = census.stale_reconcile(
        ctx.records,
        reqs,
        snap,
        ctx.clock.boottime(),
        now,
        stores=stores,
        husk_sids=husk_sids,
    )
    stale_sids = {sid for sid, verdict, _r in stale if verdict == "NOT_NEEDED"}
    autorecover = zero_human(paths)
    env = fanout_env(paths)  # D2a: once per pass
    idle_reads = _own(ctx, "idle_composer", None)
    if idle_reads is not None:
        idle_reads.begin_pass(now, snap.sessions, _own(ctx, "pass_caps", True))
    for sid, verdict, reason in stale:
        _event(paths, "stale", sid, detail="%s %s" % (verdict, reason))
        req = req_by_sid.get(sid)
        # Claiming drains the request from the poller too, on a verdict the poller does not share:
        # only an ACTING reconciler (recon.on) may, and only for a request it may act on (D1.9).
        if (
            mode == "act"
            and req is not None
            and verdict == "NOT_NEEDED"
            and os.path.exists(paths.recon_on)
            and (autorecover or req.origin == "cc-lr")
        ):
            store.claim_request(paths, req_by_sid[sid], verdict, reason)
            old = ctx.records.get(sid)
            if (
                old is None
                # a cc-lr requester asked AFTER this sid's last record closed (it recovered
                # before the first pass): a fresh member carries the verdict to it (55dbe05de6e3)
                or (
                    _requester(req)[0]
                    and old.terminal is not None
                    and old.terminal.at < req.at
                )
            ):
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
    buckets: List[T.Bucket] = []
    for s in snap.sessions.values():
        step()
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
        if old is not None and census.rebind_pane(old, s, snap):
            # ahead of the bucket: a record whose session no longer buckets into a record type
            # never reaches upsert, and its pane evidence is read by this pass's derive
            _event(paths, "rebind", s.sid, old.record_id, "pane %d:%d" % tuple(s.pane))
        _read_composer(
            s,
            snap,
            facts,
            now,
            old,
            _own(ctx, "composer_gate", None),
            env=env,
            idle=idle_reads,
        )
        b = census.bucket(s, snap, facts, now, env=env)
        buckets.append(b)
        if (
            b.name == "IMPOSSIBLE"
            and b.kind == "limited"
            and s.sid not in stale_sids
            and s.sid not in husk_sids
            and (old is None or not old.open)
        ):
            # W7h defect 3: a limited session the census cannot recover is a cohort member with
            # a terminal outcome and a page, not a silent drop. An open record is left to its
            # phase machine (a pane gone mid-move is PANE-GONE's R, not this).
            req = req_by_sid.get(s.sid)
            cid = census.cohort_id(b.acct, b.scope, b.resets_at)
            rec = census.impossible_record(
                b, s, cid, req.origin if req else "census", now
            )
            ctx.records[s.sid] = rec
            _event(paths, "impossible", s.sid, rec.record_id, b.reason)
        if b.name not in RECORD_TYPES or s.sid in stale_sids or s.sid in husk_sids:
            continue
        if (
            b.name == "HELD:team"
            and b.kind != "limited"
            and (old is None or not old.open)
        ):
            # A lead with live members that is NOT limited is a working team, never a recovery: no
            # record. The W6d rig caught the case: a lead continued in place at its reset closed
            # IN-PLACE, and the next pass re-opened it as an idle HELD:team with no reset to wake at.
            continue
        req = req_by_sid.get(s.sid)
        origin = req.origin if req else ("fanout" if b.kind == "idle" else "census")
        pane = snap.panes.get("%d:%d" % s.pane) if s.pane else None
        if old is not None and old.open and not act.live_procs(old, snap):
            was, assign_id = old.substate, old.assign_id or old.record_id
            if settle.rebucket(old, b.name, now, b.resets_at):
                _event(paths, "rebucket", s.sid, old.record_id, b.name)
                if was == "PLANNED" and mode == "act":
                    plan.unassign(assign_id)  # HELD:team took it over: void its phantom
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
    for sid, req in req_by_sid.items():
        rq_sid, rq_pane = _requester(req)
        rec = ctx.records.get(sid)
        # an old closed record never picks up a newer request's requester
        if (
            rq_sid
            and rec is not None
            and (rec.open or (rec.terminal is not None and rec.terminal.at >= req.at))
        ):
            rec.requester_sid, rec.requester_pane = rq_sid, rq_pane
    return buckets, stale


_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_PANE_RE = re.compile(r"^[A-Za-z0-9._][A-Za-z0-9._-]*$")


def _requester(req: Optional[T.Request]) -> Tuple[str, str]:
    """(requester_sid, requester_pane) of a cc-lr request, '' for anything not well-formed: the
    sid is the mail address (decision 55dbe05de6e3), the pane only the same-pane guard."""
    if req is None or req.origin != "cc-lr":
        return "", ""
    rs, rp = req.raw.get("requester_sid"), req.raw.get("requester_pane")
    rs = rs.lower() if isinstance(rs, str) and _UUID_RE.match(rs.lower()) else ""
    rp = str(rp) if isinstance(rp, (str, int)) and _PANE_RE.match(str(rp)) else ""
    return rs, rp


WAKE_AFTER_S = (
    120.0  # past the source's stale live fact (resets_at + 60) and its cached row
)
WAKE_SUBSTATES = ("WAIT_RESET", "HELD:team")


def _wakes(ctx: Ctx, snap: T.Snapshot, facts: Dict[str, T.Fact], now: float) -> int:
    """The in-place reset wake (D1.11 WAIT_RESET and --place's stay, D4.9 HELD:team). At the reset
    + 120 s + the sid's jitter (the stay: at once), a limited session is continued in its OWN pane:
    no /exit, no relaunch, no other account. A fresh turn after the reset closes it as continued in
    place, in _derive (settle._in_place, the one owner of that close). The wake is paced per account (Admission.pace_wake); the focus gate, the composer read
    and the member re-check happen just before the keystroke (act.cmd_wake, may_actuate)."""
    n = 0
    for rec in ctx.records.values():
        w = rec.wait
        if (
            not rec.open
            or rec.phase != "PRE-MOVE"
            or rec.kind != "limited"
            or rec.substate not in WAKE_SUBSTATES
            or w is None
            or w.eta is None
        ):
            continue
        # A fresh turn after the wake closed it IN-PLACE in _derive (settle._in_place), before here.
        stay = w.detail == "stay"
        if now < w.eta + (0.0 if stay else WAKE_AFTER_S + jitter_s(rec.sid)):
            continue
        if rec.close.get("wake_failed") or rec.close.get("wake_eta") == w.eta:
            continue  # paged and never retyped, or typed and waiting for its turn
        if rec.substate == "HELD:team" and census.live_members(rec.sid, snap) == 0:
            continue  # the team is gone: the census releases it to an ordinary move
        f = facts.get("%s.%s" % (rec.source_acct, rec.scope))
        if (
            f is not None
            and not f.contradicted
            and (f.resets_at or 0) > now
            and not rec.close.get(
                "cohort_exit"
            )  # its proof already outranked that fact
        ):
            continue  # no headroom: the source is limited again, on a later reset
        pane = snap.panes.get("%d:%d" % rec.pane) if rec.pane else None
        tel = _tel(ctx)
        if pane is None or pane.state != "claude":
            if tel is not None:
                tel.gate("wake", "pane-unseen")
            continue
        ok, _why = ctx.admission.pace_wake(rec.sid, rec.source_acct, now)
        if not ok:
            dl = _own(ctx, "deadline", "off")
            if dl != "off" and admit.overdue(rec, now):
                # W11: a wake past due + W_wake skips the pacer (its slot is still charged)
                if dl == "shadow":
                    _deadline_shadow(ctx, rec, "wake", _why)
                else:
                    ctx.admission.pacer_take(
                        rec.sid, rec.source_acct, ctx.admission._t_dec(now)
                    )
                    _event(
                        ctx.paths,
                        "wake-deadline",
                        rec.sid,
                        rec.record_id,
                        "%s refused it; overdue since %s"
                        % (_why, report._hm(admit.deadline_of(rec))),
                    )
                    ok = True
        if not ok:
            if tel is not None:
                tel.gate("wake", _why)
            continue
        ctx.actions[rec.sid] = (
            "wake"  # marked typed (wake_eta) only once _dispatch spawns it
        )
        _event(ctx.paths, "wake", rec.sid, rec.record_id, rec.substate)
        n += 1
    return n


def _stranded(ctx: Ctx, snap: T.Snapshot, mode: str, now: float) -> int:
    """lr-wake h defect 5: every tombstoned session whose successor never started (census.
    stranded_tombstone) is a STRANDED state, recorded once (event ``stranded-tombstone``) and paged
    once with its one remedy: ``lr-unstrand.sh`` exits it in its OWN pane (refusing on background
    work or a non-empty composer) and resumes it on the target there. Nothing is typed from here:
    the remedy is one command, never a recycle and never a new pane."""
    amap = _amap(ctx.home)
    rep = ctx.reporter or report.Reporter(ctx.paths, mode)
    rep.mode = mode
    ctx.reporter = rep
    n = 0
    for s in snap.sessions.values():
        step()
        seen: Set[str] = set()
        for h in s.holders:
            if h.bg or not h.cfg or h.cfg in seen:
                continue
            seen.add(h.cfg)
            plan_ = census.stranded_tombstone(s.sid, h.cfg, s, now, amap=amap)
            if plan_ is None:
                continue
            n += 1
            text = (
                "STRANDED %s (pane %s): moved %s → %s at %s, the successor never started and the "
                "old process still sits in its pane. Remedy, same pane: %s"
                % (
                    s.sid[:8],
                    plan_["pane"] or "?",
                    observe_rows.acct_of_cfg(h.cfg, amap) or h.cfg,
                    plan_["target_acct"] or plan_["target"],
                    plan_["since"],
                    plan_["command"],
                )
            )
            if rep._once("stranded", s.sid + ":" + plan_["since"], "stranded", text):
                _event(ctx.paths, "stranded-tombstone", s.sid, "", text)
            break
    return n


PROVENANCE_EVERY_S = 3600.0


def provenance_check(act_file: Optional[str] = None) -> str:
    """The check's path in the CHECKOUT this package really lives in. The daemon runs from
    ~/.claude/scripts/limit-recover, a farm of per-file symlinks where scripts/checks/ is not
    deployed, so a path built from the import location named a file that does not exist and the
    hourly check never ran. realpath(act.py) is the checkout's own file."""
    real = os.path.realpath(act_file or act.__file__)
    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(real))))
    return os.path.join(repo, "scripts", "checks", "launchagent-provenance.sh")


def _provenance(paths: T.Paths, now: float) -> bool:
    """REPORT §5 Q9, the provenance half: once an hour, detached and self-bounded, the check that
    pages on a com.reso.* LaunchAgent no repository shipped (scripts/checks/launchagent-provenance.sh;
    the agent-installed drain ran 12 h unseen on 2026-10-18). It only reads and pages; it never loads
    or unloads anything. LR_RECON_PROVENANCE=off skips it."""
    if os.environ.get("LR_RECON_PROVENANCE", "on") == "off":
        return False
    stamp = paths.p("provenance.stamp")
    try:
        if now - os.stat(stamp).st_mtime < PROVENANCE_EVERY_S:
            return False
    except OSError:
        pass
    store.atomic_write_text(stamp, "%f\n" % now)
    check = provenance_check()
    if not os.path.isfile(check):
        return False
    try:
        clock.popen_detached(  # W9: registered, so reap_children collects it with no waitpid(-1)
            ["/bin/bash", check],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        return False
    return True


def _band(ctx: Ctx, now: float) -> None:
    """REPORT lever A1: log this daemon's own base priority once per pass to recon/band.log and
    page once per process if it is below 31 (band.py). LR_RECON_BAND_CHECK=off skips it."""
    if band is None or os.environ.get("LR_RECON_BAND_CHECK", "on") == "off":
        return
    rep = ctx.reporter or report.Reporter(ctx.paths, read_mode(ctx.paths, ctx.mode_cap))

    def page(text: str) -> None:
        _event(ctx.paths, "band-low", detail=text[:200])
        rep.daemon_page("BAND", text)

    ctx.band_paged = band.check(
        ctx.paths.p("band.log"), now, ctx.band_paged, page, store.append_bounded
    )


SNAP_TIMEOUT_S = 20
DRAFT_SNAPS_PER_PASS = 1


def snap_bin() -> str:
    """W6b's lr-composer-snapshot.sh (LR_COMPOSER_SNAP_BIN is the seam)."""
    return os.environ.get("LR_COMPOSER_SNAP_BIN") or os.path.join(
        act.SCRIPTS, "lib", "lr-composer-snapshot.sh"
    )


def _run_snap(args: List[str]) -> Tuple[int, str]:
    try:
        cp = run_bounded(
            ["/bin/bash", snap_bin()] + args,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=SNAP_TIMEOUT_S,
        )
    except (OSError, subprocess.TimeoutExpired):
        return 124, ""
    return cp.returncode, cp.stdout


def _draft_snapshots(ctx: Ctx, snap: T.Snapshot) -> int:
    """D6.7: once per attempt, a record held on an operator draft (HOLD-DRAFT) gets its pane's raw
    --ansi screen saved (lr-composer-snapshot.sh snap: a read, it types nothing) and the draft row
    kept, so the page can quote what the operator wrote. Draft stash stays off (decision 6): this
    snapshot is the only record of the draft. A failed read records nothing and says so.

    W9: at most DRAFT_SNAPS_PER_PASS snapshots a pass (each is 2 × 22 s at its bound); the rest are
    left untouched (no attempt stamp) and taken on later passes. recon/pass-caps.off lifts it."""
    n = tried = 0
    cap = DRAFT_SNAPS_PER_PASS if _own(ctx, "pass_caps", False) else None
    for rec in ctx.records.values():
        step()
        if not rec.open or rec.substate != "HOLD-DRAFT" or not rec.pane:
            continue
        if rec.close.get("draft_snap_attempt") == rec.attempt:
            continue
        if cap is not None and tried >= cap:
            tel = _tel(ctx)
            if tel is not None:
                tel.gate("draft", "pass-cap")
            continue
        tried += 1
        rec.close["draft_snap_attempt"] = rec.attempt
        pane = snap.panes.get("%d:%d" % rec.pane)
        rc, out = _run_snap(
            [
                "snap",
                str(rec.pane[1]),
                rec.sid,
                "HOLD-DRAFT",
                "--focused",
                "1" if pane is not None and pane.is_focused else "0",
                "--limited",
                "1" if rec.kind == "limited" else "0",
            ]
        )
        lines = [x for x in out.splitlines() if x.strip()]
        if rc != 0 or not lines:
            _event(ctx.paths, "draft-snap-none", rec.sid, rec.record_id, "rc=%d" % rc)
            continue
        rec.close["draft_snap"] = lines[-1]
        rc, rows = _run_snap(["row", lines[-1]])
        text = " / ".join(r.strip() for r in rows.splitlines() if r.strip())
        if rc == 0 and text:
            rec.close["draft_text"] = text[:300]
        _event(ctx.paths, "draft-snap", rec.sid, rec.record_id, lines[-1])
        n += 1
    return n


FOCUS_LEDGER_MAX = 4 * 1024 * 1024


def _focus_ledger(
    paths: T.Paths,
    snap: T.Snapshot,
    buckets: List[T.Bucket],
    mode: str,
    now: float,
) -> Optional[Dict[str, Any]]:
    """D7.5: one append-only row per pass that saw a LIMITED session — how many, and how many sat
    in the focused pane. Focus had never been logged (0 recycle-held-focused rows), and
    last-pass.json is overwritten every pass; this is the data the focused-pane move (decision 7)
    and its idle-time follow-up are judged on."""
    limited = [b for b in buckets if b.kind == "limited"]
    if not limited:
        return None
    focused = 0
    for b in limited:
        s = snap.sessions.get(b.sid)
        pane = snap.panes.get("%d:%d" % s.pane) if s and s.pane else None
        focused += bool(pane and pane.is_focused)
    row = {
        "t": now,
        "mode": mode,
        "limited": len(limited),
        "focused": focused,
        "held_focus": sum(1 for b in limited if b.name == "HOLD-FOCUS"),
    }
    try:
        os.makedirs(paths.shadow, exist_ok=True)
        store.append_bounded(
            os.path.join(paths.shadow, "focus.jsonl"),
            store.dumps(row),
            FOCUS_LEDGER_MAX,
        )
    except OSError as e:
        _event(paths, "focus-ledger-error", detail=repr(e)[:200])
    return row


# The substates in which a draft changes what the plan does with a LIMITED session: about to be
# placed, placed, or already held on the draft. A record waiting on its reset or held on something
# else is read once it becomes one of these, so a cohort waiting out a reset costs no kitty reads.
DRAFT_READ_SUBSTATES = (
    "DETECTED",
    "WAIT_SLOT",
    "WAIT_DATA",
    "WAIT_CAPACITY",
    "BACKOFF",
    "PLANNED",
    "HOLD-DRAFT",
)


def _reads_limited_composer(
    s: T.SessionObs, old: Optional[T.Record], snap: T.Snapshot
) -> bool:
    """W7h: a LIMITED session's composer is read before it is bucketed, when no record is open for
    it or its record is idle in PRE-MOVE in a substate a draft would change. Never while one of
    our actuators is live on it: its own /exit in the composer would read as a draft."""
    if not census._death(s):
        return False
    if old is None or not old.open:
        return True
    return (
        old.phase == "PRE-MOVE"
        and (old.substate or "") in DRAFT_READ_SUBSTATES
        and not act.live_procs(old, snap)
    )


COMPOSER_BUDGET_S = (
    20.0  # W9: composer reads one pass may spend (started while under it)
)
COMPOSER_READ_S = 7.0  # one read at its bound: kitten's 5 s plus the reap grace


class ComposerGate:
    """W9 (B2 review F-D 4a): the census's composer reads were one 7 s child per limited session, so
    n = 20 in a kitty stall put 140 s in the census alone. Per pass:

      * a per-socket breaker: after one read on a socket times out, the rest on it return "unknown"
        with no child — the bucket a timed-out read already gets (census.py "an unreadable
        composer ... stays with the actuator's precheck"), so it is never assumed empty;
      * a budget: a read starts only while the pass has spent < COMPOSER_BUDGET_S on reads (so
        ≤ budget + one read), and past it a read returns "unknown" with no child;
      * oldest-read-first rotation: a sid read more recently than a sid from last pass's queue that
        is still unserved this pass reserves COMPOSER_READ_S for each such older sid, so the
        census's fixed session order cannot starve the sessions behind the budget forever.

    ``capped`` False (recon/pass-caps.off) reads every composer, as before W9."""

    def __init__(
        self,
        seq: int,
        last: Dict[str, int],
        prev: List[str],
        capped: bool = True,
        budget_s: float = COMPOSER_BUDGET_S,
        mono: Optional[Callable[[], float]] = None,
    ) -> None:
        self.seq, self.last, self.prev, self.capped = seq, last, list(prev), capped
        self.budget_s = budget_s
        self.mono = mono if mono is not None else time.monotonic
        self.spent = 0.0
        self.broken: Set[str] = set()
        self.served: Set[str] = set()
        self.wanted: List[str] = []
        self.reads = self.skipped = 0

    def _reserved(self, sid: str) -> float:
        mine = self.last.get(sid, 0)
        older = sum(
            1
            for o in self.prev
            if o != sid and o not in self.served and self.last.get(o, 0) < mine
        )
        return older * COMPOSER_READ_S

    def read(self, sid: str, sock: str, window_id: int) -> str:
        self.wanted.append(sid)
        self.served.add(sid)
        if self.capped and (
            sock in self.broken or self.spent + self._reserved(sid) >= self.budget_s
        ):
            self.skipped += 1
            return "unknown"
        late: List[bool] = []

        def run(*a: Any, **kw: Any) -> Any:
            try:
                return run_bounded(*a, **kw)
            except subprocess.TimeoutExpired:
                late.append(True)
                raise

        t0 = self.mono()
        try:
            return observe.composer_state(sock, window_id, run=run)
        finally:
            self.spent += self.mono() - t0
            self.reads += 1
            self.last[sid] = self.seq
            if late:
                self.broken.add(sock)


def _composer(gate: Optional[ComposerGate], sid: str, pane: T.PaneObs) -> str:
    if gate is None:
        return observe.composer_state(pane.sock, pane.window_id)
    return gate.read(sid, pane.sock, pane.window_id)


IDLE_COMPOSER_TTL_S = (
    60.0  # D2a (E9): an idle composer verdict is reused this long per session
)
IDLE_COMPOSER_READS = 4  # D2a (D16, E9): idle composer reads one pass may start


class IdleComposer:
    """D2a (review D16, E9): with fan-out on, every at-rest session under a fact-covered account had
    its composer read on every pass (p50 6 s cadence) for the fact's median 10.5 h, focused and
    occupied panes included, each read up to 5 s on the pass. Now a session's verdict is kept
    IDLE_COMPOSER_TTL_S, and at most IDLE_COMPOSER_READS idle reads start per pass; the rest return
    no verdict, which census._idle reads as "not affirmatively empty" (WORKING), the safe side. Every
    read still goes through the pass's ComposerGate, so it stays inside W9's composer budget. A
    gate-skipped "unknown" is not kept (no read happened). Limited-session reads are not touched."""

    def __init__(
        self, ttl_s: float = IDLE_COMPOSER_TTL_S, per_pass: int = IDLE_COMPOSER_READS
    ) -> None:
        self.ttl_s, self.per_pass = ttl_s, per_pass
        self.seen: Dict[str, Tuple[float, str]] = {}
        self.reads = self.cached = self.capped = 0
        self.now = 0.0

    def begin_pass(
        self, now: float, live: Mapping[str, Any], capped: bool = True
    ) -> None:
        """``capped`` False (recon/pass-caps.off) lifts the per-pass cap, as for W9's caps."""
        self.now, self.reads = now, 0
        self.cached = self.capped = 0
        self.per_pass = IDLE_COMPOSER_READS if capped else 1 << 30
        for sid in [s for s in self.seen if s not in live]:
            del self.seen[sid]

    def read(self, sid: str, fn: Callable[[], str]) -> str:
        hit = self.seen.get(sid)
        if hit is not None and 0 <= self.now - hit[0] < self.ttl_s:
            self.cached += 1
            return hit[1]
        if self.reads >= self.per_pass:
            self.capped += 1
            return ""
        self.reads += 1
        v = fn()
        if v != "unknown":
            self.seen[sid] = (self.now, v)
        return v


def _read_composer(
    s: T.SessionObs,
    snap: T.Snapshot,
    facts: Dict[str, T.Fact],
    now: float,
    old: Optional[T.Record] = None,
    gate: Optional[ComposerGate] = None,
    env: Optional[Mapping[str, str]] = None,
    idle: Optional[IdleComposer] = None,
) -> None:
    """The one kitty read per session per pass, spent only where the answer decides a bucket: a
    LIMITED session that is or is about to be a mover (census.bucket holds a draft, W7h), and an
    idle fan-out candidate, which needs an affirmatively EMPTY composer (census._idle) and is read
    only with fan-out on (``env``: the pass's fanout_env). ``gate`` (the daemon's per-pass
    ComposerGate) bounds the reads; ``idle`` (D2a) keeps and caps the idle ones."""
    env = os.environ if env is None else env
    if s.pane and _reads_limited_composer(s, old, snap):
        pane = snap.panes.get("%d:%d" % s.pane)
        if pane is not None and pane.state == "claude":
            s.composer = _composer(gate, s.sid, pane)
        return
    if (
        env.get("LR_IDLE_FANOUT", "off") != "on"
        or not s.pane
        or not s.transcript.at_rest
        or (s.transcript.last or {}).get("limit")
        or census._cover(s, facts, now) is None
    ):
        return
    pane = snap.panes.get("%d:%d" % s.pane)
    if pane is not None and pane.state == "claude":
        if idle is None:
            s.composer = _composer(gate, s.sid, pane)
        else:
            s.composer = idle.read(s.sid, lambda: _composer(gate, s.sid, pane))


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
    usage: Optional[Dict[str, Dict[str, Any]]] = None,
) -> None:
    """Level-triggered confirm (§3 step 10): the derived phase replaces the cached one."""
    for rec in ctx.records.values():
        step()
        if not rec.open:
            continue
        act.adopt(rec, snap)
        _note_activity(ctx, rec, snap, now)
        _deadline_derive(ctx, rec, now)
        was, assign_id = rec.substate, rec.assign_id or rec.record_id
        proof = (
            ""
            if act.live_procs(rec, snap)
            else settle.engaged_elsewhere(rec, snap, now)
        )
        if proof:
            in_place = rec.close.get("via") == "IN-PLACE"
            if in_place and was == "PLANNED":
                plan.unassign(assign_id)  # answered before A ran: void its phantom seat
            ev = "engaged-in-place" if in_place else "engaged-elsewhere"
            _event(ctx.paths, ev, rec.sid, rec.record_id, proof)
            continue
        if not act.live_procs(rec, snap):
            why = settle.holder_gone(rec, snap, now) or settle.idle_unneeded(
                rec, facts, now
            )
            if why:
                _event(ctx.paths, "not-needed", rec.sid, rec.record_id, why)
                continue
            planned = rec.substate == "PLANNED"
            why, resume = settle.cohort_exit(rec, facts, usage, snap, now)
            if why:
                if planned:
                    plan.unassign(
                        assign_id
                    )  # its seat on the target is no longer wanted
                ev = "cohort-exit-resume" if resume else "not-needed"
                _event(ctx.paths, ev, rec.sid, rec.record_id, why)
                continue  # a resume is _wakes' (the stay), this same pass
        if rec.substate == "PARKED-REBOOT":
            continue  # the census owns the reboot park (census.park); the phase table defers
        if rec.escalated:
            inputs = _rearm_inputs(rec, snap)
            prev = rec.close.get("rearm_inputs") or {}
            if classify.should_rearm(rec, now, inputs, prev):
                n = int(rec.close.get("rearms", 0)) + 1
                if n > classify.REARM_CAP:
                    # D1.10: page (IMPOSSIBLE is an immediate page) and release the session to the
                    # other recovery paths, which defer to owned/<sid> for as long as it stands
                    rec.terminal = T.Terminal(
                        outcome="IMPOSSIBLE",
                        proof="escalated again after %d re-arms; released to the other "
                        "recovery paths" % classify.REARM_CAP,
                        at=now,
                    )
                    _event(ctx.paths, "rearm-cap", rec.sid, rec.record_id, str(n - 1))
                    continue
                rec.close["rearms"] = n
                classify.rearm(rec, now)
                _event(
                    ctx.paths,
                    "rearm",
                    rec.sid,
                    rec.record_id,
                    "15 min or an input changed",
                )
            rec.close["rearm_inputs"] = inputs
        # A6: the intent's nonce is read BEFORE prune_dead clears it — it is what tells this
        # spawn's exit from a stale one (S-5) — and an exit nothing carries is found first (S-9)
        want = rec.intent.nonce if rec.intent is not None else None
        orphan = act.intent_only_exit(ctx.paths, rec)
        dead = act.prune_dead(rec, snap)
        if orphan is not None:
            dead.append(orphan)
            rec.intent = None  # settled once; the wrapper is gone, the file says so
        for pr, rc in settle.dead_actuators(
            dead,
            act.EXIT_CODES,
            lambda p: act.read_exit(ctx.paths, p),
            act._SPAWNED,
            rec.procs,
            want,
        ):
            why = settle.superseded(pr, want, rec.procs)
            if why:
                _event(
                    ctx.paths,
                    "stale-exit",
                    rec.sid,
                    rec.record_id,
                    "%s pid=%d nonce=%s %s — not scored"
                    % (pr.argv_hash, pr.pid, pr.nonce, why),
                )
                continue
            log = settle.actlog(ctx.paths, rec, pr.argv_hash)
            text = settle.tail(log)
            detail = settle.settle_exit(rec, pr, rc, text, now)
            if detail:
                _event(ctx.paths, "exit", rec.sid, rec.record_id, detail)
            tel = _tel(ctx)
            if tel is not None:
                tel.act_exit(rec, pr, rc, detail or "", log)
        if not act.live_procs(rec, snap):
            detail = settle.rolled_back(ctx.paths, rec, now)
            if detail:
                _event(ctx.paths, "rolled-back", rec.sid, rec.record_id, detail)
            else:
                detail = settle.unknown_exit(ctx.paths, rec, now)  # W11 lever 10
                if detail:
                    _event(ctx.paths, "unknown-exit", rec.sid, rec.record_id, detail)
        if not rec.open:
            continue
        if settle.note_watcher_hold(ctx.home, rec, now):
            _event(ctx.paths, "hold", rec.sid, rec.record_id, rec.last_error.detail)
        if settle.reprobe(rec, now):
            _event(ctx.paths, "reprobe", rec.sid, rec.record_id, "hold re-probed")
        if settle.replaced_elsewhere(rec, snap, now):
            _event(ctx.paths, "replaced", rec.sid, rec.record_id, rec.terminal.proof)
            continue
        r_proof = settle.replaced_in_place(rec, snap)
        if r_proof:
            _event(ctx.paths, "r-in-place", rec.sid, rec.record_id, r_proof)
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
        rec.phase = res.phase
        ctx.actions[rec.sid] = res.action
        _note_close(rec, res, snap, now)
        if res.phase != "PRE-MOVE" or res.substate == "HOLD-MENU":
            rec.substate = res.substate
        elif settle.mark_in_flight(
            rec
        ):  # this pass entered the relaunch gap: owned, not orphaned
            _event(ctx.paths, "in-flight", rec.sid, rec.record_id, "relaunch gap")
        if rec.phase == "PRE-MOVE" and rec.substate == "IN-FLIGHT":
            # B7 D4: its own anchor, never updated_at (save_records rewrites that every pass, so an
            # unconfirmed record measured one pass gap and sat IN-FLIGHT silently). _invariant
            # pages on it; it feeds no DETERMINISTIC ladder (B7 review efficacy 3).
            rec.close.setdefault("in_flight_at", now)
        else:
            rec.close.pop("in_flight_at", None)
        if rec.substate == "UNPROMPTED":
            # C2 E5: the durable age of an owed continue, any phase (a deaf kitty leaves the record
            # PRE-MOVE with substate UNPROMPTED); MAX_AGE_S["UNPROMPTED"] pages on it
            rec.close.setdefault("unprompted_since", now)
        else:
            rec.close.pop("unprompted_since", None)
        if (
            rec.phase == "PRE-MOVE"
            and rec.substate == "IN-FLIGHT"
            and not ev.holders
            and not rec.escalated
            and rec.timeline.confirmed is not None
            and now - rec.timeline.confirmed >= IN_FLIGHT_MAX_S
            # never while this attempt's watcher or unsettled launcher lives: the watcher's own
            # --await runs to 1,200 s, so a 600 s verdict here was our timeout convicting it
            and settle.quiet_for(rec, "typer", now) >= 0
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


def _note_activity(ctx: Ctx, rec: T.Record, snap: T.Snapshot, now: float) -> None:
    """B7 R5: this census's sighting of the move's activity, stamped at the top of _derive's loop for
    EVERY open record, before any reader and before any early ``continue`` (holder_gone and
    rolled_back read busy; C's grace and the IN-FLIGHT anchor read typer). A skipped stamp left a
    first-unseen anchor reading "seen" forever (B7 review correctness 4).

    busy: an actuator, watcher or recorded launcher of the record, or an lr-fire-resume relay of THIS
    move (settle.move_relay_live). _invariant's ACTIVE_FAST_S skip reads the same stamp, so a record
    held only by the session's own long-lived relay is re-driven or paged, never silent.
    typer: something that may still type into the session. C's quiet grace reads typer, not busy: a
    launcher whose own verdict ended its typing is only the session's pty relay, and keying C on it
    held the owed continue for good."""
    first = _own(ctx, "pass_clock", "wall") != "pass"
    live = bool(act.live_procs(rec, snap))
    watcher = evidence.watcher_live(rec, snap)
    settle.note_seen(
        rec,
        "busy",
        live
        or watcher
        or evidence._role_live(rec, snap, "launcher", "fire_resume")
        or settle.move_relay_live(ctx.home, rec, snap, now),
        now,
        first_unseen=first,
    )
    settle.note_seen(
        rec,
        "typer",
        live
        or watcher
        or (
            evidence.launcher_live(rec, snap)
            and not settle.launcher_settled(ctx.home, rec, now)
        ),
        now,
        first_unseen=first,
    )
    rec.close.setdefault("typer_at", 0.0)


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
    mvs = plan.movers(list(recs.values()), snap, now, facts)
    if not mvs:
        return 0
    # B4 R1 (W10): on the loop thread, inside run_pass's pass_index, so the map is the kept
    # index's answer as of this pass's walk; recon/place-holds.off is re-read every pass
    t_h = time.monotonic()
    mvs = plan.with_holds(
        mvs, plan.holds_amap(), off=os.path.exists(paths.p(plan.PLACE_HOLDS_OFF))
    )
    holds_s = time.monotonic() - t_h
    kw = plan.kwork(snap, _accounts(ctx.home), now)
    placed: Dict[str, T.Placement] = {}
    for lane in ("general", "fable"):
        step()
        lane_mvs = [m for m in mvs if recs[m.sid].lane == lane]
        if not lane_mvs:
            continue
        load1 = os.getloadavg()[0]
        timeout = plan.place_timeout(load1, os.cpu_count() or 1)
        t0 = time.monotonic()
        got, rc = plan.place(lane, lane_mvs, paths.facts, kw, timeout=timeout)
        dur = time.monotonic() - t0
        misses = ctx.place_misses.get(lane, 0) + 1 if rc in plan.TRANSIENT_RC else 0
        ctx.place_misses[lane] = misses
        n_got = len(got)
        got = plan.keep_waits(got, ctx.pre_census, rc, misses)
        _event(
            paths,
            "place",
            detail="lane=%s rc=%d cause=%s n=%d kept=%d misses=%d dur=%.1fs timeout=%.0fs "
            "load1=%.0f holds=%d/%d holds_s=%.2f"
            % (
                lane,
                rc,
                plan.PLACE_CAUSE.get(rc, "exit"),
                len(lane_mvs),
                n_got - len(got),
                misses,
                dur,
                timeout,
                load1,
                sum(1 for m in lane_mvs if m.holds is not None),
                len(lane_mvs),
                holds_s,
            ),
        )
        tel = _tel(ctx)
        if rc != 0 and tel is not None:
            tel.gate("place", plan.PLACE_CAUSE.get(rc, "exit"))
        if (
            rc == 3 and mode != "observe"
        ):  # a sweep hits the usage endpoint: never in shadow
            plan.start_fresh_sweep(paths, now, popen=clock.popen_detached)
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
        pid=os.getpid(), lstart=store.self_lstart(), owner="lr-reconciler"
    )  # W9: one in-process read per process, not a ps every act pass
    for rec in ctx.records.values():
        step()
        if not rec.open or rec.plan_only or rec.substate != "PLANNED":
            continue
        fence = store.read_fence(ctx.paths, rec.sid)
        if fence is not None and fence.record_id != rec.record_id:
            # D1.10: owned/<sid> left by an earlier record of this sid. A sid has at most one open
            # record, so that one is terminal: its fence and claim are stale, not a live owner.
            store.release_fence(ctx.paths, rec.sid, fence.record_id)
            store.claim_release(ctx.paths, rec.sid, fence.record_id)
            _event(ctx.paths, "own-takeover", rec.sid, rec.record_id, fence.record_id)
            fence = None
        if fence is None:
            me.record_id = rec.record_id
            verdict = store.take_ownership(
                ctx.paths, rec, me, _alive, lambda pid: "", now
            )
            _event(ctx.paths, "own", rec.sid, rec.record_id, verdict)
    step()
    rows = plan.phantom_rows(list(ctx.records.values()))
    # W9 (B2 F6): --assign-many ran every pass while any phantom lived — a claude-accounts start
    # each 3-5 s re-asserting unchanged rows with a 1200 s TTL. Now only on a changed row set (a
    # new placement is charged in its own pass: invariant 16), after a failed call, or every
    # ASSIGN_REFRESH_S (a 10x margin on the TTL). A restart's empty memo assigns at once.
    key = tuple(sorted((str(r["acct"]), str(r["id"]), int(r["w"])) for r in rows))
    wall = time.time()
    if (
        not _own(ctx, "pass_caps", False)
        or key != ctx.assign_key
        or ctx.assign_rc != 0
        or wall - ctx.assign_at >= ASSIGN_REFRESH_S
    ):
        ctx.assign_rc = plan.assign_many(rows)
        ctx.assign_key, ctx.assign_at = key, wall


ASSIGN_REFRESH_S = 120.0


FIRST_TURN = settle.MOVE_ACTUATORS + ("C", "C-retry")
MINTS_PER_PASS = (
    6  # admit.PACE_BURST: the most first-turn tokens one pass may mint (W9)
)


def _active_now(snap: T.Snapshot) -> int:
    """The live mid-turn sessions (cc_sp_active's meaning): held and not at rest."""
    return sum(
        1 for s in snap.sessions.values() if s.holders and not s.transcript.at_rest
    )


def _ceiling() -> int:
    try:
        return max(0, int(os.environ.get("CC_ADMIT_ACTIVE_CEILING", "8")))
    except ValueError:
        return 8


def _admission_period(ctx: Ctx, snap: T.Snapshot, now: float) -> None:
    """ACTIVE while any limited record is open: R and L_open freeze on entry (§C6 gate 1-2). Pacer
    slots free on ENGAGED or a closed record; a boot slot frees once no relaunching actuator of its
    record is alive."""
    adm = ctx.admission
    corpses = [r for r in ctx.records.values() if r.open and r.kind == "limited"]
    if not corpses:
        adm.leave_active()
    else:
        l1, l5, _l15 = os.getloadavg()
        adm.enter_active(
            _active_now(snap),
            len(corpses),
            _ceiling(),
            l1,
            l5,
            os.cpu_count() or 1,
            now,
        )
    for r in ctx.records.values():
        if not r.open or r.phase in ("ENGAGED", "MOVED"):
            adm.pacer_release(r.sid)
    for sid in list(ctx.boots.held):
        r = ctx.records.get(sid)
        if r is None or not any(
            p.argv_hash in act.BOOTING for p in act.live_procs(r, snap)
        ):
            ctx.boots.release(sid)


# ── W11 (B3): the per-record deadline's wiring ──────────────────────────────────────────────────
def _deadline_derive(ctx: Ctx, rec: T.Record, now: float) -> None:
    """Every open limited record: set its deadline once, rebase it on leaving a reset wait, and
    note the first pass it is overdue (event ``overdue``). Never raises (F-B)."""
    try:
        if rec.kind != "limited":
            return
        admit.ensure_deadline(rec)
        if admit.sync_deadline(rec):
            _event(
                ctx.paths,
                "deadline-rebased",
                rec.sid,
                rec.record_id,
                "left its reset wait: deadline %s" % report._hm(rec.deadline_at),
            )
        if "overdue_at" not in rec.close and admit.overdue(rec, now):
            rec.close["overdue_at"] = now
            d = admit.deadline_of(rec) or now
            _event(
                ctx.paths,
                "overdue",
                rec.sid,
                rec.record_id,
                "lane=%s age=%ds substate=%s deadline=%s"
                % (
                    rec.lane,
                    int(now - (rec.timeline.detected or d)),
                    rec.substate,
                    report._hm(d),
                ),
            )
    except Exception as e:  # noqa: BLE001 — a deadline bug must never strand every record
        _event(ctx.paths, "deadline-error", rec.sid, rec.record_id, repr(e)[:200])


def _deadline_lane(ctx: Ctx, now: float) -> None:
    """Lever 3 (correctness F-A): the lane is deadline-admitted first turns that are submitted, not
    yet ENGAGED, and admitted <= T_att ago. Not live processes: a C exits ~24 s after submitting,
    so counting live actuators admitted 6 first turns a pass onto one account. Recounted once per
    dispatch from the records, then incremented per admission (never pass-scoped, B7 class)."""
    used, per = 0, {}  # type: Tuple[int, Dict[str, int]]
    for r in ctx.records.values():
        at = r.close.get("deadline_admitted_at")
        if not r.open or at is None or r.phase in ("ENGAGED", "MOVED"):
            continue
        try:
            if now - float(at) > admit.T_ATT_S:
                continue  # D7: a first turn that never ENGAGES leaves the lane after T_att
        except (TypeError, ValueError):
            continue
        used += 1
        a = str(r.close.get("deadline_acct") or r.target_acct or r.source_acct)
        per[a] = per.get(a, 0) + 1
    ctx.deadline_used, ctx.deadline_per_acct = used, per


def _deadline_room(ctx: Ctx, rec: T.Record) -> str:
    """'' = room in the lane for this record's first turn, else the reason it has none."""
    acct = rec.target_acct or rec.source_acct
    if _own(ctx, "deadline_used", 0) >= admit.DEADLINE_WIDTH:
        return "deadline-lane"
    if _own(ctx, "deadline_per_acct", {}).get(acct, 0) >= admit.DEADLINE_PER_ACCT:
        return "deadline-acct:%s" % acct
    return ""


def _deadline_note(ctx: Ctx, rec: T.Record, why: str, now: float) -> None:
    """An overdue record held this pass: its blocker in close.deadline_hold (the DEADLINE page
    names it) and a ``deadline-held`` event on change, like admit-refused."""
    if rec.close.get("deadline_hold") != why:
        rec.close["deadline_hold"] = why
        _event(
            ctx.paths,
            "deadline-held",
            rec.sid,
            rec.record_id,
            "%s (overdue %ds)" % (why, int(now - (admit.deadline_of(rec) or now))),
        )


def _deadline_shadow(ctx: Ctx, rec: T.Record, would: str, actual: str) -> None:
    """recon/deadline.shadow: log the would-admit once per record per attempt, change nothing."""
    key = "%s:%d" % (would, rec.attempt)
    if rec.close.get("deadline_shadow") != key:
        rec.close["deadline_shadow"] = key
        _event(
            ctx.paths,
            "deadline-shadow",
            rec.sid,
            rec.record_id,
            "would admit (%s); actual: %s" % (would, actual),
        )


def _slot_priority(ctx: Ctx) -> None:
    """Lever 4: while an overdue A/R record waits on boot slots, keep lr_root/locks/slot-priority
    leased (until = now + max(180 s, 2 × the last pass)); lr-move-lib.sh caps the move lane at one
    slot while it stands. Nothing waits: remove our own file at once rather than let it lapse."""
    root = ctx.paths.lr_root
    if ctx.slot_priority_want:
        w = time.time()
        if admit.write_slot_priority(root, w, ctx.last_pass_s, ctx.slot_priority_want):
            ctx.slot_priority_at = w
    elif ctx.slot_priority_at:
        ctx.slot_priority_at = 0.0
        admit.clear_slot_priority(root)


def _slot_priority_refresh(ctx: Ctx) -> None:
    """clock.step's hook: refresh the lease mid-pass (at most every 30 s), so the move lane's cap
    cannot lapse inside one long pass ("Freshness is subject-relative")."""
    if ctx.slot_priority_want and time.time() - ctx.slot_priority_at >= 30.0:
        _slot_priority(ctx)


def _lstart_epoch(lstart: str) -> Optional[float]:
    try:
        return time.mktime(
            time.strptime(" ".join(lstart.split()), "%a %b %d %H:%M:%S %Y")
        )
    except (ValueError, OverflowError):
        return None


IDLE_BOOT_SLOTS = 1  # D2a (D16, E9): the most boot slots idle records hold while a limited one is open


def _idle_boot_refusal(ctx: Ctx, rec: T.Record, now: float) -> str:
    """D2a: an idle move is optional work, a limited relaunch is the guarantee. Idle records take 0
    boot slots while any overdue limited record waits (W11's slot-priority signal, or an open
    limited record past its deadline), and at most IDLE_BOOT_SLOTS while any limited record is open,
    so the limited cohort keeps D_eff >= 5 of the 6 (admit.BootSlots.START). Limited records sort
    first in _dispatch, so within a pass a limited relaunch never waits on an idle boot. '' = no
    refusal; nothing is taken either way."""
    limited = [
        r
        for r in ctx.records.values()
        if r.open and r.kind == "limited" and r.sid != rec.sid
    ]
    if not limited:
        return ""
    if _own(ctx, "slot_priority_want", "") or any(
        r.phase not in ("ENGAGED", "MOVED") and admit.overdue(r, now) for r in limited
    ):
        return "idle-yields-overdue"
    held = sum(
        1
        for sid in ctx.boots.held
        if sid != rec.sid and sid in ctx.records and ctx.records[sid].kind == "idle"
    )
    return "idle-slot-cap" if held >= IDLE_BOOT_SLOTS else ""


def _admit(
    ctx: Ctx, rec: T.Record, which: str, snap: T.Snapshot, now: float
) -> Tuple[bool, str]:
    """D1.12: the only concurrency cap used to be LR_RECON_WORKERS (16). A relaunch now holds a boot
    slot, and a limited session's first turn (a move that types its prompt, or a continue) must
    pass Admission.decide: restore budget, CPU brake, per-account pacer, then the probe. The token
    rides to the actuator as LR_ADMIT_TOKEN_PATH."""
    if which in act.BOOTING and rec.kind == "idle":
        why = _idle_boot_refusal(ctx, rec, now)
        if why:
            return False, why
    if which in act.BOOTING and not ctx.boots.acquire(rec.sid):
        return False, "boot-slots"
    if rec.kind != "limited" or which not in FIRST_TURN:
        return True, "no-first-turn"
    if (
        which in ("C", "C-retry")
        and (rec.phase, rec.substate) == ("RELAUNCHED", "UNPROMPTED")
        and settle.launcher_admitted(ctx.home, rec)
    ):
        # The relaunch's own launcher was admitted for this first turn and typed nothing; C now
        # delivers that turn. A second admission charged it twice and, under the CPU brake that
        # never lifts at 15-40/core, held the owed continue indefinitely (gap 1 lever 3).
        return True, "launcher-admitted"
    if isinstance(ctx, Ctx) and ctx.pass_caps and ctx.pass_mints >= MINTS_PER_PASS:
        # W9: the pace bucket refills 1 per 20 s DURING a pass, so it alone does not bound a long
        # pass's mints; this does (P_cap's "mints 6 × 32"). Nothing is taken: next pass decides.
        if which in act.BOOTING:
            ctx.boots.release(rec.sid)
        return False, "pass-cap"
    unredeemed = sum(
        1
        for r in ctx.records.values()
        if r.open
        and r.admit_token
        and r.phase not in ("ENGAGED", "MOVED")
        and r.sid != rec.sid
    )
    l1, l5, _l15 = os.getloadavg()
    # W11: an overdue record's first turn may take the deadline lane (decide's overdue branch). The
    # mode gates it (F-H): off = today's gates exactly, shadow = today's gates plus a would-admit log.
    dl = _own(ctx, "deadline", "off")
    od = dl != "off" and admit.overdue(rec, now)
    room = _deadline_room(ctx, rec) if od else "no"
    acct = rec.target_acct or rec.source_acct
    ok, why = ctx.admission.decide(
        rec.sid,
        acct,
        now,
        _active_now(snap),
        unredeemed,
        l1,
        l5,
        os.cpu_count() or 1,
        rec.cohort_id,
        overdue=od and dl == "on",
        lane_room=not room,
    )
    if od and room and not ok and dl == "on":
        ctx.admission.deadline_why = room
    if od and dl == "shadow" and not room and not ok:
        _deadline_shadow(ctx, rec, "first turn", why)
    if not ok:
        if which in act.BOOTING:
            ctx.boots.release(rec.sid)
        return False, why
    # an idle move relaunches with no prompt (act.cmd_move adds --no-prompt), so it owes no turn
    tok = ctx.admission.mint_token(rec.sid, owes_prompt=rec.kind != "idle")
    if isinstance(ctx, Ctx):
        ctx.pass_mints += 1
    if why == "admit:deadline" and tok is None and which in settle.MOVE_ACTUATORS:
        # Lever 6 (efficacy 3): with no token lr-handoff re-probes the very gate this admission
        # bypassed and can park the move (lr-handoff.sh's PARKED capacity), silently. So no A/R
        # spawns: the pace and pacer charges stand and the record retries next pass, loudly.
        if which in act.BOOTING:
            ctx.boots.release(rec.sid)
        _event(
            ctx.paths,
            "deadline-mint-failed",
            rec.sid,
            rec.record_id,
            "%s on %s: no admission token minted; not spawned, retried next pass"
            % (which, acct),
        )
        return False, "deadline-mint-failed"
    rec.admit_token = tok or ""
    # W9: mints are counted per pass (summary "mints"). Each is ≤ 30 s + the reap grace, and a pass
    # mints at most MINTS_PER_PASS (6, the pace bucket's burst; the cap above enforces it)
    if why == "admit:deadline":
        t_dec = max(now, ctx.wall()) if isinstance(ctx, Ctx) else now
        rec.close["deadline_admitted_at"] = t_dec
        rec.close["deadline_acct"] = acct
        ctx.deadline_used = _own(ctx, "deadline_used", 0) + 1
        per = _own(ctx, "deadline_per_acct", {})
        per[acct] = per.get(acct, 0) + 1
        ctx.deadline_per_acct = per
        # F-K: the spawn row carries no admission reason, so the lane's admissions are evented
        _event(
            ctx.paths,
            "deadline-admit",
            rec.sid,
            rec.record_id,
            "%s on %s lane_used=%d/%d acct_used=%d/%d memory=%s"
            % (
                which,
                acct,
                ctx.deadline_used,
                admit.DEADLINE_WIDTH,
                per[acct],
                admit.DEADLINE_PER_ACCT,
                ctx.admission.hard.state,
            ),
        )
    else:
        rec.close.pop("deadline_admitted_at", None)
        rec.close.pop("deadline_acct", None)
    rec.close.pop("deadline_hold", None)
    return True, why


def _record_jobs(ctx: Ctx, rec: T.Record, snap: T.Snapshot, now: float) -> str:
    """Before a move is dispatched, write down the background jobs its exit will end: one JSON line
    per job under ``<lr_root>/carried-jobs/``. The recycle watcher records and mails them itself
    when it answers the background-work dialog (handoff-fire.sh rcy_jobs_capture); this is the
    record that exists whichever path the move takes, R's replace included. Never raises."""
    s = snap.sessions.get(rec.sid)
    if s is None or not s.bg_work:
        return ""
    path = os.path.join(
        ctx.paths.lr_root, "carried-jobs", "%s.%d.recon.jsonl" % (rec.sid, int(now))
    )
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            for b in s.bg_work:
                fh.write(
                    json.dumps(
                        {
                            "sid": rec.sid,
                            "pane": rec.pane[1] if rec.pane else None,
                            "pid": b.pid,
                            "started_utc": b.lstart,
                            "watcher": b.watcher_only,
                            "argv": b.argv,
                            "recorded_by": "lr-reconciler",
                        }
                    )
                    + "\n"
                )
    except OSError:
        return ""
    _event(ctx.paths, "jobs-recorded", rec.sid, rec.record_id, path)
    return path


def _dispatch(ctx: Ctx, snap: T.Snapshot, mode: str, now: float) -> int:
    n = 0
    running = act.running_count(ctx.records, snap)
    wake_ok = ctx.clock.wake_guard_ok()
    _admission_period(ctx, snap, now)
    tel = _tel(ctx)
    dl = _own(ctx, "deadline", "off")
    ctx.admission.begin_pass(now)  # W11 lever 5: the probe at most once per pass
    _deadline_lane(ctx, now)
    ctx.slot_priority_want = ""
    inf = float("inf")

    def refused(gate: str, why: str, rec: Optional[T.Record] = None) -> None:
        # B6: EVERY refusal counts, each pass; the events below stay on change only
        if tel is not None:
            tel.gate(gate, why)
        if rec is not None and dl != "off" and admit.overdue(rec, now):
            _deadline_note(ctx, rec, "%s:%s" % (gate, why), now)

    def order(r: T.Record) -> Tuple[bool, float, float]:
        # W11: earliest deadline first (the switch gates the sort too, F-H); before, oldest death
        # first, which a re-offered weekly-reset strand jumped by hours (efficacy 8)
        if dl == "off":
            return (r.kind != "limited", 0.0, r.timeline.detected or now)
        admit.sync_deadline(r)
        return (
            r.kind != "limited",
            admit.deadline_of(r) or inf,
            r.timeline.detected or now,
        )

    for rec in sorted(ctx.records.values(), key=order):
        step()
        t_dec = max(now, ctx.wall())  # B7 R2: this record's decision instant
        res = T.PhaseResult(
            phase=rec.phase,
            substate=rec.substate,
            action=ctx.actions.get(rec.sid, ""),
        )
        which = act.choose(res, rec)
        if which is None:
            continue
        if which == "C" and settle.quiet_for(rec, "typer", now) < C_GRACE_S:
            # The move's own launcher types the prompt, and its user record lands 1.6-11 s after
            # the Enter (W0) with re-sends up to 45 s: C only after that whole chain is quiet, or
            # it types a SECOND prompt into a session that already has one (W5 rig). The typer
            # stamp (_note_activity) ends the chain at the launcher's own verdict, not its exit.
            # B7 R4: this is an EVIDENCE wait, so it reads the census instant, never t_dec. C's
            # go-ahead is this census's UNPROMPTED and nothing re-reads the transcript before it
            # types; a later wall reading cannot make that census newer (B7 reviews, finding 1).
            refused("grace", "C", rec)
            continue
        if _c_rc5_landed(ctx, rec, which, t_dec):
            refused("grace", "c-rc5-landed", rec)
            continue
        ok, why = act.may_actuate(
            ctx.paths, mode, rec, which, snap, now, wake_ok, running, act.workers_cap()
        )
        if not ok:
            refused("may", why, rec)  # this refusal had no event at all
            continue
        if which in act.CLAIMED_ACTUATORS:
            # the claim before the token (act.hold_claim): another live driver keeps the session
            ok, why = act.hold_claim(ctx.paths, rec, _alive, now)
            if not ok:
                refused("claim", why, rec)
                if rec.close.get("claim_held") != why:
                    rec.close["claim_held"] = why
                    holder = store.read_claim(ctx.paths, rec.sid)
                    _event(
                        ctx.paths,
                        "claim-held",
                        rec.sid,
                        rec.record_id,
                        "%s: pid %s (%s) drives it; no token minted"
                        % (
                            why,
                            holder.pid if holder else "?",
                            (holder.owner if holder else "") or "a bash lane",
                        ),
                    )
                continue
            rec.close.pop("claim_held", None)
        ok, why = _admit(ctx, rec, which, snap, now)
        if not ok:
            # The gate's numbers ride with its name, for `cc-lr status --cohort` (report.next_action):
            # a standing refusal read "the reconciler continues" for as long as it stood.
            terms = ctx.admission.last_terms if why in ("restore-r", "drip") else ""
            refused("admit", why)
            if dl != "off" and admit.overdue(rec, now):
                # the overdue branch fell through: say why (lane full, hard stop) beside the gate
                dwhy = ctx.admission.deadline_why
                _deadline_note(
                    ctx, rec, "admit:%s%s" % (why, " (%s)" % dwhy if dwhy else ""), now
                )
                if dl == "on" and why == "boot-slots" and which in act.BOOTING:
                    # lever 4: the move lane yields while this overdue A/R waits on a boot slot
                    ctx.slot_priority_want = (
                        "overdue %s waits on boot slots" % rec.sid[:8]
                    )
            if rec.close.get("admit_refused") != why:
                rec.close["admit_refused"] = why
                _event(
                    ctx.paths,
                    "admit-refused",
                    rec.sid,
                    rec.record_id,
                    "%s (%s)" % (why, terms) if terms else why,
                )
            rec.close["admit_terms"] = terms
            rec.close.setdefault("admit_refused_at", t_dec)
            continue
        rec.close.pop("admit_refused", None)
        rec.close.pop("admit_terms", None)
        rec.close.pop("admit_refused_at", None)
        if tel is not None:
            tel.admitted(why)
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
            refused("argv", "empty", rec)
            continue
        pane = snap.panes.get("%d:%d" % rec.pane) if rec.pane else None
        if which in settle.MOVE_ACTUATORS:
            _record_jobs(ctx, rec, snap, now)
            # A6 S-8: set BEFORE spawn, so spawn's pre-Popen intent save carries it. Set after, a
            # pass killed before save_records lost it and the next move re-used the attempt (a
            # double typer by the audit above). If Popen raises, an attempt number is skipped.
            rec.close["move_attempt"] = rec.attempt
        if tel is not None:
            # B6: like move_attempt, set before spawn so spawn's own saves carry the stamps
            tel.pre_spawn(rec, which)
        pid = act.spawn(
            ctx.paths,
            rec,
            which,
            argv,
            act.actuator_env(rec, ctx.paths, pane.sock if pane else ""),
            now,
        )
        if tel is not None:
            tel.spawned(rec, which, pid)
        if which == "C" and ctx.actions.get(rec.sid) == "wake" and rec.wait:
            # typed for this reset: the next pass waits for the turn instead of retyping. Set here,
            # not when the wake was chosen, or a wake refused by admission was never tried again
            # (W6d rig: one CPU-brake refusal left a STAY session unwoken for good).
            rec.close["wake_eta"] = rec.wait.eta
            # A6 (d): a decision, not replayable from any file; on disk now, not at the pass end
            store.save_record(ctx.paths, rec, now)
        if which in settle.MOVE_ACTUATORS + ("C", "C-retry"):
            store.append_launch(
                ctx.paths,
                "%d\t%s\trecon-%s\tspawn\tpid=%d\tattempt=%d\trecord=%s"
                % (
                    max(now, ctx.wall()),
                    rec.sid,
                    which,
                    pid,
                    rec.attempt,
                    rec.record_id,
                ),
            )
        running += 1
        n += 1
    if isinstance(ctx, Ctx):
        _slot_priority(ctx)
    return n


def _c_rc5_landed(ctx: Ctx, rec: T.Record, which: str, t: float) -> bool:
    """C2-lite double-prompt guard: before a C or C-retry after an rc-5 C (CR sent, no record yet,
    "CANNOT TELL"), re-read the target transcript in process for THAT attempt's token. kitty runs a
    timed-out request late (~9 min measured, handoff-fire.sh), so the first C may land during the
    backoff, after this pass's census read the transcript. Present: skip the retry, stamp the
    submit, and let the next census re-derive. Returns True when the retry is skipped."""
    token = rec.close.get("c_rc5_token")
    if which not in classify.C_ACTUATORS or not token or rec.phase == "PRE-MOVE":
        return False
    tgt = evidence.transcript_path(rec.target_cfg, rec.cwd, rec.sid)
    if not tgt or not os.path.exists(tgt) or tokens.find_token(tgt, token, 0) is None:
        return False
    rec.close.pop("c_rc5_token", None)
    rec.timeline.submitted = rec.timeline.submitted or t
    _event(
        ctx.paths,
        "c-rc5-landed",
        rec.sid,
        rec.record_id,
        "the rc-5 C's token is in the target transcript: %s skipped, re-derived next pass"
        % which,
    )
    return True


def _command(ctx: Ctx, rec: T.Record, which: str) -> List[str]:
    if which == "A" or which == "R" and act.replaces(rec):
        # R over a live launcher-rooted source is the existing REPLACE inside lr-handoff (§C8 R row):
        # the same argv as A, whose recycle handoff-fire refuses ("NO shell under its session"), so
        # lr-handoff fires the successor beside the pane and retires the source once it is verified.
        # boot-resume-launch would refuse it: the source is a live holder (exit 5).
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
    if which == "C" and ctx.actions.get(rec.sid) == "wake" and rec.phase == "PRE-MOVE":
        os.makedirs(ctx.paths.p("work"), exist_ok=True)
        payload = ctx.paths.p("work", rec.sid + ".wake.txt")
        text = act.WAKE_TEXT_TEAM if rec.substate == "HELD:team" else act.WAKE_TEXT
        store.atomic_write_text(payload, text + "\n")
        return act.cmd_wake(rec, payload)
    if which in ("C", "C-retry"):
        rec.submit_token = act.new_token()
        os.makedirs(ctx.paths.p("work"), exist_ok=True)
        payload = ctx.paths.p("work", rec.sid + ".prompt.txt")
        store.atomic_write_text(payload, act.continue_prompt(rec, rec.scope, "") + "\n")
        return act.cmd_engage(rec, payload)
    return []  # SPLIT needs a bg job id the census does not carry yet: it pages instead


def _cohort(ctx: Ctx, cid: str, recs: List[T.Record], now: float) -> T.Cohort:
    """The cohort one pass reports on. Its reset is the cid's own key and its opening its first
    member's detection, and once set both are kept from its file, which every pass rewrites.
    Rebuilt bare every pass, the file read resets_at null and opened_at 0 (W5b2 defect A): the open
    page said "until ?", an all-good close page would have timed the cohort from the epoch, and the
    shadow's stop-marker window reached back to every earlier limit on the account."""
    prev = report.load_cohort(ctx.paths, cid)
    resets = prev.resets_at if prev is not None else None
    opened = prev.opened_at if prev is not None else 0.0
    det = [r.timeline.detected for r in recs if r.timeline.detected]
    r0 = recs[0]
    return T.Cohort(
        cid=cid,
        acct=r0.source_acct,
        scope=r0.scope,
        resets_at=resets or census.cohort_resets(cid),
        opened_at=opened or (min(det) if det else now),
        members=[r.sid for r in recs],
    )


def _requester_sets(ctx: Ctx, snap: T.Snapshot) -> Tuple[Set[str], Set[str]]:
    """(live, held) for Reporter.requester_mails. Held = a mail would wake a session that cannot
    use it: its last turn is a limit or auth death, it is the subject of an open record of any
    kind (a mid-move mail makes it take a turn mid-move), or its record ended IMPOSSIBLE and it
    has served no healthy turn since (recovered by hand, the IMPOSSIBLE record stays)."""
    live = {sid for sid, s in snap.sessions.items() if s.pid}
    held: Set[str] = set()
    for r in ctx.records.values():
        if r.terminal is not None and r.terminal.outcome == "IMPOSSIBLE":
            s = snap.sessions.get(r.sid)
            ok_at = s.transcript.last_assistant_ok_at if s else None
            if not ok_at or ok_at <= r.terminal.at:
                held.add(r.sid)
        elif r.open:
            held.add(r.sid)
    for sid, s in snap.sessions.items():
        last = s.transcript.last or {}
        if last.get("limit") or last.get("kind") == "auth_cliff":
            held.add(sid)
    return live, held


def _report(ctx: Ctx, mode: str, now: float, snap: Optional[T.Snapshot] = None) -> None:
    rep = ctx.reporter or report.Reporter(ctx.paths, mode)
    # The mode is re-read every pass (D6.4): the Reporter outlives a `recon/mode` write on the
    # running daemon, and built once it kept every page in observe until a restart.
    rep.mode = mode
    ctx.reporter = rep
    # W9: latched pages go to the durable outbox (recon/outbox/) and at most one synchronous send a
    # pass is made, pages and requester mails together: immediate pages first, then mails, then the
    # rest. A page or mail over the cap waits for a later pass, never lost (the outbox file / the
    # mail's latch-on-result). recon/page-outbox.off and recon/pass-caps.off each lift part of it.
    caps = _own(ctx, "pass_caps", False)
    rep.begin_pass(
        outbox=_own(ctx, "page_outbox", False),
        sends=report.SENDS_PER_PASS if caps else None,
    )
    adm = _own(ctx, "admission", None)
    by_cid: Dict[str, List[T.Record]] = {}
    for r in ctx.records.values():
        by_cid.setdefault(r.cohort_id, []).append(r)
    for cid, recs in by_cid.items():
        step()
        cohort = _cohort(ctx, cid, recs, now)
        try:
            rep.open_page(cohort, recs, {})
            rep.delta_page(cohort, recs)
            if all(not r.open for r in recs):
                rep.close_page(cohort, recs)
            rep.unrecoverable_page(cohort, recs)
            for r in recs:
                step()
                rep.immediate_pages(cohort, r)
                rep.max_age_page(cohort, r)
                _w11_record_pages(ctx, rep, cohort, r, snap, now)
            # W11 lever 8: one DEADLINE page per cohort (after max_age_page, whose latch excludes
            # its members), the drip's page, and the SLO page that had no caller
            if snap is not None:
                live = {r.sid for r in recs if act.live_procs(r, snap)}
                rep.deadline_page(cohort, recs, live)
            if adm is not None and cid in adm.drip_pages:
                rep.drip_page(cohort)
            if any(r.kind == "limited" for r in recs):
                rep.slo_page(cohort, recs)
            report.write_cohort(ctx.paths, cohort, recs, now)
        except Exception as e:  # a surface failure never stops the loop
            _event(ctx.paths, "report-error", detail=repr(e)[:200])
    if adm is not None:
        adm.drip_pages = []
        try:
            _hard_stop_report(ctx, rep, now)
        except Exception as e:  # noqa: BLE001
            _event(ctx.paths, "report-error", detail=repr(e)[:200])
    try:
        rep.flush_outbox(immediate_only=True)
    except Exception as e:
        _event(ctx.paths, "report-error", detail=repr(e)[:200])
    if snap is not None:
        try:
            live, held = _requester_sets(ctx, snap)
            rep.requester_mails(list(ctx.records.values()), live, held)
        except Exception as e:
            _event(ctx.paths, "report-error", detail=repr(e)[:200])
    try:
        rep.flush_outbox()
    except Exception as e:
        _event(ctx.paths, "report-error", detail=repr(e)[:200])
    try:
        # operator-readout.sh reads this one file instead of loading every record: a Stop hook
        # has a ~2-3 s budget and no python on its path. Empty file ⇒ nothing open ⇒ no line.
        line = report.readout_line(ctx.paths, now, list(ctx.records.values()))
        tel = _tel(ctx)
        alert = getattr(tel, "last_alert", "") if tel is not None else ""
        if line and alert:
            # B6 §6.4: only a measured anomaly of the last pass; empty otherwise, so the Stop
            # hook's "a wrong line is worse than a missing one" holds
            line = line.rstrip("\n") + " · ⚠ rail: %s → cc-lr status --rail" % alert
        store.atomic_write_text(ctx.paths.p("readout.line"), line)
    except Exception as e:
        _event(ctx.paths, "report-error", detail=repr(e)[:200])


def _w11_record_pages(
    ctx: Ctx,
    rep: report.Reporter,
    cohort: T.Cohort,
    r: T.Record,
    snap: Optional[T.Snapshot],
    now: float,
) -> None:
    """Per record: classify's BACKOFF_PAGE, an unknown-exit re-offer, and (lever 9) an actuator
    alive past T_att — paged once, never killed. Only our own actuators count: role "actuator", not
    adopted by argv (a watcher or an adopted descendant outlives its attempt by design)."""
    rep.backoff_page(cohort, r)
    rep.unknown_exit_page(cohort, r)
    if snap is None or not r.open or r.kind != "limited":
        return
    for p in act.live_procs(r, snap):
        if p.role != "actuator" or p.argv_hash in ("", "adopted"):
            continue
        t0 = _lstart_epoch(p.lstart)
        if t0 is not None and now - t0 > admit.T_ATT_S:
            rep.attempt_page(cohort, r, p.pid, p.lstart, now - t0)


def _hard_stop_report(ctx: Ctx, rep: report.Reporter, now: float) -> None:
    """The hard stop's own events (trip, release, unknown-release), and lever 7's page: a trip that
    has lasted W_hard while overdue records wait pages once per trip, "deadline bypass off"."""
    hs = ctx.admission.hard
    waiting = [
        r
        for r in ctx.records.values()
        if r.open and r.phase not in ("ENGAGED", "MOVED") and admit.overdue(r, now)
    ]
    if waiting and hs.tripped and _own(ctx, "deadline", "off") == "on":
        # decide() reads the stop only for an overdue member with lane room; a trip judged on a
        # stale read would page a stop that has since cleared, so read it once more here
        hs.check()
    for ev, detail in hs.events:
        _event(ctx.paths, ev, detail=detail)
    hs.events = []
    since = hs.tripped_since()
    if since is None:
        ctx.hard_paged = None
        return
    if ctx.hard_paged == since or time.time() - since < admit.DEADLINE_HARD_S:
        return
    if not waiting:
        return
    ctx.hard_paged = since
    rep.daemon_page(
        "DEADLINE-OFF",
        "deadline bypass off: %s for %d min while %d overdue record(s) wait; the bound is today's "
        "drip plus slots until it releases"
        % (
            "; ".join(str(t["why"]) for t in hs.tripped.values()),
            int((time.time() - since) // 60),
            len(waiting),
        ),
    )


REFIRE_SUFFIX = ".refire.json"
ABANDON_SUFFIX = ".abandon.json"


def _consume_ctl(
    ctx: Ctx, suffix: str, verb: str, apply: Callable[[T.Record, str], None]
) -> int:
    """One ``ctl/<sid><suffix>`` file per request: applied to the sid's OPEN record, then moved to
    ``ctl/done/`` so neither the next pass nor a restart re-applies it. A sid with no open record is
    moved too, and logged."""
    try:
        names = sorted(n for n in os.listdir(ctx.paths.ctl) if n.endswith(suffix))
    except OSError:
        return 0
    done = os.path.join(ctx.paths.ctl, "done")
    n = 0
    for name in names:
        src = os.path.join(ctx.paths.ctl, name)
        sid, by = name[: -len(suffix)], "?"
        try:
            with open(src, encoding="utf-8") as fh:
                doc = json.load(fh)
            sid, by = str(doc.get("sid") or sid), str(doc.get("by") or by)
        except (OSError, ValueError, AttributeError):
            pass  # a torn or foreign body still names its sid in the file name
        rec = ctx.records.get(sid)
        if rec is not None and rec.open:
            apply(rec, by)
            _event(ctx.paths, verb, sid, rec.record_id, "by=%s" % by)
            n += 1
        else:
            _event(ctx.paths, verb + "-unknown", sid, detail="by=%s" % by)
        try:
            os.makedirs(done, 0o700, exist_ok=True)
            os.replace(src, os.path.join(done, name))
        except OSError as e:
            _event(ctx.paths, verb + "-error", sid, detail=repr(e)[:200])
    return n


def _refire(ctx: Ctx, now: float) -> int:
    """The daemon side of ``cc-lr cohort refire`` (§C11): re-arms one OPEN member's budget through
    classify.rearm — the same entry point the 15-minute re-arm uses, so a refire can never grant
    more than the clock would. An operator refire also resets the automatic re-arm count.

    It also forgets the last admission refusal, so the next pass logs the gate's answer again. A
    refusal is logged only when its reason changes (``_dispatch``), so a refire of a member the
    gate was still refusing for the same reason left ``refire`` as the newest event and nothing
    after it (14233392, 2026-10-13: ``restore-r`` before and after, read as a refire ignored)."""

    def apply(rec: T.Record, _by: str) -> None:
        classify.rearm(rec, now)
        rec.close.pop("rearms", None)
        rec.close.pop("admit_refused", None)

    return _consume_ctl(ctx, REFIRE_SUFFIX, "refire", apply)


def _abandon(ctx: Ctx, now: float) -> int:
    """D1.10, ``python3 -m lr_recon --abandon <sid>``: the operator gives a session up. The record
    goes terminal (IMPOSSIBLE, proof names who abandoned it), which pages and, in the same pass,
    releases owned/<sid> and the run claim to the other recovery paths."""

    def apply(rec: T.Record, by: str) -> None:
        rec.terminal = T.Terminal(
            outcome="IMPOSSIBLE", proof="abandoned by %s" % by, at=now
        )

    return _consume_ctl(ctx, ABANDON_SUFFIX, "abandon", apply)


def _release_terminal(ctx: Ctx) -> int:
    """D1.10: a terminal record gives up owned/<sid> and its run claim. release_fence had no caller,
    so every sid the daemon ever owned stayed DEFER for every other recovery path (the fence, and
    cc-resume-debt's handoff) for as long as the daemon lived. Keyed by record_id: a newer record's
    fence is never touched."""
    n = 0
    for rec in ctx.records.values():
        if rec.open:
            continue
        if store.release_fence(ctx.paths, rec.sid, rec.record_id):
            _event(ctx.paths, "release", rec.sid, rec.record_id, rec.terminal.outcome)
            n += 1
        store.claim_release(ctx.paths, rec.sid, rec.record_id)
    return n


def _release_plan_only(ctx: Ctx, snap: T.Snapshot) -> int:
    """W13 (A7 review F-D1): the HAND-OVER. An open plan-only record that is not finishing its own
    move (act.own_move_in_flight) gives up owned/<sid> and its run claim, with a ``release
    plan-only`` event. _release_terminal frees only terminal records and _own_and_charge skips
    plan-only ones, so before this every PLANNED record kept both when recon/autorecover.on was
    removed: the poller's fence read heartbeat-fresh, run_claim_take saw a live lr-reconciler, and no
    lane drove the session until its own reset closed the record. Never while one of its actuators
    lives (deleting the fence would drop the bash fence's proc-alive rule under it). Keyed by
    record_id, like _release_terminal. recon/plan-only-finish.off turns it off with Part D."""
    if not act.PLAN_ONLY_FINISH:
        return 0
    n = 0
    for rec in ctx.records.values():
        if not rec.open or not rec.plan_only or act.own_move_in_flight(rec):
            continue
        if act.live_procs(rec, snap):
            continue
        fence = store.read_fence(ctx.paths, rec.sid)
        if fence is None or fence.record_id != rec.record_id:
            continue
        if store.release_fence(ctx.paths, rec.sid, rec.record_id):
            store.claim_release(ctx.paths, rec.sid, rec.record_id)
            _event(ctx.paths, "release", rec.sid, rec.record_id, "plan-only")
            n += 1
    return n


def request_abandon(paths: T.Paths, sid: str, by: str = "operator") -> str:
    """The CLI half of --abandon: one ctl file the running daemon consumes on its next pass."""
    os.makedirs(paths.ctl, 0o700, exist_ok=True)
    path = os.path.join(paths.ctl, sid + ABANDON_SUFFIX)
    store.atomic_write_json(path, {"sid": sid, "at": time.time(), "by": by})
    return path


def _kitty_degraded(ctx: Ctx, snap: T.Snapshot) -> None:
    """C2 E5 T4: one ``kitty-degraded`` event when a pass's degraded list holds a ``kitty:`` entry
    while an open record owes its continue (UNPROMPTED). It is the direct observable of the fault C2
    targets: a deaf kitty spawns no C at all (E1), so no C exit can count it. On change only."""
    kitty = sorted(d for d in snap.degraded if d.startswith("kitty:"))
    owed = sorted(
        r.sid[:8] for r in ctx.records.values() if r.open and r.substate == "UNPROMPTED"
    )
    key = "%s|%s" % (",".join(kitty), ",".join(owed)) if kitty and owed else None
    if key is not None and key != _own(ctx, "kitty_degraded", None):
        _event(
            ctx.paths,
            "kitty-degraded",
            detail="%s while %d record(s) owe their continue: %s"
            % (", ".join(kitty), len(owed), " ".join(owed)),
        )
    ctx.kitty_degraded = key


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
        # B7 D4: its anchor is the confirm, else the first pass that saw it IN-FLIGHT (never
        # updated_at, which save_records rewrites every pass); while this attempt's watcher or
        # unsettled launcher lives (typer seen by this census) it is owned, however long.
        t = now or time.time()
        if (
            r.phase == "PRE-MOVE"
            and r.substate == "IN-FLIGHT"
            and (
                t - (r.timeline.confirmed or r.close.get("in_flight_at") or t)
                < IN_FLIGHT_MAX_S
                or settle.quiet_for(r, "typer", t) < 0
            )
        ):
            continue
        if act.live_procs(r, snap) or r.next_eligible_at or (r.wait and r.wait.reason):
            continue
        if r.phase in ("ENGAGED", "MOVED"):
            continue
        if (
            r.phase == "PRE-MOVE"
            and r.substate is None
            and r.close.get("exit_unknown")
            and not r.escalated
        ):
            continue  # W11 lever 10: settle.unknown_exit owns it and re-offers it past its window
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


def _abstain(
    ctx: Ctx, snap: T.Snapshot, mode: str, now: float, why: str
) -> Dict[str, Any]:
    """W7a: a census this pass cannot trust decides nothing — no move, close, dead verdict, HOLD
    release or wake. Records, requests and ctl files are left as they are for the next pass, which
    decides; this one leaves one ``abstain`` event and says so on the readout line and in the
    shadow's last-pass.json, so a persistent outage is visible rather than a quiet empty world."""
    ctx.abstain_streak += 1
    _event(ctx.paths, "abstain", detail="%s (%d in a row)" % (why, ctx.abstain_streak))
    try:
        store.atomic_write_text(
            ctx.paths.p("readout.line"),
            report.readout_line(
                ctx.paths, now, list(ctx.records.values()), abstain=why
            ),
        )
    except Exception as e:
        _event(ctx.paths, "report-error", detail=repr(e)[:200])
    rep = _own(ctx, "reporter", None)
    if rep is not None and _own(ctx, "page_outbox", False):
        # W9: pages latched by earlier passes do not depend on this census; a ps stall that lasts
        # minutes must not hold them, so an abstained pass spends its one send on the outbox too
        try:
            rep.mode = mode
            caps = _own(ctx, "pass_caps", False)
            rep.begin_pass(outbox=True, sends=report.SENDS_PER_PASS if caps else None)
            rep.flush_outbox()
        except Exception as e:
            _event(ctx.paths, "report-error", detail=repr(e)[:200])
    summary = {
        "mode": mode,
        "census": observe.census_line(snap),
        "abstain": why,
        "buckets": {},
        "open": sum(1 for r in ctx.records.values() if r.open),
        "stale": 0,
        "placed": 0,
        "actuations": 0,
        "defects": 0,
        "degraded": list(snap.degraded),
        "facts": 0,
    }
    if mode == "observe":
        store.atomic_write_json(
            os.path.join(ctx.paths.shadow, "last-pass.json"), summary
        )
    ctx.last_summary = summary
    return summary


ZOMBIE_PASSES = (
    2  # an unregistered zombie child seen this many passes running is an event
)


def _unowned_zombies(ctx: Ctx, snap: T.Snapshot) -> None:
    """W9 safety net for registered-only reaping: a zombie child of ours that no registry holds
    means a Popen site nothing polls (the waitpid(-1) loop that hid one is gone). One event per
    pid, and only after ZOMBIE_PASSES consecutive passes: a child that exited a moment before the
    census and is reaped this pass, or one CPython's own _cleanup collects, is not one."""
    me = os.getpid()
    owned = clock.registered_pids() | set(act._CHILDREN)
    seen = {
        r.pid
        for r in snap.procs.values()
        if r.ppid == me and r.zombie and r.pid not in owned
    }
    prev = ctx.zombies
    ctx.zombies = {pid: prev.get(pid, 0) + 1 for pid in seen}
    for pid, n in ctx.zombies.items():
        if n == ZOMBIE_PASSES:
            row = snap.procs.get(pid)
            _event(
                ctx.paths,
                "unowned-zombie",
                detail="pid %d %s" % (pid, (row.args if row else "")[:120]),
            )


def _orphan_page(ctx: Ctx) -> None:
    """W9: killed children the kernel has not let go of yet (a ps stuck past its kill) pile up in
    clock._ORPHANS. ORPHAN_PAGE_AT of them at once is one event and one page per process."""
    n = clock.orphan_count()
    if n < clock.ORPHAN_PAGE_AT or ctx.orphans_paged:
        return
    ctx.orphans_paged = True
    text = "%d killed children not yet reaped (a kernel stall?); oldest argv %s" % (
        n,
        " ".join(str(x) for x in (getattr(clock._ORPHANS[0], "args", None) or [])[:3]),
    )
    _event(ctx.paths, "orphan-backlog", detail=text[:200])
    rep = ctx.reporter or report.Reporter(ctx.paths, read_mode(ctx.paths, ctx.mode_cap))
    rep.daemon_page("ORPHANS", text)


def _keep_claims(ctx: Ctx, snap: T.Snapshot) -> None:
    """A6 (c), right after the W7a gate and before facts and the census: under load the first
    _derive comes minutes after the census (287 s measured once, p90 736 s), and the claim must name
    a live ancestor of every chain driving the record well before that (A6 F-C). adopt is
    idempotent; _derive runs it again. The daemon only (ctx.keeper, set after its flock): a --once
    process would stamp itself, then exit (S-2)."""
    me = act.self_ident(snap)
    for rec in ctx.records.values():
        if not rec.open:
            continue
        act.adopt(rec, snap)
        ev, detail = act.keep_claim(ctx.paths, rec, snap, me)
        if ev:
            _event(ctx.paths, ev, rec.sid, rec.record_id, detail)


def run_pass(ctx: Ctx, force_observe: bool = False) -> Dict[str, Any]:
    # One projects/ index serves every sid → transcript / .handed-off / .HANDOFF.json lookup
    # (transcript.ProjectsIndex): a glob per lookup lstat'd every project dir. The daemon's index
    # is kept across passes and refreshed incrementally; a ctx without one sweeps afresh.
    seq = _own(ctx, "pass_seq", 0) + 1
    if isinstance(ctx, Ctx):
        ctx.pass_seq = seq
    set_phase("begin", seq)
    tel = _tel(ctx)
    if tel is not None:
        tel.check_switch()
        tel.pass_begin(seq, _own(ctx, "slept", 0.0))
    out: Optional[Dict[str, Any]] = None
    exc: Optional[BaseException] = None
    t0 = time.time()
    try:
        with transcript.pass_index(getattr(ctx, "projects", None)):
            out = _run_pass(ctx, force_observe)
        return out
    except BaseException as e:
        exc = e
        raise
    finally:
        if isinstance(ctx, Ctx):
            ctx.last_pass_s = max(
                0.0, time.time() - t0
            )  # W11: sizes the slot-priority lease
        if tel is not None:
            tel.pass_end(out, exc)
        set_phase("idle", seq)


def _run_pass(ctx: Ctx, force_observe: bool) -> Dict[str, Any]:
    paths = ctx.paths
    store.ensure_dirs(paths)  # cheap, and a wiped root must never crash the loop
    _w9_switches(ctx)
    act.begin_pass(ctx.pass_caps)
    ctx.pass_mints = 0
    act.reap_children()  # before ps, so an exited actuator is gone AND its exit code is kept
    mode = "observe" if force_observe else read_mode(paths, ctx.mode_cap)
    # W8 kill switches, read every pass (no reload): B7's clocks, and classify's two mappings
    ctx.pass_clock = read_pass_clock(paths)
    ctx.admission.pacer_on_wall = ctx.pass_clock != "pass"
    classify.read_switches(paths.root)
    # W13: recon/plan-only-finish.off, re-read every pass (no reload)
    act.PLAN_ONLY_FINISH = not os.path.exists(paths.p(act.PLAN_ONLY_FINISH_OFF))
    # W11: recon/deadline.off | recon/deadline.shadow, re-read every pass (no reload)
    ctx.deadline = admit.deadline_mode(
        paths.p("deadline.off"), paths.p("deadline.shadow")
    )
    now = time.time()
    _ph(ctx, "observe")
    # rig_keep: a sid the daemon holds a record for stays visible mid-move (observe._sessions)
    snap = observe.observe(
        paths,
        ctx.home,
        transcript_fn=transcript.observe,
        now=now,
        rig_keep=frozenset(ctx.records),
    )
    step()
    tel = _tel(ctx)
    if tel is not None:
        tel.observed(snap)
    ctx.degraded_streak = ctx.degraded_streak + 1 if snap.degraded else 0
    # W7a: the one gate between the census and every decision. It stands before facts, census,
    # derive, refire/abandon, wakes, plan, dispatch, release and the invariant, so an empty or
    # collapsed census can move, close, kill, release or wake nothing.
    why = observe.untrusted(snap, ctx.last_nclaude)
    if "ps" not in snap.degraded:
        ctx.last_nclaude = observe.claude_count(snap)
    if why:
        return _abstain(ctx, snap, mode, now, why)
    ctx.abstain_streak = 0
    _unowned_zombies(ctx, snap)
    if ctx.keeper:
        _keep_claims(ctx, snap)
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
    _ph(ctx, "facts")
    facts = _facts(ctx, snap, now)
    step()
    _ph(ctx, "census")
    reqs = store.list_requests(paths)
    ctx.pre_census = {s: r.substate or "" for s, r in ctx.records.items()}
    gate = ctx.composer_gate = ComposerGate(
        ctx.pass_seq, ctx.composer_last, ctx.composer_want, ctx.pass_caps
    )
    try:
        buckets, stale = _census(ctx, snap, facts, reqs, mode, now)
    finally:
        ctx.composer_gate = None
        ctx.composer_want = gate.wanted
        for sid in [s for s in ctx.composer_last if s not in snap.sessions]:
            del ctx.composer_last[
                sid
            ]  # a session gone from the census needs no rotation slot
    tel = _tel(ctx)
    if tel is not None and gate.skipped:
        tel.gate("composer", "pass-cap")
    _focus_ledger(paths, snap, buckets, mode, now)
    _ph(ctx, "derive")
    _derive(ctx, snap, now, facts, capped.latest_usage(ctx.home, now))
    _kitty_degraded(ctx, snap)
    _draft_snapshots(ctx, snap)
    for rec in (
        ctx.records.values()
    ):  # the fold audit's evidence (plan § W5): cheap, never raises
        if evidence.fold_witness(paths, rec) == "fold":
            _event(paths, "fold-witness", rec.sid)
    # before planning, so a re-armed member is placed and dispatched this pass
    _ph(ctx, "ctl")
    _refire(ctx, now)
    _abandon(ctx, now)
    _wakes(ctx, snap, facts, now)
    _stranded(ctx, snap, mode, now)
    step()
    _ph(ctx, "plan")
    placed = _plan(ctx, snap, facts, mode, now)
    step()
    spawned = 0
    if mode == "act" and os.path.exists(paths.recon_on):
        _ph(ctx, "own")
        _own_and_charge(ctx, now)
        _ph(ctx, "dispatch")
        spawned = _dispatch(ctx, snap, mode, now)
        ctx.actuations += spawned
    elif ctx.slot_priority_want or ctx.slot_priority_at:
        ctx.slot_priority_want = (
            ""  # no dispatch, no waiter: the move lane gets its slots back
        )
        _slot_priority(ctx)
    step()
    if tel is not None:
        # before _report (cohort_status's in_state_s reads the state stamp); stamps ride save_records
        tel.note_states(ctx.records.values(), lambda r: report.bucket(r) == "moving")
    _ph(ctx, "report")
    _report(ctx, mode, now, snap)
    step()
    _ph(ctx, "save")
    _release_terminal(ctx)
    _release_plan_only(ctx, snap)
    defects = _invariant(ctx, snap, now)
    # one batch: a record whose content did not change is not rewritten (store.save_records)
    store.save_records(paths, list(ctx.records.values()), now)
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
        "mints": ctx.pass_mints,
        "composer_reads": gate.reads,
        "composer_skipped": gate.skipped,
        "idle_composer": [  # D2a: reads, reused verdicts, capped this pass
            ctx.idle_composer.reads,
            ctx.idle_composer.cached,
            ctx.idle_composer.capped,
        ],
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
    paths: T.Paths,
    home: str,
    timeout: float,
    hb: Optional[Heartbeat],
    wake: Optional[Callable[[], bool]] = None,
    tick_s: float = 1.0,
) -> bool:
    """1 s stat poll of the wake dirs; returns True on a change, False on timeout. W9: ``wake``
    (the daemon passes act.any_exited) is also polled each tick, so an actuator's exit starts the
    next pass within ~1 s — settled, and its retry's backoff scheduled — instead of 3-20 s later."""
    sig = _signature(paths, home)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        time.sleep(tick_s)
        if hb is not None:
            hb.advance()  # progress inside a wait: the loop is alive, just idle (§C2)
        if wake is not None and wake():
            return True
        if _signature(paths, home) != sig:
            return True
    return False


PASS_EXC_EXIT_AFTER = (
    3  # consecutive raising passes before the daemon exits 1 (KeepAlive restarts)
)
PASS_EXC_PAGE_EVERY_S = 3600.0


def _sigterm(signum: int, frame: Any) -> None:
    """W9 (B2 review C5): SIGTERM — launchd's kickstart -k, the watchdog's TERM — raises SystemExit
    on the main thread, so daemon()'s finally runs. There was no handler, so a kill skipped it."""
    raise SystemExit(128 + signum)


def _pass_exception(ctx: Ctx, e: Exception) -> bool:
    """W9: a pass that raises is an event and (hourly) a page instead of an instant crash. Returns
    True when it is the PASS_EXC_EXIT_AFTER-th in a row: the daemon then exits 1, and KeepAlive's
    restart is safe (A6). Answers B3 review F-B: one bad record no longer restarts the daemon."""
    ctx.pass_exc_streak += 1
    import traceback

    tb = traceback.extract_tb(e.__traceback__)
    where = "%s:%d" % (os.path.basename(tb[-1].filename), tb[-1].lineno) if tb else "?"
    detail = "%d in a row at %s: %r" % (ctx.pass_exc_streak, where, e)
    try:
        _event(ctx.paths, "pass-exception", detail=detail[:300])
        if time.time() - ctx.pass_exc_paged_at >= PASS_EXC_PAGE_EVERY_S:
            ctx.pass_exc_paged_at = time.time()
            rep = ctx.reporter or report.Reporter(
                ctx.paths, read_mode(ctx.paths, ctx.mode_cap)
            )
            rep.daemon_page("PASS-EXCEPTION", "reconciler pass raised " + detail[:200])
    except Exception:  # noqa: BLE001 — the guard must not raise out of the loop it guards
        pass
    return ctx.pass_exc_streak >= PASS_EXC_EXIT_AFTER


RESTART_REQUEST = "restart.request"  # under recon/ctl: a pass-boundary restart (A6 (f))
RESTART_REQUEST_ON = (
    "restart-request.on"  # under recon/: the operator's ruling; absent = inert
)


def _restamp(paths: T.Paths, rec: T.Record, pid: int, lstart: str) -> None:
    try:
        store.claim_restamp(paths, rec.sid, rec.record_id, pid, lstart)
    except OSError:
        pass  # a steal renamed the claim dir mid-write: the first trusted pass decides (S-6)


def _prev_heartbeat(paths: T.Paths) -> Dict[str, Any]:
    """The previous daemon's heartbeat (pid, lstart, progress_wall), read before ours replaces it.
    {} when absent or unreadable: forensics only, never raises."""
    try:
        with open(paths.heartbeat, encoding="utf-8") as fh:
            hb = json.load(fh)
        return hb if isinstance(hb, dict) else {}
    except (OSError, ValueError):
        return {}


def _restart_forensics(prev: Dict[str, Any], now: float) -> Dict[str, Any]:
    """A6 (e): who ran before, how long it had been frozen, and whether the code changed under it
    (deploy-driven vs a watchdog kill). Each field is best-effort; nothing here raises."""
    out: Dict[str, Any] = {}
    try:
        out["prev_pid"] = int(prev.get("pid") or 0)
        out["prev_lstart"] = str(prev.get("lstart") or "")
        if prev.get("progress_wall"):
            out["prev_progress_age_s"] = round(now - float(prev["progress_wall"]), 1)
    except (TypeError, ValueError):
        pass
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        mt = max(
            os.stat(os.path.join(here, n)).st_mtime
            for n in os.listdir(here)
            if n.endswith(".py")
        )
        out["code_mtime"] = int(mt)
        started = out.get("prev_lstart")
        if started:
            epoch = calendar.timegm(time.strptime(started, "%a %b %d %H:%M:%S %Y"))
            out["code_newer_than_prev"] = mt > epoch
    except (OSError, ValueError):
        pass
    return out


def _restart_loop(paths: T.Paths, now: float) -> bool:
    """Two restarts within 10 minutes among the last three rows. A requested restart's own row and
    the startup row that follows it are exempt: they are the pass-boundary restart (f) working."""
    try:
        with open(paths.restarts, encoding="utf-8") as fh:
            rows = [json.loads(ln) for ln in fh.readlines()[-4:]]
        n = 0
        for i in range(max(0, len(rows) - 3), len(rows)):
            if rows[i].get("cause") == "requested" or (
                i > 0 and rows[i - 1].get("cause") == "requested"
            ):
                continue
            if now - float(rows[i].get("t", 0)) < RESTART_PAGE_WINDOW_S:
                n += 1
        return n >= 2
    except (OSError, ValueError, AttributeError):
        return False


def _restart_requested(paths: T.Paths) -> bool:
    """A6 (f), inert until ruled: ``recon/ctl/restart.request`` asks for a restart at this pass
    boundary, after save_records, honored only while ``recon/restart-request.on`` exists. launchd
    KeepAlive restarts the daemon within ~10 s; a deploy then never kills a pass mid-act."""
    req = os.path.join(paths.ctl, RESTART_REQUEST)
    if not (os.path.exists(req) and os.path.exists(paths.p(RESTART_REQUEST_ON))):
        return False
    store._unlink(req)
    store.append_restart(
        paths, {"t": time.time(), "pid": os.getpid(), "cause": "requested"}
    )
    return True


def _startup(
    ctx: Ctx, me: Optional[str] = None, prev: Optional[Dict[str, Any]] = None
) -> None:
    paths = ctx.paths

    def bad(path: str, reason: str) -> None:
        _event(paths, "quarantine", detail="%s %s" % (os.path.basename(path), reason))

    ctx.records = store.load_all(paths, bad)
    me = store.proc_lstart(os.getpid()) if me is None else me
    prev = _prev_heartbeat(paths) if prev is None else prev
    keeper = act.keeper_on(paths)
    inherited: List[str] = []
    phases: Dict[str, str] = {}
    for rec in ctx.records.values():
        claim = store.read_claim(paths, rec.sid)
        if not (rec.open and claim is not None and claim.record_id == rec.record_id):
            continue
        acts = [p for p in rec.procs if p.role == "actuator"]
        if not (keeper and (rec.intent is not None or acts)):
            _restamp(paths, rec, os.getpid(), me)
            continue
        # A6 (c): an actuator the last daemon started may still run, and only it (an ancestor of
        # its handoff-fire) may hold the claim. Startup has no census: stamp the last NAMED
        # actuator's recorded identity — a dead one is no worse a holder than the dead old daemon,
        # and a live one is protected from the first moment, however long the first pass takes
        # (F-D, S-1). The first trusted pass's keeper then decides from its census.
        named = [p for p in acts if p.argv_hash != "adopted"]
        intent_act = rec.intent.actuator if rec.intent is not None else ""
        inherited.append(
            "%s:%s"
            % (
                rec.sid[:8],
                named[-1].argv_hash if named else intent_act or "adopted",
            )
        )
        phases[rec.sid[:8]] = rec.phase
        if named and named[-1].lstart:
            w = named[-1]
            if (claim.pid, claim.lstart) != (w.pid, w.lstart):
                _restamp(paths, rec, w.pid, w.lstart)
            detail = (
                "pid %d → %s pid %d, started by the last daemon; the first pass decides"
                % (
                    claim.pid,
                    w.argv_hash,
                    w.pid,
                )
            )
        elif not named and claim.lstart:
            # intent-only (killed between Popen and the procs save) or adopted-only: the wrapper's
            # pid is unknown until a census adopts it by nonce. A dead holder with an lstart reads
            # dead or reused to bash, never foreign (F-B); the first pass hands it over.
            detail = (
                "pid %d left for the first pass (no named actuator recorded)"
                % claim.pid
            )
        else:
            # never leave an old-daemon claim with an empty lstart: bash judges it by pid alone,
            # and a reused pid reads live and foreign (S-1)
            _restamp(paths, rec, os.getpid(), me)
            detail = "pid %d → this daemon (no recorded lstart to stamp)" % claim.pid
        _event(paths, "claim-inherited", rec.sid, rec.record_id, detail)
    now = time.time()
    act.reap_exits(paths, now)
    row: Dict[str, Any] = {
        "t": now,
        "pid": os.getpid(),
        "lstart": me,
        "inflight": len(inherited),
        "inherited": inherited[:16],
        "prev_phase": dict(list(phases.items())[:16]),
    }
    row.update(_restart_forensics(prev, now))
    store.append_restart(paths, row)
    if _restart_loop(paths, now):
        _event(paths, "restart-loop", detail="second restart within 10 minutes")


def _make_telemetry(ctx: Ctx, me: str, prev: Dict[str, Any]) -> Any:
    """B6, daemon only (P3). The constructor is guarded too: methods are, __init__ is not, and an
    exception there would kill every daemon start. Any failure is one event and no telemetry."""
    if telemetry is None:
        if _TELEMETRY_IMPORT_ERROR:
            _event(
                ctx.paths, "telemetry-off", detail="import: " + _TELEMETRY_IMPORT_ERROR
            )
        return None
    if os.environ.get("LR_RECON_TELEMETRY", "on") == "off":
        return None
    try:
        tel = telemetry.Telemetry(ctx.paths)
    except Exception as e:  # noqa: BLE001
        _event(ctx.paths, "telemetry-off", detail="constructor: %r" % e)
        return None
    tel.start(prev, list(ctx.records.values()), me)
    return tel


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
    # A6 F-E ii: read the previous heartbeat, then write ours BEFORE _startup's claim loop, with
    # one ps for both. The watchdog's kill already let the old heartbeat go stale, so until ours
    # is written the fence's freshness rule holds nothing off an inherited record.
    _w9_switches(ctx)
    me = (
        store.self_lstart()
    )  # W9: in process, cached for _own_and_charge and the boot slots
    prev = _prev_heartbeat(paths)
    hb = Heartbeat(paths.heartbeat, os.getpid(), me, ctx.clock)
    hb.write_now()
    _startup(ctx, me, prev)
    ctx.keeper = True  # after the flock: the one process whose claims these are (S-2)
    hb.start()
    bind_steps(hb)  # run_pass's step() calls advance hb, from this thread only
    bind_step_hook(
        lambda: _slot_priority_refresh(ctx)
    )  # W11 lever 4: the lease keeps pace
    ctx.telem = _make_telemetry(ctx, me, prev)
    if ctx.telem is not None:
        bind_child_hook(ctx.telem.child)
    caf = Caffeinate(os.getpid())
    old_term = signal.signal(signal.SIGTERM, _sigterm)
    queued = report.Reporter(ctx.paths, "act").queued()
    if queued:
        _event(
            paths, "outbox-replay", detail="%d page(s) left by the last daemon" % queued
        )
    try:
        while True:
            slept = ctx.clock.tick()
            ctx.slept = slept
            if slept:
                for rec in ctx.records.values():
                    shift_record(rec, slept)
            try:
                summary = run_pass(ctx, force_observe=ctx.clock.take_observe_only())
                ctx.pass_exc_streak = 0
            except Exception as e:  # noqa: BLE001 — SystemExit / KeyboardInterrupt still end it
                if _pass_exception(ctx, e):
                    return 1
                summary = {"open": sum(1 for r in ctx.records.values() if r.open)}
            if _restart_requested(paths):
                return (
                    0  # after this pass's save_records; launchd KeepAlive restarts us
                )
            if (
                not ctx.paths.canary
            ):  # the daemon only: a --once or test pass never pages it
                _provenance(ctx.paths, time.time())
            _band(ctx, time.time())
            _orphan_page(ctx)
            if ctx.telem is not None:
                ctx.telem.box()  # off the loop thread, ≤ 2.5 s wait, throttled on its own CPU
            rep = ctx.reporter
            hb.note_pass(rep.queued() if rep is not None else 0, clock.orphan_count())
            hb.advance()
            moving = any(
                r.open and r.phase in MOVING or r.substate == "PLANNED"
                for r in ctx.records.values()
            )
            caf.set_hold(moving)
            if moving:
                wait_for_change(paths, ctx.home, ACTIVE_FAST_S, hb, act.any_exited)
            elif summary["open"]:
                wait_for_change(paths, ctx.home, ACTIVE_S, hb, act.any_exited)
            else:
                wait_for_change(paths, ctx.home, DORMANT_S, hb, act.any_exited)
    finally:
        # W9 (A6 §2.7): flush the page outbox and release the flock — nothing else. No record is
        # saved here: a pass cut mid-way is replayed by the next daemon from its files.
        try:
            signal.signal(signal.SIGTERM, old_term)
        except (ValueError, TypeError):
            pass
        bind_child_hook(None)
        bind_steps(None)
        bind_step_hook(None)
        try:
            if ctx.reporter is not None and ctx.page_outbox:
                ctx.reporter.begin_pass(outbox=True, sends=None)
                ctx.reporter.flush_outbox(deadline=time.monotonic() + FINAL_FLUSH_S)
        except Exception:  # noqa: BLE001 — leftovers stay queued for the next daemon
            pass
        caf.close()
        hb.stop()
        lockf.close()


FINAL_FLUSH_S = (
    10.0  # daemon exit: queued pages are sent while this lasts (launchd waits 20 s)
)


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="lr_recon", description=__doc__.splitlines()[0])
    ap.add_argument(
        "--mode", choices=T.MODES, help="cap the mode (can only lower recon/mode)"
    )
    ap.add_argument(
        "--once", action="store_true", help="one pass, print the census, exit"
    )
    ap.add_argument("--root", help="reconciler state root (default LR_RECON_ROOT)")
    ap.add_argument(
        "--abandon",
        metavar="SID",
        help="give up recovering SID: the running daemon closes its record and releases it",
    )
    a = ap.parse_args(argv)
    paths = T.Paths.from_env(root=a.root)
    if a.abandon:
        if "/" in a.abandon or not a.abandon.strip():
            print("lr_recon: --abandon needs a session id", file=sys.stderr)
            return 2
        print(request_abandon(paths, a.abandon.strip()))
        return 0
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
