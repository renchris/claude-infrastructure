#!/usr/bin/env python3
"""Independent pricing of a deny rule over myjoined.json, with the researcher's model as the base case
and reviewer corrections as switches. Usage: python3 -I price.py myjoined.json <days> [t_from_iso]
Weights pp/Mtok (round 3): read 0.0057-0.0076, write 0.245 (blended 5m+1h fit), output 0.404."""

import json, math, re, sys
from datetime import datetime
from collections import Counter, defaultdict

J = json.load(open(sys.argv[1]))
DAYS = float(sys.argv[2])
if len(sys.argv) > 3:
    tf = datetime.fromisoformat(sys.argv[3].replace("Z", "+00:00")).timestamp()
    J = [r for r in J if r["t"] >= tf]
wk = 7.0 / DAYS
TO_RX = re.compile(r"(?:^|[;&|\s(])g?timeout\s+(?:-\S+\s+)*([0-9]+)([sm]?)\s")


def selfbound(cmd):
    ns = [
        int(m.group(1)) * (60 if m.group(2) == "m" else 1) for m in TO_RX.finditer(cmd)
    ]
    return bool(ns) and max(ns) < 300


# remaining requests after the call in the same agent file (for persistent context growth)
REM = {}
for r in J:
    pass


def scen(read, w_extra, o_extra, W):
    return dict(R=read, w=w_extra, o=o_extra, W=W)


def price(
    rows,
    k,
    comply=1.0,
    poll_short=1,
    poll_bg=False,
    growth=0,
    rem=None,
    dedup_req=False,
    O=0.404,
):
    s = c = wrong = 0.0
    seen_mid = set()
    for r in rows:
        rt = r["rt"]
        if rt is None:
            continue
        kk = math.ceil(rt / 270.0) if rt > 270 else 1
        if r["why"] == "poll-loop" and not poll_bg:
            n = kk if rt > 270 else poll_short
        else:
            n = 1 + kk if rt > 270 else 2
        per = (r["ctx"] * k["R"] + k["w"] * k["W"] + k["o"] * O) / 1e6
        cost = n * per
        if growth and rem is not None:
            cost += n * growth * rem.get(r["id"], 0) * k["R"] / 1e6
        c += cost
        if rt <= 270:
            wrong += cost
        if r["reb"]:
            if dedup_req and r["mid"] in seen_mid:
                continue
            seen_mid.add(r["mid"])
            s += comply * min(r["ncc"], r["ctx"]) * (k["W"] - k["R"]) / 1e6
    return (
        round((s - c) * wk, 2),
        round(s * wk, 2),
        round(c * wk, 2),
        round(wrong * wk, 2),
    )


if __name__ == "__main__":
    # remaining requests after each call: needs nfile/idx -> recompute from broad_v.jsonl
    rem = {}
    try:
        for l in open("/tmp/lean-idle/w3-subagent-deny/review-numbers/broad_v.jsonl"):
            x = json.loads(l)
            rem[x["id"]] = max(0, x["nfile"] - x["idx"] - 1)
    except OSError:
        pass
    sets = {
        "narrow": [r for r in J if r["why"]],
        "poll-loop": [r for r in J if r["why"] == "poll-loop"],
        "long-runner": [r for r in J if r["why"] == "long-runner"],
        "waiter": [r for r in J if r["why"] == "waiter"],
        "narrow-selfbound": [r for r in J if r["why"] and not selfbound(r["cmd"])],
        "broad": J,
    }
    LOW = dict(R=0.0057, w=500, o=60, W=0.245)
    HIGH = dict(R=0.0076, w=1234, o=300, W=0.245)
    for name, rows in sets.items():
        nres = [r for r in rows if r["rt"] is not None]
        print(
            "## %s calls %d (%.0f/wk) short %.3f rebuilt %d"
            % (
                name,
                len(rows),
                len(rows) * wk,
                sum(r["rt"] <= 270 for r in nres) / max(1, len(nres)),
                sum(r["reb"] for r in rows),
            )
        )
        for kn, k in (("low", LOW), ("high", HIGH)):
            for cm in (1.0, 0.7, 0.5):
                print(
                    "  %s c%.1f researcher-model net/save/cost/wrong %s"
                    % (kn, cm, price(rows, k, cm))
                )
        # reviewer corrections
        for kn, k in (("low", LOW), ("high", HIGH)):
            k2 = dict(k, W=0.20)
            k3 = dict(k, W=0.153)
            print(
                "  %s c1.0 | poll short via bg (2 extra) %s | +ctx growth %s | W5m=0.20 %s | W5m=0.153 %s | all(0.20,bg,growth) c1.0 %s c0.7 %s c0.5 %s"
                % (
                    kn,
                    price(rows, k, 1.0, poll_bg=True)[::3],
                    price(rows, k, 1.0, growth=k["w"], rem=rem)[::3],
                    price(rows, k2, 1.0)[::3],
                    price(rows, k3, 1.0)[::3],
                    price(rows, k2, 1.0, poll_bg=True, growth=k["w"], rem=rem)[::3],
                    price(rows, k2, 0.7, poll_bg=True, growth=k["w"], rem=rem)[::3],
                    price(rows, k2, 0.5, poll_bg=True, growth=k["w"], rem=rem)[::3],
                )
            )
    nr = [r for r in J if r["why"]]
    rr = [rem.get(r["id"], 0) for r in nr]
    rr.sort()
    print(
        "remaining requests after a narrow call: median %d mean %.1f p90 %d"
        % (rr[len(rr) // 2], sum(rr) / len(rr), rr[int(len(rr) * 0.9)])
    )
    sb = [r for r in nr if selfbound(r["cmd"])]
    print(
        "selfbound narrow",
        len(sb),
        Counter(r["why"] for r in sb),
        "rebuilt",
        sum(r["reb"] for r in sb),
    )
