#!/usr/bin/env python3
"""Tally a judges/ dir by the probe's rule: strict majority over 3 blind judges per pair,
majority recall = key id hit by >=2 judges, plus bad cites / wrong claims / scores summed
over all judges.

Usage: tally.py <judges dir> [<corpus-final.json>]
Control: run on the original ../judges and it must reproduce ../instruments/tally.txt totals.
"""

import collections, glob, json, os, sys

jd = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
corpus = json.load(
    open(
        sys.argv[2]
        if len(sys.argv) > 2
        else os.path.join(here, "..", "corpus", "corpus-final.json")
    )
)
keys = {b["id"]: [k["id"] for k in b["key"]] for b in corpus}
PAIRS = [("A", "B"), ("A", "C"), ("B", "C")]

tallies = {p: collections.Counter() for p in PAIRS}
tot = {a: collections.Counter() for a in "ABC"}
scores = {a: [] for a in "ABC"}
for bid, kid in keys.items():
    files = sorted(glob.glob(os.path.join(jd, f"{bid}-J*.json")))
    if len(files) != 3:
        print(f"{bid}: {len(files)} judge files — SKIPPED (need 3)")
        continue
    js = [json.load(open(f)) for f in files]
    canon = {k.lower(): k for k in kid}
    per = {
        a: {"hits": collections.Counter(), "bad": [], "chk": [], "wrong": [], "sc": []}
        for a in "ABC"
    }
    calls = {p: [] for p in PAIRS}
    for j in js:
        lm, v = j["label_map"], j["verdict"]
        for o in v["outputs"]:
            a = lm[o["label"]]
            hits = {
                canon[h.strip().lower()]
                for h in o["key_hits"]
                if h.strip().lower() in canon
            }
            per[a]["hits"].update(hits)
            per[a]["bad"].append(len(o["citations_bad"]))
            per[a]["chk"].append(o["citations_checked"])
            per[a]["wrong"].append(len(o["wrong_claims"]))
            per[a]["sc"].append(o["score_1_10"])
        inv = {"tie": "tie", **lm}
        for (x, y), f in zip([("X", "Y"), ("X", "Z"), ("Y", "Z")], ("xy", "xz", "yz")):
            w = inv[v[f]]
            pair = tuple(sorted((lm[x], lm[y])))
            calls[pair].append(w)
    line = [bid]
    for p in PAIRS:
        c = collections.Counter(calls[p]).most_common()
        maj = c[0][0] if c and c[0][1] >= 2 else "no-maj"
        tallies[p][maj] += 1
        line.append(f"{p[0]}-{p[1]}:{maj}[{','.join(calls[p])}]")
    print(" ".join(line))
    for a in "ABC":
        m = sum(1 for k in kid if per[a]["hits"][k] >= 2)
        tot[a]["mrec"] += m
        tot[a]["keys"] += len(kid)
        tot[a]["bad"] += sum(per[a]["bad"])
        tot[a]["chk"] += sum(per[a]["chk"])
        tot[a]["wrong"] += sum(per[a]["wrong"])
        scores[a] += per[a]["sc"]
        print(
            f"   {a} majority-recall {m}/{len(kid)}  bad-cites {per[a]['bad']} of checked {per[a]['chk']}  wrong-claims {per[a]['wrong']}  scores {per[a]['sc']}"
        )

print("\nPAIRWISE strict-majority tallies:")
for p in PAIRS:
    print(f"  {p[0]} vs {p[1]}: {dict(tallies[p])}")
print("\nTOTALS")
for a in "ABC":
    t = tot[a]
    if not t["keys"]:
        continue
    print(
        f"  {a} majority-recall {t['mrec']}/{t['keys']} = {100 * t['mrec'] / t['keys']:.1f}%  bad-cites {t['bad']}/{t['chk']} = {100 * t['bad'] / max(1, t['chk']):.1f}%  wrong-claims {t['wrong']}  mean score {sum(scores[a]) / len(scores[a]):.2f}"
    )
