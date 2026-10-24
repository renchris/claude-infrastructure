import pickle,sys,collections,re
W=lambda r: r[2]+1.25*r[3]+0.1*r[4]+5*r[5]
def grp(t):
  if t.startswith('task-notification:'):
    s=t[18:]
    if s.startswith('Background command'):
      m=re.match(r'Background command "(.*?)"',s); d=(m.group(1) if m else s)[:40]
      return 'M tn: background command ('+d+')'
    if s.startswith('Agent'): return 'M tn: subagent completed'
    if s.lower().startswith('workflow') or 'workflow' in s.lower()[:40]: return 'M tn: workflow completed'
    if s.startswith('Monitor'): return 'M tn: monitor'
    return 'M tn: other('+s[:30]+')'
  if t.startswith('human:'):
    s=t[6:]
    if s.startswith('handoff'): return 'D handoff-fire successor [locate]'
    if s.startswith('reboot'): return 'D reboot restore [restore]'
    if s.startswith('dispatched'): return 'D dispatched brief (You are...)'
    return 'H operator prompt ('+s+')'
  if t.startswith('stop-hook:'):
    s=t[10:]
    if s.startswith('🔧'): return 'M stop-hook session-continue'
    if s.startswith('Completi'): return 'M stop-hook completion-assert'
    if s.startswith('['): return 'M goal evaluator re-prompt'
    return 'M stop-hook floors/nudges'
  if t=='goal-checkin': return 'M goal evaluator re-prompt'
  if t.startswith('scheduled:'): return 'M scheduled (/loop,cron,ScheduleWakeup)'
  if t=='peer-message': return 'M peer-message (cross-session bus)'
  if t=='teammate-message': return 'M teammate-message (agent teams)'
  if t.startswith(('meta:A session-scoped','meta:short and concise','meta:(Re-invocation')): return 'H operator (/goal set, skill expansion)'
  if t.startswith('meta:'): return 'M other hook meta'
  if t.startswith('unlabeled'): return 'H? unlabeled'
  if t=='subagent:parent-not-in-window': return '? workflow subagents, parent transcript absent'
  return '? '+t
accts=sys.argv[1:]
A=collections.defaultdict(lambda: collections.defaultdict(float)); T=collections.defaultdict(float)
for a in accts:
  for r in pickle.load(open(f'/tmp/usage-audit/{a}.v2.pkl','rb'))['reqs']:
    g=grp(r[6]); w=W(r); v=A[g]
    v['n']+=1; v['w']+=w; v['ctx']+=r[1]; v['main']+=r[7]=='main'; v['w_'+a]+=w
    T['n']+=1; T['w']+=w; T['w_'+a]+=w
print(f"4 accounts, 7d: {int(T['n'])} req, est-weight {T['w']/1e9:.2f}B input-token-equivalents")
print('group | req | req% | weight% | weight B | mean ctx | main-thread req | weight% next/next2/next3/next4')
for g,v in sorted(A.items(), key=lambda x:-x[1]['w'])[:28]:
  print(f"{g} | {int(v['n'])} | {100*v['n']/T['n']:.1f} | {100*v['w']/T['w']:.1f} | {v['w']/1e9:.3f} | {v['ctx']/v['n']/1e3:.0f}k | {int(v['main'])} | "+'/'.join(f"{100*v['w_'+a]/T['w_'+a]:.0f}" for a in accts))
for lab,p in (('M machine (hook/loop/notification/bus)','M'),('D infra-dispatched first prompts','D'),('H operator','H'),('? unknown','?')):
  n=sum(v['n'] for g,v in A.items() if g.startswith(p)); w=sum(v['w'] for g,v in A.items() if g.startswith(p)); c=sum(v['ctx'] for g,v in A.items() if g.startswith(p))
  print(f'{lab}: req {100*n/T["n"]:.1f}%, weight {100*w/T["w"]:.1f}%, mean ctx {c/max(n,1)/1e3:.0f}k')
