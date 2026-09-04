#!/usr/bin/env python3
"""Per-app rule weightings: one review harness, three different problems.

`reso-landing-app` is a purchased marketing template and its review is an
aesthetics problem. `reso-management-app` is a dense internal dashboard and its
review is a design-system-conformance problem, where the deterministic layer does
nearly all the work. `reso-web-app` sits between. Running one undifferentiated
rule set over all three produces the same report three times, and two of them are
wrong in opposite directions.

🚨 **A weighting here is an ADMISSION and an ORDER. It is never a score.**
PIPELINE_SPEC §6 Cut list forbids "any score, grade, rank or 1-5 rating", and a
per-rule multiplier is the most natural way in the world to smuggle one back in:
multiply severity by 1.4, sum over findings, and you have minted a page quality
number that no measurement supports. So the three things a profile may change
are exactly:

  ADMIT    does this rule run here at all, and if not, does it stay silent or
           does it ABSTAIN? Three-valued, and the third value is the important
           one -- a rule whose premise is absent must say so, not pass.
  ORDER    which findings a reader sees first. C7 ruling 3: rank by consequence,
           not document order. An abstention on a 12px legend and one on the
           primary CTA are not interchangeable.
  ROUTE    which of the unscreenable classes this app's one vision call should
           lead with. It never adds or removes a call -- T2 is unconditional and
           budget-exempt -- it only decides what the call is asked first.

🚨 **And a profile may never loosen a band** (§1.4). Bands are physics; profiles
are policy. If a per-app override ever appears that widens a tolerance, that is
the bug this paragraph exists to catch.

### On the stack facts this file deliberately does NOT carry

§2 C11 is a table that bans prose as a source and then published three wrong
cells of its own. Its ruling is that `profiles.json` is a GENERATED artifact,
read from `node_modules` and never from `package.json`, never from a wave brief,
and never from a hand-written example. So this module carries no version, no
engine list and no file path: `stack_state()` returns UNRESOLVED with the command
that resolves it. What it does carry is the review INTENT and its consequences,
which are genuinely a policy decision about what the review is for -- the one
thing that is legitimately prose, because it is a value judgement rather than a
measurement.

The `token_map` field is the seam between the two, and it is the reason this file
is worth having. It is a MEASUREMENT (C11, 2026-08-26) and it perishes. It is
recorded with its date and its consequence, and every consumer must treat a live
read as outranking it.
"""

from __future__ import annotations

# Rule -> family, per PIPELINE_SPEC §1.4. The families are what a profile speaks
# about; naming individual rules in a profile would mean editing every profile
# each time a rule is added, which is how per-app config rots.
FAMILY = {
    "spacing-rhythm": "G",  # geometry
    "misalignment": "G",
    "grid-violation": "G",
    "type-scale": "T",  # type
    "token-drift": "K",  # token conformance
    "contrast": "A",  # correctness floors -- the only family permitted to gate
    "contrast-indeterminate": "A",
    "touch-target": "A",
    "overflow": "O",  # containment
    "xcheck-zero-ink": "X",  # cross-checks: DOM vs pixels
    "xcheck-optical-centre": "X",
    "xcheck-optical-centre-v": "X",
    "xcheck-contrast-varies": "X",
}

# The six classes no deterministic rule can screen (§1.5 T2). A profile orders
# them; it may not shorten the list, because T2 is unconditional.
UNSCREENABLE = [
    "hierarchy",
    "gestalt",
    "content-fit",
    "semantic-coherence",
    "optical-alignment",
    "readability",
]

# ADMIT states. "abstain" is the one that earns this module its keep: it is what
# a rule must do when its PREMISE is missing rather than when its subject is
# clean, and the difference is invisible in a report that only has pass/fail.
ADMIT, ABSTAIN, EXCLUDE = "admit", "abstain", "exclude"

