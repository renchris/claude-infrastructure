#!/usr/bin/env python3
"""Fusion eval (TrueMemory adoption Wave E #4b): does RRF of FTS5 + model2vec beat FTS5 alone?

Idea: arXiv 2605.04897 / TrueMemory #4b; independent implementation, no TrueMemory code.

Arm `fts` is `bin/cc-memory-search`'s own `build_corpus` + `search`, imported (never its `main`, so
no log row is written). Arm `fused` ranks the SAME corpus by reciprocal-rank fusion (k=60) of that
FTS5 list and a cosine list over head text (H1 or name, then description) embedded with model2vec
(`minishlab/potion-base-8M` unless --model), the recipe in
`docs/research/truememory-2026-09-27/empirical-harness/hybrid_lite.py`. model2vec (and numpy, when
present) are imported only inside the fused arm; without model2vec that arm is NOT-RUN and the FTS5
arm still scores.

Scope: `--store/--lessons/--rules` give one custom scope for every query (the fixture), or
`--project-map FILE` ({project: {"store": DIR, "root": DIR}}) resolves the shipped default project
scope per query. Documents born after the query time leave the corpus before ranking, in both arms.
Primary (docs/research/truememory-2026-09-27.md §5.19): rank of the first gold hit (11 if not in the
top 10), one-sided sign test on the `op` style, ADOPT iff p < 0.05 and R@1(fused) >= R@1(fts).
"""

from __future__ import annotations

import argparse
import datetime
import importlib.machinery
import importlib.util
import json
import math
import os
import re
import resource
import subprocess
import sys
import time
from pathlib import Path
from types import ModuleType
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import recall_eval as rv  # noqa: E402

DEFAULT_SEARCH = Path(__file__).resolve().parents[3] / "bin" / "cc-memory-search"
DEFAULT_MODEL = "minishlab/potion-base-8M"
RRF_K = 60
POOL = 100
CUT = 10
ARMS = ("fts", "fused")
Vec = list[float]


