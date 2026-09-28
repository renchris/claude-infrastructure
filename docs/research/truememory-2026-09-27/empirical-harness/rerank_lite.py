"""Transfer probe: FTS5-fielded + model2vec RRF, then MiniLM cross-encoder rerank of only the top-K files
(header+first 1200 chars of body). Measures whether TrueMemory's reranker gain survives a much smaller pool."""
import json, os, sys, time, resource
sys.path.insert(0, os.path.dirname(__file__))
from common import *
import torch
from sentence_transformers import CrossEncoder
raw = json.load(open(f"{OUT}/raw_hybrid_lite.json"))["rrf_fts5fielded+m2v_full"]
docs = load_docs(); Q = load_queries()
t = time.perf_counter()
ce = CrossEncoder("cross-encoder/ms-marco-MiniLM-L-6-v2", device="cpu")
with torch.no_grad():
    for p in ce.model.parameters(): p.data = p.data.clone()   # mmap-backed weights give NaN/SIGBUS on this box
load_s = time.perf_counter() - t
def passage(fid):
    n, de, h = title_of(docs[fid]); _, body = split_frontmatter(docs[fid])
    return ((h or n.replace("-", " ")) + ". " + de + "\n" + body)[:1500]
res, out = {"_meta": {"load_s": load_s}}, {}
for K in (5, 10, 20):
    rk, lat = {}, []
    for q in Q:
        cands = raw[q["id"]][:K]
        s = time.perf_counter()
        sc = ce.predict([(q["q"], passage(f)) for f in cands], show_progress_bar=False)
        lat.append((time.perf_counter() - s) * 1000)
        # fuse like TrueMemory: 0.6 * minmax(rerank) + 0.4 * minmax(1/rank)
        import numpy as np
        sc = np.asarray(sc, dtype=float); r = np.array([1.0 / (i + 1) for i in range(len(cands))])
        mm = lambda x: (x - x.min()) / (x.max() - x.min() + 1e-9)
        fused = 0.6 * mm(sc) + 0.4 * mm(r)
        rk[q["id"]] = [cands[i] for i in np.argsort(-fused)] + raw[q["id"]][K:]
    res[f"rrf_lite+minilm_rerank_top{K}"] = score(Q, rk)
    res[f"rrf_lite+minilm_rerank_top{K}"].update(rerank_ms_mean=sum(lat) / len(lat), rerank_ms_max=max(lat))
    out[K] = {k: v[:10] for k, v in rk.items()}
res["_meta"]["maxrss_bytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
json.dump(res, open(f"{OUT}/results_rerank_lite.json", "w"), indent=1)
json.dump(out, open(f"{OUT}/raw_rerank_lite.json", "w"), indent=1)
for k, v in res.items():
    if k.startswith("_"): print(v); continue
    print(f"{k:34s} r@1={v['recall@1']:.2f} r@5={v['recall@5']:.2f} mrr={v['mrr']:.3f} rerank_ms_mean={v['rerank_ms_mean']:.0f} {v['by_style']}")
