#!/usr/bin/env python3
# Tabulate subagent busts by what preceded them (measured tool runtime) and the gaps while a bg Bash is live.
import json, collections
S=[json.loads(l) for l in open('/tmp/usage-audit/r2/cache-rebuilds/subwait.jsonl')]
B=[s for s in S if s['bust']]
M=lambda x:f"{x/1e6:.1f}M"
tot=sum(s['cc'] for s in B)
print(f"subagent busts n={len(B)} cc={M(tot)} (all gaps)")
def rtb(s):
    if s['rt'] is None: return 'rt n/a'
    return 'ran>270s' if s['rt']>270 else 'ran<=270s'
c=collections.Counter(); cc=collections.Counter()
for s in B:
    k=(s['kind'], rtb(s)); c[k]+=1; cc[k]+=s['cc']
for k in sorted(c, key=lambda k:-cc[k]): print(f"  {k[0]:36s} {k[1]:10s} n={c[k]:4d} cc={M(cc[k]):>6s} ({cc[k]/tot:.0%})")
fg270=[s for s in B if s['kind'].startswith('fg Bash') and s['rt'] and s['rt']>270]
print(f"busts after a foreground Bash that RAN >270s: n={len(fg270)} cc={M(sum(s['cc'] for s in fg270))} = {sum(s['cc'] for s in fg270)/tot:.1%} of subagent bust tokens; of those with timeout param >270s: {sum('timeout>270s' in s['kind'] for s in fg270)}")
g5=[s for s in B if 300<s['gap']<=3600]
f5=[s for s in g5 if s['kind'].startswith('fg Bash') and s['rt'] and s['rt']>270]
print(f"  within the 5-60m slice: {len(f5)}/{len(g5)} busts, {M(sum(s['cc'] for s in f5))}/{M(sum(s['cc'] for s in g5))}")
# gap vs runtime: is the gap the tool?
import statistics as st
d=[s['gap']-s['rt'] for s in fg270]
print('  gap minus tool runtime (s): median',round(st.median(d)),'p90',round(sorted(d)[int(.9*len(d))]))
rts=sorted(s['rt'] for s in fg270); print('  tool runtime (min): p10',round(rts[len(rts)//10]/60,1),'median',round(st.median(rts)/60,1),'p90',round(rts[int(.9*len(rts))]/60,1),'max',round(rts[-1]/60,1))
# runtime>600 with timeout param? (Bash max is 600 s)
print('  runtime > 610 s:', sum(1 for s in fg270 if s['rt']>610))
# part 2
J=json.load(open('/tmp/usage-audit/r2/cache-rebuilds/subwait_bg.json'))
gp=J['gaps']
print(f"\nREQUEST GAPS WHILE A SUBAGENT'S OWN BACKGROUND BASH IS LIVE: files={J['nfiles']} pairs={len(gp)}")
c=collections.Counter(); bc=collections.Counter(); bcc=collections.Counter()
for g,b,k,ccv in gp:
    kk=('<=270s' if g<=270 else '270-300s' if g<=300 else '>5m', k)
    c[kk]+=1; bc[kk]+=b; bcc[kk]+=ccv if b else 0
for k in sorted(c, key=lambda k:(k[0],-c[k]))[:40]: print(f"  gap {k[0]:9s} after {k[1]:26s} n={c[k]:6d} busts={bc[k]:4d} ({bc[k]/c[k]:.1%}) bust_cc={M(bcc[k])}")
n5=sum(1 for g,b,k,_ in gp if g>300); print(f"  share of waiting gaps >5m: {n5}/{len(gp)} = {n5/len(gp):.2%}")
