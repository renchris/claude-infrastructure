#!/usr/bin/env python3
"""The false-positive budget: the gate every new rule has to pass before it ships.

About 20% false positives is where an AI reviewer loses its credibility regardless
of catch rate, because the reader stops reading. Two zero-FP runs are the baseline
this bench has to defend, and defending it means re-running EVERY rule against the
clean control every time one is added or changed -- not once, at authoring time,
by the person who is most convinced the rule is right.

This measures two different things, and conflating them is how a bench flatters
itself:

  CONTROL FP   findings on clean.html, where by construction nothing is wrong.
               The budget here is ZERO, not 20%. A rule that fires on the control
               is overfitted or noisy and its findings everywhere else are worth
               nothing -- the corpus's own scoring note says so. This is a hard
               gate: non-zero exits non-zero.

  OFF-TARGET FP  on a variant page, findings that are not about the injected
               defect. The manifest defines a false positive as "reports a defect
               on the clean control, or on an unmodified element of a defect page",
               and this is the second half. The budget here IS the ~20% number.

               One honest wrinkle, stated rather than smoothed away: some
               off-target findings on this corpus are REAL. The hierarchy-inversion
               variant restyles the primary button to #EFF6FF/#3B82F6, which is a
               genuine 3.38:1 contrast failure and a genuine off-token colour. The
               injection created them; the rules are right to report them. They are
               counted as off-target anyway, because the alternative is a scorer
               that exonerates whatever it recognises -- and a budget you can argue
               your way out of is not a budget. The number this prints is therefore
               a CEILING on the true FP rate.

  PROFILE SAFETY  every profile in profiles.py, re-scored over the control. This is
               the invariant that a weighting can only suppress or reorder, never
               create, checked rather than asserted. If someone ever adds a
               profile that lowers a threshold, this is what catches it.

Usage: python3 fp_budget.py <corpus-dir> [--budget 0.20] [--profile NAME]
Exit:  0 all budgets held · 1 a budget was breached · 2 the corpus is not usable
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

import detect_dom
import detect_xcheck
import profiles

CONTROL = "clean"
DEFAULT_BUDGET = 0.20

SEG_CLASSES = re.compile(r"\.([A-Za-z0-9_-]+)")
NTH = re.compile(r":nth-(?:child|of-type)\((\d+)\)")


def on_target(path: str, selector: str) -> bool:
    """Does this finding's element path fall inside the defect's target?

    The manifest names targets as CSS selectors (`.kpi-card:nth-child(3)`,
    `.glyph-btn .glyph`) and the detectors emit rendered paths
    (`div.kpi-row:nth-of-type(2) > div.kpi-card:nth-of-type(3)`). Match on the
    selector's LEAF -- its classes, and its index if it carries one -- against any
    segment of the path.

    Any segment, not just the last, and that is deliberate: a finding on a button
    inside `.actions` is a finding about the region `.actions` names. Scoring it as
    off-target would inflate the FP rate with findings that are plainly about the
    defect, which is the mirror of the error the docstring above refuses to make.

    A finding on an element the selector names as an ANCESTOR counts too, and only
    those. The repaired X2 reports `.glyph-btn`, because the container is what
    makes the centring claim, while the manifest's target is `.glyph-btn .glyph`;
    scoring that true positive as a false one would be the scorer punishing the
    detector for being right about which element to blame. The bound is that the
    ancestor must appear IN THE MANIFEST'S OWN SELECTOR -- ground truth stays the
    thing that decides, and "any ancestor" would make `body` on-target for
    everything.
    """
    for chunk in reversed(selector.strip().split()):
        want = set(SEG_CLASSES.findall(chunk))
        if not want:
            continue
        idx = NTH.search(chunk)
        for seg in path.split(" > "):
            if not want <= set(SEG_CLASSES.findall(seg)):
                continue
            if idx:
                got = NTH.search(seg)
                if not got or got.group(1) != idx.group(1):
                    continue
            return True
    return False


def run(corpus: pathlib.Path, profile_name: str) -> dict:
    manifest = json.loads((corpus / "manifest.json").read_text())
    tokens = manifest["tokens"]
    profile = profiles.get(profile_name)
    targets = {d["id"]: d["target"] for d in manifest["defects"]}

    per_page = {}
    for f in sorted((corpus / "snapshots").glob("*.json")):
        shot = corpus / "shots" / f"{f.stem}.png"
        snap = json.loads(f.read_text())
        findings = detect_dom.find(snap, tokens)
        if shot.exists():
            findings += detect_xcheck.check(snap, shot)
        per_page[f.stem] = profiles.apply(profile, findings)
    return {"profile": profile_name, "per_page": per_page, "targets": targets}


def report(res: dict, budget: float) -> int:
    per_page, targets = res["per_page"], res["targets"]
    ctrl = per_page.get(CONTROL)
    if ctrl is None:
        print(f"fp_budget: no {CONTROL} page captured -- nothing can be graded")
        return 2

    failures = []
    print(f"profile: {res['profile']}")
    print(f"\nCONTROL  clean.html -- budget 0 finding(s), got {len(ctrl)}")
    for c in ctrl:
        print(f"    [{c['rule']}] {c['target']}: {c['detail'][:80]}")
    if ctrl:
        failures.append(f"{len(ctrl)} finding(s) on the clean control")

    # The control's own findings are subtracted from every variant: a rule that
    # fires everywhere including clean is one defect, not thirteen.
    base = {(c["rule"], c["target"], c["detail"]) for c in ctrl}
    tot_on, tot_off = 0, 0
    print(f"\nVARIANTS  budget {budget * 100:.0f}% off-target")
    for page, fs in sorted(per_page.items()):
        if page == CONTROL:
            continue
        novel = [f for f in fs if (f["rule"], f["target"], f["detail"]) not in base]
        sel = targets.get(page)
        on = [f for f in novel if sel and on_target(f["target"], sel)]
        off = [f for f in novel if f not in on]
        tot_on += len(on)
        tot_off += len(off)
        mark = " " if not off else "!"
        print(f"  {mark} {page:22} {len(on):2d} on-target  {len(off):2d} off-target")
        for f in off:
            print(f"        [{f['rule']}] {f['target'][-52:]}")

    n = tot_on + tot_off
    rate = (tot_off / n) if n else 0.0
    print(
        f"\n  {tot_on} on-target, {tot_off} off-target of {n} -> {rate * 100:.1f}% FP"
    )
    if rate > budget:
        failures.append(
            f"off-target rate {rate * 100:.1f}% over the {budget * 100:.0f}% budget"
        )

    # --- the profile-safety invariant ---------------------------------------
    print("\nPROFILE SAFETY  a weighting may suppress or reorder, never create")
    corpus_rules = {f["rule"] for fs in per_page.values() for f in fs}
    for name in sorted(profiles.PROFILES):
        p = profiles.get(name)
        scored = profiles.apply(p, ctrl)
        extra = len(scored) - len(
            [c for c in ctrl if profiles.weight_of(p, c["rule"]) > 0]
        )
        ok = len(scored) <= len(ctrl) and extra == 0
        print(
            f"  {'ok ' if ok else 'FAIL'} {name:18} control {len(ctrl)} -> {len(scored)}"
            f"   queue {p['queue']}/page"
        )
        if not ok:
            failures.append(f"profile {name} added findings to the control")

    unknown = profiles.unknown_rules(corpus_rules)
    if unknown:
        print(f"\n  !! rules with no axis in profiles.AXIS: {', '.join(unknown)}")
        failures.append(
            f"{len(unknown)} unclassified rule(s); every profile weights them 1.0"
        )

    print()
    for f in failures:
        print(f"BREACH  {f}")
    print("fp_budget: " + ("FAILED" if failures else "all budgets held"))
    return 1 if failures else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path)
    ap.add_argument("--budget", type=float, default=DEFAULT_BUDGET)
    ap.add_argument("--profile", default="default")
    a = ap.parse_args(argv[1:])
    corpus = a.corpus.resolve()
    if not (corpus / "manifest.json").exists():
        print(f"fp_budget: no manifest under {corpus}")
        return 2
    return report(run(corpus, a.profile), a.budget)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
