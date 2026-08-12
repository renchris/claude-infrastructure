#!/usr/bin/env python3
"""Close the rows a triage wave adjudicated PRUNE or MERGE.

Evidence is the agent's own one-line reason, prefixed so the store records WHY and
by what pass — a close with no reason is indistinguishable from a silent drop, and
`cc-backlog reopen <id> --force` is the undo.

── WHY THIS FILE IS TRACKED NOW (2026-08-12, W2 of BACKLOG_SELF_DRAINING) ──────────
It closed 161 rows on 2026-08-09 with 0 failures — the single largest reduction this
pile has ever seen — from an UNTRACKED file in docs/plans/backlog-consolidation-
2026-08-09/ with no caller and no test, one `git clean -f -d` from gone.

WHAT IT IS AND IS NOT, because the distinction is the whole reason it is safe. This
is a TRIAGE-WAVE tool, not a standing sweep: its input is a directory of OUT-*.md
reports in which agents recorded a per-row verdict, so it can only ever close rows a
human-supervised pass actually adjudicated. It has no opinion of its own. Nothing
schedules it and nothing should — an unattended closer over a store this size is the
one tool in this directory that could destroy work rather than re-file it, and the
verdict tables are what bound it. Its live sibling is group.py, which only ever
LINKS (see link.py's header on why linking is the weaker, true assertion).

THE PARSER IS FORMAT-TOLERANT ON PURPOSE. Each agent wrote its verdict lines
slightly differently (backticked id, bare id, bold verb). The contract is the SET of
ids and their verdicts, not the punctuation.

Dry by default. Pass --run to execute.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import subprocess
import sys

# id | VERDICT | reason...   (tolerant of backticks and bold, as the reports vary)
#
# THE LEADING PIPE IS OPTIONAL, and it was not. Every line in the 2026-08-09 reports began with the
# id, so the original anchored on it — but the reports are MARKDOWN, and the natural way to write a
# verdict table there is `| id | VERDICT | reason |`. Such a row parsed as nothing: this file would
# have reported "0 rows to close" over a complete table and exited 0, which is the silent-skip
# failure the whole toolkit is built to avoid. verify.py would still have caught it (that is what it
# is for), but the contract in the docstring above is "the SET of ids and their verdicts, not the
# punctuation", so the parser should hold up its end.
LINE = re.compile(
    r"^\s*\|?\s*\**`?([0-9a-f]{12})`?\**\s*\|\s*\**(PRUNE|UPDATE|KEEP|MERGE)\**\s*\|\s*(.*)$",
    re.M,
)

# Only touch rows the wave actually adjudicated, and only in these two verdicts.
CLOSE = {"PRUNE", "MERGE"}


def backlog_bin(explicit: str | None = None) -> str:
    if explicit:
        return explicit
    env = os.environ.get("CC_BACKLOG_BIN")
    if env:
        return env
    here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    local = os.path.join(here, "bin", "cc-backlog")
    return local if os.path.exists(local) else "cc-backlog"


def collect(triage_dir: str) -> list[tuple[str, str, str, str]]:
    """→ [(id, verdict, slice, reason)], first verdict per id wins."""
    rows: list[tuple[str, str, str, str]] = []
    for path in sorted(glob.glob(os.path.join(triage_dir, "OUT-*.md"))):
        slice_name = os.path.basename(path)[4:-3]
        with open(path) as fh:
            body = fh.read()
        for iid, verdict, reason in LINE.findall(body):
            if verdict not in CLOSE:
                continue
            clean = re.sub(r"[`*]", "", reason).strip()
            clean = re.sub(r"\s+", " ", clean)
            if len(clean) > 300:
                clean = clean[:297] + "..."
            rows.append((iid, verdict, slice_name, clean))
    seen: set[str] = set()
    uniq: list[tuple[str, str, str, str]] = []
    for r in rows:
        if r[0] in seen:
            continue
        seen.add(r[0])
        uniq.append(r)
    return uniq


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True, description=__doc__)
    ap.add_argument("--dir", required=True, help="triage directory holding OUT-*.md")
    ap.add_argument("--run", action="store_true", help="close the rows (default: dry)")
    ap.add_argument("--bin", default=None, help="path to cc-backlog (tests)")
    ap.add_argument("--log", default=None, help="write a per-row log here")
    ap.add_argument(
        "--stamp",
        default="backlog-consolidation",
        help="evidence prefix naming the pass that adjudicated these rows",
    )
    args = ap.parse_args()

    if not os.path.isdir(args.dir):
        print(f"prune.py: no such triage directory: {args.dir}", file=sys.stderr)
        return 2
    uniq = collect(args.dir)
    n_prune = sum(1 for r in uniq if r[1] == "PRUNE")
    print(f"{len(uniq)} rows to close  ({n_prune} PRUNE, {len(uniq) - n_prune} MERGE)")
    if not uniq:
        return 0

    if not args.run:
        for iid, verdict, _sl, reason in uniq[:5]:
            print(f"  [{verdict}] {iid}  {reason[:110]}")
        print("  … DRY RUN — nothing written. Pass --run to execute.")
        return 0

    bin_path = backlog_bin(args.bin)
    ok = fail = 0
    log = open(args.log, "w") if args.log else None
    try:
        for iid, verdict, sl, reason in uniq:
            ev = f"{args.stamp} [{verdict}/{sl}]: {reason}"
            p = subprocess.run(
                [bin_path, "done", iid, "--evidence", ev],
                capture_output=True,
                text=True,
            )
            if p.returncode == 0:
                ok += 1
            else:
                fail += 1
                print(
                    f"verdict=refused    {iid}: rc={p.returncode} "
                    f"{p.stderr.strip()[:140]}",
                    file=sys.stderr,
                )
            if log:
                log.write(
                    f"{'OK  ' if p.returncode == 0 else 'FAIL'} {iid} {verdict} "
                    f"{reason[:120]}\n"
                )
    finally:
        if log:
            log.close()
    print(f"closed={ok} failed={fail}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
