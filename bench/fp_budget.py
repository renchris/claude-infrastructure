#!/usr/bin/env python3
"""The false-positive budget: every rule re-run against the clean control.

§8 item 2 of the wave README. ~20% false positives is where an AI reviewer loses
credibility regardless of catch rate, and the two zero-FP runs already measured are
the baseline to defend. This is the gate that defends them: **no rule ships until it
has been re-run against the clean control**, and this file is how that is checked
rather than remembered.

It is deliberately a standalone acceptance script and not part of the repo's
commit-time gate, because it needs a browser and a rendered corpus. Run it after
`build_corpus.py` + `capture.py`; it exits non-zero when the budget is breached.

--------------------------------------------------------------------------------
What counts as a false positive, and what does not
--------------------------------------------------------------------------------
A false positive is a DEFECT CLAIM on a page with no defect. An ABSTENTION on the
control is not one -- it is the layer reporting honestly that it cannot decide,
which is the most valuable thing the deterministic layer produces. Summing the two
into one number would report the seam as the defect.

They are still both budgeted, because they fail differently and the failures are
not interchangeable:

    a false positive costs the reader's TRUST -- budget 0, hard gate
    an abstention costs a MODEL CALL     -- budget: reported, and it must not grow
                                            faster than the corpus

The second budget is the one that rots quietly. Every new rule that can abstain
adds to the vision layer's bill, and the bill is paid per page, so a rule abstaining
on a component present on every page multiplies. That number is printed here next
to the router's own routed count so the two can be compared: a large gap between
`raised` and `routed` means the cross-check and the baseline are doing their job.

--------------------------------------------------------------------------------
The corpus's own second FP class, and why it is REPORTED rather than gated
--------------------------------------------------------------------------------
`manifest.json` defines a false positive as a claim on the control *or on an
unmodified element of a defect page*. The second half cannot be gated honestly
here: the manifest's `target` is a CSS selector (`.kpi-card:nth-child(3)`) and a
finding's target is a captured path (`div.kpi-row:nth-of-type(2) > div.kpi-card:
nth-of-type(3)`), and matching them is a heuristic, not an equality. A gate built on
a heuristic fails in both directions and gets bypassed within a month.

So off-target claims are counted, listed and left to a human. Several are genuinely
correct -- `overflow-clip` clips three table cells and all three are real, and the
`spacing-gap` variant genuinely breaks both the rhythm rule and the grid rule on the
same element. Calling those false would be worse than not measuring them.

--------------------------------------------------------------------------------
Red-proof
--------------------------------------------------------------------------------
A gate that has never been seen to fail is not known to be a gate. This one was
proven red by raising `detect_dom.CONTRAST_MIN` from 4.5 to 21.0, which no real
colour pair can satisfy: 26 false positives on the control, exit 1. Restoring the
constant returned exit 0. Re-run that exact perturbation after any change here.

Usage: python3 fp_budget.py <corpus-dir> [--profile <name>]
Exit:  0 = budget held · 1 = a rule claimed a defect on the clean control
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import re
import sys

import detect_dom
import detect_xcheck
import profiles
from verdict import abstentions, claims

CREDIBILITY_FP_RATE = 0.20  # where an AI reviewer loses the room, per §8 item 2


def target_classes(selector: str) -> set[str]:
    """Class tokens in a manifest defect selector, e.g. '.btn-primary' -> {btn-primary}."""
    return set(re.findall(r"\.([A-Za-z0-9_-]+)", selector))


def on_target(finding_path: str, selector: str) -> bool:
    """Heuristic: does this finding point at the element the defect was injected on?

    Advisory only -- see the module docstring for why this is not a gate.
    """
    cls = target_classes(selector)
    return bool(cls) and cls <= set(re.findall(r"[A-Za-z0-9_-]+", finding_path))


def main(corpus: pathlib.Path, profile_name: str) -> int:
    manifest = json.loads((corpus / "manifest.json").read_text())
    control = pathlib.Path(manifest["control"]).stem
    tokens = manifest["tokens"]

    # Run BOTH detectors here rather than reading their JSON, so the budget can
    # never certify a stale findings file that no longer matches the rules on disk.
    snaps = corpus / "snapshots"
    dom = {
        f.stem: detect_dom.find(json.loads(f.read_text()), tokens)
        for f in sorted(snaps.glob("*.json"))
    }
    xchk = detect_xcheck.run(corpus)
    allf = {k: dom.get(k, []) + xchk.get(k, []) for k in dom}

    if control not in allf:
        print(f"FAIL: no control page {control!r} in the corpus", file=sys.stderr)
        return 1

    # --- 1. the hard gate: zero defect claims on the clean control ------------
    ctrl_claims = claims(allf[control])
    ctrl_abstain = abstentions(allf[control])
    by_rule = collections.Counter(f["rule"] for f in ctrl_claims)

    print(f"CONTROL  {control}.html")
    print(
        f"  false positives : {len(ctrl_claims)}"
        f"{'   <-- BUDGET BREACHED' if ctrl_claims else '   (budget held)'}"
    )
    for rule, n in sorted(by_rule.items()):
        print(f"      [{rule}] x{n}")
    for f in ctrl_claims:
        print(f"      {f['target']}: {f['detail'][:90]}")
    print(f"  abstentions     : {len(ctrl_abstain)}  (not false positives)")
    for f in ctrl_abstain:
        print(f"      [{f['rule']}] {f['target']}")

    # --- 2. every rule, and whether this corpus exercises it ------------------
    fired = collections.Counter(f["rule"] for fs in allf.values() for f in fs)
    ctrl_only = {
        r
        for r in fired
        if all(f["rule"] != r for p, fs in allf.items() if p != control for f in fs)
    }
    declared = set(detect_dom.RULES) | set(detect_xcheck.RULES)
    print(
        f"\nRULE COVERAGE  ({len(fired)} of {len(declared)} declared rule(s) fired "
        f"across {len(allf)} pages)"
    )
    for rule, n in sorted(fired.items()):
        note = "  <-- fires ONLY on the control" if rule in ctrl_only else ""
        print(
            f"  {rule:32} {n:3d} finding(s) · {by_rule.get(rule, 0)} on the control{note}"
        )
    # A rule that never fires anywhere has never been re-run against the control in
    # any meaningful sense -- the corpus simply cannot speak to it. That is not a
    # failure, but it must not read as coverage.
    for rule in sorted(declared - set(fired)):
        print(f"  {rule:32}   0 finding(s) · NOT EXERCISED by this corpus")
    for rule in sorted(set(fired) - declared):
        print(f"  {rule:32} {fired[rule]:3d} finding(s) · UNDECLARED — add it to RULES")

    # --- 3. advisory: claims on a defect page that miss the injected target ---
    defects = {d["id"]: d for d in manifest["defects"]}
    base_keys = {(f["rule"], f["target"], f["detail"]) for f in allf[control]}
    off = []
    for page, fs in sorted(allf.items()):
        if page == control or page not in defects:
            continue
        for f in claims(fs):
            if (f["rule"], f["target"], f["detail"]) in base_keys:
                continue  # inherited from the control, already gated above
            if not on_target(f["target"], defects[page]["target"]):
                off.append((page, f))
    novel = sum(
        1
        for page, fs in allf.items()
        if page != control
        for f in claims(fs)
        if (f["rule"], f["target"], f["detail"]) not in base_keys
    )
    rate = (len(off) / novel) if novel else 0.0
    print(
        f"\nOFF-TARGET CLAIMS (advisory)  {len(off)} of {novel} novel claim(s) "
        f"= {rate:.0%}  [credibility threshold {CREDIBILITY_FP_RATE:.0%}]"
    )
    for page, f in off:
        print(f"  {page:22} [{f['rule']:22}] {f['target'][:60]}")

    # --- 4. the abstention bill, which is the OTHER budget -------------------
    raised = sum(len(abstentions(fs)) for fs in allf.values())
    plan_path = corpus / "route" / "route-plan.json"
    routed = "not planned yet (run route.py)"
    if plan_path.exists():
        plan = json.loads(plan_path.read_text())
        routed = sum(p["accounting"]["abstentions_routed"] for p in plan["pages"])
        routed = f"{routed} routed after the cross-check and baseline subtractions"
    print(f"\nABSTENTION BILL  {raised} raised across {len(allf)} pages · {routed}")

    # --- 5. what the active profile mutes, so a weighting change is visible ---
    ranked = profiles.rank(
        profile_name, [f for fs in allf.values() for f in claims(fs)]
    )
    muted = [g for g in ranked if g["muted"]]
    prof = profiles.profile(profile_name)
    print(
        f"\nPROFILE {profile_name} ({prof['app']})  "
        f"{len(muted)} of {len(ranked)} claim(s) muted below weight {profiles.MUTE_BELOW}"
    )
    for rule, n in sorted(collections.Counter(g["rule"] for g in muted).items()):
        print(f"  {rule:32} x{n}  (weight {profiles.weight(profile_name, rule)})")

    ok = not ctrl_claims
    print(f"\n{'PASS' if ok else 'FAIL'}: false-positive budget on the clean control")
    return 0 if ok else 1


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", default="corpus/out", type=pathlib.Path)
    ap.add_argument("--profile", default="default", choices=sorted(profiles.PROFILES))
    a = ap.parse_args()
    sys.exit(main(a.corpus.resolve(), a.profile))