def load_search(path: Path) -> ModuleType:
    loader = importlib.machinery.SourceFileLoader("cc_memory_search", str(path))
    spec = importlib.util.spec_from_loader("cc_memory_search", loader)
    if spec is None:
        raise ImportError(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["cc_memory_search"] = (
        mod  # its @dataclass resolves annotations through this
    )
    loader.exec_module(mod)
    return mod


def rrf(lists: list[list[int]], k: int = RRF_K) -> list[int]:
    """Reciprocal-rank fusion: each list adds 1/(k + i + 1) at 0-based position i. Ties keep first
    appearance order (the first list's items first), as hybrid_lite.py's sorted() does."""
    score: dict[int, float] = {}
    for lst in lists:
        for i, x in enumerate(lst):
            score[x] = score.get(x, 0.0) + 1.0 / (k + i + 1)
    return sorted(score, key=lambda x: -score[x])


def sign_test(wins: int, losses: int) -> float:
    """One-sided P(X >= wins) for X ~ Binomial(wins + losses, 1/2); ties are dropped by the caller."""
    n = wins + losses
    if n == 0:
        return 1.0
    return float(sum(math.comb(n, j) for j in range(wins, n + 1))) / float(2**n)


# ── births ──────────────────────────────────────────────────────────────────────────────────────


def blame_times(path: str) -> dict[int, float]:
    """Line number -> committer time of that line (its last change: a conservative birth)."""
    try:
        out = subprocess.run(
            [
                "git",
                "-C",
                os.path.dirname(path) or ".",
                "blame",
                "--line-porcelain",
                "--",
                path,
            ],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return {}
    times: dict[int, float] = {}
    line, t = 0, 0.0
    for ln in out.splitlines():
        m = re.match(r"^[0-9a-f]{40} \d+ (\d+)", ln)
        if m:
            line = int(m.group(1))
        elif ln.startswith("committer-time "):
            t = float(ln.split()[1])
        elif ln.startswith("\t"):
            times[line] = t
    return times


class Gather:
    """Wraps the CLI's per-source doc builders so each raw doc carries a birth and the cutoff
    applies BEFORE the CLI's own dedupe runs (so a twin born in time is never shadowed)."""

    def __init__(self, mod: ModuleType) -> None:
        self.mod = mod
        self.orig: dict[str, Callable[..., list[Any]]] = {
            n: getattr(mod, n)
            for n in ("topic_docs", "cold_docs", "lesson_docs", "rules_docs")
        }
        self.birth: dict[int, float | None] = {}
        self.raw: list[Any] = []
        self.gb: dict[str, dict[str, float]] = {}
        self.blame: dict[str, dict[int, float]] = {}

    def fs(self, p: str) -> float | None:
        try:
            return rv.fs_birth(Path(p))
        except OSError:
            return None

    def git(self, p: str) -> float | None:
        d = os.path.dirname(os.path.realpath(p))
        if d not in self.gb:
            self.gb[d] = rv.git_birth(Path(d))
        return self.gb[d].get(os.path.realpath(p), self.fs(p))

    def build(self, scope: Any, cutoff: float | None) -> list[Any]:
        def keep(docs: list[Any], births: list[float | None]) -> list[Any]:
            out = []
            for d, b in zip(docs, births):
                self.birth[id(d)] = b
                self.raw.append(d)
                if cutoff is None or b is None or b <= cutoff:
                    out.append(d)
            return out

        def topic(store: str, only_feedback: bool = False) -> list[Any]:
            docs = self.orig["topic_docs"](store, only_feedback)
            return keep(docs, [self.fs(d.path) for d in docs])

        def cold(store: str) -> list[Any]:
            docs = self.orig["cold_docs"](store)
            return keep(
                docs,
                [
                    self.fs(
                        d.path if os.path.isfile(d.path) else d.path.rsplit(":", 1)[0]
                    )
                    for d in docs
                ],
            )

        def lesson(ldir: str) -> list[Any]:
            docs = self.orig["lesson_docs"](ldir)
            return keep(docs, [self.git(d.path) for d in docs])

        def rules(path: str) -> list[Any]:
            docs = self.orig["rules_docs"](path)
            text = self.mod.read_text(path) or ""
            lines = [
                i for i, ln in enumerate(text.split("\n"), 1) if ln.startswith("- ")
            ]
            if path not in self.blame:
                self.blame[path] = blame_times(path)
            bl = self.blame[path]
            fb = self.fs(path)
            return keep(docs, [bl.get(n, fb) for n in lines])

        wrapped = {
            "topic_docs": topic,
            "cold_docs": cold,
            "lesson_docs": lesson,
            "rules_docs": rules,
        }
        self.raw = []
        for n, f in wrapped.items():
            setattr(self.mod, n, f)
        try:
            return list(self.mod.build_corpus(scope))
        finally:
            for n, f in self.orig.items():
                setattr(self.mod, n, f)


# ── ids ─────────────────────────────────────────────────────────────────────────────────────────


class Ids:
    """CLI doc path -> recall_eval-style id (store:<name>/<rel>, lessons:<f>, rules:<f>:<line>)."""

    def __init__(self, stores: list[str], lessons: list[str]) -> None:
        self.stores = sorted(
            {os.path.realpath(s) for s in stores}, key=len, reverse=True
        )
        self.lessons = {os.path.realpath(x) for x in lessons}

    def of(self, doc: Any, rule_files: set[str]) -> str:
        p = doc.path
        if os.path.isfile(p):
            rp = os.path.realpath(p)
            for s in self.stores:
                if rp.startswith(s + os.sep):
                    return f"store:{rv.store_name(Path(s))}/{os.path.relpath(rp, s)}"
            if os.path.dirname(rp) in self.lessons:
                return f"lessons:{os.path.basename(rp)}"
            return f"file:{rp}"
        container, _, line = p.rpartition(":")
        if os.path.realpath(container) in rule_files:
            return f"rules:{os.path.basename(container)}:{line}"
        return f"row:{os.path.basename(container)}:{line}"


def is_gold(pats: list[str], ids: set[str]) -> bool:
    for p in pats:
        for i in ids:
            if rv.gold_hit(p, i) or (p.startswith("rules:") and i.startswith(p + ":")):
                return True
    return False


def declares_supersede(doc: Any) -> bool:
    text = doc.body
    if os.path.isfile(doc.path):
        text = Path(doc.path).read_text(encoding="utf-8", errors="replace")
    meta = rv.split_frontmatter(text)[0]
    return rv.SUPERSEDE.search(text) is not None or bool(
        {"supersedes", "replaces"} & set(meta)
    )


# ── embedding ───────────────────────────────────────────────────────────────────────────────────


class Embedder:
    def __init__(self, model: str) -> None:
        t0 = time.perf_counter()
        from model2vec import (  # type: ignore[import-not-found,unused-ignore]  # fused arm only
            StaticModel,
        )

        self.model = StaticModel.from_pretrained(model)
        self.load_s = time.perf_counter() - t0
        self.cache: dict[str, Vec] = {}
        try:
            import numpy as np

            self.np: Any = np
        except ImportError:
            self.np = None

    def unit(self, v: Any) -> Vec:
        vec = [float(x) for x in v]
        n = math.sqrt(sum(x * x for x in vec)) + 1e-9
        return [x / n for x in vec]

    def encode(self, texts: list[str]) -> list[Vec]:
        todo = [t for t in dict.fromkeys(texts) if t not in self.cache]
        if todo:
            for t, v in zip(todo, self.model.encode(todo)):
                self.cache[t] = self.unit(v)
        return [self.cache[t] for t in texts]

    def rank(self, query: str, heads: list[str], top: int) -> list[int]:
        qv = self.unit(self.model.encode([query])[0])
        mat = self.encode(heads)
        if self.np is not None and mat:
            sims = list(self.np.asarray(mat) @ self.np.asarray(qv))
        else:
            sims = [sum(a * b for a, b in zip(row, qv)) for row in mat]
        return sorted(range(len(heads)), key=lambda i: (-sims[i], i))[:top]


def head_text(mod: ModuleType, doc: Any) -> str:
    h = mod.h1_of(doc.body) if os.path.isfile(doc.path) else ""
    return (h or str(doc.name).replace("-", " ")) + ". " + str(doc.description)


# ── scoring ─────────────────────────────────────────────────────────────────────────────────────


def summarise(rows: list[dict[str, Any]], arm: str) -> dict[str, Any]:
    ranks = [r[f"rank_{arm}"] for r in rows]
    n = len(ranks)
    r1 = sum(1 for x in ranks if x == 1)
    r5 = sum(1 for x in ranks if x <= 5)
    mrr = sum(1 / x for x in ranks if x <= CUT)
    return {
        "n_scored": n,
        "r1": round(r1 / n, 4) if n else None,
        "r1_ci": rv.wilson(r1, n),
        "r5": round(r5 / n, 4) if n else None,
        "r5_ci": rv.wilson(r5, n),
        "mrr": round(mrr / n, 4) if n else None,
        "mrr_ci": rv.wilson(mrr, n),
        "supersede_top1": sum(1 for r in rows if r[f"sup_{arm}"]),
    }


def compare(rows: list[dict[str, Any]]) -> dict[str, Any]:
    w = sum(1 for r in rows if r["rank_fused"] < r["rank_fts"])
    lo = sum(1 for r in rows if r["rank_fused"] > r["rank_fts"])
    return {
        "wins": w,
        "losses": lo,
        "ties": len(rows) - w - lo,
        "p": round(sign_test(w, lo), 6),
    }


def scope_args(
    stores: list[str], lessons: str | None, rules: list[str]
) -> argparse.Namespace:
    return argparse.Namespace(all=False, store=stores, lessons=lessons, rules=rules)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    ap.add_argument("--queries", type=Path, required=True)
    ap.add_argument("--store", action="append", default=[])
    ap.add_argument("--lessons")
    ap.add_argument("--rules", action="append", default=[])
    ap.add_argument(
        "--project-map", type=Path, help='{project: {"store": DIR, "root": DIR}}'
    )
    ap.add_argument("--search-cmd", type=Path, default=DEFAULT_SEARCH)
    ap.add_argument(
        "--model", default=os.environ.get("FUSION_EVAL_MODEL", DEFAULT_MODEL)
    )
    ap.add_argument("--arms", default=",".join(ARMS))
    ap.add_argument(
        "--limit",
        type=int,
        default=0,
        help="score only the first N records (cold probe)",
    )
    ap.add_argument("--out", type=Path)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)

    t_start = time.perf_counter()
    mod = load_search(a.search_cmd)
    records: list[dict[str, Any]] = json.loads(a.queries.read_text())
    if a.limit:
        records = records[: a.limit]
    pmap: dict[str, dict[str, str]] = (
        json.loads(a.project_map.read_text()) if a.project_map else {}
    )
    if not pmap and not (a.store or a.lessons or a.rules):
        print("need --store/--lessons/--rules or --project-map", file=sys.stderr)
        return 2
    arms = [x for x in a.arms.split(",") if x]
    not_run: dict[str, str] = {}
    emb: Embedder | None = None
    if "fused" in arms:
        try:
            emb = Embedder(a.model)
        except Exception as exc:  # noqa: BLE001 — any load failure is a NOT-RUN, never a zero
            not_run["fused"] = (
                f"model2vec unavailable ({type(exc).__name__}: {str(exc)[:120]})"
            )

    gather = Gather(mod)
    rows: list[dict[str, Any]] = []
    lat_ms: list[float] = []
    corpus_sizes: dict[str, int] = {}
    unmapped: list[str] = []
    for r in records:
        cutoff = rv.iso(r["miss_ts"]) if r.get("miss_ts") else None
        if pmap:
            if r.get("project") not in pmap:
                unmapped.append(
                    str(r["id"])
                )  # reported, never silently scored as a miss
                continue
            pm = pmap[r["project"]]
            saved = os.environ.get("MEMORY_INDEX_PATH")
            os.environ["MEMORY_INDEX_PATH"] = os.path.join(pm["store"], "MEMORY.md")
            try:
                scope = mod.resolve_scope(scope_args([], None, []), pm["root"])
            finally:
                if saved is None:
                    os.environ.pop("MEMORY_INDEX_PATH", None)
                else:
                    os.environ["MEMORY_INDEX_PATH"] = saved
        else:
            scope = mod.resolve_scope(
                scope_args(a.store, a.lessons, a.rules), os.getcwd()
            )
        docs = gather.build(scope, cutoff)
        corpus_sizes[r.get("project", "") or "custom"] = len(docs)
        rule_files = {os.path.realpath(x) for x in scope.rules}
        ids = Ids(list(scope.stores) + mod.all_store_dirs(), list(scope.lessons))
        doc_ids = [ids.of(d, rule_files) for d in docs]
        # a raw doc the CLI dropped as a same-(name, description) twin counts through its kept twin
        kept_paths = {
            os.path.realpath(d.path) if os.path.exists(d.path) else d.path for d in docs
        }
        by_key = {(d.name, d.description): i for i, d in enumerate(docs)}
        alias: dict[int, set[str]] = {i: {doc_ids[i]} for i in range(len(docs))}
        for d in gather.raw:
            rp = os.path.realpath(d.path) if os.path.exists(d.path) else d.path
            k = by_key.get((d.name, d.description))
            b = gather.birth.get(id(d))
            if (
                k is not None
                and rp not in kept_paths
                and (cutoff is None or b is None or b <= cutoff)
            ):
                alias[k].add(ids.of(d, rule_files))
        pats = [rv.norm_gold(g) for g in r.get("gold", [])]
        gold_idx = {i for i in range(len(docs)) if is_gold(pats, alias[i])}
        styles = [("op", r.get("operator_verbatim") or r.get("q", ""))]
        if r.get("agent_query"):
            styles.append(("ag", r["agent_query"]))
        heads = [head_text(mod, d) for d in docs] if emb else []
        where = {id(d): i for i, d in enumerate(docs)}
        for style, text in styles:
            t0 = time.perf_counter()
            fts = [
                where[id(d)] for d, _ in mod.search(docs, mod.query_terms([text]), POOL)
            ]
            ranked: dict[str, list[int]] = {"fts": fts}
            if emb is not None:
                ranked["fused"] = rrf([fts, emb.rank(text, heads, POOL)])
                lat_ms.append((time.perf_counter() - t0) * 1000)
            row: dict[str, Any] = {
                "id": r["id"],
                "style": style,
                "source": r.get("source", ""),
                "project": r.get("project", ""),
                "class": "scored" if gold_idx else "gold-missing",
                "corpus": len(docs),
            }
            for arm, lst in ranked.items():
                pos = next(
                    (i + 1 for i, x in enumerate(lst[:CUT]) if x in gold_idx), CUT + 1
                )
                deep = next((i + 1 for i, x in enumerate(lst) if x in gold_idx), None)
                top = lst[0] if lst else None
                row[f"rank_{arm}"] = pos
                row[f"deep_{arm}"] = deep
                row[f"top5_{arm}"] = [doc_ids[i] for i in lst[:5]]
                row[f"sup_{arm}"] = (
                    top is not None
                    and top not in gold_idx
                    and declares_supersede(docs[top])
                )
            rows.append(row)

    live = [x for x in arms if x not in not_run]
    results: dict[str, Any] = {
        "generated": datetime.datetime.now(datetime.timezone.utc).isoformat(
            timespec="seconds"
        ),
        "model": a.model if emb else None,
        "rrf_k": RRF_K,
        "pool": POOL,
        "records": len(records),
        "corpus_sizes": corpus_sizes,
        "not_run": not_run,
        "unmapped": unmapped,
        "styles": {},
        "rows": rows,
    }
    for style in ("op", "ag"):
        sr = [x for x in rows if x["style"] == style]
        scored = [x for x in sr if x["class"] == "scored"]
        if not sr:
            continue
        s: dict[str, Any] = {
            "records": len(sr),
            "gold_missing": len(sr) - len(scored),
            "arms": {arm: summarise(scored, arm) for arm in live},
            "supersede_top1_all": {
                arm: sum(1 for x in sr if x[f"sup_{arm}"]) for arm in live
            },
        }
        if "fused" in live and "fts" in live:
            s["sign"] = compare(scored)
            r1a, r1b = s["arms"]["fts"]["r1"] or 0.0, s["arms"]["fused"]["r1"] or 0.0
            s["verdict"] = "ADOPT" if s["sign"]["p"] < 0.05 and r1b >= r1a else "DROP"
        else:
            s["verdict"] = "NOT-RUN"
        results["styles"][style] = s
    results["perf"] = {
        "total_s": round(time.perf_counter() - t_start, 3),
        "model_load_s": round(emb.load_s, 3) if emb else None,
        "fused_query_ms_mean": round(sum(lat_ms) / len(lat_ms), 2) if lat_ms else None,
        "fused_query_ms_max": round(max(lat_ms), 2) if lat_ms else None,
        "maxrss_mb": round(
            resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
            / (1 << 20 if sys.platform == "darwin" else 1 << 10),
            1,
        ),
    }
    if a.out:
        a.out.parent.mkdir(parents=True, exist_ok=True)
        a.out.write_text(json.dumps(results, indent=1) + "\n")
    if unmapped:
        print(
            f"UNMAPPED {len(unmapped)} record(s) with no --project-map entry: {' '.join(unmapped)}",
            file=sys.stderr if a.json else sys.stdout,
        )
    for arm, why in not_run.items():
        print(f"ARM {arm} NOT-RUN: {why}", file=sys.stderr if a.json else sys.stdout)
    if a.json:
        print(json.dumps(results, indent=1))
        return 0
    for style, s in results["styles"].items():
        for arm, m in s["arms"].items():
            print(
                f"{style:3} {arm:6} n={m['n_scored']:<3} R@1 {rv.fmt(m['r1'], m['r1_ci'])} "
                f"R@5 {rv.fmt(m['r5'], m['r5_ci'])} MRR {rv.fmt(m['mrr'], m['mrr_ci'])} sup={m['supersede_top1']}"
            )
        if "sign" in s:
            g = s["sign"]
            print(
                f"{style:3} sign wins={g['wins']} losses={g['losses']} ties={g['ties']} p={g['p']}"
            )
        print(f"VERDICT {style} {s['verdict']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
