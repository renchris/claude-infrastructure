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

import calendar
import json
import os
import re
import time
from typing import Any, Callable, Dict, List, Optional, Tuple

from lr_recon import capped, census, classify, report
from lr_recon import types as T
from lr_recon.evidence import _same_cfg, transcript_path

REPROBE_S = 120.0
WAIT_RETRY_S = 60.0
R_PROOF_S = (
    120.0  # an R rc 0 opened a WINDOW; the session must show up in it within this
)
MOVE_ACTUATORS = ("A", "A-husk", "B", "R")
TAIL_BYTES = 16 * 1024
# Substates the census derives from a bucket; it may rewrite them while nothing is in flight.
CENSUS_OWNED = (
    "DETECTED",
    "WAIT_RESET",
    "HOLD-FOCUS",
    "HOLD-BGWORK",
    "HOLD-SUBAGENTS",
    "HOLD-DRAFT",  # W7h: the census reads a limited session's composer (see rebucket)
    "HOLD:iterm",
    "HELD:team",
    "LAUNCHER-ROOTED",
    "SPLIT-BRAIN",
)
BUCKET_SUBSTATE = {
    "LIMITED": "DETECTED",
    # a mover whose move is R (W7g); still in CENSUS_OWNED so an old held record is rewritten
    "LAUNCHER-ROOTED": "DETECTED",
    "STAY": "WAIT_RESET",
    "IDLE-ELIGIBLE": "DETECTED",
}
# D4.4: a lead's live members hold it (HELD:team) over these too, and only this many consecutive
# member-free passes release it.
TEAM_ABSORBS = ("WAIT_SLOT", "WAIT_DATA", "WAIT_CAPACITY", "BACKOFF", "PLANNED")
TEAM_EXIT_PASSES = 2
# Holds the census cannot observe: re-probed through the actuator's own precheck.
REPROBED = ("HOLD-DRAFT", "HOLD-MENU", "HOLD-COMPOSER", "HOLD-LOAD")
# lr-handoff's wake guard writes neither a PRECHECK nor a `verdict:` line, only `lr-handoff:
# HELD:wake-guard (woke Ns ago)` and a NOTMOVED verdict quoting it (lr-handoff.sh WAKE GUARD), so
# that one line is matched by name (W8 G5): unmatched, it fell to the free-text DETERMINISTIC.
_REASON = re.compile(
    r"(?:PRECHECK |verdict: |lr-handoff: (?=HELD:wake-guard\b))(?:HELD|REFUSED):([A-Za-z:-]+)"
)
# classify's IMPOSSIBLE text, which is also R's own subject line (outcome)
_LAUNCHER_ROOTED = re.compile(r"launcher[- ]rooted", re.IGNORECASE)
# handoff-fire's held-after-confirm reasons (recycle-held-<reason>) → the PRE-MOVE hold they mean
RCY_HELD_SUB = {
    "draft": "HOLD-DRAFT",
    "bg-work": "HOLD-BGWORK",
    "bgwork": "HOLD-BGWORK",
    "subagents": "HOLD-SUBAGENTS",
    "focused": "HOLD-FOCUS",
    "team": "HELD:team",
    "busy": "HOLD-COMPOSER",  # mid-turn: re-probed through the precheck
    "unreachable": "HOLD-COMPOSER",  # composer unreadable (not a draft): re-probed the same way
    "exit-readback": "HOLD-COMPOSER",  # the typed /exit read back wrong: a composer read
    # gap-3 E2: a recycle the load gate refused after the confirm is not a composer hold. 6 of the
    # 18 HOLD-COMPOSER transitions 10-13..10-20 were this (load 9.9-29.1/core), and 0 of 18 were a
    # composer condition, so the label hid the cause from every page and readout.
    "load": "HOLD-LOAD",
}
# handoff-fire's hf_recycle_hold line: held after the confirm, and whether the unconfirm undid it.
# Three forms: exit-readback is held AFTER /exit was typed and says so (recycle-failures-kitty
# REPORT.md fix 2); exit-signal-ignored is held after a SIGTERM (fix 10); every other class is
# "ABORTED before /exit".
_RCY_HELD = re.compile(
    r"recycle (?:ABORTED before /exit|HELD after /exit was TYPED|HELD after SIGTERM) \(held: ([A-Za-z-]+)\):"
    r".*\bunconfirm rc (\w+)\."
)
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


def outcome(
    rec: T.Record, rc: Optional[int], text: str, actuator: str = ""
) -> Tuple[str, str, str]:
    """(disposition, substate, reason). A precheck's named refusal wins over the free-text classes,
    because it is the actuator's own verdict on why nothing was done."""
    held = _held_after_confirm(text)
    if held and rec.phase == "PRE-MOVE":
        # lr-handoff calls this STRANDED too, but unconfirm rc 0 restored the source: a named hold
        return "HOLD", held, "HELD:%s after the confirm (unconfirm rc 0)" % held
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
    if actuator in classify.C_ACTUATORS and classify.c_transient(text):
        # C2-lite (W8): cc-tui could not tell, or its kitty RPC failed; never a verdict on the
        # session. Read first, so no free-text class outranks cc-tui's own last line.
        return "TRANSIENT", "", ""
    lines = text.splitlines()[-40:]
    if actuator == "R":
        # R's own subject: lr-handoff's REPLACE announces "pane P is launcher-rooted … REPLACING in
        # place", and classify reads launcher-rooted as IMPOSSIBLE, the class that sends a record TO
        # R. Left in, any failed R (a kitty timeout) ended the record IMPOSSIBLE (W7g).
        lines = [ln for ln in lines if not _LAUNCHER_ROOTED.search(ln)]
    return classify.classify("\n".join(lines), -1 if rc is None else rc), "", ""


