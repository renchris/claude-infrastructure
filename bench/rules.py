#!/usr/bin/env python3
"""The rule registry: one place that knows every rule the deterministic layer can emit.

There is exactly one reason this file exists, and it is not tidiness. Three
separate obligations in the research all reduce to "somebody must enumerate the
rules", and all three were previously discharged by reading the source:

  * PIPELINE_SPEC C18 ruling 1 -- "absolute zero on the control is the ship gate,
    no exceptions". A gate that cannot enumerate the rules cannot tell a rule
    that fired zero times from a rule that never ran.
  * PIPELINE_SPEC C7 / C16 -- the routing subtraction is CODE, not discipline.
    The router has to know which rules are abstentions and which classes a model
    is allowed to be asked about.
  * README section 8 -- "one review harness, three different rule weightings".
    A weighting is a total function over the rules; a missing key is a silent
    default, which is how an app quietly stops being reviewed.

So a rule is registered here or it does not exist. `assert_registered` is called
by every detector at emit time, which makes the registry impossible to forget:
an unregistered rule id is a hard error at the moment it is first reported, in
the detector's own test run, rather than a shrug in a downstream consumer.

The `answer` column is the NEVER list from PIPELINE_SPEC section 1.5 made
mechanical. A rule whose answer has a number in it may never become a question
for a vision model. The one legal exception is its own abstention -- an
abstention is precisely the statement "I could not produce the number", which is
a judgement call about an image and nothing else.
"""

from __future__ import annotations

from dataclasses import dataclass

# The six classes no deterministic rule can screen, from PIPELINE_SPEC section
# 1.5 trigger T2. These are routed once per page, unconditionally, and are never
# cut for budget -- they are the entire reason a vision layer is in the design.
UNSCREENABLE_CLASSES = (
    "hierarchy",
    "gestalt",
    "content-fit",
    "semantic-coherence",
    "optical-alignment",
    "readability",
)

# Severity ordering, so consequence ranking is not a string comparison.
SEVERITY_RANK = {"high": 3, "medium": 2, "low": 1}


@dataclass(frozen=True)
class Rule:
    """One deterministic rule.

    layer       which detector emits it -- `dom` (computed styles only) or
                `xcheck` (a DOM claim measured against the rendered pixels).
    klass       the defect class, shared across layers. Two rules may answer the
                same class from different substrates; the router collapses on it.
    answer      `number` when the finding's content is a measured quantity,
                `judgement` when it is not. Only `judgement` and abstentions may
                be routed to a model. This is section 1.5's NEVER list.
    abstention  the rule's verdict is "I cannot answer this", which is the
                vision layer's job queue rather than a finding.
    intent      which review intent the rule serves. The per-app weightings in
                review_profiles.json are authored against these, so a new rule
                inherits a defensible default instead of a zero.
    """

    id: str
    layer: str
    klass: str
    answer: str
    intent: str
    abstention: bool = False

    @property
    def routable(self) -> bool:
        """May a model be asked THIS RULE's question?

        Only an abstention. Class membership deliberately does not grant it: a
        rule can answer a question inside an unscreenable class -- the ink
        centroid answers a piece of `optical-alignment`, the overflow rule
        answers a piece of `content-fit` -- and its answer is still a number, so
        the model must never be asked to re-derive it. The unconditional
        page-level question about those six classes is trigger T2, which the
        router raises from UNSCREENABLE_CLASSES directly and not from any rule.
        Conflating the two is how a settled number becomes a re-asked question.
        """
        return self.abstention


def _r(*a, **kw) -> tuple[str, Rule]:
    rule = Rule(*a, **kw)
    return rule.id, rule


