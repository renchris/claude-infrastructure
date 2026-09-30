"""Synthesis stop-rule check (2026-09-30). Extends carried_seeds.py (same detection model) with the three
things the judges said the earlier sims lacked:
  1. seeds that can themselves be universal-blind (u_seed), i.e. realistic seeds;
  2. false-positive material findings that survive verification (LLM action bias), which reset dryness
     and whose 'fixes' also inject fix-born holes;
  3. a HARD cap: R_max = min(round-1 forecast + 2, R_ABS), after which the verdict is BOUNDED.
Stop rule under test: first round r>=2 ending K consecutive dry rounds (dry = 0 verified material items,
real or false) -> CERTIFIED; else r == R_max -> BOUNDED. The residual is STATED, never gated:
  mu_hat = F*pi/(1-pi) per seed cohort (original cohort planted at freeze 1; one fix cohort per round,
  size ceil(0.5*fixes), carried), n_pred95 = Poisson 95% quantile at the Clopper-Pearson upper mu.
Coverage is reported against detectable-left AND total-left (incl. universal-blind)."""
import math, sys, numpy as np
from math import comb
rng = np.random.default_rng(7)
sig = lambda x: 1/(1+np.exp(-x))
FAMS = np.array([0,0,1,1,2,2,3,3]); T = 8; R_ABS = 10

def cp_upper(k, n, a=0.05):
    if n == 0: return 1.0
    if k >= n: return 1.0
    lo, hi = 0.0, 1.0
    for _ in range(50):
        mid = (lo+hi)/2
        cdf = sum(comb(n,j)*mid**j*(1-mid)**(n-j) for j in range(0,k+1))
        (lo, hi) = (mid, hi) if cdf > a else (lo, mid)
    return hi
def pois_q95(mu):
    if not np.isfinite(mu): return float('inf')
    c, p, n = 0.0, math.exp(-mu), 0
    while True:
        c += p
        if c >= 0.95: return n
        n += 1; p *= mu/n
def holes(n, u, tag):
    return dict(d=rng.normal(0,1.2,n), f=rng.normal(0,1.5,(4,n)), ub=rng.random(n)<u, tag=np.full(n,tag))
def cat(A,B): return {k:np.concatenate([A[k],B[k]],axis=-1) for k in A}
def sub(A,m): return {k:(v[:,m] if v.ndim==2 else v[m]) for k,v in A.items()}
def detect(H):
    n = len(H['d'])
    if n == 0: return np.zeros((T,0),bool)
    P = sig(-1.0 + H['d'][None,:] + H['f'][FAMS,:]); P[:,H['ub']] = 1e-4
    return rng.random(P.shape) < P
def chao2(X):
    k = X.sum(0); S = int((k>0).sum()); Q1 = int((k==1).sum()); Q2 = int((k==2).sum())
    return S + ((T-1)/T)*Q1*(Q1-1)/(2*(Q2+1))

# tags: 0 original real, 1 fix-born real, 2 original-cohort seed, 3 fix-cohort seed
def one(N0, u, u_seed, b, K, s, fp_rate):
    H = cat(holes(N0,u,0), holes(s,u_seed,2)); fix_seeds_planted = 0
    F0 = F1 = 0; r = 0; dry = 0; Rmax = R_ABS; pending_fix_seeds = 0; verdict = None
    while True:
        r += 1
        if pending_fix_seeds:
            H = cat(H, holes(pending_fix_seeds, u_seed, 3)); fix_seeds_planted += pending_fix_seeds; pending_fix_seeds = 0
        X = detect(H); found = X.any(0)
        realf = found & (H['tag'] < 2)
        F0 += int((found & (H['tag']==0)).sum()); F1 += int((found & (H['tag']==1)).sum())
        fp = rng.poisson(fp_rate)                     # false material items that passed verification
        if r == 1:                                    # forecast from round 1 (Chao2 on real finds, seed recall)
            Nhat = max(chao2(X[:, H['tag']<2]) + fp, 1.0)
            R1 = found[H['tag']==2].mean(); q = (1-R1) + 0.1*R1
            fc = math.ceil(math.log(Nhat/0.5)/math.log(1/max(q,1e-3))) + K if q < 1 else R_ABS
            Rmax = min(fc + 2, R_ABS)
        items = int(realf.sum()) + fp
        H = sub(H, ~found)
        if items == 0:
            dry += 1
            if dry >= K and r >= 2: verdict = 'CERTIFIED'; break
        else:
            dry = 0
            inj = int((rng.random(items) < b).sum())
            if inj: H = cat(H, holes(inj,u,1))
            pending_fix_seeds = math.ceil(0.5*items)
        if r >= Rmax: verdict = 'BOUNDED'; break
    k0 = int((H['tag']==2).sum()); k1 = int((H['tag']==3).sum())
    def est(F, k, n):
        if n == 0: return 0.0, 0.0
        pt = (k+0.5)/(n+1); pu = cp_upper(k, n)
        mu = F*pt/(1-pt); muu = F*pu/(1-pu) if pu < 1 else float('inf')
        return mu, muu
    m0, mu0 = est(F0, k0, s); m1, mu1 = est(F1, k1, fix_seeds_planted)
    mu_hat = m0 + m1; n95 = pois_q95(mu0 + mu1)
    det_left = int(((H['tag']<2)&(~H['ub'])).sum()); tot_left = int((H['tag']<2).sum())
    return dict(r=r, v=verdict, mu=mu_hat, n95=n95, det=det_left, tot=tot_left)

def run(label, reps=800, **kw):
    R = [one(**kw) for _ in range(reps)]; a = lambda k: np.array([x[k] for x in R], dtype=float)
    r, det, tot, n95, mu = a('r'), a('det'), a('tot'), a('n95'), a('mu')
    bounded = np.mean([x['v']=='BOUNDED' for x in R])
    print(f"{label}: rounds p50={np.median(r):.0f} p90={np.percentile(r,90):.0f} max={r.max():.0f} | BOUNDED={bounded:.2f}"
          f" | det-left mean={det.mean():.2f} P(>=1)={np.mean(det>=1):.2f} | total-left mean={tot.mean():.2f} P(>=1)={np.mean(tot>=1):.2f}"
          f" | stated mu median={np.median(mu):.2f} n95 median={np.median(n95):.0f}"
          f" | cover(det<=n95)={np.mean(det<=n95):.3f} cover(tot<=n95)={np.mean(tot<=n95):.3f}")

if __name__ == '__main__':
    print("stop = K consecutive dry (0 verified material, real or false) with r>=2; hard cap min(forecast+2, 10) -> BOUNDED")
    for K in (2, 3):
        for (N0,u_seed,fp,b) in ((60,0.0,0.0,0.1),(60,0.05,0.0,0.1),(60,0.05,0.25,0.1),(60,0.05,0.5,0.1),(60,0.05,0.25,0.3),(30,0.05,0.25,0.1),(150,0.05,0.25,0.1)):
            run(f"K={K} N0={N0} u_seed={u_seed} fp/round={fp} b={b}", N0=N0, u=0.05, u_seed=u_seed, b=b, K=K, s=60, fp_rate=fp)