# The reset wake's non-zero exits that page instead of retyping (D4.9 step 6): cc_tui_submit rc 1-4,
# and a missing focus gate. rc 5 (CR sent, no record yet) and rc 0 wait for the fresh turn instead.
WAKE_FAILED = {
    1: "the pane is gone",
    2: "the composer could not be read, or a dialog is open",
    3: "the composer holds a draft",
    4: "the typed text read back wrong and was scrubbed",
    8: "no lr_focus_gate to ask; nothing was typed",
}


def wake_exit(rec: T.Record, rc: Optional[int], text: str, now: float) -> str:
    """One reset wake's exit. rc 6 = the focus gate held it: re-probed later, never paged. A failure
    in WAKE_FAILED is paged once and never retyped; the operator owns the pane from there."""
    if rc == 6:
        rec.close.pop("wake_eta", None)
        rec.next_eligible_at = now + REPROBE_S
        held = _REASON.findall(text)
        return "wake held (%s), re-probed" % (held[-1] if held else "focused")
    if rc in WAKE_FAILED:
        rec.close["wake_failed"] = "%s (rc %d)" % (WAKE_FAILED[rc], rc)
        return "wake failed: " + rec.close["wake_failed"]
    return "wake rc=%s — waiting for a turn after the reset" % rc


def settle_exit(
    rec: T.Record, pr: T.ProcRole, rc: Optional[int], text: str, now: float
) -> str:
    """Apply one dead actuator's exit to its record. Returns the event detail ('' = nothing)."""
    if pr.role != "actuator":
        return ""
    if pr.argv_hash == "C" and rec.phase == "PRE-MOVE" and "wake_eta" in rec.close:
        return wake_exit(rec, rc, text, now)
    if rc == 0 and pr.argv_hash == "UNCONFIRM":
        return _unconfirmed(rec, now)
    if pr.argv_hash in classify.C_ACTUATORS:
        # C2-lite: an rc-5 C typed its prompt and could not see it land; the next C or C-retry
        # first looks for THIS token (__main__._c_rc5_landed). A later exit of either kind ends it.
        if rc == 5 and rec.submit_token:
            rec.close["c_rc5_token"] = rec.submit_token
        elif rc == 0:
            rec.close.pop("c_rc5_token", None)
    if rc == 0:
        release_holds(rec)
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
            # one window per R: the same pass re-derived PANE-GONE/R and spawned another
            rec.next_eligible_at = now + R_PROOF_S
        return "%s rc=0" % pr.argv_hash
    if rc is None and not _rolled_back_by_its_log(rec, pr.argv_hash, text):
        # Adopted by argv, or exited before this daemon could reap it: no code is no verdict. The
        # derived phase is the truth; scoring it as a failure escalated a move that had engaged.
        return "%s exited, code unknown — the phase decides" % pr.argv_hash
    if rec.phase in ("MOVED", "ENGAGED"):
        # The phase table already proved the move from disk; an actuator exiting non-zero after
        # that (a watcher's own engagement wait timing out) is a stale verdict. Scored, it bumped
        # the attempt and re-opened a MOVED record to RELAUNCHED (W5b real canary 3).
        return "%s rc=%s after %s — the phase decides" % (pr.argv_hash, rc, rec.phase)
    return _score(rec, pr.argv_hash, rc, text, now)


# lr-handoff's own closing line; a rollback after the transplant began ends "verdict=NOTMOVED".
_VERDICT = re.compile(r"^lr-handoff \S+: verdict=([A-Z][A-Z-]*)", re.M)


def _rolled_back_by_its_log(rec: T.Record, actuator: str, text: str) -> bool:
    """A move actuator whose LAST verdict is NOTMOVED, on a record the phase table derives PRE-MOVE:
    the move was undone (admit aborted: lock, tombstone and target copy withdrawn; source alive), so
    its exit is a verdict even with no exit code. One move spawn per (sid, attempt) makes the log
    this spawn's own."""
    verdicts = _VERDICT.findall(text)
    return (
        actuator in MOVE_ACTUATORS
        and rec.phase == "PRE-MOVE"
        and bool(verdicts)
        and verdicts[-1] == "NOTMOVED"
    )


def rolled_back(paths: T.Paths, rec: T.Record, now: float) -> str:
    """§4.4: a move that rolled back after its transplant began, whose exit nothing scored, is
    re-offered as a counted retry. The R exit is reaped with no code (the daemon restarted under it,
    or adopted it), "the phase decides", and the phase table derives PRE-MOVE with no substate once
    the target copy is withdrawn: timeline.planned and target_acct keep holder_gone and _in_place
    off it, movers() takes no substate None, and RECON-DEFECT paged every pass with nothing acting
    (db755a94, 2026-10-20: HELD:unreachable on pane 41, then NOTMOVED, "a retry is safe").

    Keyed on the evidence, not the shape: this attempt's own move actlog must end NOTMOVED. Scored
    exactly as a reaped exit would be (_score), so the attempt is bumped and repeated rollbacks
    escalate through the existing budget. The caller has checked no actuator of the record is live.
    Returns the event detail ('' = not settled)."""
    t = rec.timeline
    if (
        not rec.open
        or rec.phase != "PRE-MOVE"
        or rec.substate is not None
        or rec.wait is not None
        or (rec.next_eligible_at or 0) > now
        or rec.escalated
        or not rec.target_acct
        or t.confirmed is not None
        or t.exit_typed_by_me is not None
        or quiet_for(rec, "busy", now) < HOLDER_GONE_QUIET_S
    ):
        return ""
    for a in MOVE_ACTUATORS:
        text = tail(actlog(paths, rec, a))
        if _rolled_back_by_its_log(rec, a, text):
            return "rolled back, nothing scored it: " + _score(rec, a, None, text, now)
    return ""


