#!/usr/bin/env python3
# Sim-consistent life of a recycle's overhead. usage: python3 -I v6_life.py <verify_dir> <ctx_new> <files_from>
# files_from = "pairs" (all predecessor + successor transcripts) or "all150" (every indexed main session
# that ever reached 150k context; slower). For each policy point (turn start after >=900 s idle, previous
# request ctx >=150k, no offset active), replay sim.py's rule: offset = ctx_prev - ctx_new; later requests
# run at ctx - offset; the overhead lives until the next policy point on the OFFSET context, a compaction
# (ctx < 0.6 x previous, which resets the offset in sim.py) or the session end.
# Prints the distribution of life (requests) and writes v6.life.<files_from>.json. Busy-job holds ignored.
import json, os, statistics as st, sys
from datetime import datetime

V, CTX_NEW, SRC = sys.argv[1], float(sys.argv[2]), sys.argv[3]
ep = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def series(path):
    reqs, idx, turn = [], {}, set()
    pending_turn = False
    with open(path, "rb") as fh:
        for line in fh:
            if b'"isSidechain":true' in line:
                continue
            if b'"type":"user"' not in line and b'"type":"assistant"' not in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("type") == "user":
                c = (r.get("message") or {}).get("content")
                is_tr = isinstance(c, list) and any(
                    isinstance(b, dict) and b.get("type") == "tool_result" for b in c
                )
                if not is_tr and not r.get("isMeta"):
                    pending_turn = True
                continue
            if r.get("type") != "assistant":
                continue
            m = r.get("message") or {}
            if m.get("model") == "<synthetic>":
                continue
            u = m.get("usage") or {}
            k = r.get("requestId") or m.get("id")
            if k in idx:
                continue
            idx[k] = len(reqs)
            if pending_turn:
                turn.add(len(reqs))
                pending_turn = False
            reqs.append(
                (
                    ep(r["timestamp"]),
                    (u.get("input_tokens") or 0)
                    + (u.get("cache_creation_input_tokens") or 0)
                    + (u.get("cache_read_input_tokens") or 0),
                )
            )
    return reqs, turn


if SRC == "pairs":
    files = set()
    for l in open(os.path.join(V, "vpairs.jsonl")):
        p = json.loads(l)
        if p.get("pred_path"):
            files.add(p["pred_path"])
            files.add(p["succ_path"])
else:
    files = set()
    for l in open(os.path.join(V, "idx.jsonl")):
        r = json.loads(l)
        if r["size"] > 2_000_000:  # a 150k-context session is at least a few MB on disk
            files.add(r["path"])
lives, ended_by = [], {"next_point": 0, "compaction": 0, "end": 0}
nsess = 0
for f in sorted(files):
    R, T = series(f)
    if len(R) < 3:
        continue
    nsess += 1
    off = 0
    i = 1
    while i < len(R):
        if R[i][1] < 0.6 * R[i - 1][1]:
            off = 0
        if (
            off == 0
            and i in T
            and R[i][0] - R[i - 1][0] >= 900
            and R[i - 1][1] >= 150000
        ):
            off = max(0, R[i - 1][1] - CTX_NEW)
            j = i + 1
            why = "end"
            while j < len(R):
                if R[j][1] < 0.6 * R[j - 1][1]:
                    why = "compaction"
                    break
                if (
                    j in T
                    and R[j][0] - R[j - 1][0] >= 900
                    and R[j - 1][1] - off >= 150000
                ):
                    why = "next_point"
                    break
                j += 1
            lives.append(j - i)
            ended_by[why] += 1
            off = 0
            i = j
            continue
        i += 1
L = sorted(lives)
print(
    "src=%s ctx_new=%.0f sessions=%d policy points=%d" % (SRC, CTX_NEW, nsess, len(L))
)
print(
    "life (requests the overhead is carried): median %d mean %.0f p25 %d p75 %d p90 %d"
    % (
        st.median(L),
        sum(L) / len(L),
        L[len(L) // 4],
        L[3 * len(L) // 4],
        L[int(0.9 * len(L))],
    )
)
print("ended by:", ended_by)
json.dump(
    dict(lives=L, ended_by=ended_by),
    open(os.path.join(V, "v6.life.%s.json" % SRC), "w"),
)
