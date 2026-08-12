#!/usr/bin/env python3
"""Citation graph over the backlog — the derived impact signal.

A row's own words cite other 12-hex row ids. IN-DEGREE (how many OTHER rows name
this one) is a measured proxy for "closing this retires or unblocks others", and it
cannot go stale, because nothing stores it: every run re-derives it from the live
ledger.

── WHY THIS FILE IS TRACKED NOW (2026-08-12, W2 of BACKLOG_SELF_DRAINING) ──────────
Promoted with its siblings out of an untracked triage directory. Its input was
generalised in the same move and for the same reason: it read a snapshot file
(`backlog-open.json`) captured by one wave, so a tracked copy would have measured a
store frozen on 2026-08-11 forever — a derived signal that silently stops being
derived is worse than no signal, because it still prints a confident ranking. It now
reads the LIVE store through cc-backlog by default, and --file still accepts a
snapshot for a retrospective read.

WHAT IT IS FOR, now that grouping exists: ordering. group.py decides WHICH wave owns
a row; in-degree says which rows inside a wave to work FIRST, because a row three
siblings cite is a root the others hang off. The grouping sweep prints the top of
this ranking so the number reaches a reader rather than a JSON file nobody opens.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

HEX12 = re.compile(r"\b[0-9a-f]{12}\b")
CITING_FIELDS = ("title", "evidence", "needs", "dodRef", "condition", "source")


def backlog_bin(explicit: str | None = None) -> str:
    if explicit:
        return explicit
    env = os.environ.get("CC_BACKLOG_BIN")
    if env:
        return env
    here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    local = os.path.join(here, "bin", "cc-backlog")
    return local if os.path.exists(local) else "cc-backlog"


def load(bin_path: str, path: str | None, scope: str) -> list[dict]:
    if path:
        with open(path) as fh:
            return json.load(fh)
    flag = "--all" if scope == "all" else "--open"
    p = subprocess.run(
        [bin_path, "list", flag, "--json"], capture_output=True, text=True
    )
    if p.returncode != 0:
        print(
            f"citegraph.py: cc-backlog list failed rc={p.returncode}: "
            f"{p.stderr.strip()[:200]}",
            file=sys.stderr,
        )
        return []
    try:
        return json.loads(p.stdout or "[]")
    except json.JSONDecodeError as exc:
        print(f"citegraph.py: cc-backlog list emitted non-JSON: {exc}", file=sys.stderr)
        return []


def graph(items: list[dict]) -> list[dict]:
    by_id = {i["id"]: i for i in items if i.get("id")}
    out: dict[str, set[str]] = defaultdict(set)
    inn: dict[str, set[str]] = defaultdict(set)
    for it in items:
        src = it.get("id")
        if not src:
            continue
        blob = " ".join(str(it.get(k) or "") for k in CITING_FIELDS)
        for tgt in set(HEX12.findall(blob)):
            # A self-reference is not a citation, and a 12-hex token that resolves
            # to nothing in this population is a git sha or a foreign id — counting
            # either would inflate the ranking with rows nobody can act on.
            if tgt == src or tgt not in by_id:
                continue
            out[src].add(tgt)
            inn[tgt].add(src)
    rows = [
        {
            "id": i["id"],
            "status": i.get("status"),
            "project": i.get("project"),
            "condition": i.get("condition") or "",
            "in": len(inn[i["id"]]),
            "out": len(out[i["id"]]),
            "cited_by": sorted(inn[i["id"]]),
            "cites": sorted(out[i["id"]]),
            "title": (i.get("title") or "")[:120],
        }
        for i in items
        if i.get("id")
    ]
    rows.sort(key=lambda r: (-r["in"], -r["out"]))
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True, description=__doc__)
    ap.add_argument(
        "--file", default=None, help="read a snapshot JSON instead of the live store"
    )
    ap.add_argument("--scope", choices=("open", "all"), default="open")
    ap.add_argument("--top", type=int, default=20)
    ap.add_argument("--json", action="store_true", help="emit the whole graph as JSON")
    ap.add_argument("--out", default=None, help="also write the full graph JSON here")
    ap.add_argument("--bin", default=None, help="path to cc-backlog (tests)")
    args = ap.parse_args()

    items = load(backlog_bin(args.bin), args.file, args.scope)
    if not items:
        print("citegraph.py: empty or unreadable store — no graph", file=sys.stderr)
        return 0
    rows = graph(items)
    if args.out:
        with open(args.out, "w") as fh:
            json.dump(rows, fh, indent=1)
    if args.json:
        print(json.dumps(rows, indent=1))
        return 0

    edges = sum(r["out"] for r in rows)
    linked = sum(1 for r in rows if r["in"] or r["out"])
    print(f"rows={len(rows)}  with-any-edge={linked}  edges={edges}")
    print("\nTOP IN-DEGREE (closing these retires/unblocks the most):")
    for r in rows[: args.top]:
        if not r["in"]:
            break
        print(
            f"  in={r['in']:2d} out={r['out']:2d}  {r['id']}  [{r['status']}]  "
            f"{r['title'][:88]}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
