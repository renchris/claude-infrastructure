import json, datetime as dt, os, collections
F=json.load(open('/tmp/kmaxq/files.json'))
def P(s): return dt.datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
for a,T in [('next','2026-09-29T05:30:40Z'),('next4','2026-09-29T05:56:43Z')]:
    T=P(T); c=collections.Counter()
    for f in F:
        if f['acct']==a and f['top'] and any(T-600<t<=T for t in f['ts']):
            ep=None; first=None; n=0
            for line in open(f['path']):
                try:o=json.loads(line)
                except: continue
                if ep is None and o.get('entrypoint'): ep=o.get('entrypoint')
                if first is None and o.get('type')=='user':
                    m=o.get('message',{}).get('content'); first=(m if isinstance(m,str) else json.dumps(m))[:70]
                n+=1
            c[ep]+=1
            print(a, os.path.basename(os.path.dirname(f['path']))[-40:], os.path.basename(f['path'])[:8], ep, n, len(f['ts']), dt.datetime.utcfromtimestamp(f['ts'][0]).strftime('%H:%M:%S'), repr(first))
    print(a, dict(c))
