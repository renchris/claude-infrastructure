"""settle.py: what the pass learns BETWEEN actuations (§7.2, §4.1) — the W5 integration glue.

Three things W3 built the parts for and nothing called, found by the W5 rig's first act-mode run:

* **An actuator's exit is read.** A dead actuator's exit code (kept by ``act.reap_children``) and the
  tail of its actlog go through the NOTMOVED map (a precheck refusal names its reason) or, failing
  that, ``classify.classify``; the class then sets the record's substate, wait, backoff or terminal.
  Without this a refused move was re-spawned every 3 s pass, forever: nothing moved the record out
  of PLANNED and no backoff was ever set.
* **A held record can clear.** ``census.upsert`` never re-buckets an open record, so HOLD-BGWORK
  stayed held after the job ended and HOLD-FOCUS after focus moved. ``rebucket`` lets the census
  own the substates it produced, while no actuator is live; ``reprobe`` retries a hold the census
  cannot see (a draft) every ``REPROBE_S`` through the precheck, which refuses before anything
  irreversible.
* **confirm_len is read from the transplant tombstone** (``<sid>.HANDOFF.json``), which is where
  lr-transplant writes it; ENGAGED (§4.2 row 5) cannot hold without it.
"""

import json
import os
import re
from typing import Dict, List, Optional, Tuple

from lr_recon import classify
from lr_recon import types as T
from lr_recon.evidence import transcript_path

REPROBE_S = 120.0
WAIT_RETRY_S = 60.0
MOVE_ACTUATORS = ("A", "A-husk", "B", "R")
TAIL_BYTES = 16 * 1024
# Substates the census derives from a bucket; it may rewrite them while nothing is in flight.
CENSUS_OWNED = (
    "DETECTED",
    "WAIT_RESET",
    "HOLD-FOCUS",
    "HOLD-BGWORK",
    "HOLD-SUBAGENTS",
    "HOLD:iterm",
    "HELD:team",
    "LAUNCHER-ROOTED",
    "SPLIT-BRAIN",
)
BUCKET_SUBSTATE = {
    "LIMITED": "DETECTED",
    "STAY": "WAIT_RESET",
    "IDLE-ELIGIBLE": "DETECTED",
}
# Holds the census cannot observe: re-probed through the actuator's own precheck.
REPROBED = ("HOLD-DRAFT", "HOLD-MENU", "HOLD-COMPOSER")
_REASON = re.compile(r"(?:PRECHECK |verdict: )(?:HELD|REFUSED):([A-Za-z:-]+)")
# handoff-fire's held-after-confirm reasons (recycle-held-<reason>) → the PRE-MOVE hold they mean
RCY_HELD_SUB = {
    "draft": "HOLD-DRAFT",
    "bg-work": "HOLD-BGWORK",
    "bgwork": "HOLD-BGWORK",
    "subagents": "HOLD-SUBAGENTS",
    "focused": "HOLD-FOCUS",
}
_STRANDED = re.compile(r"^lr-handoff \S+: verdict=STRANDED\b", re.M)
_HOLD_SUB = (
    (re.compile(r"\bdraft\b", re.I), "HOLD-DRAFT"),
    (re.compile(r"bg-work|background work", re.I), "HOLD-BGWORK"),
    (re.compile(r"subagent", re.I), "HOLD-SUBAGENTS"),
    (re.compile(r"\bmenu\b", re.I), "HOLD-MENU"),
)


def actlog(paths: T.Paths, rec: T.Record, actuator: str) -> str:
    return os.path.join(
        paths.p("actlogs"), "%s.%d.%s.log" % (rec.sid[:8], rec.attempt, actuator)
    )


def tail(path: str, n: int = TAIL_BYTES) -> str:
    try:
        with open(path, "rb") as fh:
            size = os.fstat(fh.fileno()).st_size
            fh.seek(max(0, size - n))
            return fh.read().decode("utf-8", "replace")
    except OSError:
        return ""


