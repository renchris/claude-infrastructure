#!/usr/bin/env python3
"""The one predicate that says whether a finding is a CLAIM or an ABSTENTION.

Both detectors, the router and the false-positive budget ask this question, and
they must never answer it differently. If the budget counted an abstention as a
false positive it would report the layer's most valuable output as its worst
defect; if the router treated a claim as an abstention it would buy a model call
to re-ask a question arithmetic already closed.

The wire format is the rule name's `-indeterminate` suffix. That is not a new
convention -- `detect_dom.py` already emitted `contrast-indeterminate`, and
P5-route's T1 formula is already written as `f.rule.endswith("-indeterminate")`.
Encoding it in the name rather than in a separate field means a findings JSON
written before this module existed still classifies correctly, and a new rule
declares its own verdict class by what it is called.

An ABSTENTION means: this layer looked, and the honest answer is that it cannot
decide. It is a routing instruction, not a defect. A silent pass where an
abstention belonged is a defect shipped -- which is why abstentions are budgeted
(they cost model calls) but never scored as false positives (they cost no trust).
"""

from __future__ import annotations

ABSTAIN_SUFFIX = "-indeterminate"


def is_abstention(finding: dict) -> bool:
    """True when the finding is an honest 'I cannot decide', not a defect claim."""
    return str(finding.get("rule", "")).endswith(ABSTAIN_SUFFIX)


def claims(findings: list[dict]) -> list[dict]:
    """Only the defect claims -- what a false-positive budget is measured over."""
    return [f for f in findings if not is_abstention(f)]


def abstentions(findings: list[dict]) -> list[dict]:
    """Only the abstentions -- what the router turns into cropped questions."""
    return [f for f in findings if is_abstention(f)]
