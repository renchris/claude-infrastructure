#!/usr/bin/env python3
"""Replay the DESK lane over the recorded utilization series and score it on STRANDED WEEKLY QUOTA.

`score_interactive`'s docstring has said "re-run the replay after >=2 full weekly cycles before
treating either number as durable" since W1 and there was no replay to run — the W1 numbers came
from a harness that lived in a session and died with it. This is that harness, made re-runnable.

    scripts/desk-strand-replay.py                 # verdict for the shipped constants
    scripts/desk-strand-replay.py --sweep         # capture vs FULL_H, the plateau the pick sits on
    scripts/desk-strand-replay.py --flat          # counterfactual: the pre-W2 flat floor

WHAT IT MEASURES, and why this metric and not another. Actual burn cannot be replayed — the series
records where quota WENT, not where it would have gone under a different policy, and re-simulating
an operator's day is fiction. So the metric is the one thing a router controls: of the sweeps in an
account's final hours before a weekly reset, on how many did the desk lane NAME that account while
it still held headroom. Quota strands when nothing is pointed at it, so desk-time-on-target is the
lever, and it is observable rather than modelled.

    on-target  desk named the about-to-reset account AND it still had >1pp left
    exposure   desk named an account with <2pp left whose OWN reset is >5h away — the weekly wall
               DESK_W_FLOOR exists to prevent. This must not rise when the floor is loosened; it
               is the term that makes the trade honest rather than a one-sided win.

CAVEAT, standing: the window is short. Read a flat sweep as "the guard rarely binds here", never as
"the constant is validated" — the same absence-of-evidence caveat DESK_5H_FLOOR carries.
"""

import argparse
import collections
import importlib.machinery
import importlib.util
import json
import os
import sys
from datetime import datetime, timedelta

SRC = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "bin",
    "claude-accounts",
)
UTIL = os.environ.get("CC_UTIL_LOG") or os.path.expanduser(
    "~/.claude/logs/account-utilization.jsonl"
)

_argv, sys.argv = sys.argv, ["claude-accounts"]
_spec = importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", SRC)
)
ca = importlib.util.module_from_spec(_spec)
try:
    _spec.loader.exec_module(ca)
except SystemExit:
    pass
sys.argv = _argv

CFG = ca.load_cfg(need_claude_bin=False)


def load_sweeps(path=UTIL):
    """The series, regrouped into the SWEEPS it was written from: {ts: {acct: sample}}."""
    by_ts = collections.defaultdict(dict)
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue  # a torn tail line is data loss, never a crash
        by_ts[d["ts"]][d["acct"]] = d
    return [(ts, by_ts[ts]) for ts in sorted(by_ts)]


def to_row(d, now):
    """A recorded sample -> the row shape the scorers consume. Reset stamps become HOURS at `now`,
    which is what makes this a replay rather than a re-scoring at today's clock."""

    def hrs(key):
        v = d.get(key)
        if not v:
            return None
        try:
            return (datetime.fromisoformat(v) - now).total_seconds() / 3600.0
        except (TypeError, ValueError):
            return None

    # CONCURRENCY: use the instrument the series RECORDED when it has one. Rows written before
    # 2026-08-16 carry only `k`, and k_cap differs 5x by instrument (KMAX=8 for a work-charged row,
    # KMAX_RESIDENT=40 for a pane-charged one), so those are replayed as WORK — the strict end,
    # which can only over-report a kmax exclusion, never hide one. Any `kmax-concurrency` verdict
    # drawn from a legacy row is therefore an UPPER BOUND, not an attribution.
    legacy = "k_src" not in d
    return {
        "acct": d["acct"],
        "session_pct": d.get("session_pct"),
        "weekly_pct": d.get("weekly_pct"),
        "fable_pct": d.get("fable_pct"),
        "session_reset_h": hrs("session_reset_at"),
        "weekly_reset_h": hrs("weekly_reset_at"),
        "credits_on": d.get("credits_on", False),
        "auth": d.get("auth", "ok"),
        "k": d.get("k", 0),
        "k_work": d.get("k", 0) if legacy else d.get("k_work"),
        "k_src": "work" if legacy else d.get("k_src"),
        "k_phantom_desk": 0,
        "desk_incumbent": False,
    }


