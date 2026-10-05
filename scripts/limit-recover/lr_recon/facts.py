"""The account fact ledger (§C4; invariants 13, 14).

A fact is "account X cannot serve scope S", one file per ``<acct>.<scope>`` under
``recon/facts/``. Facts are ADDED by a death verdict (hook/census) or a wire ``rejected`` read,
and removed only by the §C4 "Expires only when" rules below. Contradiction (a non-error turn in
scope after the fact was observed) marks a fact but never expires it: a fact that blocks idle
fan-out must still be honoured for sessions already LIMITED on it.

Scopes: "5h", "7d", "auth" (account-wide), "fable" (the fable lane), "model:<name>" (sessions on
that model only). ``<name>`` is lower-case, taken from the ``model_scoped:<Name>`` cap.

Never a limit signal here, by design: the usage endpoint integer >= 100, or a usage-endpoint 429.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime
import json
import os
import re
import sys
import tempfile
import time
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple

from lr_recon import types as T

GRACE_S = 60.0  # resets_at + 60 < now; wire read_at > observed_at + 60 (§C4)
WIRE_OK = ("allowed", "allowed_warning")
_WINDOW_OF_SCOPE = {"5h": "five_hour", "7d": "seven_day"}
_SCOPE_OF_CAP = {"five_hour": "5h", "seven_day": "7d"}
_MODEL_PREFIX = "model_scoped:"

OkTurn = Tuple[
    str, str, str, float
]  # (acct, model, lane, ts): a non-error assistant turn
OnBad = Callable[[str, Exception], None]


# ── store ────────────────────────────────────────────────────────────────────────────────────────


def _atomic_write(path: str, data: str) -> None:
    """tmp + fsync + os.replace in the same dir, so a reader sees the old fact or the new one."""
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=d)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def fact_path(paths: T.Paths, key: str) -> str:
    return os.path.join(paths.facts, key + ".json")


def load_facts(paths: T.Paths, on_bad: Optional[OnBad] = None) -> Dict[str, T.Fact]:
    """Every parseable fact, keyed ``<acct>.<scope>``. A bad file is reported, never fatal."""
    out: Dict[str, T.Fact] = {}
    try:
        names = sorted(os.listdir(paths.facts))
    except FileNotFoundError:
        return out
    for name in names:
        if not name.endswith(".json") or name.startswith("."):
            continue
        p = os.path.join(paths.facts, name)
        try:
            with open(p) as f:
                data = json.load(f)
            if (
                not isinstance(data, dict)
                or not data.get("acct")
                or not data.get("scope")
            ):
                raise ValueError("not a fact record")
            fact: T.Fact = T.from_dict(T.Fact, data)
        except (OSError, ValueError, TypeError) as e:
            if on_bad is not None:
                on_bad(p, e)
            continue
        out[fact.key] = fact
    return out


def merge(old: Optional[T.Fact], new: T.Fact) -> T.Fact:
    """§C4 merge: the first writer keeps observed_at (and its sid/src); a later writer may only
    RAISE resets_at; contradicted is sticky once true; untested clears once any writer tested."""
    if old is None:
        return new
    resets = old.resets_at
    if new.resets_at is not None and (resets is None or new.resets_at > resets):
        resets = new.resets_at
    return dataclasses.replace(
        old,
        resets_at=resets,
        contradicted=old.contradicted or new.contradicted,
        untested=old.untested and new.untested,
        window=old.window or new.window,
    )


def write_fact(paths: T.Paths, fact: T.Fact) -> T.Fact:
    """Merge ``fact`` into whatever is on disk for its key and write the result atomically."""
    p = fact_path(paths, fact.key)
    old: Optional[T.Fact] = None
    try:
        with open(p) as f:
            data = json.load(f)
        if isinstance(data, dict):
            old = T.from_dict(T.Fact, data)
    except (OSError, ValueError, TypeError):
        old = (
            None  # an unreadable predecessor loses: the new observation is the evidence
        )
    merged = merge(old, fact)
    _atomic_write(
        p, json.dumps(T.to_dict(merged), separators=(",", ":"), sort_keys=True)
    )
    return merged


def reap(paths: T.Paths, keys: Iterable[str]) -> int:
    """Delete expired fact files. The dir is bounded by accounts x scopes, so no sweep is needed."""
    n = 0
    for k in keys:
        try:
            os.unlink(fact_path(paths, k))
            n += 1
        except FileNotFoundError:
            pass
    return n


# ── producers ────────────────────────────────────────────────────────────────────────────────────


def scope_of(verdict: Dict[str, Any]) -> Optional[str]:
    """An ``lr_predicate`` verdict -> its fact scope, or None (not a fact: monthly spend, unknown
    cap, a non-limit error). An auth cliff is the "auth" scope: the account cannot serve at all."""
    if verdict.get("kind") == "auth_cliff":
        return "auth"
    if not verdict.get("limit"):
        return None
    cap = verdict.get("cap") or ""
    if cap in _SCOPE_OF_CAP:
        return _SCOPE_OF_CAP[cap]
    if cap.startswith(_MODEL_PREFIX):
        name = cap[len(_MODEL_PREFIX) :].strip().lower()
        if not name:
            return None
        return "fable" if name == "fable" else "model:" + name
    return None


def fact_from_death(
    acct: str, sid: str, verdict: Dict[str, Any], now: float, src: str
) -> Optional[T.Fact]:
    """A session's death -> a fact. The fable scope is ``untested`` (§C1: no instance seen)."""
    scope = scope_of(verdict)
    if scope is None or not acct:
        return None
    resets = verdict.get("resets_at")
    return T.Fact(
        acct=acct,
        scope=scope,
        window=_WINDOW_OF_SCOPE.get(scope, ""),
        resets_at=float(resets) if isinstance(resets, (int, float)) else None,
        first_sid=sid,
        observed_at=float(now),
        src=src,
        untested=(scope == "fable"),
    )


