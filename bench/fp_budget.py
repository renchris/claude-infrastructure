#!/usr/bin/env python3
"""The false-positive budget: every rule re-run against the clean control.

~20% false positives is where an AI reviewer loses credibility regardless of its
catch rate, and a detector that invents defects is worse than no detector because
an agent ACTS on them. The two zero-FP runs this corpus produced are the baseline
to defend, so this is the gate a rule has to pass before it ships -- not a report
someone reads afterwards. It exits non-zero on a breach.

Three gates, in the order they matter.

  CONTROL      findings on clean.html. Budget: exactly ZERO, always. A rule that
               fires on the control is overfitted or noisy and its findings
               everywhere else are worth nothing. This is not the 20% gate; it is
               a floor beneath it.
  OFF-TARGET   novel findings on elements the injected CSS did not touch. Budget:
               the profile's `fp_budget`, 20% by default. "Did not touch" is
               computed by diffing each variant's snapshot against the control's
               -- exact, and it needs no selector to be parsed or trusted.
  RECALL       whether a finding actually landed on the declared target, split by
               `detectable_by`. Not a budget, but it belongs in the same run: a
               quiet detector scores a perfect FP rate by finding nothing, and the
               two numbers are only meaningful together.

This is a gate on the DETECTOR, not on a page. The June 2026 campaign settled that
gates adjudicate correctness and coverage only and that taste stays human; the
question here is whether a rule is sound, which is exactly a correctness question.

Usage: python3 fp_budget.py <corpus-dir> [--profile bench] [--no-x2]
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

# The corpus scores a true positive as "names the right defect CLASS and points at
# the right target", so a hit needs both. Without the class half, hierarchy-
# inversion scores as found: two unrelated rules fire inside `.actions` because the
# injected CSS also drifts a colour token, and the recall column reads 4/4 for a
# stack that cannot reach visual hierarchy at all. A class with no rule against it
# is not a miss -- it is the residue the abstention router exists to queue, and it
# is reported as such below.
RULE_CLASS = {
    "spacing-rhythm": "spacing-inconsistency",
    "grid-violation": "grid-violation",
    "type-scale": "typographic-scale",
    "token-drift": "token-drift",
    "contrast": "contrast",
    "contrast-indeterminate": "contrast",
    "xcheck-contrast-varies": "contrast",
    "xcheck-backdrop-indeterminate": "contrast",
    "overflow": "overflow",
    "touch-target": "accessibility",
    "misalignment": "misalignment",
    "xcheck-optical-centre": "optical-alignment",
}
REACHABLE = set(RULE_CLASS.values())

SEG = re.compile(r"^([a-z0-9]+)((?:\.[A-Za-z0-9_-]+)*)(?::nth-of-type\((\d+)\))?$")
COMPOUND = re.compile(
    r"^([a-z0-9]+)?((?:\.[A-Za-z0-9_-]+)*)(?::nth-(?:child|of-type)\((\d+)\))?$"
)


def _classes(s: str) -> set[str]:
    return set(re.findall(r"\.([A-Za-z0-9_-]+)", s))


def seg_matches(seg: str, compound: str) -> bool:
    ms, mc = SEG.match(seg), COMPOUND.match(compound)
    if not ms or not mc:
        return False
    if mc.group(1) and mc.group(1) != ms.group(1):
        return False
    if not _classes(mc.group(2) or "") <= _classes(ms.group(2) or ""):
        return False
    if mc.group(3) and int(mc.group(3)) != int(ms.group(3) or 1):
        return False
    return True


def resolve(selector: str, paths: list[str]) -> set[str]:
    """Every element path a manifest target selector names.

    Descendant combinators only -- that is all the corpus uses, and a partial
    parser that silently mismatches a selector would corrupt the recall column
    while looking like it worked.
    """
    compounds = selector.split()
    hits = set()
    for path in paths:
        segs = path.split(" > ")
        if not seg_matches(segs[-1], compounds[-1]):
            continue
        i = 0
        for seg in segs[:-1]:
            if i < len(compounds) - 1 and seg_matches(seg, compounds[i]):
                i += 1
        if i == len(compounds) - 1:
            hits.add(path)
    return hits


def in_subtree(a: str, b: str) -> bool:
    """True when a and b are the same element or one contains the other."""
    return a == b or a.startswith(b + " > ") or b.startswith(a + " > ")


def touched(clean: dict, variant: dict) -> set[str]:
    """Elements this variant's injection affects: changed, plus their subtree.

    Diffing the two snapshots beats parsing the injected selector: it catches
    every element the rule cascaded onto and every element that merely MOVED as a
    result, which is the same set a reviewer would call "affected by this change".

    It has to expand both ways, and the downward half is not a courtesy. Painting
    a gradient on `.hero` changes no computed style on `.hero-title` inside it and
    moves nothing -- and makes that title's contrast unverifiable. The abstention
    raised on it is a correct finding about a real consequence of the injection;
    scoring it as a false positive would have penalised the rule for being right,
    and would have put this corpus's off-target rate at 17.4% of a 20% budget on
    the strength of four true positives.
    """
    base = {e["path"]: e for e in clean["elements"]}
    changed = set()
    for e in variant["elements"]:
        b = base.get(e["path"])
        if b is None or b["styles"] != e["styles"] or b["rect"] != e["rect"]:
            changed.add(e["path"])
    out = set(changed)
    for p in changed:
        segs = p.split(" > ")
        for i in range(1, len(segs)):
            out.add(" > ".join(segs[:i]))
    for e in variant["elements"]:
        if any(e["path"].startswith(p + " > ") for p in changed):
            out.add(e["path"])
    return out


def run(corpus: pathlib.Path, prof: profiles.Profile) -> int:
    manifest = json.loads((corpus / "manifest.json").read_text())
    tokens = manifest["tokens"]
    snaps, results = {}, {}
    for f in sorted((corpus / "snapshots").glob("*.json")):
        png = corpus / "shots" / f"{f.stem}.png"
        if not png.exists():
            continue
        snap = json.loads(f.read_text())
        snaps[f.stem] = snap
        results[f.stem] = prof.rank(
            detect_dom.find(snap, tokens) + detect_xcheck.check(snap, png)
        )
    if "clean" not in results:
        sys.exit("no control page captured; run capture.py first")

    failures = []

    # --- gate 1: the control -------------------------------------------------
    ctrl = results["clean"]
    print(f"CONTROL  clean.html -> {len(ctrl)} finding(s), budget 0")
    for c in ctrl:
        print(f"    FP [{c['rule']}] {c['target']}: {c['detail'][:88]}")
    if ctrl:
        failures.append(f"{len(ctrl)} finding(s) on the clean control")
    print()

    baseline = {(c["rule"], c["target"], c["detail"]) for c in ctrl}

    # --- gates 2 and 3: per variant -----------------------------------------
    print(f"{'variant':22} {'by':7} {'novel':>5} {'on-tgt':>6} {'off':>4}  target hit")
    novel_total = off_total = 0
    missed, residue = [], []
    for d in manifest["defects"]:
        name = d["id"]
        if name not in results:
            continue
        novel = [
            f
            for f in results[name]
            if (f["rule"], f["target"], f["detail"]) not in baseline
        ]
        affected = touched(snaps["clean"], snaps[name])
        off = [f for f in novel if f["target"] not in affected]
        targets = resolve(d["target"], [e["path"] for e in snaps[name]["elements"]])
        reachable = d["klass"] in REACHABLE
        hit = any(
            RULE_CLASS.get(f["rule"]) == d["klass"] and in_subtree(f["target"], t)
            for f in novel
            for t in targets
        )
        novel_total += len(novel)
        off_total += len(off)
        if not reachable:
            residue.append((name, d["klass"]))
        elif not hit:
            missed.append((name, d["detectable_by"]))
        print(
            f"{name:22} {d['detectable_by']:7} {len(novel):5d} "
            f"{len(novel) - len(off):6d} {len(off):4d}  "
            f"{'yes' if hit else ('no rule reaches this class' if not reachable else 'NO')}"
        )
        for f in off:
            print(f"    off-target [{f['rule']}] {f['target']}")

    rate = off_total / novel_total if novel_total else 0.0
    print()
    print(
        f"OFF-TARGET  {off_total}/{novel_total} = {rate:.1%}, "
        f"budget {prof.fp_budget:.0%}"
    )
    if rate > prof.fp_budget:
        failures.append(f"off-target FP rate {rate:.1%} over budget")

    # --- recall, reported beside the budget ---------------------------------
    res_ids = {n for n, _ in residue}
    for kind in ("dom", "pixels"):
        total = sum(
            1
            for d in manifest["defects"]
            if d["detectable_by"] == kind and d["id"] not in res_ids
        )
        miss = sum(1 for _, k in missed if k == kind)
        print(f"RECALL      {kind:6} {total - miss}/{total}")
    for name, kind in missed:
        print(f"    missed [{kind}] {name}")
    if residue:
        print(
            f"RESIDUE     {len(residue)} defect(s) in classes no rule reaches -- "
            f"the abstention router's judgement queue, not a miss"
        )
        for name, klass in residue:
            print(f"    residue [{klass}] {name}")

    print()
    if failures:
        print("BUDGET BREACHED: " + "; ".join(failures))
        return 1
    print(f"budget held under profile {prof.id}")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", default="corpus/out", type=pathlib.Path)
    ap.add_argument("--profile", default="bench")
    ap.add_argument("--no-x2", action="store_true", help="disable the X2 arm")
    a = ap.parse_args()
    raise SystemExit(run(a.corpus.resolve(), profiles.get(a.profile)))
