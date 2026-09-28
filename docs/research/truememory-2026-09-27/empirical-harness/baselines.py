"""(b) ripgrep keyword, (c) SQLite FTS5 BM25, (d) index-only baselines. stdlib + rg binary."""
import json, os, re, sqlite3, subprocess, sys, time, resource
sys.path.insert(0, os.path.dirname(__file__))
from common import *

docs = load_docs()
Q = load_queries()
results, raw = {}, {}

def timed(fn):
    t = time.perf_counter(); r = fn(); return r, (time.perf_counter() - t) * 1000

# ---------- (b) ripgrep: per-term substring count, rank by distinct terms matched then total hits
def rg_rank(q):
    per_file = {}
    for t in terms(q):
        p = subprocess.run(["rg", "-i", "-c", "-F", "--", t, CORPUS + "/memory", CORPUS + "/lessons"],
                           capture_output=True, text=True)
        for line in p.stdout.splitlines():
            path, _, c = line.rpartition(":")
            fid = os.path.relpath(path, CORPUS)
            d = per_file.setdefault(fid, [0, 0]); d[0] += 1; d[1] += int(c)
    return [f for f, _ in sorted(per_file.items(), key=lambda kv: (-kv[1][0], -kv[1][1], kv[0]))]

# (b2) ripgrep AND of all terms (what an agent gets from `rg -l a | xargs rg -l b ...`)
def rg_and(q):
    ts = terms(q); files = None
    for t in ts:
        p = subprocess.run(["rg", "-i", "-l", "-F", "--", t, CORPUS + "/memory", CORPUS + "/lessons"],
                           capture_output=True, text=True)
        s = {os.path.relpath(x, CORPUS) for x in p.stdout.split()}
        files = s if files is None else files & s
    return sorted(files or [])

for name, fn in (("rg_distinct_terms", rg_rank), ("rg_all_terms_AND", rg_and)):
    rk, lat = {}, []
    for q in Q:
        r, ms = timed(lambda: fn(q["q"])); rk[q["id"]] = r; lat.append(ms)
    results[name] = score(Q, rk); results[name]["latency_ms_mean"] = sum(lat) / len(lat)
    results[name]["latency_ms_max"] = max(lat)
    if name == "rg_all_terms_AND":
        results[name]["queries_with_zero_hits"] = sum(1 for v in rk.values() if not v)
        results[name]["mean_result_count"] = sum(len(v) for v in rk.values()) / len(rk)
    raw[name] = {k: v[:20] for k, v in rk.items()}

# ---------- (c) FTS5 BM25
def fts_query(q):
    ts = terms(q)
    return " OR ".join('"' + t.replace('"', '""') + '"' for t in ts) or '""'

def build_fts(fielded, path=":memory:"):
    con = sqlite3.connect(path)
    if fielded:
        con.execute("CREATE VIRTUAL TABLE d USING fts5(fid UNINDEXED, name, descr, body, tokenize='porter unicode61')")
        for fid, text in docs.items():
            n, de, h = title_of(text); _, body = split_frontmatter(text)
            con.execute("INSERT INTO d VALUES (?,?,?,?)", (fid, (n.replace('-', ' ') + ' ' + h), de, body))
    else:
        con.execute("CREATE VIRTUAL TABLE d USING fts5(fid UNINDEXED, body, tokenize='porter unicode61')")
        for fid, text in docs.items():
            con.execute("INSERT INTO d VALUES (?,?)", (fid, text))
    con.commit(); return con

for name, fielded, rankexpr in (("fts5_bm25_body", False, "bm25(d)"),
                                ("fts5_bm25_fielded_10_5_1", True, "bm25(d, 0, 10.0, 5.0, 1.0)")):
    t0 = time.perf_counter(); con = build_fts(fielded); build_ms = (time.perf_counter() - t0) * 1000
    rk, lat = {}, []
    for q in Q:
        sql = f"SELECT fid FROM d WHERE d MATCH ? ORDER BY {rankexpr} LIMIT 20"
        r, ms = timed(lambda: [x[0] for x in con.execute(sql, (fts_query(q["q"]),))])
        rk[q["id"]] = r; lat.append(ms)
    results[name] = score(Q, rk); results[name].update(build_ms=build_ms, latency_ms_mean=sum(lat) / len(lat),
                                                       latency_ms_max=max(lat))
    raw[name] = rk
