#!/usr/bin/env python3
"""Load and enforce the per-app review profiles.

README section 8, last paragraph: the three apps are three different problems --
a marketing-aesthetics one, a design-system-conformance one, and one between --
so there is one review harness and three rule weightings. This is the loader and,
more importantly, the enforcement.

Three rules it enforces, each because the alternative fails silently:

  A profile must weight EVERY registered rule. A missing key would take a
  default, and a default is how a rule quietly stops mattering for an app
  nobody re-read the profile for. Registering a rule in bench/rules.py now
  breaks every profile until someone decides what it means per app, which is
  the point.

  A profile may not weight a rule that does not exist. A renamed rule leaves a
  dead key behind, and a dead key looks exactly like a live one.

  A weight ranks, it never suppresses. 0.0 is legal and means the rule is OFF
  for that app -- a claim that it cannot be true there. Anything above 0.0
  orders the report and the router's crop budget and drops nothing. Ranking and
  suppression are kept apart because a weight that silently dropped findings
  would be a false-negative generator with no sensor on it.

What is deliberately NOT here: any fact about an app's framework, CSS engine,
token map or attribution capability. PIPELINE_SPEC C11 bans prose as a source for
those, and it earned that ban by getting three of its own cells wrong in the very
table that stated it. Stack facts belong in a GENERATED artifact read live from
the checkout. Every `stack` field here is null and stays null.

Usage: python3 profiles.py [--profile <app>] [--findings <file.json>]
"""

from __future__ import annotations

import argparse
import json
import pathlib

from rules import RULES, SEVERITY_RANK

HERE = pathlib.Path(__file__).resolve().parent
PROFILES_PATH = HERE / "review_profiles.json"


class ProfileError(ValueError):
    pass


def load() -> dict:
    doc = json.loads(PROFILES_PATH.read_text())
    profs = doc["profiles"]
    for name, p in profs.items():
        w = p["weights"]
        missing = sorted(set(RULES) - set(w))
        unknown = sorted(set(w) - set(RULES))
        if missing:
            raise ProfileError(
                f"profile {name!r} has no weight for {missing}. Every registered "
                f"rule needs one -- a default is how a rule quietly stops "
                f"mattering for an app."
            )
        if unknown:
            raise ProfileError(
                f"profile {name!r} weights {unknown}, which bench/rules.py does "
                f"not register. A dead key looks exactly like a live one."
            )
        for rid, v in w.items():
            if not isinstance(v, (int, float)) or v < 0:
                raise ProfileError(f"profile {name!r}: weight {rid}={v!r} is not >= 0")
        if p.get("stack") is not None:
            raise ProfileError(
                f"profile {name!r} carries a `stack` value. Stack facts are "
                f"generated from a live read of the checkout, never authored "
                f"here (PIPELINE_SPEC C11)."
            )
    return profs


def weights_for(name: str | None) -> dict[str, float]:
    profs = load()
    if name is None:
        return dict(profs["default"]["weights"])
    if name not in profs:
        raise ProfileError(
            f"unknown profile {name!r}; have {sorted(profs)}"
        )
    return dict(profs[name]["weights"])


def rank(findings: list[dict], weights: dict[str, float]) -> list[dict]:
    """Order findings for one app, and say why each landed where it did.

    Weight zero drops the finding, because zero is the one weight that is a claim
    about truth rather than about priority. Everything else is ordering.
    """
    out = []
    for f in findings:
        w = weights.get(f["rule"], 1.0)
        if w == 0.0:
            continue
        g = dict(f)
        g["weight"] = w
        g["rank_score"] = round(SEVERITY_RANK.get(f["severity"], 1) * w, 3)
        out.append(g)
    out.sort(key=lambda g: (-g["rank_score"], g["rule"], g["target"]))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", default=None)
    ap.add_argument(
        "--findings",
        type=pathlib.Path,
        default=None,
        help="a findings_*.json to re-rank under the profile",
    )
    a = ap.parse_args()
    profs = load()

    if a.findings is None:
        rids = sorted(RULES)
        names = [n for n in profs if n != "default"]
        w = max(len(r) for r in rids)
        print(f"{len(profs)} profiles over {len(RULES)} rules — all complete\n")
        print(f"{'rule':{w}} {'default':>8} " + " ".join(f"{n:>20}" for n in names))
        print("-" * (w + 9 + 21 * len(names)))
        for r in rids:
            row = f"{r:{w}} {profs['default']['weights'][r]:8.1f} "
            row += " ".join(f"{profs[n]['weights'][r]:20.1f}" for n in names)
            print(row)
        print()
        for n in names:
            print(f"{n:24} {profs[n]['review_intent']}")
        return 0

    weights = weights_for(a.profile)
    doc = json.loads(a.findings.read_text())
    flat = [dict(f, page=page) for page, fs in doc.items() for f in fs]
    ranked = rank(flat, weights)
    print(f"profile {a.profile or 'default'}: {len(ranked)} of {len(flat)} findings kept")
    for f in ranked[:20]:
        print(
            f"  {f['rank_score']:5.2f}  [{f['rule']:22}] {f['page']:20} "
            f"{f['target'][:44]}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
