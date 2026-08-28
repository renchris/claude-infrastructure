#!/usr/bin/env python3
"""Per-app rule weightings: one review harness, three different problems.

`reso-landing-app` is a purchased Next 14 template, and its conformance is
someone else's design system. Reporting that its corner radii disagree with each
other is true, unactionable, and arrives by the hundred -- the question that
matters there is whether the marketing page *works*, which is a judgement.
`reso-management-app` is Next 16 / React 19 / Tailwind 4 and is almost entirely a
design-system conformance problem, which is exactly what the deterministic layer
is good at, so its residue for the vision layer is the smallest of the three.
`reso-web-app` (Next 13) sits between them.

A weight does three concrete things and nothing else:

  1. **Suppression.** Weight 0 drops the finding before it is reported. The count
     of suppressed findings is always printed, because a filter that hides its own
     activity is indistinguishable from a detector that found nothing.
  2. **Ordering.** score = severity(2/1/0.5) x weight. This is what decides which
     cluster wins a region call when a page has more clusters than PER_PAGE_MAX.
  3. **Routing.** An abstention whose rule is suppressed does not earn a model
     call. Down-weighting a rule and then paying 1,600 visual tokens to ask a
     model about its abstention would spend the budget on the axis the profile
     just said it does not care about.

Weights are ORDINAL AND UNVERIFIED as a ranking, in the same sense P5 marks the
2/1/0.5 severity weights: they have never had to choose between three competing
clusters on one page, because the corpus has never produced three. The probe that
would settle them is a corpus page carrying simultaneous conformance and
correctness findings under the landing profile, checking that the correctness
cluster is the one picked. What is NOT a judgement call, and is the load-bearing
half, is which rules may be zeroed at all: only conformance rules ever are.
A correctness rule -- contrast, overflow, touch-target, and every cross-check arm
-- carries weight 1.0 in every profile, because a profile is a statement about
what is worth someone's attention, never about what is true.

Usage:  python3 profiles.py [name]        # print a profile
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field

# The six T2 question classes (P5 s2). Each is on the list because the corpus
# measured a defect in it that no rule found.
T2_ALL = (
    "hierarchy",
    "gestalt",
    "content-fit",
    "semantic-coherence",
    "optical-alignment",
    "readability",
)

# Rules whose weight may never be lowered. These are correctness, not taste: a
# 2.54:1 contrast ratio is a broken page on a marketing site and on a dashboard
# alike, and a profile that could silence one would be a preference overriding a
# fact.
CORRECTNESS = frozenset(
    {
        "contrast",
        "contrast-indeterminate",
        "overflow",
        "touch-target",
        "xcheck-zero-ink",
        "xcheck-contrast-varies",
        "xcheck-contrast-indeterminate",
        "xcheck-optical-centre",
    }
)

# Everything the two detectors can emit. Listed explicitly so that adding a rule
# without deciding its weight fails loudly in `validate()` rather than defaulting
# to 1.0 in every profile and quietly changing three apps' review at once.
ALL_RULES = frozenset(
    CORRECTNESS
    | {
        "spacing-rhythm",
        "grid-violation",
        "type-scale",
        "token-drift",
        "misalignment",
    }
)

SEVERITY_WEIGHT = {"high": 2.0, "medium": 1.0, "low": 0.5}


@dataclass(frozen=True)
class Profile:
    name: str
    stack: str
    # Where the app's design tokens live. Absent is not a soft failure: without
    # it `token-drift` degrades from a set difference to a histogram, and the
    # router reports coverage "partial-no-token-source" rather than letting the
    # class silently empty.
    token_source: str | None
    rationale: str
    weights: dict[str, float]
    t2_classes: tuple[str, ...]
    per_page_max: int
    notes: str = ""
    unverified: tuple[str, ...] = field(default_factory=tuple)

    def weight(self, rule: str) -> float:
        return self.weights.get(rule, 1.0)

    def score(self, finding: dict) -> float:
        sev = SEVERITY_WEIGHT.get(finding.get("severity", "medium"), 1.0)
        return sev * self.weight(finding["rule"])

    def keeps(self, finding: dict) -> bool:
        return self.weight(finding["rule"]) > 0.0


# Conformance rules only -- see CORRECTNESS for the ones no profile may touch.
_FULL = {
    "spacing-rhythm": 1.0,
    "grid-violation": 1.0,
    "type-scale": 1.0,
    "token-drift": 1.0,
    "misalignment": 1.0,
}

PROFILES: dict[str, Profile] = {
    "reso-landing-app": Profile(
        name="reso-landing-app",
        stack="Next 14, purchased template",
        token_source="tailwind.config.js",
        rationale=(
            "Marketing aesthetics. The template's internal conformance is a "
            "system we did not author and will not change, so conformance "
            "findings here are true and unactionable, and they arrive in volume "
            "large enough to bury the correctness findings underneath them. "
            "grid-violation is zeroed outright rather than lowered: a purchased "
            "template does not use our 8px grid, so the rule's premise -- that "
            "the page has one grid it is departing from -- is false on this app, "
            "and a rule whose premise is false does not produce weak findings, it "
            "produces noise at full confidence."
        ),
        weights={
            **_FULL,
            "grid-violation": 0.0,
            "token-drift": 0.25,
            "type-scale": 0.25,
            "spacing-rhythm": 0.5,
            "misalignment": 0.5,
        },
        t2_classes=("hierarchy", "gestalt", "readability"),
        per_page_max=2,
    ),
    "reso-management-app": Profile(
        name="reso-management-app",
        stack="Next 16, React 19, Tailwind 4",
        # Tailwind 4 is CSS-first; there is no tailwind.config.*.
        token_source="src/app/globals.css @theme",
        rationale=(
            "Design-system conformance. We own the system, so every conformance "
            "finding is directly actionable and the deterministic layer does "
            "nearly all the work -- which is why this profile spends its model "
            "budget on the two classes rules cannot reach at all, and buys only "
            "one region call per page. The screen is strongest here, so the "
            "residue is smallest; a page needing two region calls on this app is "
            "evidence about the rules, not about the page."
        ),
        weights=dict(_FULL),
        t2_classes=("semantic-coherence", "content-fit"),
        per_page_max=1,
    ),
    "reso-web-app": Profile(
        name="reso-web-app",
        stack="Next 13",
        token_source=None,
        rationale=(
            "Between the two. Conformance is ours but the system is older and "
            "less uniformly applied, so conformance findings are actionable more "
            "often than on the template and less often than on the dashboard."
        ),
        weights={
            **_FULL,
            "token-drift": 0.75,
            "type-scale": 0.75,
            "grid-violation": 0.75,
        },
        t2_classes=T2_ALL,
        per_page_max=2,
        notes=(
            "token_source is unresolved. Until it is, token-drift cannot be a set "
            "difference against a palette and the router reports coverage "
            "'partial-no-token-source' rather than an empty class."
        ),
        unverified=(
            'token source: grep -rl "@theme|theme:" src app --include=*.css --include=*.ts',
        ),
    ),
    # The bench's own corpus is a synthetic dashboard with a declared token set,
    # so it reviews under management-app semantics with the full T2 list -- the
    # corpus is the instrument that grows that list, so it never narrows it.
    "bench": Profile(
        name="bench",
        stack="corpus/build_corpus.py synthetic dashboard",
        token_source="corpus/out/manifest.json tokens",
        rationale=(
            "The measuring instrument. Nothing is suppressed and nothing is "
            "down-weighted, because a profile that filtered the corpus would be "
            "grading the detectors against a subset of their own output."
        ),
        weights=dict(_FULL),
        t2_classes=T2_ALL,
        per_page_max=2,
    ),
}

DEFAULT = "bench"


def get(name: str | None) -> Profile:
    key = name or DEFAULT
    if key not in PROFILES:
        raise SystemExit(
            f"unknown profile {key!r}; known: {', '.join(sorted(PROFILES))}"
        )
    return PROFILES[key]


def validate() -> list[str]:
    """Every profile must weight every rule, and never lower a correctness one."""
    problems = []
    for p in PROFILES.values():
        for rule in sorted(ALL_RULES):
            w = p.weight(rule)
            if rule in CORRECTNESS and w != 1.0:
                problems.append(
                    f"{p.name}: {rule} is a correctness rule and cannot carry "
                    f"weight {w}; a profile states what is worth attention, never "
                    f"what is true"
                )
        for rule in p.weights:
            if rule not in ALL_RULES:
                problems.append(
                    f"{p.name}: weights {rule!r}, which no detector emits -- a "
                    f"stale weight is a rule silently un-tuned"
                )
        for cls in p.t2_classes:
            if cls not in T2_ALL:
                problems.append(f"{p.name}: unknown T2 class {cls!r}")
    return problems


def main() -> None:
    problems = validate()
    for p in problems:
        print(f"INVALID  {p}")
    which = [a for a in sys.argv[1:] if not a.startswith("-")]
    for name in which or sorted(PROFILES):
        p = PROFILES[name]
        print(f"\n{p.name}  ({p.stack})")
        print(f"  tokens        {p.token_source or 'UNRESOLVED -- see notes'}")
        print(f"  region calls  {p.per_page_max}/page")
        print(f"  asks          {', '.join(p.t2_classes)}")
        tuned = {r: w for r, w in sorted(p.weights.items()) if w != 1.0}
        print(f"  down-weighted {tuned or 'nothing'}")
        print(f"  why           {p.rationale}")
        if p.notes:
            print(f"  note          {p.notes}")
        for u in p.unverified:
            print(f"  UNVERIFIED    {u}")
    raise SystemExit(1 if problems else 0)


if __name__ == "__main__":
    main()
