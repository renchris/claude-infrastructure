#!/usr/bin/env python3
"""Per-app rule weightings: one review harness, three different problems.

`reso-landing-app` (Next 14, purchased template) is largely a marketing-aesthetics
problem. `reso-management-app` (Next 16, React 19, Tailwind 4) is mostly
design-system conformance, where the deterministic layer does nearly all the work.
`reso-web-app` (Next 13) sits between them. Running one flat rule set over all
three is how a reviewer loses its credibility on the first app it looks at: on a
purchased template, `token-drift` against OUR tokens is not a finding, it is a
restatement of the fact that we bought the template.

THE INVARIANT THAT MAKES THIS SAFE, and the reason a weighting is not a knob:

    A weight can SUPPRESS a finding or REORDER it. It can never CREATE one.

Nothing here runs a detector, lowers a threshold, or relaxes a tolerance. Every
finding a profile can emit was already emitted by a rule that had to survive the
clean control first. So the zero-false-positive result the whole bench rests on
holds under every profile by construction rather than by re-measurement --
`fp_budget.py` asserts exactly that, over every profile, rather than trusting this
paragraph.

The second thing a profile carries is the VLM queue budget, and it is the half
that actually costs money. `reso-management`'s residue is small because the
deterministic layer answers most of its questions; `reso-landing`'s residue IS the
review, because "does this page make me want the thing" is not a rule.

ACCESSIBILITY IS NOT WEIGHTABLE BELOW 1.0 ANYWHERE, and that is a policy, not an
oversight. A marketing page's contrast failure is a contrast failure. The only
axis a profile is allowed to turn down is conformance-to-OUR-design-system, which
is the one axis that is genuinely a claim about which codebase you are in.

Usage: python3 profiles.py [<name>]   # print a profile, or the whole table
"""

from __future__ import annotations

import sys

# --- the rule catalogue ----------------------------------------------------
# Every rule either detector can emit, and the axis it belongs to. A rule absent
# from here is a bug, not a default: `unknown_rules()` reports it rather than
# silently weighting it 1.0, because a new rule that nobody classified is exactly
# the rule that will slip past a profile's suppression and land on a purchased
# template as noise.
AXIS = {
    # design-system conformance -- a claim about OUR tokens, grid and scale
    "spacing-rhythm": "conformance",
    "grid-violation": "conformance",
    "type-scale": "conformance",
    "token-drift": "conformance",
    # correctness -- the render is wrong, in any codebase, under any taste
    "overflow": "correctness",
    "misalignment": "correctness",
    "xcheck-zero-ink": "correctness",
    # accessibility -- never weighted below 1.0, see the module docstring
    "contrast": "accessibility",
    "contrast-indeterminate": "accessibility",
    "touch-target": "accessibility",
    "xcheck-contrast-varies": "accessibility",
    # craft -- true, small, and about whether the thing looks made rather than
    # assembled. Worth most where the page's job is to be looked at.
    "xcheck-optical-centre": "craft",
}

SEVERITY_VALUE = {"high": 3.0, "medium": 2.0, "low": 1.0}

