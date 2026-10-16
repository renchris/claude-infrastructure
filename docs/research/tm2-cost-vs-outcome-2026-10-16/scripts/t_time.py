#!/usr/bin/env python3
"""t_time.py — the TrueMemory 2.0 program's clock: span, stages, kit agent-days, working vs waiting.

Inputs (all read-only): git on this repo and on the tm2-plan worktree, program/budget.json,
~/.claude/autonomy/decisions/*.json (operator packets naming truememory), `cc-custody list`, and
data/k_attrib.json (hourly program activity; run k_census.py then k_attrib.py first).

Working hour = a UTC hour holding >= 1 billed response from a session attributed to the program,
the kit or the kit's method design (k_attrib.py buckets program, kit, kit-method).
Waiting = every other hour of the span. Each idle hour is given ONE cause, first match wins:
  operator  a class-C packet naming truememory was open (created .. resolved), or one of the
            hand-dated operator checkpoints in CHECKPOINTS below was pending
  vendor    a vendor usage wall the program recorded (WALLS below)
  night     local 23:00-08:00 (UTC-05:00) with no recorded cause
  other     the rest (unexplained daytime idle)

Usage (from the repo root):
  python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/t_time.py
Writes data/t_time.json; prints the summary.
"""

import collections, glob, json, os, subprocess
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
TM2 = os.path.expanduser("~/Development/.worktrees/tm2-plan")
REC = os.path.join(TM2, "docs/research/truememory-2.0-2026-09-28/program")
NOW = "2026-10-16T14:00:00Z"  # fixed so every rerun reproduces the report


def ep(s):
    return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()


def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%MZ")


H = 3600.0
STAGES = [
    ("P0 pre-program", "2026-09-27T00:00:00Z", "2026-10-02T03:11:20Z"),
    ("S1", "2026-10-02T03:11:20Z", "2026-10-02T04:36:44Z"),
    ("S2", "2026-10-02T04:36:44Z", "2026-10-02T05:57:46Z"),
    ("gap S2-S3", "2026-10-02T05:57:46Z", "2026-10-02T06:26:09Z"),
    ("S3", "2026-10-02T06:26:09Z", "2026-10-03T03:51:14Z"),
    ("gap S3-S4", "2026-10-03T03:51:14Z", "2026-10-04T02:41:59Z"),
    ("S4", "2026-10-04T02:41:59Z", "2026-10-08T17:19:54Z"),
    ("S5", "2026-10-08T17:19:54Z", "2026-10-08T21:01:34Z"),
    ("gap S5-S6", "2026-10-08T21:01:34Z", "2026-10-09T21:15:19Z"),
    ("S6", "2026-10-09T21:15:19Z", "2026-10-10T15:52:16Z"),
    ("S7", "2026-10-10T15:52:16Z", "2026-10-13T04:15:43Z"),
    ("S8", "2026-10-13T04:15:43Z", NOW),
]
STD_BUDGET = {
    1: 2.0,
    2: 1.5,
    3: 1.5,
    4: 3.0,
    5: 2.5,
    6: 1.0,
}  # scripts/research-kit/lib/kit.py _STD_STAGE_DAYS
OVERRUN = 1.5  # kit.CAPS["overrun_factor"]
# Operator checkpoints the records name but no packet carries (start = asked, end = answered).
CHECKPOINTS = [
    (
        "S5 reaction checkpoint + frame v2 re-sign",
        "2026-10-08T21:10:29Z",
        "2026-10-09T21:09:40Z",
        "286adeec3 -> 99c41d2cb",
    ),
    (
        "frame re-sign after the plan/topic-owner keys",
        "2026-10-10T05:23:02Z",
        "2026-10-10T15:51:17Z",
        "566c07705 -> c9ed7263a",
    ),
    (
        "profile switch to lite + round-1 record writes by the operator",
        "2026-10-12T06:51:54Z",
        "2026-10-12T17:07:53Z",
        "6dfebdd4c -> 390b73707/764ced52d",
    ),
]
WALLS = [
    (
        "OpenAI usage wall (round 1)",
        "2026-10-10T16:58:16Z",
        "2026-10-10T21:00:00Z",
        "22c849325",
    ),
    (
        "OpenAI usage wall again",
        "2026-10-11T06:19:36Z",
        "2026-10-11T09:42:00Z",
        "83d161606",
    ),
]
WEEKS = [
    ("Wk0", ep("2026-09-21T05:00:00Z")),
    ("Wk1", ep("2026-09-28T05:00:00Z")),
    ("Wk2", ep("2026-10-05T05:00:00Z")),
    ("Wk3", ep("2026-10-12T05:00:00Z")),
]