def resets(sweeps, drop=5):
    """(acct, ts, pct_before) per observed weekly reset. Detected by the quota DROP: weekly_reset_at
    drifts by minutes on every sweep, so an advance in that stamp is not a reset and reading it as
    one reports ~1,200 phantom resets."""
    prev, out = {}, []
    for ts, accts in sweeps:
        for a, d in accts.items():
            p = prev.get(a)
            if p is not None and p - d["weekly_pct"] >= drop:
                out.append((a, ts, p))
            prev[a] = d["weekly_pct"]
    return out


def measure(sweeps, events, hours=12.0):
    """(on_target, total, exposure) over each event's final `hours`."""
    on = tot = exposure = 0
    for acct, rts, _pct in events:
        end = datetime.fromisoformat(rts)
        start = end - timedelta(hours=hours)
        for ts, accts in sweeps:
            t = datetime.fromisoformat(ts)
            if not (start <= t <= end) or acct not in accts:
                continue
            scored = []
            for r in (to_row(d, t) for d in accts.values()):
                s, _why = ca.score_interactive(r, CFG)
                if s:
                    scored.append((s, r))
            if not scored:
                continue
            pick = max(scored, key=lambda x: x[0])[1]
            tot += 1
            if pick["acct"] == acct and (100 - pick["weekly_pct"]) > 1:
                on += 1
            T = pick["weekly_reset_h"]
            if (100 - pick["weekly_pct"]) < 2 and isinstance(T, (int, float)) and T > 5:
                exposure += 1
    return on, tot, exposure


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--sweep",
        action="store_true",
        help="capture across a range of DESK_W_FLOOR_FULL_H",
    )
    ap.add_argument(
        "--flat", action="store_true", help="counterfactual: the pre-W2 flat floor"
    )
    ap.add_argument(
        "--hours",
        type=float,
        default=12.0,
        help="endgame window per reset (default 12)",
    )
    ap.add_argument("--util", default=UTIL, help="utilization series path")
    a = ap.parse_args()

    sweeps = load_sweeps(a.util)
    if not sweeps:
        sys.exit(f"desk-strand-replay: no sweeps in {a.util}")
    events = resets(sweeps)
    print(f"{len(sweeps)} sweeps  {sweeps[0][0][:16]} -> {sweeps[-1][0][:16]}")
    seen = [d for _ts, accts in sweeps for d in accts.values()]
    legacy = sum(1 for d in seen if "k_src" not in d)
    if legacy:
        print(
            f"⚠ {legacy}/{len(seen)} rows predate k_src/k_work recording — replayed as WORK "
            f"(the strict cap), so any kmax exclusion below is an UPPER BOUND, not an attribution"
        )
    print(f"{len(events)} weekly resets observed:")
    for acct, ts, pct in events:
        print(
            f"    {acct:7s} {ts[:16]}  reset at {pct:3d}% used  -> {100 - pct:2d}pp stranded"
        )
    print()

    def run(label):
        on, tot, exp = measure(sweeps, events, a.hours)
        pct = on / tot * 100 if tot else 0.0
        print(
            f"{label:>22s} | on-target {on:4d}/{tot:<5d} = {pct:5.1f}% | wall-exposure {exp:4d}"
        )
        return pct

    print(f"{'policy':>22s} | {'desk-time on an expiring account':>32s} | guard")
    print("-" * 74)
    if a.sweep:
        for fh in (0, 8, 12, 18, 24, 36, 48):
            os.environ["CC_ROUTE_DESK_W_RAMP"] = "off" if fh == 0 else "on"
            os.environ["CC_ROUTE_DESK_W_FULL_H"] = str(fh or 24)
            run("FLAT (pre-W2)" if fh == 0 else f"ramp/{fh}h")
        os.environ.pop("CC_ROUTE_DESK_W_RAMP", None)
        os.environ.pop("CC_ROUTE_DESK_W_FULL_H", None)
        return
    if a.flat:
        os.environ["CC_ROUTE_DESK_W_RAMP"] = "off"
        run("FLAT (pre-W2)")
        os.environ.pop("CC_ROUTE_DESK_W_RAMP")
    run(f"SHIPPED (ramp/{ca.desk_w_floor_full_h(CFG['router']):.0f}h)")


if __name__ == "__main__":
    main()
