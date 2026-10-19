"""Is an account capped right now? The reset-aware answer (lr-wake 2026-10-18, Wave G).

Two decisions went wrong on 2026-10-18 for the same reason: "capped" was read off a fact that had
outlived its window.

- **The cohort that never expired** (h defect 3). Cohort ``next4-7d-1792314000`` still held 3e929a81
  PRE-MOVE 11 h after it formed, when next4's weekly limit had reset (5% used). A member whose
  source is under its caps, or past the cohort's reset, has nothing to move: it goes NOT_NEEDED and
  is continued in place (``settle.cohort_exit``).
- **The drain that re-rotated healthy sessions** (RC7). ``drain-v2.sh`` treated "past its weekly
  reset" as a reason to rotate next4, so after the reset it re-rotated healthy next4 sessions every
  ~10 min, each ending rc=1. Here past the reset is NOT capped, and ``lr_recon.drain`` stops a
  window's drain after its first rc=1.

Evidence, in order: the window's reset (passed ⇒ not capped), a server rejection on the wire
(capped), a live uncontradicted fact (capped), the newest usage row (``weekly_pct``/``session_pct``
at 100 ⇒ capped, under 100 and read after the fact ⇒ under its caps). Recovery needs POSITIVE
evidence; a missing reading never reads as recovered. Pure, apart from ``latest_usage``'s one read.
"""

from __future__ import annotations

import datetime
import json
import os
import time
from typing import Any, Dict, Optional, Tuple

from lr_recon import facts as F
from lr_recon import types as T

USAGE_MAX_AGE_S = 900.0  # a usage row older than this is no reading (claude-accounts refreshes ~5 min)
USAGE_TAIL_BYTES = 256 * 1024
_PCT = {"7d": "weekly_pct", "5h": "session_pct"}
_RESET = {"7d": "weekly_reset_at", "5h": "session_reset_at"}
_WIRE = {"7d": "wire_7d_status", "5h": "wire_5h_status"}


def usage_file(home: str) -> str:
    return os.environ.get("LR_RECON_USAGE_FILE") or os.path.join(
        home, ".claude", "logs", "account-utilization.jsonl"
    )


def _epoch(v: Any) -> Optional[float]:
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return float(v)
    if isinstance(v, str) and v:
        try:
            dt = datetime.datetime.fromisoformat(v.replace("Z", "+00:00"))
        except ValueError:
            return None
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        return dt.timestamp()
    return None


def latest_usage(
    home: str, now: Optional[float] = None, max_age_s: float = USAGE_MAX_AGE_S
) -> Dict[str, Dict[str, Any]]:
    """The newest non-stale row per account from the tail of ``account-utilization.jsonl``, with
    ``read_at`` (epoch) added. Rows older than ``max_age_s`` are dropped. Never raises."""
    now = time.time() if now is None else now
    out: Dict[str, Dict[str, Any]] = {}
    try:
        with open(usage_file(home), "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - USAGE_TAIL_BYTES))
            data = fh.read().decode("utf-8", "replace")
    except OSError:
        return out
    for line in data.splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if not isinstance(row, dict) or not row.get("acct") or row.get("stale"):
            continue
        at = _epoch(row.get("ts"))
        if at is None or now - at > max_age_s:
            continue
        prev = out.get(str(row["acct"]))
        if prev is None or at >= prev["read_at"]:
            out[str(row["acct"])] = dict(row, read_at=at)
    return out


def _pct(row: Dict[str, Any], scope: str) -> Optional[float]:
    v = row.get(_PCT.get(scope, ""))
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    return float(v)


def capped(
    acct: str,
    scope: str,
    facts: Dict[str, T.Fact],
    usage: Dict[str, Dict[str, Any]],
    now: float,
    resets_at: Optional[float] = None,
) -> Tuple[bool, str]:
    """(capped, why) for ``acct``'s ``scope`` window (``7d``/``5h``). ``resets_at`` is the window
    the caller is acting on (a cohort's key, a drain's latched window): once it has passed, the
    account is not capped on THAT window whatever an old fact or row says."""
    if resets_at is not None and resets_at + F.GRACE_S < now:
        return False, "past its reset at %s" % _hm(resets_at)
    row = usage.get(acct) or {}
    if row.get(_WIRE.get(scope, "")) == "rejected":
        return True, "the server rejects its %s window" % scope
    fact = facts.get("%s.%s" % (acct, scope))
    pct = _pct(row, scope)
    if fact is not None and not fact.contradicted and not F.reset_passed(fact, now):
        # a usage row read AFTER the fact, under 100, outranks it (the fact may predate a reset the
        # row has seen); anything else leaves the fact standing
        fresher = (
            bool(row) and float(row.get("read_at") or 0) > fact.observed_at + F.GRACE_S
        )
        if not (fresher and pct is not None and pct < 100):
            return True, "a live %s fact%s" % (
                scope,
                " (resets %s)" % _hm(fact.resets_at) if fact.resets_at else "",
            )
    if pct is None:
        return False, "no %s reading" % scope
    if pct >= 100:
        row_reset = _epoch(row.get(_RESET.get(scope, "")))
        if row_reset is not None and row_reset + F.GRACE_S < now:
            return False, "its %s window reset at %s" % (scope, _hm(row_reset))
        return True, "%s at %d%%" % (_PCT[scope], pct)
    return False, "under its caps (%s %d%%)" % (_PCT[scope], pct)


def recovered(
    acct: str,
    scope: str,
    facts: Dict[str, T.Fact],
    usage: Dict[str, Dict[str, Any]],
    now: float,
    resets_at: Optional[float] = None,
) -> str:
    """The proof that ``acct`` can serve its ``scope`` window again, or '' when that is not proven.
    Positive evidence only: the window's reset passed, a contradicted fact (it served a turn), or a
    fresh usage row under 100 with no live fact newer than it."""
    if not acct or scope not in _PCT:
        return ""
    if resets_at is not None and resets_at + F.GRACE_S < now:
        return "%s is past the reset at %s" % (acct, _hm(resets_at))
    fact = facts.get("%s.%s" % (acct, scope))
    if fact is not None and fact.contradicted:
        return "%s served a turn since its %s limit" % (acct, scope)
    is_capped, why = capped(acct, scope, facts, usage, now, resets_at)
    if is_capped or not why.startswith("under its caps"):
        return ""
    return "%s is %s" % (acct, why)


def _hm(ts: Optional[float]) -> str:
    return "?" if ts is None else time.strftime("%Y-%m-%dT%H:%MZ", time.gmtime(ts))
