#!/usr/bin/env python3
"""The rule taxonomy: what each rule claims, and what kind of claim it is.

One table, imported by everything that has to reason ABOUT rules rather than run
them -- the false-positive budget and the abstention router. Written down because
three separate things need the same three facts and would otherwise each invent
their own answer:

  klass      what the finding is a claim about, in the corpus manifest's own
             vocabulary, so a detector's output can be scored against ground
             truth by CLASS rather than by whether it said anything at all. A
             contrast failure reported at the right element on the
             hierarchy-inversion page is not a hierarchy finding, and counting it
             as one would credit the deterministic layer with the one capability
             it provably does not have.

  kind       ASSERT -- a verdict with a number behind it, terminal.
             ABSTAIN -- the rule reached its own limit and said so. This is the
             single most valuable output in the pipeline: an abstention routes to
             the vision layer, a silent pass routes nowhere, and every silent
             pass that should have been an abstention is a defect shipped.

  substrate  which detector emits it. Used to say who could not answer, never to
             decide who is right.

DISCHARGES is the other half of the router's job and the reason the vision queue
is affordable. An abstention is not automatically a model call: where a later,
cheaper layer answered the same question about the same element, the abstention
is spent and must not be paid for twice. The gradient case is the whole worked
example -- `contrast-indeterminate` says a ratio cannot be computed, and
`xcheck-contrast-varies` answers it with two numbers off the pixels and no model
at all, so it leaves the queue entirely.

JUDGEMENT_ONLY is the converse: corpus classes NO rule can reach, by
construction, because they are judgements about whether a page makes sense rather
than violations of anything. A rule that ever claims one of these has stopped
measuring and started opining, and the pipeline's own division of labour forbids
it. They are the gestalt queue's reason to exist.
"""

from __future__ import annotations

from dataclasses import dataclass

ASSERT = "assert"
ABSTAIN = "abstain"


@dataclass(frozen=True)
class Rule:
    klass: str
    kind: str
    substrate: str
    # What a reader is being asked to look at when this reaches the vision layer.
    # Only meaningful for ABSTAIN rules; it becomes the crop's caption.
    question: str = ""


RULES: dict[str, Rule] = {
    # --- deterministic, DOM-determined ------------------------------------
    "spacing-rhythm": Rule("spacing-inconsistency", ASSERT, "dom"),
    "grid-violation": Rule("grid-violation", ASSERT, "dom"),
    "type-scale": Rule("typographic-scale", ASSERT, "dom"),
    "token-drift": Rule("token-drift", ASSERT, "dom"),
    "contrast": Rule("contrast", ASSERT, "dom"),
    "overflow": Rule("overflow", ASSERT, "dom"),
    "touch-target": Rule("accessibility", ASSERT, "dom"),
    "misalignment": Rule("misalignment", ASSERT, "dom"),
    "contrast-indeterminate": Rule(
        "contrast",
        ABSTAIN,
        "dom",
        "Does this text stay legible across its whole width? The backdrop is an "
        "image or gradient, so no single contrast ratio describes it. Do not "
        "report a ratio; say whether a reader loses the text anywhere in it.",
    ),
    # --- the DOM-vs-pixels cross-check ------------------------------------
    "xcheck-zero-ink": Rule("render", ASSERT, "xcheck"),
    "xcheck-optical-centre": Rule("optical-alignment", ASSERT, "xcheck"),
    "xcheck-contrast-varies": Rule("contrast", ASSERT, "xcheck"),
    "xcheck-centre-indeterminate": Rule(
        "optical-alignment",
        ABSTAIN,
        "xcheck",
        "Does this mark sit where its container says it does? Neither the "
        "container's fill nor the backdrop behind it is a solid colour, so the "
        "centroid could not be measured. Do not estimate an offset in pixels; "
        "say whether it reads as centred.",
    ),
    "xcheck-contrast-unsampleable": Rule(
        "contrast",
        ABSTAIN,
        "xcheck",
        "Is this text legible against what is behind it? Too little of its box "
        "differs from the text colour for the backdrop to be sampled. Do not "
        "report a ratio.",
    ),
}

# abstention rule -> the assertions that answer the same question and spend it.
DISCHARGES: dict[str, frozenset[str]] = {
    "contrast-indeterminate": frozenset({"xcheck-contrast-varies", "contrast"}),
    "xcheck-contrast-unsampleable": frozenset({"xcheck-contrast-varies", "contrast"}),
    "xcheck-centre-indeterminate": frozenset({"xcheck-optical-centre"}),
}

# Corpus classes no rule may claim. See the module docstring.
JUDGEMENT_ONLY = frozenset({"visual-hierarchy"})

UNKNOWN = Rule("unknown", ASSERT, "unknown")


def rule(name: str) -> Rule:
    """Never KeyError on a rule someone added and forgot to classify -- an
    unclassified rule must still be counted, and counted somewhere visible."""
    return RULES.get(name, UNKNOWN)


def unclassified(names) -> list[str]:
    """Rules seen in a run that this table does not know about. The budget prints
    these: a rule outside the taxonomy is scored as `unknown` and can neither be
    discharged nor routed, so it silently loses whatever it was worth."""
    return sorted({n for n in names if n not in RULES})