RULES: dict[str, Rule] = dict(
    [
        # --- detect_dom.py: computed styles and the box model ----------------
        _r("spacing-rhythm", "dom", "spacing", "number", "conformance"),
        _r("grid-violation", "dom", "spacing", "number", "conformance"),
        _r("type-scale", "dom", "typography", "number", "conformance"),
        _r("token-drift", "dom", "token", "number", "conformance"),
        _r("contrast", "dom", "contrast", "number", "accessibility"),
        _r("overflow", "dom", "content-fit", "number", "correctness"),
        _r("touch-target", "dom", "target-size", "number", "accessibility"),
        _r("misalignment", "dom", "alignment", "number", "conformance"),
        # The interesting output. Not a finding -- a routed question.
        _r(
            "contrast-indeterminate",
            "dom",
            "contrast",
            "judgement",
            "accessibility",
            abstention=True,
        ),
        # --- detect_xcheck.py: the DOM's claim against the rendered pixels ---
        _r("xcheck-zero-ink", "xcheck", "content-fit", "number", "correctness"),
        _r(
            "xcheck-optical-centre",
            "xcheck",
            "optical-alignment",
            "number",
            "aesthetics",
        ),
        _r("xcheck-contrast-varies", "xcheck", "contrast", "number", "accessibility"),
    ]
)

# Which rule settles which abstention -- PIPELINE_SPEC C16, made into a table
# instead of a habit. The gradient case is the worked example: the cross-check
# measures contrast in thirds and returns two real numbers, so re-asking a model
# about that text run spends a crop on a closed question.
#
# Stated as an explicit mapping rather than derived from a shared `klass`,
# because deriving it silently over-claims: `xcheck-optical-centre` and
# `xcheck-zero-ink` also share a class with something, and a future abstention in
# those classes would be marked resolved by a rule that never looked at it. A new
# abstention gets an empty set here until someone can name what closes it.
#
# The subtraction is PER SUBJECT, never per class: X3 answering the hero caption
# says nothing about the hero title sitting on the same gradient.
RESOLVED_BY: dict[str, set[str]] = {
    "contrast-indeterminate": {"xcheck-contrast-varies"},
}


class UnregisteredRule(KeyError):
    """Raised when a detector emits a rule id the registry does not carry."""


def assert_registered(rule_id: str) -> Rule:
    """Look a rule up, refusing an unknown id loudly.

    Called on every emit. The cost is a dict lookup; the value is that a new
    rule cannot reach a report without also reaching the false-positive budget
    and every per-app weighting.
    """
    try:
        return RULES[rule_id]
    except KeyError:
        raise UnregisteredRule(
            f"rule {rule_id!r} is not in bench/rules.py. Register it there first: "
            f"registration is what forces it through the clean-control run "
            f"(fp_budget.py) and into every per-app weighting "
            f"(review_profiles.json)."
        ) from None


def by_layer(layer: str) -> dict[str, Rule]:
    return {k: v for k, v in RULES.items() if v.layer == layer}


def _selfcheck() -> None:
    """Refuse an internally inconsistent registry.

    Runs on import. These are cheap and each one has already been a real defect
    somewhere in this substrate.
    """
    for rid, rule in RULES.items():
        assert rule.id == rid, f"{rid}: key and id disagree"
        assert rule.layer in ("dom", "xcheck"), f"{rid}: unknown layer {rule.layer}"
        assert rule.answer in ("number", "judgement"), f"{rid}: bad answer column"
        if rule.abstention:
            assert rule.answer == "judgement", (
                f"{rid}: an abstention whose answer is a number is a contradiction"
            )
    for abst, closers in RESOLVED_BY.items():
        assert_registered(abst)
        assert RULES[abst].abstention, f"{abst} is in RESOLVED_BY but is not an abstention"
        for c in closers:
            assert_registered(c)
    missing = [r for r in RULES.values() if r.abstention and r.id not in RESOLVED_BY]
    assert not missing, (
        f"abstentions with no RESOLVED_BY entry: {[r.id for r in missing]}. "
        f"Add an entry -- an empty set is a legitimate answer and says 'nothing "
        f"closes this yet', which is exactly what the router needs to hear."
    )


_selfcheck()


if __name__ == "__main__":
    print(f"{len(RULES)} registered rules")
    hdr = f"{'rule':24} {'layer':7} {'class':17} {'answer':10} {'intent':14} routable"
    print(hdr)
    print("-" * len(hdr))
    for rid, rule in RULES.items():
        print(
            f"{rid:24} {rule.layer:7} {rule.klass:17} "
            f"{'abstain' if rule.abstention else rule.answer:10} "
            f"{rule.intent:14} {'yes' if rule.routable else 'NEVER'}"
        )
