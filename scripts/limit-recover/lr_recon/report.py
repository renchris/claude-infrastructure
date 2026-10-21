"""The operator surface (§C11, §7.4): cohort OPEN/DELTA/CLOSE pages, immediate pages, max-age and
SLO pages, the per-cohort status file and the readout line.

Why one class holds latches on disk: a daemon restart must never re-page (§C11 "latched once"), so
every fired page is recorded in ``recon/cohorts/<cid>.pages[.<mode>].json`` before this returns.
Latches are kept per mode, so a page withheld in observe mode never suppresses the real one after
the switch to act (D6.4). Every external effect goes through the injectable ``page``/``mail`` sinks;
in mode "observe" nothing is sent — would-be pages go to ``recon/shadow/pages.jsonl`` and to
``digest()`` instead.

The default page sink (D6.5) tries the desk (``cc-notify --role desk``) and, unless that reports
``verdict=delivered``, posts through ``lr-page.sh`` (Notification Center, plus the phone when
Pushover is configured). A page counts as failed only when both fail."""

import hashlib
import json
import os
import re
import subprocess
import time
from typing import Callable, Dict, List, Optional, Sequence, Set, Tuple

from lr_recon import admit, store
from lr_recon import types as T
from lr_recon.clock import run_bounded

PageSink = Callable[[str], None]
MailSink = Callable[[str, str], None]

DELTA_MIN_GAP_S = 300  # §C11 DELTA: at most one per 5 minutes
REFIRE_S = 3600  # §C11 max-age pages re-fire hourly
SLO_AFTER_DEATH_S = 600  # §7.4: judged 10 minutes after the cohort's last death
SHADOW_MAX = 4 * 1024 * 1024
NOTIFY_TIMEOUT_S = 10
REQUESTER_MAIL_TRIES = (
    3  # a requester mail that fails (not rc 124) is retried this many passes
)
PAGE_TIMEOUT_S = 45  # lr-page.sh: Notification Center (10 s) + phone (20 s) + slack
# W9: one synchronous send a pass, pages and requester mails together: ≤ NOTIFY 10 + lr-page 45 s
SENDS_PER_PASS = 1
OUTBOX = "outbox"  # under recon/: one JSON file per latched, unsent page
OUTBOX_TRIES = (
    3  # a page whose sinks all fail is retried on this many passes, then dropped
)
_NOTIFY_VERDICT = re.compile(r"cc-notify: verdict=([A-Za-z-]+)")
GOOD = ("CLOSED", "NOT_NEEDED", "REPLACED", "REPLACED-NEW-WINDOW")

# Pages expand identifiers (§C11): the operator reads plain words, the status file keeps codes.
_SAY: Dict[str, str] = {
    "DETECTED": "detected, not yet planned",
    "PLANNED": "planned, about to move",
    "WAIT_SLOT": "waiting for a free slot on another account",
    "WAIT_RESET": "waiting for the limit to reset",
    "WAIT_DATA": "waiting for account data",
    "WAIT_CAPACITY": "waiting for spare capacity",
    "HOLD-DRAFT": "held: an unsent draft in the prompt",
    "HOLD-BGWORK": "held: a background job is still running",
    "HOLD-SUBAGENTS": "held: subagents are still running",
    "HOLD-MENU": "held: a menu is open in the pane",
    "HOLD-COMPOSER": "held: the precheck read a turn in flight or an unreadable composer",
    "HOLD-LOAD": "held: the recycle was refused for machine load",
    "UNPROMPTED": "relaunched, but its continue prompt is not yet delivered",
    "HOLD:repo-bare": "held: the checkout is a bare repository",
    "HOLD:iterm": "held: an iTerm pane cannot be relaunched in place",
    "HELD:team": "held: team lead; continued in place at the reset",
    "BACKOFF": "backing off after an error",
    "PARKED-REBOOT": "parked: planned before the machine rebooted",
}
_NEXT: Dict[str, str] = {
    "PARKED-REBOOT": "boot-resume relaunches it in resume mode; in page mode, by hand",
    "HOLD-DRAFT": "send or clear the draft",
    "HOLD-BGWORK": "moves when the job ends",
    "HOLD-SUBAGENTS": "moves when the subagents finish",
    "HOLD-MENU": "close the menu in the pane",
    "HOLD-COMPOSER": "re-probed every 2 minutes; look at the pane if it stays held",
    "HOLD-LOAD": "re-probed every 2 minutes",
    "HOLD:repo-bare": "move this session by hand",
    "HOLD:iterm": "relaunch this session by hand",
}
_IMMEDIATE: Dict[str, str] = {
    "SPLIT-BRAIN": "split brain: two live processes hold one session; the reconciler stopped",
    "ESCALATED": "escalated: automatic recovery gave up",
    "IMPOSSIBLE": "impossible: this session cannot be recovered",
    "HELD:team": "held: a team session",
    "WAKE-FAILED": "the continue at the reset could not be typed",
}
IMMEDIATE_KINDS = frozenset(
    _IMMEDIATE
)  # W9: these leave the outbox before every other send


# D3.3: --place's reasons for "no account passes the floors". Decision 3 ruled wait, so such a
# session is not waiting for a slot to free up; it waits until an account has safe room again.
_THIN = ("recovery-5h-thin", "recovery-weekly-thin")


def say(rec: T.Record) -> str:
    """The plain-words state of an open record, or '' when it has no named WAIT/HOLD state."""
    st = _state(rec) or ""
    if st == "WAIT_SLOT" and rec.wait and any(t in rec.wait.detail for t in _THIN):
        return "no account has safe room; re-checked every pass"
    return _SAY.get(st, "")


def _hm(ts: Optional[float]) -> str:
    return "?" if ts is None else time.strftime("%H:%MZ", time.gmtime(ts))


