#!/usr/bin/env python3
"""Offline replay (estimate): E1g join rule with each e1h fast arm (1 rep, live 2026-10-06) and E1c's on-pre
careful calls (rep 1 and rep 2, 2026-10-04, cold walls). Careful relay counts only if its wall <= 8.5 s."""
import json
from pathlib import Path
H = Path.home()/".claude/autonomy/research/router-heldout"
REL = ("completeness","pushback"); LIM = 9.0; CAREFUL_LIM = 8.5
strata = [json.loads(l)["stratum"] for l in open(H/"tuning.jsonl")]
lab = [{int(r["id"][1:]): r["label"] for r in map(json.loads, open(H/f"tuning-labels-{v}.jsonl"))} for v in ("anthropic","openai")]
agreed = {k: lab[0][k] for k in lab[0] if lab[1].get(k) == lab[0][k]}
border = [k for k in lab[0] if k in lab[1] and lab[0][k] != lab[1][k] and (lab[0][k] in REL or lab[1][k] in REL)]
neither = [k for k in lab[0] if lab[0][k] not in REL and lab[1].get(k) not in REL]
new = json.load(open("/tmp/e1h-research/stronger-model-live-calls.json"))
old = json.load(open("/Users/chrisren/Development/.worktrees/wt-cc-024434-55635/docs/research/router-classifier-e1c-2026-10-04/tune-2reps.json"))
def ok(c, lim): return c and c["label"] not in ("INVALID","TIMEOUT") and c["wall_s"] <= lim
def union(f, c):
    if ok(f, LIM) and f["label"] in REL: return f["label"], "fast"
    if ok(c, CAREFUL_LIM) and c["label"] in REL: return c["label"], "careful"
    if ok(f, LIM): return f["label"], "fast"
    if ok(c, CAREFUL_LIM): return c["label"], "careful"
    return None, None
fasts = {a: {int(k): v[0] for k, v in r.items()} for a, r in new["arms"].items()}
fasts["e1c:off-e1b rep1"] = {int(k): v[0] for k, v in old["arms"]["off-e1b"].items()}
for fa, F in fasts.items():
    for rep in (0, 1):
        C = {int(k): v[rep] for k, v in old["arms"]["on-pre"].items()}
        U = {k: union(F[k], C[k]) for k in F}
        rec = [U[k][0] in REL for k in U if strata[k] != "other" and agreed.get(k) in REL]
        oth = [U[k][0] == agreed[k] for k in U if strata[k] == "other" and k in agreed]
        bd = sum(1 for k in border if U[k][0] in REL)
        fp = [k for k in neither if U[k][0] in REL]
        fp_by = {s: sum(1 for k in fp if U[k][1] == s) for s in ("fast","careful")}
        fb = sum(1 for k in U if U[k][0] is None)
        print(f"union({fa} + on-pre rep{rep+1}): recall {sum(rec)}/{len(rec)}  other {sum(oth)}/{len(oth)}  "
              f"borderline {bd}/{len(border)}  relays on neither-relay rows {len(fp)}/{len(neither)} (fast {fp_by['fast']}, careful {fp_by['careful']})  fallback {fb}/{len(U)}")
