#!/usr/bin/env python3
"""Per-app rule weightings. One review harness, three different problems.

The three apps are not three instances of one review. `reso-landing-app` is a
purchased Next 14 template, so it is a MARKETING-AESTHETICS problem: its design
system is not ours, and every conformance rule -- "this radius differs from the
page's dominant radius", "this margin is off our 8px grid" -- is measuring our
convention against somebody else's deliberate design. Those rules do not become
more accurate there, they become noise, and noise is the thing that destroys an
AI reviewer's credibility faster than a missed defect does.

`reso-management-app` (Next 16, React 19, Tailwind 4) is the opposite: a design
system we own and can be conformed to, where the deterministic layer does nearly
all of the work and drift is a real finding rather than an opinion.
`reso-web-app` (Next 13) sits between the two.

So a weight here is not a confidence score. It answers one question: on THIS app,
does this rule's finding change what someone does? A weight of 0 removes the rule
from the app entirely -- an off rule is quieter than a low-priority one, and the
false-positive budget in `fp_budget.py` is what earns a rule its way back on.

Two profile fields govern spend rather than ranking:

  judgement     whether whole-page judgement -- hierarchy, attention, "does this
                page make sense" -- enters the vision queue at all. It is the one
                class no rule reaches, and it is worth paying for on a marketing
                page whose whole job is the first two seconds. On an internal
                admin surface it is spend with no decision behind it.
  queue_budget  the ceiling on vision-queue entries per page. The abstention set
                is small, and that is precisely what makes the vision spend
                affordable; a budget keeps it small when a page is unusual.

Nothing here is a quality gate. The June 2026 campaign settled that taste stays
human and gates adjudicate correctness and coverage only, and a weighting is a
priority order for a person reading a report, never a threshold that passes or
fails a build.
"""

from __future__ import annotations

# Severity as a number, so a weight and a severity compose into one order.
SEVERITY = {"high": 3.0, "medium": 2.0, "low": 1.0}

# Every rule either detector can emit. Listing them explicitly means a new rule
# has to be given a weight per app before it can ship, rather than inheriting a
# default nobody chose.
RULES = (
    "spacing-rhythm",
    "grid-violation",
    "type-scale",
    "token-drift",
    "contrast",
    "contrast-indeterminate",
    "overflow",
    "touch-target",
    "misalignment",
    "xcheck-zero-ink",
    "xcheck-optical-centre",
    "xcheck-contrast-varies",
    "xcheck-backdrop-indeterminate",
)


class Profile:
    def __init__(
        self,
        pid: str,
        stance: str,
        weights: dict[str, float],
        judgement: bool,
        queue_budget: int,
        fp_budget: float = 0.20,
    ) -> None:
        self.id = pid
        self.stance = stance
        self.weights = weights
        self.judgement = judgement
        self.queue_budget = queue_budget
        # ~20% false positives is where an AI reviewer loses credibility whatever
        # its catch rate, so that is the ceiling rather than a target. The control
        # run is a separate, harder gate: exactly zero.
        self.fp_budget = fp_budget

    def weight(self, rule: str) -> float:
        return self.weights.get(rule, 1.0)

    def enabled(self, rule: str) -> bool:
        return self.weight(rule) > 0.0

    def priority(self, finding: dict) -> float:
        sev = SEVERITY.get(finding.get("severity", "medium"), 2.0)
        return sev * self.weight(finding["rule"])

    def rank(self, findings: list[dict]) -> list[dict]:
        """Drop what this app does not care about, order what is left."""
        keep = [f for f in findings if self.enabled(f["rule"])]
        for f in keep:
            f["priority"] = round(self.priority(f), 2)
            f["profile"] = self.id
        return sorted(keep, key=lambda f: -f["priority"])