PROFILES = {
    # The corpus itself. Everything admitted, because the corpus is where a rule
    # earns admission anywhere else.
    "bench-corpus": {
        "intent": "instrument",
        "why": "the ground-truth corpus: every family runs, and the control is the gate",
        "admit": {},
        "order": ["A", "O", "X", "K", "T", "G"],
        "route_first": ["hierarchy", "readability", "optical-alignment"],
        "token_map": {
            "state": "PRESENT",
            "source": "corpus/out/manifest.json#tokens",
            "measured": "2026-08-26",
        },
    },
    "reso-landing-app": {
        "intent": "marketing-aesthetics",
        "why": (
            "a purchased template whose job is to convert. Its rhythm and scale are the "
            "vendor's deliberate choices, so conformance findings name decisions we did "
            "not make and would not act on; what actually fails here is perceptual"
        ),
        "admit": {
            "K": (
                EXCLUDE,
                "purchased template: the token set is the vendor's. A drift finding "
                "here is a report that someone else's design system is not ours, "
                "which is true, unactionable, and would arrive on every element",
            ),
            "G": (
                EXCLUDE,
                "the same argument one step weaker, and it is still decisive: an "
                "8px-grid violation on a template is a claim that the vendor should "
                "have used our grid",
            ),
        },
        # Correctness floors first because they are the only findings that are
        # ours to fix on someone else's markup, then the perceptual arms.
        "order": ["A", "X", "O", "T", "G", "K"],
        "route_first": ["hierarchy", "gestalt", "readability"],
        "token_map": {
            "state": "UNRESOLVED",
            "source": None,
            "measured": None,
            "note": "not measured by C11; generate before admitting K",
        },
    },
    "reso-management-app": {
        "intent": "design-system-conformance",
        "why": (
            "a dense internal dashboard. Nothing here needs to delight; it needs to be "
            "consistent, legible and unclipped, which is almost entirely a job for the "
            "deterministic layer"
        ),
        "admit": {
            # 🚨 This is the whole reason a profile is not a multiplier. The app
            # whose review IS conformance is the one app that cannot currently
            # produce a conformance verdict, and weighting K up while its token
            # source is absent would have produced the most confident garbage in
            # the programme.
            "K": (
                ABSTAIN,
                "engine-has-no-token-source: measured 2026-08-26, Tailwind 4 sits in "
                "the PostCSS chain emitting utilities from no declared token map "
                "(@theme count = 0 in the app-shell CSS), so a colour authored by that "
                "engine is unattributable to a token by construction. C11's ruling is "
                "INDETERMINATE, never FAIL and never a silent pass",
            ),
        },
        "order": ["K", "O", "A", "G", "T", "X"],
        # A dashboard's real failures are a clipped cell and a table that does not
        # say what it means -- not whether it delights.
        "route_first": ["content-fit", "semantic-coherence", "hierarchy"],
        "token_map": {
            "state": "SPLIT",
            "source": "styled-system/tokens/index.mjs (panda) + NONE (tailwind4)",
            "measured": "2026-08-26",
            "note": (
                "two engines in one PostCSS chain. A two-engine app needs an explicit "
                "precedence or the K family refuses outright (C11)"
            ),
        },
    },
    "reso-web-app": {
        "intent": "mixed",
        "why": "between the other two; neither lens dominates",
        "admit": {
            "K": (
                ABSTAIN,
                "class-names-not-invertible: measured 2026-08-26, Chakra 2 + Emotion 11 "
                "emit runtime css-<hash> class names, so the conformance surface is "
                "100% INDETERMINATE until autoLabel is turned on app-side (B11)",
            ),
        },
        "order": ["A", "O", "K", "X", "G", "T"],
        "route_first": ["hierarchy", "content-fit", "readability"],
        "token_map": {
            "state": "UNRESOLVED",
            "source": None,
            "measured": "2026-08-26",
            "note": "no Tailwind, no Panda; tokens live in a Chakra theme object",
        },
    },
}

DEFAULT = "bench-corpus"


def get(app: str) -> dict:
    """-> the profile. An unknown app is a REFUSAL, not a default: silently
    reviewing an app under another app's lens is the failure this module exists
    to prevent, and it would be invisible in the output."""
    if app not in PROFILES:
        raise SystemExit(
            f"no profile for {app!r}. Known: {', '.join(sorted(PROFILES))}.\n"
            f"Add one deliberately -- do not fall back to a default, because a "
            f"marketing page reviewed as a design system reports nothing but noise."
        )
    return dict(PROFILES[app], app=app)


def admission(profile: dict, rule: str):
    """-> (state, reason). The reason is carried into the finding, so a report
    can always say WHY a family is silent -- an absent family and a clean one
    look identical otherwise."""
    fam = FAMILY.get(rule, "?")
    state, reason = profile["admit"].get(fam, (ADMIT, ""))
    return state, reason


def apply(profile: dict, findings: list[dict]) -> list[dict]:
    """Admit, mark and order one page's findings under a profile.

    EXCLUDE drops the finding. ABSTAIN keeps it and demotes it to INDETERMINATE
    with the profile's reason, which is what routes it to the vision layer
    instead of asserting it. Nothing here changes a measurement.
    """
    out = []
    for f in findings:
        state, reason = admission(profile, f["rule"])
        if state == EXCLUDE:
            continue
        g = dict(f, family=FAMILY.get(f["rule"], "?"))
        if state == ABSTAIN and g.get("verdict", "FAIL") == "FAIL":
            g["verdict"] = "INDETERMINATE"
            g["detail"] = f"{g['detail']}  [held by profile: {reason}]"
            g.setdefault("routeTo", "semantic-coherence")
        out.append(g)
    order = {fam: i for i, fam in enumerate(profile["order"])}
    sev = {"high": 0, "medium": 1, "low": 2}
    # By consequence, then by severity, then stably by subject. No sum, no score:
    # this is a reading order, and two findings never combine into a number.
    return sorted(
        out,
        key=lambda f: (
            order.get(f["family"], 99),
            sev.get(f["severity"], 9),
            f["target"],
        ),
    )


def route_order(profile: dict) -> list[str]:
    """The six unscreenable classes, this app's leading interests first. The list
    is never shortened -- T2 is unconditional and budget-exempt -- so this only
    decides what the one call is asked first."""
    lead = [c for c in profile["route_first"] if c in UNSCREENABLE]
    return lead + [c for c in UNSCREENABLE if c not in lead]


def stack_state(app: str) -> dict:
    """Deliberately refuses to answer. §2 C11: no stage takes a per-app premise
    from prose, and after that attack, not from a hand-written JSON example
    either. Versions, engines and token-map paths are read from `node_modules`
    at profile-generation time or they are not known."""
    return {
        "app": app,
        "state": "UNRESOLVED",
        "resolve_with": "dr surface --app <app>  (reads node_modules, writes profiles.json)",
        "why": (
            "a range specifier is not a version and a wave brief is not a measurement; "
            "C11 was written to stop this pipeline inheriting a false premise and then "
            "published three wrong cells of its own"
        ),
    }


if __name__ == "__main__":
    for name in PROFILES:
        p = get(name)
        tm = p["token_map"]
        print(f"\n{name}  [{p['intent']}]")
        print(f"  why      {p['why']}")
        print(f"  order    {' > '.join(p['order'])}")
        print(f"  routes   {' > '.join(route_order(p))}")
        print(f"  tokens   {tm['state']}  ({tm.get('source') or 'no source'})")
        for fam, (state, reason) in p["admit"].items():
            print(f"  {state:8} {fam}: {reason[:96]}")
