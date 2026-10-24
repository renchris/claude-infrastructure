import json, sys, re, collections
CUT="2026-09-29T00:00:00Z"; W30="2026-08-30T00:00:00Z"
rows=[]; bad=0
for line in open(sys.argv[1], encoding="utf-8"):
    try: r=json.loads(line)
    except Exception: bad+=1; continue
    rows.append(r)
pre=[r for r in rows if (r.get("ts") or "")<CUT]
asks=[r for r in pre if r.get("decision")=="ask"]
def cls(reason):
    reason=reason or ""
    if "confirm intent" in reason: return "confirm intent"
    if reason.startswith("No URL parsed"): return "No URL parsed"
    if reason.startswith("Non-HTTP scheme"): return "Non-HTTP scheme"
    m=re.match(r"^(\S+) to unknown host ", reason)
    if m: return f"{m.group(1)} to unknown host" + (" (sends a body)" if "sends a body" in reason else "")
    m=re.match(r"^(\S+) to unvetted host ", reason)
    if m: return f"{m.group(1)} to unvetted host"
    return "OTHER: "+reason[:60]
print("total rows", len(rows), "unparseable", bad, "pre-cutoff rows", len(pre), "ts range", min(r["ts"] for r in pre), max(r["ts"] for r in pre))
for label, sel in (("ALL", asks), ("LAST30", [r for r in asks if r["ts"]>=W30])):
    tids={r.get("tool_use_id") for r in sel}; sids={r.get("session_id") for r in sel}
    print(f"\n== {label}: ask rows={len(sel)} distinct tool_use_id={len(tids)} (null tid rows={sum(1 for r in sel if not r.get('tool_use_id'))}) sessions={len(sids)}")
    c=collections.Counter(cls(r.get("reason")) for r in sel)
    for k,v in c.most_common(): print(f"  {v:6d} {100*v/len(sel):5.1f}%  {k}  (prompts={len({r.get('tool_use_id') for r in sel if cls(r.get('reason'))==k})})")
    ci=[r for r in sel if "confirm intent" in (r.get("reason") or "")]
    print(f"  confirm-intent: rows={len(ci)} share={100*len(ci)/max(1,len(sel)):.1f}% prompts={len({r.get('tool_use_id') for r in ci})} sessions={len({r.get('session_id') for r in ci})}")
    print("  split:", collections.Counter("POST to unknown host" if r["reason"].startswith("POST to unknown host") else "<METHOD> <host> — confirm intent" for r in ci))
    print("  method field:", collections.Counter(r.get("method") for r in ci))
    mm=[]
    for r in ci:
        m=re.match(r"^(\S+)", r["reason"]); rm=m.group(1)
        if rm!=r.get("method"): mm.append((rm, r.get("method")))
    print("  method-vs-reason mismatches:", len(mm), collections.Counter(mm).most_common(5))
    hc=collections.Counter(r.get("host") for r in ci)
    print("  distinct hosts:", len(hc), " top5:", hc.most_common(5))
    print("  all hosts:", hc.most_common())
    # reason-host vs host field
    hm=0
    for r in ci:
        rs=r["reason"]
        h=re.sub(r" — confirm intent$","",rs); h=h.split(" to unknown host ")[-1] if " to unknown host " in h else h.split(" ",1)[1] if " " in h else ""
        if h!=(r.get("host") or ""): hm+=1
    print("  reason-host != host field:", hm)
