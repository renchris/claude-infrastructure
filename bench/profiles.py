#!/usr/bin/env python3
"""Per-app rule weightings: one review harness, three different problems.

From the wave's §8: `reso-landing-app` (Next 14, purchased template) is largely a
MARKETING-AESTHETICS problem; `reso-management-app` (Next 16, React 19, Tailwind 4)
is mostly DESIGN-SYSTEM CONFORMANCE, where the deterministic layer does nearly all
the work; `reso-web-app` (Next 13) sits between. The rules are the same everywhere.
What differs is what a finding is WORTH, and that is what this file encodes.

--------------------------------------------------------------------------------
What a weight is allowed to do, and what it is not
--------------------------------------------------------------------------------
A weight orders findings and sizes the model-call queue. It NEVER decides truth: a
2.54:1 contrast ratio is 2.54:1 in a landing page and in a dashboard, and no
profile can make it pass.

So the weights obey three rules, and the first is the one that keeps this file from
becoming a way to make a report look clean:

  1. ACCESSIBILITY AND CORRECTNESS ARE PINNED AT 1.0 IN EVERY PROFILE.
     `contrast`, `touch-target`, `overflow`, `xcheck-zero-ink` and every abstention
     never move. They are not matters of house style, and an app that wants them
     quieter wants a different requirement, not a different weight.
  2. NOTHING IS DELETED. A finding weighted below MUTE_BELOW is marked `muted` and
     reported in its own counted line, not dropped. A silent pass is the failure
     mode this whole pipeline is built to avoid; a weighting scheme that could
     vanish a finding would reintroduce it at the report layer.
  3. THE PAGE-LEVEL JUDGEMENT CALL IS NEVER WEIGHTED TO ZERO. Three of the corpus's
     most valuable findings came from asking a model to look at a clean image with
     nobody looking for anything. Cutting that call converts the reviewer into a
     linter with a screenshot (P5-route T2).

--------------------------------------------------------------------------------
Why the conformance rules are DAMPED on a purchased template
--------------------------------------------------------------------------------
`reso-landing-app` did not author its design system, so `token-drift`,
`grid-violation`, `type-scale` and `radius` drift are measured against tokens the
template never agreed to. Every one of those findings is arithmetically true and
almost all of them are noise -- and ~20% noise is where an AI reviewer loses
credibility regardless of catch rate (§8 item 2). The weighting is how that budget
is spent on a per-app basis rather than by loosening a rule for everyone, which
would blind the dashboard where those same rules are the entire point.

The inverse holds for `reso-management-app`: conformance is what the review is FOR,
so those rules are amplified and the aesthetic questions -- which cost a model call
each -- are damped to the one page-level call that rule 3 protects.

⚠️ These multipliers are ORDINAL AND UNCALIBRATED. They break ties in the intended
direction; they are not evidence about how much worse one class is than another. No
measurement here supports a specific ratio, and the corpus has never had enough
competing findings on one page for the ranking to be exercised. Treat a change to a
number here as free, and a change to rule 1 as a decision.
"""

from __future__ import annotations

# Below this, a finding is MUTED: still reported, in its own counted line, but not
# in the ranked list and never a model call. Never deleted -- see rule 2.
MUTE_BELOW = 0.25

# Ordinal, matching P5-route §3.2's severity weights.
SEVERITY_VALUE = {"high": 2.0, "medium": 1.0, "low": 0.5}

# Pinned at 1.0 in every profile. Correctness and accessibility are not house style.
PINNED = frozenset(
    {
        "contrast",
        "touch-target",
        "overflow",
        "xcheck-zero-ink",
        "xcheck-contrast-varies",
    }
)

PROFILES: dict[str, dict] = {
    "reso-management": {
        "app": "reso-management-app",
        "stack": "Next 16 · React 19 · Tailwind 4",
        "thesis": "design-system conformance; the deterministic layer does nearly all the work",
        "default": 1.0,
        "weights": {
            # Conformance IS the review here.
            "token-drift": 2.0,
            "grid-violation": 1.75,
            "type-scale": 1.75,
            "spacing-rhythm": 1.5,
            "misalignment": 1.5,
            # Aesthetic judgement still happens, but as the one page-level call.
            "hierarchy": 0.75,
            "gestalt": 0.5,
            "readability": 0.75,
            "content-fit": 0.5,
            "semantic-coherence": 1.0,
            "optical-alignment": 0.5,
        },
    },
    "reso-landing": {
        "app": "reso-landing-app",
        "stack": "Next 14 · purchased template",
        "thesis": "marketing aesthetics; the template's tokens are not ours to enforce",
        "default": 1.0,
        "weights": {
            # Measured against tokens this codebase never agreed to -> mostly noise.
            "token-drift": 0.2,
            "grid-violation": 0.2,
            "type-scale": 0.5,
            "spacing-rhythm": 0.5,
            "misalignment": 0.75,
            # What a landing page is actually judged on.
            "hierarchy": 2.0,
            "gestalt": 1.75,
            "readability": 1.5,
            "content-fit": 1.75,
            "semantic-coherence": 1.0,
            "optical-alignment": 1.25,
        },
    },
    "reso-web": {
        "app": "reso-web-app",
        "stack": "Next 13",
        "thesis": "between the two; no weighting evidence either way, so none is invented",
        "default": 1.0,
        "weights": {},
    },
    "default": {
        "app": "(unknown)",
        "stack": "-",
        "thesis": "no per-app knowledge; every rule at face value",
        "default": 1.0,
        "weights": {},
    },
}


def profile(name: str) -> dict:
    if name not in PROFILES:
        raise KeyError(f"unknown profile {name!r}; have {sorted(PROFILES)}")
    return PROFILES[name]


def weight(name: str, rule: str) -> float:
    """The multiplier for one rule under one profile. Pinned rules ignore the map."""
    p = profile(name)
    if rule in PINNED:
        return 1.0
    return float(p["weights"].get(rule, p["default"]))


def score(name: str, finding: dict) -> float:
    """weight x severity. Ordinal only -- it ranks, it does not measure."""
    sev = SEVERITY_VALUE.get(str(finding.get("severity", "medium")), 1.0)
    return weight(name, str(finding.get("rule", ""))) * sev


def rank(name: str, findings: list[dict]) -> list[dict]:
    """Findings with `weight`/`score`/`muted` attached, ordered worst-first.

    Muted findings sort last and are flagged, never removed (rule 2).
    """
    out = []
    for f in findings:
        g = dict(f)
        g["weight"] = weight(name, str(f.get("rule", "")))
        g["score"] = score(name, f)
        g["muted"] = g["weight"] < MUTE_BELOW
        out.append(g)
    out.sort(key=lambda g: (g["muted"], -g["score"], g["rule"], g["target"]))
    return out
