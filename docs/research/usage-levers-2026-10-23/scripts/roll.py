import pickle,sys,collections,re
sys.path.insert(0,'/tmp/usage-audit')
W=lambda r: r[2]+1.25*r[3]+0.1*r[4]+5*r[5]
def fam(t):
  if not t.startswith('task-notification:'): return None
  s=t[18:]; l=s.lower()
  if s.startswith('Background command'):
    if re.search(r'watch|wake|inbox|arm |re-arm|mail|poll|wait|sleep|idle',l): return 'tn bg-cmd: watcher/wake/poll'
    if re.search(r'land|commit|ship|push|merge|ci ','l' if False else l): return 'tn bg-cmd: land/commit/CI'
    if re.search(r'test|suite|build|run ',l): return 'tn bg-cmd: test/build'
    return 'tn bg-cmd: other'
  if 'goal check-in' in l: return 'tn goal check-in (background work)'
  if 'peer mail' in l or '📬' in s: return 'tn peer mail'
  if s.startswith('Agent') or 'agent "' in l: return 'tn subagent completed'
  if 'workflow' in l[:60]: return 'tn workflow completed'
  if s.startswith('Monitor'): return 'tn monitor'
  if not s: return 'tn (no summary)'
  return 'tn other'
T=0;A=collections.defaultdict(lambda:[0,0.0,0]); ex=collections.defaultdict(collections.Counter)
for a in sys.argv[1:]:
  for r in pickle.load(open(f'/tmp/usage-audit/{a}.v2.pkl','rb'))['reqs']:
    w=W(r); T+=w; f=fam(r[6])
    if f: A[f][0]+=1; A[f][1]+=w; A[f][2]+=r[1]; ex[f][r[6][18:60]]+=1
print('task-notification family | req | weight% | weight B | mean ctx | top summaries')
for f,(n,w,c) in sorted(A.items(), key=lambda x:-x[1][1]):
  print(f'{f} | {n} | {100*w/T:.1f} | {w/1e9:.3f} | {c/n/1e3:.0f}k | {ex[f].most_common(3)}')
print('ALL tn weight%', round(100*sum(v[1] for v in A.values())/T,1))
