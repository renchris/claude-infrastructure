#!/usr/bin/env python3
"""k_attrib.py — attribute the k_census.py sessions to the TrueMemory 2.0 program, and price them.

Reads data/k_raw.json (run k_census.py first). Every session gets ONE bucket and the rule that
put it there (how):
  O  explicit override, with the evidence in OVERRIDES below
  A  the session's first recorded cwd (a program, kit, reviewer-bundle or adoption worktree)
  B  the session's FIRST user message (the brief), hook-injected lines stripped first, since a
     hook writes "RESEARCH PROGRAM truememory-2-0 ..." into prompts of unrelated sessions
  S  same session id attributed on another account (cc-lr switch keeps the id across accounts)
Buckets: program (lead, records, plan, contact, reviewers), kit (kit implementation),
kit-method (the research-method design the kit implements), mixed (an adoption lead that also
wrote the first TM2 plan commits: an upper band only), measurement (this report), adoption
(TrueMemory adoption into OUR memory: NOT TM2), suspect (unattributed, but >= 5 transcript lines
name the program worktree: reported, never counted), other.

Quota, two independent methods, both reported:
  M1 fitted price: data/k_ccqp_fit21d.json from `bin/cc-quota-price --json --since 21d`
     (pp per token class); pp = sum(coef x tokens).
  M2 share of the measured meter: per (account, 6 h bucket), the weekly_pct movement in
     ~/.claude/logs/account-utilization.jsonl times the program's share of that bucket's
     priced tokens (output + cache_creation + input, cache_read excluded, as the tool does).

Usage (from the repo root):
  python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/k_attrib.py
Writes data/k_attrib.json and data/k_sessions.csv; prints the summary tables.
"""

import collections, csv, json, os, re, sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")
UTIL = os.path.expanduser("~/.claude/logs/account-utilization.jsonl")


def ep(s):
    return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()


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
    ("S8", "2026-10-13T04:15:43Z", "2099-01-01T00:00:00Z"),
]
STAGES = [(n, ep(a), ep(b)) for n, a, b in STAGES]
WEEKS = [
    ("Wk0", ep("2026-09-21T05:00:00Z")),
    ("Wk1", ep("2026-09-28T05:00:00Z")),
    ("Wk2", ep("2026-10-05T05:00:00Z")),
    ("Wk3", ep("2026-10-12T05:00:00Z")),
]


def stage_of(t):
    for n, a, b in STAGES:
        if a <= t < b:
            return n
    return "pre"


def week_of(t):
    w = "pre"
    for n, a in WEEKS:
        if t >= a:
            w = n
    return w


