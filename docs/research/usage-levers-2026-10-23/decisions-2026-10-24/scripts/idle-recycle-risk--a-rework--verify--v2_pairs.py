#!/usr/bin/env python3
# Successor discovery + pairing check (verifier). usage: python3 -I v2_pairs.py <verify_dir>
# Successor: any of the first 3 non-meta user prompts carries HANDOFF-RECYCLE-.  Predecessor: the uuid in
# "LEDGER AT RETIREMENT (... session <uuid>)".  Checks: predecessor exists, same cwd, predecessor's last
# timestamp vs brief timestamp, predecessor ran handoff-fire --recycle near its end, the brief names the
# predecessor anywhere else. Writes vpairs.jsonl.
import json, os, re, statistics as st, sys, collections
from datetime import datetime

V = sys.argv[1]
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
LED = re.compile(r"LEDGER AT RETIREMENT \([^)]*session (" + UUID + r")")
ep = lambda s: (
    datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp() if s else None
)
R = [json.loads(l) for l in open(os.path.join(V, "idx.jsonl"))]
by = {}
for r in R:
    k = r["sid"] or r["fname"]
    if k not in by or r["size"] > by[k]["size"]:
        by[k] = r
succ = []
pos = collections.Counter()
for k, r in by.items():
    for j, (ts, t, mk, led, tlen) in enumerate(r["prompts"]):
        if mk:
            t = led  # the ledger line, searched below
            succ.append((k, r, j, ts, t))
            pos[j] += 1
            break
print("successors", len(succ), "marker in prompt #", dict(pos))
st_ = collections.Counter()
gaps, rows = [], []
for k, r, j, bts, t in succ:
    m = LED.search(t)
    pred = m.group(1) if m else None
    p = by.get(pred) if pred else None
    row = dict(
        succ=k,
        succ_path=r["path"],
        succ_acct=r["acct"],
        cwd=r["cwd"],
        brief_ts=bts,
        brief_pos=j,
        brief_len=r["prompts"][j][4],
        pred=pred,
        pred_path=p["path"] if p else None,
        pred_acct=p["acct"] if p else None,
    )
    if not pred:
        st_["no_ledger_uuid"] += 1
    elif not p:
        st_["pred_file_missing"] += 1
    else:
        st_["paired"] += 1
        row["same_cwd"] = p["cwd"] == r["cwd"]
        st_["same_cwd"] += int(row["same_cwd"])
        st_["same_acct"] += int(p["acct"] == r["acct"])
        g = ep(bts) - ep(p["ts_last"])
        row["pred_last_minus_brief_s"] = -g
        gaps.append(g)
        hf = [c for c in p["hf_cmds"] if "--recycle" in c[1]]
        row["pred_ran_recycle"] = bool(hf)
        st_["pred_ran_recycle"] += int(bool(hf))
        if hf:
            d = ep(bts) - ep(hf[-1][0])
            row["recycle_cmd_to_brief_s"] = d
        st_["pred_is_self"] += int(pred == k)
    rows.append(row)
print(dict(st_))
gs = sorted(gaps)
print(
    "brief_ts - pred ts_last (s): n=%d min %.0f p10 %.0f median %.0f p90 %.0f max %.0f; negative(pred active after brief)=%d; >1h=%d"
    % (
        len(gs),
        gs[0],
        gs[len(gs) // 10],
        st.median(gs),
        gs[int(len(gs) * 0.9)],
        gs[-1],
        sum(1 for x in gs if x < 0),
        sum(1 for x in gs if x > 3600),
    )
)
d = sorted(r["recycle_cmd_to_brief_s"] for r in rows if "recycle_cmd_to_brief_s" in r)
print(
    "recycle cmd -> brief (s): n=%d median %.0f p90 %.0f max %.0f; within 30 min %d"
    % (
        len(d),
        st.median(d),
        d[int(len(d) * 0.9)],
        d[-1],
        sum(1 for x in d if 0 <= x <= 1800),
    )
)
with open(os.path.join(V, "vpairs.jsonl"), "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
