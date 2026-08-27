#!/usr/bin/env python3
"""The false-positive budget: every rule, re-run against the clean control.

~20% false positives is where an AI reviewer loses credibility regardless of
catch rate. This is the gate that defends the distance to that line, and it is
the one gate every new rule has to pass before it ships. Three claims, kept
separate on purpose, because collapsing them is how a bound gets quoted as a
measurement (PIPELINE_SPEC.md section 2 C18):

  1. ABSOLUTE ZERO ON THE CONTROL IS THE SHIP GATE, and it is enforceable at
     n = 1. A rule that fires on a page with no defect will fire on every page.
     No exceptions and no baseline-diff suppression -- subtracting the control's
     own findings from every other page is precisely how a noisy rule survives.
     Non-zero here exits 1.
  2. NO FALSE-POSITIVE RATE MAY BE PRINTED BELOW n = 16 CLEAN PAGES. 3/16 =
     18.75% is the first n strictly under the ~20% cliff, so below it the honest
     output is the deficit, not a number. This harness refuses rather than
     rounding, and prints how many clean pages it is short.
  3. THE BUDGET IS STATED PER 1,000 SUBJECT-CHECKS, never per run. One corpus
     page here puts 47 elements to a rule; one real route puts 1,841. False
     positives scale with subjects, not with pages, so a per-run rate measured
     on this corpus understates a real audit by a factor of ~35.

Point 3 is why the detectors now return a census. A finding count with no
denominator cannot be compared between two corpora, which makes it useless for
exactly the mined-clean-corpus run (B0) this harness exists to serve.

Usage:
  python3 fp_budget.py <corpus-dir> [<more-corpus-dirs>...] [--x2] [--clean-glob 'clean*']
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import sys

import detect_dom
import detect_xcheck

# The n at which a 3-of-n rule-of-three bound first sits under the ~20% cliff.
RATE_MIN_CLEAN_PAGES = 16
CLIFF = 0.20


def clean_pages(corpus: pathlib.Path, glob: str) -> list[tuple[str, pathlib.Path]]:
    snaps = corpus / "snapshots"
    return [(f.stem, f) for f in sorted(snaps.glob(f"{glob}.json"))]


def run(corpora: list[pathlib.Path], glob: str, x2: bool) -> dict:
    fps: dict[str, list[dict]] = collections.defaultdict(list)
    census: collections.Counter = collections.Counter()
    pages, envs = [], []

    for corpus in corpora:
        manifest = json.loads((corpus / "manifest.json").read_text())
        env_file = corpus / "run_env.json"
        if env_file.exists():
            envs.append(json.loads(env_file.read_text()))
        for stem, snap_file in clean_pages(corpus, glob):
            snap = json.loads(snap_file.read_text())
            page_census: collections.Counter = collections.Counter()
            found = detect_dom.find(snap, manifest["tokens"], census=page_census)
            png = detect_xcheck.best_shot(corpus / "shots", stem)
            if png is not None:
                found += detect_xcheck.check(snap, png, x2=x2, census=page_census)
            census.update(page_census)
            pages.append(f"{corpus.parent.name}/{corpus.name}/{stem}")
            for f in found:
                fps[f["rule"]].append(
                    {**f, "page": f"{corpus.parent.name}/{corpus.name}/{stem}"}
                )

    return {
        "clean_pages": pages,
        "subject_checks": dict(census),
        "false_positives": {k: v for k, v in fps.items()},
        "x2_enabled": x2,
        "render_env": envs,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpora", type=pathlib.Path, nargs="+")
    ap.add_argument("--x2", action="store_true", help="include the X2 centroid arm")
    ap.add_argument("--clean-glob", default="clean*")
    ap.add_argument("--json", type=pathlib.Path, help="write the full result here")
    a = ap.parse_args()

    r = run([c.resolve() for c in a.corpora], a.clean_glob, a.x2)
    n = len(r["clean_pages"])
    total_fp = sum(len(v) for v in r["false_positives"].values())
    total_checks = sum(r["subject_checks"].values())

    print(
        f"FALSE-POSITIVE BUDGET -- {n} clean page(s), "
        f"{total_checks} subject-check(s), X2 {'on' if a.x2 else 'off'}"
    )
    for env in r["render_env"]:
        print(
            f"  rendered by Chromium {env.get('browser')} on {env.get('platform')} "
            f"at dpr {env.get('device_scale_factors')}"
        )
    print()

    # Every rule that ran, whether or not it fired. A rule that is absent from
    # this table has not been cleared -- it has not been tested.
    print(f"  {'rule':24} {'subject-checks':>14} {'FP':>4}  per 1,000 checks")
    for rule in sorted(set(r["subject_checks"]) | set(r["false_positives"])):
        checks = r["subject_checks"].get(rule, 0)
        fp = len(r["false_positives"].get(rule, []))
        per_k = f"{1000 * fp / checks:.2f}" if checks else "n/a"
        mark = "  <-- FIRES ON A CLEAN PAGE" if fp else ""
        print(f"  {rule:24} {checks:14d} {fp:4d}  {per_k:>16}{mark}")

    for rule, items in sorted(r["false_positives"].items()):
        for f in items:
            print(f"\n  [{rule}] {f['page']} :: {f['target']}\n    {f['detail']}")

    print()
    if n < RATE_MIN_CLEAN_PAGES:
        # The deficit, not a rounded number. A rate quoted from too small an n is
        # the failure this section of the spec was rewritten to stop.
        print(
            f"RATE WITHHELD: {n} clean page(s) against the {RATE_MIN_CLEAN_PAGES} "
            f"needed before any false-positive RATE may be quoted "
            f"(3/{RATE_MIN_CLEAN_PAGES} = 18.75% is the first bound under the "
            f"{CLIFF:.0%} credibility cliff). Short by "
            f"{RATE_MIN_CLEAN_PAGES - n}. Mine clean screens from the apps' own "
            f"git history -- every finding on a page that shipped and was never "
            f"touched by a visual-bug fix is a false positive by construction."
        )
    else:
        print(
            f"false-positive rate: {total_fp}/{n} pages = {total_fp / n:.2%} "
            f"({1000 * total_fp / max(total_checks, 1):.2f} per 1,000 subject-checks)"
        )

    if a.json:
        a.json.write_text(json.dumps(r, indent=1))

    if total_fp:
        print(
            f"\nSHIP GATE: FAILED -- {total_fp} finding(s) on a page with no defect. "
            f"A rule that fires here fires everywhere; fix it or ship it disabled."
        )
        sys.exit(1)
    print("\nSHIP GATE: PASSED -- zero findings on every clean page.")


if __name__ == "__main__":
    main()
