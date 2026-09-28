"""Shared corpus/query/metric helpers. stdlib only."""
import json, os, re, glob
CORPUS = "/tmp/tm-sandbox/corpus"
INDEXES = "/tmp/tm-sandbox/indexes"
OUT = "/tmp/tm-research/tm-empirical"
STOP = set("""a an the and or but if of to in on at by for with from into onto over under is are was were be been being
it its it's this that these those i my me we our you your he she they them their his her as so not no do does did done
has have had having can could would should will just only still even too very than then there here when while after before
about because what which who whom whose why how all any some every each both either neither also out up down off again
same other such own more most much many once got get gets getting made make makes keeps keep kept actually anymore""".split())

def load_docs():
    docs = {}
    for sub in ("memory", "lessons"):
        for p in sorted(glob.glob(f"{CORPUS}/{sub}/*.md")):
            docs[f"{sub}/{os.path.basename(p)}"] = open(p, encoding="utf-8", errors="replace").read()
    return docs

def split_frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---\n?(.*)$", text, re.S)
    if not m:
        return {}, text
    fm, body = m.group(1), m.group(2)
    meta = {}
    for k in ("name", "description"):
        mm = re.search(rf"^{k}:\s*(.*)$", fm, re.M)
        if mm:
            meta[k] = mm.group(1).strip().strip('"')
    return meta, body

def title_of(text):
    meta, body = split_frontmatter(text)
    h = re.search(r"^#\s+(.*)$", body, re.M)
    return meta.get("name", ""), meta.get("description", ""), (h.group(1) if h else "")

def load_queries():
    return json.load(open(f"{OUT}/queries.json"))

def terms(q):
    toks = re.findall(r"[A-Za-z0-9_][A-Za-z0-9_.\-/]*", q.lower())
    out = []
    for t in toks:
        t = t.strip(".-/")
        if len(t) < 2 or t in STOP:
            continue
        if t not in out:
            out.append(t)
    return out

def dedupe_files(ranked):
    seen, out = set(), []
    for f in ranked:
        if f and f not in seen:
            seen.add(f); out.append(f)
    return out

def score(queries, ranked_by_qid):
    """ranked_by_qid: qid -> list of file ids (deduped, best first)."""
    rows, r1, r5, r10, mrr = [], 0, 0, 0, 0.0
    for q in queries:
        rk = ranked_by_qid.get(q["id"], [])
        gold = set(q["gold"])
        pos = next((i + 1 for i, f in enumerate(rk) if f in gold), None)
        r1 += pos == 1; r5 += bool(pos and pos <= 5); r10 += bool(pos and pos <= 10)
        mrr += 1.0 / pos if pos else 0.0
        rows.append({"id": q["id"], "style": q["style"], "gold_rank": pos, "top5": rk[:5]})
    n = len(queries)
    by_style = {}
    for s in sorted({q["style"] for q in queries}):
        sub = [r for r in rows if r["style"] == s]
        by_style[s] = {"n": len(sub),
                       "r1": sum(r["gold_rank"] == 1 for r in sub),
                       "r5": sum(bool(r["gold_rank"] and r["gold_rank"] <= 5) for r in sub)}
    return {"n": n, "recall@1": r1 / n, "recall@5": r5 / n, "recall@10": r10 / n, "mrr": mrr / n,
            "hits@1": r1, "hits@5": r5, "by_style": by_style, "rows": rows}