def _score(
    rec: T.Record, actuator: str, rc: Optional[int], text: str, now: float
) -> str:
    """Score one failed actuator exit: its class sets the substate, wait, backoff or terminal."""
    disp, sub, reason = outcome(rec, rc, text, actuator)
    if actuator in MOVE_ACTUATORS:
        # Whatever it was refused for, the NEXT move spawn is a new attempt: the double-typer audit
        # allows exactly one move spawn per (sid, attempt), so a retry must not share one. Nor may it
        # inherit this attempt's confirm: note_confirm re-reads it while the tombstone stands.
        rec.attempt += 1
        rec.confirm_len = rec.timeline.confirmed = None
    detail = (reason or disp)[:200]
    fp = classify.fingerprint(rec.phase, disp, text, -1 if rc is None else rc, "")
    pre = rec.phase == "PRE-MOVE"
    if disp != "HOLD":
        release_holds(rec)
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
            if rec.wait is not None and reason.startswith("bg-work:ship-land"):
                rec.wait.detail = (
                    "ship-land"  # decision 2: a ship-land job pages at 60 min
                )
        else:
            # Past PRE-MOVE no hold substate stops the phase table, which re-derived the same
            # actuator every pass: a held husk re-spawned A-husk every ~4 s (W5b real canary 3,
            # 181 spawns, each held). A HOLD waits one re-probe before the next try.
            rec.next_eligible_at = now + REPROBE_S
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
        actuator,
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
    if sub in REPROBED:
        # gap-3 E2: a re-probed hold's wait is dropped by reprobe (DETECTED) and again by the next
        # placement (PLANNED), so `since` restarted every 120 s cycle and its max age never came
        # (769b7294 cycled six times 03:23-05:17Z, never paged). The first hold of the class is
        # kept in close.hold_since until a non-hold outcome (release_holds).
        held = rec.close.setdefault("hold_since", {})
        since = min(since, float(held.setdefault(sub, since)))
    rec.substate = sub
    rec.wait = T.Wait(
        reason=sub,
        since=since,
        eta=now + REPROBE_S if sub in REPROBED else None,
        max_age_s=T.MAX_AGE_S.get(sub),
    )


def release_holds(rec: T.Record) -> None:
    """A non-hold outcome ends every re-probed hold's age clock (see _hold)."""
    rec.close.pop("hold_since", None)


