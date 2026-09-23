import json, heapq, itertools, random, math, sys, collections as C
from collections import deque
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/land.log') if l.startswith('{"v":3')]
w=[r for r in rows if r['ts_start']>='2026-09-16T04:59:00Z' and not (r['exit']==0 and r['rounds']==0)]
g=lambda p,k:(p.get(k) or 0)
CODE=[(g(p,'reconcile_s'),g(p,'tsc_s'),g(p,'suite_s'),g(p,'push_s')) for r in w for p in r['per_round'] if p.get('suite_mode') in ('union','full') and p.get('push_s') is not None]
NCW=[g(p,'reconcile_s')+g(p,'tsc_s')+g(p,'push_s') for r in w for p in r['per_round'] if p.get('suite_mode')=='none' and p.get('push_s') is not None]
NCP=[g(p,'push_s') for r in w for p in r['per_round'] if p.get('suite_mode')=='none' and p.get('push_s') is not None]
RED_GAP=[33,80,84,118,157,168,202,376,411]
class Sim:
    def __init__(s): s.t=0.0; s.q=[]; s.c=itertools.count()
    def at(s,dt,fn): heapq.heappush(s.q,(s.t+dt,next(s.c),fn))
    def run(s,until):
        while s.q and s.q[0][0]<=until:
            t,_,fn=heapq.heappop(s.q); s.t=t; fn()
class Sem:
    def __init__(s,sim,k): s.sim=sim; s.k=k; s.n=0; s.w=deque(); s.busy=0.0; s.t0=None
    def acquire(s,cb):
        if s.n<s.k: s.n+=1; s.sim.at(0,cb)
        else: s.w.append(cb)
    def release(s):
        if s.w: s.sim.at(0,s.w.popleft())
        else: s.n-=1
def run(cfg,N,Tc,hours=200,seed=1):
    rnd=random.Random(seed); sim=Sim(); sem=Sem(sim,1)
    trunk=[None]  # trunk[v] = kind of land that produced version v ('code'/'nc')
    st={'lat':{'code':[],'nc':[]},'rounds':[],'fl':[0,0],'slot':0.0,'exits':C.Counter(),'lands':0,'batch':[]}
    qc=cfg.get('q',0.42); qn=cfg.get('qnc',0.17); pfl=cfg.get('pflake',0.10); preal=cfg.get('preal',0.014)
    WARM=5*3600
    def step(gen,val=None):
        try: cmd=gen.send(val)
        except StopIteration: return
        if cmd[0]=='sleep': sim.at(cmd[1],lambda: step(gen))
        elif cmd[0]=='acq': sem.acquire(lambda: step(gen))
        elif cmd[0]=='rel': sem.release(); sim.at(0,lambda: step(gen))
        elif cmd[0]=='enq': QUEUE.append((cmd[1],sim.t,lambda ok: step(gen,ok))); kick()
    def moved_needs_reverify(v0):
        kinds=trunk[v0+1:]
        if not kinds: return False
        if not cfg.get('carry'): return True
        qq = qc if 'code' in kinds else qn
        return rnd.random()<qq
    def push_ok(v0,kind):
        if len(trunk)-1==v0: trunk.append(kind); return True
        return False
    def cas_session(i):
        yield ('sleep',rnd.expovariate(1/(Tc*60))*rnd.random())
        while True:
            yield ('sleep',rnd.expovariate(1/(Tc*60)))
            code = rnd.random()<cfg.get('fcode',0.40)
            t0=sim.t; nround=0; firstround=True
            while True:  # attempts
                rounds=0; landed=False; end=None; verified_at=None
                while True:
                    rounds+=1; nround+=1
                    if not code:
                        if cfg.get('nc_slot'):
                            yield ('acq',); a1=sim.t
                        v0=len(trunk)-1; yield ('sleep',rnd.choice(NCW))
                        okn=push_ok(v0,'nc')
                        if cfg.get('nc_slot'): st['slot']+=sim.t-a1; yield ('rel',)
                        if okn: landed=True; break
                        if rounds>=cfg.get('rmax',5): end='exh'; break
                        yield ('sleep',rnd.uniform(1,4)); continue
                    rec,tsc,suite,push=rnd.choice(CODE)
                    if not cfg.get('hook',True): push=rnd.choice(NCP)
                    if cfg.get('keep_slot') and rounds>1 and verified_at is not None:
                        # still holding the slot from the lost round: rebase, carry or re-verify in place
                        if moved_needs_reverify(verified_at):
                            v0=len(trunk)-1; yield ('sleep',rec+tsc+suite)
                            if rnd.random()<pfl or rnd.random()<preal:
                                st['slot']+=sim.t-a0; yield ('rel',); end='red'; break
                        else:
                            v0=len(trunk)-1; yield ('sleep',rec)
                        verified_at=v0
                        yield ('sleep',push)
                        ok=push_ok(v0,'code')
                        if ok or rounds>=cfg.get('rmax',5):
                            st['slot']+=sim.t-a0; yield ('rel',)
                        if ok: landed=True; break
                        if rounds>=cfg.get('rmax',5): end='exh'; break
                        yield ('sleep',rnd.uniform(1,4)); continue
                    held=False
                    # can we carry the previous verdict across the rebase?
                    carry = verified_at is not None and not moved_needs_reverify(verified_at)
                    if carry:
                        v0=len(trunk)-1; yield ('sleep',rec)
                    elif cfg.get('admit_first'):
                        if cfg.get('tsc_outside'):
                            vpre=len(trunk)-1; yield ('sleep',rec+tsc)
                            yield ('acq',); held=True; a0=sim.t
                            v0=len(trunk)-1
                            if v0!=vpre and moved_needs_reverify(vpre): yield ('sleep',rec+tsc)
                            else: yield ('sleep',rec)
                        else:
                            yield ('acq',); held=True; a0=sim.t
                            v0=len(trunk)-1; yield ('sleep',rec+tsc)
                        yield ('sleep',suite)
                        red = rnd.random()<pfl or rnd.random()<preal
                        if red or not cfg.get('hold_push'):
                            st['slot']+=sim.t-a0; yield ('rel',); held=False
                        if red: end='red'; break
                        verified_at=v0
                    else:
                        v0=len(trunk)-1; yield ('sleep',rec+tsc)
                        yield ('acq',); a0=sim.t; yield ('sleep',suite); st['slot']+=sim.t-a0; yield ('rel',)
                        if rnd.random()<pfl or rnd.random()<preal: end='red'; break
                        verified_at=v0
                    if cfg.get('hook',True) and rnd.random()<cfg.get('phook',0.10):
                        yield ('sleep',push); end='hookred'; break
                    yield ('sleep',push)
                    ok=push_ok(v0,'code')
                    if held and (ok or not cfg.get('keep_slot')): st['slot']+=sim.t-a0; yield ('rel',)
                    if firstround: st['fl'][0 if ok else 1]+=1; firstround=False
                    if ok: landed=True; break
                    if not cfg.get('carry'): verified_at=None
                    if cfg.get('reflock_terminal',True) and rnd.random()<0.24: end='reflock'; break
                    if rounds>=cfg.get('rmax',5): end='exh'; break
                    yield ('sleep',rnd.uniform(1,4))
                if landed: break
                st['exits'][end]+=1
                gap={'red':rnd.choice(RED_GAP),'hookred':rnd.choice([30,30,49,91,298]),'reflock':rnd.choice([10,18,21,34,44]),'exh':31}[end]
                yield ('sleep',gap)
            if sim.t>WARM:
                st['lat']['code' if code else 'nc'].append(sim.t-t0); st['lands']+=1
                if code: st['rounds'].append(nround)
    # ---------------- merge queue (one lander, batch, verify once) ----------------
    QUEUE=[]; busy=[False]
    def kick():
        if not busy[0] and QUEUE: busy[0]=True; sim.at(0,lambda: step(lander()))
    def lander():
        while QUEUE:
            batch=QUEUE[:cfg.get('bmax',10)]; del QUEUE[:len(batch)]
            ncode=sum(1 for (k,_,_) in batch if k)
            if sim.t>WARM: st['batch'].append(len(batch))
            if ncode:
                rec,tsc,suite,_=rnd.choice(CODE); a0=sim.t
                yield ('sleep',rec*len(batch)+tsc+suite+rnd.choice(NCP)); st['slot']+=sim.t-a0
                red = rnd.random()<pfl or any(rnd.random()<preal for _ in range(ncode))
            else:
                yield ('sleep',rnd.choice(NCW)); red=False
            if red:
                # invariant 6: a red is never re-rolled -> every rider is ejected and must re-submit
                for _,_,cb in batch: sim.at(0,lambda cb=cb: cb(False))
            else:
                trunk.append('code' if ncode else 'nc')
                for _,_,cb in batch: sim.at(0,lambda cb=cb: cb(True))
        busy[0]=False
    def q_session(i):
        yield ('sleep',rnd.expovariate(1/(Tc*60))*rnd.random())
        while True:
            yield ('sleep',rnd.expovariate(1/(Tc*60)))
            code = rnd.random()<cfg.get('fcode',0.40); t0=sim.t
            while True:
                ok = yield ('enq',code)
                if ok: break
                yield ('sleep',rnd.choice(RED_GAP))
            if sim.t>WARM: st['lat']['code' if code else 'nc'].append(sim.t-t0); st['lands']+=1
    for i in range(N): step((q_session if cfg.get('queue') else cas_session)(i))
    sim.run(hours*3600)
    return st
def pct(a,p):
    if not a: return float('nan')
    a=sorted(a);k=(len(a)-1)*p;f=int(k);c=min(f+1,len(a)-1);return a[f]+(a[c]-a[f])*(k-f)
BASE=dict(hook=False,reflock_terminal=False,rmax=10)
CFG={
 'C0 today':dict(hook=True,reflock_terminal=True),
 'C1 token-honoured':dict(hook=False,reflock_terminal=True),
 'C2 +reflock-race,rmax10':dict(BASE),
 'C3 +admit-then-fetch':dict(BASE,admit_first=True),
 'C4 +carry(q.42)':dict(BASE,admit_first=True,carry=True,q=0.42),
 'C4w +carry(q.72)':dict(BASE,admit_first=True,carry=True,q=0.72),
 'C6 +tsc-out,slot-thru-push q.42':dict(BASE,admit_first=True,carry=True,q=0.42,tsc_outside=True,hold_push=True),
 'C6w same q.72':dict(BASE,admit_first=True,carry=True,q=0.72,tsc_outside=True,hold_push=True),
 'C7 keep-slot q.42':dict(BASE,admit_first=True,carry=True,q=0.42,tsc_outside=True,hold_push=True,keep_slot=True),
 'C7w keep-slot q.72':dict(BASE,admit_first=True,carry=True,q=0.72,tsc_outside=True,hold_push=True,keep_slot=True),
 'C8 full-mutex q.42':dict(BASE,admit_first=True,carry=True,q=0.42,tsc_outside=True,hold_push=True,keep_slot=True,nc_slot=True),
 'Q queue(inv6)':dict(queue=True),
}
if __name__=='__main__':
    Ns=[int(x) for x in sys.argv[1].split(',')]; Tc=float(sys.argv[2]); names=sys.argv[3].split('|') if len(sys.argv)>3 and sys.argv[3] else list(CFG)
    pf=float(sys.argv[4]) if len(sys.argv)>4 else 0.10
    for name in names:
        for N in Ns:
            L=[];NL=[];R=[];fl=[0,0];slot=0;hrs=0;ex=C.Counter();lands=0;B=[]
            for seed in (1,2,3):
                st=run(dict(CFG[name],pflake=pf),N,Tc,hours=200,seed=seed)
                L+=st['lat']['code'];NL+=st['lat']['nc'];R+=st['rounds'];fl[0]+=st['fl'][0];fl[1]+=st['fl'][1];slot+=st['slot'];hrs+=200-5;ex+=st['exits'];lands+=st['lands'];B+=st['batch']
            print('%-32s N=%2d Tc=%2.0f pfl=%.2f lands/h=%5.1f | CODE p50=%5.0f p90=%5.0f p95=%5.0f | NONCODE p50=%4.0f p90=%4.0f | mean code=%5.0f nc=%4.0f blend=%4.0f | rounds=%.2f P1loss=%.2f slot=%.2f exits/land=%.2f %s'%(
                name,N,Tc,pf,lands/hrs,pct(L,.5),pct(L,.9),pct(L,.95),pct(NL,.5),pct(NL,.9),sum(L)/max(1,len(L)),sum(NL)/max(1,len(NL)),(sum(L)+sum(NL))/max(1,len(L)+len(NL)),sum(R)/max(1,len(R)),fl[1]/max(1,sum(fl)),slot/((hrs+15)*3600),sum(ex.values())/max(1,lands),('batch mean=%.2f p90=%.0f'%(sum(B)/len(B),pct(B,.9)) if B else '')))
            sys.stdout.flush()
