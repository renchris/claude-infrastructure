#!/usr/bin/env python3
# Survey record kinds present in the 191 main 1-2h bust transcripts (goal markers, wake markers).
import json, collections, re
R=[json.loads(l) for l in open('/tmp/usage-audit/r2/cache-rebuilds/gaps.jsonl')]
sel=[r for r in R if not r['sub'] and r['bust'] and 3600<r['gap']<=7200]
files=sorted({r['root']+'/'+r['rel'] for r in sel})
att=collections.Counter(); sysc=collections.Counter(); goalcmd=collections.Counter(); ustr=collections.Counter()
for p in files:
    for line in open(p,errors='replace'):
        if '"goal' not in line and 'attachment' not in line and '"system"' not in line and '/goal' not in line: continue
        try: d=json.loads(line)
        except: continue
        t=d.get('type')
        if t=='attachment': att[(d.get('attachment') or {}).get('type')]+=1
        elif t=='system':
            sysc[(d.get('subtype'), str(d.get('content'))[:40] if d.get('subtype')=='informational' else '')]+=1
        elif t=='user':
            c=(d.get('message') or {}).get('content')
            s=c if isinstance(c,str) else ' '.join(x.get('text','') for x in c if isinstance(x,dict) and x.get('type')=='text') if isinstance(c,list) else ''
            m=re.search(r'<command-name>(/goal[^<]*)</command-name>',s)
            if m: goalcmd[m.group(1)]+=1
            if '/goal' in s[:200]: ustr[s[:80]]+=1
print('files',len(files))
print('ATTACH',att.most_common(60))
print('SYSTEM',[x for x in sysc.most_common(40)])
print('GOALCMD',goalcmd.most_common(10))
print('USTR',ustr.most_common(10))