def rebucket(
    rec: T.Record, bucket_name: str, now: float, eta: Optional[float] = None
) -> bool:  # eta: the bucket's reset, kept on WAIT_RESET and HELD:team (D1.11, D4.9)
    """Let the census rewrite a substate it owns while the record is idle in PRE-MOVE.

    HELD:team is sticky both ways (D4.4). Entering, it also takes over a waiting, backing-off or
    PLANNED record: without that, a member-count flicker (1, 0, 1) left the lead WAIT_SLOT, then
    PLANNED, then moved by A with its members still live. Leaving needs TEAM_EXIT_PASSES
    consecutive member-free passes, so a finished team is still released but a one-pass read of 0
    is ignored. A PLANNED record taken over drops its target; the caller voids the phantom."""
    if not rec.open or rec.phase != "PRE-MOVE":
        return False
    new = BUCKET_SUBSTATE.get(bucket_name, bucket_name)
    if (
        new == "DETECTED"
        and rec.substate == "WAIT_RESET"
        and rec.close.get("cohort_exit")
    ):
        # cohort_exit's stay: the session still reads LIMITED until its in-place continue lands,
        # and DETECTED would plan the move the exit just cancelled. The plan re-offers it after
        # REOFFER_AFTER_S if the wake never lands (plan.movers).
        return False
    if new == "HELD:team":
        rec.close.pop("team_zero", None)
    elif rec.substate == "HELD:team":
        n = int(rec.close.get("team_zero", 0)) + 1
        rec.close["team_zero"] = n
        if n < TEAM_EXIT_PASSES:
            return False
        rec.close.pop("team_zero", None)
    # W7h: a draft the census reads holds the record whether it is waiting or PLANNED, as a team
    # does: the plan must not carry a draft as a mover. A HOLD-DRAFT with a re-probe eta came from
    # an actuator's precheck; the census takes it over on reading the draft itself (eta None) and
    # releases only one it holds, so one empty read cannot re-fire a move the precheck refused.
    if new == "HOLD-DRAFT" and rec.substate == new and rec.wait is not None:
        rec.wait.eta = None
    if (
        rec.substate == "HOLD-DRAFT"
        and new != rec.substate
        and (rec.wait is None or rec.wait.eta is not None)
    ):
        return False
    owned = rec.substate in CENSUS_OWNED or (
        new in ("HELD:team", "HOLD-DRAFT") and rec.substate in TEAM_ABSORBS
    )
    if not owned or new not in CENSUS_OWNED or new == rec.substate:
        return False
    if rec.substate == "PLANNED":
        rec.target_acct = rec.target_cfg = ""
    if new == "DETECTED":
        rec.substate, rec.wait = new, None
    else:
        _hold(rec, new, now)
        if new == "HOLD-DRAFT" and rec.wait is not None:
            rec.wait.eta = (
                None  # census-held: re-read every pass, never the timed re-probe
            )
        if (
            new in ("HELD:team", "WAIT_RESET")
            and eta is not None
            and rec.wait is not None
        ):
            rec.wait.eta = (
                eta  # the reset: the in-place wake and the page deadline key on it
            )
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
    this attempt's HF_RECYCLE_ATTEMPT label.

    Latched once per attempt in rec.close["watcher_hold"]: re-stamping HOLD after each UNCONFIRM
    failure erased the DETERMINISTIC last_error, so the identical second failure never escalated (W5
    rig 0f71c0d5: 57 rc 2 retries, never ESCALATED). Row 9 reads the latch instead (evidence)."""
    want = "%s:%d" % (rec.record_id, rec.attempt)
    if rec.close.get("watcher_hold") == want:
        return False
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
            rec.close["watcher_hold"] = want
            rec.attempts_by_class["HOLD"] = rec.attempts_by_class.get("HOLD", 0) + 1
            rec.last_error = T.LastError(
                cls="HOLD",
                fingerprint="watcher|" + sub,
                detail="%s: watcher held after the confirm; unconfirm=needed" % sub,
                at=now,
            )
            return True
    return False


def _held_after_confirm(text: str) -> str:
    """The PRE-MOVE hold a `(held: <r>) … unconfirm rc 0` hold line (either form) names, or ''."""
    hits = [m for m in _RCY_HELD.finditer(text) if m.group(2) == "0"]
    return RCY_HELD_SUB.get(hits[-1].group(1).lower(), "HOLD-COMPOSER") if hits else ""


def note_unconfirm(paths: T.Paths, rec: T.Record, now: float) -> str:
    """lr-transplant --phase unconfirm undid this attempt's confirm: the tombstone is now
    <sid>.HANDOFF.json.unconfirmed and <sid>.jsonl is back. Level-triggered on that rename, so a
    lost actuator exit code (a daemon restart) cannot leave a latched confirm_len that marks the
    record IN-FLIGHT for good (W5 rig, draft-after-confirm). Returns the new substate, or ''.

    Not gated on a latched confirm_len: latching needs a pass inside the 4-8 s confirm→unconfirm
    window, and the W5 rig's draft-after-confirm missed it and sat at PRE-MOVE/None. Unlatched, only
    a record through custody (None) or in the gap (IN-FLIGHT) is pulled back; PLANNED/DETECTED
    never, so a re-planned attempt is not re-held off an old rename."""
    if rec.phase != "PRE-MOVE":
        return ""
    if rec.confirm_len is None and rec.substate not in (None, "IN-FLIGHT"):
        return ""
    src = transcript_path(rec.source_cfg, rec.cwd, rec.sid)
    if not src.endswith(".jsonl"):
        return ""
    base = src[: -len(".jsonl")]
    if (
        os.path.exists(base + ".HANDOFF.json")
        or os.path.exists(src + ".handed-off")
        or not os.path.exists(base + ".HANDOFF.json.unconfirmed")
    ):
        return ""  # still confirmed (the real relaunch gap), or never was
    try:
        st = os.stat(base + ".HANDOFF.json.unconfirmed")
    except OSError:
        return ""
    # lr_file_evidence moves an older one aside, so a new unconfirm is a new inode: once per rename
    key = "%d:%d" % (st.st_ino, int(st.st_mtime))
    if rec.close.get("unconfirmed") == key:
        return ""
    rec.close["unconfirmed"] = key
    sub = ""
    for att in (rec.attempt, rec.attempt - 1):  # settle_exit may already have bumped it
        for a in ("A", "A-husk"):
            p = os.path.join(paths.p("actlogs"), "%s.%d.%s.log" % (rec.sid[:8], att, a))
            sub = sub or _held_after_confirm(tail(p))
    if sub:
        rec.attempts_by_class["HOLD"] = rec.attempts_by_class.get("HOLD", 0) + 1
        rec.last_error = T.LastError(
            cls="HOLD",
            fingerprint="unconfirmed|" + sub,
            detail="%s: held after the confirm; unconfirmed" % sub,
            at=now,
        )
    # the one path UNCONFIRM rc 0 takes: attempt += 1 (one move spawn per (sid, attempt)), confirm
    # cleared, then the hold (HOLD-DRAFT is REPROBED) or DETECTED
    _unconfirmed(rec, now)
    return rec.substate or ""


def superseded(pr: T.ProcRole, want: Optional[str], live: List[T.ProcRole]) -> str:
    """Why a dead actuator's exit must not be settled at all ('' = settle it). "stale": a newer spawn
    holds the intent, and this exit would be scored against that spawn's attempt, log and phase
    (A6 S-5). "duplicate": a live entry carries its nonce, so the one spawn is still running (S-3).
    Not even the None path: a None exit can still be scored by its log (_rolled_back_by_its_log)."""
    if not pr.nonce:
        return ""
    if any(p.nonce == pr.nonce for p in live):
        return "duplicate"
    if want is not None and pr.nonce != want:
        return "stale"
    return ""


def dead_actuators(
    procs: List[T.ProcRole],
    exits: Dict[int, int],
    durable: Optional[Callable[[T.ProcRole], Optional[int]]] = None,
    spawned: Optional[Dict[int, str]] = None,
    live: Optional[List[T.ProcRole]] = None,
    want: Optional[str] = None,
) -> List[Tuple[T.ProcRole, Optional[int]]]:
    """Pair each dead actuator with its exit code (A6 rules 4 and 6): the wrapper's exit file first
    (``durable``: exact by nonce, survives a restart and pid reuse), then this process's own reaped
    code, accepted only when ``spawned`` says this process spawned that pid under that nonce; None
    is unknown. An adopted descendant never carries a code: the wrapper's exit is the verdict. A
    superseded entry (stale or duplicate) gets None. ``spawned=None`` is the legacy pairing by pid."""
    out: List[Tuple[T.ProcRole, Optional[int]]] = []
    for p in procs:
        if p.role != "actuator":
            continue
        own = exits.pop(p.pid, None)  # always popped: never left for a reused pid
        if spawned is not None:
            mine = bool(p.nonce) and spawned.get(p.pid) == p.nonce
            if mine:
                spawned.pop(p.pid, None)
            else:
                own = None
        if p.argv_hash == "adopted" or superseded(p, want, live or []):
            out.append((p, None))
            continue
        rc = durable(p) if durable is not None else None
        out.append((p, own if rc is None else rc))
    return out


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
    target (architecture §5 Pinning). The old target becomes the source; the target is re-placed.

    An auth hop stays reversible until its new attempt confirms: the auth fact may yet be
    contradicted (W5 rig r2 target-auth: another session served on it ~1.3 s after the hop, and A
    refused the dead evidence to ESCALATED). So its pre-hop fields are stashed FIRST, before any is
    cleared; undo_hop restores them."""
    if why == "auth":
        rec.close["pre_hop"] = {
            "source": [
                rec.source_acct,
                rec.source_cfg,
                rec.source_pid,
                rec.source_lstart,
            ],
            "target": [rec.target_acct, rec.target_cfg],
            "assign_id": rec.assign_id,
            "submit_token": rec.submit_token,
            "confirm_len": rec.confirm_len,
            "bundle": rec.bundle,
            "timeline": T.to_dict(rec.timeline),
        }
    else:
        rec.close.pop("pre_hop", None)  # never undo into an older hop's world
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