def _hold_substate(text: str) -> str:
    for rx, sub in _HOLD_SUB:
        if rx.search(text):
            return sub
    return "HOLD-COMPOSER"


def outcome(rec: T.Record, rc: Optional[int], text: str) -> Tuple[str, str, str]:
    """(disposition, substate, reason). A precheck's named refusal wins over the free-text classes,
    because it is the actuator's own verdict on why nothing was done."""
    if _STRANDED.search(text):
        # lr-handoff's own verdict: the transplant is DONE and the relaunch did not verify. The
        # session now lives on the target, so no free-text class may close it (W5 rig: a usage dump
        # above the verdict said "headless" and scored IMPOSSIBLE, abandoning a moved session). A
        # retry is safe; the next pass derives the husk from disk and the phase table rescues it.
        return "TRANSIENT", "", "stranded: transplant done, relaunch not verified"
    reasons = _REASON.findall(text)
    if reasons and rec.phase == "PRE-MOVE":
        reason = reasons[-1].rstrip(":")
        disp, sub = classify.map_notmoved(reason, rec.kind)
        if disp == "NOT_NEEDED" and rec.close.get("hop"):
            # a hop's source is the failed TARGET: "not limited" there is a gate to wait out,
            # never proof the session is fine (it is still stuck on its last error)
            disp, sub = "WAIT", "WAIT_SLOT"
        if disp == "DETERMINISTIC" and "unreadable" in reason:
            disp = "TRANSIENT"  # a screen we could not read is a retry, never a verdict
        return disp, sub, reason
    last = "\n".join(text.splitlines()[-40:])
    return classify.classify(last, -1 if rc is None else rc), "", ""


def settle_exit(
    rec: T.Record, pr: T.ProcRole, rc: Optional[int], text: str, now: float
) -> str:
    """Apply one dead actuator's exit to its record. Returns the event detail ('' = nothing)."""
    if pr.role != "actuator":
        return ""
    if rc == 0 and pr.argv_hash == "UNCONFIRM":
        return _unconfirmed(rec, now)
    if rc == 0:
        # TRANSPLANTED too: a confirmed move is usually derived TRANSPLANTED (row 12) in the pass
        # before its A exits, and a PRE-MOVE-only test left the relaunch gap with no substate.
        if pr.argv_hash in ("A", "A-husk") and rec.phase in (
            "PRE-MOVE",
            "TRANSPLANTED",
        ):
            rec.substate, rec.wait = "IN-FLIGHT", None
        if pr.argv_hash == "R":
            rec.close["replaced_at"] = (
                now  # closed by replaced_elsewhere once it is seen
            )
        return "%s rc=0" % pr.argv_hash
    if rc is None:
        # Adopted by argv, or exited before this daemon could reap it: no code is no verdict. The
        # derived phase is the truth; scoring it as a failure escalated a move that had engaged.
        return "%s exited, code unknown — the phase decides" % pr.argv_hash
    disp, sub, reason = outcome(rec, rc, text)
    if pr.argv_hash in MOVE_ACTUATORS:
        # Whatever it was refused for, the NEXT move spawn is a new attempt: the double-typer audit
        # allows exactly one move spawn per (sid, attempt), so a retry must not share one.
        rec.attempt += 1
    detail = (reason or disp)[:200]
    fp = classify.fingerprint(rec.phase, disp, text, -1 if rc is None else rc, "")
    pre = rec.phase == "PRE-MOVE"
    if disp == "NOT_NEEDED":
        rec.terminal = T.Terminal(
            outcome="NOT_NEEDED", proof="actuator: " + detail, at=now
        )
    elif disp == "HOLD":
        # A HOLD is not an attempt, but §4.2 row 9 reads it: a husk whose move was HELD unconfirms.
        rec.attempts_by_class["HOLD"] = rec.attempts_by_class.get("HOLD", 0) + 1
        rec.last_error = T.LastError(cls="HOLD", fingerprint=fp, detail=detail, at=now)
        if pre:
            _hold(rec, sub or _hold_substate(text), now)
    elif disp == "WAIT":
        classify.apply_failure(rec, "WAIT", fp, detail, now)
        # Without an eligibility time the next pass re-spawned the actuator every few seconds
        # (W5 rig: refused idle moves in PRE-MOVE, a capacity-shed R in PANE-GONE).
        rec.next_eligible_at = now + WAIT_RETRY_S
        if pre:
            rec.substate = sub or "WAIT_SLOT"
            rec.wait = T.Wait(reason=rec.substate, since=now, eta=now + WAIT_RETRY_S)
    elif disp in ("TRANSIENT", "DETERMINISTIC", "IMPOSSIBLE"):
        d = classify.apply_failure(rec, disp, fp, detail, now)
        if d == "IMPOSSIBLE":
            rec.terminal = T.Terminal(outcome="IMPOSSIBLE", proof=detail, at=now)
        elif pre:
            rec.substate, rec.wait = "BACKOFF", None
        disp = d
    return "%s rc=%s → %s%s" % (
        pr.argv_hash,
        rc,
        disp,
        ("/" + rec.substate) if pre and rec.substate else "",
    )


