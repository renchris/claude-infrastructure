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
from typing import Callable, Dict, List, Optional, Sequence, Tuple

from lr_recon import store
from lr_recon import types as T

PageSink = Callable[[str], None]
MailSink = Callable[[str, str], None]

DELTA_MIN_GAP_S = 300  # §C11 DELTA: at most one per 5 minutes
REFIRE_S = 3600  # §C11 max-age pages re-fire hourly
SLO_AFTER_DEATH_S = 600  # §7.4: judged 10 minutes after the cohort's last death
SHADOW_MAX = 4 * 1024 * 1024
NOTIFY_TIMEOUT_S = 10
PAGE_TIMEOUT_S = 45  # lr-page.sh: Notification Center (10 s) + phone (20 s) + slack
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
    "HOLD:repo-bare": "held: the checkout is a bare repository",
    "HOLD:iterm": "held: an iTerm pane cannot be relaunched in place",
    "HELD:team": "held: team lead; continued in place at the reset",
    "BACKOFF": "backing off after an error",
    "PARKED-REBOOT": "parked until the machine reboots",
}
_NEXT: Dict[str, str] = {
    "HOLD-DRAFT": "send or clear the draft",
    "HOLD-BGWORK": "moves when the job ends",
    "HOLD-SUBAGENTS": "moves when the subagents finish",
    "HOLD-MENU": "close the menu in the pane",
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
    return rec.substate if rec.phase == "PRE-MOVE" else None


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


def next_action(rec: T.Record) -> str:
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
    return "the reconciler continues (%s)" % rec.phase.lower()


def max_age_deadline(rec: T.Record) -> Optional[float]:
    """Absolute time after which a WAIT/HOLD record pages (§C11 max ages). None ⇒ no max age."""
    st, w = _state(rec), rec.wait
    if rec.terminal is not None or st is None or st not in T.MAX_AGE_S:
        return None
    since = w.since if w is not None else rec.updated_at
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
    since = rec.wait.since if rec.wait else rec.updated_at
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
        members.append(
            {
                "sid": r.sid,
                "pane": list(r.pane) if r.pane else None,
                "cwd": r.cwd,
                "phase": r.phase,
                "substate": r.substate,
                "bucket": bucket(r),
                "age_s": round(now - start, 1) if start else None,
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
    paths: T.Paths, sids: Sequence[str]
) -> Dict[Tuple[str, str], Dict[str, set]]:
    """(sid, attempt) → {"launch": distinct launch-lock taker pids, "move": move-actuator spawn pids}
    from recon/launch.log. lr-fire-resume and every fenced legacy actor log their launch-lock take;
    the daemon logs each move spawn. Either set above 1 is a double typer for that attempt: two
    processes launching the session, or a second move actuator over the same attempt."""
    want, out = set(sids), {}  # type: ignore[var-annotated]
    try:
        with open(paths.launch_log, encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                t = ln.rstrip("\n").split("\t")
                if len(t) < 4 or t[1] not in want:
                    continue
                kv = dict(x.split("=", 1) for x in t[4:] if "=" in x)
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
                    key = (t[1], kv.get("attempt") or "legacy@" + t[0])
                    out.setdefault(key, {"launch": set(), "move": set()})[cls].add(
                        kv.get("pid", "?")
                    )
    except OSError:
        pass
    return out


def double_typers(paths: T.Paths, sids: Sequence[str]) -> int:
    return sum(
        1
        for v in _typers(paths, sids).values()
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


def dod_line(paths: T.Paths, records: Sequence[T.Record]) -> str:
    """The cohort's measured DoD. Short shape (every member engaged in place):
    ``ENGAGED k/n · same-window · same-uuid · double-typer · split-brain · lost-records · p95``;
    otherwise the tally shape with CLOSED / HOLD named / REPLACED-NEW-WINDOW / NOT_NEEDED."""
    n = len(records)
    sids = [r.sid for r in records]
    double = double_typers(paths, sids)
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
    doc["status"]["dod"] = dod_line(paths, records)
    store.atomic_write_json(os.path.join(paths.cohorts, cohort.cid + ".json"), doc)


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
    paths: T.Paths, now: float, records: Optional[Sequence[T.Record]] = None
) -> str:
    """One counted line for hooks/operator-readout.sh; "" when nothing is open. ``records`` lets the
    daemon pass its in-memory set: its pass writes records AFTER reporting, so a disk read here
    would render the previous pass."""
    if records is None:
        records = list(store.load_all(paths, lambda _p, _r: None).values())
    live = [r for r in records if r.open]
    if not live:
        return ""
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
    return line


class PageFailed(Exception):
    """No channel took the page; Reporter._emit counts it."""


def _run(argv: List[str], timeout: float) -> Tuple[int, str]:
    """(rc, stderr). A timeout is rc 124 and a missing binary rc 127, never an exception."""
    try:
        cp = subprocess.run(
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
        raise PageFailed("cc-notify %s rc=%d verdict=%s" % (pane, rc, verdict or "-"))


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

    def _emit(self, kind: str, cid: str, text: str, pane: Optional[str] = None) -> None:
        if self.mode == "observe":
            os.makedirs(self.paths.shadow, exist_ok=True)
            row = {
                "t": self.now(),
                "kind": kind,
                "cid": cid,
                "pane": pane,
                "text": text,
            }
            store.append_bounded(
                os.path.join(self.paths.shadow, "pages.jsonl"),
                store.dumps(row),
                SHADOW_MAX,
            )
            self._shadowed.append("%s %s" % (kind, text))
            return
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
        """§C11 Mail: one mail per cohort, only to a cc-lr requester pane."""
        latch = self._latch(cohort.cid)
        if "mail" in latch:
            return False
        latch["mail"] = self.now()
        self._save(cohort.cid, latch)
        self._emit("MAIL", cohort.cid, "%s: %s" % (self._head(cohort), text), pane=pane)
        return True

    # ── per-record pages ───────────────────────────────────────────────────────────────────────
    def immediate_pages(self, cohort: T.Cohort, rec: T.Record) -> List[str]:
        """SPLIT-BRAIN, ESCALATED, IMPOSSIBLE, HELD:team — each latched per record_id + kind."""
        kinds = []
        if rec.phase == "SPLIT-BRAIN":
            kinds.append("SPLIT-BRAIN")
        if rec.escalated:
            kinds.append("ESCALATED")
        if rec.terminal is not None and rec.terminal.outcome == "IMPOSSIBLE":
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
        since = rec.wait.since if rec.wait else rec.updated_at
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
