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
    reasons = _REASON.findall(text)
    if reasons and rec.phase == "PRE-MOVE":
        reason = reasons[-1].rstrip(":")
        disp, sub = classify.map_notmoved(reason, rec.kind)
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
    if rc == 0:
        return "%s rc=0" % pr.argv_hash
    if rc is None:
        # Adopted by argv, or exited before this daemon could reap it: no code is no verdict. The
        # derived phase is the truth; scoring it as a failure escalated a move that had engaged.
        return "%s exited, code unknown — the phase decides" % pr.argv_hash
    disp, sub, reason = outcome(rec, rc, text)
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
        if pre:
            rec.substate = sub or "WAIT_SLOT"
            rec.wait = T.Wait(reason=rec.substate, since=now, eta=now + 60.0)
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


def dead_actuators(
    procs: List[T.ProcRole], exits: Dict[int, int]
) -> List[Tuple[T.ProcRole, Optional[int]]]:
    """Pair each dead actuator with its exit code (None: exited before this daemon, or adopted)."""
    return [(p, exits.pop(p.pid, None)) for p in procs if p.role == "actuator"]
