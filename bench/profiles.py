#!/usr/bin/env python3
"""Per-app rule weightings: one review harness, three different questions.

`reso-landing-app` is a purchased marketing template and `reso-management-app` is
an internal dashboard on our own design system. Running the same rule set over
both at the same weight produces a report that is wrong in opposite directions:
forty unactionable token-drift findings on the template, and a dashboard review
that leads with a judgement call when the deterministic layer already had the
answer. So the rules are shared and the WEIGHTS are per app.

Three things a weight is allowed to do, and one it is not:

  RANK      the report leads with what matters for this app.
  DEMOTE    below `surfacing_floor` a finding is `advisory`: printed, attributed,
            never asserted. It is not deleted -- a suppressed finding and an
            absent one must never be the same bytes.
  ROUTE     which unscreenable classes earn the page's image budget.

  SUPPRESS  never. A weight cannot take a finding out of the report and cannot
            touch the false-positive gate, which runs unweighted by construction
            (`fp_budget.py` asserts this rather than trusting it). A rule that
            fires on a clean page is broken at every weight, and a per-app knob
            that can hide that is a knob for hiding evidence.

Usage: python3 profiles.py [--list | <name>]
"""

from __future__ import annotations

import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_PATH = HERE / "profiles.json"

# The six classes no rule can screen (PIPELINE_SPEC S4/T2). A profile picks the
# subset its app actually fails at; it may not invent a seventh, because a class
# with no stated reason to exist is a model call with no stated reason to exist.
UNSCREENABLE = (
    "hierarchy",
    "gestalt",
    "content-fit",
    "semantic-coherence",
    "optical-alignment",
    "readability",
)


class Profile:
    def __init__(self, name: str, doc: dict, cfg: dict):
        self.name = name
        self.kind = doc.get("kind", "unknown")
        self.why = doc.get("why", [])
        self.stack = doc.get("stack")
        self.weights = doc.get("weights", {})
        self.t2_classes = [c for c in doc.get("t2_classes", []) if c in UNSCREENABLE]
        self.image_budget = int(doc.get("image_budget", 2))
        self.floor = float(cfg.get("surfacing_floor", 0.25))
        self.sev = cfg.get("severity_score", {})

    def weight(self, rule: str) -> float:
        """Unlisted rules weigh 1.0. A profile states its exceptions, not its world."""
        return float(self.weights.get(rule, 1.0))

    def rank(self, finding: dict) -> float:
        s = self.sev.get(finding.get("severity", "medium"), 2)
        return self.weight(finding["rule"]) * s

    def rung(self, finding: dict) -> str:
        """`asserted` or `advisory` -- and nothing is ever dropped."""
        return "advisory" if self.weight(finding["rule"]) < self.floor else "asserted"

    def apply(self, findings: list[dict]) -> list[dict]:
        out = []
        for f in findings:
            g = dict(f)
            g["weight"] = self.weight(f["rule"])
            g["rank"] = self.rank(f)
            g["rung"] = self.rung(f)
            out.append(g)
        return sorted(out, key=lambda g: -g["rank"])


def load(name: str | None = None, path: pathlib.Path | None = None) -> Profile:
    cfg = json.loads((path or DEFAULT_PATH).read_text())
    name = name or cfg["default_profile"]
    if name not in cfg["profiles"]:
        raise SystemExit(
            f"unknown profile {name!r}; have: {', '.join(sorted(cfg['profiles']))}"
        )
    return Profile(name, cfg["profiles"][name], cfg)


def names(path: pathlib.Path | None = None) -> list[str]:
    return sorted(json.loads((path or DEFAULT_PATH).read_text())["profiles"])


if __name__ == "__main__":
    if "--list" in sys.argv or len(sys.argv) == 1:
        cfg = json.loads(DEFAULT_PATH.read_text())
        for n in sorted(cfg["profiles"]):
            p = load(n)
            demoted = sorted(r for r in p.weights if p.weights[r] < p.floor)
            print(
                f"{n:18} {p.kind:26} budget={p.image_budget} t2={','.join(p.t2_classes)}"
            )
            print(f"{'':18} demoted below {p.floor}: {', '.join(demoted) or 'none'}")
    else:
        p = load(sys.argv[1])
        print(
            json.dumps({"name": p.name, "kind": p.kind, "weights": p.weights}, indent=1)
        )
