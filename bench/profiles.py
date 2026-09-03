#!/usr/bin/env python3
"""Per-app rule weightings: one review harness, three different problems.

The corpus measures whether a rule is CORRECT. A weighting decides whether a
correct finding is worth showing, and that answer is different per application:

  reso-landing-app     Next 14, a purchased template. Largely a marketing-
                       aesthetics problem. Its design tokens are the vendor's,
                       not ours, so token-drift and grid-violation are describing
                       someone else's system and firing them at full weight
                       produces a wall of true-but-unactionable findings -- the
                       fastest way to spend the ~20% credibility budget without
                       a single false positive. What matters is whether the page
                       reads well, which is the vision layer's question.

  reso-management-app  Next 16, React 19, Tailwind 4. Mostly design-system
                       conformance, and the deterministic layer does nearly all
                       the work. Token drift, grid, scale and rhythm ARE the
                       review here; each one is a concrete diff against a system
                       we own. The aesthetic agenda is close to off, because a
                       dense internal tool that conforms is finished.

  reso-web-app         Next 13. Sits between the two on both axes.

Two knobs, deliberately, because they are the two independent questions:

  `weights`  multiplies a deterministic finding's severity. 0.0 SUPPRESSES the
             rule for this app -- it is not reported and cannot spend the false-
             positive budget. Anything above 1.0 promotes.
  `agenda`   the standing questions the deterministic layer cannot answer by
             construction, which the router sends to the vision layer as CROPS.
             This is a per-app agenda rather than a finding, so it is a question
             and never a claim -- see fp_budget.py on why that distinction is
             what keeps the budget honest.

Weights are stated per rule, never inferred from severity, so a change of
emphasis is a diff in this file and not a retuned threshold somewhere else.
"""

from __future__ import annotations

# Every rule either detector can emit, with the substrate it comes from. A rule
# absent from a profile's `weights` inherits 1.0; listing all of them here keeps
# "we forgot to weight this" distinguishable from "we weighted it at 1.0".
RULES = {
    # --- deterministic, from computed styles / box model (detect_dom) ---------
    "spacing-rhythm": "dom",
    "grid-violation": "dom",
    "type-scale": "dom",
    "token-drift": "dom",
    "contrast": "dom",
    "overflow": "dom",
    "touch-target": "dom",
    "misalignment": "dom",
    # The abstention. Never weighted to 0 anywhere: suppressing it converts an
    # honest "UNVERIFIED" into a silent pass, which is the one failure mode this
    # whole pipeline exists to prevent.
    "contrast-indeterminate": "abstention",
    # --- the DOM-vs-pixels comparator (detect_xcheck) ------------------------
    "xcheck-zero-ink": "xcheck",
    "xcheck-optical-centre": "xcheck",
    "xcheck-contrast-varies": "xcheck",
}

# Questions with no number in the answer. Each names a DOM selector fragment so
# the router can crop to it exactly -- the grounder supplies identity, the DOM
# supplies geometry, and no model is ever asked to draw a box.
AGENDA = {
    "hierarchy": (
        "actions",
        "Does the eye land on the primary action first? Compare the visual weight "
        "of the actions in this group against which one is semantically primary.",
    ),
    "hero-legibility": (
        "hero",
        "Does this hero read cleanly at a glance -- does the text hold against its "
        "backdrop across the full width, and does the headline outrank the caption?",
    ),
    "scan-order": (
        "kpi-row",
        "Do these tiles read as one row of peers, or does one pull attention out of "
        "turn? Judge the grouping and the reading order, not the spacing.",
    ),
    "table-legibility": (
        "panel",
        "Does this table's promise match what it shows -- do the columns line up for "
        "comparison, and does any caption describe styling that is not present?",
    ),
}

