#!/usr/bin/env python3
"""research-index.py — the research index stage 1's mining reads first (REPORT.md §3.2 step 1, §8 item 7).

Writes docs/research/INDEX.jsonl: one row per top-level entry of docs/research (a file or a directory),
`{topic, path, date, status}`, sorted by path, so a mining fan-out reads prior research through one
file instead of 400 directory entries. The index is GENERATED, never hand-edited.

  research-index.py [--root REPO]            write the index
  research-index.py [--root REPO] --check    exit 1 if the committed index is stale or missing an entry

topic   the first markdown H1 of the file (for a directory: of REPORT.md, README.md, SYNTHESIS.md, or
        its first .md), else the entry's name
date    YYYY-MM-DD from the entry's name, else the date git first added it, else "unknown"
status  a frontmatter `status:` value, else "superseded" when the head of the text says so, else
        "unknown" (an unstated status is said, never guessed)
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional

LEAD_DOCS = ("REPORT.md", "README.md", "SYNTHESIS.md")
SKIP = {"INDEX.jsonl", ".DS_Store"}


def lead_doc(entry: Path) -> Optional[Path]:
    if entry.is_file():
        return entry if entry.suffix in (".md", ".markdown") else None
    for n in LEAD_DOCS:
        if (entry / n).is_file():
            return entry / n
    mds = sorted(entry.glob("*.md"))
    return mds[0] if mds else None


def topic_of(entry: Path) -> str:
    doc = lead_doc(entry)
    if doc:
        for ln in doc.read_text(errors="replace").splitlines()[:60]:
            m = re.match(r"^#\s+(.+?)\s*$", ln)
            if m:
                return m.group(1)
    return entry.stem if entry.is_file() else entry.name


def status_of(entry: Path) -> str:
    doc = lead_doc(entry)
    if not doc:
        return "unknown"
    head = doc.read_text(errors="replace").splitlines()[:40]
    if head and head[0].strip() == "---":
        for ln in head[1:]:
            if ln.strip() == "---":
                break
            m = re.match(r"^status:\s*(\S.*?)\s*$", ln)
            if m:
                return m.group(1)
    for ln in head:
        m = re.match(r"^\**status\**:\**\s*([^—·;(]+)", ln.strip(), re.I)
        if m and m.group(1).strip():
            return m.group(1).strip().rstrip(".:").lower()[:40]
    if any(re.search(r"\bsuperseded\b", ln, re.I) for ln in head[:12]):
        return "superseded"
    return "unknown"


def added_dates(repo: Path) -> Dict[str, str]:
    """docs/research/<entry> -> the date git first added anything under it (one log pass)."""
    p = subprocess.run(
        [
            "git",
            "-C",
            str(repo),
            "log",
            "--diff-filter=A",
            "--name-only",
            "--format=@%as",
            "--reverse",
            "--",
            "docs/research",
        ],
        capture_output=True,
        text=True,
    )
    out: Dict[str, str] = {}
    date = ""
    for ln in p.stdout.splitlines():
        if ln.startswith("@"):
            date = ln[1:]
        elif ln.startswith("docs/research/"):
            top = "/".join(ln.split("/")[:3])
            out.setdefault(top, date)
    return out


def build(repo: Path) -> List[Dict[str, str]]:
    base = repo / "docs" / "research"
    dates = added_dates(repo)
    rows = []
    for e in sorted(base.iterdir()):
        if e.name in SKIP or e.name.startswith("."):
            continue
        rel = f"docs/research/{e.name}"
        m = re.search(r"(20\d\d-\d\d-\d\d)", e.name)
        rows.append(
            {
                "topic": topic_of(e),
                "path": rel + ("/" if e.is_dir() else ""),
                "date": m.group(1) if m else dates.get(rel, "unknown"),
                "status": status_of(e),
            }
        )
    return rows


def render(rows: List[Dict[str, str]]) -> str:
    return "".join(
        json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n" for r in rows
    )


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="research-index.py")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    repo = Path(a.root)
    out = repo / "docs" / "research" / "INDEX.jsonl"
    text = render(build(repo))
    if a.check:
        have = out.read_text() if out.exists() else ""
        if have != text:
            old = {json.loads(ln)["path"] for ln in have.splitlines() if ln.strip()}
            new = {json.loads(ln)["path"] for ln in text.splitlines()}
            print(
                f"INDEX.jsonl is stale: {len(new - old)} entry(ies) missing, {len(old - new)} gone; "
                "run scripts/research-kit/research-index.py",
                file=sys.stderr,
            )
            return 1
        print(f"INDEX.jsonl current: {len(text.splitlines())} entries")
        return 0
    out.write_text(text)
    print(f"wrote {out} ({len(text.splitlines())} entries)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
