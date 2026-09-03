#!/usr/bin/env python3
"""The false-positive budget: re-run every rule against the clean control.

~20% false positives is where an AI reviewer loses credibility regardless of its
catch rate, and a detector that invents defects is worse than no detector because
an agent ACTS on them. The two zero-FP runs this corpus produced are the baseline
to defend, so this exists to make defending them mechanical: every rule, every
profile, against `clean.html`, on every run, with a non-zero exit when the
baseline slips.

It is a gate rather than a report because the failure it guards is silent. A new
rule that fires on the control still looks productive -- it emits findings, and
they are all wrong. The control is the only thing that can say so.

WHAT COUNTS AS A FALSE POSITIVE, stated precisely, because the distinction is
what keeps the number honest:

  CLAIM      a rule asserting a defect exists at a target. On the clean control,
             every claim is a false positive by construction; the control has no
             defects. This is the budget.

  ABSTENTION `contrast-indeterminate` and its kind. Not a claim -- it asserts the
             opposite, that the rule could not decide. An abstention on the
             control would be a rule declining to answer where an answer exists,
             which is a coverage gap worth seeing, so it is REPORTED but does not
             spend the budget. Counting it as a false positive would create a
             standing incentive to convert abstentions into confident passes,
             which is the exact failure the abstention exists to prevent.

  QUESTION   a tier-2 agenda crop from `route.py`. A standing per-app question
             sent to the vision layer, not derived from any finding and asserting
             nothing. Exempt, and the profile that asks the most questions is not
             thereby the noisiest.

  SIDE EFFECT a novel claim on a DEFECT page that does not sit on the defect's
             declared target. The manifest's own scoring calls this a false
             positive; it is reported separately here and NOT counted, because a
             finding novel-vs-control on a defect page was by definition caused
             by the injected CSS, and whether a true consequence of the injection
             counts against the detector is a per-defect judgement the corpus
             does not encode. Reported so a human can adjudicate; not counted so
             the gate cannot be gamed either way. (Targets match by CLASS, not by
             nth-child index, so a per-index defect matches its whole class.)

Usage:
  python3 fp_budget.py <corpus-dir>            # every profile
  python3 fp_budget.py <corpus-dir> --profile reso-landing-app
Exit status: 0 if every profile holds the zero-claim baseline on the control.
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import re
import sys

import detect_dom
import detect_xcheck
import profiles

# The credibility cliff, from the literature and from this corpus's own argument.
# It is the ceiling, not the target: the defended baseline below it is zero.
FP_CREDIBILITY_CEILING = 0.20
CONTROL = "clean"


def classes_in(selector: str) -> set[str]:
    """Class tokens named by a manifest defect selector, e.g. '.btn-primary'."""
    return set(re.findall(r"\.([A-Za-z0-9_-]+)", selector))


def on_target(path: str, want: set[str]) -> bool:
    """True when the finding's element, or an ancestor of it, carries the classes.

    Subtree-inclusive on purpose: injecting a defect on a container legitimately
    surfaces the finding on the descendant that renders it.
    """
    return not want or want.issubset(set(re.findall(r"\.([A-Za-z0-9_-]+)", path)))


def collect(corpus: pathlib.Path) -> dict[str, list[dict]]:
    tokens = json.loads((corpus / "manifest.json").read_text())["tokens"]
    out = {}
    for f in sorted((corpus / "snapshots").glob("*.json")):
        png = corpus / "shots" / f"{f.stem}.png"
        if not png.exists():
            continue
        snap = json.loads(f.read_text())
        out[f.stem] = detect_dom.find(snap, tokens) + detect_xcheck.check(snap, png)
    return out


def is_claim(f: dict) -> bool:
    return profiles.RULES.get(f["rule"]) != "abstention"


def audit(corpus: pathlib.Path, name: str, raw: dict[str, list[dict]]) -> dict:
    profile = profiles.resolve(name)
    kept = {page: profiles.apply(profile, fs) for page, fs in raw.items()}

    ctrl = kept.get(CONTROL, [])
    ctrl_claims = [f for f in ctrl if is_claim(f)]
    ctrl_abstentions = [f for f in ctrl if not is_claim(f)]

    total_claims = sum(1 for fs in kept.values() for f in fs if is_claim(f))
    rate = len(ctrl_claims) / total_claims if total_claims else 0.0

    # Per-rule, so a newly added rule is visible on its own line rather than
    # averaged into a total that still looks fine.
    per_rule = collections.Counter()
    per_rule_ctrl = collections.Counter()
    for page, fs in kept.items():
        for f in fs:
            if not is_claim(f):
                continue
            per_rule[f["rule"]] += 1
            if page == CONTROL:
                per_rule_ctrl[f["rule"]] += 1

    manifest = json.loads((corpus / "manifest.json").read_text())
    targets = {d["id"]: classes_in(d["target"]) for d in manifest["defects"]}
    base = {(f["rule"], f["target"]) for f in ctrl}
    side = []
    for page, fs in kept.items():
        if page == CONTROL or page not in targets:
            continue
        for f in fs:
            if (
                is_claim(f)
                and (f["rule"], f["target"]) not in base
                and not on_target(f["target"], targets[page])
            ):
                side.append({"page": page, **f})

    return {
        "profile": name,
        "control_claims": ctrl_claims,
        "control_abstentions": ctrl_abstentions,
        "total_claims": total_claims,
        "fp_rate": rate,
        "per_rule": dict(per_rule),
        "per_rule_control": dict(per_rule_ctrl),
        "side_effects": side,
        "pass": not ctrl_claims,
    }


def report(a: dict) -> None:
    verdict = "PASS" if a["pass"] else "FAIL"
    print(f"=== {a['profile']:22} {verdict}")
    print(
        f"    control claims   {len(a['control_claims']):3d}   "
        f"(budget 0; ceiling {FP_CREDIBILITY_CEILING:.0%} of "
        f"{a['total_claims']} total claims)"
    )
    print(f"    FP rate          {a['fp_rate']:6.1%}")
    if a["control_abstentions"]:
        print(
            f"    abstentions      {len(a['control_abstentions']):3d}   "
            f"on the control -- reported, not counted"
        )
    for f in a["control_claims"]:
        print(f"    FALSE POSITIVE   [{f['rule']}] {f['target']}")
        print(f"                     {f['detail'][:110]}")
    print(f"    {'rule':26} {'fired':>6} {'on control':>11}")
    for rule in sorted(a["per_rule"], key=lambda r: -a["per_rule"][r]):
        n_c = a["per_rule_control"].get(rule, 0)
        flag = "  <-- FP" if n_c else ""
        print(f"    {rule:26} {a['per_rule'][rule]:>6} {n_c:>11}{flag}")
    if a["side_effects"]:
        print(
            f"    side effects     {len(a['side_effects']):3d}   (reported, not counted)"
        )
        for f in a["side_effects"]:
            print(f"      {f['page']:22} [{f['rule']}] {f['target'][:46]}")
    print()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path, nargs="?", default="corpus/out")
    ap.add_argument("--profile", default=None, help="default: every profile")
    a = ap.parse_args()

    corpus = pathlib.Path(a.corpus).resolve()
    raw = collect(corpus)
    if CONTROL not in raw:
        sys.exit(f"no control page {CONTROL!r} under {corpus / 'snapshots'}")

    names = [a.profile] if a.profile else list(profiles.PROFILES)
    audits = [audit(corpus, n, raw) for n in names]
    for x in audits:
        report(x)

    (corpus / "fp_budget.json").write_text(
        json.dumps(
            {
                "ceiling": FP_CREDIBILITY_CEILING,
                "profiles": {
                    x["profile"]: {k: v for k, v in x.items() if k != "profile"}
                    for x in audits
                },
            },
            indent=1,
        )
    )

    bad = [x["profile"] for x in audits if not x["pass"]]
    if bad:
        sys.exit(f"FAIL: control claims under {', '.join(bad)}")
    print(f"OK: {len(audits)} profile(s) hold the zero-claim baseline on the control.")


if __name__ == "__main__":
    main()
