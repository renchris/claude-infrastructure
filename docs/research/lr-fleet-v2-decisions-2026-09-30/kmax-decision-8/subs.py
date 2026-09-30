import json, datetime as dt, os, collections
F=json.load(open('/tmp/kmaxq/files.json'))
def P(s): return dt.datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
for a,T in [('next','2026-09-29T04:26:04Z'),('next4','2026-09-29T04:26:04Z'),('next','2026-09-29T05:12:03Z'),('next','2026-09-29T05:18:21Z'),('next','2026-09-29T06:03:54Z'),('next','2026-09-29T05:44:06Z')]:
    t0=P(T); c=collections.Counter(); kinds=collections.Counter()
    for f in F:
        if f['acct']==a and not f['top'] and any(t0-600<t<=t0 for t in f['ts']):
            p=f['path']; parts=p.split('/')
            i=parts.index('projects'); slug=parts[i+1]; sid=parts[i+2][:8]
            kind='workflow' if '/workflows/' in p else 'agent'
            c[(slug[-30:],sid)]+=1; kinds[kind]+=1
    print(T[11:19],a,dict(kinds),c.most_common(6))