def _dur(s: float) -> str:
    s = max(0, int(s))
    if s >= 3600:
        return "%dh%02dm" % (s // 3600, s % 3600 // 60)
    return "%dm%02ds" % (s // 60, s % 60) if s >= 60 else "%ds" % s


def _state(rec: T.Record) -> Optional[str]:
    """The named WAIT/HOLD state, if any: the wait's reason, else a PRE-MOVE substate."""
    if rec.wait is not None:
        return rec.wait.reason
    if rec.substate == "UNPROMPTED":
        return "UNPROMPTED"  # W8: an owed continue has a max age in every phase (C2 E5)
    return rec.substate if rec.phase == "PRE-MOVE" else None


def _since(rec: T.Record) -> float:
    """When the record entered its named state: the wait's own stamp; for UNPROMPTED its durable
    close.unprompted_since; else (B7 D4b) the detection, never updated_at, which save_records
    rewrites every pass (a max age measured from it never came)."""
    if rec.wait is not None:
        return rec.wait.since
    if _state(rec) == "UNPROMPTED" and rec.close.get("unprompted_since") is not None:
        return float(rec.close["unprompted_since"])
    return rec.timeline.detected or rec.updated_at


def bucket(rec: T.Record) -> str:
    """One of done / escalated / held / waiting / moving — the readout's counted dispositions."""
    if rec.terminal is not None:
        return "done"
    if rec.escalated:
        return "escalated"
    st = _state(rec) or ""
    if st.startswith(("HOLD", "HELD")):
        return "held"
    if st.startswith(("WAIT", "BACKOFF", "PARKED")):
        return "waiting"
    return "moving"


def who(rec: T.Record) -> str:
    """A record has no title: name it by pane, sid8 and cwd basename (§C11 CLOSE residue)."""
    pane = "pane %d:%d, " % tuple(rec.pane) if rec.pane else ""
    base = os.path.basename(rec.cwd.rstrip("/")) or "?"
    return "session %s (%s%s)" % (rec.sid[:8], pane, base)


def _rq_key(rec: T.Record, b: str) -> str:
    """The requester-mail latch: per record, bucket and terminal time, so a fresh NOT_NEEDED
    minted under an old record_id (a later cc-lr claim) is still mailed."""
    at = int(rec.terminal.at) if rec.terminal is not None and rec.terminal.at else 0
    return "rq:%s:%s:%d" % (rec.record_id, b, at)


def _verdict_part(rec: T.Record) -> str:
    """``verdict=<OUTCOME|ESCALATED> session <sid8> (…)``: the token cc-lr requesters match on."""
    if rec.terminal is not None:
        return "verdict=%s %s at %s" % (
            rec.terminal.outcome,
            who(rec),
            _hm(rec.terminal.at),
        )
    err = " after %s" % rec.last_error.cls.lower() if rec.last_error else ""
    return "verdict=ESCALATED %s%s — next: %s" % (who(rec), err, next_action(rec))


def next_action(rec: T.Record, now: Optional[float] = None) -> str:
    """What happens next, in words. W11: with ``now`` (passed only by the DEADLINE page) an overdue
    record is prefixed "overdue since HH:MM: "; with no ``now`` there is no prefix, so the text never
    depends on the clock (F-C: a wall-clock prefix broke 5 of 57 test_report tests, measured)."""
    head = ""
    if now is not None and rec.terminal is None and admit.overdue(rec, now):
        head = "overdue since %s: " % _hm(admit.deadline_of(rec))
    return head + _next_action(rec)


def _next_action(rec: T.Record) -> str:
    if rec.terminal is not None:
        return (
            "none"
            if rec.terminal.outcome in GOOD
            else "cannot be recovered: %s" % (rec.terminal.proof or "no proof recorded")
        )
    if rec.escalated:
        return "recover by hand, or cc-lr cohort refire %s" % rec.sid[:8]
    st = _state(rec) or ""
    if st in _NEXT:
        return _NEXT[st]
    eta = rec.wait.eta if rec.wait else None
    if rec.close.get("wake_failed"):
        return "continue it by hand: %s" % rec.close["wake_failed"]
    if st == "HELD:team":
        if not eta:
            return "continued in place after the reset; paged 10 min after it if not"
        return "continued in place after %s; paged at %s if not" % (
            _hm(eta),
            _hm(eta + 600),
        )
    if st.startswith("WAIT"):
        return "wakes at %s" % _hm(eta) if eta else "the reconciler retries"
    gate = rec.close.get("admit_refused")
    if gate:
        # A standing admission refusal, by the gate's name and numbers (14233392, 2026-10-13: it
        # read "the reconciler continues" for the ten hours the restore budget refused it).
        terms = rec.close.get("admit_terms")
        since = rec.close.get("admit_refused_at")
        return "admission gate %s refuses its first turn%s%s; re-offered every pass" % (
            gate,
            " (%s)" % terms if terms else "",
            " since %s" % _hm(since) if since else "",
        )
    return "the reconciler continues (%s)" % rec.phase.lower()


def max_age_deadline(rec: T.Record) -> Optional[float]:
    """Absolute time after which a WAIT/HOLD record pages (§C11 max ages). None ⇒ no max age."""
    st, w = _state(rec), rec.wait
    if rec.terminal is not None or st is None or st not in T.MAX_AGE_S:
        return None
    since = _since(rec)
    limit = T.MAX_AGE_S[st]
    if limit is None:
        return since  # "at once": due on entry
    if st in ("WAIT_SLOT", "HELD:team") and w is not None and w.eta is not None:
        return w.eta + limit  # earliest wake / the reset, plus 10 min
    if st == "HOLD-BGWORK" and w is not None and "ship-land" in w.detail:
        limit = T.HOLD_BGWORK_SHIPLAND_MAX_AGE_S  # decision 2 (SETTLED)
    return since + limit


def max_age_due(rec: T.Record, now: float) -> bool:
    d = max_age_deadline(rec)
    return d is not None and now >= d


def _draft(rec: T.Record) -> str:
    """D6.7: the held draft, quoted, when a snapshot recovered it (the page leaves as argv)."""
    text = rec.close.get("draft_text") if rec.substate == "HOLD-DRAFT" else ""
    return ' — the draft reads: "%s"' % text if text else ""


def residue_needs(rec: T.Record, now: float) -> Optional[str]:
    """The ``cc-backlog needs`` line for human residue: a real draft or a background job held past
    its max age (§C11). The caller files it."""
    st = _state(rec)
    if st not in ("HOLD-DRAFT", "HOLD-BGWORK") or not max_age_due(rec, now):
        return None
    since = _since(rec)
    detail = " (%s)" % rec.wait.detail if rec.wait and rec.wait.detail else ""
    return "limit-recover on %s %s: %s is %s%s for %s — %s%s" % (
        rec.source_acct or "?",
        rec.scope or "?",
        who(rec),
        _SAY[str(st)][6:],
        detail,
        _dur(now - since),
        next_action(rec),
        _draft(rec),
    )


def _tally(records: Sequence[T.Record]) -> Dict[str, int]:
    out = {"moving": 0, "waiting": 0, "held": 0, "escalated": 0, "done": 0}
    for r in records:
        out[bucket(r)] += 1
    return out


def cohort_status(
    cohort: T.Cohort, records: Sequence[T.Record], now: float
) -> Dict[str, object]:
    """What ``cc-lr status --cohort`` renders (W4): per member the phase, age, attempt, last error
    class, next action and ETA."""
    members = []
    for r in sorted(records, key=lambda x: x.sid):
        start = r.wait.since if r.wait else (r.timeline.detected or r.updated_at)
        # B6 display only: the telemetry stamp of the current state and of the first attempt
        tel = r.close.get("tel") or {}
        at, first = tel.get("at"), tel.get("first")
        det = r.timeline.detected
        members.append(
            {
                "sid": r.sid,
                "pane": list(r.pane) if r.pane else None,
                "cwd": r.cwd,
                "phase": r.phase,
                "substate": r.substate,
                "bucket": bucket(r),
                "age_s": round(now - start, 1) if start else None,
                "in_state_s": round(now - float(at), 1) if at else None,
                "first_attempt_s": round(float(first) - det, 1)
                if first and det and not tel.get("pre")
                else None,
                "attempt": r.attempt,
                "last_error": r.last_error.cls if r.last_error else None,
                "next_action": next_action(r),
                "eta": r.wait.eta if r.wait else None,
                "outcome": r.terminal.outcome if r.terminal else None,
            }
        )
    return {
        "cid": cohort.cid,
        "acct": cohort.acct,
        "scope": cohort.scope,
        "at": now,
        "tally": _tally(records),
        "members": members,
    }


# ── the cohort DoD line (W5): one renderer, two shapes, the same two rig_lib.expected_line derives ──
DOD_P95_S = 120.0
_ORD = {1: "1st", 2: "2nd", 3: "3rd"}


MOVE_ROLES = ("recon-A", "recon-A-husk", "recon-B", "recon-R")


def _typers(
    paths: T.Paths,
    sids: Sequence[str],
    since: Optional[float] = None,
    records: Optional[Set[str]] = None,
) -> Dict[Tuple[str, str, str], Dict[str, set]]:
    """(sid, record, attempt) → {"launch": distinct launch-lock taker pids, "move": move-actuator
    spawn pids} from recon/launch.log. lr-fire-resume and every fenced legacy actor log their
    launch-lock take; the daemon logs each move spawn. Either set above 1 is a double typer for that
    attempt: two processes launching the session, or a second move actuator over the same attempt.
    The record is in the key because every move numbers its attempts from 1: keyed (sid, attempt),
    30c3a88d's two moves 31 h apart (hf-13384-…, hf-73036-…, one take each) read as a double
    typer (W5b2). The launch lock refuses a concurrent second take, so a split cannot hide one.
    ``since`` bounds the read to one cohort's lifetime: a row before it counts only if its record=
    is in ``records``. Unbounded, 3e929a81 joined next3-7d-1792497600 carrying two resumes of one
    old record 35 h apart (hf-52800-…, both attempt=1, both days before the cohort opened) and the
    cohort read double-typer 1 forever. An unparseable timestamp is kept, never dropped."""
    want, out = set(sids), {}  # type: ignore[var-annotated]
    try:
        with open(paths.launch_log, encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                t = ln.rstrip("\n").split("\t")
                if len(t) < 4 or t[1] not in want:
                    continue
                kv = dict(x.split("=", 1) for x in t[4:] if "=" in x)
                if since is not None and kv.get("record", "") not in (records or ()):
                    try:
                        if float(t[0]) < since:
                            continue
                    except ValueError:
                        pass
                # "inherited" is a child acting under its parent's lock: the same typer chain
                cls = (
                    "launch"
                    if t[3] == "taken"
                    else "move"
                    if t[3] == "spawn" and t[2] in MOVE_ROLES
                    else ""
                )
                if cls:
                    # a legacy actor has no attempt: each of its takes is its own key
                    key = (
                        t[1],
                        kv.get("record", ""),
                        kv.get("attempt") or "legacy@" + t[0],
                    )
                    out.setdefault(key, {"launch": set(), "move": set()})[cls].add(
                        kv.get("pid", "?")
                    )
    except OSError:
        pass
    return out


def double_typers(
    paths: T.Paths,
    sids: Sequence[str],
    since: Optional[float] = None,
    records: Optional[Set[str]] = None,
) -> int:
    return sum(
        1
        for v in _typers(paths, sids, since, records).values()
        if len(v["launch"]) > 1 or len(v["move"]) > 1
    )


def _quarantined(paths: T.Paths, sids: Sequence[str]) -> int:
    try:
        names = os.listdir(paths.quarantine)
    except OSError:
        return 0
    return sum(1 for sid in sids if any(n.startswith(sid) for n in names))


def _p95(xs: List[float]) -> float:
    xs = sorted(xs)
    return xs[max(0, int(round(0.95 * len(xs) + 0.5)) - 1)] if xs else 0.0


def dod_line(
    paths: T.Paths, records: Sequence[T.Record], opened_at: Optional[float] = None
) -> str:
    """The cohort's measured DoD. Short shape (every member engaged in place):
    ``ENGAGED k/n · same-window · same-uuid · double-typer · split-brain · lost-records · p95``;
    otherwise the tally shape with CLOSED / HOLD named / REPLACED-NEW-WINDOW / NOT_NEEDED.
    The double-typer read starts at the cohort's lifetime: its earliest member detection or its
    opening, whichever is earlier; with neither known it reads the whole log."""
    n = len(records)
    sids = [r.sid for r in records]
    bounds = [float(r.timeline.detected) for r in records if r.timeline.detected]
    if opened_at:
        bounds.append(float(opened_at))
    double = double_typers(
        paths,
        sids,
        min(bounds) if bounds else None,
        {r.record_id for r in records if r.record_id},
    )
    split = sum(1 for r in records if "SPLIT-BRAIN" in (r.close.get("seen") or []))
    lost = _quarantined(paths, sids)
    via = [r.close.get("via") for r in records]
    outcomes = [r.terminal.outcome if r.terminal else None for r in records]
    if (
        n
        and all(v == "ENGAGED" for v in via)
        and all(o in (None, "CLOSED") for o in outcomes)
    ):
        lat = [
            float(r.close.get("at", 0)) - float(r.timeline.detected or 0)
            for r in records
            if r.timeline.detected
        ]
        p95 = _p95(lat)
        tail = (
            "p95 detect→engaged <= %ds" % DOD_P95_S
            if p95 <= DOD_P95_S
            else "p95 detect→engaged = %ds (> %ds)" % (p95, DOD_P95_S)
        )
        return (
            "ENGAGED %d/%d · same-window %d/%d · same-uuid %d/%d · double-typer %d · "
            "split-brain %d · lost-records %d · %s"
            % (
                n,
                n,
                sum(1 for r in records if r.close.get("same_window")),
                n,
                sum(1 for r in records if r.close.get("same_uuid")),
                n,
                double,
                split,
                lost,
                tail,
            )
        )
    closed = [r for r in records if r.terminal and r.terminal.outcome == "CLOSED"]
    eng = sum(1 for r in closed if r.close.get("via") == "ENGAGED")
    mov = sum(1 for r in closed if r.close.get("via") == "MOVED")
    # D1.11/D4.9: continued in its own pane at the reset (named only when there is one, so every
    # cohort that has none renders exactly as before)
    inplace = sum(1 for r in closed if r.close.get("via") == "IN-PLACE")
    held = [
        r
        for r in records
        if r.open and (r.substate or "").startswith("HOLD") and r.wait
    ]
    draft = sum(1 for r in held if r.substate == "HOLD-DRAFT")
    bg = sum(1 for r in held if r.substate == "HOLD-BGWORK")
    rec_bg = sum(1 for r in closed if "HOLD-BGWORK" in (r.close.get("seen") or []))
    hold = "HOLD named %d/%d (draft %d, bgwork %d" % (len(held), n, draft, bg)
    if rec_bg:
        hold += " — the %s bgwork recovers after its job ends" % _ORD.get(
            bg + 1, "%dth" % (bg + 1)
        )
    unowned = sum(1 for r in records if r.open and r.close.get("defect"))
    return " · ".join(
        [
            "CLOSED %d/%d (ENGAGED %d, MOVED %d%s)"
            % (len(closed), n, eng, mov, ", IN-PLACE %d" % inplace if inplace else ""),
            hold + ")",
            "REPLACED-NEW-WINDOW %d" % outcomes.count("REPLACED-NEW-WINDOW"),
            "NOT_NEEDED %d" % outcomes.count("NOT_NEEDED"),
            "double-typer %d" % double,
            "split-brain %d" % split,
            "lost-records %d" % lost,
            "unowned-non-terminal %d" % unowned,
        ]
    )


def write_cohort(
    paths: T.Paths, cohort: T.Cohort, records: Sequence[T.Record], now: float
) -> None:
    """Writes ``recon/cohorts/<cid>.json``: the Cohort's own fields plus a ``status`` key, so the
    file still loads as a ``T.Cohort`` (from_dict ignores unknown keys)."""
    os.makedirs(paths.cohorts, exist_ok=True)
    doc = T.to_dict(cohort)
    doc["status"] = cohort_status(cohort, records, now)
    doc["status"]["dod"] = dod_line(paths, records, cohort.opened_at)
    store.atomic_write_json(os.path.join(paths.cohorts, cohort.cid + ".json"), doc)


def load_cohort(paths: T.Paths, cid: str) -> Optional[T.Cohort]:
    """``recon/cohorts/<cid>.json`` as a ``T.Cohort`` (its ``status`` key is ignored), or None."""
    try:
        with open(os.path.join(paths.cohorts, cid + ".json"), encoding="utf-8") as fh:
            doc = json.load(fh)
        return T.from_dict(T.Cohort, doc) if isinstance(doc, dict) else None
    except (OSError, ValueError, TypeError):
        return None


# The readout is one line: name at most three bg-held panes, count the rest.
BG_HELD_SHOWN = 3


def _bg_held(rec: T.Record) -> str:
    """`<who> pages <HH:MM> (60 min, ship-land)` for one HOLD-BGWORK record. Decision 2 (SETTLED):
    hold background work until it ends, and page at 60 min for a ship-land job, 20 min otherwise —
    so the line tells the operator WHEN the hold turns into their problem, not just that it exists."""
    d = max_age_deadline(rec)
    ship = rec.wait is not None and "ship-land" in rec.wait.detail
    limit = (
        T.HOLD_BGWORK_SHIPLAND_MAX_AGE_S if ship else T.MAX_AGE_S["HOLD-BGWORK"] or 0
    )
    return "%s pages %s (%d min%s)" % (
        who(rec),
        "?" if d is None else time.strftime("%H:%M", time.localtime(d)),
        limit // 60,
        ", ship-land" if ship else "",
    )


def readout_line(
    paths: T.Paths,
    now: float,
    records: Optional[Sequence[T.Record]] = None,
    abstain: str = "",
) -> str:
    """One counted line for hooks/operator-readout.sh; "" when nothing is open. ``records`` lets the
    daemon pass its in-memory set: its pass writes records AFTER reporting, so a disk read here
    would render the previous pass. ``abstain`` (W7a) is why this pass decided nothing; it is shown
    even with nothing open, because an abstaining census cannot know that nothing is open."""
    if records is None:
        records = list(store.load_all(paths, lambda _p, _r: None).values())
    live = [r for r in records if r.open]
    note = " · census abstained, no decisions: " + abstain if abstain else ""
    if not live:
        return "lr-recon: 0 known open" + note if abstain else ""
    t = _tally(live)
    n = len({r.cohort_id or r.sid for r in live})
    line = (
        "lr-recon: %d cohort%s open · %d moving · %d waiting · %d held · %d escalated"
        % (
            n,
            "" if n == 1 else "s",
            t["moving"],
            t["waiting"],
            t["held"],
            t["escalated"],
        )
    )
    bg = sorted(
        (r for r in live if not r.escalated and _state(r) == "HOLD-BGWORK"),
        key=lambda r: (max_age_deadline(r) or 0.0, r.sid),
    )
    for r in bg[:BG_HELD_SHOWN]:
        line += " · bg-held: " + _bg_held(r)
    if len(bg) > BG_HELD_SHOWN:
        line += " · +%d more" % (len(bg) - BG_HELD_SHOWN)
    return line + note


class PageFailed(Exception):
    """No channel took the page; Reporter._emit counts it."""


class MailUnverified(PageFailed):
    """cc-notify hit its timeout (rc 124). It writes the mailbox before its slow liveness and
    wake steps, so the line has most likely landed: latch it, never resend (a duplicate wake)."""


def _run(argv: List[str], timeout: float) -> Tuple[int, str]:
    """(rc, stderr). A timeout is rc 124 and a missing binary rc 127, never an exception."""
    try:
        cp = run_bounded(
            argv,
            timeout=timeout,
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.TimeoutExpired:
        return 124, ""
    except OSError:
        return 127, ""
    return cp.returncode, cp.stderr or ""


def notify_argv(*args: str) -> List[str]:
    # LR_NOTIFY_BIN: a canary or rig daemon pages into its own log, never the operator's inbox
    exe = os.environ.get("LR_NOTIFY_BIN") or os.path.join(
        os.environ.get("HOME", os.path.expanduser("~")), ".claude", "bin", "cc-notify"
    )
    return [exe] + list(args)


def page_argv(text: str) -> List[str]:
    # LR_PAGE_BIN: the rig's own stub; else lr-page.sh beside this package
    exe = os.environ.get("LR_PAGE_BIN") or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lr-page.sh"
    )
    return ["/bin/bash", exe, "--title", "reconciler", text]


def _cc_notify(*args: str) -> Tuple[int, str]:
    """(rc, verdict) of one cc-notify send; verdict is '' when none was printed."""
    rc, err = _run(notify_argv(*args), NOTIFY_TIMEOUT_S)
    m = _NOTIFY_VERDICT.findall(err)
    return rc, (m[-1] if m else "")


def default_page(text: str) -> None:
    """The desk first; anything short of ``verdict=delivered`` (a non-zero exit such as rc 3 for an
    unset role, or mailbox-only / unverified) also goes through lr-page.sh. Raises PageFailed only
    when neither reached anyone. The desk has been dead for weeks, so lr-page is the working leg."""
    rc, verdict = _cc_notify("--role", "desk", text)
    if rc == 0 and verdict == "delivered":
        return
    prc, _err = _run(page_argv(text), PAGE_TIMEOUT_S)
    if prc != 0:
        raise PageFailed(
            "cc-notify rc=%d verdict=%s; lr-page rc=%d" % (rc, verdict or "-", prc)
        )


def default_mail(pane: str, text: str) -> None:
    rc, verdict = _cc_notify(pane, text)
    if rc != 0:
        why = "cc-notify %s rc=%d verdict=%s" % (pane, rc, verdict or "-")
        raise MailUnverified(why) if rc == 124 else PageFailed(why)


class Reporter:
    """Latched pages for every cohort. ``failures`` counts sink errors, which are never raised."""

    def __init__(
        self,
        paths: T.Paths,
        mode: str,
        page: Optional[PageSink] = None,
        mail: Optional[MailSink] = None,
        now: Callable[[], float] = time.time,
    ) -> None:
        self.paths, self.mode, self.now = paths, mode, now
        self._page: PageSink = page or default_page
        self._mail: MailSink = mail or default_mail
        self.failures = 0
        self._shadowed: List[str] = []
        # W9 (B2 stage 1): off until the daemon's _report turns it on each pass (begin_pass), so a
        # Reporter built anywhere else sends inline exactly as before
        self.outbox = False
        self.sends_left: Optional[int] = None  # None = uncapped
        self._seq = 0

    # ── W9: the durable outbox and the per-pass send cap ─────────────────────────────────────────
    def begin_pass(self, outbox: bool, sends: Optional[int]) -> None:
        """One pass's send allowance: ``sends`` synchronous sends (pages and requester mails
        together; None = uncapped), and whether latched pages queue in ``recon/outbox/``."""
        self.outbox, self.sends_left = outbox, sends

    def _outbox_dir(self) -> str:
        return self.paths.p(OUTBOX)

    def _may_send(self) -> bool:
        return self.sends_left is None or self.sends_left > 0

    def _spend(self) -> None:
        if self.sends_left is not None:
            self.sends_left -= 1

    def queued(self) -> int:
        """Pages waiting in the outbox (heartbeat ``pages_queued``)."""
        try:
            return sum(1 for n in os.listdir(self._outbox_dir()) if n.endswith(".json"))
        except OSError:
            return 0

    def _enqueue(self, kind: str, cid: str, text: str, pane: Optional[str]) -> None:
        """Written (atomically) before any send: a kill between latch and send no longer loses the
        page — the next daemon finds it here. At least once: a kill mid-send may repeat it."""
        self._seq += 1
        prio = 0 if (kind in IMMEDIATE_KINDS or cid == "_daemon") else 1
        t = self.now()
        name = "%d-%017.6f-%d-%d.json" % (prio, t, os.getpid(), self._seq)
        row = {"t": t, "kind": kind, "cid": cid, "text": text, "pane": pane, "tries": 0}
        d = self._outbox_dir()
        os.makedirs(d, exist_ok=True)
        store.atomic_write_json(os.path.join(d, name), row)

    def flush_outbox(
        self, immediate_only: bool = False, deadline: Optional[float] = None
    ) -> int:
        """Send queued pages oldest first within priority (immediate kinds first) while the pass's
        send allowance lasts and, when given, monotonic ``deadline`` has not passed. A file is
        unlinked after its sink returns; a failed send stays queued and is retried on later passes,
        then dropped at OUTBOX_TRIES with an event. Observe mode sends nothing. Returns sends."""
        if self.mode == "observe":
            return 0
        d = self._outbox_dir()
        try:
            names = sorted(n for n in os.listdir(d) if n.endswith(".json"))
        except OSError:
            return 0
        sent = 0
        for name in names:
            if immediate_only and not name.startswith("0-"):
                break
            if not self._may_send():
                break
            if deadline is not None and time.monotonic() >= deadline:
                break
            path = os.path.join(d, name)
            try:
                with open(path, encoding="utf-8") as fh:
                    row = json.load(fh)
                if not isinstance(row, dict):
                    raise ValueError("not an object")
            except OSError:
                continue  # gone (another flush took it) or unreadable now: next pass
            except ValueError:
                store._unlink(path)
                self.failures += 1
                continue
            self._spend()
            pane = row.get("pane")
            try:
                if pane is not None:
                    self._mail(str(pane), str(row.get("text", "")))
                else:
                    self._page(str(row.get("text", "")))
            except Exception:  # noqa: BLE001 — a failed page must never stop the daemon
                self.failures += 1
                row["tries"] = int(row.get("tries", 0) or 0) + 1
                if row["tries"] >= OUTBOX_TRIES:
                    store._unlink(path)
                    self._event(
                        "page-gave-up",
                        detail="%s %s"
                        % (row.get("kind", "?"), str(row.get("text", ""))[:160]),
                    )
                else:
                    try:
                        store.atomic_write_json(path, row)
                    except OSError:
                        pass
                continue
            store._unlink(path)
            sent += 1
        return sent

    # ── latches ────────────────────────────────────────────────────────────────────────────────
    def _latch_path(self, cid: str) -> str:
        # Keyed by mode (D6.4). observe keeps the historical name: every latch on disk today was
        # written by the observe-mode daemon, so act must not read that file.
        suffix = "" if self.mode == "observe" else "." + self.mode
        return os.path.join(self.paths.cohorts, (cid or "_") + ".pages%s.json" % suffix)

    def _latch(self, cid: str) -> Dict[str, object]:
        try:
            with open(self._latch_path(cid), encoding="utf-8") as fh:
                data = json.load(fh)
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def _save(self, cid: str, latch: Dict[str, object]) -> None:
        os.makedirs(self.paths.cohorts, exist_ok=True)
        store.atomic_write_json(self._latch_path(cid), latch)

    def _shadow(self, kind: str, cid: str, text: str, pane: Optional[str]) -> None:
        os.makedirs(self.paths.shadow, exist_ok=True)
        row = {"t": self.now(), "kind": kind, "cid": cid, "pane": pane, "text": text}
        store.append_bounded(
            os.path.join(self.paths.shadow, "pages.jsonl"), store.dumps(row), SHADOW_MAX
        )
        self._shadowed.append("%s %s" % (kind, text))

    def _send_mail(self, cid: str, addr: str, text: str) -> str:
        """One mail through self._mail, NOT _emit (which swallows the failure the caller must
        latch on): "sent" | "unverified" (rc 124) | "failed" | "shadowed" (observe mode)."""
        if self.mode == "observe":
            self._shadow("MAIL", cid, text, addr)
            return "shadowed"
        try:
            self._mail(addr, text)
        except MailUnverified:
            return "unverified"
        except Exception:  # noqa: BLE001 — a failed mail must never stop the daemon
            self.failures += 1
            return "failed"
        return "sent"

    def _event(self, ev: str, sid: str = "", rid: str = "", detail: str = "") -> None:
        try:
            os.makedirs(os.path.dirname(self.paths.events), exist_ok=True)
            store.append_event(
                self.paths,
                T.Event(t=self.now(), ev=ev, sid=sid, record_id=rid, detail=detail),
            )
        except OSError:
            self.failures += 1  # a lost event row must never block the latch after it

    def _emit(self, kind: str, cid: str, text: str, pane: Optional[str] = None) -> None:
        if self.mode == "observe":
            self._shadow(kind, cid, text, pane)
            return
        if self.outbox:
            try:
                self._enqueue(kind, cid, text, pane)
                return
            except OSError:
                pass  # an unwritable outbox must not lose the page: send it inline
        try:
            if pane is not None:
                self._mail(pane, text)
            else:
                self._page(text)
        except Exception:  # noqa: BLE001 — a failed page must never stop the daemon
            self.failures += 1

    def _once(self, cid: str, key: str, kind: str, text: str) -> Optional[str]:
        latch = self._latch(cid)
        if key in latch:
            return None
        latch[key] = self.now()
        self._save(cid, latch)
        self._emit(kind, cid, text)
        return text

    def daemon_page(self, kind: str, text: str) -> None:
        """A page about the daemon itself, not a cohort (band.py's priority check). Same sinks and
        the same observe-mode shadowing as every other page; the caller latches it."""
        self._emit(kind, "_daemon", text)

    def digest(self) -> str:
        """Observe mode's replacement for paging: every would-be page since the last digest."""
        rows, self._shadowed = self._shadowed, []
        if not rows:
            return ""
        return "\n".join(["lr-recon observe: %d page(s) withheld" % len(rows)] + rows)

    # ── cohort pages ───────────────────────────────────────────────────────────────────────────
    @staticmethod
    def _head(cohort: T.Cohort) -> str:
        return "%s %s" % (cohort.acct, cohort.scope)

    @staticmethod
    def _shape(records: Sequence[T.Record]) -> str:
        # (sid, phase, substate) plus the outcome: a member going terminal is a disposition change.
        rows = sorted(
            (r.sid, r.phase, r.substate or "", r.terminal.outcome if r.terminal else "")
            for r in records
        )
        return hashlib.sha1(store.dumps(rows).encode("utf-8")).hexdigest()[:16]

    def open_page(
        self,
        cohort: T.Cohort,
        records: Sequence[T.Record],
        placements: Optional[Dict[str, T.Placement]] = None,
        working: int = 0,
    ) -> Optional[str]:
        placements = placements or {}
        kinds = [r.kind for r in records]
        parts = [
            "%s LIMITED (%s) until %s"
            % (cohort.acct, cohort.scope, _hm(cohort.resets_at)),
            "%d blocked, %d idle" % (kinds.count("limited"), kinds.count("idle"))
            + (", %d working (expected to die later)" % working if working else ""),
        ]
        moves: Dict[str, Tuple[int, int]] = {}
        waits: List[T.Record] = []
        reasons: List[str] = []
        for r in records:
            p = placements.get(r.sid)
            acct = r.target_acct or (p.acct if p else None)
            if acct and r.wait is None:
                n, w = moves.get(acct, (0, 0))
                moves[acct] = (n + 1, w + (r.weight or (p.weight if p else 1)))
                continue
            waits.append(r)
            why = (p.reason if p and p.reason else "") or (
                r.wait.detail if r.wait else ""
            )
            if why and why not in reasons:
                reasons.append(why)
        parts += [
            "%s←%d (weight %d)" % (a, n, w) for a, (n, w) in sorted(moves.items())
        ]
        if waits:
            etas = [r.wait.eta for r in waits if r.wait and r.wait.eta]
            parts.append(
                "%d WAITING%s%s"
                % (
                    len(waits),
                    " (%s)" % "; ".join(reasons[:3]) if reasons else "",
                    " earliest wake %s" % _hm(min(etas)) if etas else "",
                )
            )
        text = " · ".join(parts)
        fired = self._once(cohort.cid, "open", "OPEN", text)
        if fired is not None:
            latch = self._latch(cohort.cid)
            latch["delta"] = {"at": None, "hash": self._shape(records)}
            self._save(cohort.cid, latch)
        return fired

    def delta_page(
        self, cohort: T.Cohort, records: Sequence[T.Record]
    ) -> Optional[str]:
        latch, h, now = self._latch(cohort.cid), self._shape(records), self.now()
        last = latch.get("delta") if isinstance(latch.get("delta"), dict) else {}
        assert isinstance(last, dict)
        if last.get("hash") == h:
            return None
        at = last.get("at")
        if isinstance(at, (int, float)) and now - at < DELTA_MIN_GAP_S:
            return None  # coalesced: the change stays pending until the window opens
        t = _tally(records)
        text = (
            "%s cohort update: %d members · %d moving · %d waiting · %d held · %d escalated · %d done"
            % (
                self._head(cohort),
                len(records),
                t["moving"],
                t["waiting"],
                t["held"],
                t["escalated"],
                t["done"],
            )
        )
        latch["delta"] = {"at": now, "hash": h}
        self._save(cohort.cid, latch)
        self._emit("DELTA", cohort.cid, text)
        return text

    def close_page(
        self, cohort: T.Cohort, records: Sequence[T.Record]
    ) -> Optional[str]:
        good = [
            r for r in records if r.terminal is not None and r.terminal.outcome in GOOD
        ]
        head = "%s cohort closed: %d/%d" % (self._head(cohort), len(good), len(records))
        if len(good) == len(records):
            end = max([r.terminal.at for r in good if r.terminal] + [cohort.opened_at])
            text = "%s in %s" % (head, _dur(end - cohort.opened_at))
        else:
            rest = [r for r in records if r not in good]
            text = (
                head
                + "; residue: "
                + "; ".join(
                    "%s — %s — next: %s" % (who(r), self._reason(r), next_action(r))
                    for r in rest
                )
            )
        return self._once(cohort.cid, "close", "CLOSE", text)

    @staticmethod
    def _reason(r: T.Record) -> str:
        if r.terminal is not None:
            return "outcome %s" % r.terminal.outcome.lower()
        if r.escalated:
            return "escalated" + (
                " after %s" % r.last_error.cls.lower() if r.last_error else ""
            )
        st = _state(r)
        return say(r) or "in phase %s" % r.phase.lower()

    def mail_requester(self, cohort: T.Cohort, pane: str, text: str) -> bool:
        """§C11 Mail: one mail per cohort, only to a cc-lr requester pane. Latched only once
        the send succeeded: latching first lost a failed mail for good."""
        if "mail" in self._latch(cohort.cid):
            return False
        text = "%s: %s" % (self._head(cohort), text)
        if self._send_mail(cohort.cid, pane, text) == "failed":
            return False
        latch = self._latch(cohort.cid)
        latch["mail"] = self.now()
        self._save(cohort.cid, latch)
        return True

    def requester_mails(
        self, records: Sequence[T.Record], live: Set[str], held: Set[str]
    ) -> int:
        """Decision 55dbe05de6e3: the cc-lr requester of a record that reached done or escalated
        gets ONE mail per pass naming every such record, addressed by its session id (the box
        mailbox-drain and cc-await-ping read; a pane number can be reused). No mail to the subject
        itself or its pane. While the requester is not live, nothing is latched (one
        requester-not-live event); while it is ``held`` (capped, busy in a record of its own, or
        IMPOSSIBLE), nothing is sent or latched. Latched after rc 0 or rc 124 (sent-unverified);
        any other failure retries next pass, at most REQUESTER_MAIL_TRIES times. Returns mails sent."""
        due: Dict[str, List[Tuple[T.Record, str]]] = {}
        for r in records:
            req, b = r.requester_sid, bucket(r)
            if not req or b not in ("done", "escalated") or req == r.sid:
                continue
            if r.pane and r.requester_pane == str(r.pane[1]):
                continue
            latch, key = self._latch(r.cohort_id), _rq_key(r, b)
            if key in latch:
                continue
            if req not in live:
                nl = "rq-nl:%s:%s" % (r.record_id, req[:8])
                if nl not in latch:
                    latch[nl] = self.now()
                    self._save(r.cohort_id, latch)
                    self._event("requester-not-live", r.sid, r.record_id, req)
                continue
            if req not in held:
                due.setdefault(req, []).append((r, key))
        sent = 0
        for req, items in sorted(due.items()):
            if self.mode != "observe" and not self._may_send():
                break  # W9: this pass's send is spent; unlatched, so a later pass mails it
            parts = [_verdict_part(r) for r, _k in items]
            text = (
                "lr-recon: recovery verdict for %d session(s) — %s — detail: cc-lr status %s"
                % (
                    len(items),
                    " · ".join(parts),
                    items[0][0].sid[:8],
                )
            )
            res = self._send_mail(items[0][0].cohort_id, req, text)
            if res != "shadowed":
                self._spend()
            if res == "unverified":
                self._event("requester-mail-unverified", req, detail=text[:200])
            for r, key in items:
                latch = self._latch(r.cohort_id)
                if res == "failed":
                    tries = int(latch.get("rq-try:" + key, 0) or 0) + 1
                    latch["rq-try:" + key] = tries
                    if tries >= REQUESTER_MAIL_TRIES:
                        latch[key] = self.now()
                        self._event("requester-mail-gave-up", r.sid, r.record_id, req)
                else:
                    latch[key] = self.now()
                self._save(r.cohort_id, latch)
            sent += res != "failed"
        return sent

    # ── per-record pages ───────────────────────────────────────────────────────────────────────
    def immediate_pages(self, cohort: T.Cohort, rec: T.Record) -> List[str]:
        """SPLIT-BRAIN, ESCALATED, IMPOSSIBLE, HELD:team — each latched per record_id + kind."""
        kinds = []
        if rec.phase == "SPLIT-BRAIN":
            kinds.append("SPLIT-BRAIN")
        if rec.escalated:
            kinds.append("ESCALATED")
        # a census-made IMPOSSIBLE is paged by unrecoverable_page, once per cohort
        census_made = bool(rec.close.get("impossible"))
        if (
            rec.terminal is not None
            and rec.terminal.outcome == "IMPOSSIBLE"
            and not census_made
        ):
            kinds.append("IMPOSSIBLE")
        if _state(rec) == "HELD:team":
            kinds.append("HELD:team")
        if rec.open and rec.close.get("wake_failed"):
            kinds.append("WAKE-FAILED")  # D4.9 step 6: paged once, never retyped
        out = []
        for k in kinds:
            extra = (
                " until the reset at %s" % _hm(rec.wait.eta if rec.wait else None)
                if k == "HELD:team"
                else ""
            )
            text = "%s: %s — %s%s — next: %s" % (
                self._head(cohort),
                who(rec),
                _IMMEDIATE[k],
                extra,
                next_action(rec),
            )
            if self._once(cohort.cid, "imm:%s:%s" % (rec.record_id, k), k, text):
                out.append(text)
        return out

    def unrecoverable_page(
        self, cohort: T.Cohort, records: Sequence[T.Record]
    ) -> Optional[str]:
        """One page per cohort for the limited sessions the census itself found unrecoverable
        (``census.impossible_record``: headless, cwd gone), never one per death: a single limit
        can stop many headless holders at once, and a page that always fires is ignored (lead
        ruling, W7h). It names every such member and their count; a later member re-sends the
        whole list, at most once per DELTA_MIN_GAP_S, and an unchanged list never re-sends."""
        recs = sorted(
            (r for r in records if r.close.get("impossible")), key=lambda r: r.sid
        )
        if not recs:
            return None
        sids = [r.sid for r in recs]
        latch, now = self._latch(cohort.cid), self.now()
        last = latch.get("unrecoverable")
        last = last if isinstance(last, dict) else {}
        if last.get("sids") == sids:
            return None
        at = last.get("at")
        if isinstance(at, (int, float)) and now - at < DELTA_MIN_GAP_S:
            return None  # coalesced: the new member is named when the window opens
        text = (
            "%s: %d limited session(s) cannot be recovered here: %s — next: relaunch by hand"
            % (
                self._head(cohort),
                len(recs),
                "; ".join("%s — %s" % (who(r), r.close["impossible"]) for r in recs),
            )
        )
        latch["unrecoverable"] = {"at": now, "sids": sids}
        self._save(cohort.cid, latch)
        self._emit("IMPOSSIBLE", cohort.cid, text)
        return text

    def max_age_page(self, cohort: T.Cohort, rec: T.Record) -> Optional[str]:
        """Pages once a WAIT/HOLD record passes its max age, then re-fires hourly (§C11)."""
        now = self.now()
        if not max_age_due(rec, now):
            return None
        st = str(_state(rec))
        key = "age:%s:%s" % (rec.record_id, st)
        latch = self._latch(cohort.cid)
        last = latch.get(key)
        if isinstance(last, (int, float)) and now - last < REFIRE_S:
            return None
        since = _since(rec)
        text = "%s: %s — %s for %s, past its maximum age — next: %s%s" % (
            self._head(cohort),
            who(rec),
            say(rec) or st,
            _dur(now - since),
            next_action(rec),
            _draft(rec),
        )
        latch[key] = now
        self._save(cohort.cid, latch)
        self._emit("MAX-AGE", cohort.cid, text)
        return text

    # ── W11 (B3) pages: each latched, so each fires once (then hourly where stated) ─────────────
    def deadline_page(
        self, cohort: T.Cohort, records: Sequence[T.Record], live: Set[str]
    ) -> Optional[str]:
        """ONE page per cohort (F-D: per-record pages ran N × 55 s in one pass) for its limited
        members overdue past deadline + W_hard and not in a live attempt (``live`` = sids with a
        live actuator), then hourly. A member is left out when another page owns it (F-E): any
        ``age:<record_id>:*`` latch or a close.hold_since (MAX-AGE), ESCALATED, PARKED-REBOOT
        (boot-resume owns it, for days), wake_failed (WAKE-FAILED), plan_only and a cohort_exit stay."""
        now = self.now()
        latch = self._latch(cohort.cid)
        rows = []
        for r in sorted(records, key=lambda x: x.sid):
            if (
                r.kind != "limited"
                or not r.open
                or r.escalated
                or r.phase in ("ENGAGED", "MOVED")
                or r.sid in live
                or r.plan_only
                or r.substate == "PARKED-REBOOT"
                or r.close.get("wake_failed")
                or r.close.get("cohort_exit")
                or r.close.get("hold_since")
                or any(str(k).startswith("age:%s:" % r.record_id) for k in latch)
            ):
                continue
            d = admit.deadline_of(r)
            if d is None or now < d + admit.DEADLINE_HARD_S:
                continue
            err = r.last_error
            rows.append(
                "%s — overdue since %s (detected %s); soft gates bypassed; blocked by %s — next: %s"
                % (
                    who(r),
                    _hm(d),
                    _hm(r.timeline.detected),
                    r.close.get("deadline_hold")
                    or (
                        "%s: %s" % (err.cls.lower(), err.detail[:80])
                        if err
                        else "nothing recorded"
                    ),
                    next_action(r, now),
                )
            )
        if not rows:
            return None
        last = latch.get("deadline")
        if isinstance(last, (int, float)) and now - last < REFIRE_S:
            return None
        text = "%s: %d limited session(s) past their deadline: %s" % (
            self._head(cohort),
            len(rows),
            "; ".join(rows),
        )
        latch["deadline"] = now
        self._save(cohort.cid, latch)
        self._emit("DEADLINE", cohort.cid, text)
        return text

    def drip_page(self, cohort: T.Cohort) -> Optional[str]:
        """Architecture C6: the drip "admits one per 30 s AND pages" — once per cohort."""
        return self._once(
            cohort.cid,
            "drip",
            "DRIP",
            "%s: the capacity probe refused %d passes running; the drip now admits one first turn "
            "per %ds — next: read cc-lr status --cohort; nothing to do unless it stands"
            % (self._head(cohort), admit.DRIP_AFTER, int(admit.DRIP_EVERY_S)),
        )

    def backoff_page(self, cohort: T.Cohort, rec: T.Record) -> Optional[str]:
        """classify's BACKOFF_PAGE (the 6th TRANSIENT, then every PAGE_EVERY), once per count."""
        n = rec.close.get("backoff_page")
        if not n or not rec.open:
            return None
        err = rec.last_error
        return self._once(
            cohort.cid,
            "backoff:%s:%s" % (rec.record_id, n),
            "BACKOFF",
            "%s: %s — %s transient failures running%s — next: %s"
            % (
                self._head(cohort),
                who(rec),
                n,
                ", last: %s" % err.detail[:120] if err else "",
                next_action(rec),
            ),
        )

    def attempt_page(
        self, cohort: T.Cohort, rec: T.Record, pid: int, lstart: str, age_s: float
    ) -> Optional[str]:
        """W11 lever 9: an actuator alive past T_att pages once and is NOT killed."""
        return self._once(
            cohort.cid,
            "tatt:%s:%d:%s" % (rec.record_id, pid, lstart),
            "T-ATT",
            "%s: %s — its actuator pid %d has run %s, past the %ds attempt budget; not killed, "
            "its boot slot stays held while it lives — next: %s"
            % (
                self._head(cohort),
                who(rec),
                pid,
                _dur(age_s),
                int(admit.T_ATT_S),
                next_action(rec),
            ),
        )

    def unknown_exit_page(self, cohort: T.Cohort, rec: T.Record) -> Optional[str]:
        """W11 lever 10: one page per unknown-exit re-offer (it replaced a RECON-DEFECT every pass)."""
        n = rec.close.get("unknown_exit_retries")
        if not n:
            return None
        return self._once(
            cohort.cid,
            "unk:%s:%s" % (rec.record_id, n),
            "RECON-DEFECT",
            "%s: %s — its move exited with no code and no NOTMOVED verdict; re-offered as transient "
            "retry %s (the re-offer's safety is a hypothesis) — next: %s"
            % (self._head(cohort), who(rec), n, next_action(rec)),
        )

    def slo_page(self, cohort: T.Cohort, records: Sequence[T.Record]) -> Optional[str]:
        """§7.4: 10 minutes after the last death every member is CLOSED or in a named WAIT/HOLD
        within its max age; otherwise page once, naming the members that are neither."""
        now = self.now()
        deaths = [r.timeline.detected for r in records if r.timeline.detected]
        if now < max(deaths + [cohort.opened_at]) + SLO_AFTER_DEATH_S:
            return None
        bad = [
            r
            for r in records
            if r.terminal is None
            and (bucket(r) not in ("waiting", "held") or max_age_due(r, now))
        ]
        if not bad:
            return None
        text = "%s cohort missed its 10-minute target: %s" % (
            self._head(cohort),
            "; ".join(
                "%s — %s — next: %s" % (who(r), self._reason(r), next_action(r))
                for r in bad
            ),
        )
        return self._once(cohort.cid, "slo", "SLO", text)
