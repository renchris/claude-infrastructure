import json,sys,os,re,time,pickle,bisect,hashlib,collections
from datetime import datetime
acct,root=sys.argv[1],sys.argv[2]
NOW=time.time(); CUT=NOW-7*86400
def ts(s):
  try: return datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
  except: return None
INHERIT=('Base directory for this skill','[Image','<local-command-caveat>','# ','<command-message>','> **','<command-name>','<local-command-stdout>','Caveat:')
def classify(d,txt):
  o=d.get('origin'); ok=o.get('kind') if isinstance(o,dict) else None
  t=txt.lstrip(); to=d.get('turnOrigin')
  if '<<autonomous-loop' in t: return 'loop-sentinel(/loop,ScheduleWakeup)'
  if to=='scheduled' or d.get('scheduledTaskId'): return 'scheduled:'+re.sub(r'\s+',' ',t)[:40]
  if ok=='task-notification' or to=='task_notification' or t.startswith('<task-notification>'):
    mm=re.search(r'<summary>(.*?)</summary>',t,re.S); sm=re.sub(r'\s+',' ',mm.group(1)) if mm else ''
    sm=re.sub(r'\(exit code \d+\)|\d+','#',sm)[:70]
    return 'task-notification:'+sm
  if ok=='peer' or to=='peer' or t.startswith('Another Claude session sent'): return 'peer-message'
  if t.startswith('<teammate-message'): return 'teammate-message'
  if t.startswith('Stop hook feedback:'):
    s=re.sub(r'\s+',' ',t[19:].strip())[:22]; return 'stop-hook:'+s
  if t.startswith('Goal check-in'): return 'goal-checkin'
  if d.get('isCompactSummary') or t.startswith('This session is being continued from a previous'): return 'compaction-continuation'
  if t.startswith('<bash-input>') or t.startswith('<bash-stdout>'): return None
  if d.get('isMeta'):
    if t.startswith(INHERIT) or not t: return None
    return 'meta:'+re.sub(r'\s+',' ',t)[:30]
  if t.startswith(('<local-command','<command-name>')): return 'human'
  if ok=='human' or d.get('promptSource') in ('typed','queued'):
    if t.startswith('[locate]'): return 'human:handoff-fire successor [locate]'
    if '[restore]' in t[:40] or t.startswith('[boot-resume]'): return 'human:reboot restore [restore]'
    if t.startswith('You are'): return 'human:dispatched brief (You are...)'
    return 'human:'+str(d.get('promptSource'))
  if not t: return None
  return 'unlabeled:'+re.sub(r'\s+',' ',t)[:30]
reqs={}   # msgid -> [ts, ctx, inp, cc, cr, out, trig, file_kind, sid, agent, skill, cc1h, humanprefix]
sess={}   # sid -> dict(first,last,trig timeline, entrypoint)
subfiles=[]
nfiles=0; nbytes=0; loopother=0; compacts=collections.Counter()
for dp,dn,fn in os.walk(root, followlinks=False):
  for f in fn:
    if not f.endswith('.jsonl'): continue
    p=os.path.join(dp,f)
    try: st=os.stat(p)
    except: continue
    if st.st_mtime<CUT: continue
    nfiles+=1; nbytes+=st.st_size
    is_sub='/subagents/' in p
    rel=p[len(root):].strip('/').split('/')
    sid=rel[1] if is_sub and len(rel)>2 else f[:-6]
    trig='(no-trigger-yet)'; hp=''; first=None; timeline=[]; ep=None; subfirst=None
    with open(p,'rb') as fh:
      for line in fh:
        h=line[:600]
        if b'"type":"assistant"' in line[:2000] or b'"type":"assistant"' in line[-1500:]:
          try: d=json.loads(line)
          except: continue
          if d.get('type')!='assistant': continue
          m=d.get('message') or {}; u=m.get('usage'); mid=m.get('id') or d.get('requestId')
          if not u or not mid: continue
          t=ts(d.get('timestamp',''))
          if t is None: continue
          if first is None: first=t
          if subfirst is None: subfirst=t
          if m.get('model')=='<synthetic>': continue
          if t<CUT: continue
          inp=u.get('input_tokens',0) or 0; cc=u.get('cache_creation_input_tokens',0) or 0; cr=u.get('cache_read_input_tokens',0) or 0; out=u.get('output_tokens',0) or 0
          c1=(u.get('cache_creation') or {}).get('ephemeral_1h_input_tokens',0) or 0
          r=reqs.get(mid)
          if r: r[5]=max(r[5],out); continue
          reqs[mid]=[t,inp+cc+cr,inp,cc,cr,out,trig,'sub' if is_sub else 'main',sid,d.get('attributionAgent'),d.get('attributionSkill'),c1,hp, p if is_sub else None]
          continue
        if b'"type":"user"' in line:
          if b'"tool_use_id"' in line: continue
          try: d=json.loads(line)
          except: continue
          if d.get('type')!='user': continue
          t=ts(d.get('timestamp',''))
          if first is None and t: first=t
          ep=ep or d.get('entrypoint')
          ct=(d.get('message') or {}).get('content')
          if isinstance(ct,list): txt=' '.join(x.get('text','') for x in ct if isinstance(x,dict) and x.get('type')=='text')
          else: txt=ct if isinstance(ct,str) else ''
          if is_sub: continue
          c=classify(d,txt)
          if c is None: continue
          trig=c; hp=re.sub(r'\s+',' ',txt.strip())[:50] if c.startswith('human') or c.startswith('unlabeled') else ''
          if t: timeline.append((t,c))
          continue
        if b'autonomous-loop' in line: loopother+=1
        if b'compact_boundary' in h: compacts['main' if not is_sub else 'sub']+=1
    if is_sub: subfiles.append((sid,subfirst,p))
    else:
      s=sess.setdefault(sid,{'first':None,'tl':[],'ep':None,'files':0})
      s['files']+=1
      if first and (s['first'] is None or first<s['first']): s['first']=first
      s['tl']+=timeline; s['ep']=s['ep'] or ep
# attribute subagent requests to parent's trigger at subagent start
subtrig={}
for sid,sf,p in subfiles:
  s=sess.get(sid); tg='subagent:parent-not-in-window'
  if s and s['tl'] and sf:
    tl=sorted(s['tl']); i=bisect.bisect_right([x[0] for x in tl],sf)-1
    tg=tl[i][1] if i>=0 else '(no-trigger-yet)'
  subtrig[p]=tg
for k,r in reqs.items():
  if r[7]=='sub': r[6]=subtrig.get(r[13],'?')
pickle.dump({'reqs':list(reqs.values()),'sess':{k:{'first':v['first'],'ep':v['ep'],'n':len(v['tl'])} for k,v in sess.items()},'nfiles':nfiles,'nbytes':nbytes,'loopother':loopother,'compacts':dict(compacts)},open(f'/tmp/usage-audit/{acct}.v2.pkl','wb'))
print(acct,'DONE files',nfiles,'bytes',nbytes,'reqs',len(reqs),'loopother',loopother,dict(compacts))
