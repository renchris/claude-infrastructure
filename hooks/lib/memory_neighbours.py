#!/usr/bin/env python3
"""memory_neighbours.py — the two nearest existing files to a memory topic or lesson being CREATED.

Called by hooks/backup-before-write.sh (truememory-2026-09-27.md §3.10) with the new file's path
as argv[1] and its content on stdin. Prints ONE JSON object, {"top": [{path, score}, ...], "pool_n"}.

Why this scorer and nothing cleverer: over the measured duplicate pairs, gzip novelty under 0.25
caught 0 of 3 (scores 0.55-0.88), while IDF-weighted token overlap on name, description and first
paragraph ranked the twin FIRST in 8 of 8 directions. So: no gzip, and no absolute threshold — the
caller always shows the top two and the model judges.

Pool: every *.md in the new file's own directory (never MEMORY.md, never recursing, so archive/**
is out), plus <repo>/docs/lessons/*.md when the repo can be resolved — from a memory store's
project slug, or directly for a lesson. Only the first 1.5 KB of each file is read.

Exit codes: 0 answered (an empty `top` means an empty pool), 124 the internal budget expired
(CC_MEM_NEIGH_BUDGET seconds, default 2), 2 usage. The caller logs every one of them.
"""

from __future__ import annotations

import json
import math
import os
import re
import signal
import sys
from pathlib import Path
from types import FrameType

HEAD_BYTES = 1536
STOP = frozenset(
    "the and for with that this from into are was were not but you your its it's has have had "
    "when then than them they will can one two all any only never always every what which who "
    "how why a an of to in on at by or is be as if so do no md".split()
)
_WORD = re.compile(r"[a-z0-9]+")
_SLUG_CHAR = re.compile(r"[^A-Za-z0-9]")


def _timeout(_sig: int, _frame: FrameType | None) -> None:
    os._exit(124)


def _budget() -> float:
    try:
        b = float(os.environ.get("CC_MEM_NEIGH_BUDGET", "2"))
    except ValueError:
        return 2.0
    return b if b > 0 else 2.0


def tokens(text: str) -> set[str]:
    return {w for w in _WORD.findall(text.lower()) if len(w) > 2 and w not in STOP}


def profile(path: Path, head: str) -> set[str]:
    """Tokens of the file's stem, frontmatter name + description, title and first paragraph."""
    name = desc = ""
    body = head
    if head.startswith("---"):
        end = head.find("\n---", 3)
        front = head[3:end] if end != -1 else head[3:]
        body = head[end + 4 :] if end != -1 else ""
        for line in front.splitlines():
            key, _, val = line.partition(":")
            if key.strip() == "name":
                name = val.strip()
            elif key.strip() == "description":
                desc = val.strip()
    blocks = [b.strip() for b in re.split(r"\n\s*\n", body) if b.strip()]
    lead = blocks[:2] if blocks and blocks[0].startswith("#") else blocks[:1]
    return tokens(" ".join([path.stem.replace("-", " "), name, desc, *lead]))


def _read_head(path: Path) -> str:
    try:
        with path.open("rb") as fh:
            return fh.read(HEAD_BYTES).decode("utf-8", "replace")
    except OSError:
        return ""


def _slug_to_dir(slug: str) -> Path | None:
    """Invert Claude Code's project slug (every non-alphanumeric char → '-') against the disk."""
    stack: list[tuple[Path, str]] = [(Path("/"), slug)]
    steps = 0
    while stack and steps < 400:
        steps += 1
        base, rest = stack.pop()
        if not rest:
            return base
        if not rest.startswith("-"):
            continue
        try:
            names = [e.name for e in os.scandir(base) if e.is_dir()]
        except OSError:
            continue
        for n in names:
            s = "-" + _SLUG_CHAR.sub("-", n)
            if rest == s or rest.startswith(s + "-"):
                stack.append((base / n, rest[len(s) :]))
    return None


def lessons_dir(new: Path) -> Path | None:
    parts = new.parts
    if len(parts) >= 3 and parts[-3:-1] == ("docs", "lessons"):
        return new.parent
    if new.parent.name == "memory":
        repo = _slug_to_dir(new.parent.parent.name)
        if repo is not None and (repo / "docs" / "lessons").is_dir():
            return repo / "docs" / "lessons"
    return None


def pool_for(new: Path) -> list[Path]:
    dirs = [new.parent]
    lessons = lessons_dir(new)
    if lessons is not None and lessons != new.parent:
        dirs.append(lessons)
    out: list[Path] = []
    for d in dirs:
        try:
            files = sorted(d.glob("*.md"))
        except OSError:
            continue
        out.extend(
            f for f in files if f.name != "MEMORY.md" and f != new and f.is_file()
        )
    return out


def rank(new: Path, content: str, pool: list[Path]) -> list[tuple[Path, float]]:
    docs = {p: profile(p, _read_head(p)) for p in pool}
    q = profile(new, content[:HEAD_BYTES])
    n = len(docs) + 1
    df: dict[str, int] = {}
    for toks in [q, *docs.values()]:
        for t in toks:
            df[t] = df.get(t, 0) + 1
    idf = {t: math.log((n + 1) / (c + 1)) + 1.0 for t, c in df.items()}
    qn = math.sqrt(sum(idf[t] ** 2 for t in q))
    scored: list[tuple[Path, float]] = []
    for p, toks in docs.items():
        dn = math.sqrt(sum(idf[t] ** 2 for t in toks))
        shared = sum(idf[t] ** 2 for t in q & toks)
        scored.append((p, shared / (qn * dn) if qn and dn else 0.0))
    scored.sort(key=lambda x: (-x[1], str(x[0])))
    return scored


def main(argv: list[str]) -> int:
    signal.signal(signal.SIGALRM, _timeout)
    signal.setitimer(signal.ITIMER_REAL, _budget())
    if len(argv) != 2:
        print(
            "usage: memory_neighbours.py <new-file-path>  (content on stdin)",
            file=sys.stderr,
        )
        return 2
    new = Path(argv[1])
    content = sys.stdin.read()
    pool = pool_for(new)
    top = rank(new, content, pool)[:2] if pool else []
    print(
        json.dumps(
            {
                "top": [{"path": str(p), "score": round(s, 3)} for p, s in top],
                "pool_n": len(pool),
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
