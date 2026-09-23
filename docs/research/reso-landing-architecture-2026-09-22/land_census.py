#!/usr/bin/env python3
"""land_census.py — re-derive every land-path number in reso-landing-architecture-2026-09-22.md.

Reads reso's own land telemetry (~/.reso/land.log, v3 rows written by scripts/ship-land.sh's EXIT
trap: one row per landing ATTEMPT, per_round[] carrying reconcile_s/tsc_s/sem_wait_s/suite_s/push_s).

  python3 land_census.py                         # 7 days ending at the newest row
  python3 land_census.py --since 2026-09-16T04:59:00Z --until 2026-09-23T04:59:00Z

Sections: baseline · verify window vs inter-land gap · push-rejection classes · per-unit latency ·
stage-vs-load fits · in-flight concurrency · bottleneck prices · verification-failure reproducibility.
Read-only. Never writes anything.
"""

import argparse, collections as C, datetime as dt, json, os

ap = argparse.ArgumentParser()
ap.add_argument("--log", default=os.path.expanduser("~/.reso/land.log"))
ap.add_argument("--since")
ap.add_argument("--until")
ap.add_argument("--days", type=float, default=7)
a = ap.parse_args()
T = lambda s: dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
rows = [json.loads(l) for l in open(a.log) if l.startswith('{"v":3')]
end = T(a.until) if a.until else max(T(r["ts_end"]) for r in rows)
start = T(a.since) if a.since else end - dt.timedelta(days=a.days)
w = sorted(
    [r for r in rows if start <= T(r["ts_start"]) <= end], key=lambda r: r["ts_start"]
)
dur = lambda r: (T(r["ts_end"]) - T(r["ts_start"])).total_seconds()


def pct(xs, p):
    xs = sorted(xs)
    if not xs:
        return float("nan")
    k = (len(xs) - 1) * p
    f = int(k)
    c = min(f + 1, len(xs) - 1)
    return xs[f] + (xs[c] - xs[f]) * (k - f)


def dist(xs):
    return "n=%d p50=%.0f p90=%.0f p95=%.0f max=%.0f" % (
        len(xs),
        pct(xs, 0.5),
        pct(xs, 0.9),
        pct(xs, 0.95),
        max(xs) if xs else 0,
    )


def code_round(pr):
    return pr.get("suite_mode") in ("union", "full")


print("## window %s → %s (UTC): %d attempts" % (start, end, len(w)))
print("exit_class", C.Counter(r["exit_class"] for r in w).most_common())
print("attempt duration (s)", dist([dur(r) for r in w]))

# verify window per code round vs the gap between trunk advances
vw = [
    sum(
        (pr.get(k) or 0)
        for k in ("reconcile_s", "tsc_s", "sem_wait_s", "suite_s", "push_s")
    )
    for r in w
    for pr in r["per_round"]
    if code_round(pr) and pr.get("push_s") is not None
]
ends = sorted(T(r["ts_end"]) for r in w if r["exit"] == 0)
gaps = [(b - x).total_seconds() for x, b in zip(ends, ends[1:])]
print("\n## verify window (code rounds, s)", dist(vw))
print(
    "inter-land gap (s) p10=%.0f p25=%.0f p50=%.0f"
    % (pct(gaps, 0.1), pct(gaps, 0.25), pct(gaps, 0.5))
)
# Stage medians over CODE rounds only: a non-code round records suite_s = 0 (ship-land.sh:671),
# and mixing those zeros in drags the suite median down (a first draft of this document did that).
for k in ("reconcile_s", "tsc_s", "sem_wait_s", "suite_s"):
    print(
        "  %-12s %s"
        % (
            k,
            dist(
                [
                    pr[k]
                    for r in w
                    for pr in r["per_round"]
                    if isinstance(pr.get(k), (int, float)) and code_round(pr)
                ]
            ),
        )
    )
for mode in ("union", "full"):
    print(
        "  suite_s %-5s %s"
        % (
            mode,
            dist(
                [
                    pr["suite_s"]
                    for r in w
                    for pr in r["per_round"]
                    if pr.get("suite_mode") == mode and pr.get("suite_s") is not None
                ]
            ),
        )
    )
print(
    "  push_s code rounds    ",
    dist(
        [
            pr["push_s"]
            for r in w
            for pr in r["per_round"]
            if code_round(pr) and pr.get("push_s") is not None
        ]
    ),
)
print(
    "  push_s no-suite rounds",
    dist(
        [
            pr["push_s"]
            for r in w
            for pr in r["per_round"]
            if pr.get("suite_mode") == "none" and pr.get("push_s") is not None
        ]
    ),
)

