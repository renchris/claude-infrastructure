#!/usr/bin/env python3
"""The false-positive budget: run every rule against the clean control, and fail.

An AI reviewer loses its credibility at roughly 20% false positives regardless of
how much it catches, and once lost the catch rate stops mattering because nobody
reads the report. Two zero-FP runs are the baseline this pipeline has to defend,
and "we re-ran it against the control" is a habit, which is another way of saying
it will be skipped on the day it would have caught something.

So it is a gate. It asserts four things and exits non-zero on any of them:

  1. THE CONTROL IS SILENT. Zero findings on clean.html, from every rule, in
     every layer. A rule that fires on the control is overfitted or noisy and its
     findings elsewhere are worth nothing -- so this is not a rate, it is a
     floor, and no budget is spent to satisfy it.

  2. EVERY FINDING IS ATTRIBUTABLE. On a defect page, a finding must land inside
     the subtree the injected CSS actually touched. Attribution is computed from
     the defect's own `css` selectors, not from its `target` -- the DOM's
     `contrast-indeterminate` on the hero TITLE is a true statement caused by a
     gradient injected on the hero, and scoring it as a false positive because
     the manifest names the CAPTION would punish the rule for being right.

  3. THE BUDGET HOLDS. Off-target findings as a share of all findings, against a
     stated ceiling.

  4. WEIGHTINGS CANNOT SUPPRESS. Every app profile is routed and the resulting
     queues must be identical in content and differ only in weight. A profile
     that could drop a finding would be a way to make an app look clean by
     editing a JSON file. This is the assertion that keeps `weights.json` a
     priority scheme rather than a filter.

Usage: python3 fp_budget.py <corpus-dir> [--budget 0.20]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

import route

CLASS_RE = re.compile(r"\.([A-Za-z0-9_-]+)")
NTH_RE = re.compile(r":nth-child\((\d+)\)")


def selector_parts(sel: str) -> list[tuple[str, int | None]]:
    """-> [(class, nth-or-None)] for one descendant selector, in document order."""
    parts = []
    for compound in sel.split():
        classes = CLASS_RE.findall(compound)
        if not classes:
            continue
        nth = NTH_RE.search(compound)
        parts.append((classes[0], int(nth.group(1)) if nth else None))
    return parts


def path_segments(path: str) -> list[tuple[set[str], int | None]]:
    segs = []
    for seg in path.split(" > "):
        head, _, nth = seg.partition(":nth-of-type(")
        classes = set(head.split(".")[1:])
        segs.append((classes, int(nth.rstrip(")")) if nth else None))
    return segs


def matches(path: str, sel: str) -> bool:
    """True when the selector matches this element OR one of its ancestors.

    A subsequence walk gives ancestor-or-self for free: if the selector's parts
    appear in order among the path's segments, the element is inside the subtree
    the selector names.

    `:nth-child(N)` is compared against `:nth-of-type(N)`, which is only sound
    where the matched element's siblings are homogeneous. That holds throughout
    this corpus (checked: every indexed selector addresses a div among divs); a
    corpus with mixed siblings would need the real index carried in the snapshot.
    """
    parts = selector_parts(sel)
    if not parts:
        return False
    segs = path_segments(path)
    i = 0
    for cls, nth in parts:
        while i < len(segs):
            classes, seg_nth = segs[i]
            i += 1
            if cls in classes and (nth is None or nth == seg_nth):
                break
        else:
            return False
    return True


def attributable_selectors(defect: dict) -> list[str]:
    """Every selector the injected CSS actually addresses, plus the named target.

    Rule preludes only: the declaration blocks carry colours like `#1D4ED3` that
    would otherwise be read as selectors.
    """
    sels = [defect["target"]]
    for prelude in re.findall(r"(^|\})([^{}]*)\{", defect["css"]):
        for sel in prelude[1].split(","):
            sel = sel.strip()
            if sel:
                sels.append(sel)
    return sorted(set(sels))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path, nargs="?", default="corpus/out")
    ap.add_argument("--budget", type=float, default=0.20)
    ap.add_argument("--weights", type=pathlib.Path, default=None)
    a = ap.parse_args()
    corpus = pathlib.Path(a.corpus).resolve()
    wpath = a.weights or pathlib.Path(__file__).parent / "weights.json"

    manifest = json.loads((corpus / "manifest.json").read_text())
    control = manifest["control"].removesuffix(".html")
    by_id = {d["id"]: d for d in manifest["defects"]}

    layers = {}
    for name, fn in (("dom", "findings_dom.json"), ("xcheck", "findings_xcheck.json")):
        p = corpus / fn
        if p.exists():
            layers[name] = json.loads(p.read_text())
        else:
            print(f"  ?? {fn} absent -- the {name} layer was not run")

    failures: list[str] = []

    # --- 1. the control is silent -----------------------------------------
    print("1. CONTROL")
    for layer, res in layers.items():
        ctrl = res.get(control, [])
        rules = sorted({f["rule"] for f in ctrl})
        print(
            f"   {layer:7} {len(ctrl)} finding(s) on {control}.html {rules if rules else ''}"
        )
        for f in ctrl:
            failures.append(
                f"control: [{layer}/{f['rule']}] fired on {control}.html at "
                f"{f['target']} -- {f['detail'][:80]}"
            )

    # --- 2 and 3. attribution and the budget ------------------------------
    print("\n2. ATTRIBUTION  (per rule, over the defect pages)")
    per_rule: dict[str, list[int]] = {}
    off: list[str] = []
    for layer, res in layers.items():
        for page, fs in res.items():
            if page == control or page not in by_id:
                continue
            sels = attributable_selectors(by_id[page])
            for f in fs:
                on = any(matches(f["target"], s) for s in sels)
                row = per_rule.setdefault(f"{layer}/{f['rule']}", [0, 0])
                row[0 if on else 1] += 1
                if not on:
                    off.append(
                        f"off-target: [{layer}/{f['rule']}] on {page} at "
                        f"{f['target']} -- injection touches {sels}"
                    )
    total = sum(a_ + b for a_, b in per_rule.values())
    total_off = sum(b for _, b in per_rule.values())
    for rule, (on, bad) in sorted(per_rule.items()):
        flag = "  <-- off-target" if bad else ""
        print(f"   {rule:32} on-target {on:2d}   off-target {bad:2d}{flag}")
    rate = (total_off / total) if total else 0.0
    print(
        f"\n3. BUDGET  {total_off}/{total} off-target = {rate:.1%}  ceiling {a.budget:.0%}"
    )
    if rate > a.budget:
        failures.append(
            f"budget: {rate:.1%} off-target exceeds the {a.budget:.0%} ceiling"
        )
    failures.extend(off)

    # --- 4. a weighting cannot suppress -----------------------------------
    print("\n4. PROFILE INVARIANCE")
    cfg = json.loads(wpath.read_text())
    shapes, weights_seen = {}, {}
    for app in sorted(cfg["apps"]):
        prof = route.load_weights(wpath, app)
        plan = route.build(corpus, prof, True, False)
        shapes[app] = sorted(
            (q["page"], q["kind"], q["class"], tuple(q.get("targets", [])))
            for q in plan["queue"]
        )
        weights_seen[app] = plan["family_weight"]
        # Read the DECLARED weight, never the routed one. The router clamps a
        # sub-floor weight up to 1.0 so a bad profile cannot do harm at runtime --
        # which means checking the clamped value here would assert a property the
        # clamp has already made true, and this arm would be permanently green.
        # Measured: it was. The clamp is the repair; this is the report.
        for fam in plan["weight_floors_applied_to"]:
            failures.append(
                f"floor: {app} declares family {fam} at "
                f"{cfg['apps'][app]['families'][fam]} -- accessibility and "
                f"correctness may be weighted up, never down. The router clamped "
                f"it to 1.0; fix the profile."
            )
    ref_app = sorted(shapes)[0]
    for app, shape in shapes.items():
        same = shape == shapes[ref_app]
        print(
            f"   {app:22} {len(shape):2d} item(s)  content {'identical' if same else 'DIFFERS'}"
            f"  weights {weights_seen[app]}"
        )
        if not same:
            failures.append(
                f"suppression: {app}'s queue differs in CONTENT from {ref_app}'s -- "
                f"a weighting changed what is detected, not just its order"
            )

    print()
    if failures:
        print(f"FAIL  {len(failures)} breach(es):")
        for f in failures[:20]:
            print(f"   - {f}")
        return 1
    print("PASS  control silent, every finding attributable, no profile suppresses.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