def facts_from_wire(rows: Iterable[Dict[str, Any]], now: float) -> List[T.Fact]:
    """``claude-accounts --json`` rows -> 5h/7d facts. The wire can only ADD a refusal."""
    out: List[T.Fact] = []
    for row in rows:
        name = row.get("name")
        wire = row.get("wire")
        if not name or not isinstance(wire, dict):
            continue
        for scope in ("5h", "7d"):
            if wire.get(scope + "_status") == "rejected":
                out.append(
                    T.Fact(
                        acct=str(name),
                        scope=scope,
                        window=_WINDOW_OF_SCOPE[scope],
                        observed_at=float(now),
                        src="wire",
                    )
                )
    return out


# ── lifecycle ────────────────────────────────────────────────────────────────────────────────────


def _epoch(v: Any) -> Optional[float]:
    """An epoch number or an ISO-8601 string -> epoch seconds; anything else -> None."""
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
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


def _rows_for(wire_rows: Iterable[Dict[str, Any]], acct: str) -> List[Dict[str, Any]]:
    return [r for r in wire_rows if r.get("name") == acct]


def _wire_read_at(row: Dict[str, Any]) -> Optional[float]:
    wire = row.get("wire")
    return _epoch(wire.get("read_at")) if isinstance(wire, dict) else None


def _wire_clears(fact: T.Fact, rows: List[Dict[str, Any]]) -> bool:
    """5h/7d: a read of THE SAME WINDOW says allowed, stamped > observed_at + 60. No read_at ⇒
    never (W1: no producer stamps it yet, and an unstamped read may predate the death)."""
    for row in rows:
        wire = row.get("wire")
        read_at = _wire_read_at(row)
        if not isinstance(wire, dict) or read_at is None:
            continue
        if (
            wire.get(fact.scope + "_status") in WIRE_OK
            and read_at > fact.observed_at + GRACE_S
        ):
            return True
    return False


def _auth_clears(
    fact: T.Fact, rows: List[Dict[str, Any]], ok_turns: Iterable[OkTurn]
) -> bool:
    """auth: BOTH an ``auth == ok`` read after observed_at AND a non-error turn after it."""
    read_ok = False
    for row in rows:
        read_at = _epoch(row.get("read_at"))
        if read_at is None:
            read_at = _wire_read_at(row)
        if (
            row.get("auth") == "ok"
            and read_at is not None
            and read_at > fact.observed_at
        ):
            read_ok = True
    if not read_ok:
        return False
    return any(t[0] == fact.acct and t[3] > fact.observed_at for t in ok_turns)


def reset_passed(fact: T.Fact, now: float) -> bool:
    return fact.resets_at is not None and fact.resets_at + GRACE_S < now


def expire(
    facts: Dict[str, T.Fact],
    now: float,
    wire_rows: Iterable[Dict[str, Any]],
    ok_turns: Iterable[OkTurn],
) -> List[str]:
    """Keys that expire under §C4 "Expires only when". Contradiction never expires a fact;
    ``model:*`` and ``fable`` expire only at resets_at."""
    rows_all = list(wire_rows)
    turns = list(ok_turns)
    out: List[str] = []
    for key, fact in sorted(facts.items()):
        rows = _rows_for(rows_all, fact.acct)
        if (
            reset_passed(fact, now)
            or (fact.scope in _WINDOW_OF_SCOPE and _wire_clears(fact, rows))
            or (fact.scope == "auth" and _auth_clears(fact, rows, turns))
        ):
            out.append(key)
    return out


def covers(fact: T.Fact, lane: str, model: str) -> bool:
    """Does ``fact`` apply to a session on (lane, model)? Account-wide scopes cover everything."""
    if fact.account_wide:
        return True
    m = (model or "").lower()
    if fact.scope == "fable":
        return lane == "fable" or "fable" in m
    if fact.scope.startswith("model:"):
        name = fact.scope[len("model:") :]
        return bool(name) and name in m
    return False