# --- the profiles ----------------------------------------------------------
# `weights` is keyed by AXIS, with optional per-rule overrides in `rules`.
# `queue` is the per-page ceiling on VLM jobs the router may emit.
PROFILES: dict[str, dict] = {
    "default": {
        "app": "(none)",
        "why": "flat weighting; the shape of the findings, with nothing asserted about which app",
        "weights": {
            "conformance": 1.0,
            "correctness": 1.0,
            "accessibility": 1.0,
            "craft": 1.0,
        },
        "rules": {},
        "queue": 3,
    },
    "reso-management": {
        "app": "reso-management-app (Next 16, React 19, Tailwind 4)",
        "why": (
            "design-system conformance. The app owns its tokens, so drift from them is a "
            "real defect rather than a difference of opinion, and the deterministic layer "
            "answers nearly every question this app raises -- which is why its vision "
            "budget is the smallest of the three."
        ),
        "weights": {
            "conformance": 1.6,
            "correctness": 1.3,
            "accessibility": 1.3,
            "craft": 0.8,
        },
        "rules": {},
        "queue": 2,
    },
    "reso-landing": {
        "app": "reso-landing-app (Next 14, purchased template)",
        "why": (
            "marketing aesthetics. The template arrived with its own scale, radii and "
            "palette; measuring those against OUR tokens produces a page of findings that "
            "are all the same finding -- 'this is a template' -- so conformance is turned "
            "down hard and token-drift is suppressed outright. What is left is whether the "
            "page persuades, which no rule asks, so this profile buys the largest queue."
        ),
        "weights": {
            "conformance": 0.4,
            "correctness": 1.2,
            "accessibility": 1.0,
            "craft": 1.5,
        },
        # 0.0 is suppression, and it is reported as such rather than dropped
        # silently: a rule that is off for a reason should still be able to say so.
        "rules": {"token-drift": 0.0},
        "queue": 5,
    },
    "reso-web": {
        "app": "reso-web-app (Next 13)",
        "why": (
            "between the two. Part product surface with our tokens, part marketing; "
            "nothing is turned off, and conformance carries slightly less than it does in "
            "the management app because this codebase predates the token set."
        ),
        "weights": {
            "conformance": 0.9,
            "correctness": 1.2,
            "accessibility": 1.2,
            "craft": 1.1,
        },
        "rules": {},
        "queue": 3,
    },
}

ACCESSIBILITY_FLOOR = 1.0


def get(name: str) -> dict:
    if name not in PROFILES:
        raise SystemExit(
            f"unknown profile {name!r}; have {', '.join(sorted(PROFILES))}"
        )
    return PROFILES[name]


def weight_of(profile: dict, rule: str) -> float:
    """The multiplier this profile puts on one rule.

    An unclassified rule weights 1.0 -- fail-open on VISIBILITY is right here,
    because the failure mode of guessing low is a suppressed real finding and the
    failure mode of guessing high is one line of noise. `unknown_rules()` still
    reports it so the omission gets fixed rather than absorbed.
    """
    if rule in profile["rules"]:
        return float(profile["rules"][rule])
    axis = AXIS.get(rule)
    if axis is None:
        return 1.0
    w = float(profile["weights"].get(axis, 1.0))
    if axis == "accessibility":
        return max(w, ACCESSIBILITY_FLOOR)
    return w


def apply(profile: dict, findings: list[dict]) -> list[dict]:
    """Rank and suppress. NEVER add -- see the module docstring's invariant.

    Returns a new list, each finding carrying `weight` and `priority`, sorted
    most-important first, with weight-0 rules removed. The input list is not
    mutated, so the same findings can be scored under several profiles and
    compared, which is what `fp_budget.py --all-profiles` does.
    """
    out = []
    for f in findings:
        w = weight_of(profile, f["rule"])
        if w <= 0.0:
            continue
        g = dict(f)
        g["weight"] = round(w, 3)
        g["priority"] = round(
            w * SEVERITY_VALUE.get(f.get("severity", "medium"), 2.0), 3
        )
        out.append(g)
    out.sort(key=lambda g: (-g["priority"], g["rule"], g["target"]))
    return out


def suppressed_rules(profile: dict) -> list[str]:
    return sorted(r for r, w in profile["rules"].items() if float(w) <= 0.0)


def unknown_rules(rules) -> list[str]:
    return sorted({r for r in rules if r not in AXIS})


def main(argv: list[str]) -> None:
    names = argv[1:] or sorted(PROFILES)
    for n in names:
        p = get(n)
        print(f"\n{n}  ->  {p['app']}")
        print(f"  {p['why']}")
        print(f"  vlm queue budget: {p['queue']} job(s)/page")
        for axis in ("conformance", "correctness", "accessibility", "craft"):
            rules = sorted(r for r, a in AXIS.items() if a == axis)
            print(f"  {axis:15} x{p['weights'].get(axis, 1.0):<5}", end="")
            print(
                "  ".join(
                    f"{r}{'' if weight_of(p, r) == p['weights'].get(axis, 1.0) else f'(x{weight_of(p, r):g})'}"
                    for r in rules
                )
            )
        supp = suppressed_rules(p)
        if supp:
            print(f"  suppressed:     {', '.join(supp)}")


if __name__ == "__main__":
    main(sys.argv)
