#!/usr/bin/env python3
"""plan-venue-census — what venue verdict would every open plan's `advance` row get?

A REPO-ONLY MEASUREMENT. It reads `docs/plans/*.md` and `bin/cc-eligible`, and nothing else: no
backlog store, no deep git history, no live layer. That is the whole point — the population it
measures is a deterministic function of files in the checkout, so a cloud VM can compute it and a
local session gets the identical answer.

── WHY THIS EXISTS (BACKLOG_DRAIN_24_7 §2.1, 2026-08-23) ──────────────────────────────────────────
`bin/cc-discover`'s C2 critic mints one backlog row per open plan:

    add_candidate "advance $title" "$proj" "$path" "plan-open"        (cc-discover:273)

so the row's ENTIRE specification span is a one-line plan title, a path, and the literal source word
`plan-open`. `bin/cc-eligible` decides venue by classifying exactly that span (its SPAN_FIELDS), and
a ~10-word title cannot say what a 15,000-line plan is about. Measured on this repo: **27 of 44**
open plans mint a row that reads `eligible`, i.e. the lane will send it off-box — including
`BACKLOG_DRAIN_24_7` itself, whose every wave is a fold of `~/.claude/autonomy/backlog.jsonl`, a
file that cannot exist in a VM (`bin/cc-cloud`'s header states it outright).

MASTER_OPERATOR_GATED.md named this on 2026-08-15 and deliberately declined to fix it, because
"adding a spelling would be a guess at the class from one instance, and the right change needs a
count over the very store this venue cannot read". This file supplies the count that does NOT need
the store, and — arm 2 — refutes the obvious repair before anyone builds it.

── THE TWO ARMS, AND ARM 2 IS THE ONE THAT EARNS ITS KEEP ────────────────────────────────────────
  ARM 1  the SPEC SPAN — exactly what cc-eligible sees today. Prints the ELIGIBLE bucket, titles
         and all, for the same reason `cc-eligible sweep` does: that is the bucket where a missed
         classification does damage.
  ARM 2  CONTROL — the SAME table over the plan BODY, which is the naive repair ("the classifier
         should read more of the plan"). On this repo it refuses **44 of 44**. A predicate that
         fires on every member of its population is not a classifier, so widening the span is NOT
         the fix, and that is now measured rather than argued. Arm 2 is what stops this census from
         being read as "so add the body to SPAN_FIELDS".

The conclusion the two arms support together is narrower and more useful than either alone: for the
`advance <plan>` row CLASS, venue is not recoverable from text at all — neither the thin span nor
the fat one — so it needs a per-plan DECLARATION (a frontmatter key, or an explicit `cc-backlog
venue` label) rather than a better guess. Designing that is a LOCAL session's job: `cc-eligible`'s
own OFFBOX_LANE class refuses off-box edits to the venue rule, and `bin/cc-venue`'s producer
abstains on a shallow clone by measurement.

🚨 ONE TABLE, NEVER A COPY. The spellings are imported from `bin/cc-eligible` by loading that file,
never re-typed here. A second copy of the table would drift from the gate the moment either was
touched, which is the exact defect `tests/backlog-fold-agreement.bats` exists to pin for the status
fold (memory: sibling-auditors-must-share-the-state-model).

🚨 ONE PLAN READER, NEVER A FOURTH. The open-plan population comes from `find-plan.sh --list-open`,
never from a local re-implementation. find-plan.sh's own header records that there are already
THREE copies of `plan_status()` in this tree and that the third disagrees with the other two; a
fourth reader invented here would be a fourth answer to "is this plan open".

CENSUS, NOT A GATE. Always exit 0 except on usage (2) or an unusable environment (3). Nothing
consumes its verdict, nothing is refused because of it, and it writes no file.

Usage:
  scripts/plan-venue-census.py [--repo <dir>] [--json]

Env:
  CC_CENSUS_FINDPLAN   path to find-plan.sh          (default: <repo>/scripts/find-plan.sh)
  CC_CENSUS_ELIGIBLE   path to cc-eligible           (default: <repo>/bin/cc-eligible)
  CC_PLAN_SCAN_ROOTS   forwarded to find-plan.sh     (default: <repo>/docs/plans)
  CC_PLAN_INDEX        forwarded to find-plan.sh     (default: a path that does not exist, so the
                       census reads the CHECKOUT and never this box's plans-index.json)
"""

import argparse
import collections
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys


