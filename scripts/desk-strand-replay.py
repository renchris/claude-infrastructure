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


def resets(sweeps, drop=5, roll_s=3600):
    """(acct, ts, pct_before, pct_used) per observed weekly reset — a quota DROP whose WINDOW also
    moved. The drop alone was the whole test until 2026-09-06, on the evidence that `weekly_pct`
    never decreased inside a window (0/8, weekly-reset-utilization-2026-08-25 §2).

    THAT PREMISE DIED ON 2026-09-01. The endpoint began zeroing the meter MID-window on all four
    accounts — seven times in five days — leaving the window's close exactly where it was. `next2`
    fell 49 -> 0 on 09-04 and still closed that same window at 73% cumulative. Read as a reset,
    that window reports "22% used -> 78pp stranded": a 51 pp overstatement, in the one number the
    operator reads to decide how hard to run the fleet. The shape is visible in the predecessor's
    own output — it reported 20 resets of which "8 share two instants, which is not what four
    independent weekly resets look like", and worked around it by scoring only the solo instants.
    They are not resets at all.

    So require the other half: the window's CLOSE must move ~7 days. Two traps make that harder
    than reading the field.
      · At a zeroing of EITHER kind the endpoint stops publishing a close — `weekly_reset_at` goes
        null and stays null for minutes to hours (next4 held null for 9 h on 2026-09-01). So the
        comparison is against the next NON-NULL stamp, forward-filled. Judging on the null itself
        admits every mid-window zeroing: that is how next4's 09-01 event read as a reset stranding
        90 pp while its window was simply still running.
      · The stamp jitters sub-second between sweeps, so this is a tolerance and not an equality —
        equality mints thousands of phantom rollovers (§1, trap 1). An hour sits far above the
        jitter and far below a real advance.

    A mid-window zeroing is therefore not a reset, and the percentage it discards is not stranded
    quota — it is quota already spent that the meter forgot. `pct_used` adds those segments back;
    it equals `pct_before` where no zeroing happened, so the two differ only where the meter is
    known to understate. WHAT the zeroing is remains open: the vendor was never observed doing it
    before 2026-09-01 and this store cannot say why.

    A sample can carry `weekly_pct: null` — the sweep reached the account and could not READ its
    weekly meter (logged out, a token refusal, a shape the reader did not parse). That is an
    ABSENT observation, not a value, and it used to crash this whole tool on the subtraction
    below: two such rows out of 20,306 made the replay the item's own next step names unrunnable.
    Neither obvious repair is safe, so the direction is chosen explicitly:

      · treating null as 0 would mint a phantom reset at every hole — the exact failure the drop
        detector exists to avoid;
      · clearing `prev` would DROP a real reset that happens to straddle the hole, because the
        next readable sample would have nothing to be compared against.

    So a hole is SKIPPED and `prev` is carried across it: the comparison resumes at the next
    readable sample, against the last one that was actually observed. The count is returned and
    printed, because a replay over a series with silent holes is precisely the absence-of-evidence
    reading this file's standing CAVEAT warns about."""
    seq = collections.defaultdict(list)
    for ts, accts in sweeps:
        for a, d in accts.items():
            seq[a].append((ts, d))
    out, holes = [], 0
    for a, rows in seq.items():
        # Each sample's next KNOWN close, forward-filled, so a run of nulls decides nothing.
        nxt, carry = [None] * len(rows), None
        for i in range(len(rows) - 1, -1, -1):
            carry = rows[i][1].get("weekly_reset_at") or carry
            nxt[i] = carry
        # `whole` = has this account's window been watched from its own start? The ledger opens
        # mid-window and its first samples flap (58% then lower then higher, 2026-08-10); summing
        # those segments publishes 158% used. A window we did not see begin is reported off the
        # meter alone.
        prev, segs, whole = None, [0], False
        for i, (ts, d) in enumerate(rows):
            cur = d.get("weekly_pct")
            if not isinstance(cur, (int, float)):
                holes += 1
                continue  # unreadable ⇒ no observation; prev is deliberately NOT touched
            if prev is not None and prev[0] - cur >= drop and _rolled(prev[1], nxt[i], roll_s):
                out.append((a, ts, prev[0], sum(segs) if whole else prev[0]))
                segs, whole = [0], True
            elif cur < segs[-1] - 1:
                segs.append(cur)      # a zeroing INSIDE the window: the meter restarts, usage does not
            else:
                segs[-1] = max(segs[-1], cur)
            prev = (cur, d.get("weekly_reset_at"))
    out.sort(key=lambda e: e[1])
    return out, holes


def _rolled(before, after, roll_s):
    """Did the weekly WINDOW advance across this drop? Unknown on either side answers False — an
    unmeasurable rollover is not an observed one, and admitting it restores the drop-only rule."""
    if not before or not after:
        return False
    try:
        b = datetime.fromisoformat(before)
        aft = datetime.fromisoformat(after)
    except (TypeError, ValueError):
        return False
    return (aft - b).total_seconds() > roll_s