PROFILES: dict[str, Profile] = {
    # The instrument's own profile: everything on, everything level. The corpus
    # is scored under this so a weighting can never flatter a detector.
    "bench": Profile(
        "bench",
        "unweighted -- the measuring instrument, not an app",
        {r: 1.0 for r in RULES},
        judgement=True,
        queue_budget=99,
    ),
    "reso-management": Profile(
        "reso-management",
        "design-system conformance: a Tailwind 4 system we own, where drift is a "
        "defect and the deterministic layer does nearly all the work",
        {
            # Conformance is the point here, so the token rules lead.
            "token-drift": 1.5,
            "grid-violation": 1.3,
            "type-scale": 1.3,
            "spacing-rhythm": 1.2,
            "misalignment": 1.0,
            # Correctness is never discounted on any app.
            "contrast": 1.5,
            "overflow": 1.5,
            "touch-target": 1.5,
            # An admin surface is mostly solid backdrops, so abstentions are rare
            # and each one is worth looking at.
            "contrast-indeterminate": 1.0,
            "xcheck-backdrop-indeterminate": 1.0,
            "xcheck-zero-ink": 1.5,
            "xcheck-contrast-varies": 1.0,
            "xcheck-optical-centre": 1.0,
        },
        judgement=False,
        queue_budget=2,
    ),
    "reso-landing": Profile(
        "reso-landing",
        "marketing aesthetics: a purchased Next 14 template whose design system "
        "is not ours, so conformance rules measure our convention against "
        "somebody else's deliberate design",
        {
            # Off, not merely quiet. On a bought template these fire on intent.
            "token-drift": 0.0,
            "grid-violation": 0.0,
            # A marketing page varies type and rhythm on purpose; keep a whisper
            # so a genuinely broken step still surfaces, well below correctness.
            "type-scale": 0.25,
            "spacing-rhythm": 0.5,
            "misalignment": 0.5,
            "contrast": 1.5,
            "overflow": 1.5,
            "touch-target": 1.5,
            # Hero gradients and photographic backdrops are the house style, so
            # this is the abstention that actually fires here, and the one whose
            # answer a reader's eye depends on.
            "contrast-indeterminate": 1.5,
            "xcheck-contrast-varies": 1.5,
            "xcheck-backdrop-indeterminate": 1.5,
            "xcheck-zero-ink": 1.5,
            "xcheck-optical-centre": 1.0,
        },
        judgement=True,
        queue_budget=6,
    ),
    "reso-web": Profile(
        "reso-web",
        "between the two: a Next 13 app with some of our system and some "
        "inherited marketing surface",
        {
            "token-drift": 0.75,
            "grid-violation": 0.5,
            "type-scale": 0.75,
            "spacing-rhythm": 0.75,
            "misalignment": 0.75,
            "contrast": 1.5,
            "overflow": 1.5,
            "touch-target": 1.5,
            "contrast-indeterminate": 1.25,
            "xcheck-contrast-varies": 1.25,
            "xcheck-backdrop-indeterminate": 1.25,
            "xcheck-zero-ink": 1.5,
            "xcheck-optical-centre": 1.0,
        },
        judgement=True,
        queue_budget=4,
    ),
}


def get(pid: str) -> Profile:
    if pid not in PROFILES:
        raise SystemExit(f"unknown profile {pid!r}; have {', '.join(sorted(PROFILES))}")
    return PROFILES[pid]


if __name__ == "__main__":
    for name, p in PROFILES.items():
        off = [r for r in RULES if not p.enabled(r)]
        print(f"{name}")
        print(f"  {p.stance}")
        print(
            f"  judgement queue: {'on' if p.judgement else 'off'}"
            f" · budget {p.queue_budget}/page"
            f" · off-target FP ceiling {p.fp_budget:.0%}"
        )
        if off:
            print(f"  rules off: {', '.join(off)}")
        top = sorted(RULES, key=lambda r: -p.weight(r))[:4]
        print(f"  leads with: {', '.join(f'{r} x{p.weight(r):g}' for r in top)}")