def undo_hop(rec: T.Record) -> bool:
    """An auth hop whose SOURCE auth fact was contradicted before the new attempt confirmed: the
    account serves, so put the pre-hop move back and re-engage in place (the TARGET-AUTH guard's
    C-retry). The attempt stays bumped: the hop's A may already have spawned under it."""
    pre = rec.close.get("pre_hop")
    if not isinstance(pre, dict) or rec.timeline.confirmed is not None:
        return False
    rec.close.pop("pre_hop")
    rec.close.pop("hop", None)
    rec.source_acct, rec.source_cfg, rec.source_pid, rec.source_lstart = pre["source"]
    rec.target_acct, rec.target_cfg = pre["target"]
    rec.assign_id, rec.submit_token = pre["assign_id"], pre["submit_token"]
    rec.confirm_len, rec.bundle = pre["confirm_len"], pre["bundle"]
    rec.timeline = T.from_dict(T.Timeline, pre["timeline"])
    rec.phase, rec.substate, rec.wait, rec.next_eligible_at = (
        "TARGET-AUTH",
        None,
        None,
        None,
    )
    return True


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


# lr-fire-resume's verdicts that END its typing chain: after any of them its expect falls through to
# `interact` and types nothing more, but the relay lives as long as the claude it spawned. READY and
# READY-QUIET end it only at stage "ready" (the --no-prompt path); at stage "inject" READY-QUIET is
# the moment it STARTS typing.
LAUNCHER_DONE_STATES = (
    "READY-NOT-SEEN",
    "submitted",
    "queued",
    "INDETERMINATE:submit",
    "UNSUBMITTED",
    "UNVERIFIED:submit",
    "FAILED:submit",
    "FAILED",
)
# lr-fire-resume passed the owed prompt as the spawn's positional argument (gap 1, 2026-10-20): the
# relay types nothing, and the CLI itself submits the prompt once its boot reaches the REPL.
PROMPT_ARGV = "prompt-argv"
# A launcher that never wrote a verdict (an unreadable screen on the --no-prompt path notes nothing,
# and a missing LR_NOTE_SH silences every note) still types nothing this long after the target
# holder appeared: its ready wait (LR_READY_WAIT_S 180 s) and the submit poll (RCY_ENGAGE_TIMEOUT
# 180 s, re-reads to 45 s) are all bounded well inside it. It is also the bound on an argv prompt
# that never lands: the slowest boot measured was 112 s (gap 1 §2.2).
LAUNCHER_CHAIN_MAX_S = 600.0


def _attempt_events(home: str, rec: T.Record) -> List[Dict[str, Any]]:
    """This attempt's events from its newest bundle (an older bundle of the attempt is a past run),
    or [] when none of the newest four bundles carries the attempt."""
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
        mine: List[Dict[str, Any]] = []
        for ln in lines:
            try:
                ev = json.loads(ln)
            except ValueError:
                continue
            if isinstance(ev, dict) and str(ev.get("attempt", "")) == str(rec.attempt):
                mine.append(ev)
        if mine:
            return mine
    return []


def launcher_settled(home: str, rec: T.Record, now: float) -> str:
    """Why this attempt's live lr-fire-resume can no longer type ('' = it still may).

    C's quiet grace exists so C never types over the launcher's own prompt, and it was keyed on the
    launcher PROCESS. That process is a pty relay for the session's whole life, so on a relaunch
    whose launcher typed nothing (READY-NOT-SEEN, both RELAUNCHED/UNPROMPTED members of cohort
    next3-7d-1792497600 on 2026-10-20) the grace never opened and the owed continue never went out.
    The launcher's own verdict, in this attempt's bundle, says when its typing is over.

    A prompt passed on the spawn argv (``prompt-argv``) is DELIVERED, not owed: only its own record
    (``submitted``) or the chain bound settles that run, so C never sends a second copy."""
    started, verdict, argv = False, "", False
    for ev in _attempt_events(home, rec):
        state = ev.get("state")
        if state == "relaunch-typed":  # a (re)start: its verdict is owed again
            started, verdict, argv = True, "", False
        elif started and state == PROMPT_ARGV:
            argv = True
        elif started and (
            state in LAUNCHER_DONE_STATES
            or (state in READY_STATES and ev.get("stage") == "ready")
        ):
            verdict = str(state)
    if argv and verdict != "submitted":
        # The prompt is IN the spawned CLI, which submits it whenever its boot gets there: no
        # verdict short of the record itself means it was lost, and a C typed now would be the
        # second copy. Only the chain bound below releases it.
        verdict = ""
    if verdict:
        return "launcher verdict %s" % verdict
    seen = (rec.target_sample or {}).get("at")
    if seen is not None and now - float(seen) >= LAUNCHER_CHAIN_MAX_S:
        return "target holder up %ds with no launcher verdict" % (now - float(seen))
    return ""


