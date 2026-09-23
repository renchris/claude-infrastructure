import json, heapq, itertools, random, math, sys, collections as C
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/land.log') if l.startswith('{"v":3')]
w=[r for r in rows if r['ts_start']>='2026-09-16T04:59:00Z' and not (r['exit']==0 and r['rounds']==0)]
g=lambda p,k:(p.get(k) or 0)
CODE=[(g(p,'reconcile_s'),g(p,'tsc_s'),g(p,'suite_s'),g(p,'push_s')) for r in w for p in r['per_round'] if p.get('suite_mode') in ('union','full') and p.get('push_s') is not None]
NCW=[g(p,'reconcile_s')+g(p,'tsc_s')+g(p,'push_s') for r in w for p in r['per_round'] if p.get('suite_mode')=='none' and p.get('push_s') is not None]
NCP=[g(p,'push_s') for r in w for p in r['per_round'] if p.get('suite_mode')=='none' and p.get('push_s') is not None]
RED_GAP=[33,80,84,118,157,168,202,376,411]   # measured gap after statics-red before re-attempt
class Sim:
    def __init__(s): s.t=0.0; s.q=[]; s.c=itertools.count()
    def at(s,dt,fn): heapq.heappush(s.q,(s.t+dt,next(s.c),fn))
    def run(s,until):
        while s.q and s.q[0][0]<=until:
            t,_,fn=heapq.heappop(s.q); s.t=t; fn()
class Sem:
    def __init__(s,sim,k): s.sim=sim; s.k=k; s.n=0; s.w=collections_deque()
    def acquire(s,cb):
        if s.n<s.k: s.n+=1; s.sim.at(0,cb)
        else: s.w.append(cb)
    def release(s):
        if s.w: s.sim.at(0,s.w.popleft())
        else: s.n-=1
from collections import deque as collections_deque
def run(cfg,N,Tc,hours=300,seed=1):
    rnd=random.Random(seed); sim=Sim(); sem=Sem(sim,1)
    st={'ver':0,'lat':{'code':[],'nc':[]},'rounds':[],'firstloss':[0,0],'suite_busy':0.0,'exits':C.Counter(),'lands':0}
    q=cfg.get('q',0.42); pfl=cfg.get('pflake',0.10); preal=cfg.get('preal',0.014)
    def step(gen,val=None):
        try: cmd=gen.send(val)
        except StopIteration: return
        if cmd[0]=='sleep': sim.at(cmd[1],lambda: step(gen))
        elif cmd[0]=='acq': sem.acquire(lambda: step(gen))
        elif cmd[0]=='rel': sem.release(); sim.at(0,lambda: step(gen))
        elif cmd[0]=='enq': QUEUE.append((cmd[1],lambda: step(gen))); kick()
    # ---------------- CAS session ----------------
    def cas_session(i):
        yield ('sleep',rnd.expovariate(1/(Tc*60))*rnd.random())  # desync start
        while True:
            yield ('sleep',rnd.expovariate(1/(Tc*60)))
            code = rnd.random()<cfg.get('fcode',0.40)
            t0=sim.t; nround=0; first=True
            while True:  # attempts
                rounds=0; landed=False; attempt_end=None
                while True:  # rounds
                    rounds+=1; nround+=1
                    cheap = cfg.get('carry') and rounds>1 and rnd.random()>q
                    if not code:
                        v0=st['ver']; yield ('sleep',rnd.choice(NCW))
                    else:
                        rec,tsc,suite,push=rnd.choice(CODE)
                        if not cfg.get('hook',True): push=rnd.choice(NCP)
                        if cfg.get('admit_first') and not cheap:
                            yield ('acq',)
                            v0=st['ver']; yield ('sleep',rec+tsc)
                            ts=sim.t; yield ('sleep',suite); st['suite_busy']+=suite
                            if cfg.get('hold_push'):
                                red = rnd.random()<pfl or rnd.random()<preal
                                if red:
                                    yield ('rel',); attempt_end='red'; break
                                yield ('sleep',push)
                                ok = st['ver']==v0
                                if ok: st['ver']+=1
                                yield ('rel',)
                                if ok: landed=True; break
                                # loss while holding (only to non-code/others)
                                if first: st['firstloss'][1]+=1
                                first=False
                                if rounds>=cfg.get('rmax',5): attempt_end='exh'; break
                                yield ('sleep',rnd.uniform(1,4)); continue
                            yield ('rel',)
                        else:
                            v0=st['ver']
                            if cheap:
                                yield ('sleep',rec)
                            else:
                                yield ('sleep',rec+tsc)
                                yield ('acq',); yield ('sleep',suite); st['suite_busy']+=suite; yield ('rel',)
                        if not cheap:
                            if rnd.random()<pfl or rnd.random()<preal: attempt_end='red'; break
                        if cfg.get('hook',True) and rnd.random()<cfg.get('phook',0.10):
                            yield ('sleep',push); attempt_end='hookred'; break
                        yield ('sleep',push)
                    if st['ver']==v0:
                        st['ver']+=1; landed=True
                        if code and first: st['firstloss'][0]+=1
                        break
                    if code and first: st['firstloss'][1]+=1
                    first=False
                    if cfg.get('reflock_terminal',True) and rnd.random()<0.24: attempt_end='reflock'; break
                    if rounds>=cfg.get('rmax',5): attempt_end='exh'; break
                    yield ('sleep',rnd.uniform(1,4))
                if landed: break
                st['exits'][attempt_end]+=1
                gap={'red':rnd.choice(RED_GAP),'hookred':rnd.choice([30,30,49,91,298]),'reflock':rnd.choice([10,18,21,34,44]),'exh':31}[attempt_end]
                yield ('sleep',gap)
            if sim.t>WARM:
                st['lat']['code' if code else 'nc'].append(sim.t-t0); st['rounds'].append(nround) if code else None; st['lands']+=1
    # ---------------- merge queue ----------------
    QUEUE=[]; busy=[False]
    def kick():
        if not busy[0] and QUEUE: busy[0]=True; sim.at(0,lambda: step(lander()))
    def lander():
        while QUEUE:
            batch=QUEUE[:cfg.get('bmax',10)]; del QUEUE[:len(batch)]
            ncode=sum(1 for (k,_) in batch if k)
            while True:
                if ncode:
                    rec,tsc,suite,_=rnd.choice(CODE); d=rec+tsc+suite+rnd.choice(NCP); st['suite_busy']+=suite
                else: d=rnd.choice(NCW)
                yield ('sleep',d)
                if ncode and rnd.random()<pfl: continue      # flake: re-verify whole batch once more
                if ncode and any(rnd.random()<preal for _ in range(ncode)):
                    # bisect: ~ceil(log2(B))+1 more verifies, then land the rest (culprit ejected & re-enqueued later: approximated as landing)
                    for _ in range(max(1,math.ceil(math.log2(max(2,len(batch)))))):
                        rec,tsc,suite,_=rnd.choice(CODE); yield ('sleep',rec+tsc+suite+rnd.choice(NCP)); st['suite_busy']+=suite
                break
            st['ver']+=1
            for _,cb in batch: sim.at(0,cb)
        busy[0]=False
    def q_session(i):
        yield ('sleep',rnd.expovariate(1/(Tc*60))*rnd.random())
        while True:
            yield ('sleep',rnd.expovariate(1/(Tc*60)))
            code = rnd.random()<cfg.get('fcode',0.40); t0=sim.t
            yield ('enq',code)
            if sim.t>WARM: st['lat']['code' if code else 'nc'].append(sim.t-t0); st['lands']+=1
    WARM=3600*5
    for i in range(N): step((q_session if cfg.get('queue') else cas_session)(i))
    sim.run(hours*3600)
    return st
def pct(a,p):
    if not a: return float('nan')
    a=sorted(a);k=(len(a)-1)*p;f=int(k);c=min(f+1,len(a)-1);return a[f]+(a[c]-a[f])*(k-f)
CFG={
 'C0 today':dict(hook=True,reflock_terminal=True),
 'C1 +token honoured':dict(hook=False,reflock_terminal=True),
 'C2 +reflock=race':dict(hook=False,reflock_terminal=False,rmax=10),
 'C3 +admit-then-fetch':dict(hook=False,reflock_terminal=False,rmax=10,admit_first=True),
 'C4 +carry q=.42':dict(hook=False,reflock_terminal=False,rmax=10,admit_first=True,carry=True,q=0.42),
 'C4 +carry q=.72':dict(hook=False,reflock_terminal=False,rmax=10,admit_first=True,carry=True,q=0.72),
 'C5 slot-thru-push':dict(hook=False,reflock_terminal=False,rmax=10,admit_first=True,hold_push=True,carry=True,q=0.42),
 'Q queue B<=10':dict(queue=True),
}
if __name__=='__main__':
    Ns=[int(x) for x in sys.argv[1].split(',')]; Tc=float(sys.argv[2]); names=sys.argv[3].split('|') if len(sys.argv)>3 else list(CFG)
    for name in names:
        for N in Ns:
            L=[];R=[];fl=[0,0];busy=0;hrs=0;ex=C.Counter();lands=0
            for seed in (1,2,3):
                st=run(CFG[name],N,Tc,hours=200,seed=seed)
                L+=st['lat']['code'];R+=st['rounds'];fl[0]+=st['firstloss'][0];fl[1]+=st['firstloss'][1];busy+=st['suite_busy'];hrs+=200;ex+=st['exits'];lands+=st['lands']
            print('%-22s N=%2d Tc=%2.0f lands/h=%5.1f | code lat p50=%5.0f p90=%5.0f p95=%5.0f mean=%5.0f | rounds=%.2f P(1st loss)=%.2f | suite-slot util=%.2f | exits/land=%.2f'%(
                name,N,Tc,lands/hrs,pct(L,.5),pct(L,.9),pct(L,.95),sum(L)/max(1,len(L)),sum(R)/max(1,len(R)),fl[1]/max(1,sum(fl)),busy/(hrs*3600),sum(ex.values())/max(1,lands)))
