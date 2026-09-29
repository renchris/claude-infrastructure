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
    evidence,
    observe,
    plan,
    report,
    store,
    transcript,
)
from lr_recon import facts as F
from lr_recon import types as T
from lr_recon.admit import Admission, BootSlots
from lr_recon.clock import Caffeinate, Clock, Heartbeat, shift_record

MOVING = ("TRANSPLANTED", "EXITING", "HUSK-RETIRED", "EXITED", "RELAUNCHED")
SENTINEL_S = 300.0  # §3 step 13: CLOSED after the 5-minute sentinel
ACTIVE_FAST_S, ACTIVE_S, DORMANT_S = 3.0, 5.0, 20.0
RESTART_PAGE_WINDOW_S = 600.0
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


def _cfg_of(home: str) -> Any:
    try:
        with open(
            os.path.join(home, ".claude", "accounts.json"), encoding="utf-8"
        ) as fh:
            amap = {
                a["name"]: os.path.expanduser(a["config_dir"])
                for a in json.load(fh).get("accounts", [])
            }
    except (OSError, ValueError, KeyError, AttributeError):
        amap = {}
    return lambda acct: amap.get(acct, "")


# ── one pass ────────────────────────────────────────────────────────────────────────────────────


def _facts(ctx: Ctx, snap: T.Snapshot, now: float) -> Dict[str, T.Fact]:
    """Step (a): census death rows add facts; expiry and contradiction from the census's turns."""
    paths = ctx.paths
    for s in snap.sessions.values():
        f = (
            F.fact_from_death(s.acct, s.sid, s.transcript.last or {}, now, "census")
            if s.acct and (s.transcript.last or {}).get("limit")
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
    stale = census.stale_reconcile(ctx.records, reqs, snap, ctx.clock.boottime(), now)
    stale_sids = {sid for sid, verdict, _r in stale if verdict == "NOT_NEEDED"}
    for sid, verdict, reason in stale:
        _event(paths, "stale", sid, detail="%s %s" % (verdict, reason))
        if mode == "act" and sid in req_by_sid and verdict == "NOT_NEEDED":
            store.claim_request(paths, req_by_sid[sid], verdict, reason)
    autorecover = os.path.exists(paths.autorecover_on)
    buckets: List[T.Bucket] = []
    for s in snap.sessions.values():
        if not (
            census.in_scope(s, facts, now)
            or s.sid in req_by_sid
            or s.sid in ctx.records
        ):
            continue
        b = census.bucket(s, snap, facts, now)
        buckets.append(b)
        if b.name not in RECORD_TYPES or s.sid in stale_sids:
            continue
        req = req_by_sid.get(s.sid)
        origin = req.origin if req else ("fanout" if b.kind == "idle" else "census")
        pane = snap.panes.get("%d:%d" % s.pane) if s.pane else None
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


def _derive(ctx: Ctx, snap: T.Snapshot, now: float) -> None:
    """Level-triggered confirm (§3 step 10): the derived phase replaces the cached one."""
    for rec in ctx.records.values():
        if not rec.open:
            continue
        act.adopt(rec, snap)
        act.prune_dead(rec, snap)
        out = evidence.derive(ctx.paths, rec, snap)
        res = out["result"]
        assert isinstance(res, T.PhaseResult)
        rec.phase = res.phase
        if res.phase != "PRE-MOVE" or res.substate == "HOLD-MENU":
            rec.substate = res.substate
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
            action="C" if rec.phase == "RELAUNCHED" else "",
        )
        which = act.choose(res, rec)
        if which is None:
            continue
        ok, why = act.may_actuate(
            ctx.paths, mode, rec, which, snap, now, wake_ok, running, act.workers_cap()
        )
        if not ok:
            continue
        argv = _command(ctx, rec, which)
        if not argv:
            continue
        pane = snap.panes.get("%d:%d" % rec.pane) if rec.pane else None
        act.spawn(
            ctx.paths,
            rec,
            which,
            argv,
            act.actuator_env(rec, ctx.paths, pane.sock if pane else ""),
            now,
        )
        running += 1
        n += 1
    return n


def _command(ctx: Ctx, rec: T.Record, which: str) -> List[str]:
    if which == "A":
        return act.cmd_move(
            rec,
            os.path.join(ctx.paths.facts, "%s.%s.json" % (rec.source_acct, rec.scope)),
        )
    if which == "A-husk":
        return act.cmd_husk(rec)
    if which == "B":
        ident = os.path.join(ctx.paths.sessions, rec.sid + ".identity.json")
        store.atomic_write_json(ident, T.to_dict(rec.identity))
        return act.cmd_relaunch_at_shell(rec, ident)
    if which == "UNCONFIRM":
        return act.cmd_transplant(rec, "unconfirm")
    if which == "R":
        return act.cmd_replace(rec)
    if which in ("C", "C-retry"):
        rec.submit_token = act.new_token()
        payload = os.path.join(ctx.paths.sessions, rec.sid + ".prompt.txt")
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


def _invariant(ctx: Ctx, snap: T.Snapshot) -> int:
    """§4.4: every non-terminal record has a live process, a next_eligible_at, or a named wait."""
    bad = 0
    for r in ctx.records.values():
        if (
            not r.open
            or r.phase == "PRE-MOVE"
            and r.substate in ("DETECTED", "PLANNED")
        ):
            continue
        if act.live_procs(r, snap) or r.next_eligible_at or (r.wait and r.wait.reason):
            continue
        if r.phase in ("ENGAGED", "MOVED"):
            continue
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
    mode = "observe" if force_observe else read_mode(paths, ctx.mode_cap)
    now = time.time()
    snap = observe.observe(paths, ctx.home, transcript_fn=transcript.observe, now=now)
    ctx.degraded_streak = ctx.degraded_streak + 1 if snap.degraded else 0
    facts = _facts(ctx, snap, now)
    reqs = store.list_requests(paths)
    buckets, stale = _census(ctx, snap, facts, reqs, mode, now)
    _derive(ctx, snap, now)
    placed = _plan(ctx, snap, facts, mode, now)
    spawned = 0
    if mode == "act" and os.path.exists(paths.recon_on):
        _own_and_charge(ctx, now)
        spawned = _dispatch(ctx, snap, mode, now)
        ctx.actuations += spawned
    _report(ctx, mode, now)
    defects = _invariant(ctx, snap)
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
    caf = Caffeinate()
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
