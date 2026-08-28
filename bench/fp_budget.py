#!/usr/bin/env python3
"""The false-positive budget: every rule, re-run against the clean control.

~20% false positives is where an AI reviewer loses credibility regardless of its
catch rate, and a reviewer nobody believes is worse than no reviewer, because the
real findings go unread alongside the invented ones. The two zero-FP runs in the
2026-08-26 wave are the baseline this defends. **Every rule added must clear this
before it ships**, and "clear" means two different things, both checked here:

  CONTROL   zero findings on clean.html. A rule that fires on the control is
            overfitted or noisy, and its findings on every other page are worth
            nothing, because there is no way to tell which of them are the same
            noise. This is a HARD gate: the budget is zero, not 20%.

  OFF-TARGET  on a defect page, findings that do not name the injected defect's
            target. These are the honest grey zone -- a page with one injected
            defect can carry a real second problem, and the corpus itself found
            three of those. So this is a BUDGET, not a gate: it is reported per
            rule and against the 20% credibility floor, and a rule that spends it
            has to justify each one.

The control run is what made this instrument trustworthy in the first place. The
first version of the corpus flagged four defects on the hand-authored baseline;
three were real WCAG failures nobody had noticed, and the deterministic linter
earned its keep before it ever saw an injected defect. The fourth was noise. You
cannot tell those apart without running the control, and a corpus that has not
run its own control is not allowed to grade anything.

Exit 0 when the control is quiet, 1 when it is not.

Usage:  python3 fp_budget.py <corpus-dir> [--profile NAME] [--budget 0.20]
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib

import profiles

CREDIBILITY_FLOOR = 0.20


def load(corpus: pathlib.Path) -> tuple[dict, dict, dict]:
    manifest = json.loads((corpus / "manifest.json").read_text())
    findings: dict[str, list[dict]] = collections.defaultdict(list)
    for name in ("findings_dom.json", "findings_xcheck.json"):
        path = corpus / name
        if not path.exists():
            raise SystemExit(
                f"{name} is absent. An absent findings file and an empty one are "
                f"different states, and only one of them is evidence -- run the "
                f"detector rather than reading its silence as a clean page."
            )
        for page, fs in json.loads(path.read_text()).items():
            findings[page].extend(fs)
    ground = {d["id"]: d for d in manifest["defects"]}
    return manifest, dict(findings), ground


def target_matches(finding_target: str, defect_target: str) -> bool:
    """Does a finding's element path name the defect's CSS selector?

    The corpus states targets as selectors (`.kpi-card:nth-child(3)`) and the
    detectors emit element paths (`div.kpi-row... > div.kpi-card:nth-of-type(3)`).
    Comparing on the class token plus any index is enough to tell "named the right
    element" from "named some other element", which is all this needs to decide.
    """
    cls = [
        part.split(":")[0]
        for part in defect_target.replace(" ", ".").split(".")
        if part and not part.startswith("nth")
    ]
    if not all(c in finding_target for c in cls):
        return False
    for tok in defect_target.split(":"):
        if tok.startswith("nth-child(") or tok.startswith("nth-of-type("):
            n = tok[tok.find("(") + 1 : tok.find(")")]
            if f"nth-of-type({n})" not in finding_target:
                return False
    return True


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "corpus", type=pathlib.Path, nargs="?", default=pathlib.Path("corpus/out")
    )
    ap.add_argument("--profile", default=profiles.DEFAULT)
    ap.add_argument("--budget", type=float, default=CREDIBILITY_FLOOR)
    a = ap.parse_args()

    corpus = a.corpus.resolve()
    prof = profiles.get(a.profile)
    bad = profiles.validate()
    for b in bad:
        print(f"INVALID PROFILE  {b}")

    manifest, findings, ground = load(corpus)
    control = manifest.get("control", "clean.html").removesuffix(".html")

    # --- the hard gate ------------------------------------------------------
    ctrl = [f for f in findings.get(control, []) if prof.keeps(f)]
    # An abstention is not a claim. `contrast-indeterminate` on a gradient is the
    # rule working, and counting it as a false positive would train the layer out
    # of the one output that makes the whole architecture safe.
    ctrl_claims = [f for f in ctrl if not f["rule"].endswith("-indeterminate")]
    ctrl_abstain = [f for f in ctrl if f["rule"].endswith("-indeterminate")]

    print(f"FALSE-POSITIVE BUDGET   profile {prof.name}   corpus {corpus}")
    print(
        f"  rules exercised: {len({f['rule'] for fs in findings.values() for f in fs})}"
    )
    print()
    print(
        f"CONTROL  {control}.html  -> {len(ctrl_claims)} claim(s), "
        f"{len(ctrl_abstain)} abstention(s)"
    )
    for f in ctrl_claims:
        print(f"    FP  [{f['rule']}] {f['target']}")
        print(f"        {f['detail'][:150]}")
    for f in ctrl_abstain:
        print(f"    ok  [{f['rule']}] {f['target'][:70]}  (abstention, not a claim)")

    # --- the budget ---------------------------------------------------------
    print()
    print("PER-PAGE, against the injected ground truth")
    per_rule = collections.Counter()
    per_rule_off = collections.Counter()
    hits = misses = 0
    baseline = {(f["rule"], f["target"]) for f in findings.get(control, [])}
    for page, fs in sorted(findings.items()):
        if page == control:
            continue
        gt = ground.get(page)
        novel = [
            f for f in fs if (f["rule"], f["target"]) not in baseline and prof.keeps(f)
        ]
        # A defect's blast radius is part of its ground truth: a rule that reports
        # every element the injected change actually affects has found the defect
        # more than once, not found a spurious one. `collateral` carries a reason
        # per element so this cannot be used to launder a real false positive.
        gt_targets = [gt["target"], *gt.get("collateral", {})] if gt else []
        on = [
            f for f in novel if any(target_matches(f["target"], t) for t in gt_targets)
        ]
        off = [f for f in novel if f not in on]
        for f in novel:
            per_rule[f["rule"]] += 1
        for f in off:
            per_rule_off[f["rule"]] += 1
        hits += 1 if on else 0
        misses += 0 if on else 1
        flag = "  " if on else "--"
        print(
            f" {flag} {page:24} {len(on)} on-target, {len(off)} off-target"
            f"   [{gt['detectable_by'] if gt else '?'}]"
        )
        for f in off:
            print(f"        off  [{f['rule']}] {f['target'][:60]}")

    print()
    print(
        "PER-RULE off-target share  (the 20% credibility floor is per rule, "
        "not per run)"
    )
    over = []
    for rule, n in sorted(per_rule.items(), key=lambda kv: -kv[1]):
        off = per_rule_off[rule]
        share = off / n if n else 0.0
        mark = "  "
        if share > a.budget:
            mark = "!!"
            over.append((rule, share))
        print(f"  {mark} {rule:28} {n:3d} novel, {off:3d} off-target  {share:5.0%}")

    print()
    print(f"pages with an on-target finding: {hits}/{hits + misses}")
    if over:
        print(f"OVER BUDGET: {', '.join(f'{r} at {s:.0%}' for r, s in over)}")
        print(
            "  Off-target is a budget, not a gate -- but each one now needs a "
            "reason, and 'the page really does have a second defect' is only "
            "a reason once someone has looked."
        )
    if ctrl_claims:
        print()
        print(
            f"FAIL: {len(ctrl_claims)} finding(s) on the clean control. The "
            f"budget there is zero: a rule that fires on the control makes its "
            f"findings everywhere else unreadable, because nothing distinguishes "
            f"them from the same noise."
        )
        raise SystemExit(1)
    print()
    print("PASS: the control is quiet, so the findings above are worth reading.")


if __name__ == "__main__":
    main()
