"""TrueMemory retrieval on our corpus. Run with HOME/XDG sandboxed (see /tmp/tm-sandbox/env.sh)."""
import argparse, json, os, re, sys, threading, time, resource
sys.path.insert(0, os.path.dirname(__file__))
from common import *
import psutil

ap = argparse.ArgumentParser()
ap.add_argument("--variant", choices=["doc", "chunk"], required=True)
ap.add_argument("--patch-reranker", type=int, default=1)
ap.add_argument("--modes", default="full,norerank,vec")
ap.add_argument("--tag", default="")
ap.add_argument("--limit", type=int, default=0)
ap.add_argument("--nq", type=int, default=0)
a = ap.parse_args()
tag = a.tag or f"{a.variant}_patch{a.patch_reranker}"

# ---- RSS guard (hard cap 4 GB) + peak sampler
PROC = psutil.Process(); PEAK = [0]
def guard():
    while True:
        rss = PROC.memory_info().rss; PEAK[0] = max(PEAK[0], rss)
        if rss > 4 * 1024**3:
            print(f"ABORT: RSS {rss/2**30:.2f} GB > 4 GB", flush=True); os._exit(9)
        time.sleep(0.25)
threading.Thread(target=guard, daemon=True).start()

t0 = time.perf_counter()
from truememory import Memory
import truememory.reranker as R
import_s = time.perf_counter() - t0

if a.patch_reranker:
    _orig = R.get_reranker
    def _patched(*args, **kw):
        m = _orig(*args, **kw)
        if not getattr(m, "_tm_materialized", False):
            import torch
            with torch.no_grad():
                for p in m.model.parameters():
                    p.data = p.data.clone()
            m._tm_materialized = True
        return m
    R.get_reranker = _patched

docs = load_docs(); Q = load_queries()
db = f"/tmp/tm-sandbox/db/{a.variant}.db"
mapf = db + ".idmap.json"

def chunks_for(fid, text):
    name, desc, h1 = title_of(text)
    _, body = split_frontmatter(text)
    header = (h1 or name.replace("-", " ")) + (": " + desc if desc else "")
    paras = [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip()]
    out, cur = [], ""
    for p in paras:
        if cur and len(cur) + len(p) > 1200:
            out.append(cur); cur = ""
        cur = (cur + "\n\n" + p) if cur else p
    if cur: out.append(cur)
    return [header + "\n" + c for c in out] or [header]

ingest = {}
if not os.path.exists(mapf):
    if os.path.exists(db): os.remove(db)
    m = Memory(path=db)
    idmap, add_lat = {}, []
    t = time.perf_counter()
    for fid, text in docs.items():
        pieces = [text[:50000]] if a.variant == "doc" else chunks_for(fid, text)
        for piece in pieces:
            s = time.perf_counter(); r = m.add(piece); add_lat.append(time.perf_counter() - s)
            idmap[r["id"]] = fid
    ingest_s = time.perf_counter() - t
    th = m._engine._consolidation_thread
    tw = time.perf_counter()
    if th is not None: th.join()
    final_consolidate_s = None
    if os.environ.get("TM_FINAL_CONSOLIDATE") == "1":
        s = time.perf_counter(); m._engine.consolidate(); final_consolidate_s = time.perf_counter() - s
    json.dump({str(k): v for k, v in idmap.items()}, open(mapf, "w"))
    ingest = {"rows": len(idmap), "ingest_s": ingest_s, "consolidation_tail_wait_s": time.perf_counter() - tw,
              "add_ms_mean": 1000 * sum(add_lat) / len(add_lat), "add_ms_max": 1000 * max(add_lat),
              "add_ms_p50": 1000 * sorted(add_lat)[len(add_lat) // 2], "final_consolidate_s": final_consolidate_s, "auto_consolidate_every": os.environ.get("TRUEMEMORY_AUTO_CONSOLIDATE_EVERY", "25(default)")}
    m.close()
idmap = {int(k): v for k, v in json.load(open(mapf)).items()}
m = Memory(path=db)
lim = a.limit or (20 if a.variant == "doc" else 60)
if a.nq: Q = Q[:a.nq]
results, raw = {"_meta": {"tag": tag, "import_s": import_s, "ingest": ingest, "stats": m.stats(), "limit": lim, "nq": len(Q)}}, {}

def run(mode):
    rk, lat, unmapped, nan_scores, srcs = {}, [], 0, 0, {}
    # warm-up (model load) timed separately
    s = time.perf_counter(); _call(mode, "warm up query about git"); warm = time.perf_counter() - s
    for q in Q:
        s = time.perf_counter(); rows = _call(mode, q["q"]); lat.append(time.perf_counter() - s)
        files = []
        for r in rows:
            f = idmap.get(r.get("id"))
            if f is None: unmapped += 1
            sc = r.get("score")
            if isinstance(sc, float) and sc != sc: nan_scores += 1
            srcs[str(r.get("source"))] = srcs.get(str(r.get("source")), 0) + 1
            files.append(f)
        rk[q["id"]] = dedupe_files(files)
    res = score(Q, rk)
    lat_ms = sorted(1000 * x for x in lat)
    res.update(first_call_s=warm, latency_ms_mean=sum(lat_ms) / len(lat_ms), latency_ms_p50=lat_ms[len(lat_ms) // 2],
               latency_ms_max=lat_ms[-1], unmapped_rows=unmapped, nan_score_rows=nan_scores, sources=srcs)
    return res, rk

def _call(mode, q):
    if mode == "full": return m.search(q, limit=lim)
    if mode == "norerank": return m.search(q, limit=lim, _skip_reranker=True)
    if mode == "vec": return m.search_vectors(q, limit=lim)
    if mode == "deep": return m.search_deep(q, limit=lim)
    raise SystemExit(mode)

for mode in a.modes.split(","):
    res, rk = run(mode)
    results[f"tm_{a.variant}_{mode}" + ("" if a.patch_reranker or mode != "full" else "_ASINSTALLED_nanreranker")] = res
    raw[mode] = rk
    print(f"{tag} {mode:9s} r@1={res['recall@1']:.2f} r@5={res['recall@5']:.2f} r@10={res['recall@10']:.2f} "
          f"mrr={res['mrr']:.3f} lat_mean={res['latency_ms_mean']:.0f}ms p50={res['latency_ms_p50']:.0f}ms "
          f"first={res['first_call_s']:.1f}s nan={res['nan_score_rows']} unmapped={res['unmapped_rows']}", flush=True)

results["_meta"].update(peak_rss_bytes=PEAK[0], maxrss_ru=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
                        db_bytes=sum(os.path.getsize(p) for p in [db, db + "-wal", db + "-shm"] if os.path.exists(p)))
print(json.dumps(results["_meta"], default=str), flush=True)
json.dump(results, open(f"{OUT}/results_tm_{tag}.json", "w"), indent=1, default=str)
json.dump(raw, open(f"{OUT}/raw_tm_{tag}.json", "w"), indent=1)
print("DONE", flush=True)
