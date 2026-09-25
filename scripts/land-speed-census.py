#!/usr/bin/env python3
"""land-speed-census.py — where a ship-land's seconds go, and whether a change moved them.

    scripts/land-speed-census.py [--from ISO] [--to ISO] [--json]
    scripts/land-speed-census.py --compare ISO [--days D] [--json]

--compare ISO prints two windows side by side: BASELINE = [ISO - D days, ISO) and
POST = [ISO, now). D defaults to 7. This is the before/after instrument for
.claude-plans/LAND_SPEED.md; every number that plan quotes is a re-run of this.

WHY A SECOND READER OF land.log, when scripts/gate-red-census.sh already renders it:
that tool answers "how often does the gate refuse, and which arm" over trailing windows.
This one answers a question it cannot: how an END-TO-END land decomposes, which needs a
JOIN the census never makes — a landed row to the land-lock `release` row that preceded
it — and a fixed [from, to) window so a before/after comparison is not a trailing window
sliding across the change it is meant to judge. It follows the census's denominator rules
verbatim rather than restating them differently:
  * the population is rows carrying "tool":"ship-land" (never "rows without event");
  * a "stage":"round" row is an INTERNAL stale-gate re-round, never an attempt; exit 42
    lives only there. Counting those as attempts is how a 60% land rate reads as 41%.

THE DECOMPOSITION of a landed row (exit 0), all in wall seconds:
  total_s   ship-land's own end-to-end clock (first line of the outer process to the row)
  gate_s    cumulative seconds inside run_gate across every round
  post_s    landed row ts minus the ts of the land-lock `release` row (same repo+branch,
            exit 0) that immediately preceded it: the post-push, lock-free tail — backup
            reap + stranded-sweep, both of which run BEFORE the row is written.
            None when no release row joins (reported as coverage, never as 0).
  pre_s     total_s - gate_s - post_s: fetch, rebase, preflight, lock wait + hold.

Seams: LAND_LOG (the store). NOW is taken from LAND_SPEED_NOW (a UTC stamp) when set, so a
fixture can pin the clock.
"""

import argparse
import calendar
import collections
import json
import os
import sys
import time

TS_FMT = "%Y-%m-%dT%H:%M:%SZ"


def epoch(ts):
    try:
        return calendar.timegm(time.strptime(ts, TS_FMT))
    except Exception:
        return None


def pct(vals, p):
    vals = sorted(v for v in vals if v is not None)
    if not vals:
        return None
    return vals[min(len(vals) - 1, int(p * len(vals)))]


def read_store(path):
    tool, releases, bad = [], [], 0
    if not os.path.exists(path):
        return tool, releases, bad
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                bad += 1
                continue
            if not isinstance(d, dict):
                bad += 1
                continue
            t = epoch(d.get("ts", "")) if isinstance(d.get("ts"), str) else None
            if t is None:
                continue
            d["_t"] = t
            if d.get("tool") == "ship-land":
                tool.append(d)
            elif d.get("event") == "release":
                releases.append(d)
    tool.sort(key=lambda d: d["_t"])
    releases.sort(key=lambda d: d["_t"])
    return tool, releases, bad


def join_post(landed, releases):
    """For each landed row, seconds since the preceding exit-0 release of the same repo+branch."""
    by_key = collections.defaultdict(list)
    for r in releases:
        if r.get("exit") == 0:
            by_key[(r.get("repo"), r.get("branch"))].append(r["_t"])
    out = {}
    for d in landed:
        ts = [
            t for t in by_key.get((d.get("repo"), d.get("branch")), []) if t <= d["_t"]
        ]
        # A release more than total_s before the row cannot belong to this land.
        tot = d.get("total_s")
        if ts and (not isinstance(tot, int) or d["_t"] - ts[-1] <= tot):
            out[id(d)] = d["_t"] - ts[-1]
    return out


