import json,sys,glob,os
from datetime import datetime
def te(s): return datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
gaps={'b287d693':'2026-10-24T16:37:34Z','9e80ebc5':'2026-10-24T16:58:28Z','db25f0e6':'2026-10-24T16:56:41Z','fba32d7a':'2026-10-24T16:44:11Z','79076bcf':'2026-10-24T17:03:23Z'}
roots=[os.path.expanduser('~/.claude/projects'),os.path.expanduser('~/.claude-secondary/projects'),os.path.expanduser('~/.claude-tertiary/projects'),os.path.expanduser('~/.claude-quaternary/projects')]
for s,g in gaps.items():
    fs=[f for r in roots for f in glob.glob(r+'/*/'+s+'*.jsonl')]
    g0=te(g)
    for f in fs:
        print('==',s,f.split('/')[-2][-40:])
        for line in open(f,errors='ignore'):
            try: r=json.loads(line)
            except Exception: continue
            t=r.get('timestamp')
            if not isinstance(t,str): 
                continue
            x=te(t)
            if g0-30<=x<=g0+7000:
                typ=r.get('type'); sub=r.get('subtype') or (r.get('attachment') or {}).get('type') or ''
                u=(r.get('message') or {}).get('usage') or {}
                extra=''
                if typ=='user':
                    c=(r.get('message') or {}).get('content')
                    extra=(c if isinstance(c,str) else json.dumps(c))[:70]
                if u: extra='cw=%s cr=%s'%(u.get('cache_creation_input_tokens'),u.get('cache_read_input_tokens'))
                print('  %+7.0f %-10s %-22s %s'%(x-g0,typ,sub,extra.replace('\n',' ')))
                if x>g0+300 and typ in('user','assistant'): break