def repo_root(start):
    """The checkout containing `start`, by git. Falls back to this file's parent's parent."""
    try:
        out = subprocess.run(
            ["git", "-C", start, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=20,
        )
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_eligible(path):
    """Import bin/cc-eligible as a module so its table is THE table, not a copy of it.

    The file has no `.py` suffix, so the loader must be named EXPLICITLY: `spec_from_file_location`
    picks its loader from the extension and returns None for an extensionless path, which reads as
    "cannot load" for a file that is perfectly good Python. Module level is pure — the header
    guarantees `classify()` does no I/O — so loading it cannot touch the ledger or git.
    """
    spec = importlib.util.spec_from_file_location(
        "cc_eligible", path, loader=importlib.machinery.SourceFileLoader("cc_eligible", path)
    )
    if spec is None or spec.loader is None:
        sys.stderr.write("plan-venue-census: cannot load %s\n" % path)
        sys.exit(3)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as exc:                                   # noqa: BLE001 - report, never mask
        sys.stderr.write("plan-venue-census: %s failed to load (%s)\n" % (path, exc))
        sys.exit(3)
    return mod


def open_plans(findplan, roots, index):
    """[(status, project, path, title)] from find-plan.sh --list-open — the ONE plan reader."""
    env = dict(os.environ)
    env["CC_PLAN_SCAN_ROOTS"] = roots
    env["CC_PLAN_INDEX"] = index
    try:
        out = subprocess.run(
            ["bash", findplan, "--list-open"],
            capture_output=True, text=True, env=env, timeout=120,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        sys.stderr.write("plan-venue-census: find-plan.sh unusable (%s)\n" % exc)
        sys.exit(3)
    rows = []
    for line in out.stdout.splitlines():
        parts = [p.strip() for p in line.split(" | ")]
        if len(parts) < 4 or not parts[3]:
            continue
        rows.append(tuple(parts[:4]))
    return rows


# THE SPAN cc-discover ACTUALLY MINTS, reproduced field for field rather than approximated:
#   title  = "advance <plan title>"   (cc-discover:273, add_candidate "advance $title")
#   dodRef = the plan's path          (add_candidate's 3rd arg)
#   source = "plan-open"              (add_candidate's 4th arg)
# `condition` is absent at mint — C2 files no --condition — so it is absent here too. Adding one
# would make this census measure a row cc-discover does not write.
def mint_span(path, title):
    return "\n".join(["advance " + title, path, "plan-open"])


def body_verdict(mod, path):
    """(first verdict, Counter of token→hits) for the SAME table over the plan's full text."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            txt = fh.read()
    except (IOError, OSError):
        return None, collections.Counter()
    hits = collections.Counter()
    first = None
    for verdict, _desc, pats in mod.CLASSES:
        fired = False
        for tok, rx in pats:
            n = len(rx.findall(txt))
            if n:
                hits[tok] = n
                fired = True
        if fired and first is None:
            first = verdict
    return first, hits


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--repo", default=None)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo) if args.repo else repo_root(os.getcwd())
    findplan = os.environ.get("CC_CENSUS_FINDPLAN") or os.path.join(repo, "scripts", "find-plan.sh")
    eligible = os.environ.get("CC_CENSUS_ELIGIBLE") or os.path.join(repo, "bin", "cc-eligible")
    roots = os.environ.get("CC_PLAN_SCAN_ROOTS") or os.path.join(repo, "docs", "plans")
    # A path that cannot exist, so the default census reads the CHECKOUT and never this box's
    # plans-index.json — otherwise the same repo would census differently on the box that has one.
    index = os.environ.get("CC_PLAN_INDEX") or os.path.join(repo, ".census-no-plan-index")

    for label, p in (("find-plan.sh", findplan), ("cc-eligible", eligible)):
        if not os.path.exists(p):
            sys.stderr.write("plan-venue-census: %s absent at %s\n" % (label, p))
            sys.exit(3)

    mod = load_eligible(eligible)
    rows = open_plans(findplan, roots, index)

    out = []
    for _st, proj, path, title in rows:
        span_v, _desc, span_toks = mod.classify(mint_span(path, title))
        body_v, body_hits = body_verdict(mod, path)
        out.append({
            "project": proj,
            "path": path,
            "title": title,
            "span_verdict": span_v,
            "span_tokens": span_toks,
            "body_verdict": body_v or "eligible",
            "body_top": body_hits.most_common(4),
        })

    span_counts = collections.Counter(r["span_verdict"] for r in out)
    body_refused = sum(1 for r in out if r["body_verdict"] != "eligible")
    total = len(out)

    if args.json:
        json.dump({
            "total": total,
            "span_counts": dict(span_counts),
            "body_refused": body_refused,
            "body_informative": bool(total) and body_refused != total,
            "rows": out,
        }, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0

    print("plan-venue-census — the venue verdict every open plan's `advance` row would receive")
    print("  repo        %s" % repo)
    print("  plans       %s" % roots)
    print("  open plans  %d" % total)
    if not total:
        print("\n  (no open plans found — nothing to census)")
        return 0

    print("\nARM 1 — the SPEC SPAN cc-discover mints (title | dodRef | source), as cc-eligible sees it")
    for verdict, n in span_counts.most_common():
        print("    %-28s %d" % (verdict, n))
    print("\n  ELIGIBLE bucket — what the lane would send off-box:")
    for r in out:
        if r["span_verdict"] == "eligible":
            print("    %s" % r["title"][:100])
    print("\n  refused, and by which spelling:")
    for r in out:
        if r["span_verdict"] != "eligible":
            print("    %-28s %-18s %s" % (r["span_verdict"].replace("ineligible-", ""),
                                          ",".join(r["span_tokens"])[:18], r["title"][:56]))

    print("\nARM 2 — CONTROL: the SAME table over the plan BODY (the naive 'read more' repair)")
    print("    body refuses %d of %d" % (body_refused, total))
    if body_refused == total:
        print("    → UNINFORMATIVE: it fires on every member of the population, so widening the")
        print("      span to the body is NOT the repair. Venue for this row class needs a per-plan")
        print("      DECLARATION, not a better guess at its text.")
    else:
        print("    → discriminating here: %d of %d bodies read eligible. Re-read this arm before"
              % (total - body_refused, total))
        print("      concluding anything from ARM 1 — the control has changed shape.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
