import json,re,sys,collections
sys.path.insert(0,'/tmp/conv-tests/regate-briefs/cg')
import curl_gate_da7 as g
LO,HI='2026-09-25T02:22:56Z','2026-09-29T00:00:00Z'
n=[d for d in (json.loads(l) for l in open('/Users/chrisren/.reso/curl-audit.jsonl')) if LO<=d.get('ts','')<HI and d.get('decision')=='ask' and d['reason'].startswith('No URL parsed')]
k=collections.Counter()
for d in n:
    c=d['cmd_redacted']; m=re.search(r'\bfor\s+(\w+)\s+in\s+([^;]*?);\s*do',c)
    if not (m and not re.search(r'[\$`*?]',m.group(2))): continue
    u=g._UNSEEN_BINDERS.search(c)
    b=g.shell_bindings(c)
    k[('unseen-binder:'+u.group(0).strip()) if u else ('bound:'+','.join(sorted(b)) if b else 'no-binding')]+=1
print(k)
