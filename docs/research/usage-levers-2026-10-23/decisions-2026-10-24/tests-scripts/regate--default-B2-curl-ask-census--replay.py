import json, sys, collections
rows=[json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
u=[r for r in rows if r['tool_use_id']=="unknown" and r['ts'].startswith("2026-09-10")]
print("09-10 unknown rows", len(u), "first", u[0]['ts'], "last", u[-1]['ts'], "sessions", len({r['session_id'] for r in u}))
print("cwd sample", collections.Counter(r['cwd'] for r in u).most_common(3))
real_cmds={}
for r in rows:
    if r['tool_use_id']!="unknown": real_cmds.setdefault(r['cmd_redacted'], r['ts'])
m=[r for r in u if r['cmd_redacted'] in real_cmds]
print("09-10 unknown rows whose cmd also appears with a real tid:", len(m), " earlier-than-replay:", sum(1 for r in m if real_cmds[r['cmd_redacted']]<r['ts']))
print("decision mix", collections.Counter(r['decision'] for r in u))
# real-tid rows on 09-10 for comparison
print("real-tid rows on 09-10:", sum(1 for r in rows if r['ts'].startswith('2026-09-10') and r['tool_use_id']!='unknown'))
by_min=collections.Counter(r['ts'][:16] for r in u); print("busiest minutes", by_min.most_common(3), "minutes spanned", len(by_min))
o=[r for r in rows if r['tool_use_id']=="unknown" and not r['ts'].startswith("2026-09-10") and r['decision']=='ask' and r['ts']<"2026-09-29"]
for r in o: print(" other-unknown ask", r['ts'], r['reason'][:50], r['cmd_redacted'][:80])