def launcher_admitted(home: str, rec: T.Record) -> bool:
    """True iff this attempt's launcher passed its own capacity gate (``gate-admitted``). That
    admission paid for the session's first turn; when the launcher then typed nothing, C delivers
    that same turn and must not be charged for it a second time (gap 1 lever 3)."""
    return any(ev.get("state") == "gate-admitted" for ev in _attempt_events(home, rec))


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


def replaced_in_place(rec: T.Record, snap: T.Snapshot) -> str:
    """After a successful R, the session live again in the record's OWN window under this move's
    target proves the R too: lr-handoff recycles a launcher-rooted pane in place when it can (same
    window, same uuid). Only a different window counted, so canary 4fe9935f (2026-10-13, pane 16,
    next3 → next4, live there from 06:48:18) was scored "R rc 0 but no live holder in a new window"
    at 120 s; the attempt bump made its own target read as another recovery path, and it closed
    "engaged elsewhere". Proven here, the phase table closes it as this move's. Returns the proof."""
    if not rec.close.get("replaced_at") or rec.terminal is not None or not rec.pane:
        return ""
    s = snap.sessions.get(rec.sid)
    for h in s.holders if s else []:
        if (
            not h.bg
            and h.pane is not None
            and tuple(h.pane) == tuple(rec.pane)
            and _same_cfg(h.cfg, rec.target_cfg)
            and (h.pid, h.lstart) != (rec.source_pid, rec.source_lstart)
        ):
            rec.close.pop("replaced_at", None)
            return "live in its own window %d:%d on %s after R" % (
                tuple(h.pane) + (rec.target_acct or os.path.basename(h.cfg),)
            )
    return ""


def engaged_elsewhere(rec: T.Record, snap: T.Snapshot, now: float) -> str:
    """W5b2 defect C: a session another recovery path moved (legacy limit-recover, a hand move,
    boot-resume) and that is working again never read as engaged. Row 5 needs this attempt's own
    submit token and a holder under the target, so the record sat IN-FLIGHT, drew RECON-DEFECT
    every pass, and expired ESCALATED then IMPOSSIBLE while the session worked.

    The census's own evidence settles it: the sid's one live holder runs under neither the source
    nor this attempt's own move target, and its newest assistant record is a healthy turn after the
    death was detected. Two holders stay with row 1 (split brain). The target counts as elsewhere
    until this attempt spawns a move of its own, because only that move's token proves anything
    there. An escalation is dropped, or the closed record would still page ESCALATED. Returns the
    proof ('' = not settled).

    The same evidence with the holder under the SOURCE is the session answering where it died
    (``_in_place``): one decision, so the two branches partition on where the holder runs."""
    s = snap.sessions.get(rec.sid)
    if rec.terminal is not None or s is None or len(s.holders) != 1:
        return ""
    ok, h = s.transcript.last_assistant_ok_at, s.holders[0]
    if (
        (s.transcript.last or {}).get("limit")
        or ok is None
        or ok <= (rec.timeline.detected or now)
        or h.bg
        or not h.cfg
    ):
        return ""
    if _same_cfg(h.cfg, rec.source_cfg):
        return _in_place(rec, h, ok, now)
    if rec.close.get("move_attempt") == rec.attempt and _same_cfg(
        h.cfg, rec.target_cfg
    ):
        return ""  # this attempt's own move: row 5 proves it by its own token
    acct = s.acct if s.acct and _same_cfg(h.cfg, s.cfg) else os.path.basename(h.cfg)
    rec.phase, rec.substate, rec.wait, rec.escalated = "ENGAGED", None, None, False
    rec.close.update(
        via="ENGAGED",
        by="elsewhere",
        acct=acct,
        at=now,
        pane=list(h.pane) if h.pane else None,
        same_window=bool(rec.pane and h.pane and tuple(h.pane) == tuple(rec.pane)),
        same_uuid=True,
    )
    proof = "engaged on %s, moved there by another recovery path" % acct
    rec.terminal = T.Terminal(outcome="CLOSED", proof=proof, at=now)
    return proof


def _in_place(rec: T.Record, h: T.HolderObs, ok: float, now: float) -> str:
    """W7f: a limited session answering again on its SOURCE, before any move of ours confirmed, has
    nothing to recover: a nudge in place (legacy, a hand ``continue``), its own reset wake (D1.11,
    D4.9), or a limit the account contradicted. The census never re-buckets it (its last record is a
    healthy turn, so it reads WORKING and the census skips the record), so without this it sat
    PRE-MOVE in its last hold forever: LAUNCHER-ROOTED paged RECON-DEFECT every pass, and DETECTED
    was planned and moved by A, an /exit and relaunch of a working session (W5b2, 2026-10-01).
    Past PRE-MOVE (a confirmed transplant, a typed /exit) the phase table owns it."""
    if (
        rec.kind != "limited"
        or rec.phase != "PRE-MOVE"
        or rec.substate == "IN-FLIGHT"
        or rec.timeline.confirmed is not None
        or rec.timeline.exit_typed_by_me is not None
    ):
        return ""
    w = rec.wait
    if w is not None and w.eta is not None and ok > w.eta:
        proof = "continued in place after the reset at %s" % report._hm(w.eta)
    else:
        proof = "answered in place on %s after its limit: nothing to move" % (
            rec.source_acct or "its source"
        )
    rec.substate, rec.wait, rec.escalated = None, None, False
    rec.close.update(
        via="IN-PLACE",
        at=now,
        pane=list(h.pane) if h.pane else None,
        same_window=bool(rec.pane and h.pane and tuple(h.pane) == tuple(rec.pane)),
        same_uuid=True,
    )
    # A cohort exit (cohort_exit) was never a recovery: the source served again, so nothing was needed.
    if rec.close.get("cohort_exit"):
        proof = "%s; %s" % (rec.close["cohort_exit"], proof)
        rec.terminal = T.Terminal(outcome="NOT_NEEDED", proof=proof, at=now)
        return proof
    rec.terminal = T.Terminal(outcome="CLOSED", proof=proof, at=now)
    return proof


