#!/usr/bin/env python3
"""Grade the instrument, and enforce the false-positive budget on the control.

Around 20% false positives is where an AI reviewer loses its credibility
regardless of catch rate -- a reviewer that cries wolf is switched off, and a
switched-off reviewer has a catch rate of zero. Two zero-FP runs are the baseline
this defends, and defending it is not a habit anybody can be trusted to keep by
hand: **every rule added must be re-run against the clean control before it
ships**, and that sentence is only true if something executes it.

So this is a gate, not a report. It exits non-zero when:

  * any rule makes an ASSERTED finding on the clean control (hard, budget zero --
    the control is correct by construction, so every finding on it is false);
  * the false-positive rate across the defect pages exceeds `--fp-budget`;
  * a rule exists in the detector source but was never exercised by the corpus,
    because an ungraded rule is exactly the one that ships a false positive.

An abstention is not a finding and is not counted against the budget. That
asymmetry is the whole design: an honest `INDETERMINATE` routes to the vision
layer, a false `PASS` routes nowhere, and a false ASSERTION routes an agent into
changing correct code.

WHAT COUNTS AS A FALSE POSITIVE, COMPUTED RATHER THAN LISTED
------------------------------------------------------------
A finding on a defect page is false if it lands on an element the injected CSS
did not touch. "Touched" is not a hand-maintained allowlist -- it is computed by
diffing each variant's snapshot against the control's, element by element, over
rect and computed styles. That matters because several injected defects have
legitimate collateral: restyling the two buttons to invert the hierarchy really
does drift a colour token and really does drop a contrast ratio, and calling
those false because the manifest names `.actions` as the target would be marking
the detector wrong for being right.

  true positive  -- novel, and points at the manifest's target for this defect
  collateral     -- novel, on an element the injected CSS did change, but not the
                    named target. Real, reported, not scored as a hit
  FALSE POSITIVE -- novel, on an element the injected CSS never touched

Usage: python3 score.py <corpus-dir> [--fp-budget 0.2] [--app <profile>]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

DETECTOR_SOURCES = ("detect_dom.py", "detect_xcheck.py")
# `rep("rule-name", ...)` is how both detectors emit. Finding the rules in the
# SOURCE rather than in the run is the point: a rule that fired nowhere is
# invisible to a report built from findings, and it is the one nobody graded.
RULE_RE = re.compile(r'\brep\(\s*\n?\s*"([a-z0-9-]+)"')

SEL_STEP = re.compile(r"\.([A-Za-z0-9_-]+)|:nth-(?:child|of-type)\((\d+)\)")
PATH_SEG = re.compile(r"^([a-z0-9]+)((?:\.[A-Za-z0-9_-]+)*)(?::nth-of-type\((\d+)\))?$")


def parse_selector(sel: str) -> list[tuple[set, int | None]]:
    """`.kpi-card:nth-child(4) .kpi-label` -> [({kpi-card}, 4), ({kpi-label}, None)]"""
    steps = []
    for part in sel.strip().split():
        classes, idx = set(), None
        for c, n in SEL_STEP.findall(part):
            if c:
                classes.add(c)
            if n:
                idx = int(n)
        steps.append((classes, idx))
    return steps


def parse_path(path: str) -> list[tuple[set, int | None]]:
    out = []
    for seg in path.split(" > "):
        m = PATH_SEG.match(seg.strip())
        if not m:
            out.append((set(), None))
            continue
        classes = {c for c in m.group(2).split(".") if c}
        out.append((classes, int(m.group(3)) if m.group(3) else None))
    return out


def matches(sel: str, path: str) -> bool:
    """Does this finding's element path satisfy the manifest's target selector?

    Descendant semantics, anchored at the end: the selector's last step must be
    the path's last segment, and its earlier steps must appear in order above it.
    `nth-child` and `nth-of-type` are treated as equal, which is true for every
    target in this corpus (each sits among same-tag siblings) and is checked by
    the run rather than assumed -- a mismatch shows up as a missed defect.
    """
    steps, segs = parse_selector(sel), parse_path(path)
    if not steps or not segs:
        return False

    def step_ok(step, seg):
        cls, idx = step
        return cls <= seg[0] and (idx is None or idx == seg[1])

    if not step_ok(steps[-1], segs[-1]):
        return False
    i = len(segs) - 2
    for step in reversed(steps[:-1]):
        while i >= 0 and not step_ok(step, segs[i]):
            i -= 1
        if i < 0:
            return False
        i -= 1
    return True


def claim_key(f: dict) -> tuple:
    mag = f.get("offset_px")
    return (f["rule"], f["target"], None if mag is None else round(mag))


def is_abstention(f: dict) -> bool:
    return f["rule"].endswith("-indeterminate")


def touched_paths(control: dict, variant: dict) -> set[str]:
    """The injected CSS's blast radius: elements it changed, and their subtrees.

    Diffing rect and computed styles finds the elements the rule landed on. The
    subtree has to come with them, because an element's RENDERING depends on its
    ancestors while its own computed styles do not: putting a gradient on `.hero`
    leaves `.hero-title`'s every style byte-identical and still changes what that
    title is painted over. Scoring the title's contrast finding as false would
    have marked the detector wrong for being right -- which is what this did
    before the subtree clause, on the one page built to exercise exactly that.
    """
    c = {e["path"]: e for e in control["elements"]}
    direct = set()
    for e in variant["elements"]:
        base = c.get(e["path"])
        if base is None or base["rect"] != e["rect"] or base["styles"] != e["styles"]:
            direct.add(e["path"])
    out = set(direct)
    for e in variant["elements"]:
        if any(e["path"].startswith(d + " > ") for d in direct):
            out.add(e["path"])
    return out


def declared_rules(bench: pathlib.Path) -> set[str]:
    rules = set()
    for name in DETECTOR_SOURCES:
        src = bench / name
        if src.exists():
            rules |= set(RULE_RE.findall(src.read_text()))
    return rules


def load_findings(corpus: pathlib.Path) -> dict[str, list[dict]]:
    out: dict[str, list[dict]] = {}
    for name in ("findings_dom.json", "findings_xcheck.json"):
        f = corpus / name
        if not f.exists():
            sys.exit(f"missing {f} -- run the detectors first")
        for page, fs in json.loads(f.read_text()).items():
            out.setdefault(page, []).extend(fs)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path)
    ap.add_argument(
        "--fp-budget",
        type=float,
        default=0.20,
        help="max share of novel findings on untouched elements, across defect "
        "pages. 0.20 is where an AI reviewer stops being believed; the run "
        "this defends is at 0.00.",
    )
    ap.add_argument(
        "--control-abstain-budget",
        type=int,
        default=0,
        help="max abstentions the CONTROL may raise. An abstention on a page "
        "that is correct by construction is not a false positive -- it is a "
        "false SPEND, a model call that can only come back saying nothing is "
        "wrong. The affordability of the vision layer rests on the abstention "
        "set staying small, so it gets a budget of its own. Measured at 0.",
    )
    a = ap.parse_args()
    corpus = a.corpus.resolve()
    bench = pathlib.Path(__file__).parent

    manifest = json.loads((corpus / "manifest.json").read_text())
    control_name = pathlib.Path(manifest["control"]).stem
    findings = load_findings(corpus)
    snaps = {
        f.stem: json.loads(f.read_text()) for f in (corpus / "snapshots").glob("*.json")
    }
    if control_name not in snaps:
        sys.exit(f"no snapshot for the control page {control_name!r}")

    failures: list[str] = []

    # --- 1. the control: budget zero, no exceptions --------------------------
    ctrl = findings.get(control_name, [])
    ctrl_asserted = [f for f in ctrl if not is_abstention(f)]
    ctrl_abstained = [f for f in ctrl if is_abstention(f)]
    print("FALSE-POSITIVE BUDGET")
    print(
        f"  control {control_name}.html: {len(ctrl_asserted)} asserted "
        f"(budget 0), {len(ctrl_abstained)} abstention(s) "
        f"(budget {a.control_abstain_budget})"
    )
    for f in ctrl_asserted:
        print(f"      FP [{f['rule']}] {f['target']}: {f['detail'][:80]}")
    for f in ctrl_abstained:
        print(f"      SPEND [{f['rule']}] {f['target']}: {f['detail'][:80]}")
    if ctrl_asserted:
        by_rule = sorted({f["rule"] for f in ctrl_asserted})
        failures.append(
            f"{len(ctrl_asserted)} asserted finding(s) on the clean control from "
            f"rule(s) {', '.join(by_rule)}"
        )
    if len(ctrl_abstained) > a.control_abstain_budget:
        by_rule = sorted({f["rule"] for f in ctrl_abstained})
        failures.append(
            f"{len(ctrl_abstained)} abstention(s) on the clean control from rule(s) "
            f"{', '.join(by_rule)}, over the budget of "
            f"{a.control_abstain_budget} -- every one is a model call that can only "
            f"come back saying nothing is wrong"
        )

    baseline = {claim_key(f) for f in ctrl}

    # --- 2. per defect: hit, collateral, false positive ----------------------
    by_id = {d["id"]: d for d in manifest["defects"]}
    rows, tot_novel, tot_fp = [], 0, 0
    per_rule: dict[str, dict[str, int]] = {}

    for did, d in by_id.items():
        page = findings.get(did, [])
        novel = [f for f in page if claim_key(f) not in baseline]
        asserted = [f for f in novel if not is_abstention(f)]
        absts = [f for f in novel if is_abstention(f)]
        touched = (
            touched_paths(snaps[control_name], snaps[did]) if did in snaps else set()
        )
        # What counts as getting this defect right depends on what the corpus
        # says a correct detector should DO with it. Where the manifest expects
        # an abstention, an ASSERTION on the target is not a hit -- it is a
        # threshold the detector invented, which is the failure mode this whole
        # instrument exists to catch.
        want_abstain = d.get("expect", "assert") == "abstain"
        on_target = [f for f in asserted if matches(d["target"], f["target"])]
        abst_on_target = [f for f in absts if matches(d["target"], f["target"])]
        hits = abst_on_target if want_abstain else on_target
        rest = [f for f in asserted if f not in hits]
        if want_abstain and on_target:
            failures.append(
                f"{did}: expected an abstention and got {len(on_target)} asserted "
                f"finding(s) on the target -- the detector invented a threshold"
            )
        collateral = [f for f in rest if f["target"] in touched]
        fps = [f for f in rest if f["target"] not in touched]
        tot_novel += len(asserted)
        tot_fp += len(fps)
        for f in asserted:
            r = per_rule.setdefault(
                f["rule"], {"control": 0, "hit": 0, "collateral": 0, "fp": 0}
            )
            r["hit" if f in hits else ("collateral" if f in collateral else "fp")] += 1
        for f in absts:
            r = per_rule.setdefault(
                f["rule"], {"control": 0, "hit": 0, "collateral": 0, "fp": 0}
            )
            if f in hits:
                r["hit"] += 1
        rows.append(
            {
                "id": did,
                "by": d["detectable_by"],
                "expect": d.get("expect", "assert"),
                "hit": bool(hits),
                "n_hit": len(hits),
                "collateral": len(collateral),
                "fp": len(fps),
                "abstained": len(absts),
                "fp_detail": [(f["rule"], f["target"]) for f in fps],
            }
        )
    for f in ctrl_asserted:
        per_rule.setdefault(
            f["rule"], {"control": 0, "hit": 0, "collateral": 0, "fp": 0}
        )["control"] += 1

    fp_rate = tot_fp / tot_novel if tot_novel else 0.0
    print(
        f"  defect pages: {tot_fp} false positive(s) of {tot_novel} asserted "
        f"finding(s) = {fp_rate:.1%} (budget {a.fp_budget:.0%})"
    )
    if fp_rate > a.fp_budget:
        failures.append(
            f"false-positive rate {fp_rate:.1%} over the {a.fp_budget:.0%} budget"
        )

    # --- 3. every declared rule graded against the control -------------------
    print("\nPER-RULE, AGAINST THE CONTROL")
    print(f"  {'rule':38} {'control':>7} {'hit':>4} {'collat':>7} {'fp':>4}")
    declared = declared_rules(bench)
    unexercised = sorted(declared - set(per_rule))
    for rule in sorted(set(per_rule) | declared):
        r = per_rule.get(rule)
        if r is None:
            print(f"  {rule:38} {'--':>7} {'--':>4} {'--':>7} {'--':>4}   UNEXERCISED")
            continue
        flag = "  <-- FP on control" if r["control"] else ""
        print(
            f"  {rule:38} {r['control']:>7} {r['hit']:>4} "
            f"{r['collateral']:>7} {r['fp']:>4}{flag}"
        )
    if unexercised:
        failures.append(
            "rule(s) never exercised by the corpus, so never graded against the "
            f"control: {', '.join(unexercised)}"
        )

    # --- 4. catch rate, split the way the corpus splits ----------------------
    print("\nCATCH RATE")
    for kind in ("dom", "pixels"):
        sub = [r for r in rows if r["by"] == kind]
        got = sum(1 for r in sub if r["hit"])
        print(f"  {kind + '-determined':18} {got}/{len(sub)}")
        for r in sub:
            if not r["hit"]:
                mark = "MISS"
            else:
                mark = "ABST" if r["expect"] == "abstain" else "HIT "
            extra = []
            if r["collateral"]:
                extra.append(f"{r['collateral']} collateral")
            if r["fp"]:
                extra.append(f"{r['fp']} FALSE: {r['fp_detail']}")
            if r["abstained"]:
                extra.append(f"{r['abstained']} abstention(s) -> vision queue")
            print(f"      {mark} {r['id']:22} {'; '.join(extra)}")

    # --- 5. the routing: is what nothing asserted still reachable? -----------
    route_f = corpus / "route.json"
    if route_f.exists():
        route = json.loads(route_f.read_text())
        print(f"\nROUTING (profile {route['app']})")
        for r in rows:
            page = route["pages"].get(r["id"], {})
            lanes = set()
            for q in page.get("queue", []):
                if q["kind"] == "crop" and any(
                    matches(by_id[r["id"]]["target"], t) for t in q["targets"]
                ):
                    lanes.add("crop")
                elif q["kind"] == "gestalt":
                    lanes.add("gestalt")
            settled = r["hit"] and r["expect"] == "assert"
            if settled:
                state = "asserted"
            elif lanes:
                state = "routed:" + "+".join(sorted(lanes))
            else:
                state = "UNREACHABLE"
            print(f"  {r['id']:22} {r['by']:7} {state}")
            # An abstention needs a lane even when it was raised perfectly. The
            # whole claim of the abstention design is that INDETERMINATE goes
            # somewhere; an abstention with no lane is the same defect shipped,
            # with a paper trail attached.
            if not settled and not lanes:
                why = (
                    "was correctly abstained on but no queue lane carries it"
                    if r["hit"]
                    else "is neither asserted nor reachable by any queue lane"
                )
                failures.append(f"{r['id']} {why}")
    else:
        print("\nROUTING  (no route.json -- run route.py to grade the queue)")

    print()
    if failures:
        print("FAIL")
        for f in failures:
            print(f"  - {f}")
        sys.exit(1)
    print("PASS -- control quiet, budget held, every declared rule graded.")


if __name__ == "__main__":
    main()
