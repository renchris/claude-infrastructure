"""attack_sim.py - the SYNTHESIS's own cert_sim model with four LLM-behaviour terms the synthesis set to zero.
  fpp   false-MATERIAL findings per PANEL per round that survive triage (so round FP = fpp*T; cert_sim holds
        fp per ROUND constant, which is why width looked free)
  q     P(a found REAL material hole is triaged down to REFINEMENT/DISPUTED); seeds bypass the raters
        (SYNTHESIS §5.3: a script + one seed-aware judge match them), so pi is unaffected
  omit  fraction of real holes that are OMISSIONS (never in the text) with detection shifted -2 logits;
        seeds are commission mutations of text that exists (§5.3 operators), so they are never shifted
  surf  after signoff, fraction of residual holes (live+downgraded) and of universally-blind holes that
        surface and are triaged 'escape' (in-frame, reproduced, material)
A take-back (§8.3) = escapes > n_pred95. Stop = K dry rounds or R_max (cap certifies). stdlib only."""
import random, math, sys
sys.path.insert(0, '/tmp/rescomp/design')
import cert_sim as m

DIV24 = dict(panels=[(f, s) for f in "ABCD" for s in range(6)], corr={"D": ("A", 0.6)})
COMPS = {8: m.DIV8, 16: m.DIV16, 24: DIV24}

def binom(rng, n, p):
    return sum(1 for _ in range(n) if rng.random() < p)

def program(rng, N0=20, T=24, K=3, s=100, b=0.1, u=0.05, fpp=0.0, q=0.0, omit=0.0, R_max=14, surf_det=1.0, surf_blind=0.5):
    cfg = m.Cfg(N0=N0, K=K, comp=COMPS[T], s=s, b=b, u=u)
    orig = []
    for _ in range(N0):
        it = m.new_item(rng, cfg)
        if rng.random() < omit:
            it["z"] = [z - 2.0 for z in it["z"]]
        orig.append(it)
    seeds = [m.new_item(rng, cfg, blind_ok=False) for _ in range(s)]
    live_o, live_f, live_s, live_sh = list(orig), [], list(seeds), []
    s_sh = 0; F_o = F_f = 0; deferred = 0; dry = 0; k = 0; fp_tot = 0
    while True:
        k += 1
        found = 0
        keep = []
        for it in live_o:
            if m.detect(rng, it, cfg.sd_e):
                if rng.random() < q: deferred += 1          # real, material, rated REFINEMENT/DISPUTED: not fixed, not in F
                else: F_o += 1; found += 1
            else: keep.append(it)
        live_o = keep
        keep = []
        for it in live_f:
            if m.detect(rng, it, cfg.sd_e):
                if rng.random() < q: deferred += 1
                else: F_f += 1; found += 1
            else: keep.append(it)
        live_f = keep
        live_s = [it for it in live_s if not m.detect(rng, it, cfg.sd_e)]
        live_sh = [it for it in live_sh if not m.detect(rng, it, cfg.sd_e)]
        nfp = m.poisson(rng, fpp * T)
        fp_tot += nfp; F_o += nfp; found += nfp
        if found:
            dry = 0
            for _ in range(found):
                for _ in range(m.poisson(rng, b)): live_f.append(m.new_item(rng, cfg))
                live_sh.append(m.new_item(rng, cfg, blind_ok=False)); s_sh += 1
        else:
            dry += 1
        if dry >= K: stop = "dry"; break
        if k >= R_max: stop = "cap"; break
    d_o = m.predictive_draws(rng, F_o, len(live_s), s, 600)
    d_f = m.predictive_draws(rng, F_f, len(live_sh), s_sh, 600) if s_sh else [0] * 600
    npred = m.quantile([a + c for a, c in zip(d_o, d_f)], 0.95)
    det_left = sum(1 for it in live_o + live_f if not it["blind"])
    blind_left = sum(1 for it in live_o + live_f if it["blind"])
    esc = binom(rng, det_left + deferred, surf_det) + binom(rng, blind_left, surf_blind)
    return dict(k=k, stop=stop, npred=npred, det_left=det_left, deferred=deferred, blind=blind_left,
                esc=esc, takeback=esc > npred, fp=fp_tot)

def row(name, reps=400, seed=11, **kw):
    rng = random.Random(seed)
    R = [program(rng, **kw) for _ in range(reps)]
    ks = [r["k"] for r in R]
    print("%-44s rounds p50/p90 %2d/%-2d  cap-stop %5.1f%%  npred95 med %d  material-left(det+deferred) %.2f  blind %.2f  P(take-back) %5.1f%%" % (
        name, m.pct(ks, .5), m.pct(ks, .9), 100 * m.mean([r["stop"] == "cap" for r in R]), m.pct([r["npred"] for r in R], .5),
        m.mean([r["det_left"] + r["deferred"] for r in R]), m.mean([r["blind"] for r in R]), 100 * m.mean([r["takeback"] for r in R])))

if __name__ == "__main__":
    for N0 in (20, 60):
        print("\n## N0=%d  (K=3, s=100, b=0.1, u=0.05, R_max=14)" % N0)
        print("# A. baseline as the synthesis models it (fpp=0, q=0, omit=0); take-back counts only desk-detectable surfacing (surf_blind=0)")
        row("A0 max24 synthesis assumptions", N0=N0, T=24, surf_blind=0.0)
        print("# B. the synthesis's own declared invisible mass surfaces post-signoff and is triaged 'escape' (surf_blind)")
        for sb in (0.25, 0.5, 1.0):
            row("B max24 invisible surfacing %.2f" % sb, N0=N0, T=24, surf_blind=sb)
        print("# C. false-MATERIAL per PANEL (scales with T); width stops being free")
        for fpp in (0.01, 0.02, 0.04):
            for T in (8, 16, 24):
                row("C fpp=%.2f T=%d" % (fpp, T), N0=N0, T=T, fpp=fpp, surf_blind=0.0)
        print("# D. rater self-preference: real holes triaged down w.p. q; seeds bypass raters")
        for qq in (0.1, 0.2, 0.3):
            row("D max24 q=%.1f" % qq, N0=N0, T=24, q=qq, surf_blind=0.0)
        print("# E. omission-class real holes (-2 logits), seeds are commission mutations")
        for om in (0.3, 0.5):
            row("E max24 omit=%.1f" % om, N0=N0, T=24, omit=om, surf_blind=0.0)
        print("# F. combined, moderate: fpp=.02 q=.15 omit=.3 surf_blind=.5")
        for T in (8, 16, 24):
            row("F combined T=%d" % T, N0=N0, T=T, fpp=0.02, q=0.15, omit=0.3, surf_blind=0.5)