def measure(tool, releases, lo, hi):
    rows = [d for d in tool if lo <= d["_t"] < hi]
    lands = [d for d in rows if d.get("stage", "land") != "round"]
    rounds = [d for d in rows if d.get("stage") == "round"]
    landed = [d for d in lands if d.get("exit") == 0]
    post = join_post(landed, releases)
    n = len(lands)

    def num(d, k):
        v = d.get(k)
        return v if isinstance(v, int) and not isinstance(v, bool) else None

    dec = collections.OrderedDict()
    for name, fn in (
        ("total_s", lambda d: num(d, "total_s")),
        ("gate_s", lambda d: num(d, "gate_s")),
        ("gate_arms_s", lambda d: num(d, "gate_arms_s")),
        ("smoke_s", lambda d: num(d, "smoke_s")),
        ("post_s", lambda d: post.get(id(d))),
        (
            "pre_s",
            lambda d: (
                (num(d, "total_s") - num(d, "gate_s") - post[id(d)])
                if id(d) in post
                and num(d, "total_s") is not None
                and num(d, "gate_s") is not None
                else None
            ),
        ),
    ):
        vals = [fn(d) for d in landed]
        dec[name] = {
            "p50": pct(vals, 0.5),
            "p90": pct(vals, 0.9),
            "n": sum(1 for v in vals if v is not None),
        }

    # Attempts per landed branch: terminal rows of one repo+branch up to and including exit 0.
    streak = collections.Counter()
    attempts = []
    for d in lands:
        k = (d.get("repo"), d.get("branch"))
        streak[k] += 1
        if d.get("exit") == 0:
            attempts.append(streak.pop(k))
    first_time = sum(1 for d in landed if num(d, "gate_rounds") == 1)

    reds = collections.Counter()
    for d in lands:
        if d.get("exit") == 6:
            for arm in (d.get("red") or "unattributed").split(","):
                # smoke:<suite> names a suite, not an arm: fold to the arm class so the
                # table ranks arms (the suite names stay in land.log for whoever needs them).
                reds[(arm.strip() or "unattributed").split(":", 1)[0]] += 1

    return {
        "from": time.strftime(TS_FMT, time.gmtime(lo)),
        "to": time.strftime(TS_FMT, time.gmtime(hi)),
        "lands": n,
        "rounds": len(rounds),
        "landed": len(landed),
        "landed_rate": (len(landed) / float(n)) if n else None,
        "exit_hist": dict(
            sorted(
                collections.Counter(d.get("exit") for d in lands).items(),
                key=lambda kv: -kv[1],
            )
        ),
        "gate_rounds_landed": dict(
            sorted(
                collections.Counter(num(d, "gate_rounds") for d in landed).items(),
                key=lambda kv: str(kv[0]),
            )
        ),
        "first_round_landed": first_time,
        "attempts_per_landed_branch": {
            "p50": pct(attempts, 0.5),
            "p90": pct(attempts, 0.9),
            "max": max(attempts) if attempts else None,
            "n": len(attempts),
        },
        "landed_decomposition": dec,
        "red_arms": dict(reds.most_common()),
    }


def fmt(v, suffix=""):
    return "-" if v is None else ("%s%s" % (v, suffix))


