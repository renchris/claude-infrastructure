"""classify.py: class first, fingerprint second (§7.2).

A failure is first put in a CLASS by an explicit allowlist, and only what no list claims is a
DETERMINISTIC candidate. That order is the point: a slow boot or a kitty timeout that repeats all night
must back off and never escalate, while an unknown error that repeats exactly is a real defect and
stops (ESCALATED) with evidence instead of looping. The fingerprint then decides "the same error":
phase, class, the first ``!!`` line with digits and paths normalised, and the actuator script's sha.

The frozen Record has no paging field, so paging is carried in the returned disposition.
"""

import re
from typing import Dict, List, Optional, Pattern, Tuple

from lr_recon import types as T

BACKOFF_S = (10, 30, 60, 120)  # then doubling, capped
BACKOFF_CAP_S = 300
PAGE_AT = 6  # the TRANSIENT attempt that first pages
PAGE_EVERY = (
    12  # at the 300 s cap, 12 attempts ~ one hour: "hourly after" with no clock field
)
REARM_S = 900.0  # an ESCALATED record re-arms after 15 minutes regardless of inputs
COUNTED = ("TRANSIENT", "DETERMINISTIC", "IMPOSSIBLE")  # WAIT and HOLD are not attempts

_PATH = re.compile(r"(?:~|(?<![\w.~])/)[^\s:'\"()\[\],;]*[^\s:'\"()\[\],;.]")
_DIGITS = re.compile(r"\d+")
_KILLED_RC = frozenset((124, 137, 143, -9, -15))


def _rx(*alts: str) -> List[Pattern[str]]:
    return [re.compile(a, re.IGNORECASE) for a in alts]


# Checked in this order; the first class with a match wins. IMPOSSIBLE and HOLD first, because a text
# naming a draft or a headless session must never be retried as a transient.
_CLASSES: Tuple[Tuple[str, List[Pattern[str]]], ...] = (
    (
        "IMPOSSIBLE",
        _rx(
            r"launcher[- ]rooted",
            r"\bheadless\b",
            r"\bcwd\b.{0,20}\b(?:gone|missing|does not exist|no such)",
        ),
    ),
    (
        "HOLD",
        _rx(
            r"\bdraft\b",
            r"\bbackground work\b|\bbg-work\b",
            r"\blive subagents?\b|\bsubagents? (?:still )?(?:live|running)\b",
            r"\bheld:team\b",
            r"\bcomposer\b.{0,20}\bunreadable\b|\bunreadable composer\b",
            r"\bparked menu\b|\bmenu parked\b|\bhold-menu\b",
            r"\brepo(?:sitory)?\b.{0,10}\bbare\b|\bcore\.bare\b|\brepo-bare\b",
            r"\biterm",
        ),
    ),
    (
        "WAIT",
        _rx(
            r"\bno routable target\b",
            r"\bcapacity\b.{0,10}\brefused\b|\bcapacity-refused\b",
            # capacity-admit's own shed wording (boot-resume-launch exit 9, lr-fire-resume):
            # "capacity-admit: REFUSING resume <sid> on <acct> — load …"
            r"\bcapacity-admit\b.{0,20}\brefus",
            r"\bevery account\b.{0,10}\blimited\b|\ball accounts\b.{0,10}\blimited\b",
            r"\brouter (?:exit|rc)[ =:]*3\b",
            r"\btarget[-_]limited\b",
            r"\btarget[-_]auth\b",
        ),
    ),
    (
        "TRANSIENT",
        _rx(
            r"\bkitty\b.{0,40}\btime[d ]*out\b|\brpc time[d ]*out\b",
            r"\bsurface rc[ =:]*3\b",
            r"\bresolved to no tty\b",
            r"\bno claude process appeared within\b",
            r"\block\b.{0,20}\bbusy\b|\bbusy\b.{0,10}\block\b",
            r"\brouter (?:exit|rc)[ =:]*5\b",
            r"\b429\b",
            r"\bswallowed enter\b|\benter\b.{0,10}\bswallowed\b",
            r"\bkilled (?:actuator|watcher)\b|\b(?:actuator|watcher)\b.{0,10}\bkilled\b",
            r"\bcc_tui_submit\b.{0,40}\bmangled\b",
            r"\bbackground dialog\b.{0,30}\breappear|\bdialog reappeared\b",
        ),
    ),
)


def _norm(line: str) -> str:
    return _DIGITS.sub("N", _PATH.sub("<path>", line.strip()))[:240]


def fingerprint(
    phase: str, cls: str, stderr_text: str, rc: int, script_sha: str
) -> str:
    """(phase, class, first ``!!`` line normalised, script sha); without a ``!!`` line the rc and the
    last non-empty stderr line stand in. Digits and paths are normalised so a pid, a port or a tmp path
    does not make one recurring error look new."""
    lines = [ln for ln in stderr_text.splitlines() if ln.strip()]
    bang = next((ln for ln in lines if ln.lstrip().startswith("!!")), None)
    if bang is not None:
        body = _norm(bang)
    else:
        body = "rc=%d %s" % (rc, _norm(lines[-1]) if lines else "")
    return "|".join((phase, cls, body.rstrip(), script_sha))


