#!/usr/bin/env python3
"""Grade the deterministic layer against the corpus's own ground truth.

The README quotes 9/9 on the DOM-determined defects and a union of 11/11 across
three detectors. Those numbers were read off a printed table by a person. This
makes them a computed verdict, which matters for one specific reason: every
change to a rule, a tolerance or the corpus itself can move them, and until now
nothing would have said so. The false-positive gate catches a rule that got
louder; this catches a rule that got quieter, and the second failure is the
silent one.

Scoring follows the manifest's own definitions:

  true positive   names the right defect class AND points at the right target
  miss            the defect page produced no finding matching both
  unreachable     the manifest says no deterministic rule can see it, and the
                  router's T2 trigger is what covers it -- scored separately,
                  never as a miss, because counting a correct abstention as a
                  miss is the mistake the corpus itself made once and had to
                  publish a correction for

Findings that also appear on the clean control are excluded. That is legitimate
here and only here: the control is gated at absolute zero by fp_budget.py, so the
exclusion is provably a no-op rather than a suppression mechanism.

Usage: python3 score.py <corpus-dir>
Exit: 0 = every reachable defect found · 1 = at least one miss
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

# Which rules are an acceptable answer for each defect class the manifest
# declares. This is a SCORING key, not a rule-authoring key -- the rules are
# written against the page's own dominant convention and have never seen this
# table. A class with an empty set is one the manifest itself marks as invisible
# to the DOM.
ACCEPTS: dict[str, set[str]] = {
    "spacing-inconsistency": {"spacing-rhythm", "grid-violation"},
    "misalignment": {"misalignment"},
    "token-drift": {"token-drift"},
    "typographic-scale": {"type-scale"},
    "grid-violation": {"grid-violation"},
    "contrast": {"contrast", "contrast-indeterminate", "xcheck-contrast-varies"},
    "overflow": {"overflow"},
    "accessibility": {"touch-target"},
    "optical-alignment": {"xcheck-optical-centre"},
    # A judgement about the RELATION between two elements, both of which have
    # entirely valid styles. No rule reaches it and none should pretend to.
    "visual-hierarchy": set(),
}

SEG = re.compile(r"^([a-z0-9-]+)((?:\.[^.:]+)*)(?::nth-of-type\((\d+)\))?$", re.I)


def parse_selector(sel: str) -> tuple[set[str], int | None]:
    """Last simple selector of a manifest target -> (class tokens, nth index)."""
    last = sel.split()[-1]
    nth = None
    m = re.search(r":nth-child\((\d+)\)", last)
    if m:
        nth = int(m.group(1))
        last = last[: m.start()]
    return {c for c in last.split(".") if c}, nth


def target_matches(path: str, sel: str) -> bool:
    """Does a finding's element path point at the selector's element?

    Matched on the path's own leaf segment, so an ancestor that happens to share
    a class name cannot claim a hit. The corpus's sibling lists are homogeneous,
    which is what lets `nth-child` in a selector answer to `nth-of-type` in a
    path; on a heterogeneous list this equivalence does not hold and the scorer
    would need the real index.
    """
    want, nth = parse_selector(sel)
    m = SEG.match(path.rsplit(" > ", 1)[-1])
    if not m:
        return False
    have = {c for c in m.group(2).split(".") if c}
    if not want <= have:
        return False
    return nth is None or (m.group(3) is not None and int(m.group(3)) == nth)


def main(corpus: pathlib.Path) -> int:
    manifest = json.loads((corpus / "manifest.json").read_text())
    layers = {}
    for name in ("dom", "xcheck"):
        p = corpus / f"findings_{name}.json"
        if p.exists():
            layers[name] = json.loads(p.read_text())
        else:
            print(f"⚠ findings_{name}.json missing; that layer scores 0 by default")
            layers[name] = {}

    def findings_for(page: str) -> list[dict]:
        out = []
        for name, doc in layers.items():
            base = {
                (f["rule"], f["target"], f["detail"]) for f in doc.get("clean", [])
            }
            for f in doc.get(page, []):
                if (f["rule"], f["target"], f["detail"]) not in base:
                    out.append(dict(f, layer=name))
        return out

    hits, misses, unreachable = [], [], []
    rows = []
    for d in manifest["defects"]:
        accepts = ACCEPTS[d["klass"]]
        found = [
            f
            for f in findings_for(d["id"])
            if f["rule"] in accepts and target_matches(f["target"], d["target"])
        ]
        if not accepts:
            unreachable.append(d)
            verdict, by = "unreachable", "routed as T2"
        elif found:
            hits.append(d)
            verdict = "HIT"
            by = ", ".join(sorted({f"{f['layer']}/{f['rule']}" for f in found}))
        else:
            misses.append(d)
            verdict, by = "MISS", ""
        rows.append((d["id"], d["detectable_by"], d["klass"], verdict, by))

    w = max(len(r[0]) for r in rows)
    print(f"{'defect':{w}} {'by':7} {'class':22} {'verdict':12} found by")
    print("-" * (w + 60))
    for r in rows:
        print(f"{r[0]:{w}} {r[1]:7} {r[2]:22} {r[3]:12} {r[4]}")

    reachable = len(hits) + len(misses)
    print(
        f"\n{len(hits)}/{reachable} reachable defects found "
        f"({len(unreachable)} unreachable by construction, covered by the "
        f"router's unconditional T2 question)"
    )
    for group in ("dom", "pixels"):
        ds = [d for d in manifest["defects"] if d["detectable_by"] == group]
        h = sum(1 for d in ds if d in hits)
        u = sum(1 for d in ds if d in unreachable)
        print(f"  {group:7} {h}/{len(ds) - u} reachable" + (f"  (+{u} unreachable)" if u else ""))
    for d in misses:
        print(f"  MISS {d['id']}: {d['summary'][:100]}")
    return 1 if misses else 0


if __name__ == "__main__":
    raise SystemExit(main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "corpus/out").resolve()))