def _unconfirmed(rec: T.Record, now: float) -> str:
    """UNCONFIRM rc 0 undid this attempt's confirm: the source is whole again, so the next move is a
    NEW attempt (one move spawn per (sid, attempt)), held for the reason the move was held for."""
    err = rec.last_error
    rec.attempt += 1
    rec.confirm_len, rec.submit_token = None, ""
    tl = rec.timeline
    tl.confirmed = tl.exit_typed_by_me = tl.exited = tl.relaunched = tl.submitted = None
    rec.last_error = None  # row 9's HOLD branch is per attempt
    if err is not None and err.cls == "HOLD":
        head = err.detail.split(":", 1)[0]
        sub = head if head in RCY_HELD_SUB.values() else _hold_substate(err.detail)
        _hold(rec, sub, now)
    else:
        rec.substate, rec.wait = "DETECTED", None
    return "UNCONFIRM rc=0 → PRE-MOVE/%s, attempt %d" % (rec.substate, rec.attempt)


def _hold(rec: T.Record, sub: str, now: float) -> None:
    since = rec.wait.since if rec.wait and rec.wait.reason == sub else now
    rec.substate = sub
    rec.wait = T.Wait(
        reason=sub,
        since=since,
        eta=now + REPROBE_S if sub in REPROBED else None,
        max_age_s=T.MAX_AGE_S.get(sub),
    )


def rebucket(rec: T.Record, bucket_name: str, now: float) -> bool:
    """Let the census rewrite a substate it owns while the record is idle in PRE-MOVE."""
    if not rec.open or rec.phase != "PRE-MOVE" or rec.substate not in CENSUS_OWNED:
        return False
    new = BUCKET_SUBSTATE.get(bucket_name, bucket_name)
    if new not in CENSUS_OWNED or new == rec.substate:
        return False
    if new == "DETECTED":
        rec.substate, rec.wait = new, None
    else:
        _hold(rec, new, now)
    return True


def reprobe(rec: T.Record, now: float) -> bool:
    """A hold the census cannot observe goes back to DETECTED once its re-probe time has come."""
    if (
        rec.open
        and rec.phase == "PRE-MOVE"
        and rec.substate in REPROBED
        and rec.wait is not None
        and rec.wait.eta is not None
        and now >= rec.wait.eta
    ):
        rec.substate, rec.wait = "DETECTED", None
        return True
    return False


