# Builds sim_points.py: a verbatim copy of W4 sim.py with (1) request id kept on each row and
# (2) every recycle point of ONE (K,N) policy emitted to a TSV. Nothing else in the model changes.
import sys
src = open(sys.argv[1]).read()
def rep(old, new, count=1):
    global src
    assert src.count(old) == count, (old, src.count(old))
    src = src.replace(old, new)
rep('        model=x[5],\n    )\n', '        model=x[5],\n        req=x[4],\n    )\n')
rep('                nrec[a] += 1\n',
    '                nrec[a] += 1\n                EMIT.append(("mid", k, a, prev["ts"], prev["req"], r["ts"], r["req"], gap, eff_prev, r["turn"]))\n')
rep('                term[a] += 1\n',
    '                term[a] += 1\n                EMIT.append(("terminal", k, a, prev["ts"], prev["req"], "", "", E - prev["ts"], eff_last, ""))\n')
rep('if __name__ == "__main__":', 'EMIT = []\nif False:')
src += '''
if __name__ == "__main__":
    K, N, out_path = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    EMIT.clear()
    base, new, nrec, term, per_sess, parts = simulate([(K, N)], READS["mid"])
    wk = 7.0 / DAYS
    print("K=%d N=%d saved_pp_week=%.2f mid=%d terminal=%d emitted=%d" % (
        K, N, sum((base[a] - new[a]) * wk for a in ACCTS), sum(nrec.values()), sum(term.values()), len(EMIT)))
    paths = {}
    for (a, fi), f in files.items():
        paths.setdefault(f["sid"], set()).add(f["path"])
    with open(out_path, "w") as o:
        o.write("kind\\tsid\\tacct\\tprev_ts\\tprev_req\\tnext_ts\\tnext_req\\tgap_s\\tctx\\tnext_turn\\tpaths\\n")
        for e in EMIT:
            ps = set()
            for (a2, fi) in sess_files[e[1]]:
                ps.add(files[(a2, fi)]["path"])
            o.write("\\t".join(str(x) for x in e) + "\\t" + "|".join(sorted(ps)) + "\\n")
'''
open(sys.argv[2], "w").write(src)