# every rejected push, classified by its own captured tail
cls = C.Counter()
for r in w:
    for pr in r["per_round"]:
        if pr.get("push_rc") in (None, 0):
            continue
        tl = pr.get("push_tail") or ""
        k = (
            "github-ref-lock-race"
            if "cannot lock ref" in tl
            # rc 99 is ship-land's OWN verdict, made on the FULL push output; the log keeps
            # only 3 tail lines, which usually cut off the 'fetch first' line itself
            else "client-non-fast-forward-race"
            if pr.get("rc") == 99
            or any(
                s in tl
                for s in ("non-fast-forward", "fetch first", "Updates were rejected")
            )
            else "pre-push-unit-tests-failed"
            if "unit tests failed" in tl
            else "push-timeout"
            if pr["push_rc"] in (124, 137)
            else "other-hook-refusal"
        )
        cls[(k, "round rc %s" % pr.get("rc"))] += 1
print("\n## rejected pushes")
[print("  ", k, v) for k, v in cls.most_common()]

# units: consecutive attempts of one branch up to and including the landing one
by = C.defaultdict(list)
for r in w:
    by[r["branch"]].append(r)
units = []
for b, rs in by.items():
    cur = []
    for r in rs:
        cur.append(r)
        if r["exit"] == 0:
            units.append(
                (
                    (T(r["ts_end"]) - T(cur[0]["ts_start"])).total_seconds(),
                    len(cur),
                    b,
                    (T(r["ts_start"]) - T(cur[0]["ts_start"])).total_seconds(),
                )
            )
            cur = []
print("\n## per-unit latency, first attempt → landed (s)", dist([u[0] for u in units]))
print(
    "units needing >1 attempt: %d; wall-clock before their landing attempt: %.1f h"
    % (sum(1 for u in units if u[1] > 1), sum(u[3] for u in units) / 3600)
)


# stage time vs entry load (OLS)
def ols(xs, ys):
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum(
        (x - mx) ** 2 for x in xs
    )
    r2 = 1 - sum((y - (my + b * (x - mx))) ** 2 for x, y in zip(xs, ys)) / sum(
        (y - my) ** 2 for y in ys
    )
    return my - b * mx, b, r2, n


print("\n## stage(L) = a + b·load1_entry")
for k, sel in (
    ("suite_s", lambda pr: pr.get("suite_mode") == "union"),
    ("tsc_s", lambda pr: not pr.get("tsc_skipped") and (pr.get("tsc_s") or 0) > 0),
    ("push_s", code_round),
):
    xs, ys = [], []
    for r in w:
        for pr in r["per_round"]:
            if pr.get(k) is not None and sel(pr):
                xs.append(r["load1_entry"])
                ys.append(pr[k])
    if len(xs) > 2:
        print("  %-8s a=%.0fs b=%.2fs/load R²=%.2f n=%d" % ((k,) + ols(xs, ys)))

# in-flight attempts sampled every 30 s
ev = sorted([(T(r["ts_start"]), 1) for r in w] + [(T(r["ts_end"]), -1) for r in w])
cur = i = 0
x = start
samp = []
while x < end:
    while i < len(ev) and ev[i][0] <= x:
        cur += ev[i][1]
        i += 1
    samp.append(cur)
    x += dt.timedelta(seconds=30)
print(
    "\n## in-flight attempts: max %d, distribution %s"
    % (max(samp), sorted(C.Counter(samp).items()))
)
print("busiest hours", C.Counter(r["ts_start"][:13] for r in w).most_common(5))

# bottleneck prices
lost = [
    pr
    for r in w
    for pr in r["per_round"]
    if pr.get("rc") == 99 or "cannot lock ref" in (pr.get("push_tail") or "")
]
print("\n## prices over the window")
print(
    "  lost-race rounds: n=%d, %.1f wall-h"
    % (
        len(lost),
        sum(
            sum(
                (pr.get(k) or 0)
                for k in ("reconcile_s", "tsc_s", "sem_wait_s", "suite_s", "push_s")
            )
            for pr in lost
        )
        / 3600,
    )
)
dup = [
    pr["push_s"] - 4
    for r in w
    for pr in r["per_round"]
    if code_round(pr) and pr.get("push_s") is not None
]
print(
    "  duplicate pre-push suite: n=%d rounds, %.2f wall-h (mean %.0fs; 4 s = a no-suite push)"
    % (len(dup), sum(dup) / 3600, sum(dup) / max(len(dup), 1))
)
print(
    "  cc-sem admission wait: %.2f wall-h"
    % (sum(pr.get("sem_wait_s") or 0 for r in w for pr in r["per_round"]) / 3600)
)

# did a verification failure reproduce on the same tree?
print("\n## verification failures → next attempt on the same branch")
for j, r in enumerate(w):
    hook = any(
        "unit tests failed" in (pr.get("push_tail") or "") for pr in r["per_round"]
    )
    if not (hook or r["exit_class"] == "statics-red"):
        continue
    nxt = next((x for x in w[j + 1 :] if x["branch"] == r["branch"]), None)
    print(
        "  %s %-15s %-26s same_tree_next=%s next=%s specs=%s"
        % (
            r["ts_start"],
            "pre-push-tests" if hook else "land-suite",
            r["branch"][:26],
            None if not nxt else nxt["tree"] == r["tree"],
            None if not nxt else nxt["exit_class"],
            r["fail_specs"][:2],
        )
    )