def note_confirm(rec: T.Record) -> bool:
    """confirm_len + timeline.confirmed from the transplant tombstone, once per attempt."""
    if rec.confirm_len is not None:
        return False
    src = transcript_path(rec.source_cfg, rec.cwd, rec.sid)
    if not src.endswith(".jsonl"):
        return False
    tomb = src[: -len(".jsonl")] + ".HANDOFF.json"
    try:
        with open(tomb, encoding="utf-8") as fh:
            doc = json.load(fh)
        n = doc.get("confirm_len")
        st = os.stat(tomb)
    except (OSError, ValueError, AttributeError):
        return False
    if not isinstance(n, int) or isinstance(n, bool):
        return False
    rec.confirm_len = n
    rec.timeline.confirmed = rec.timeline.confirmed or st.st_mtime
    return True


def note_watcher_hold(home: str, rec: T.Record, now: float) -> bool:
    """§7 step 5: the detached watcher cancels a dialog AFTER the confirm and says so only in its
    handoffs row (`recycle-held-<reason>`, `…; unconfirm=needed`); A has already exited, usually
    rc 0, so no actuator exit carries it and row 9 picked A-husk over UNCONFIRM (W5 rig). Keyed on
    this attempt's HF_RECYCLE_ATTEMPT label."""
    if rec.last_error is not None and rec.last_error.cls == "HOLD":
        return False
    want = "%s:%d" % (rec.record_id, rec.attempt)
    path = os.path.join(home, ".claude", "logs", "handoffs.jsonl")
    for ln in reversed(tail(path, 256 * 1024).splitlines()):
        try:
            row = json.loads(ln)
        except ValueError:
            continue
        if not isinstance(row, dict) or str(row.get("attempt", "")) != want:
            continue
        sub = RCY_HELD_SUB.get(str(row.get("class", ""))[len("recycle-held-") :])
        if sub and "unconfirm=needed" in str(row.get("detail", "")):
            rec.attempts_by_class["HOLD"] = rec.attempts_by_class.get("HOLD", 0) + 1
            rec.last_error = T.LastError(
                cls="HOLD",
                fingerprint="watcher|" + sub,
                detail="%s: watcher held after the confirm; unconfirm=needed" % sub,
                at=now,
            )
            return True
    return False


def dead_actuators(
    procs: List[T.ProcRole], exits: Dict[int, int]
) -> List[Tuple[T.ProcRole, Optional[int]]]:
    """Pair each dead actuator with its exit code (None: exited before this daemon, or adopted)."""
    return [(p, exits.pop(p.pid, None)) for p in procs if p.role == "actuator"]


# ── attempts: in flight, hop, release (W5) ───────────────────────────────────────────────────────


def mark_in_flight(rec: T.Record) -> bool:
    """A PLANNED move whose transplant is confirmed (or whose A returned 0) is IN-FLIGHT: the relaunch
    gap derives PRE-MOVE (source dead, target not up yet), and a PLANNED record there was dispatched
    a SECOND A over a transplanted session (W5 rig, with and without a daemon restart)."""
    if (
        rec.phase == "PRE-MOVE"
        and rec.substate
        in ("PLANNED", None)  # None: PLANNED → TRANSPLANTED (row 12) → the gap
        and rec.confirm_len is not None
    ):
        rec.substate, rec.wait = "IN-FLIGHT", None
        return True
    return False


def new_attempt(
    rec: T.Record, holder: Optional[T.HolderObs], why: str, now: float
) -> None:
    """§4.2 rows 2-3: the session is live on the target and failed there — a NEW move FROM that
    target (architecture §5 Pinning). The old target becomes the source; the target is re-placed."""
    if holder is not None:
        rec.source_pid, rec.source_lstart = holder.pid, holder.lstart
    rec.source_acct, rec.source_cfg = rec.target_acct, rec.target_cfg
    rec.attempt += 1
    rec.target_acct = rec.target_cfg = rec.assign_id = rec.submit_token = rec.bundle = (
        ""
    )
    rec.confirm_len, rec.sentinel_until, rec.intent = None, None, None
    tl = rec.timeline
    tl.planned = tl.confirmed = tl.exit_typed_by_me = tl.exited = None
    tl.relaunched = tl.submitted = None
    rec.phase, rec.substate, rec.wait = "PRE-MOVE", "DETECTED", None
    rec.close["hop"] = why
    rec.close["hops"] = int(rec.close.get("hops", 0)) + 1