def classify(text: str, rc: int) -> str:
    """A T.ERROR_CLASSES member. Allowlists first; a killed actuator (rc 124/137/143) is TRANSIENT;
    everything else is a DETERMINISTIC candidate (it escalates only on a repeat, see apply_failure)."""
    for cls, pats in _CLASSES:
        if any(p.search(text) for p in pats):
            return cls
    if rc in _KILLED_RC:
        return "TRANSIENT"
    return "DETERMINISTIC"


def map_notmoved(reason: str, kind: str, pane_at_shell: bool = True) -> Tuple[str, str]:
    """The probe's NOTMOVED reason -> (disposition, substate) per the §7.2 table. The disposition is an
    outcome (NOT_NEEDED), a class (WAIT/HOLD/TRANSIENT/DETERMINISTIC) or a phase (EXITED)."""
    r = reason.strip().lower()
    if r == "not-limited":
        return ("NOT_NEEDED", "") if kind == "limited" else ("WAIT", "WAIT_DATA")
    if r == "teammate":
        return ("NOT_NEEDED", "")  # the lead owns it
    if r == "draft":
        return ("HOLD", "HOLD-DRAFT")
    if r == "bg-work":
        return ("HOLD", "HOLD-BGWORK")
    if r == "pane-not-cc":
        return ("EXITED", "") if pane_at_shell else ("TRANSIENT", "")
    if r.startswith("unreadable"):
        return ("TRANSIENT", "")
    if r.startswith("capacity"):
        return ("WAIT", "WAIT_CAPACITY")
    if r.startswith("router"):
        return ("TRANSIENT", "") if re.search(r"\b5\b", r) else ("WAIT", "WAIT_SLOT")
    return ("DETERMINISTIC", "")


def backoff_s(n: int) -> int:
    """The n-th TRANSIENT attempt's delay: 10/30/60/120, then doubling, capped at 300 s."""
    if n <= len(BACKOFF_S):
        return BACKOFF_S[max(n, 1) - 1]
    return min(BACKOFF_CAP_S, BACKOFF_S[-1] << min(n - len(BACKOFF_S), 8))


def apply_failure(rec: T.Record, cls: str, fp: str, detail: str, now: float) -> str:
    """Record one failure and return its disposition: BACKOFF, BACKOFF_PAGE, WAIT, HOLD, RETRY,
    ESCALATED or IMPOSSIBLE.

    WAIT and HOLD bump their per-class count but are not attempts, so they leave ``last_error`` alone:
    a WAIT between two identical DETERMINISTIC failures does not break "consecutive"."""
    rec.attempts_by_class[cls] = rec.attempts_by_class.get(cls, 0) + 1
    if cls not in COUNTED:
        return "HOLD" if cls == "HOLD" else "WAIT"
    prev: Optional[T.LastError] = rec.last_error
    rec.last_error = T.LastError(cls=cls, fingerprint=fp, detail=detail, at=now)
    if cls == "TRANSIENT":
        n = rec.attempts_by_class[cls]
        rec.next_eligible_at = now + backoff_s(n)
        page = n == PAGE_AT or (n > PAGE_AT and (n - PAGE_AT) % PAGE_EVERY == 0)
        return "BACKOFF_PAGE" if page else "BACKOFF"
    if cls == "IMPOSSIBLE":
        return "IMPOSSIBLE"
    if prev is not None and prev.cls == "DETERMINISTIC" and prev.fingerprint == fp:
        rec.escalated = True
        rec.next_eligible_at = None
        return "ESCALATED"
    rec.next_eligible_at = now + BACKOFF_S[0]
    return "RETRY"


def should_rearm(
    rec: T.Record, now: float, inputs: Dict[str, str], prev_inputs: Dict[str, str]
) -> bool:
    """An ESCALATED record re-arms at 15 minutes, or when any input changed: actuator scripts sha, the
    repo's core.bare/worktree list, the eligibility set, the pane's (pid, lstart), a lock holder, the
    load-below-failure flag. The caller encodes each as a string; a key appearing or vanishing is a
    change. An empty ``prev_inputs`` is no baseline, so only the clock can re-arm."""
    if not rec.escalated:
        return False
    if rec.last_error is not None and now - rec.last_error.at >= REARM_S:
        return True
    if not prev_inputs:
        return False
    return any(
        inputs.get(k) != prev_inputs.get(k) for k in set(inputs) | set(prev_inputs)
    )


def rearm(rec: T.Record, now: float) -> None:
    """Clear ESCALATED and reset the attempt counters for one re-fire. ``last_error`` stays, so the
    same fingerprint failing again escalates at once instead of earning a second free attempt."""
    rec.escalated = False
    for cls in COUNTED:
        rec.attempts_by_class.pop(cls, None)
    rec.next_eligible_at = now