WT = r"^/Users/chrisren/Development/\.worktrees/"
CWD_RULES = [
    ("measurement", re.compile(WT + r"tm2-cost-vs-outcome(/|$)")),
    (
        "program",
        re.compile(
            r"^/Users/chrisren/\.claude[^/]*/autonomy/research/truememory-2-0(/|$)"
        ),
    ),
    (
        "kit",
        re.compile(
            WT + r"(kit-[^/]*|fix-research-kit[^/]*|feat-research-kit[^/]*|rp-[^/]*|"
            r"fix/research-[^/]*|[^/]*research-router[^/]*)(/|$)"
        ),
    ),
    ("program", re.compile(WT + r"(tm2-[^/]*|tm-upstream[^/]*)(/|$)")),
    ("adoption", re.compile(WT + r"tma-[^/]*(/|$)")),
]
HOOK_LINE = re.compile(
    r"[^\n]*RESEARCH PROGRAM truememory-2-0[^\n]*|[^\n]*research block \(REPORT[^\n]*",
    re.I,
)
BRIEF_RULES = [
    (
        "kit",
        re.compile(
            r"^KIT FIX|for the research kit|research kit in claude-infrastructure|"
            r"RESEARCH_PROGRAM_BUILD|Row 15: seal fresh held-out set",
            re.I | re.M,
        ),
    ),
    ("kit-method", re.compile(r"research method v1\.2|upfront research method", re.I)),
    (
        "program",
        re.compile(
            r"research[- ]program LEAD|TrueMemory (2\.0 )?(program )?lead|REPLAN session|"
            r"lead of a dedicated RESEARCH-AND-PLAN|truememory-2-0|TrueMemory 2\.0|tm2-plan",
            re.I,
        ),
    ),
]
LEAD_RX = re.compile(
    r"research[- ]program LEAD|TrueMemory (2\.0 )?(program )?lead|REPLAN session|"
    r"lead of a dedicated RESEARCH-AND-PLAN",
    re.I,
)
# Sessions whose brief does not settle the bucket; each was read by hand (grep counts on the
# session's transcript, quoted in the reason).
OVERRIDES = {
    "2ca0eb64": (
        "other",
        "agent-peer-wake build; its brief names a TM2 lead pane as an example, 2 program lines",
    ),
    "1b2cdb4d": (
        "kit-method",
        "METHOD UPGRADE 'exhaust, then proceed' (fire-method-exhaust-then-proceed, 10-16)",
    ),
    "44881f21": (
        "mixed",
        "AgentMemory (Cognition/Devin) study judged for agentsync AND TM 2.0; 205 lines name tm2-plan",
    ),
    "7c395da7-fbbe-4123-8bd5-2456787d12c3": (
        "mixed",
        "TrueMemory ADOPTION lead (brief) that also wrote the first TM2 plan "
        "commits: 174 adoption vs 34 TRUEMEMORY_2_0 references on next4",
    ),
    "bb231dfd": (
        "kit-method",
        "the research-method design (docs/research/upfront-research-exhaustion-2026-09-30)",
    ),
    "d8964eb2": (
        "kit-method",
        "'Locate our exhaustive upfront research methodology' (method audit, 10-04)",
    ),
}


def override(sid):
    for k, v in OVERRIDES.items():
        if sid.startswith(k):
            return v
    return None


def classify(s):
    o = override(s["sid"])
    if o:
        return o[0], "O"
    for b, rx in CWD_RULES:
        if s["cwd"] and rx.match(s["cwd"]):
            return b, "A"
    brief = HOOK_LINE.sub("", s["brief"])
    for b, rx in BRIEF_RULES:
        if rx.search(brief):
            # a brief that merely names the program (an example path, a sibling's pane) is not
            # program work: outside a lead brief, demand activity in the program worktree too
            if b == "program" and not LEAD_RX.search(brief) and s["suspect_lines"] < 5:
                continue
            s["matched"] = rx.search(brief).group(
                0
            )  # the evidence, without publishing the brief
            return b, "B"
    return "other", "-"


def sub_of(s):
    """What the session did, inside its bucket (cwd first, then how it was attributed)."""
    c, b = s["cwd"], s["bucket"]
    if b != "program":
        return b
    if "/autonomy/research/truememory-2-0" in c:
        return "certification reviewers (Anthropic lane)"
    if "/tm2-plan-replan" in c:
        return "plan critique rounds (replan worktree)"
    if "/tm2-slice" in c or "/tm-upstream" in c:
        return "upstream contact (slice, clones, upstream plan)"
    if "/.worktrees/tm2-plan" in c:
        return "records and waves (tm2-plan worktree)"
    if "/.worktrees/tm2-" in c:
        return "waves in other tm2 worktrees"
    return "lead sessions (by brief)"