def render(ws, out):
    labels = [w["label"] for w in ws]
    col = 22
    out.write("LAND-SPEED CENSUS  (store: %s)\n" % ws[0]["store"])
    out.write("  %-36s" % "" + "".join("%-*s" % (col, l) for l in labels) + "\n")
    out.write(
        "  %-36s" % "window"
        + "".join("%-*s" % (col, w["from"][5:16] + "→" + w["to"][5:16]) for w in ws)
        + "\n"
    )

    def row(name, fn):
        out.write("  %-36s" % name + "".join("%-*s" % (col, fn(w)) for w in ws) + "\n")

    row("terminal lands (n)", lambda w: fmt(w["lands"]))
    row("stale-gate rounds (not attempts)", lambda w: fmt(w["rounds"]))
    row(
        "landed",
        lambda w: (
            "%d (%s)"
            % (
                w["landed"],
                "-"
                if w["landed_rate"] is None
                else "%.1f%%" % (100 * w["landed_rate"]),
            )
        ),
    )
    row("landed on gate round 1", lambda w: fmt(w["first_round_landed"]))
    row(
        "attempts/landed branch p50/p90",
        lambda w: (
            "%s/%s (n=%s)"
            % (
                fmt(w["attempts_per_landed_branch"]["p50"]),
                fmt(w["attempts_per_landed_branch"]["p90"]),
                w["attempts_per_landed_branch"]["n"],
            )
        ),
    )
    out.write("  LANDED decomposition p50/p90 (s)\n")
    for k in ("total_s", "gate_s", "gate_arms_s", "smoke_s", "post_s", "pre_s"):
        row(
            "    " + k,
            lambda w, k=k: (
                "%s/%s (n=%s)"
                % (
                    fmt(w["landed_decomposition"][k]["p50"]),
                    fmt(w["landed_decomposition"][k]["p90"]),
                    w["landed_decomposition"][k]["n"],
                )
            ),
        )
    out.write("  exit histogram (terminal lands)\n")
    codes = sorted({c for w in ws for c in w["exit_hist"]}, key=lambda c: str(c))
    for c in codes:
        row("    exit %s" % c, lambda w, c=c: fmt(w["exit_hist"].get(c, 0)))
    out.write("  gate-red arms (exit 6; a land may name several)\n")
    arms = sorted(
        {a for w in ws for a in w["red_arms"]},
        key=lambda a: -sum(w["red_arms"].get(a, 0) for w in ws),
    )
    for a in arms:
        row("    " + a, lambda w, a=a: fmt(w["red_arms"].get(a, 0)))
    small = [w["label"] for w in ws if w["lands"] < 30]
    if small:
        out.write(
            "  ⚠ n < 30 in: %s — too small to judge a rate or a p90; read as indicative only.\n"
            % ", ".join(small)
        )


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--from", dest="lo")
    ap.add_argument("--to", dest="hi")
    ap.add_argument("--compare")
    ap.add_argument("--days", type=float, default=7.0)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    store = os.environ.get("LAND_LOG") or os.path.expanduser("~/.claude/land.log")
    now_env = os.environ.get("LAND_SPEED_NOW")
    now = epoch(now_env) if now_env else int(time.time())
    if now is None:
        sys.stderr.write("land-speed-census: LAND_SPEED_NOW is not a UTC stamp\n")
        return 2
    tool, releases, bad = read_store(store)
    if not tool:
        sys.stderr.write("land-speed-census: no ship-land rows in %s\n" % store)
        return 3

    windows = []
    if a.compare:
        cut = epoch(a.compare)
        if cut is None:
            sys.stderr.write(
                "land-speed-census: --compare wants a UTC stamp (%s)\n" % TS_FMT
            )
            return 2
        windows.append(("baseline", cut - int(a.days * 86400), cut))
        windows.append(("post", cut, now + 1))
    else:
        lo = epoch(a.lo) if a.lo else now - int(a.days * 86400)
        hi = epoch(a.hi) if a.hi else now + 1
        if lo is None or hi is None:
            sys.stderr.write(
                "land-speed-census: --from/--to want UTC stamps (%s)\n" % TS_FMT
            )
            return 2
        windows.append(("window", lo, hi))

    ws = []
    for label, lo, hi in windows:
        w = measure(tool, releases, lo, hi)
        w["label"] = label
        w["store"] = store
        w["unparseable_lines"] = bad
        ws.append(w)

    if a.json:
        json.dump(ws, sys.stdout, indent=1, default=str)
        sys.stdout.write("\n")
    else:
        render(ws, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