def _never_began(rec: T.Record) -> bool:
    """Open in PRE-MOVE with no move of ours begun: nothing planned, confirmed or typed, no target,
    no recorded process. Past any of those the phase table and the reboot park own the record."""
    t = rec.timeline
    return (
        rec.open
        and rec.phase == "PRE-MOVE"
        and rec.substate not in ("PLANNED", "IN-FLIGHT", "PARKED-REBOOT")
        and t.planned is None
        and t.confirmed is None
        and t.exit_typed_by_me is None
        and not rec.target_acct
        and not rec.procs
    )


def note_seen(
    rec: T.Record, key: str, seen: bool, now: float, first_unseen: bool = True
) -> None:
    """B7 R5: stamp one census's view of an activity (``busy``: an actuator, watcher or launcher of
    the move; ``typer``: something that may still type into the session), before any reader of the
    same pass. ``<key>_at`` is the last census that SAW it, an UPPER bound on when it stopped;
    ``<key>_quiet_at`` is the first census that did NOT, a LOWER bound (None while it is seen). A
    quiet window is measured from the lower bound: from the upper bound one long pass read as that
    much quiet, with the activity gone a second before the census. ``first_unseen=False`` (the
    recon/pass-clock kill switch) keeps the old last-seen reading."""
    at, quiet = key + "_at", key + "_quiet_at"
    if seen:
        rec.close[at] = now
        rec.close[quiet] = None
    elif quiet not in rec.close:
        # a record no pass of this code has stamped (an older daemon's): keep its old reading, so
        # the first pass after the upgrade decides exactly as before (a fresh `now` here re-waited a
        # 30-min-old rollback 60 s more and paged RECON-DEFECT, measured)
        rec.close[quiet] = float(rec.close.get(at) or 0.0)
    elif rec.close[quiet] is None:
        # seen by the previous census, not by this one
        rec.close[quiet] = now if first_unseen else float(rec.close.get(at) or 0.0)


def quiet_for(rec: T.Record, key: str, t: float) -> float:
    """Seconds ``key`` has certainly been absent at ``t`` (-1.0: this pass's census saw it). A record
    no pass has stamped yet (a unit test) reads the old last-seen gap."""
    quiet = key + "_quiet_at"
    if quiet not in rec.close:
        last = rec.close.get(key + "_at")
        if last is None and key == "typer":
            last = rec.close.get(
                "busy_at"
            )  # the C grace's reading before typer_at (58885750c)
        return t - float(last or 0.0)
    q = rec.close[quiet]
    return -1.0 if q is None else t - float(q)


def _lstart_epoch(lstart: str) -> Optional[float]:
    """ps LSTART (read under TZ=UTC LC_ALL=C, observe.PS_ENV_OVERRIDES) as epoch seconds."""
    try:
        return float(calendar.timegm(time.strptime(lstart, "%a %b %d %H:%M:%S %Y")))
    except (TypeError, ValueError):
        return None


def _attempt_launcher_open(home: str, rec: T.Record, now: float) -> bool:
    """This attempt's launcher started (a ``relaunch-typed`` event) and has not settled."""
    started = any(
        ev.get("state") == "relaunch-typed" for ev in _attempt_events(home, rec)
    )
    return started and not launcher_settled(home, rec, now)


def move_relay_live(home: str, rec: T.Record, snap: T.Snapshot, now: float) -> bool:
    """A live ``lr-fire-resume … <sid>`` that belongs to THIS move (B7 review: busy is a lane of the
    move, not any relay of the sid). The relay is the session's pty relay for the session's whole
    life (lr-fire-resume execs a shell only after claude exits), so a source pane rooted by an
    EARLIER relay was busy in every census and a rolled-back move on it never re-drove, silently
    (6 relays measured alive 13-15 h). A relay counts if it started after the move (its lstart is
    later than timeline.planned, else the move spawn's intent.at), or this attempt's launcher has
    not settled. With no move start on record, or an unreadable lstart, every relay counts, as
    before."""
    start = rec.timeline.planned
    if start is None and rec.intent is not None:
        start = rec.intent.at
    relays = [
        r
        for r in snap.procs.values()
        if not r.zombie and rec.sid in r.args and "lr-fire-resume" in r.args
    ]
    if not relays:
        return False
    if start is None:
        return True
    for r in relays:
        t = _lstart_epoch(r.lstart)
        if t is None or t > float(start):
            return True
    return _attempt_launcher_open(home, rec, now)


HOLDER_GONE_QUIET_S = 60.0  # since the first census that saw no watcher or launcher of the move (busy_quiet_at)


def holder_gone(rec: T.Record, snap: T.Snapshot, now: float) -> str:
    """W7i: a PRE-MOVE record nothing owns (no substate, wait or next_eligible_at, no move begun)
    whose session has no live holder is closed NOT_NEEDED(dead-before-claim). §3 step 3: "No live
    holder at first observation: NOT_NEEDED(dead-before-claim)"; invariant 25: "NOT_NEEDED only on
    target-side evidence or dead-before-claim"; §4.4: a record that breaks the invariant "gets its
    next action in the same pass". Nothing gave it one: a record back from SPLIT-BRAIN derives
    PRE-MOVE with substate None (the phase table writes no PRE-MOVE substate and the census
    rewrites only one it owns), the census stops seeing a dead session, and §4.4 logged
    RECON-DEFECT for it every pass: five records, about 1,400 events an hour on 2026-10-05.

    It spawns nothing (invariant 27: no R for a pane this reconciler did not retire); a session
    that died unmoved is the resume debt's. With a live holder the record is left as it is.
    Returns the proof ('' = not settled)."""
    if (
        not _never_began(rec)
        or rec.substate is not None
        or rec.wait is not None
        or rec.next_eligible_at
    ):
        return ""
    if quiet_for(rec, "busy", now) < HOLDER_GONE_QUIET_S:
        return ""
    s = snap.sessions.get(rec.sid)
    if s is not None and s.holders:
        return ""
    if rec.source_pid and snap.alive(rec.source_pid, rec.source_lstart):
        return ""
    proof = "dead-before-claim: no live holder, and no plan, wait or eligibility"
    rec.escalated = False
    rec.terminal = T.Terminal(outcome="NOT_NEEDED", proof=proof, at=now)
    return proof