# on-disk size of the plain FTS index
p = "/tmp/tm-sandbox/fts5_body.db"
if os.path.exists(p): os.remove(p)
build_fts(False, p).close(); results["fts5_bm25_body"]["disk_bytes"] = os.path.getsize(p)

# ---------- (d) index-only: rank the one-liners of always-loaded indexes by BM25, map line -> file
LINK = re.compile(r"^\s*-\s*\[([^\]]*)\]\(([^)]+)\)\s*(.*)$")
def parse_index(path, kind):
    out = []
    for line in open(path, encoding="utf-8"):
        m = LINK.match(line)
        if not m: continue
        tgt = m.group(2)
        if kind == "memory":
            fid = "memory/" + os.path.basename(tgt)
        else:
            if "docs/lessons/" not in tgt: continue
            fid = "lessons/" + os.path.basename(tgt)
        out.append((fid, m.group(1) + " " + m.group(3)))
    return out

IDX = {
    "hot_MEMORY.md": parse_index(f"{INDEXES}/MEMORY.md", "memory"),
    "rules_hooks": parse_index(f"{INDEXES}/agent-operating-lessons.md", "rules") +
                   parse_index(f"{INDEXES}/agent-operating-lessons-situational.md", "rules"),
    "cold_archive_index": parse_index(f"{INDEXES}/MEMORY_ARCHIVE_2026-H2-COLD.md", "memory"),
}
IDX["always_loaded(hot+rules)"] = IDX["hot_MEMORY.md"] + IDX["rules_hooks"]
IDX["all_indexes(hot+rules+cold)"] = IDX["always_loaded(hot+rules)"] + IDX["cold_archive_index"]
for iname, lines in IDX.items():
    con = sqlite3.connect(":memory:")
    con.execute("CREATE VIRTUAL TABLE l USING fts5(fid UNINDEXED, txt, tokenize='porter unicode61')")
    con.executemany("INSERT INTO l VALUES (?,?)", lines)
    covered = {f for f, _ in lines}
    rk = {}
    for q in Q:
        rk[q["id"]] = dedupe_files([x[0] for x in con.execute(
            "SELECT fid FROM l WHERE l MATCH ? ORDER BY bm25(l) LIMIT 40", (fts_query(q["q"]),))])
    name = "index_only:" + iname
    results[name] = score(Q, rk)
    results[name]["index_lines"] = len(lines)
    results[name]["distinct_files_indexed"] = len(covered)
    results[name]["coverage_ceiling_queries"] = sum(1 for q in Q if set(q["gold"]) & covered)
    results[name]["coverage_ceiling_frac"] = results[name]["coverage_ceiling_queries"] / len(Q)
    raw[name] = rk

results["_meta"] = {"n_docs": len(docs), "n_memory": sum(k.startswith("memory/") for k in docs),
                    "n_lessons": sum(k.startswith("lessons/") for k in docs),
                    "corpus_bytes": sum(len(v.encode()) for v in docs.values()),
                    "maxrss_bytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}
json.dump(results, open(f"{OUT}/results_baselines.json", "w"), indent=1)
json.dump(raw, open(f"{OUT}/raw_baselines.json", "w"), indent=1)
for k, v in results.items():
    if k.startswith("_"): continue
    extra = {kk: v[kk] for kk in ("latency_ms_mean", "coverage_ceiling_queries", "queries_with_zero_hits") if kk in v}
    print(f"{k:42s} r@1={v['recall@1']:.2f} r@5={v['recall@5']:.2f} r@10={v['recall@10']:.2f} mrr={v['mrr']:.3f} {extra}")
print(results["_meta"])
