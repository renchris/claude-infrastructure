#!/usr/bin/env python3
"""The false-positive ship gate: every rule, re-run against the clean control.

Around 20% false positives is where an AI reviewer loses credibility regardless
of its catch rate, and a detector that invents defects is worse than no detector
because an agent *acts* on them. So this is the gate every new rule has to pass
before it ships, and it is deliberately the least clever file here.

**Three claims that must stay separate, because collapsing them is how a
comfortable number gets quoted:**

1. **Absolute zero asserted findings on the control is the gate, and it is
   enforceable at n = 1.** A rule that fires on a page with no defect will fire on
   every page. No exceptions, no baseline-diff suppression -- suppressing a
   control finding by diffing it against itself is how the rule survives.

2. **No false-positive RATE may be printed below n = 16 clean pages.** With the
   rule of three, 3/8 bounds the rate at 37.5% and 3/16 is the first n strictly
   under the ~20% cliff. A rate computed on fewer pages is a number whose
   confidence interval contains the abandonment threshold, and printing it
   anyway is the whole failure this file exists to prevent. Below 16 it prints
   the bound and refuses the rate.

3. **The budget is stated per 1,000 SUBJECT-CHECKS, never per run.** A real page
   censuses ~1,841 subjects against this corpus's ~50, so a per-run rate is a
   number about the corpus rather than about the app. At ~193,000 subject-checks
   per audit, a per-subject rate of 1e-4 -- twenty times better than anything
   measured in this substrate -- still delivers ~19 false findings to an agent
   that acts on them by editing source.

**An abstention is not a false positive.** `INDETERMINATE` asserts nothing; it is
the router's queue and its cost is images, not credibility. The two are counted
and reported separately, and conflating them would push the pipeline toward
silent passes, which is the strictly worse failure: an abstention routes
somewhere, a pass routes nowhere.

⚠️ **What this gate cannot tell you.** The control is one 106-line page of ~50
elements, and false-positive supply grows with subject count rather than page
count, so zero here was measured at roughly 1/35th the subject density of the
target. The gate is necessary and it is not sufficient. The instrument that would
settle it is a mined corpus of clean screens that shipped and were never
subsequently touched by a visual-bug fix -- every finding on that set is a false
positive by construction, at zero labelling cost. Point `--control-dir` at it.

Usage:
  python3 fp_budget.py <corpus-dir> [--x2] [--control-dir DIR] [--app NAME]
Exit: 0 gate passed · 1 gate FAILED (an asserted finding on a clean page)
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

import detect_dom
import detect_xcheck
import profiles

# The rule of three: with zero events in n trials, the 95% upper bound on the
# rate is about 3/n. Below this n the bound still contains the credibility cliff.
MIN_N_FOR_A_RATE = 16
CREDIBILITY_CLIFF = 0.20


def run_control(corpus: pathlib.Path, page: str, tokens: dict, app: str) -> dict:
    snap = json.loads((corpus / "snapshots" / f"{page}.json").read_text())
    png = corpus / "shots" / f"{page}.png"

    dstats: dict = {}
    findings = detect_dom.find(snap, tokens, dstats)
    subject_checks = dstats.get("subject_checks", 0)

    if png.exists():
        xstats: dict = {}
        findings += detect_xcheck.check(snap, png, xstats)
        subject_checks += xstats.get("subject_checks", 0)

    findings = profiles.weigh(findings, app)
    return {
        "page": page,
        "subject_checks": subject_checks,
        "elements": dstats.get("elements", 0),
        "asserted": [f for f in findings if f["verdict"] == "asserted"],
        "indeterminate": [f for f in findings if f["verdict"] != "asserted"],
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", default="corpus/out", type=pathlib.Path)
    ap.add_argument(
        "--control-dir",
        type=pathlib.Path,
        help="a directory of MINED clean pages (snapshots/ + shots/), the real denominator",
    )
    ap.add_argument("--app", default="default")
    ap.add_argument(
        "--x2",
        action="store_true",
        help="include the X2 optical-centre arm (off by default, as it ships)",
    )
    a = ap.parse_args()
    corpus = a.corpus.resolve()
    tokens = json.loads((corpus / "manifest.json").read_text())["tokens"]

    # detect_xcheck reads its own flag off argv at import; this is the one place
    # that decides, so the gate cannot disagree with the detector about what ran.
    detect_xcheck.X2_ENABLED = a.x2

    controls = [("clean", corpus)]
    if a.control_dir:
        d = a.control_dir.resolve()
        controls += [(p.stem, d) for p in sorted((d / "snapshots").glob("*.json"))]

    runs = [run_control(root, page, tokens, a.app) for page, root in controls]
    n = len(runs)
    total_subjects = sum(r["subject_checks"] for r in runs)
    fps = [(r["page"], f) for r in runs for f in r["asserted"]]
    abstentions = sum(len(r["indeterminate"]) for r in runs)

    print(
        f"FALSE-POSITIVE BUDGET   profile={a.app}   X2={'on' if detect_xcheck.X2_ENABLED else 'off'}"
    )
    print(f"  clean pages (n)          {n}")
    print(
        f"  subject-checks           {total_subjects:,}  ({total_subjects // max(n, 1):,}/page)"
    )
    print(
        f"  ASSERTED on a clean page {len(fps)}   <- the gate; it is zero or it fails"
    )
    print(
        f"  abstentions              {abstentions}   (not false positives: they assert nothing)"
    )

    for page, f in fps:
        print(f"    FP  {page:20} [{f['rule']}] {f['target']}")
        print(f"        {f['detail'][:150]}")

    print()
    if len(fps) == 0:
        bound = 3.0 / n
        per_1k = 3000.0 / total_subjects if total_subjects else float("nan")
        # The per-subject bound is admissible at any n -- it is a statement about
        # this many subject-checks, and subject-checks are what an audit spends.
        # The per-PAGE rate is the one with the cliff in its interval.
        print(f"  95% upper bound, per 1,000 subject-checks  {per_1k:.2f}")
        if n < MIN_N_FOR_A_RATE:
            print(
                f"\n  PER-PAGE RATE WITHHELD. n={n} < {MIN_N_FOR_A_RATE}. The rule of "
                f"three bounds it at 3/{n}, whose interval still contains the "
                f"~{CREDIBILITY_CLIFF:.0%} credibility cliff, so any rate printed here "
                f"would be a number that cannot distinguish 'safe' from 'abandon'.\n"
                f"  Fix the denominator, not the wording: mine clean pages that "
                f"shipped and were never touched by a visual-bug fix, then\n"
                f"    python3 fp_budget.py {a.corpus} --control-dir <mined>"
            )
        else:
            print(
                f"\n  Per-page rate admissible at n={n}: bound {bound * 100:.1f}% is "
                f"strictly under the {CREDIBILITY_CLIFF:.0%} cliff."
            )
        print("\nGATE PASSED — zero asserted findings on every clean page.")
        return 0

    print(
        f"GATE FAILED — {len(fps)} asserted finding(s) on a clean page. A rule that "
        f"fires where there is no defect fires everywhere, and its findings on the "
        f"defect pages are worth nothing. Fix the rule or make it abstain; do NOT "
        f"suppress it by diffing against this same control."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
