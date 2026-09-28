"""Transfer probe: FTS5 fielded BM25 (stdlib) + model2vec potion-base-8M cosine (numpy), fused by RRF.
Tests whether TrueMemory's cheap vector leg adds recall on OUR corpus without torch/reranker."""
import json, os, sys, time, sqlite3, resource
sys.path.insert(0, os.path.dirname(__file__))
from common import *
import numpy as np
t0 = time.perf_counter()
from model2vec import StaticModel
mdl = StaticModel.from_pretrained("minishlab/potion-base-8M")
load_s = time.perf_counter() - t0
docs = load_docs(); Q = load_queries(); fids = list(docs)

def doc_text(fid, mode):
    text = docs[fid]; n, de, h = title_of(text); _, body = split_frontmatter(text)
    head = (h or n.replace("-", " ")) + ". " + de
    return head if mode == "head" else head + "\n" + body

res, raw = {}, {}
fts = sqlite3.connect(":memory:")
fts.execute("CREATE VIRTUAL TABLE d USING fts5(fid UNINDEXED, name, descr, body, tokenize='porter unicode61')")
for fid, text in docs.items():
    n, de, h = title_of(text); _, body = split_frontmatter(text)
    fts.execute("INSERT INTO d VALUES (?,?,?,?)", (fid, n.replace('-', ' ') + ' ' + h, de, body))
def ftsq(q): return " OR ".join('"' + t + '"' for t in terms(q))
def fts_rank(q): return [r[0] for r in fts.execute("SELECT fid FROM d WHERE d MATCH ? ORDER BY bm25(d,0,10,5,1) LIMIT 100", (ftsq(q),))]

for mode in ("full", "head"):
    t = time.perf_counter()
    E = mdl.encode([doc_text(f, mode) for f in fids]); E = E / (np.linalg.norm(E, axis=1, keepdims=True) + 1e-9)
    enc_s = time.perf_counter() - t
    rk_vec, rk_rrf, lat = {}, {}, []
    for q in Q:
        s = time.perf_counter()
        qv = mdl.encode([q["q"]])[0]; qv = qv / (np.linalg.norm(qv) + 1e-9)
        order = np.argsort(-(E @ qv))[:100]
        vec = [fids[i] for i in order]
        fr = fts_rank(q["q"])
        sc = {}
        for lst in (fr, vec):
            for i, f in enumerate(lst): sc[f] = sc.get(f, 0) + 1.0 / (60 + i + 1)
        rrf = sorted(sc, key=lambda f: -sc[f])
        lat.append((time.perf_counter() - s) * 1000)
        rk_vec[q["id"]] = vec; rk_rrf[q["id"]] = rrf
    res[f"m2v_vec_only_{mode}"] = score(Q, rk_vec)
    res[f"rrf_fts5fielded+m2v_{mode}"] = score(Q, rk_rrf)
    res[f"rrf_fts5fielded+m2v_{mode}"].update(latency_ms_mean=sum(lat) / len(lat), encode_corpus_s=enc_s)
    raw[f"m2v_vec_only_{mode}"] = {k: v[:20] for k, v in rk_vec.items()}
    raw[f"rrf_fts5fielded+m2v_{mode}"] = {k: v[:20] for k, v in rk_rrf.items()}
res["_meta"] = {"model_load_s": load_s, "maxrss_bytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}
json.dump(res, open(f"{OUT}/results_hybrid_lite.json", "w"), indent=1)
json.dump(raw, open(f"{OUT}/raw_hybrid_lite.json", "w"), indent=1)
for k, v in res.items():
    if k.startswith("_"): print(v); continue
    print(f"{k:34s} r@1={v['recall@1']:.2f} r@5={v['recall@5']:.2f} r@10={v['recall@10']:.2f} mrr={v['mrr']:.3f} {v['by_style']}")
