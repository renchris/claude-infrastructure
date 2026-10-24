import pickle,collections,bisect,re,sys
sys.path=[p for p in sys.path if p]  # -I already isolates
exec(open('/tmp/usage-audit/skeptic-lp/an.py').read().split('G = collections')[0])  # reuse WL/WM/tcls definitions only
agree=collections.Counter(); by_launch=collections.Counter(); by_ts=collections.Counter(); tot=0
for a in ['next','next2','next3','next4']:
  D=pickle.load(open(f'/tmp/usage-audit/skeptic-lp/{a}.pkl','rb')); files=D['files']
  bys=collections.defaultdict(list)
  for r in D['reqs']: bys[r[7]].append(r)
  for s,L in bys.items():
    tl=sorted(D['tl'].get(s,[])); tts=[x[0] for x in tl]
    cls_at=lambda t: (tcls(tl[i][1],tl[i][2]) if (i:=bisect.bisect_right(tts,t)-1)>=0 else '(no trigger)')
    launches=sorted((r[0],t) for r in L if r[6]=='main' for t in r[10] if t in ('Agent','Task','Workflow'))
    lts=[x[0] for x in launches]
    sf=collections.defaultdict(list)
    for r in L:
      if r[6]!='main': sf[r[8]].append(r)
    for fi,rows in sf.items():
      t0=min(x[0] for x in rows); w=sum(WL(x) for x in rows); tot+=w
      ts_cls=cls_at(t0)
      j=bisect.bisect_right(lts,t0)-1
      la_cls=cls_at(launches[j][0]) if j>=0 else '(launcher not in window)'
      by_ts[ts_cls]+=w; by_launch[la_cls]+=w
      agree['same' if ts_cls==la_cls else 'differ']+=w
print('subagent list-weight whose timestamp-attributed trigger equals the trigger of the turn holding the most recent Agent/Workflow launch: %.0f%%'%(100*agree['same']/tot))
print('class | share of subagent weight: timestamp-attributed (their method) | launcher-turn attributed')
for k in sorted(set(by_ts)|set(by_launch),key=lambda k:-(by_ts[k]+by_launch[k]))[:12]:
  print('%s | %.1f%% | %.1f%%'%(k,100*by_ts[k]/tot,100*by_launch[k]/tot))
