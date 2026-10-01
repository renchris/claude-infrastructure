"""cli.py — the verb table of bin/cc-research (REPORT.md §8 items 9-12, 15; wave C of
docs/plans/RESEARCH_PROGRAM_BUILD.md).

One argparse parser; each module below adds its own verbs through `add_verbs(sub)` and sets
`fn=<callable(Namespace) -> int>` on every parser it adds. The modules own disjoint verbs:

  cli_core     index frame estimate forecast gate freeze trace reconcile lint verdict pending
               menu budget ceiling reopen                                   (item 9, state)
  cli_records  census premise source decision concern park triage
                                                                            (item 9 records)
  cli_probe    probe doctor self-test                                       (item 10)
  cli_cert     round frame-critique rehearse slots open-round slot raters check-round (item 11)
  cli_jobs     job sweep|freshness|triage|drift|market, run by jobs/research-job.sh (item 12)
  cli_refclass reference-class                                              (item 15)

Exit codes are the kit's (RECORDS.md): 0 ok · 1 a check failed · 2 usage or refusal · 3 a dead
vendor lane · 4 a voided slot. A kit.KitError is a refusal (exit 2), never a traceback.
Records stay append-only and caps stay in kit.py (CAPS, r_max): a verb never re-derives either.
Python 3.9-safe, standard library only.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List, Optional

HERE = Path(__file__).resolve().parent
for p in (HERE, HERE.parents[1] / "lib", HERE.parent):  # kit libs · scripts/lib · kit scripts
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))

import kit  # noqa: E402

MODULES = ("cli_core", "cli_records", "cli_probe", "cli_cert", "cli_jobs",
           "cli_refclass")


def build() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="cc-research")
    sub = ap.add_subparsers(dest="verb", required=True)
    for name in MODULES:
        __import__(name).add_verbs(sub)
    return ap


def main(argv: Optional[List[str]] = None) -> int:
    a = build().parse_args(argv)
    try:
        return int(a.fn(a))
    except kit.KitError as e:
        print(f"cc-research: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
