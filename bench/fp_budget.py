#!/usr/bin/env python3
"""The false-positive budget: re-run every rule against the clean control, and gate.

~20% false positives is where an AI reviewer loses credibility regardless of catch
rate, and the two zero-FP runs in the 2026-08-26 wave are the baseline to defend.
Defending it needs a mechanism, not an intention: the rule was stated in prose --
"every rule added must be re-run against the clean control before it ships" -- and
prose does not run. This does.

Three things it makes mechanical:

  1. THE CONTROL RUN IS THE GATE. Any rule with a finding on `clean.html` exits 1.
     A finding on the control is a false positive by construction, at zero
     labelling cost, which is why the control is the cheapest denominator we own.
  2. A RULE CANNOT SHIP UNBUDGETED. `BUDGETED` below is a registry, and a rule name
     that appears in output without an entry exits 1 naming itself. That is the
     ratchet: adding a rule and forgetting to measure it is now a red run rather
     than a silent widening of exposure. It is also the only part of this file that
     defends against the failure it exists for -- a control run nobody re-ran.
  3. THE DENOMINATOR IS PRINTED. The wave's own false-positive bound was computed
     on the wrong denominator (3/8 = 37.5%, not 3/13 = 23.1%) and the error was
     invisible because no denominator was stated beside the rate. Every rate here
     carries the count it was divided by.

The off-target column is reported and deliberately does NOT gate. A finding on an
element the variant did not touch is a false-positive CANDIDATE, not a false
positive: injecting `#EFF6FF` on a button really does create a real contrast
failure on that button, and a rule that reports it is right. Scoring those
automatically would either credit noise or convict a correct detector, so they are
named for a human instead of counted by a machine.

Usage: python3 fp_budget.py <corpus-dir> [--x2]
Exit:  0 = every enabled rule is quiet on the control · 1 = budget breached.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

import detect_dom
import detect_xcheck

# Every rule allowed to emit a finding, and whether it is on by default. A name
# missing from here is a hard failure -- see (2) in the docstring.
BUDGETED = {
    "spacing-rhythm": True,
    "grid-violation": True,
    "type-scale": True,
    "token-drift": True,
    "contrast": True,
    "contrast-indeterminate": True,
    "overflow": True,
    "touch-target": True,
    "misalignment": True,
    "xcheck-zero-ink": True,
    "xcheck-contrast-varies": True,
    # PROVISIONAL, off by default. Its two 2026-08-26 defects are fixed; the cost
    # printed by this run is the third, and is why it stays off.
    "xcheck-optical-centre": False,
}

CONTROL = "clean"

COMPOUND = re.compile(r"(?:\.[A-Za-z0-9_-]+|:nth-child\(\d+\)|[A-Za-z][A-Za-z0-9]*)")


def compounds(selector: str) -> list[list[str]]:
    """`.a:nth-child(2) .b` -> [['.a', ':nth-child(2)'], ['.b']]."""
    return [COMPOUND.findall(part) for part in selector.split() if part.strip()]


def segment_matches(seg: str, compound: list[str]) -> bool:
    for tok in compound:
        if tok.startswith("."):
            if tok not in {"." + c for c in re.findall(r"\.([A-Za-z0-9_-]+)", seg)}:
                return False
        elif tok.startswith(":nth-child("):
            n = tok[len(":nth-child(") : -1]
            if f":nth-of-type({n})" not in seg:
                return False
        elif not seg.startswith(tok):
            return False
    return True


def on_target(path: str, selector: str) -> bool:
    """True when the finding is on the injected element or inside its subtree.

    A relation defect (`hierarchy-inversion` names `.actions`) is reported on the
    children that carry it, so a descendant counts. Subsequence, not equality:
    the manifest names a CSS selector and the finding names a full path.
    """
    segs = path.split(" > ")
    want = compounds(selector)
    i = 0
    for seg in segs:
        if i < len(want) and segment_matches(seg, want[i]):
            i += 1
    return i == len(want)


def budget(corpus: pathlib.Path, with_x2: bool) -> dict:
    manifest = json.loads((corpus / "manifest.json").read_text())
    tokens = manifest["tokens"]
    targets = {d["id"]: d["target"] for d in manifest["defects"]}

    detect_xcheck.X2_ENABLED = with_x2
    per_page: dict[str, list[dict]] = {}
    for f in sorted((corpus / "snapshots").glob("*.json")):
        snap = json.loads(f.read_text())
        found = detect_dom.find(snap, tokens)
        png = corpus / "shots" / f"{f.stem}.png"
        if png.exists():
            found += detect_xcheck.check(snap, png)
        per_page[f.stem] = found

    control = per_page.get(CONTROL, [])
    # The key spans the CLAIM, not just its location. Deduplicating on
    # (rule, target) alone silently swallowed a real defect in the 2026-08-26
    # run -- the assertion-span-must-equal-its-subject failure -- and an arm
    # whose finding differs from the control only in its NUMBER is exactly the
    # case that key loses.
    baseline = {(c["rule"], c["target"], c["detail"]) for c in control}
    n_elements = len(
        json.loads((corpus / "snapshots" / f"{CONTROL}.json").read_text())["elements"]
    )

    rules: dict[str, dict] = {}
    unregistered = set()
    for page, findings in per_page.items():
        for f in findings:
            rule = f["rule"]
            if rule not in BUDGETED:
                unregistered.add(rule)
            r = rules.setdefault(
                rule,
                {
                    "enabled_by_default": BUDGETED.get(rule),
                    "control_fp": 0,
                    "control_where": [],
                    "on_target": 0,
                    "off_target": 0,
                    "off_target_where": [],
                    "pages_firing": 0,
                },
            )
            if page == CONTROL:
                r["control_fp"] += 1
                r["control_where"].append(f["target"])
                continue
            if (rule, f["target"], f["detail"]) in baseline:
                continue  # inherited from the control; already counted there
            sel = targets.get(page)
            if sel and on_target(f["target"], sel):
                r["on_target"] += 1
            else:
                r["off_target"] += 1
                r["off_target_where"].append(f"{page}: {f['target']}")
    for rule, r in rules.items():
        r["pages_firing"] = sum(
            1 for fs in per_page.values() if any(f["rule"] == rule for f in fs)
        )

    breaches = sorted(
        rule
        for rule, r in rules.items()
        if r["control_fp"] and BUDGETED.get(rule, False)
    )
    return {
        "corpus": str(corpus),
        "x2": with_x2,
        "denominators": {
            "control_pages": 1,
            "control_elements": n_elements,
            "corpus_pages": len(per_page),
            "defect_pages": len(per_page) - 1,
        },
        "rules": dict(sorted(rules.items())),
        "unregistered_rules": sorted(unregistered),
        "control_findings": len(control),
        "breaches": breaches,
        "verdict": (
            "BREACHED"
            if breaches or unregistered
            else ("CLEAN" if not control else "CLEAN (provisional arms only)")
        ),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", type=pathlib.Path, default="corpus/out")
    ap.add_argument("--x2", action="store_true", help="include the provisional arm")
    a = ap.parse_args()
    corpus = pathlib.Path(a.corpus).resolve()

    b = budget(corpus, a.x2)
    (corpus / "fp_budget.json").write_text(json.dumps(b, indent=1))
    d = b["denominators"]

    print(
        f"FALSE-POSITIVE BUDGET   control = {CONTROL}.html, "
        f"{d['control_elements']} elements; corpus = {d['corpus_pages']} pages"
    )
    print(
        f"{'rule':26} {'dflt':>4} {'ctrl FP':>7} {'on-tgt':>6} "
        f"{'off-tgt':>7}  verdict"
    )
    for rule, r in b["rules"].items():
        dflt = (
            "on"
            if r["enabled_by_default"]
            else ("off" if r["enabled_by_default"] is False else "??")
        )
        if r["enabled_by_default"] is None:
            verdict = "UNREGISTERED -- budget it before it ships"
        elif r["control_fp"] == 0:
            verdict = "ships"
        elif not r["enabled_by_default"]:
            verdict = (
                f"stays off -- fires on {r['pages_firing']}/{d['corpus_pages']} pages, "
                f"control included"
            )
        else:
            verdict = f"BLOCKED -- {r['control_fp']} FP on the control"
        print(
            f"{rule:26} {dflt:>4} {r['control_fp']:>7} {r['on_target']:>6} "
            f"{r['off_target']:>7}  {verdict}"
        )

    enabled = {k: v for k, v in b["rules"].items() if v["enabled_by_default"]}
    on_fp = sum(v["control_fp"] for v in enabled.values())
    print(
        f"\nenabled rules: {on_fp} control finding(s) over "
        f"{d['control_elements']} elements on {d['control_pages']} control page "
        f"= {on_fp / d['control_elements'] * 100:.1f}% of subject-checks, "
        f"against the ~20% credibility cliff"
    )
    for rule, r in b["rules"].items():
        if r["off_target_where"]:
            print(f"\noff-target, {rule} -- adjudicate by hand, not counted as FP:")
            for w in r["off_target_where"]:
                print(f"    {w}")
    if b["unregistered_rules"]:
        print(f"\nUNREGISTERED RULES: {b['unregistered_rules']}")
        print("    add each to BUDGETED with its default, then re-run this file.")
    if b["breaches"]:
        print(f"\nBUDGET BREACHED by {b['breaches']}")
    print(f"\nverdict: {b['verdict']}")
    return 1 if (b["breaches"] or b["unregistered_rules"]) else 0


if __name__ == "__main__":
    sys.exit(main())
