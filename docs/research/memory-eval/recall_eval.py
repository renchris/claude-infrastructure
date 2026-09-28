#!/usr/bin/env python3
"""Memory recall eval: does the right memory file reach the agent for a query?

Scores exact gold-path matches (R@1, R@5, MRR with Wilson 95% intervals) per arm and query style.
Arms: loaded-only (what the MEMORY.md loader injects after truncation, plus resident rules files),
load-everything (in-process fielded FTS5 over the whole corpus) and retriever (the shipped
cc-memory-search CLI, run as a subprocess exactly as a hook or agent runs it).

Outcome classes kept apart from hit/miss: gold-missing (no time-valid gold in the corpus: a capture
failure, not a retrieval one), in-context-not-obeyed (record label), reinforced-superseding-memory
(the top hit declares it replaces a practice, or the record names it). Design: TrueMemory report
section 3.5 and 5.11 (docs/research/truememory-2026-09-27.md). Stdlib only.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import math
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

DEFAULT_GOLD = (
    Path.home() / ".claude" / "autonomy" / "memory-eval" / "field-queries.json"
)
DEFAULT_RETRIEVER = Path(__file__).resolve().parents[3] / "bin" / "cc-memory-search"
LINE_LIMIT = 200
UNIT_LIMIT = 25_000
FTS_LIMIT = 50
STYLES = ("op", "op12", "ag", "authored")
CLASSES = (
    "hit",
    "miss",
    "gold-missing",
    "in-context-not-obeyed",
    "reinforced-superseding-memory",
)
EXIT_MANIFEST = 3

# Tokeniser and stopwords are the 50-query bake-off's (empirical-harness/common.py), so the
# numbers here stay comparable with that pass and with the gap-2 replay.
STOP = set(
    """a an the and or but if of to in on at by for with from into onto over under is are was were
