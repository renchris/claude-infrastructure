#!/usr/bin/env python3
"""Reviewer: how much of a default slot's first request is the agent-type prefix, and how much is the
brief? Fit first_tokens = a + b*brief_chars per (version, agentType); report prefix delta by version
and the brief-driven excess that the researcher's d = first_tokens - 9200 counts as saving."""

import collections
import json
import statistics as st

O = "/tmp/lean-idle/workflow-lean/review-numbers"
S = [json.loads(l) for l in open(f"{O}/slots.jsonl")]
S = [s for s in S if s["nreq"] and s["first_ts"] and s["first_ts"] >= "2026-09-24T05"]


def ft(s):
    return s["first_cw"] + s["first_cr"] + s["first_in"]


def fit(xs, ys):
    mx, my = st.mean(xs), st.mean(ys)
    sxx = sum((x - mx) ** 2 for x in xs)
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx if sxx else 0
    return my - b * mx, b


g = collections.defaultdict(list)
for s in S:
    g[(s["version"], s["agentType"])].append(s)
vers = collections.Counter(
    s["version"] for s in S if s["agentType"] == "workflow-subagent"
)
print("default slots by version", vers.most_common(8))
res = {}
for (v, at), ss in sorted(g.items(), key=lambda kv: -len(kv[1])):
    if at not in ("workflow-subagent", "workflow-lean") or len(ss) < 30:
        continue
    # small-brief subset: brief < 6000 chars, to get the intercept robustly
    small = [s for s in ss if s["brief_chars"] < 6000]
    a, b = fit([s["brief_chars"] for s in ss], [ft(s) for s in ss])
    med_small = (
        st.median([ft(s) - s["brief_chars"] / 3.6 for s in small]) if small else None
    )
    res[(v, at)] = (a, b, med_small)
    print(
        f"{v} {at:18s} n={len(ss):5d} median_first={st.median([ft(s) for s in ss]):8.0f} "
        f"median_brief_chars={st.median([s['brief_chars'] for s in ss]):6.0f} fit a={a:8.0f} b={b:.3f} tok/char "
        f"median(first - brief/3.6, brief<6k)={med_small:8.0f}"
    )
for v in vers:
    if (v, "workflow-subagent") in res and (v, "workflow-lean") in res:
        print(
            "prefix delta",
            v,
            "intercepts",
            round(res[(v, "workflow-subagent")][0] - res[(v, "workflow-lean")][0]),
            "median-method",
            round(res[(v, "workflow-subagent")][2] - res[(v, "workflow-lean")][2]),
        )
# brief excess: for default slots, (first - 9200) vs constant delta
for v in sorted(vers):
    ss = [s for s in S if s["agentType"] == "workflow-subagent" and s["version"] == v]
    if len(ss) < 30:
        continue
    d_res = sum(max(0, ft(s) - 9200) for s in ss) / len(ss)
    print(
        v,
        "mean d_researcher",
        round(d_res),
        "mean brief tok (chars/3.6)",
        round(st.mean(s["brief_chars"] / 3.6 for s in ss)),
        "p90 brief chars",
        sorted(s["brief_chars"] for s in ss)[int(0.9 * len(ss))],
    )