def idle_unneeded(rec: T.Record, facts: Optional[Dict[str, T.Fact]], now: float) -> str:
    """W7i: an idle member whose fact can no longer move it is closed NOT_NEEDED(reason) (§4.2
    Outcomes). An idle move is optional work that an uncontradicted 5h/7d fact alone licenses (§3
    step 5; §C4 "A contradicted fact blocks idle fan-out"); once that fact is contradicted or
    gone, the census reads the session WORKING, which rewrites no substate, so the record kept its
    last one for good: 14 members of next3-auth-0 sat HOLD:iterm ("relaunch this session by hand")
    for sessions on a logged-in account, and the cohort could never close. Only before a move of
    ours began. Returns the proof ('' = not settled)."""
    if facts is None or rec.kind != "idle" or not _never_began(rec):
        return ""
    fact = facts.get("%s.%s" % (rec.source_acct, rec.scope))
    if fact is not None and not fact.contradicted:
        return ""
    proof = "idle member, no move begun: the %s fact on %s is %s" % (
        rec.scope or "account",
        rec.source_acct or "its account",
        "gone" if fact is None else "contradicted (the account served a turn since)",
    )
    rec.substate, rec.wait, rec.escalated = None, None, False
    rec.terminal = T.Terminal(outcome="NOT_NEEDED", proof=proof, at=now)
    return proof


def cohort_exit(
    rec: T.Record,
    facts: Optional[Dict[str, T.Fact]],
    usage: Optional[Dict[str, Dict[str, Any]]],
    snap: T.Snapshot,
    now: float,
) -> Tuple[str, bool]:
    """lr-wake h defect 3: a limited member whose SOURCE can serve again has nothing to move. Cohort
    ``next4-7d-1792314000`` held 3e929a81 PRE-MOVE/IN-FLIGHT 11 h after it formed, with next4's
    weekly limit already reset (5% used): the cohort had no exit for "the source is healthy again".

    Only before any move of ours committed (PRE-MOVE, nothing confirmed or typed; the caller has
    checked no actuator is alive), and only on POSITIVE evidence (capped.recovered: the cohort's
    reset passed, the fact was contradicted, or a fresh usage row under 100). Returns (proof,
    resume): with the session still live in its own pane on the source, ``resume`` is True and the
    record becomes the in-place stay wake (WAIT_RESET, detail ``stay``) — _wakes types the continue
    in its own pane and the fresh turn closes it NOT_NEEDED (``_in_place``). With nothing to wake
    it is NOT_NEEDED at once and the resume debt owns the session. ('', False) = not settled."""
    if (
        rec.kind != "limited"
        or rec.terminal is not None
        or rec.phase != "PRE-MOVE"
        # None is a record nothing owns (back from SPLIT-BRAIN): the census owns that one (§4.4)
        or rec.substate in (None, "PARKED-REBOOT")
        or rec.timeline.confirmed is not None
        or rec.timeline.exit_typed_by_me is not None
        or rec.close.get("cohort_exit")
    ):
        return "", False
    proof = capped.recovered(
        rec.source_acct,
        rec.scope,
        facts or {},
        usage or {},
        now,
        census.cohort_resets(rec.cohort_id) if rec.cohort_id else None,
    )
    if not proof:
        return "", False
    proof = "cohort exit: " + proof
    s = snap.sessions.get(rec.sid)
    live_here = bool(
        s is not None
        and any(
            not h.bg
            and h.pane is not None
            and rec.pane
            and tuple(h.pane) == tuple(rec.pane)
            and _same_cfg(h.cfg, rec.source_cfg)
            for h in s.holders
        )
    )
    rec.target_acct, rec.target_cfg, rec.escalated = "", "", False
    rec.close["cohort_exit"] = proof
    if live_here:
        rec.substate = "WAIT_RESET"
        rec.wait = T.Wait(
            reason="WAIT_RESET",
            since=now,
            eta=now,
            detail="stay",
            wakes=["reset"],
        )
        return proof, True
    rec.substate, rec.wait = None, None
    rec.terminal = T.Terminal(outcome="NOT_NEEDED", proof=proof, at=now)
    return proof, False


def replacement_unproven(rec: T.Record, now: float) -> bool:
    """R rc 0 proves a window opened, never that the session is live in it: the engine can refuse
    INSIDE the window after the launcher returned (W5 rig). No holder in another window by
    R_PROOF_S ⇒ the R failed, DETERMINISTIC, so a second identical one ESCALATES instead of opening
    one window per capacity admit forever."""
    at = rec.close.get("replaced_at")
    if not at or rec.terminal is not None or now - float(at) < R_PROOF_S:
        return False
    rec.close.pop("replaced_at", None)
    detail = "R rc 0 but no live holder in a new window after %ds" % R_PROOF_S
    fp = classify.fingerprint(rec.phase, "DETERMINISTIC", "!! " + detail, 0, "")
    rec.attempt += 1
    classify.apply_failure(rec, "DETERMINISTIC", fp, detail, now)
    return True