PROFILES: dict[str, dict] = {
    "default": {
        "note": "Unweighted. Every rule at face value; used by the corpus itself.",
        "weights": {},
        "agenda": [],
    },
    "reso-management-app": {
        "note": (
            "Design-system conformance. The deterministic layer is the review; the "
            "vision layer sees only what a rule abstained on."
        ),
        "weights": {
            "token-drift": 2.0,
            "grid-violation": 2.0,
            "type-scale": 1.75,
            "spacing-rhythm": 1.5,
            "misalignment": 1.5,
            "contrast": 1.0,
            "overflow": 1.0,
            "touch-target": 1.0,
            "xcheck-zero-ink": 1.0,
            "xcheck-contrast-varies": 1.0,
            # A dense internal tool has few bespoke marks and the compensation is a
            # component-library concern, not a per-screen one. Real, and rarely
            # this app's job to fix.
            "xcheck-optical-centre": 0.5,
        },
        # Nearly nothing: a conforming dense tool is finished. Only the relational
        # question that no conformance rule can express.
        "agenda": ["hierarchy"],
    },
    "reso-landing-app": {
        "note": (
            "Marketing aesthetics on a purchased template. Conformance rules "
            "describe the vendor's system, so they are suppressed or demoted; the "
            "review is mostly the vision layer's."
        ),
        "weights": {
            # Suppressed, not demoted. These measure drift from a token set we do
            # not own, so every finding is true and none is actionable.
            "token-drift": 0.0,
            "grid-violation": 0.0,
            # A purchased template legitimately runs a wider type scale and a
            # looser rhythm than a design system does. Kept, well below the fold.
            "type-scale": 0.4,
            "spacing-rhythm": 0.4,
            "misalignment": 0.5,
            # Correctness, not taste. These bind everywhere and are never demoted:
            # a marketing page that fails WCAG or clips its copy is broken however
            # good it looks.
            "contrast": 1.5,
            "overflow": 1.5,
            "touch-target": 1.5,
            "xcheck-zero-ink": 1.5,
            "xcheck-contrast-varies": 1.5,
            # Marketing pages are where bespoke marks and optical centring live.
            "xcheck-optical-centre": 1.5,
        },
        "agenda": ["hierarchy", "hero-legibility", "scan-order"],
    },
    "reso-web-app": {
        "note": "Between the two: a design system exists, and the pages still sell.",
        "weights": {
            "token-drift": 1.25,
            "grid-violation": 1.0,
            "type-scale": 1.0,
            "spacing-rhythm": 1.0,
            "misalignment": 1.0,
            "contrast": 1.25,
            "overflow": 1.25,
            "touch-target": 1.25,
            "xcheck-zero-ink": 1.25,
            "xcheck-contrast-varies": 1.25,
            "xcheck-optical-centre": 1.0,
        },
        "agenda": ["hierarchy", "hero-legibility"],
    },
}

SEVERITY_RANK = {"low": 1.0, "medium": 2.0, "high": 3.0}


def resolve(name: str) -> dict:
    if name not in PROFILES:
        raise SystemExit(
            f"unknown profile {name!r}; have {', '.join(sorted(PROFILES))}"
        )
    return PROFILES[name]


def weight_of(profile: dict, rule: str) -> float:
    """A rule's multiplier under this profile. Unlisted rules sit at 1.0.

    The abstention is pinned at 1.0 and cannot be suppressed: a profile that
    silenced it would convert `UNVERIFIED` into a confident pass, and an
    abstention routes to the vision layer where a pass routes nowhere.
    """
    if RULES.get(rule) == "abstention":
        return 1.0
    return float(profile.get("weights", {}).get(rule, 1.0))


def score(profile: dict, finding: dict) -> float:
    """Weighted severity, for ranking. 0.0 means suppressed for this app."""
    base = SEVERITY_RANK.get(finding.get("severity", "medium"), 2.0)
    return base * weight_of(profile, finding["rule"])


def apply(profile: dict, findings: list[dict]) -> list[dict]:
    """Drop what this app suppresses, annotate the rest, rank by weighted severity."""
    kept = []
    for f in findings:
        w = weight_of(profile, f["rule"])
        if w == 0.0:
            continue
        kept.append({**f, "weight": w, "score": round(score(profile, f), 2)})
    return sorted(kept, key=lambda f: -f["score"])


if __name__ == "__main__":
    print(f"{'rule':26} {'substrate':11} " + " ".join(f"{p:>20}" for p in PROFILES))
    for rule, sub in RULES.items():
        cells = " ".join(f"{weight_of(PROFILES[p], rule):>20.2f}" for p in PROFILES)
        print(f"{rule:26} {sub:11} {cells}")
    print()
    for name, p in PROFILES.items():
        print(f"{name:22} agenda: {', '.join(p['agenda']) or '(none)'}")
