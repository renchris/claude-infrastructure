import json,re,sys,collections
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/curl-audit.jsonl') if l.strip()]
def tpl(r):
    s=r['reason']
    if s.startswith('No URL parsed'): return 'nourl'
    if s.startswith('Non-HTTP'): return 'nonhttp'
    if 'request carries' in s: return 'cred'
    if 'and it sends a body' in s: return 'body'
    if s.startswith('POST to unknown host') and 'confirm intent' in s: return 'post-confirm'
    if 'confirm intent' in s: return 'method-confirm'
    if s.startswith('Mixed'): return 'mixed'
    if 'unknown host' in s: return 'get-unknown-host'
    return 'other:'+s[:40]
for since in ('2026-08-29','2026-08-30'):
  for excl in (False,True):
    c=collections.Counter()
    for r in rows:
        if r['decision']!='ask' or r['ts']<since: continue
        if excl and r.get('tool_use_id')=='unknown': continue
        c[tpl(r)]+=1
    print(since,'excl_unknown' if excl else 'all',sum(c.values()),dict(c))
c=collections.Counter(); 
for r in rows:
    if r['decision']=='ask' and r.get('tool_use_id')!='unknown': c[tpl(r)]+=1
print('alltime excl unknown',sum(c.values()),dict(c))
c=collections.Counter()
for r in rows:
    if r['decision']=='ask': c[tpl(r)]+=1
print('alltime all',sum(c.values()),dict(c))
