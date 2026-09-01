#!/usr/bin/env python3
"""Per-app rule weightings, and the one invariant a weighting file must not break.

The three apps are three different problems and one harness. `reso-landing-app`
is a purchased marketing template, so its conformance findings describe the
template's conventions rather than a defect, and what matters is whether the page
persuades -- which no rule reaches. `reso-management-app` is an internal dashboard
where conformance is nearly the whole job and the deterministic layer does nearly
all of it. `reso-web-app` sits between and is currently unaddressable on
conformance, because Emotion's runtime `css-<hash>` class names are not
invertible.

Two things this file is careful about, both of them ways a weighting file goes
wrong rather than ways it goes right:

**Weight 0 means ABSTAIN, never SKIP.** A skipped check and a clean check produce
the same bytes, so a weight of zero on a family that was silently dropped is
indistinguishable from a family that passed. Every zero-weighted subject is
emitted as INDETERMINATE and lands in the router's queue, where its cost is
visible.

**`correctness` is pinned and `load()` refuses a profile that lowers it.** Every
other weight is a product judgement. Contrast, overflow and touch-target are not:
"it is a marketing site" is a real argument about token drift and is not an
argument about 2.54:1 text. A weighting file is precisely where that conflation
would be made once, by someone reasonable, and then never re-read -- so the
refusal is code rather than a comment.

**The stack facts are NOT in here.** PIPELINE_SPEC C11 rules that a table which
bans prose as a source must be generated, and it earned that ruling by publishing
three wrong cells in the very fix that made the ruling. `profiles.json` therefore
ships an empty `measured` block and a clearly non-authoritative
`stack_reference`; `--measure` populates the real one from a checkout's own
`node_modules`, and anything that disagrees with that read loses automatically.

Usage:
  python3 profiles.py                       show every profile and its weights
  python3 profiles.py --measure <checkout>  read a checkout's real stack into
                                            profiles.json's `measured` block
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
PROFILES_PATH = HERE / "profiles.json"

# Packages worth resolving, and why each one changes a downstream decision.
PROBE_PACKAGES = {
    "next": "frame API shape: Next 14 reads lineNumber/colNumber, Next 16 reads line1/column1",
    "react": "_debugSource is present on React 18 and dead on React 19",
    "tailwindcss": "token map source; Tailwind 4 with no @theme has no token map at all",
    "@pandacss/dev": "second token engine; two engines in one chain need an explicit precedence",
    "@chakra-ui/react": "runtime css-<hash> class names, not invertible",
    "@emotion/react": "same, and autoLabel is the one-line fix",
    "framer-motion": "motion surface; pairs with the prefers-reduced-motion grep",
}


class ProfileError(Exception):
    """A weighting file that would silently weaken a check is a build failure."""


def load(path: pathlib.Path | None = None) -> dict:
    """Read profiles.json and refuse it if it lowers a pinned family."""
    doc = json.loads((path or PROFILES_PATH).read_text())
    pinned = {k for k, v in doc["families"].items() if v.get("pinned")}
    families = set(doc["families"])
    for name, prof in doc["profiles"].items():
        w = prof["weights"]
        missing = families - set(w)
        if missing:
            raise ProfileError(
                f"profile {name!r} does not weight {sorted(missing)}. An unweighted "
                f"family is an unstated decision, and it defaults to whatever the "
                f"reader assumes."
            )
        for fam in pinned:
            if w[fam] < 1.0:
                raise ProfileError(
                    f"profile {name!r} weights the pinned family {fam!r} at {w[fam]}. "
                    f"{doc['families'][fam]['pinned_because']}"
                )
        for fam, val in w.items():
            if not 0.0 <= val <= 1.0:
                raise ProfileError(
                    f"profile {name!r}: {fam} weight {val} is not in [0,1]"
                )
    return doc


def profile_for(app: str, doc: dict | None = None) -> tuple[str, dict]:
    """-> (profile name actually used, the profile). Falls back to `default`."""
    doc = doc or load()
    return (
        (app, doc["profiles"][app])
        if app in doc["profiles"]
        else (
            "default",
            doc["profiles"]["default"],
        )
    )


def family_of(rule: str, doc: dict | None = None) -> str | None:
    doc = doc or load()
    for fam, spec in doc["families"].items():
        if rule in spec["rules"]:
            return fam
    return None


def weigh(findings: list[dict], app: str, doc: dict | None = None) -> list[dict]:
    """Apply an app's weights to a finding list, in place of nothing being applied.

    A weight NEVER deletes a finding. It sets `weight` and, at zero, converts an
    assertion into an abstention -- which is a routing cost the pipeline can see,
    unlike a deletion. Below the advisory floor a finding still ships, marked
    `surfacing: "advisory"`, because the moment the app adopts a token map the
    weight goes back up and the history has to already be there.
    """
    doc = doc or load()
    name, prof = profile_for(app, doc)
    w = prof["weights"]
    for f in findings:
        fam = family_of(f["rule"].removesuffix("-indeterminate"), doc)
        if fam is None:
            f["weight"], f["family"], f["surfacing"] = 1.0, None, "surfaced"
            continue
        val = w[fam]
        f["family"], f["weight"], f["profile"] = fam, val, name
        if val == 0.0 and f["verdict"] == "asserted":
            f["verdict"] = "indeterminate"
            f["detail"] += (
                f" -- UNVERIFIED under the {name} profile: {fam} carries weight 0 "
                f"here, so this is routed rather than asserted"
            )
        f["surfacing"] = "surfaced" if val >= 0.5 else "advisory"
    return findings


def measure(checkout: pathlib.Path) -> dict:
    """Read a checkout's REAL stack out of its own node_modules.

    Declared and installed are recorded separately because C11 found them
    disagreeing (16.2.6 declared, 16.3.0 installed) and the frame API depends on
    the installed one.
    """
    pkg_path = checkout / "package.json"
    if not pkg_path.exists():
        raise ProfileError(f"no package.json under {checkout}")
    pkg = json.loads(pkg_path.read_text())
    declared = {**pkg.get("dependencies", {}), **pkg.get("devDependencies", {})}
    out: dict = {"checkout": str(checkout), "packages": {}}
    for name, why in PROBE_PACKAGES.items():
        inst = checkout / "node_modules" / name / "package.json"
        installed = json.loads(inst.read_text())["version"] if inst.exists() else None
        if name not in declared and installed is None:
            continue
        out["packages"][name] = {
            "declared": declared.get(name),
            "installed": installed,
            "matters_because": why,
        }
    engines = [
        n
        for n in ("tailwindcss", "@pandacss/dev")
        if n in out["packages"] and out["packages"][n]["installed"]
    ]
    out["token_map"] = {
        "engines": engines,
        # Two engines resolving the same declaration is the case where a confident
        # FAIL is worse than an abstention, because its truth value depends on
        # which resolver ran. Nothing may assert conformance until this is set.
        "precedence": None if len(engines) > 1 else (engines[0] if engines else None),
        "conformance_may_assert": len(engines) == 1,
    }
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--measure", type=pathlib.Path, help="a checkout to read")
    ap.add_argument("--app", help="show one profile")
    a = ap.parse_args()
    doc = load()

    if a.measure:
        m = measure(a.measure.resolve())
        doc["measured"][a.measure.resolve().name] = m
        PROFILES_PATH.write_text(json.dumps(doc, indent=2) + "\n")
        print(f"measured {a.measure.resolve().name} -> profiles.json['measured']")
        for n, p in m["packages"].items():
            print(
                f"  {n:20} declared {str(p['declared']):12} installed {p['installed']}"
            )
        print(
            f"  token engines: {m['token_map']['engines'] or 'none'}"
            f"   conformance may assert: {m['token_map']['conformance_may_assert']}"
        )
        return 0

    names = [a.app] if a.app else list(doc["profiles"])
    fams = list(doc["families"])
    print(f"{'profile':22} " + " ".join(f"{f[:11]:>11}" for f in fams) + "  images")
    for n in names:
        p = doc["profiles"][n]
        print(
            f"{n:22} "
            + " ".join(f"{p['weights'][f]:>11.2f}" for f in fams)
            + f"  {p['vision_budget_images']:>6}   {p['label']}"
        )
    print()
    for f, spec in doc["families"].items():
        pin = "  PINNED at 1.0" if spec.get("pinned") else ""
        print(f"  {f:14} {', '.join(spec['rules'])}{pin}")
    if not doc["measured"]:
        print(
            "\n  measured: EMPTY. Conformance abstains until a live read fills it:\n"
            "    python3 profiles.py --measure <checkout>\n"
            "  `stack_reference` in profiles.json is orientation only and nothing reads it."
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
