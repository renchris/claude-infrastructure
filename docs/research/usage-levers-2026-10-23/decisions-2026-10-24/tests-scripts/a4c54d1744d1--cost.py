"""Per-agent cost of regate:lean:* / regate:default:* in one workflow dir.
Requests = distinct requestId on assistant records. Per request, usage fields take the max over
that request's records (streamed blocks repeat usage; output_tokens grows to its final value).
pp = (0.245*(cache_creation+input) + 0.0067*cache_read + 0.404*output)/1e6 (weekly pp per Mtok).
Usage: python3 -I cost.py <wf_dir>"""
import json, sys, os, collections
WR, WW, WO = 0.0067, 0.245, 0.404
wf = sys.argv[1]
lab = {}
for l in open(os.path.join(wf, "journal.jsonl")):
    r = json.loads(l)
    if r.get("type") == "started" and (r.get("label") or "").startswith("regate:"):
        lab[r["agentId"]] = r["label"]
rows = []
for aid, label in sorted(lab.items(), key=lambda x: x[1]):
    parts = label.split(":")
    if len(parts) < 3 or parts[1] not in ("lean", "default"):
        continue
    f = os.path.join(wf, f"agent-{aid}.jsonl")
    meta = json.load(open(os.path.join(wf, f"agent-{aid}.meta.json")))
    req = collections.OrderedDict()
    tools = collections.Counter()
    vers = set(); ts = []; diffs = 0
    for l in open(f):
        r = json.loads(l)
        if r.get("timestamp"): ts.append(r["timestamp"])
        if r.get("type") != "assistant":
            continue
        vers.add(r.get("version"))
        m = r["message"]; u = m.get("usage") or {}
        rid = r.get("requestId") or m.get("id")
        cc1h = (u.get("cache_creation") or {}).get("ephemeral_1h_input_tokens", 0)
        cur = dict(inp=u.get("input_tokens", 0), cw=u.get("cache_creation_input_tokens", 0),
                   cr=u.get("cache_read_input_tokens", 0), out=u.get("output_tokens", 0), cw1h=cc1h)
        if rid in req:
            prev = req[rid]
            if any(prev[k] != cur[k] for k in ("inp", "cw", "cr")): diffs += 1
            req[rid] = {k: max(prev[k], cur[k]) for k in cur}
        else:
            req[rid] = cur
        for c in m.get("content") or []:
            if isinstance(c, dict) and c.get("type") == "tool_use":
                tools[c.get("name")] += 1
    R = list(req.values())
    tot = {k: sum(x[k] for x in R) for k in ("inp", "cw", "cr", "out", "cw1h")}
    first = R[0]
    pp = (WW * (tot["cw"] + tot["inp"]) + WR * tot["cr"] + WO * tot["out"]) / 1e6
    rows.append(dict(label=label, arm=parts[1], brief=parts[2], agentId=aid, agentType=meta.get("agentType"),
                     versions=sorted(v for v in vers if v), requests=len(R),
                     first_input_side=first["inp"] + first["cw"] + first["cr"],
                     first_cw=first["cw"], first_cr=first["cr"], first_inp=first["inp"],
                     cache_read=tot["cr"], cache_creation=tot["cw"], cache_creation_1h=tot["cw1h"],
                     input=tot["inp"], output=tot["out"], pp=round(pp, 4),
                     pp_read=round(WR * tot["cr"] / 1e6, 4), pp_write=round(WW * (tot["cw"] + tot["inp"]) / 1e6, 4),
                     pp_out=round(WO * tot["out"] / 1e6, 4), tool_calls=sum(tools.values()),
                     tools=dict(tools), t0=min(ts), t1=max(ts), usage_field_diffs_within_request=diffs))
for r in rows:
    print(json.dumps(r))
print("---")
by = collections.defaultdict(dict)
for r in rows: by[r["brief"]][r["arm"]] = r
tl = {"lean": collections.Counter(), "default": collections.Counter()}
for b, d in sorted(by.items()):
    if "lean" in d and "default" in d:
        L, D = d["lean"], d["default"]
        print(f"{b}: requests lean {L['requests']} / default {D['requests']} = {L['requests']/D['requests']:.3f}x ; "
              f"pp lean {L['pp']:.4f} / default {D['pp']:.4f} = {L['pp']/D['pp']:.3f}x ; "
              f"first input-side lean {L['first_input_side']} / default {D['first_input_side']}")
    for a in d:
        for k in ("requests", "pp", "cache_read", "cache_creation", "output", "first_input_side"):
            tl[a][k] += d[a][k]
L, D = tl["lean"], tl["default"]
print(f"POOLED: requests lean {L['requests']} / default {D['requests']} = {L['requests']/D['requests']:.3f}x ; "
      f"pp lean {L['pp']:.4f} / default {D['pp']:.4f} = {L['pp']/D['pp']:.3f}x")
print("pooled totals", dict(L), dict(D))
