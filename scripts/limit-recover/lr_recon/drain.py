"""The capped-account drain, folded into lr_recon (lr-wake 2026-10-18, Wave G; RC7).

``~/.reso/limit-recover/listeners/drain-v2.sh`` was an agent-installed LaunchAgent
(``com.reso.drain-to-next3``) that rotated account next4 onto next2 "once capped/rejected or past
its weekly reset". The last clause was the defect: past the reset next4 was HEALTHY, so every
~10 min it re-rotated healthy sessions, each run ending rc=1 (18:37Z, 18:49Z, 19:01Z on 10-18),
until the operator paused it. This is the same branch with two changes:

- **capped is reset-aware** (``capped.capped``): a passed reset, or a fresh usage row under 100,
  reads NOT capped. Past the reset there is nothing to drain.
- **rc=1 stops the window**: the first rotate that fails latches ``stopped`` for that window
  (``<recon root>/drain/<acct>.<scope>.json``); nothing re-runs it until a new window is capped.

    python3 -m lr_recon.drain --from next4 --to next2 [--fallback next3] [--scope 7d]
                              [--until-idle 3600] [--act]

Without ``--act`` it prints the decision and runs nothing. Switches: ``LR_DRAIN=off`` or
``<recon root>/drain.off``. The standing next→next3 move of drain-v2 is NOT folded: it was a
one-night operator preference, not a recovery rule. Nothing here loads, unloads or edits a
LaunchAgent; the paused drain stays paused until the operator re-points or retires it (Q2).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

from lr_recon import capped, store
from lr_recon import facts as F
from lr_recon import types as T
from lr_recon.clock import run_bounded

OVERFLOW_SESSION_PCT = (
    85  # drain-v2's "unroutable or >= 85% of its 5h window falls to the other"
)


def latch_path(paths: T.Paths, acct: str, scope: str) -> str:
    return os.path.join(paths.root, "drain", "%s.%s.json" % (acct, scope))


def read_latch(paths: T.Paths, acct: str, scope: str) -> Dict[str, Any]:
    try:
        with open(latch_path(paths, acct, scope), "r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_latch(paths: T.Paths, acct: str, scope: str, data: Dict[str, Any]) -> None:
    p = latch_path(paths, acct, scope)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    store.atomic_write_json(p, data)


def window_of(
    acct: str,
    scope: str,
    facts: Dict[str, T.Fact],
    usage: Dict[str, Dict[str, Any]],
) -> float:
    """The window being drained, keyed by its reset (0 when no reading names one)."""
    f = facts.get("%s.%s" % (acct, scope))
    if f is not None and f.resets_at:
        return float(f.resets_at)
    row = usage.get(acct) or {}
    at = capped._epoch(row.get(capped._RESET.get(scope, "")))
    return float(at or 0)


def decide(
    acct: str,
    scope: str,
    facts: Dict[str, T.Fact],
    usage: Dict[str, Dict[str, Any]],
    latch: Dict[str, Any],
    now: float,
) -> Tuple[bool, str, float]:
    """(drain, why, window). Not capped ⇒ never. Capped but this window's drain already ended
    rc=1 ⇒ stopped. A latched window that has reset is a new window."""
    window = window_of(acct, scope, facts, usage)
    latched = float(latch.get("window") or 0)
    is_capped, why = capped.capped(
        acct, scope, facts, usage, now, latched if latched else None
    )
    if latched and not is_capped:
        # the latched window may have passed while a new one is capped: judge the current one
        is_capped, why = capped.capped(acct, scope, facts, usage, now)
    if not is_capped:
        return False, "%s not capped: %s" % (acct, why), window
    if latch.get("stopped") and latched and window and latched == window:
        return (
            False,
            "%s capped (%s), but this window's drain already ended rc=%s at %s; stopped until a new window"
            % (acct, why, latch.get("rc"), latch.get("at_utc", "?")),
            window,
        )
    return True, "%s capped: %s" % (acct, why), window


def pick_target(to: str, fallback: str, usage: Dict[str, Dict[str, Any]]) -> str:
    """drain-v2's overflow: a target at or over 85% of its 5h window falls to the fallback."""
    if not fallback:
        return to
    row = usage.get(to) or {}
    pct = capped._pct(row, "5h")
    if pct is not None and pct >= OVERFLOW_SESSION_PCT:
        return fallback
    return to


def cclr_bin() -> str:
    return os.environ.get("LR_DRAIN_CCLR_BIN") or os.path.join(
        os.path.dirname(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        ),
        "bin",
        "cc-lr",
    )


def run(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(
        prog="lr_recon.drain", description=__doc__.splitlines()[0]
    )
    ap.add_argument("--from", dest="src", required=True)
    ap.add_argument("--to", required=True)
    ap.add_argument("--fallback", default="")
    ap.add_argument("--scope", default="7d", choices=("7d", "5h"))
    ap.add_argument("--until-idle", type=int, default=3600)
    ap.add_argument("--act", action="store_true")
    ap.add_argument("--root", help="reconciler state root (default LR_RECON_ROOT)")
    a = ap.parse_args(argv)
    paths = T.Paths.from_env(root=a.root)
    now = time.time()
    if os.environ.get("LR_DRAIN", "on") == "off" or os.path.exists(
        os.path.join(paths.root, "drain.off")
    ):
        print("lr_recon.drain: off (LR_DRAIN=off or drain.off); nothing run")
        return 0
    home = os.environ.get("HOME", os.path.expanduser("~"))
    facts = F.load_facts(paths)
    usage = capped.latest_usage(home, now)
    latch = read_latch(paths, a.src, a.scope)
    go, why, window = decide(a.src, a.scope, facts, usage, latch, now)
    if not go:
        if latch.get("stopped") and "stopped until" not in why:
            write_latch(paths, a.src, a.scope, {})  # the stopped window is over
        print("lr_recon.drain: hold — %s" % why)
        return 0
    to = pick_target(a.to, a.fallback, usage)
    cmd = [
        "/bin/bash",
        cclr_bin(),
        "rotate",
        "--account",
        a.src,
        "--to",
        to,
        "--until-idle",
        str(a.until_idle),
        "--no-wait",
    ]
    if not a.act:
        print("lr_recon.drain: would run — %s; %s" % (" ".join(cmd[1:]), why))
        return 0
    try:
        rc = run_bounded(cmd, stdin=subprocess.DEVNULL, timeout=4 * 3600).returncode
    except (OSError, subprocess.TimeoutExpired):
        rc = 124
    write_latch(
        paths,
        a.src,
        a.scope,
        {
            "window": window,
            "rc": rc,
            "stopped": rc == 1,
            "at": now,
            "at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
            "to": to,
        },
    )
    print(
        "lr_recon.drain: rotate %s → %s rc=%d%s"
        % (a.src, to, rc, " — stopped for this window" if rc == 1 else "")
    )
    return 0 if rc in (0, 1) else rc


if __name__ == "__main__":
    sys.exit(run())
