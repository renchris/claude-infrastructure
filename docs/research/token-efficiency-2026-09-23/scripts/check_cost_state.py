#!/usr/bin/env python3
"""Independent check of extract.sqlite against Claude Code's own per-session accounting.

Main transcripts carry `cost-state` records: {"modelUsage": {model: {inputTokens, outputTokens,
cacheReadInputTokens, cacheCreationInputTokens, ...}}, "startTime": ...}, the process's cumulative
counter. For sessions whose startTime is in the window, compare the LAST cost-state of the main file
to the extract's sum over the session's main+subagent+workflow files (xdup=0), per token class,
for output_first / output_tokens / output_est. Prints aggregates only."""
import json, os, sqlite3, sys, collections
D = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")
db = sqlite3.connect(os.path.join(D, "extract.sqlite"))
since = db.execute("select v from meta where k='since'").fetchone()[0]
mains = db.execute("select file, session_id from ctx where ctx_type='main'").fetchall()
agg = collections.Counter(); n = 0; per = []; bym = collections.Counter()
for f, sid in mains:
    last = None
    try:
        for line in open(f, "rb"):
            if b'"cost-state"' in line[:60] or b'"type":"cost-state"' in line:
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if r.get("type") == "cost-state":
                    last = r
    except OSError:
        continue
    if not last:
        continue
    st = last.get("startTime")
    try:
        from datetime import datetime, timezone
        st_iso = datetime.fromtimestamp(st / 1000 if st > 1e11 else st, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S") if isinstance(st, (int, float)) else str(st)
    except Exception:
        continue
    if st_iso < since[:19]:
        continue
    mu = last.get("modelUsage") or {}
    cs = collections.Counter()
    for m, u in mu.items():
        cs["input"] += u.get("inputTokens") or 0; cs["output"] += u.get("outputTokens") or 0
        cs["cache_read"] += u.get("cacheReadInputTokens") or 0; cs["cc"] += u.get("cacheCreationInputTokens") or 0
    ex = db.execute("select sum(input_tokens), sum(output_first), sum(output_tokens), sum(output_est), sum(cache_read), sum(cc_total), count(*) "
                    "from resp where session_id=? and xdup=0 and ts>=?", (sid, st_iso)).fetchone()
    if not ex[6]:
        continue
    n += 1
    for k, v in cs.items(): agg["cs_" + k] += v
    for k, v in zip(("input", "out_first", "out_final", "out_est", "cache_read", "cc"), ex[:6]): agg["ex_" + k] += v or 0
    per.append((cs["output"], ex[1] or 0, ex[2] or 0, ex[3] or 0))
    for m, u in mu.items():
        bym[(m, "cs_in")] += u.get("inputTokens") or 0; bym[(m, "cs_out")] += u.get("outputTokens") or 0
        bym[(m, "cs_cr")] += u.get("cacheReadInputTokens") or 0; bym[(m, "cs_cc")] += u.get("cacheCreationInputTokens") or 0
    for m, a, b, c_, d, e in db.execute("select model, sum(input_tokens), sum(output_tokens), sum(output_est), sum(cache_read), sum(cc_total) from resp where session_id=? and xdup=0 and ts>=? group by 1", (sid, st_iso)):
        bym[(m, "ex_in")] += a or 0; bym[(m, "ex_out")] += b or 0; bym[(m, "ex_est")] += c_ or 0; bym[(m, "ex_cr")] += d or 0; bym[(m, "ex_cc")] += e or 0
print("sessions compared:", n)
for k in ("input", "cache_read", "cc"):
    a, b = agg["ex_" + k], agg["cs_" + k]
    print(f"{k:12s} extract={a:>15,} cost-state={b:>15,} extract/cost-state={a / b if b else float('nan'):.4f}")
for k in ("out_first", "out_final", "out_est"):
    a, b = agg["ex_" + k], agg["cs_output"]
    print(f"{k:12s} extract={a:>15,} cost-state={b:>15,} extract/cost-state={a / b if b else float('nan'):.4f}")
# per-session: which output variant is closest to cost-state
win = collections.Counter()
for cs_o, f1, f2, f3 in per:
    if cs_o <= 0: continue
    win[min((abs(f1 - cs_o), "first"), (abs(f2 - cs_o), "final"), (abs(f3 - cs_o), "est"))[1]] += 1
print("closest variant per session:", dict(win))

print("per model (M tokens):  cost-state in/out/cr/cc  |  extract in/out_final/out_est/cr/cc")
for m in sorted({k[0] for k in bym}, key=lambda m: -(bym[(m, "cs_cr")] + bym[(m, "ex_cr")])):
    f = lambda k: bym[(m, k)] / 1e6
    print(f"  {m:28s} {f('cs_in'):8.2f} {f('cs_out'):8.2f} {f('cs_cr'):9.1f} {f('cs_cc'):8.1f} | {f('ex_in'):6.2f} {f('ex_out'):8.2f} {f('ex_est'):8.2f} {f('ex_cr'):9.1f} {f('ex_cc'):8.1f}")
