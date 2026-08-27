#!/usr/bin/env python3
"""The false-positive budget: re-run every rule against the clean control.

~20% false positives is where an AI reviewer loses credibility regardless of its
catch rate, because an agent ACTS on what it is told. A detector that invents a
defect is worse than no detector. The two zero-FP runs this bench already has are
the baseline to defend, and defending them means a gate rather than a habit: every
rule added, and every tolerance changed, is re-run against the control BEFORE it
ships, and this exits non-zero when it is not.

Three populations, kept apart on purpose, because collapsing them is how a budget
becomes a number that cannot fail:

  CONTROL false positives -- any assertion at all on clean.html. Budget: ZERO, and
      no rule gets an allowance here. The control is hand-authored to be correct;
      a rule that fires on it is overfitted or noisy and its findings elsewhere are
      worth nothing. (Twice now the control has turned out not to be clean. Both
      times the honest move was to fix the CONTROL -- three WCAG failures, then a
      backwards optical-compensation constant -- never to widen the tolerance until
      the complaint went away. Loosening a tolerance to silence a control finding
      blinds the rule to the defect it exists for; that is not a budget, it is a
      way of passing.)

  COLLATERAL false positives -- on a defect page, an assertion about an element the
      injected CSS does not touch. Scored against the injected rule's WHOLE selector
      list, not just its declared target: the gradient variant restyles `.hero` and
      `.hero-caption`, so a finding on `.hero-title` is a true consequence of the
      injection sitting inside a modified subtree, and calling it a false positive
      would be the assertion-span-must-equal-its-subject error in the other
      direction. Budget is declared per rule below, with a reason.

  ABSTENTIONS -- not false positives, and never counted as one. An abstention is
      the deterministic layer saying where it stopped being able to see; it routes
      to the vision layer rather than asserting anything. Counting them as noise
      would create pressure to delete exactly the output that makes the seam work.

Recall is reported alongside but is NOT the gate, and the asymmetry is deliberate:
recall is scored strictly (did something land on the DECLARED target), FP is scored
generously (never call a true consequence of the injection a false positive). A gate
that traded recall against precision would let a rule buy its way past this file.

Usage:
  python3 fp_budget.py <corpus-dir> [--shot-suffix @1.5x] [--profile corpus]
Exit: 0 if every budget holds, 1 if any is breached.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

# Declared allowances. Every entry needs a reason, and the reason has to be about
# the rule rather than about the run -- "it fired twice last time" is a
# measurement, not a justification.
COLLATERAL_BUDGET: dict[str, int] = {
    # Nothing has earned one yet, and that is the state to defend. A new rule
    # arrives here at 0 and either holds or explains itself in this table.
}
CONTROL_BUDGET = 0  # not per-rule, not negotiable

ABSTENTION_RULES = {"contrast-indeterminate"}

# Which defect class each rule is entitled to claim. The manifest's own scoring
# rule is "names the right defect class AND points at the right target", and the
# conjunction is load-bearing: the hierarchy-inversion variant restyles both
# buttons, so `token-drift` and `contrast` fire inside its subtree and a
# target-only test credits them with catching a defect neither one describes.
# That would score the corpus 3/3 on pixels-only while the vision layer's actual
# job -- the one relation no rule can state -- went unexamined. A rule with no
# entry here can never take recall credit, which is the safe direction; the run
# warns rather than crediting it silently.
RULE_CLASS = {
    "spacing-rhythm": "spacing-inconsistency",
    "grid-violation": "grid-violation",
    "type-scale": "typographic-scale",
    "token-drift": "token-drift",
    "contrast": "contrast",
    "overflow": "overflow",
    "touch-target": "accessibility",
    "misalignment": "misalignment",
    "xcheck-zero-ink": "content-fit",
    "xcheck-optical-centre": "optical-alignment",
    "xcheck-contrast-varies": "contrast",
}

SEL_SPLIT = re.compile(r"([^{}]+)\{")
CLASS_RE = re.compile(r"\.([A-Za-z0-9_-]+)")
NTH_RE = re.compile(r":nth-(?:child|of-type)\((\d+)\)")


def compounds(selector: str) -> list[tuple[frozenset, int | None]]:
    """`.a:nth-child(2) .b` -> [({'a'}, 2), ({'b'}, None)] -- descendant steps."""
    out = []
    for part in selector.strip().split():
        if part in (">", "+", "~"):
            continue
        nth = NTH_RE.search(part)
        out.append(
            (frozenset(CLASS_RE.findall(part)), int(nth.group(1)) if nth else None)
        )
    return out


def seg_matches(seg: str, classes: frozenset, nth: int | None) -> bool:
    seg_classes = set(CLASS_RE.findall(seg.split(":")[0]))
    if not classes <= seg_classes:
        return False
    if nth is None:
        return True
    m = NTH_RE.search(seg)
    # The corpus's nth-child selectors address same-tag sibling sets, where
    # nth-child and nth-of-type coincide. A selector over mixed siblings would
    # need the DOM, not the path string, and this says so rather than guessing.
    return (int(m.group(1)) if m else 1) == nth


def selector_matches(selector: str, path: str) -> bool:
    """Does `path` name an element this selector matches, or a descendant of one?"""
    steps = compounds(selector)
    if not steps:
        return False
    segs = path.split(" > ")
    i = 0
    for classes, nth in steps:
        while i < len(segs) and not seg_matches(segs[i], classes, nth):
            i += 1
        if i == len(segs):
            return False
        i += 1
    return True


def touched_by(defect: dict) -> list[str]:
    """Every selector the injected CSS restyles -- the modified subtree, not just
    the declared target. A finding inside it is a consequence, not a fabrication."""
    return [
        s.strip()
        for block in SEL_SPLIT.findall(defect["css"])
        for s in block.split(",")
        if s.strip()
    ]


def load(corpus: pathlib.Path, suffix: str) -> dict[str, list[dict]]:
    merged: dict[str, list[dict]] = {}
    for name in ("findings_dom.json", f"findings_xcheck{suffix}.json"):
        f = corpus / name
        if not f.exists():
            if name.startswith("findings_dom"):
                sys.exit(f"missing {f}: run detect_dom.py first")
            print(f"!! {name} absent -- its rules are UNMEASURED here, not zero")
            continue
        for page, fs in json.loads(f.read_text()).items():
            merged.setdefault(page, []).extend(fs)
    return merged


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", default="corpus/out", type=pathlib.Path)
    ap.add_argument("--shot-suffix", default="", help="score the @1.5x capture instead")
    a = ap.parse_args()
    corpus = a.corpus.resolve()

    manifest = json.loads((corpus / "manifest.json").read_text())
    defects = {d["id"]: d for d in manifest["defects"]}
    findings = load(corpus, a.shot_suffix)

    assertions = {
        p: [f for f in fs if f["rule"] not in ABSTENTION_RULES]
        for p, fs in findings.items()
    }
    abstentions = sum(
        1 for fs in findings.values() for f in fs if f["rule"] in ABSTENTION_RULES
    )

    control = assertions.get("clean", [])
    collateral: dict[str, list[tuple[str, str]]] = {}
    recall: dict[str, bool] = {}

    for page, fs in assertions.items():
        if page == "clean":
            continue
        d = defects.get(page)
        if d is None:
            continue
        touched = touched_by(d)
        recall[page] = any(
            RULE_CLASS.get(f["rule"]) == d["klass"]
            and selector_matches(d["target"], f["target"])
            for f in fs
        )
        for f in fs:
            if any(selector_matches(sel, f["target"]) for sel in touched):
                continue
            collateral.setdefault(f["rule"], []).append((page, f["target"]))

    print(f"CONTROL clean.html ({a.shot_suffix or 'dpr 1'})")
    print(f"  assertions: {len(control)}   budget: {CONTROL_BUDGET}")
    for f in control:
        print(f"    FP [{f['rule']}] {f['target']}: {f['detail'][:80]}")

    print("\nCOLLATERAL (an assertion about an element the injected CSS never touches)")
    if not collateral:
        print("  none")
    for rule, hits in sorted(collateral.items()):
        allow = COLLATERAL_BUDGET.get(rule, 0)
        flag = "" if len(hits) <= allow else "  <-- OVER BUDGET"
        print(f"  [{rule}] {len(hits)} / budget {allow}{flag}")
        for page, target in hits[:4]:
            print(f"      {page}: {target[:70]}")

    dom_ids = [d for d in defects.values() if d["detectable_by"] == "dom"]
    px_ids = [d for d in defects.values() if d["detectable_by"] == "pixels"]
    hit_dom = sum(1 for d in dom_ids if recall.get(d["id"]))
    hit_px = sum(1 for d in px_ids if recall.get(d["id"]))
    print(
        f"\nRECALL (reported, never the gate)  DOM-determined {hit_dom}/{len(dom_ids)}"
        f"   pixels-only {hit_px}/{len(px_ids)}"
    )
    for d in px_ids:
        print(
            f"    [pixels] {d['id']:22} {'found' if recall.get(d['id']) else 'MISSED'}"
        )
    for d in dom_ids:
        if not recall.get(d["id"]):
            print(f"    [dom   ] {d['id']:22} MISSED")
    print(
        f"\nABSTENTIONS {abstentions} -- routed, not scored. An abstention is where the "
        f"layer\n            says it cannot see; counting it as noise would delete the seam."
    )

    unmapped = {
        f["rule"]
        for fs in assertions.values()
        for f in fs
        if f["rule"] not in RULE_CLASS
    }
    for r in sorted(unmapped):
        print(
            f"!! rule {r!r} has no RULE_CLASS entry -- it can raise findings but can "
            f"never take recall credit. Add it before trusting the recall column."
        )

    over = [r for r, h in collateral.items() if len(h) > COLLATERAL_BUDGET.get(r, 0)]
    breached = len(control) > CONTROL_BUDGET or bool(over)
    print()
    if breached:
        if len(control) > CONTROL_BUDGET:
            print(f"BUDGET BREACHED: {len(control)} finding(s) on the clean control.")
            print("  Fix the rule, or fix the control -- never widen the tolerance.")
        for r in over:
            print(
                f"BUDGET BREACHED: {r} collateral {len(collateral[r])} > {COLLATERAL_BUDGET.get(r, 0)}"
            )
        sys.exit(1)
    print("BUDGET HELD: zero on the control, zero unbudgeted collateral.")


if __name__ == "__main__":
    main()