def measure(sweeps, events, hours=12.0):
    """(on_target, total, exposure) over each event's final `hours`."""
    on = tot = exposure = 0
    for acct, rts, _pct, *_ in events:
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
            # Same hole, second site: a picked row with no readable weekly meter can be scored
            # (score_interactive has its own handling) but cannot be judged on headroom. It counts
            # in the denominator, as a sweep the desk did spend, and toward NEITHER term — an
            # unreadable meter is not evidence of on-target and not evidence of exposure.
            head = pick["weekly_pct"]
            head = 100 - head if isinstance(head, (int, float)) else None
            if head is None:
                continue
            if pick["acct"] == acct and head > 1:
                on += 1
            T = pick["weekly_reset_h"]
            if head < 2 and isinstance(T, (int, float)) and T > 5:
                exposure += 1
    return on, tot, exposure


def attribute(sweeps, events, hours=12.0):
    """Per account, why the desk lane did NOT name it inside each reset's endgame window.

    THE GAP THIS FILLS (item 51a7a9114c78). The measure above scores the WINNER, so a strand is
    visible as a number and never as a cause: the item recording next4's 15pp could not say
    whether the desk lane skipped that account because it scored lower (a TIER, which the W2
    horizon-ramp reaches) or because it was refused outright (an EXCLUSION, which the ramp cannot
    reach at all, since an excluded account is never scored). `score_interactive` already returns
    the reason as its second value and this file was discarding it as `_why`.

    Counted per SWEEP inside the window, so the unit is desk-time — the same unit as on-target."""
    per = collections.defaultdict(collections.Counter)
    for acct, rts, _pct, *_ in events:
        end = datetime.fromisoformat(rts)
        start = end - timedelta(hours=hours)
        for ts, accts in sweeps:
            t = datetime.fromisoformat(ts)
            if not (start <= t <= end) or acct not in accts:
                continue
            for d in accts.values():
                r = to_row(d, t)
                sc, why = ca.score_interactive(r, CFG)
                per[r["acct"]][("scored" if sc else (why or "excluded:?"))] += 1
    return per


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
    ap.add_argument(
        "--attribute",
        action="store_true",
        help="per-account census of WHY the desk lane skipped an account in each endgame window",
    )
    ap.add_argument("--util", default=UTIL, help="utilization series path")
    a = ap.parse_args()

    sweeps = load_sweeps(a.util)
    if not sweeps:
        sys.exit(f"desk-strand-replay: no sweeps in {a.util}")
    events, holes = resets(sweeps)
    print(f"{len(sweeps)} sweeps  {sweeps[0][0][:16]} -> {sweeps[-1][0][:16]}")
    if holes:
        print(
            f"⚠ {holes} sample(s) carry no readable weekly meter — skipped as ABSENT, with the "
            f"prior observation carried across the hole (never read as a drop to zero)"
        )
    seen = [d for _ts, accts in sweeps for d in accts.values()]
    legacy = sum(1 for d in seen if "k_src" not in d)
    if legacy:
        print(
            f"⚠ {legacy}/{len(seen)} rows predate k_src/k_work recording — replayed as WORK "
            f"(the strict cap), so any kmax exclusion below is an UPPER BOUND, not an attribution"
        )
    print(f"{len(events)} weekly resets observed:")
    for acct, ts, pct, used in events:
        # `pct` is the meter's last reading; `used` adds back any segment the meter forgot when it
        # zeroed mid-window. They differ only there, and there the meter UNDERSTATES what was
        # spent — so the strand is reported off `used`, and the row says why, rather than
        # publishing a loss the account did not take.
        note = "" if used == pct else f"   (meter read {pct}%; zeroed mid-window, so >= {used}%)"
        print(
            f"    {acct:7s} {ts[:16]}  reset at {used:3d}% used  -> {max(0, 100 - used):2d}pp "
            f"stranded{note}"
        )
    print()

    def run(label):
        on, tot, exp = measure(sweeps, events, a.hours)
        pct = on / tot * 100 if tot else 0.0
        print(
            f"{label:>22s} | on-target {on:4d}/{tot:<5d} = {pct:5.1f}% | wall-exposure {exp:4d}"
        )
        return pct

    if a.attribute:
        per = attribute(sweeps, events, a.hours)
        print("endgame windows, per account — sweeps by desk-lane verdict:")
        for acct in sorted(per):
            tot = sum(per[acct].values())
            parts = "  ".join(
                f"{k} {v} ({v / tot * 100:.0f}%)" for k, v in per[acct].most_common()
            )
            print(f"    {acct:7s} {tot:5d} sweeps | {parts}")
        print()
        return

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
