# Builds sim_guard.py from W4 sim.py: same model, plus (1) a BLOCK set of predecessor request ids at
# which no recycle may fire (a guard), and (2) a candidates mode listing every turn-start idle gap.
import sys
src = open(sys.argv[1]).read()
def rep(old, new):
    global src
    assert src.count(old) == 1, (old, src.count(old))
    src = src.replace(old, new)
rep('        model=x[5],\n    )\n', '        model=x[5],\n        req=x[4],\n    )\n')
rep('N_s = fires(k, eff_prev, gap, prev["ts"]) if (prev is not None and r["turn"]) else None',
    'N_s = fires(k, eff_prev, gap, prev["ts"]) if (prev is not None and r["turn"] and prev["req"] not in BLOCK) else None')
rep('N_s = None if closed else fires(k, eff_last, E - prev["ts"], prev["ts"])',
    'N_s = None if (closed or prev["req"] in BLOCK) else fires(k, eff_last, E - prev["ts"], prev["ts"])')
rep('if __name__ == "__main__":', 'BLOCK = set()\nif False:')
src += '''
if __name__ == "__main__":
    mode = sys.argv[2]
    if mode == "candidates":   # every turn-start gap >= N min (any context) and every terminal tail
        N, out_path = int(sys.argv[3]), sys.argv[4]
        with open(out_path, "w") as o:
            o.write("kind\\tsid\\tacct\\tprev_ts\\tprev_req\\tnext_ts\\tnext_req\\tgap_s\\tctx\\tnext_turn\\tpaths\\n")
            for k, L in sess.items():
                ps = "|".join(sorted(files[f]["path"] for f in sess_files[k]))
                for p, r in zip(L, L[1:]):
                    if r["turn"] and r["ts"] - p["ts"] >= N * 60:
                        o.write("\\t".join(str(x) for x in ("mid", k, p["acct"], p["ts"], p["req"], r["ts"], r["req"], r["ts"] - p["ts"], p["ctx"], r["turn"])) + "\\t" + ps + "\\n")
                p = L[-1]
                if E - p["ts"] >= N * 60:
                    o.write("\\t".join(str(x) for x in ("terminal", k, p["acct"], p["ts"], p["req"], "", "", E - p["ts"], p["ctx"], "")) + "\\t" + ps + "\\n")
    else:                      # guard: python3 sim_guard.py rows K N blockfile
        K, N = int(sys.argv[3]), int(sys.argv[4])
        if len(sys.argv) > 5:
            BLOCK.update(x.strip() for x in open(sys.argv[5]) if x.strip())
        wk = 7.0 / DAYS
        for w in ("mid", "low", "high"):
            base, new, nrec, term, per_sess, parts = simulate([(K, N)], READS[w])
            print("weights=%s K=%d N=%d block=%d saved_pp_week=%.2f mid=%d terminal=%d" % (
                w, K, N, len(BLOCK), sum((base[a] - new[a]) * wk for a in ACCTS), sum(nrec.values()), sum(term.values())))
'''
open(sys.argv[2], "w").write(src)