def util_moves():
    """(acct, 6h bucket) -> weekly_pct points consumed, from consecutive samples in one reset."""
    rows = collections.defaultdict(list)
    for ln in open(UTIL):
        try:
            d = json.loads(ln)
        except ValueError:
            continue
        if (
            d.get("stale")
            or d.get("auth") != "ok"
            or d.get("weekly_pct") is None
            or not d.get("weekly_reset_at")
        ):
            continue
        rows[d["acct"]].append(
            (ep(d["ts"]), int(d["weekly_pct"]), ep(d["weekly_reset_at"]))
        )
    mv = collections.Counter()
    since = ep("2026-09-27T00:00:00Z")
    for acct, rs in rows.items():
        rs.sort()
        for (t0, p0, r0), (t1, p1, r1) in zip(rs, rs[1:]):
            if t1 < since:
                continue
            if abs(r1 - r0) <= 300:
                d = p1 - p0
                if d > 0:
                    mv[(acct, int(t1 // 21600))] += d
            elif r1 > r0 + 300:  # a genuine reset: the new window starts at p1
                mv[(acct, int(t1 // 21600))] += p1
    return mv


def main():
    raw = json.load(open(os.path.join(DATA, "k_raw.json")))
    S = raw["sessions"]
    for s in S:
        s["bucket"], s["how"] = classify(s)
    # same sid on several accounts: propagate a non-other attribution
    by_sid = collections.defaultdict(list)
    for s in S:
        by_sid[s["sid"]].append(s)
    for sid, ss in by_sid.items():
        named = [s for s in ss if s["bucket"] != "other"]
        if named:
            for s in ss:
                if s["bucket"] == "other":
                    s["bucket"], s["how"] = named[0]["bucket"], "S"
    for s in S:
        if s["bucket"] == "other" and s["suspect_lines"] >= 5:
            s["bucket"] = "suspect"
    # fitted price, if the tool produced one
    price = None
    try:
        fit = json.load(open(os.path.join(DATA, "k_ccqp_fit21d.json")))
        price = (fit.get("fit") or {}).get(
            "coef_pp_per_token"
        ) or None  # pp per token, by class
    except (OSError, ValueError):
        fit = None
    agg = collections.defaultdict(lambda: [0, 0, 0, 0, 0])
    hours = collections.defaultdict(lambda: collections.defaultdict(set))
    priced = collections.defaultdict(
        lambda: collections.Counter()
    )  # (acct,6h) -> bucket -> priced
    priced_o = collections.defaultdict(
        lambda: collections.Counter()
    )  # output-only weighting
    for s in S:
        b = s["bucket"]
        for hk, v in s["hours"].items():
            h, model = hk.split("|", 1)
            t = int(h)
            keys = [
                ("all", b),
                ("acct", b, s["acct"]),
                ("week", b, week_of(t)),
                ("stage", b, stage_of(t)),
                ("model", b, model),
                ("how", b, s["how"]),
                ("sub", b, sub_of(s)),
                ("sub_week", b, sub_of(s), week_of(t)),
                ("fleet", "week", week_of(t)),
                ("fleet", "all"),
            ]
            for k in keys:
                a = agg[k]
                for i in range(5):
                    a[i] += v[i]
            hours[b][t].add(s["sid"])
            q = (s["acct"], t // 21600)
            priced[q][b] += v[2] + v[3] + v[1]
            priced_o[q][b] += v[2]
    mv = util_moves()
    pp = collections.defaultdict(lambda: collections.Counter())
    for q, d in mv.items():
        tot, toto = sum(priced[q].values()), sum(priced_o[q].values())
        t = q[1] * 21600
        for b in (
            "program",
            "kit",
            "kit-method",
            "mixed",
            "measurement",
            "suspect",
            "adoption",
        ):
            sh = priced[q][b] / tot if tot else 0.0
            sho = priced_o[q][b] / toto if toto else 0.0
            for k in [
                ("all", b),
                ("week", b, week_of(t)),
                ("stage", b, stage_of(t)),
                ("acct", b, q[0]),
            ]:
                pp[k]["M2"] += d * sh
                pp[k]["M2_output_only"] += d * sho
        pp[("fleet", "all")]["moved"] += d
        pp[("fleet", "week", week_of(t))]["moved"] += d
    if price:
        for k, a in agg.items():
            if k[0] in ("all", "week", "stage", "acct"):
                pp[k]["M1"] = (
                    price.get("output", 0) * a[2]
                    + price.get("cache_creation", 0) * a[3]
                    + price.get("input", 0) * a[1]
                )
    out = {
        "meta": raw["meta"],
        "fit_price": price,
        "fit_verdict": (fit or {}).get("verdict") if fit else "no fit file",
        "agg": [
            {
                "key": list(k),
                "n": v[0],
                "input": v[1],
                "output": v[2],
                "cache_creation": v[3],
                "cache_read": v[4],
            }
            for k, v in sorted(agg.items(), key=lambda kv: str(kv[0]))
        ],
        "pp": [
            {"key": list(k), **{m: round(x, 2) for m, x in v.items()}}
            for k, v in sorted(pp.items(), key=lambda kv: str(kv[0]))
        ],
        "active_hours": {b: len(hs) for b, hs in hours.items()},
        "hours": {
            b: {str(h): len(ss) for h, ss in sorted(hs.items())}
            for b, hs in hours.items()
        },
        "sessions_by_bucket_how": dict(
            collections.Counter(f"{s['bucket']}/{s['how']}" for s in S)
        ),
    }
    with open(os.path.join(DATA, "k_attrib.json"), "w") as fh:
        json.dump(out, fh, indent=1)
    with open(os.path.join(DATA, "k_sessions.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(
            [
                "acct",
                "sid",
                "bucket",
                "how",
                "cwd",
                "first_hour",
                "last_hour",
                "responses",
                "input",
                "output",
                "cache_creation",
                "cache_read",
                "suspect_lines",
                "evidence",  # matched brief phrase (B) or override reason (O); briefs stay local
            ]
        )
        for s in sorted(S, key=lambda s: (s["bucket"], s["acct"], s["sid"])):
            if s["bucket"] == "other":
                continue
            hs = [int(k.split("|")[0]) for k in s["hours"]]
            tot = [sum(v[i] for v in s["hours"].values()) for i in range(5)]
            f = lambda e: datetime.fromtimestamp(e, timezone.utc).strftime(
                "%Y-%m-%dT%HZ"
            )
            w.writerow(
                [
                    s["acct"],
                    s["sid"],
                    s["bucket"],
                    s["how"],
                    s["cwd"],
                    f(min(hs)),
                    f(max(hs)),
                    *tot,
                    s["suspect_lines"],
                    s.get("matched") or (override(s["sid"]) or ("", ""))[1],
                ]
            )
    # summary
    A = {tuple(a["key"]): a for a in out["agg"]}
    P = {tuple(p["key"]): p for p in out["pp"]}
    print("sessions by bucket/how:", out["sessions_by_bucket_how"])
    print("fit:", out["fit_verdict"], price)
    print(
        f"{'bucket':12} {'resp':>8} {'input':>9} {'output':>12} {'cache_create':>14} {'cache_read':>15}  pp_M2  pp_M2o  pp_M1"
    )
    for b in (
        "program",
        "kit",
        "kit-method",
        "mixed",
        "measurement",
        "adoption",
        "suspect",
        "other",
    ):
        a = A.get(("all", b))
        if not a:
            continue
        p = P.get(("all", b), {})
        print(
            f"{b:12} {a['n']:>8} {a['input']:>9} {a['output']:>12,} {a['cache_creation']:>14,} {a['cache_read']:>15,}  "
            f"{p.get('M2', 0):6.1f} {p.get('M2_output_only', 0):6.1f} {p.get('M1', 0):6.1f}"
        )
    f = A[("fleet", "all")]
    print(
        f"{'FLEET':12} {f['n']:>8} {f['input']:>9} {f['output']:>12,} {f['cache_creation']:>14,} {f['cache_read']:>15,}  "
        f"moved {P.get(('fleet', 'all'), {}).get('moved', 0)}"
    )


if __name__ == "__main__":
    main()
