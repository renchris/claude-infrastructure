#!/usr/bin/env python3
"""Apply a per-app rule profile to a findings file: rank, and declare what it dropped.

Three apps, three different problems, one harness. `reso-landing-app` is a
purchased template and the question asked of it is a marketing-aesthetics one;
`reso-management-app` is design-system conformance, where the deterministic layer
does nearly all the work; `reso-web-app` sits between. Same rules, same
measurements, different reading order.

The whole design is in one sentence: **a profile may reorder and it may abstain,
and it may not do anything else.** It cannot change a finding's truth value, it
cannot mint or soften a severity, and it cannot make a rule disappear quietly --
a rule a profile turns off emits an abstention naming the profile and the reason,
which is the same discipline the contrast rule already follows for a gradient. A
weighting that silently suppressed a class would be a false-clean generator with
an app's name on it, and it would be invisible in exactly the reports someone
trusts most.

`profiles.json` holds the policy. Its app rows rest on premises that C11 ruled
must be generated rather than written, so each carries a `basis` and loses to a
live surface read.

Usage:
  python3 profiles.py <corpus-dir> [--app reso-management-app] [--page clean]
"""

from __future__ import annotations

import argparse
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
SEVERITY_RANK = {"high": 3.0, "medium": 2.0, "low": 1.0}


class Profile:
    def __init__(self, name: str, cfg: dict, spec: dict):
        self.name = name
        self.cfg = cfg
        self.family_of = {
            rule: fam for fam, rules in spec["families"].items() for rule in rules
        }
        self.requirements = spec["requirements"]
        self.provides = set(cfg.get("provides", []))
        self.withheld = cfg.get("withheld", {})

    def family(self, rule: str) -> str:
        return self.family_of.get(rule, "conformance")

    def weight(self, rule: str) -> float:
        return float(self.cfg["weights"].get(self.family(rule), 1.0))

    def unmet(self, rule: str) -> tuple[str, str] | None:
        """-> (requirement, why it is withheld) when this rule cannot run here."""
        for req, rules in self.requirements.items():
            if rule in rules and req not in self.provides:
                return req, self.withheld.get(req, "not available under this profile")
        return None

    def apply(self, findings: list[dict]) -> tuple[list[dict], list[dict]]:
        """-> (ranked findings, abstentions). Nothing is dropped; it is moved."""
        ranked, abstained = [], []
        for f in findings:
            unmet = self.unmet(f["rule"])
            if unmet:
                req, why = unmet
                abstained.append(
                    {
                        "rule": f["rule"],
                        "target": f["target"],
                        "verdict": "INDETERMINATE",
                        "reason": f"rule needs {req}, which the {self.name} profile "
                        f"withholds: {why}",
                        "withheld_finding": f["detail"],
                    }
                )
                continue
            w = self.weight(f["rule"])
            ranked.append(
                {
                    **f,
                    "family": self.family(f["rule"]),
                    "weight": w,
                    # Rank only. Severity is the rule's and is carried unchanged.
                    "rank": round(w * SEVERITY_RANK.get(f.get("severity"), 2.0), 3),
                }
            )
        ranked.sort(key=lambda f: (-f["rank"], f["rule"], f["target"]))
        return ranked, abstained


def load(app: str) -> Profile:
    spec = json.loads((HERE / "profiles.json").read_text())
    if app not in spec["profiles"]:
        raise SystemExit(
            f"unknown app {app!r}; profiles.json declares "
            f"{', '.join(sorted(spec['profiles']))}"
        )
    return Profile(app, spec["profiles"][app], spec)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path)
    ap.add_argument("--app", default="default")
    ap.add_argument("--page", help="one page, instead of every page in the corpus")
    a = ap.parse_args()

    corpus = a.corpus.resolve()
    prof = load(a.app)
    findings: dict[str, list[dict]] = {}
    for name in ("findings_dom.json", "findings_xcheck.json"):
        f = corpus / name
        if not f.exists():
            continue
        for page, fs in json.loads(f.read_text()).items():
            findings.setdefault(page, []).extend(fs)

    pages = [a.page] if a.page else sorted(findings)
    out = {}
    for page in pages:
        ranked, abstained = prof.apply(findings.get(page, []))
        out[page] = {"ranked": ranked, "abstained": abstained}

    (corpus / f"findings_ranked.{a.app}.json").write_text(json.dumps(out, indent=1))
    print(f"profile {a.app} -- {prof.cfg['stance']}")
    for req, why in prof.withheld.items():
        print(f"  withholds {req}: {why[:88]}")
    for page in pages:
        r, ab = out[page]["ranked"], out[page]["abstained"]
        if not r and not ab:
            continue
        print(f"\n{page}  ({len(r)} ranked, {len(ab)} abstained)")
        for f in r[:6]:
            print(
                f"    {f['rank']:5.2f} [{f['family']:13}] {f['rule']:22} "
                f"{f['detail'][:60]}"
            )
        for x in ab[:3]:
            print(f"    ABSTAIN  {x['rule']:22} {x['reason'][:72]}")


if __name__ == "__main__":
    main()
