import json,collections,re,datetime,statistics
res=json.load(open('results.json'))
arc=json.load(open('archive.json'))
audit=[json.loads(l) for l in open('audit_snapshot.jsonl')]
asks=[r for r in audit if r['decision']=='ask' and str(r['tool_use_id']).startswith('toolu_')]
def epoch(s): return datetime.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp()
byc={}; bys=collections.defaultdict(list)
for r in arc:
    if r.get('cleared_tool_use_id'): byc.setdefault(r['cleared_tool_use_id'],r)
    bys[r['session_id']].append(r)
def cls(reason):
    if reason.startswith('POST to unknown host'): return 'CONFIRM:POST-unknown-host'
    if 'confirm intent' in reason: return 'CONFIRM:method+host'
    if reason.startswith('No URL parsed'): return 'no-url-parsed'
    if 'unvetted host' in reason: return 'GET-with-credential'
    if reason.startswith('GET to unknown host'): return 'GET-unknown-host(retired)'
    if 'sends a body' in reason: return 'GET-with-body'
    if reason.startswith('Non-HTTP'): return 'non-http-scheme'
    return 'other'
def outcome(r):
    if not r: return 'unknown(no transcript)'
    t=r['text']
    if "doesn't want to proceed" in t or 'was rejected' in t: return 'DENIED'
    if t.startswith('[Request interrupted') or 'Interrupted' in t[:40]: return 'INTERRUPTED'
    return 'GRANTED'  # tool executed (exit 0 or nonzero)
rows=[]
for a in asks:
    r=res.get(a['tool_use_id']); arow=byc.get(a['tool_use_id']); join='exact' if arow else None
    if not arow:
        c=[x for x in bys.get(a['session_id'],[]) if x.get('tool_name')=='Bash' and 0<=x['ts']-epoch(a['ts'])+2<=17 and (x.get('tool_input') or {}).get('command','')[:60].replace('\n',' ')[:40] in a['cmd_redacted'].replace('\n',' ')]
        if c: arow=c[0]; join='window+cmd'
    host=a.get('host') or '(none)'
    if host.startswith('mozilla') or ' ' in host or '(' in host: host='(parser-garbage)'
    rows.append(dict(ts=a['ts'],day=a['ts'][:10],sid=a['session_id'],tid=a['tool_use_id'],cls=cls(a['reason']),host=host,method=a.get('method'),
        outcome=outcome(r),prompt_archived=bool(arow),join=join,waited_s=arow['waited_s'] if arow else None,resolved_by=arow['resolved_by'] if arow else None,cmd=a['cmd_redacted'][:300],reason=a['reason']))
json.dump(rows,open('asks_enriched.json','w'))
