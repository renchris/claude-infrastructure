"""Per meter reading: cumulative OTHER-session next3 usage between the window start and that reading.

Same reader as others.py (dedupe by message.id, bytes past the start snapshot only), bucketed by
each record's own timestamp against meters.jsonl's reading times. Converts with round 2's weekly
weights (reads 0.00481, writes 0.245, output 0.404 pp/Mtok) and the 5h/weekly read ratio 4.14.
"""
import glob
import json
import os
import datetime
T0 = int(open("/tmp/w2probe/t-start.txt").read().strip())
snap = {p: int(n) for p, n in (line.rsplit(" ", 1) for line in open("/tmp/w2probe/snap-start.txt"))}
recs, seen = [], set()
for f in glob.glob(os.path.expanduser("~/.claude-tertiary/projects/**/*.jsonl"), recursive=True):
    if os.path.getmtime(f) < T0:
        continue
    with open(f, "rb") as fh:
        fh.seek(snap.get(f, 0))
        for raw in fh:
            try:
                d = json.loads(raw)
            except Exception:
                continue
            m = d.get("message") or {}
            u = m.get("usage")
            if d.get("type") != "assistant" or not u or m.get("model") == "<synthetic>":
                continue
            k = m.get("id") or d.get("uuid")
            if k in seen:
                continue
            seen.add(k)
            ts = datetime.datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00")).timestamp()
            recs.append((ts, u.get("cache_read_input_tokens", 0), u.get("cache_creation_input_tokens", 0),
                         u.get("output_tokens", 0), u.get("input_tokens", 0), os.path.basename(os.path.dirname(f))))
W_R, W_W, W_O, R5 = 0.00481, 0.245, 0.404, 0.0199 / 0.00481
out = []
for line in open("/tmp/w2probe/meters.jsonl"):
    m = json.loads(line)
    t = datetime.datetime.fromisoformat(m["ts"]).timestamp()
    sel = [r for r in recs if T0 <= r[0] <= t]
    rd, wr, op = sum(r[1] for r in sel), sum(r[2] for r in sel), sum(r[3] for r in sel)
    wk_ch = (W_R * rd + W_W * wr + W_O * op) / 1e6
    wk_fr = (W_W * wr + W_O * op) / 1e6
    out.append({"label": m["label"], "ts": m["ts"], "other_requests": len(sel), "other_reads": rd,
                "other_writes": wr, "other_output": op,
                "other_weekly_pp_if_charged": round(wk_ch, 3), "other_weekly_pp_if_free": round(wk_fr, 3),
                "other_5h_pp_if_charged": round(R5 * wk_ch, 3), "other_5h_pp_if_free": round(R5 * wk_fr, 3)})
json.dump(out, open("/tmp/w2probe/others_ts.json", "w"), indent=1)
for r in out:
    print(r["label"], r["ts"][11:19], r["other_requests"], r["other_reads"], r["other_writes"], r["other_output"], r["other_weekly_pp_if_charged"], r["other_weekly_pp_if_free"], r["other_5h_pp_if_charged"], r["other_5h_pp_if_free"])
first = min(recs)[0] if recs else None
print("first other record:", datetime.datetime.fromtimestamp(first).strftime("%H:%M:%S") if first else None,
      "projects:", sorted({r[5] for r in recs}))