def contradict(facts: Dict[str, T.Fact], ok_turns: Iterable[OkTurn]) -> List[str]:
    """Mark facts contradicted by an in-scope non-error turn after observed_at (in place).
    Returns the newly contradicted keys; the caller persists them via write_fact."""
    turns = list(ok_turns)
    out: List[str] = []
    for key, fact in sorted(facts.items()):
        if fact.contradicted:
            continue
        for acct, model, lane, ts in turns:
            if (
                acct == fact.acct
                and ts > fact.observed_at
                and covers(fact, lane, model)
            ):
                facts[key] = dataclasses.replace(fact, contradicted=True)
                out.append(key)
                break
    return out


_BLOCK_ORDER = {"auth": 0, "7d": 1, "5h": 2, "fable": 3}


def blocking(
    facts: Dict[str, T.Fact], acct: str, lane: str, model: str, now: float
) -> Optional[T.Fact]:
    """The fact that stops (acct, lane, model) from serving now, or None. An auth fact always
    blocks; any other covering fact blocks until its reset has passed.

    With several, the one returned is the one that BINDS: auth first (no reset frees it), then the
    latest known reset, because the account serves again only once every covering window has
    reset. A fact with no known reset ranks after those, and scope order only breaks a tie. Ranked
    on scope first, a 7d fact resetting 09:00Z was returned over the 5h fact resetting 09:40Z, and
    every reader took the earlier reset for the end of the block (W7h, next4 2026-10-04)."""
    hits = [
        f
        for f in facts.values()
        if f.acct == acct
        and (f.scope == "auth" or (covers(f, lane, model) and not reset_passed(f, now)))
    ]
    if not hits:
        return None
    hits.sort(
        key=lambda f: (
            f.scope != "auth",
            -(f.resets_at or 0.0),  # no known reset sorts after every known one
            _BLOCK_ORDER.get(f.scope, 4),
        )
    )
    return hits[0]


def limited_rows(facts: Dict[str, T.Fact], now: float) -> List[Dict[str, Any]]:
    """Rows for ``cc-lr accounts --limited``: every fact whose reset has not passed."""
    rows = [
        {
            "acct": f.acct,
            "scope": f.scope,
            "resets_at": f.resets_at,
            "src": f.src,
            "observed_at": f.observed_at,
            "contradicted": f.contradicted,
            "untested": f.untested,
        }
        for f in facts.values()
        if not reset_passed(f, now)
    ]
    rows.sort(key=lambda r: (r["acct"], r["scope"]))
    return rows


# ── hook CLI (hooks/stop-failure-marker.sh) ──────────────────────────────────────────────────────
# The hook is the fastest producer (it fires at the instant of death) and it is shell, so it
# reaches the ledger through this one entry rather than hand-writing JSON: the §C4 merge rules
# (first observed_at wins, resets_at only rises) live in write_fact and nowhere else.

_SAFE_ACCT_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
_SCOPE_RE = re.compile(r"^(5h|7d|auth|fable|model:[a-z0-9._-]{1,64})$")


def fact_from_hook(
    acct: str, sid: str, scope: str, resets_at: Optional[float], now: float
) -> T.Fact:
    """A hook death -> a fact. Same shape as fact_from_death, but the hook has already decided
    the scope from the payload, so it is taken as given (validated by the caller)."""
    return T.Fact(
        acct=acct,
        scope=scope,
        window=_WINDOW_OF_SCOPE.get(scope, ""),
        resets_at=resets_at,
        first_sid=sid,
        observed_at=float(now),
        src="hook",
        untested=(scope == "fable"),
    )


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(
        prog="lr_recon.facts", description=__doc__.splitlines()[0]
    )
    sub = ap.add_subparsers(dest="cmd", required=True)
    hw = sub.add_parser(
        "hook-write", help="merge one hook-observed fact into the ledger"
    )
    hw.add_argument("--acct", required=True)
    hw.add_argument("--sid", default="")
    hw.add_argument("--scope", required=True)
    hw.add_argument("--resets-at", default="", help="epoch seconds; empty = unknown")
    args = ap.parse_args(argv)
    # A path-unsafe account or an unknown scope would name a file the reader never looks up,
    # so it is refused rather than sanitized — the same "drop, never clean" rule the hook uses.
    if not _SAFE_ACCT_RE.match(args.acct) or not _SCOPE_RE.match(args.scope):
        print("hook-write: bad --acct or --scope", file=sys.stderr)
        return 2
    resets: Optional[float] = None
    if args.resets_at:
        try:
            resets = float(args.resets_at)
        except ValueError:
            resets = None  # an unparseable reset is an unknown reset, never a refusal
    merged = write_fact(
        T.Paths.from_env(),
        fact_from_hook(args.acct, args.sid, args.scope, resets, time.time()),
    )
    print(json.dumps(T.to_dict(merged), separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
