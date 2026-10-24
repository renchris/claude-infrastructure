#!/usr/bin/env python3
# Build per-(account, day) series and a per-session table from the scan output, meter and land data.
# usage: python3 -I build.py <data_dir>
# Dedup: one row per requestId across ALL accounts and files; the copy kept is the one in the account
# that holds the parent main session's own transcript (main sessions have 0 cross-account duplicates).
import json
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

D = sys.argv[1]
S = 1790398800
E = S + 28 * 86400
CDT = timezone(timedelta(hours=-5))
ACCTS = ["next", "next2", "next3", "next4"]
W_READ, W_WRITE, W_OUT = (
    0.0067,
    0.245,
    0.404,
)  # weekly pp per Mtok (brief); uncached input priced as write (est.)
GAP_ACTIVE = 600.0  # a gap <= 10 min between requests of one session (main + its subagents) counts as active


def day_of(t):
    return datetime.fromtimestamp(t, CDT).strftime("%Y-%m-%d")


DAYS = [day_of(S + i * 86400 + 3600) for i in range(28)]
WEEK = {d: i // 7 for i, d in enumerate(DAYS)}

# ---- files
files = {}  # (acct, fi) -> dict
main_owner = defaultdict(set)  # parent sid -> accounts holding its main transcript
for a in ACCTS:
    with open(os.path.join(D, a + ".files.tsv")) as fh:
        hdr = fh.readline().rstrip("\n").split("\t")
        for line in fh:
            v = line.rstrip("\n").split("\t")
            r = dict(zip(hdr, v))
            for k in (
                "is_sub",
                "tool_results",
                "tool_err",
                "tool_err_hook",
                "tool_err_user",
                "ptl_n",
                "ratelimit_n",
                "apierr_n",
                "workflow_calls",
                "agent_calls",
                "poll_loops",
                "bash_calls",
            ):
                r[k] = int(r[k])
            r["ptl_last_ts"] = float(r["ptl_last_ts"])
            r["last_real_ts"] = float(r["last_real_ts"])
            files[(a, int(r["fi"]))] = r

# ---- requests
reqs = {}  # requestId -> list of copies
for a in ACCTS:
    with open(os.path.join(D, a + ".req.tsv")) as fh:
        fh.readline()
        for line in fh:
            v = line.rstrip("\n").split("\t")
            row = (
                a,
                int(v[1]),
                int(v[2]),
                v[3],
                float(v[4]),
                v[6],
                int(v[7]),
                int(v[8]),
                int(v[9]),
                int(v[10]),
                int(v[11]),
                int(v[12]),
            )
            # acct, fi, is_sub, parent_sid, ts, model, inp, cc, cc1h, cr, out, turn
            if not row[2]:
                main_owner[row[3]].add(a)
            reqs.setdefault(v[5], []).append(row)

dup_stats = Counter()
kept = []
for k, cps in reqs.items():
    if len(cps) == 1:
        kept.append(cps[0])
        continue
    accts = {c[0] for c in cps}
    dup_stats["dup_ids_cross_acct" if len(accts) > 1 else "dup_ids_same_acct"] += 1
    own = main_owner.get(cps[0][3], set())
    pick = None
    for c in cps:
        if c[0] in own:
            pick = c
            break
    if pick is None:
        dup_stats["dup_no_owner"] += 1
        pick = min(cps, key=lambda c: (c[2], c[0]))
    kept.append(pick)
dup_stats["raw_rows"] = sum(len(c) for c in reqs.values())
dup_stats["unique_ids"] = len(reqs)
del reqs

# ---- per account-day and per session
day = defaultdict(lambda: defaultdict(float))  # (acct, day) -> metric -> value
sess = {}  # (acct, parent_sid) -> dict
models = Counter()
by_sess_ts = defaultdict(list)
main_rows = defaultdict(list)
for a, fi, is_sub, psid, ts, model, inp, cc, cc1h, cr, out, turn in kept:
    if ts < S or ts >= E:
        # pre-window slack rows only serve gap/ctx lookups for main sessions
        if not is_sub and S - 86400 <= ts < S:
            main_rows[(a, psid)].append((ts, inp + cc + cr, turn, 1))
        continue
    wpp = ((inp + cc) * W_WRITE + cr * W_READ + out * W_OUT) / 1e6
    d = day_of(ts)
    k = (a, d)
    x = day[k]
    x["req"] += 1
    x["out"] += out
    x["wpp"] += wpp
    x["wpp_read"] += cr * W_READ / 1e6
    x["wpp_write"] += (inp + cc) * W_WRITE / 1e6
    x["wpp_out"] += out * W_OUT / 1e6
    x["main_wpp" if not is_sub else "sub_wpp"] += wpp
    models[(model.split("-20")[0], is_sub)] += 1
    sk = (a, psid)
    s = sess.get(sk)
    if s is None:
        s = sess[sk] = defaultdict(float)
        s["first"] = ts
    s["first"] = min(s["first"], ts)
    s["req"] += 1
    s["out"] += out
    s["wpp"] += wpp
    if not is_sub:
        s["main_req"] += 1
        main_rows[sk].append((ts, inp + cc + cr, turn, 0))
    by_sess_ts[sk].append(ts)

# sessions must have a main transcript row in the window to count as a main session
for sk in list(sess):
    if sess[sk]["main_req"] == 0:
        sess[sk]["orphan_sub"] = 1

# active time: union of main + subagent request times, gaps <= GAP_ACTIVE
for sk, tss in by_sess_ts.items():
    tss.sort()
    act = 0.0
    for i in range(1, len(tss)):
        g = tss[i] - tss[i - 1]
        if g <= GAP_ACTIVE:
            act += g
            day[(sk[0], day_of(tss[i]))]["active_s"] += g
    sess[sk]["active_s"] = act

# idle points (main): turn-start request after a gap; context of the previous main request
for sk, rs in main_rows.items():
    rs.sort()
    s = sess.get(sk)
    if s is None:
        continue
    for i in range(1, len(rs)):
        ts, ctx, turn, pre = rs[i]
        if pre or not turn:
            continue
        g = ts - rs[i - 1][0]
        pctx = rs[i - 1][1]
        if g >= 900 and pctx >= 200000:
            s["d1_points"] += 1
        if g >= 3300:
            s["d3_gaps"] += 1

# file-level counters -> session and day (errors split by the file's request-days, est.)
file_days = defaultdict(Counter)
for a, fi, is_sub, psid, ts, *_r in kept:
    if S <= ts < E:
        file_days[(a, fi)][day_of(ts)] += 1
for (a, fi), f in files.items():
    sk = (a, f["parent_sid"])
    s = sess.get(sk)
    fd = file_days.get((a, fi))
    if not fd:
        continue
    tot = sum(fd.values())
    if s is not None:
        s["tool_results"] += f["tool_results"]
        s["tool_err"] += f["tool_err"]
        s["tool_err_nohook"] += f["tool_err"] - f["tool_err_hook"]
        s["tool_err_hook"] += f["tool_err_hook"]
        s["workflow_calls"] += f["workflow_calls"]
        s["poll_loops"] += f["poll_loops"]
        s["ratelimit_n"] += f["ratelimit_n"]
    for d, n in fd.items():
        x = day[(a, d)]
        share = n / tot
        x["tool_results"] += f["tool_results"] * share
        x["tool_err"] += f["tool_err"] * share
        x["tool_err_nohook"] += (f["tool_err"] - f["tool_err_hook"]) * share
    # prompt-too-long death: a PTL error with no real request after it in that file
    if f["ptl_n"] and S <= f["ptl_last_ts"] < E:
        death = f["last_real_ts"] < f["ptl_last_ts"]
        key = "ptl_sub" if f["is_sub"] else "ptl_main"
        day[(a, day_of(f["ptl_last_ts"]))][key + "_any"] += 1
        if death:
            day[(a, day_of(f["ptl_last_ts"]))][key + "_death"] += 1
            if s is not None and not f["is_sub"]:
                s["ptl_death"] = 1

# main sessions started per day
for sk, s in sess.items():
    if not s.get("orphan_sub"):
        day[(sk[0], day_of(s["first"]))]["sessions"] += 1

# ---- lands
sid_acct = defaultdict(set)
for sk in sess:
    sid_acct[sk[1]].add(sk[0])
land_stats = Counter()
for l in open(os.path.join(D, "lands_c.jsonl")):
    r = json.loads(l)
    accts = sid_acct.get(r["sid"] or "", set())
    if len(accts) != 1:
        land_stats[
            "unattributed_"
            + ("nosid" if not r["sid"] else "nomatch" if not accts else "multi")
        ] += 1
        a = "?"
    else:
        a = next(iter(accts))
    ok = r["exit"] == 0
    c = r.get("commits", 0) if ok else 0
    land_stats["ok" if ok else "fail"] += 1
    d = day_of(r["t"])
    x = day[(a, d)]
    x["land_ok" if ok else "land_fail"] += 1
    if r["exit"] == 6:
        x["land_red"] += 1
    x["commits"] += c
    if a != "?":
        s = sess.get((a, r["sid"]))
        if s is not None:
            s["land_ok" if ok else "land_fail"] += 1
            s["commits"] += c

# ---- meter
meter = json.load(open(os.path.join(D, "meter.json")))
for a in ACCTS:
    for d in DAYS:
        day[(a, d)]["meter_pp"] = meter[a]["pp"][d]
        day[(a, d)]["sat_min"] = meter[a]["sat_min"][d]

out = {
    "days": DAYS,
    "day": {"%s|%s" % k: dict(v) for k, v in day.items()},
    "sess": [dict(v, acct=k[0], sid=k[1]) for k, v in sess.items()],
    "dup_stats": dict(dup_stats),
    "land_stats": dict(land_stats),
    "models": {"%s|%d" % k: v for k, v in models.most_common()},
}
json.dump(out, open(os.path.join(D, "built.json"), "w"))
print("dup", dict(dup_stats))
print("lands", dict(land_stats))
print("models", models.most_common(8))
print(
    "sessions",
    sum(1 for s in sess.values() if not s.get("orphan_sub")),
    "orphan_sub",
    sum(1 for s in sess.values() if s.get("orphan_sub")),
)