be been being it its it's this that these those i my me we our you your he she they them their his
her as so not no do does did done has have had having can could would should will just only still
even too very than then there here when while after before about because what which who whom whose
why how all any some every each both either neither also out up down off again same other such own
more most much many once got get gets getting made make makes keeps keep kept actually
anymore""".split()
)
SUPERSEDE = re.compile(
    r"^\s*(?:[-*]\s*)?\**(?:replaces|supersedes)\**\s*:", re.I | re.M
)
LINK = re.compile(r"\]\(([^)\s]+)\)")


def terms(q: str) -> list[str]:
    out: list[str] = []
    for tok in re.findall(r"[A-Za-z0-9_][A-Za-z0-9_.\-/]*", q.lower()):
        t = tok.strip(".-/")
        if len(t) >= 2 and t not in STOP and t not in out:
            out.append(t)
    return out


def split_frontmatter(text: str) -> tuple[dict[str, str], str]:
    m = re.match(r"^---\n(.*?)\n---\n?(.*)$", text, re.S)
    if not m:
        return {}, text
    meta: dict[str, str] = {}
    for k in ("name", "description", "supersedes", "replaces"):
        mm = re.search(rf"^{k}:\s*(.*)$", m.group(1), re.M)
        if mm:
            meta[k] = mm.group(1).strip().strip('"')
    return meta, m.group(2)


def loader_effective(text: str) -> str:
    """The MEMORY.md text the loader keeps (mirrors hooks/lib/memory-index-measure.sh), truncated."""
    text = re.sub(r"^---\s*\n[\s\S]*?---\s*\n?", "", text, count=1)
    if "```" not in text:
        text = re.sub(r"(?m)^<!--[\s\S]*?-->[ \t]*\n?", "", text)
    lines = text.strip().split("\n")[:LINE_LIMIT]
    kept: list[str] = []
    units = 0
    for ch in "\n".join(lines):
        units += 2 if ord(ch) > 0xFFFF else 1
        if units > UNIT_LIMIT:
            break
        kept.append(ch)
    return "".join(kept)


@dataclass
class Doc:
    id: str
    path: Path
    birth: float | None
    text: str = ""


@dataclass
class Corpus:
    stores: list[tuple[str, Path]] = field(default_factory=list)
    lessons: Path | None = None
    rules: list[Path] = field(default_factory=list)
    docs: dict[str, Doc] = field(default_factory=dict)

    def by_real(self) -> dict[str, str]:
        return {str(d.path.resolve()): d.id for d in self.docs.values()}


def store_name(d: Path) -> str:
    base = d.parent.name if d.name == "memory" else d.name
    return re.sub(r"^-Users-[^-]+-Development-", "", base)


def git_birth(directory: Path) -> dict[str, float]:
    """First-add time per file under a git-tracked dir (a worktree's mtimes are its checkout's)."""

    # Names come back relative to the repo TOP, whatever -C says, so find the top by its .git
    # entry (rev-parse --show-toplevel refuses in a checkout whose core.bare got set).
    def git(*args: str) -> str:
        return subprocess.run(
            ["git", "-C", str(directory), *args],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        ).stdout

    top = next(
        (
            d
            for d in (directory.resolve(), *directory.resolve().parents)
            if (d / ".git").exists()
        ),
        None,
    )
    if top is None:
        return {}
    try:
        rel = os.path.relpath(directory.resolve(), top)
        out = git(
            "log",
            "--diff-filter=A",
            "--name-only",
            "--format=@%at",
            "HEAD",
            "--",
            f":(top){rel}",
        )
    except (OSError, subprocess.TimeoutExpired):
        return {}
    born: dict[str, float] = {}
    t = 0.0
    for line in out.splitlines():
        if line.startswith("@"):
            t = float(line[1:])
        elif line.strip():
            # log is newest-first, so the last write (the oldest add) wins
            born[str((top / line.strip()).resolve())] = t
    return born


def fs_birth(p: Path) -> float | None:
    st = p.stat()
    return float(getattr(st, "st_birthtime", st.st_mtime))


def add_doc(c: Corpus, doc_id: str, p: Path, birth: float | None) -> None:
    c.docs[doc_id] = Doc(
        doc_id, p, birth, p.read_text(encoding="utf-8", errors="replace")
    )


def load_live(stores: list[str], lessons: str | None, rules: list[str]) -> Corpus:
    c = Corpus()
    for spec in stores:
        name, _, raw = spec.rpartition("=") if "=" in spec else ("", "", spec)
        d = Path(raw).expanduser()
        c.stores.append((name or store_name(d), d))
    for name, d in c.stores:
        for p in sorted(d.resolve().rglob("*.md")):
            rel = p.relative_to(d.resolve()).as_posix()
            if rel != "MEMORY.md":
                add_doc(c, f"store:{name}/{rel}", p, fs_birth(p))
    if lessons:
        c.lessons = Path(lessons).expanduser()
        gb = git_birth(c.lessons)
        for p in sorted(c.lessons.glob("*.md")):
            add_doc(c, f"lessons:{p.name}", p, gb.get(str(p.resolve()), fs_birth(p)))
    births: dict[Path, dict[str, float]] = {}
    for r in rules:
        p = Path(r).expanduser()
        if p.parent not in births:
            births[p.parent] = git_birth(p.parent)
        gb = births[p.parent]
        c.rules.append(p)
        add_doc(c, f"rules:{p.name}", p, gb.get(str(p.resolve()), fs_birth(p)))
    return c


def corpus_files(c: Corpus) -> list[tuple[Path, str]]:
    """(source, snapshot-relative path) for every file the snapshot must carry."""
    out: list[tuple[Path, str]] = []
    for name, d in c.stores:
        for p in sorted(d.resolve().rglob("*.md")):
            out.append((p, f"stores/{name}/{p.relative_to(d.resolve()).as_posix()}"))
    if c.lessons:
        out += [(p, f"lessons/{p.name}") for p in sorted(c.lessons.glob("*.md"))]
    out += [(p, f"rules/{p.name}") for p in c.rules]
    return out


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def snapshot(c: Corpus, dest: Path) -> int:
    if dest.exists() and any(dest.iterdir()):
        print(f"REFUSED: snapshot destination is not empty: {dest}", file=sys.stderr)
        return 2
    births = {str(d.path.resolve()): d.birth for d in c.docs.values()}
    rows: list[str] = []
    for src, rel in corpus_files(c):
        out = dest / rel
        if out.exists():
            print(f"REFUSED: two corpus files map to {rel}", file=sys.stderr)
            return 2
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, out)
        b = births.get(str(src.resolve()))
        rows.append(f"{rel}\t{'' if b is None else repr(b)}")
    meta = {
        "stores": [n for n, _ in c.stores],
        "lessons": c.lessons is not None,
        "rules": [p.name for p in c.rules],
    }
    (dest / "CORPUS.json").write_text(json.dumps(meta, indent=1) + "\n")
    (dest / "BIRTHTIMES.tsv").write_text("".join(r + "\n" for r in rows))
    files = sorted(
        p for p in dest.rglob("*") if p.is_file() and p.name != "MANIFEST.sha256"
    )
    (dest / "MANIFEST.sha256").write_text(
        "".join(f"{sha256(p)}  {p.relative_to(dest).as_posix()}\n" for p in files)
    )
    print(f"SNAPSHOT: {len(files)} files -> {dest}")
    return 0


def verify_manifest(dest: Path) -> list[str]:
    man = dest / "MANIFEST.sha256"
    if not man.is_file():
        return [f"no manifest at {man}"]
    want: dict[str, str] = {}
    for ln in man.read_text().splitlines():
        digest, _, rel = ln.partition("  ")
        if rel:
            want[rel] = digest
    have = {
        p.relative_to(dest).as_posix()
        for p in dest.rglob("*")
        if p.is_file() and p.name != "MANIFEST.sha256"
    }
    bad = [f"missing: {r}" for r in sorted(set(want) - have)]
    bad += [f"unlisted: {r}" for r in sorted(have - set(want))]
    bad += [
        f"sha mismatch: {r}"
        for r in sorted(have & set(want))
        if sha256(dest / r) != want[r]
    ]
    return bad


def load_snapshot(dest: Path) -> Corpus:
    meta = json.loads((dest / "CORPUS.json").read_text())
    births: dict[str, float | None] = {}
    for ln in (dest / "BIRTHTIMES.tsv").read_text().splitlines():
        rel, _, b = ln.partition("\t")
        births[rel] = float(b) if b else None
    c = Corpus()
    for name in meta["stores"]:
        d = dest / "stores" / name
        c.stores.append((name, d))
        for p in sorted(d.rglob("*.md")):
            rel = p.relative_to(d).as_posix()
            if rel != "MEMORY.md":
                add_doc(c, f"store:{name}/{rel}", p, births.get(f"stores/{name}/{rel}"))
    if meta["lessons"]:
        c.lessons = dest / "lessons"
        for p in sorted(c.lessons.glob("*.md")):
            add_doc(c, f"lessons:{p.name}", p, births.get(f"lessons/{p.name}"))
    for r in meta["rules"]:
        p = dest / "rules" / r
        c.rules.append(p)
        add_doc(c, f"rules:{r}", p, births.get(f"rules/{r}"))
    return c


def norm_gold(spec: str) -> str:
    """Map a gold spec to a doc-id pattern. `memory/X` (the authored set) matches any store."""
    m = re.match(r"^(?:[\w.-]+:)?(?:docs/)?lessons/([^/]+)$", spec)
    if m:
        return f"lessons:{m.group(1)}"
    m = re.match(r"^(?:[\w.-]+:)?(?:\.claude/)?rules/([^/]+)$", spec)
    if m:
        return f"rules:{m.group(1)}"
    if spec.startswith("memory/"):
        return "store:*/" + spec[len("memory/") :]
    return spec


def gold_hit(pattern: str, doc_id: str) -> bool:
    if pattern.startswith("store:*/"):
        return doc_id.startswith("store:") and doc_id.split("/", 1)[-1] == pattern[8:]
    return pattern == doc_id


@dataclass
class Query:
    rid: str
    style: str
    text: str
    gold: list[str]
    cutoff: float | None
    label: str | None
    superseding: list[str]
    words: list[str]


def iso(ts: str) -> float:
    return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()


def split_of(rid: str) -> str:
    return (
        "holdout" if int(hashlib.sha1(rid.encode()).hexdigest(), 16) % 5 == 0 else "dev"
    )


def expand(records: list[dict[str, Any]], tag: str | None) -> list[Query]:
    out: list[Query] = []
    for r in records:
        label = r.get("outcome") or ("gold-missing" if r.get("gold_missing") else None)
        cut = iso(r["miss_ts"]) if r.get("miss_ts") else None
        common = (list(r.get("gold", [])), cut, label, list(r.get("superseding", [])))
        if "q" in r:
            out.append(
                Query(r["id"], tag or "authored", r["q"], *common, r["q"].split())
            )
            continue
        op, ag = r.get("operator_verbatim", ""), r.get("agent_query", "")
        op12 = " ".join(terms(op)[:12])
        out.append(Query(r["id"], "op", op, *common, op.split()))
        out.append(Query(r["id"], "op12", op12, *common, op12.split()))
        if ag:
            out.append(Query(r["id"], "ag", ag, *common, ag.split()))
    return out


class Fts:
    def __init__(self, c: Corpus, weights: tuple[float, float, float]) -> None:
        self.c, self.w = c, weights
        self.cache: dict[float | None, sqlite3.Connection] = {}

    def con(self, cutoff: float | None) -> sqlite3.Connection:
        if cutoff not in self.cache:
            con = sqlite3.connect(":memory:")
            con.execute(
                "CREATE VIRTUAL TABLE d USING fts5(fid UNINDEXED, name, descr, body, "
                "tokenize='porter unicode61')"
            )
            for d in self.c.docs.values():
                if cutoff is not None and d.birth is not None and d.birth > cutoff:
                    continue
                meta, body = split_frontmatter(d.text)
                h1 = re.search(r"^#\s+(.*)$", body, re.M)
                nm = meta.get("name") or d.path.stem
                con.execute(
                    "INSERT INTO d VALUES (?,?,?,?)",
                    (
                        d.id,
                        nm.replace("-", " ").replace("_", " ")
                        + " "
                        + (h1.group(1) if h1 else ""),
                        meta.get("description", ""),
                        body,
                    ),
                )
            self.cache[cutoff] = con
        return self.cache[cutoff]

    def rank(self, q: Query) -> list[str]:
        ts = terms(q.text)
        if not ts:
            return []
        match = " OR ".join('"' + t.replace('"', '""') + '"' for t in ts)
        a, b, w3 = self.w
        sql = f"SELECT fid FROM d WHERE d MATCH ? ORDER BY bm25(d, 0, {a}, {b}, {w3}) LIMIT {FTS_LIMIT}"
        return [row[0] for row in self.con(q.cutoff).execute(sql, (match,))]


def loaded_list(c: Corpus) -> list[str]:
    """Doc ids the loader puts in context, in order: each store's surviving MEMORY.md links,
    then each resident rules file and the lessons its hooks link."""
    out: list[str] = []
    for name, d in c.stores:
        idx = d / "MEMORY.md"
        if not idx.is_file():
            continue
        for tgt in LINK.findall(
            loader_effective(idx.read_text(encoding="utf-8", errors="replace"))
        ):
            rel = os.path.normpath(tgt.split("#", 1)[0])
            if not rel.startswith(".."):
                out.append(f"store:{name}/{rel}")
    for p in c.rules:
        text = p.read_text(encoding="utf-8", errors="replace")
        if re.match(r"^---\n(?:.*\n)*?paths:", text):
            continue  # path-scoped: loaded only when a matching file is touched, not resident
        out.append(f"rules:{p.name}")
        for tgt in LINK.findall(text):
            if "docs/lessons/" in tgt:
                out.append(f"lessons:{os.path.basename(tgt.split('#', 1)[0])}")
    return list(dict.fromkeys(out))


def retriever_rank(cmd: str, c: Corpus, q: Query, weights: str) -> list[str]:
    argv = [cmd, "--json", "--top", "5"]
    for _, d in c.stores:
        argv += ["--store", str(d)]
    if c.lessons:
        argv += ["--lessons", str(c.lessons)]
    for p in c.rules:
        argv += ["--rules", str(p)]
    env = dict(os.environ, CC_MEMORY_SEARCH_WEIGHTS=weights)
    res = subprocess.run(
        argv + q.words, capture_output=True, text=True, env=env, timeout=60, check=False
    )
    if res.returncode != 0:
        raise RuntimeError(
            f"retriever exit {res.returncode}: {res.stderr.strip()[:200]}"
        )
    real = c.by_real()
    out: list[str] = []
    for hit in json.loads(res.stdout or "[]"):
        doc = real.get(str(Path(hit["path"]).expanduser().resolve()))
        out.append(doc or f"unmapped:{hit['path']}")
    return out


def born_by(c: Corpus, doc_id: str, cutoff: float | None) -> bool:
    """False only for a known doc born after the miss (a live retriever cannot rewind)."""
    doc = c.docs.get(doc_id)
    return cutoff is None or doc is None or doc.birth is None or doc.birth <= cutoff


def classify(
    q: Query, ranked: list[str], c: Corpus
) -> tuple[str, int | None, list[str]]:
    pats = [norm_gold(g) for g in q.gold]
    valid = [
        d.id
        for d in c.docs.values()
        if any(gold_hit(p, d.id) for p in pats)
        and not (q.cutoff is not None and d.birth is not None and d.birth > q.cutoff)
    ]
    pos = next((i + 1 for i, f in enumerate(ranked) if f in valid), None)
    if q.label in ("in-context-not-obeyed", "reinforced-superseding-memory"):
        return q.label, pos, valid
    top = ranked[0] if ranked else None
    if top and top not in valid:
        doc = c.docs.get(top)
        declares = doc is not None and (
            SUPERSEDE.search(doc.text) is not None
            or bool({"supersedes", "replaces"} & set(split_frontmatter(doc.text)[0]))
        )
        if top in q.superseding or declares:
            return "reinforced-superseding-memory", pos, valid
    if q.label == "gold-missing" or not valid:
        return "gold-missing", pos, valid
    return ("hit" if pos else "miss"), pos, valid


def wilson(k: float, n: int, z: float = 1.96) -> list[float]:
    if n == 0:
        return [0.0, 0.0]
    p = k / n
    den = 1 + z * z / n
    mid = (p + z * z / (2 * n)) / den
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return [round(max(0.0, mid - half), 4), round(min(1.0, mid + half), 4)]


def summarise(rows: list[dict[str, Any]]) -> dict[str, Any]:
    scored = [r for r in rows if r["class"] in ("hit", "miss")]
    n = len(scored)
    r1 = sum(1 for r in scored if r["rank"] == 1)
    r5 = sum(1 for r in scored if r["rank"] and r["rank"] <= 5)
    mrr = sum(1 / r["rank"] for r in scored if r["rank"])
    return {
        "n_scored": n,
        "r1": round(r1 / n, 4) if n else None,
        "r1_ci": wilson(r1, n),
        "r5": round(r5 / n, 4) if n else None,
        "r5_ci": wilson(r5, n),
        "mrr": round(mrr / n, 4) if n else None,
        "mrr_ci": wilson(mrr, n),
        "reach": sum(1 for r in scored if r["rank"]),
        "classes": {k: sum(1 for r in rows if r["class"] == k) for k in CLASSES},
    }


def fmt(v: float | None, ci: list[float]) -> str:
    return "   -" if v is None else f"{v:.3f} [{ci[0]:.2f},{ci[1]:.2f}]"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    ap.add_argument(
        "--store", action="append", default=[], help="store dir, or NAME=DIR"
    )
    ap.add_argument("--lessons")
    ap.add_argument("--rules", action="append", default=[])
    ap.add_argument(
        "--snapshot", type=Path, help="freeze the corpus into DEST and exit"
    )
    ap.add_argument(
        "--corpus", type=Path, help="score a frozen snapshot (refused on mismatch)"
    )
    ap.add_argument("--queries", type=Path, default=DEFAULT_GOLD)
    ap.add_argument(
        "--authored", type=Path, help="agent-authored query file (style=authored)"
    )
    ap.add_argument("--project", help="score only records whose project is this")
    ap.add_argument("--arms", default="loaded-only,load-everything,retriever")
    ap.add_argument("--weights", default="10,5,1")
    ap.add_argument("--retriever-cmd", default=str(DEFAULT_RETRIEVER))
    ap.add_argument("--split", choices=("dev", "holdout"), default="dev")
    ap.add_argument("--unseal", action="store_true")
    ap.add_argument(
        "--json", action="store_true", help="print JSON results instead of the table"
    )
    ap.add_argument("--out", type=Path, help="also write JSON results here")
    a = ap.parse_args(argv)

    if a.corpus:
        bad = verify_manifest(a.corpus)
        if bad:
            print(
                f"REFUSED: corpus {a.corpus} does not match its manifest "
                f"({len(bad)} problem(s)); not scoring:",
                file=sys.stderr,
            )
            for b in bad[:20]:
                print(f"  {b}", file=sys.stderr)
            return EXIT_MANIFEST
        corpus = load_snapshot(a.corpus)
    else:
        corpus = load_live(a.store, a.lessons, a.rules)
    if a.snapshot:
        return snapshot(corpus, a.snapshot)
    if not a.queries.is_file():
        print(f"NOT-RUN: private gold absent at {a.queries}")
        return 0
    if a.split == "holdout" and not a.unseal:
        print("SEALED: holdout numbers print only with --split holdout --unseal")
        return 0
    try:
        weights = tuple(float(x) for x in a.weights.split(","))
        assert len(weights) == 3
    except (ValueError, AssertionError):
        print(f"bad --weights {a.weights!r}: want a,b,c", file=sys.stderr)
        return 2
    records = [
        r
        for r in json.loads(a.queries.read_text())
        if a.project is None or r.get("project") == a.project
    ]
    queries = expand(records, None)
    if a.authored:
        queries += expand(json.loads(a.authored.read_text()), "authored")
    queries = [q for q in queries if split_of(q.rid) == a.split]

    arms = [x.strip() for x in a.arms.split(",") if x.strip()]
    not_run: dict[str, str] = {}
    if "retriever" in arms:
        cmd = Path(a.retriever_cmd)
        if not (cmd.is_file() and os.access(cmd, os.X_OK)):
            not_run["retriever"] = f"no executable at {cmd}"
    fts = Fts(corpus, (weights[0], weights[1], weights[2]))
    loaded = loaded_list(corpus)
    rows: list[dict[str, Any]] = []
    for arm in arms:
        if arm in not_run:
            continue
        for q in queries:
            if arm == "loaded-only":
                ranked = [x for x in loaded if born_by(corpus, x, q.cutoff)]
            elif arm == "load-everything":
                ranked = fts.rank(q)
            elif arm == "retriever":
                try:
                    hits = retriever_rank(a.retriever_cmd, corpus, q, a.weights)
                    ranked = [x for x in hits if born_by(corpus, x, q.cutoff)]
                except (
                    RuntimeError,
                    OSError,
                    ValueError,
                    KeyError,
                    subprocess.TimeoutExpired,
                ) as e:
                    not_run["retriever"] = str(e)
                    rows = [r for r in rows if r["arm"] != "retriever"]
                    break
            else:
                print(f"unknown arm {arm!r}", file=sys.stderr)
                return 2
            cls, pos, valid = classify(q, ranked, corpus)
            rows.append(
                {
                    "arm": arm,
                    "id": q.rid,
                    "style": q.style,
                    "class": cls,
                    "rank": pos,
                    "valid_gold": valid,
                    "top5": ranked[:5],
                }
            )

    results: dict[str, Any] = {
        "generated": datetime.datetime.now(datetime.timezone.utc).isoformat(
            timespec="seconds"
        ),
        "split": a.split,
        "weights": a.weights,
        "project": a.project,
        "corpus": {
            "docs": len(corpus.docs),
            "stores": [n for n, _ in corpus.stores],
            "loaded_links": len(loaded),
        },
        "not_run": not_run,
        "arms": {},
        "rows": rows,
    }
    for arm in arms:
        if arm in not_run:
            continue
        ar = [r for r in rows if r["arm"] == arm]
        results["arms"][arm] = {
            s: summarise([r for r in ar if r["style"] == s])
            for s in STYLES
            if any(r["style"] == s for r in ar)
        }
    if a.out:
        a.out.parent.mkdir(parents=True, exist_ok=True)
        a.out.write_text(json.dumps(results, indent=1) + "\n")
    for arm, why in not_run.items():
        print(f"ARM {arm} NOT-RUN: {why}", file=sys.stderr if a.json else sys.stdout)
    if a.json:
        print(json.dumps(results, indent=1))
        return 0
    print(
        f"split={a.split} weights={a.weights} docs={len(corpus.docs)} "
        f"loaded_links={len(loaded)} queries={len(queries)}"
    )
    print(
        f"{'arm':16} {'style':8} {'n':>3} {'R@1 [95%]':>19} {'R@5 [95%]':>19} "
        f"{'MRR [95%]':>19} {'miss':>4} {'gm':>3} {'nob':>3} {'sup':>3}"
    )
    for arm, by in results["arms"].items():
        for s, m in by.items():
            k = m["classes"]
            print(
                f"{arm:16} {s:8} {m['n_scored']:>3} {fmt(m['r1'], m['r1_ci']):>19} "
                f"{fmt(m['r5'], m['r5_ci']):>19} {fmt(m['mrr'], m['mrr_ci']):>19} "
                f"{k['miss']:>4} {k['gold-missing']:>3} {k['in-context-not-obeyed']:>3} "
                f"{k['reinforced-superseding-memory']:>3}"
            )
    print(
        "gm=gold-missing nob=in-context-not-obeyed sup=reinforced-superseding-memory "
        "(none of the three counts as a miss)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