def target_holder(rec: T.Record, snap: T.Snapshot) -> Optional[T.HolderObs]:
    s = snap.sessions.get(rec.sid)
    for h in s.holders if s else []:
        if (
            not h.bg
            and rec.pane
            and h.pane is not None
            and tuple(h.pane) == tuple(rec.pane)
        ):
            return h
    return None


# ── readiness (§4.2 row 6, MOVED): lr-fire-resume --no-prompt notes READY / READY-QUIET ─────────

READY_STATES = ("READY", "READY-QUIET")


def bundles_dir(home: str, sid: str) -> str:
    """lr-handoff writes its run bundle under $HOME/.reso/limit-recover/<sid>/ (no other seam)."""
    return os.path.join(home, ".reso", "limit-recover", sid)


def bundle_launcher(home: str, rec: T.Record) -> str:
    """This move's own launcher (A-husk and B pass it as --resume-launcher): the newest bundle whose
    MANIFEST names this record and target, its lr-launch-<sid8>-*.sh. Nothing else ever set
    rec.bundle, so both spawned with an empty launcher and died DETERMINISTIC (W5 rig)."""
    import glob

    base = glob.escape(bundles_dir(home, rec.sid))
    for man in sorted(
        glob.glob(os.path.join(base, "bundle-*", "MANIFEST.json")), reverse=True
    ):
        try:
            with open(man, encoding="utf-8") as fh:
                doc = json.load(fh)
        except (OSError, ValueError):
            continue
        if not isinstance(doc, dict) or doc.get("record_id") != rec.record_id:
            continue
        if rec.target_acct and doc.get("target") != rec.target_acct:
            continue
        pat = "lr-launch-%s-*.sh" % rec.sid[:8]
        hits = sorted(glob.glob(os.path.join(glob.escape(os.path.dirname(man)), pat)))
        if hits:
            return hits[-1]
    return ""


def readiness(home: str, rec: T.Record) -> str:
    """The newest bundle of THIS attempt that noted READY/READY-QUIET, else "none". A bundle is this
    attempt's when its events carry attempt == rec.attempt (lr-fire-resume stamps LR_ATTEMPT)."""
    import glob

    runs = sorted(
        glob.glob(
            os.path.join(
                glob.escape(bundles_dir(home, rec.sid)), "bundle-*", "events.jsonl"
            )
        ),
        reverse=True,
    )
    for f in runs[:4]:
        try:
            with open(f, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()[-200:]
        except OSError:
            continue
        for ln in reversed(lines):
            try:
                ev = json.loads(ln)
            except ValueError:
                continue
            if (
                isinstance(ev, dict)
                and ev.get("state") in READY_STATES
                and str(ev.get("attempt", "")) == str(rec.attempt)
            ):
                return str(ev["state"])
    return "none"


def replaced_elsewhere(rec: T.Record, snap: T.Snapshot, now: float) -> bool:
    """After a successful R (§4.2 row 11), the session live in a DIFFERENT window closes the record
    REPLACED-NEW-WINDOW: the pane it was detected in is gone, so same-window cannot hold."""
    if not rec.close.get("replaced_at") or rec.terminal is not None:
        return False
    s = snap.sessions.get(rec.sid)
    for h in s.holders if s else []:
        if (
            not h.bg
            and h.pane is not None
            and (not rec.pane or tuple(h.pane) != tuple(rec.pane))
        ):
            rec.close.update(via="R", pane=list(h.pane), same_window=False, at=now)
            rec.terminal = T.Terminal(
                outcome="REPLACED-NEW-WINDOW",
                proof="live in window %d:%d after R" % tuple(h.pane),
                at=now,
            )
            return True
    return False