def week_of(t):
    w = "pre"
    for n, a in WEEKS:
        if t >= a:
            w = n
    return w


def stage_of(t):
    for n, a, b in STAGES:
        if ep(a) <= t < ep(b):
            return n
    return "after"


def git_ts(repo, rev):
    return subprocess.run(
        ["git", "-C", repo, "log", "-1", "--format=%cI", rev],
        capture_output=True,
        text=True,
    ).stdout.strip()


def main():
    out = {"now": NOW}
    now = ep(NOW)
    # ── span ────────────────────────────────────────────────────────────────────────────────
    marks = {
        "TrueMemory study (b486587e9)": git_ts(REPO, "b486587e9"),
        "first TM2 plan commit (b2401a113)": git_ts(TM2, "b2401a113"),
        "program intake (intake.jsonl init)": "2026-10-02T03:11:20Z",
    }
    out["span_days"] = {k: round((now - ep(v)) / 86400, 2) for k, v in marks.items()}
    out["marks"] = marks
    # ── stages: wall-clock and the kit's own agent-day accounting ───────────────────────────
    budget = json.load(open(os.path.join(REC, "budget.json")))
    st = []
    for n, a, b in STAGES:
        d = round((ep(b) - ep(a)) / 86400, 2)
        row = {"stage": n, "start": a, "end": b, "wall_days": d}
        if n.startswith("S") and n[1:].isdigit():
            k = int(n[1:])
            bj = budget["stages"].get(str(k))
            row["kit_agent_days"] = (
                round((ep(bj["ended"]) - ep(bj["started"])) / 86400, 2) if bj else None
            )
            row["in_budget_json"] = bool(bj)
            row["budget_days"] = STD_BUDGET.get(k)
            row["cap_days"] = STD_BUDGET[k] * OVERRUN if k in STD_BUDGET else None
        st.append(row)
    out["stages"] = st
    s16 = [r["kit_agent_days"] for r in st if r.get("kit_agent_days") is not None]
    s6 = next(r for r in st if r["stage"] == "S6")["wall_days"]
    out["stages_1_6_agent_days"] = round(sum(s16) + s6, 2)
    out["stages_1_6_budget"] = sum(STD_BUDGET.values())
    # ── activity ────────────────────────────────────────────────────────────────────────────
    ka = json.load(open(os.path.join(DATA, "k_attrib.json")))
    act = collections.Counter()
    for b in ("program", "kit", "kit-method"):
        for h, n in ka["hours"].get(b, {}).items():
            act[int(h)] = max(act[int(h)], 0) + n
    start = ep("2026-09-27T00:00:00Z")
    first = min(h for h in act if h >= start)
    hours = list(range(int(first // H) * int(H), int(now), int(H)))
    # operator intervals: class-C packets naming truememory, plus the checkpoints
    op = []
    pk = []
    for p in glob.glob(os.path.expanduser("~/.claude/autonomy/decisions/*.json")):
        try:
            txt = open(p).read()
        except OSError:
            continue
        if "truememory" not in txt.lower():
            continue
        d = json.loads(txt)
        res = d.get("resolved")
        rat = (
            res
            if isinstance(res, str)
            else ((res or {}).get("at") if isinstance(res, dict) else None)
        )
        pk.append(
            {
                "id": d["id"],
                "class": d.get("class"),
                "status": d.get("status"),
                "created": d.get("created"),
                "resolved": rat,
                "scope": "program (tm2-plan)"
                if "tm2-plan" in (d.get("subject_project") or "")
                else "kit or method",
            }
        )
        if d.get("class") == "C" and d.get("created"):
            op.append((ep(d["created"]), ep(rat) if rat else now))
    for name, a, b, ev in CHECKPOINTS:
        op.append((ep(a), ep(b)))
    walls = [(ep(a), ep(b)) for _, a, b, _ in WALLS]
    cause = collections.Counter()
    by_stage = collections.defaultdict(collections.Counter)
    by_week = collections.defaultdict(collections.Counter)
    for h in hours:
        mid = h + H / 2
        if act.get(h):
            c = "working"
        elif any(a <= mid < b for a, b in op):
            c = "waiting: operator"
        elif any(a <= mid < b for a, b in walls):
            c = "waiting: vendor wall"
        else:
            lh = (datetime.fromtimestamp(mid, timezone.utc).hour - 5) % 24
            c = (
                "idle: night (23:00-08:00 local)"
                if (lh >= 23 or lh < 8)
                else "idle: daytime, unexplained"
            )
        cause[c] += 1
        by_stage[stage_of(mid)][c] += 1
        by_week[week_of(mid)][c] += 1
    out["hours_total"] = len(hours)
    out["first_active_hour"] = iso(first)
    out["hour_causes"] = dict(cause)
    out["hour_causes_by_stage"] = {k: dict(v) for k, v in by_stage.items()}
    out["hour_causes_by_week"] = {k: dict(v) for k, v in sorted(by_week.items())}
    # how many working hours also had an operator decision open (work went on beside the wait)
    out["working_hours_with_operator_open"] = sum(
        1 for h in hours if act.get(h) and any(a <= h + H / 2 < b for a, b in op)
    )
    # concurrency: sessions per working hour
    conc = [act[h] for h in hours if act.get(h)]
    conc.sort()
    out["sessions_per_working_hour"] = {
        "mean": round(sum(conc) / len(conc), 2),
        "median": conc[len(conc) // 2],
        "p90": conc[int(len(conc) * 0.9)],
        "max": conc[-1],
        "session_hours": sum(conc),
    }
    # idle gaps >= 2 h
    gaps, run = [], None
    for h in hours:
        if not act.get(h):
            run = run or h
        else:
            if run is not None and h - run >= 2 * H:
                gaps.append((run, h))
            run = None
    if run is not None and now - run >= 2 * H:
        gaps.append((run, now))
    out["idle_gaps_ge_2h"] = {
        "count": len(gaps),
        "hours": round(sum(b - a for a, b in gaps) / H, 1),
        "longest": [
            {"from": iso(a), "to": iso(b), "hours": round((b - a) / H, 1)}
            for a, b in sorted(gaps, key=lambda g: g[0] - g[1])[:12]
        ],
    }
    # operator packets
    pk.sort(key=lambda p: p["created"] or "")
    out["operator_packets"] = {
        "count": len(pk),
        "by_class": dict(collections.Counter(p["class"] for p in pk)),
        "status": dict(collections.Counter(p["status"] for p in pk)),
        "class_C_open_hours": [
            round(
                ((ep(p["resolved"]) if p["resolved"] else now) - ep(p["created"])) / H,
                1,
            )
            for p in pk
            if p["class"] == "C"
        ],
        "by_scope_class": dict(
            collections.Counter(f"{p['scope']}/{p['class']}" for p in pk)
        ),
        "class_C_median_open_hours": sorted(
            ((ep(p["resolved"]) if p["resolved"] else now) - ep(p["created"])) / H
            for p in pk
            if p["class"] == "C"
        )[sum(1 for p in pk if p["class"] == "C") // 2],
        "unresolved": [p["id"] for p in pk if not p["resolved"]],
        "class_C_created_by_day": dict(
            collections.Counter(p["created"][:10] for p in pk if p["class"] == "C")
        ),
    }
    # fires (dispatched sessions) from the custody ledger
    cl = subprocess.run(["cc-custody", "list"], capture_output=True, text=True).stdout
    opens, ends = {}, {}
    for ln in cl.splitlines():
        f = ln.split("\t")
        if len(f) < 5:
            continue
        ts, ev, slug = f[0], f[1], f[2]
        if not (
            slug.startswith("fire-tm2")
            or slug.startswith(
                "fire-kit-"
            )  # not fire-kitty-*: terminal work, not the kit
            or slug.startswith("fire-method")
        ):
            continue
        key = (slug, f[4])
        if ev == "open":
            opens[key] = ep(ts)
        elif ev in ("return", "abandon"):
            ends[key] = (ep(ts), ev)
    fires = []
    for k, t0 in opens.items():
        t1, ev = ends.get(k, (max(now, t0), "open"))
        fires.append(
            {
                "slug": k[0],
                "opened": iso(t0),
                "hours": round((t1 - t0) / H, 2),
                "end": ev,
                "week": week_of(t0),
            }
        )
    out["fires"] = {
        "count": len(fires),
        "by_end": dict(collections.Counter(f["end"] for f in fires)),
        "by_week": dict(collections.Counter(f["week"] for f in fires)),
        "kit_fires": sum(1 for f in fires if f["slug"].startswith("fire-kit")),
        "hours_total": round(sum(f["hours"] for f in fires), 1),
        "abandoned": [f["slug"] for f in fires if f["end"] == "abandon"],
        "list": sorted(fires, key=lambda f: f["opened"]),
    }
    with open(os.path.join(DATA, "t_time.json"), "w") as fh:
        json.dump(out, fh, indent=1)
    show = {k: out[k] for k in out if k not in ("fires",)}
    show["fires"] = {k: v for k, v in out["fires"].items() if k != "list"}
    print(json.dumps(show, indent=1))


if __name__ == "__main__":
    main()
