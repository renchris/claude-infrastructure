#!/usr/bin/env python3
"""The false-positive budget: run every registered rule against clean pages.

README section 8 item 2 and PIPELINE_SPEC C18. This is the ship gate, and it is
the one measurement the whole programme's safety argument rests on, so it is
worth being precise about what it does and does not claim.

What it enforces
----------------
**Absolute zero asserted findings on the control, at n = 1.** A rule that fires
on a page with no defect will fire on every page. No exceptions, and explicitly
no baseline-diff suppression: subtracting the control's own findings from every
other page turns a broken rule into a quiet one and leaves the report looking
healthy. Both existing detectors have run clean here; that is the number every
new rule has to match before it ships.

**An abstention is not a false positive.** `contrast-indeterminate` on a clean
page with a gradient hero is the rule being right. Abstentions are counted and
printed separately, and they are the router's input rather than a defect. Folding
them into the gate would punish exactly the behaviour this pipeline was built to
reward.

**Every registered rule is accounted for.** A rule that emitted nothing because
it found nothing, and a rule that emitted nothing because it never ran, look
identical in a findings file and mean opposite things. The per-rule table carries
the subject-check count, so a rule with zero subjects is visible as unproven
rather than passing.

What it refuses to claim
------------------------
**No false-positive RATE below 16 clean pages.** 3/16 = 18.75% is the first n
strictly under the ~20% credibility cliff where an AI reviewer stops being read.
The blind judge run this programme quotes was n = 8, which bounds its rate at
3/8 = 37.5% -- nearly twice the cliff -- and for a long time it was written up as
23.1% from a denominator of 13 that no run ever used. So the rate is withheld,
loudly, with the deficit stated, rather than computed from whatever n happens to
be available.

**The budget is stated per 1,000 subject-checks, never per run.** False-positive
supply grows with subject count, not page count. This corpus is ~48 elements a
page against a real page's ~1,841 subjects, so a per-run zero here is roughly one
thirty-fifth of the exposure a real audit has, and saying "zero false positives"
without that denominator overstates it by that factor.

The instrument this wants and does not have is PIPELINE_SPEC B0: ~315 pages mined
from the three apps' own git history that shipped and were never touched by a
visual-bug fix. Every finding on that set is a false positive by construction, at
zero labelling cost. Point `--clean-dir` at it when it exists and the withheld
rate becomes a measurement.

Usage:
  python3 fp_budget.py <corpus-dir>              gate the corpus control
  python3 fp_budget.py <corpus-dir> --clean-dir <dir>   ... plus a mined clean set
Exit: 0 = gate passed · 1 = a rule fired on a page with no defect
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

import detect_dom
import detect_xcheck
from rules import RULES

# PIPELINE_SPEC C18 ruling 2. The first n whose rule-of-three upper bound is
# strictly under the ~20% credibility cliff.
RATE_FLOOR_N = 16
# P4's census of one real route, for the honest denominator note.
REAL_PAGE_SUBJECTS = 1841


def clean_pages(corpus: pathlib.Path, all_pages: bool) -> list[str]:
    """Which pages in this directory carry no defect."""
    snaps = sorted(p.stem for p in (corpus / "snapshots").glob("*.json"))
    if all_pages:
        return snaps
    mpath = corpus / "manifest.json"
    if not mpath.exists():
        raise SystemExit(
            f"{corpus} has no manifest.json, so nothing there declares which "
            f"pages are clean. Pass --all-clean if every page in it is."
        )
    control = json.loads(mpath.read_text())["control"].rsplit(".", 1)[0]
    if control not in snaps:
        raise SystemExit(f"control page {control!r} has no snapshot under {corpus}")
    return [control]


def run(corpus: pathlib.Path, pages: list[str], tokens: dict) -> tuple[list, dict]:
    findings, census = [], {}
    for page in pages:
        snap = json.loads((corpus / "snapshots" / f"{page}.json").read_text())
        for f in detect_dom.find(snap, tokens, census):
            findings.append(dict(f, page=page, corpus=corpus.name))
        png = corpus / "shots" / f"{page}.png"
        if png.exists():
            for f in detect_xcheck.check(snap, png, census):
                findings.append(dict(f, page=page, corpus=corpus.name))
        else:
            print(
                f"  note: {page} has no screenshot, so the cross-check arms did "
                f"not run on it. Run capture.py to close that hole.",
                file=sys.stderr,
            )
    return findings, census


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path)
    ap.add_argument(
        "--clean-dir",
        type=pathlib.Path,
        action="append",
        default=[],
        help="a directory whose every page is clean by construction "
        "(PIPELINE_SPEC B0, the mined corpus)",
    )
    ap.add_argument(
        "--all-clean",
        action="store_true",
        help="treat every page of <corpus> as clean, not just its control",
    )
    a = ap.parse_args()

    corpus = a.corpus.resolve()
    tokens = json.loads((corpus / "manifest.json").read_text())["tokens"]

    sets = [(corpus, clean_pages(corpus, a.all_clean))]
    for d in a.clean_dir:
        d = d.resolve()
        sets.append((d, clean_pages(d, True)))

    findings, census, n_clean = [], {}, 0
    for cdir, pages in sets:
        n_clean += len(pages)
        fs, cs = run(cdir, pages, tokens)
        findings += fs
        for k, v in cs.items():
            census[k] = census.get(k, 0) + v

    asserted = [f for f in findings if not RULES[f["rule"]].abstention]
    abstained = [f for f in findings if RULES[f["rule"]].abstention]
    checks = sum(census.values())

    where = ", ".join(f"{c.name}:{len(p)}" for c, p in sets)
    print("FALSE-POSITIVE BUDGET")
    print(f"clean pages: {n_clean}   ({where})")
    print()

    print("SHIP GATE — absolute zero ASSERTED findings on a page with no defect")
    if asserted:
        print(f"  ✗ FAIL: {len(asserted)} asserted finding(s) on clean pages")
        for f in asserted:
            print(
                f"      [{f['rule']:22}] {f['corpus']}/{f['page']} "
                f"{f['target'][:48]}\n        {f['detail'][:110]}"
            )
        print(
            "  Fix the rule or fix the control. Do NOT suppress by baselining "
            "the control's own findings — that is how a broken rule becomes a "
            "quiet one (PIPELINE_SPEC C18 ruling 1)."
        )
    else:
        print(f"  ✓ PASS: 0 asserted findings across {n_clean} clean page(s)")
    print(
        f"  ({len(abstained)} abstention(s), which are not false positives — "
        f"they are the router's input)"
    )
    print()

    print(f"{'per rule':24} {'subject-checks':>15} {'asserted':>9} {'abstained':>10}")
    print("-" * 61)
    never_ran = []
    for rid in sorted(RULES):
        n = census.get(rid, 0)
        af = sum(1 for f in asserted if f["rule"] == rid)
        ab = sum(1 for f in abstained if f["rule"] == rid)
        flag = "" if n else "   <- NEVER RAN"
        if not n:
            never_ran.append(rid)
        print(f"{rid:24} {n:15,d} {af:9d} {ab:10d}{flag}")
    if never_ran:
        print(
            f"\n  {len(never_ran)} rule(s) evaluated zero subjects on this clean "
            f"set, so this run says nothing about them: {', '.join(never_ran)}. "
            f"A rule with no subjects is unproven, not passing."
        )
    print()

    print("RATE")
    if n_clean < RATE_FLOOR_N:
        print(
            f"  WITHHELD. {n_clean} clean page(s); no false-positive rate may be "
            f"quoted below {RATE_FLOOR_N}, because 3/{RATE_FLOOR_N} = "
            f"{3 / RATE_FLOOR_N * 100:.2f}% is the first n strictly under the "
            f"~20% credibility cliff."
        )
        print(
            f"  {RATE_FLOOR_N - n_clean} more clean page(s) needed. Until then "
            f"this run is a GATE, not a measurement — mine the clean corpus "
            f"(PIPELINE_SPEC B0) and pass it as --clean-dir."
        )
    else:
        rate = len(asserted) / n_clean
        bound = 3 / n_clean if not asserted else rate
        print(f"  observed: {rate * 100:.2f}% of clean pages carry >=1 asserted finding")
        print(
            f"  95% upper bound: {bound * 100:.2f}% "
            f"({'rule of three, zero observed' if not asserted else 'observed rate'})"
        )
    print()

    print("BUDGET, per 1,000 subject-checks")
    per_k = len(asserted) / checks * 1000 if checks else 0.0
    print(f"  {per_k:.3f} asserted findings per 1,000 checks   ({checks:,d} checks)")
    print(
        f"  Denominator note: these pages average {checks // max(1, n_clean):,d} "
        f"subject-checks against ~{REAL_PAGE_SUBJECTS:,d} subjects on one real "
        f"route — roughly 1/{max(1, REAL_PAGE_SUBJECTS * len(RULES) // max(1, checks // max(1, n_clean)))}th "
        f"of the exposure an audit has. FP supply grows with subject count, not "
        f"page count."
    )
    print()

    import profiles as profiles_mod

    print("PER PROFILE — a rule at weight 0 cannot contribute a false positive")
    for name in sorted(profiles_mod.load()):
        w = profiles_mod.weights_for(None if name == "default" else name)
        live = [f for f in asserted if w.get(f["rule"], 1.0) > 0]
        off = [r for r in RULES if w.get(r, 1.0) == 0]
        print(
            f"  {name:24} {len(live):3d} asserted"
            + (f"   ({len(off)} rule(s) off: {', '.join(sorted(off))})" if off else "")
        )

    return 1 if asserted else 0


if __name__ == "__main__":
    raise SystemExit(main())
