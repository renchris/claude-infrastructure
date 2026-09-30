"""SYNTHESIS §5.1: 6 of 24 slots are 'Anthropic-alternate = Opus with different strategies' (Fable only 1 slot, odd rounds).
cert_sim/synth_width model that family as rho=0.6 to Opus (the Fable figure). Same weights => rho ~ 1. Re-run max24."""
import sys; sys.path.insert(0,'/tmp/rescomp/design'); import cert_sim as m
for rho in (0.6, 0.9, 1.0):
    comp=dict(panels=[(f,s) for f in "ABCD" for s in range(6)], corr={"D":("A",rho)})
    for N0 in (20,60):
        R=m.run(m.Cfg(N0=N0,K=3,comp=comp,s=100,pred_draws=600),500,seed=77+N0)
        print("rho(D,A)=%.1f N0=%d rounds p50/p90 %d/%d  desk-left mean %.3f  P(>=1) %.3f  npred95 holds %.1f%%"%(rho,N0,m.pct([r['rounds'] for r in R],.5),m.pct([r['rounds'] for r in R],.9),m.mean([r['res_det'] for r in R]),m.mean([1 if r['res_det']>=1 else 0 for r in R]),100*m.mean([1 if r['res_det']<=r['npred_tot'] else 0 for r in R])))
