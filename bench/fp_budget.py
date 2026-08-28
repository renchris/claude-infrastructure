#!/usr/bin/env python3
"""The false-positive budget: re-run every rule against the clean control.

~20% false positives is where an AI reviewer loses credibility regardless of its
catch rate, and this is the gate that defends against it. It is the FIRST thing
to run after touching any rule, and the only thing that decides whether a new
rule ships.

Three claims that must stay separate, because collapsing them is how a bound
gets published as a measurement (PIPELINE_SPEC C18):

  1. ABSOLUTE ZERO ON THE CONTROL IS THE SHIP GATE, and it is enforceable at
     n = 1. A rule that fires on a page with no defect will fire on every page.
     No exceptions, no baseline-diff suppression, no per-app weighting -- this
     runs UNWEIGHTED, and asserts that no profile could have hidden a hit.

  2. NO FALSE-POSITIVE *RATE* MAY BE PRINTED BELOW n = 16 CLEAN PAGES. By the
     rule of three, 0 findings over n pages bounds the rate at 3/n: at n = 1
     that is 300%, at n = 8 it is 37.5% -- nearly twice the credibility cliff --
     and 3/16 = 18.75% is the first n strictly under it. Below 16 this prints
     the DEFICIT instead of a rate, and refuses to compute one.

  3. STATE THE BUDGET PER 1,000 SUBJECT-CHECKS, never per run. One real page
     carries ~1,841 subjects against this corpus's ~47, so a per-run zero says
     almost nothing about a real audit. A per-subject rate of 1e-4 -- twenty
     times better than anything measured in this substrate -- still yields ~19
     false findings across a 105-route audit, delivered to an agent that acts on
     them by editing source.

Exit codes: 0 gate passed · 1 a rule fired on a control page · 2 nothing to run.

Usage: python3 fp_budget.py <corpus-dir> [--controls clean,other] [--json <path>]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

import detect_dom
import detect_xcheck
import profiles

# The n at which the rule-of-three bound first sits strictly under the ~20%
# credibility cliff. Below this, a rate is not a measurement, it is a hope.
MIN_N_FOR_A_RATE = 16
CLIFF = 0.20


def collect(corpus: pathlib.Path, controls: list[str]) -> dict:
    dom, dom_census = detect_dom.run(corpus)
    xc, xc_census = detect_xcheck.run(corpus)

    per_page = {}
    for page in controls:
        if page not in dom:
            continue
        findings = [
            f
            for f in list(dom.get(page, [])) + list(xc.get(page, []))
            # `info` carries a resolved abstention, not a claim about a defect.
            if f.get("severity") != "info"
        ]
        census = dict(dom_census.get(page, {}))
        for k, v in xc_census.get(page, {}).items():
            census[k] = census.get(k, 0) + v
        per_page[page] = {"findings": findings, "census": census}
    return per_page


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", default="corpus/out", type=pathlib.Path)
    ap.add_argument(
        "--controls",
        default="clean",
        help="comma-separated page stems known to carry NO defect. Every page "
        "named here is one that shipped and was never touched by a visual-bug "
        "fix, so every finding on it is a false positive by construction.",
    )
    ap.add_argument("--json", type=pathlib.Path, default=None)
    a = ap.parse_args()

    corpus = a.corpus.resolve()
    controls = [c.strip() for c in a.controls.split(",") if c.strip()]
    per_page = collect(corpus, controls)
    if not per_page:
        print(f"no control pages found in {corpus} (looked for {controls})")
        return 2

    n = len(per_page)
    hits = {p: d["findings"] for p, d in per_page.items() if d["findings"]}
    subject_checks = sum(sum(d["census"].values()) for d in per_page.values())
    by_rule: dict[str, int] = {}
    for d in per_page.values():
        for f in d["findings"]:
            by_rule[f["rule"]] = by_rule.get(f["rule"], 0) + 1

    total = sum(by_rule.values())
    print(f"FALSE-POSITIVE BUDGET  ({corpus})")
    print(f"  control pages         {n}")
    print(f"  subject-checks        {subject_checks:,}")
    print(f"  findings on controls  {total}")
    print()

    # --- claim 1: the gate --------------------------------------------------
    if hits:
        print("GATE: FAIL -- a rule fired on a page with no defect.")
        for page, fs in hits.items():
            for f in fs:
                print(f"  [{f['rule']}] {page} :: {f['target']}")
                print(f"      {f['detail'][:150]}")
        print()
        print(
            "  A rule that fires here fires everywhere. Fix the rule, or fix the\n"
            "  control if the control is the thing that is wrong -- but not by\n"
            "  weighting it down: no profile may demote a rule out of this gate."
        )
    else:
        print("GATE: PASS -- zero findings on every control page.")

    # --- claim 1b: assert no profile can launder a hit ----------------------
    laundering = []
    for name in profiles.names():
        prof = profiles.load(name)
        for rule in sorted(set(by_rule) | set(prof.weights)):
            if prof.weight(rule) <= 0:
                laundering.append((name, rule))
    if laundering:
        print()
        print("GATE: FAIL -- a profile weights a rule to zero, which is suppression.")
        for name, rule in laundering:
            print(f"  {name}: {rule} = 0")

    # --- claims 2 and 3: what may be said about the rate --------------------
    print()
    if n < MIN_N_FOR_A_RATE:
        bound = 3 / n
        print(
            f"RATE: NOT COMPUTED. {n} control page(s) is below the {MIN_N_FOR_A_RATE}\n"
            f"  needed for a rule-of-three bound under the {CLIFF:.0%} credibility\n"
            f"  cliff. At n={n} the 95% upper bound would be {bound:.1%}, which is\n"
            f"  {bound / CLIFF:.1f}x the cliff -- a number that would mislead anyone\n"
            f"  who read it as a measurement.\n"
            f"  DEFICIT: {MIN_N_FOR_A_RATE - n} more clean page(s) before this tool\n"
            f"  is allowed to print a rate at all."
        )
    else:
        bound = 3 / n
        print(
            f"RATE: 95% upper bound {bound:.2%} over {n} clean pages "
            f"({'under' if bound < CLIFF else 'OVER'} the {CLIFF:.0%} cliff)."
        )
    per_k = (total / subject_checks * 1000) if subject_checks else 0.0
    print(
        f"BUDGET: {per_k:.3f} false findings per 1,000 subject-checks "
        f"({total} over {subject_checks:,})."
    )
    if subject_checks:
        print(
            f"  Projected over a 105-route audit at ~1,841 subjects/route "
            f"(~193,000 checks): ~{per_k * 193:.0f} false findings."
        )

    report = {
        "corpus": str(corpus),
        "control_pages": sorted(per_page),
        "n": n,
        "subject_checks": subject_checks,
        "findings_on_controls": total,
        "by_rule": by_rule,
        "gate": "fail" if (hits or laundering) else "pass",
        "rate_publishable": n >= MIN_N_FOR_A_RATE,
        "deficit_pages": max(0, MIN_N_FOR_A_RATE - n),
        "per_1000_subject_checks": round(per_k, 4),
    }
    out = a.json or (corpus / "fp_budget.json")
    out.write_text(json.dumps(report, indent=1))
    print(f"\nwrote {out}")
    return 1 if (hits or laundering) else 0


if __name__ == "__main__":
    sys.exit(main())
