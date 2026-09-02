#!/usr/bin/env python3
"""The false-positive budget. Run every rule against the clean control, and fail.

About 20% false positives is where an AI reviewer stops being believed, whatever
its catch rate -- an agent that acts on invented defects is worse than no
detector, because it writes code against them. Two zero-FP runs are the baseline
this corpus defends, and defending it is a gate, not a habit: every rule added or
changed is re-run against the control BEFORE it ships.

This file is that gate. It is deliberately the only place in the bench that exits
non-zero, and it exits on facts a rule author cannot argue with:

  GATE 1  the control is silent.      Zero findings on clean.html, from every
                                      detector, at every capture scale. A rule
                                      quiet at 1x and noisy at 1.5x has not been
                                      measured; both are run.
  GATE 2  every finding is caused.    On a defect page, a novel finding must fall
                                      inside the injected defect's blast radius --
                                      the subtree of every selector its CSS
                                      touched. A finding outside it is a report
                                      about an element nobody modified.
  GATE 3  the budget holds.           Total false positives over total findings,
                                      against the stated 20% ceiling.

GATE 2's blast radius is the subtree of the injection's SELECTORS, not of its
`target` field. The gradient defect restyles `.hero` and recolours
`.hero-caption`; an abstention on `.hero-title` is then a correct report about a
title that really is sitting on a gradient, and scoring it as a false positive
would punish the rule for being right. Scoring a correct abstention as a miss is
the exact error the README records the corpus making once already.

Usage: python3 fp_budget.py [corpus-dir]   # exit 0 = the budget holds
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

import detect_dom
import detect_xcheck

FP_CEILING = 0.20
CLASS_RE = re.compile(r"\.([A-Za-z_][\w-]*)")
NTH_RE = re.compile(r"\.([A-Za-z_][\w-]*):nth-child\((\d+)\)")
SEG_NTH_RE = re.compile(r":nth-of-type\((\d+)\)")


def blast_radius(defect: dict) -> list[tuple[str, int | None]]:
    """Every (class, index) the injected CSS could legitimately change something in.

    Selector text, not the `target` field: a rule set that restyles a container
    changes the rendering of everything inside it, and a detector noticing that is
    correct rather than noisy.
    """
    selectors = defect["css"].split("{")[:-1]
    text = " ".join(s.split("}")[-1] for s in selectors)
    nth = dict(NTH_RE.findall(text))
    return [(c, int(nth[c]) if c in nth else None) for c in set(CLASS_RE.findall(text))]


def in_radius(path: str, radius: list[tuple[str, int | None]]) -> bool:
    for seg in path.split(" > "):
        idx = SEG_NTH_RE.search(seg)
        classes = set(seg.split(":")[0].split(".")[1:])
        for cls, want in radius:
            if cls in classes and (want is None or (idx and int(idx.group(1)) == want)):
                return True
    return False


def grade(corpus: pathlib.Path, suffix: str, tokens: dict, defects: dict) -> dict:
    dom = {
        f.stem: detect_dom.find(json.loads(f.read_text()), tokens)
        for f in sorted((corpus / "snapshots").glob("*.json"))
    }
    xchk = detect_xcheck.run(corpus, suffix)
    control = dom.get("clean", []) + xchk.get("clean", [])
    base = {(f["rule"], f["target"], f["detail"]) for f in control}

    off_target, total_novel, by_rule = [], 0, {}
    for page in sorted(dom):
        if page == "clean" or page not in defects:
            continue
        radius = blast_radius(defects[page])
        for f in dom[page] + xchk.get(page, []):
            if (f["rule"], f["target"], f["detail"]) in base:
                continue  # the control already says this; not this page's news
            total_novel += 1
            by_rule[f["rule"]] = by_rule.get(f["rule"], 0) + 1
            if not in_radius(f["target"], radius):
                off_target.append({"page": page, **f})

    fps = len(control) + len(off_target)
    total = len(control) + total_novel
    return {
        "shot": suffix or "@1x",
        "control_findings": control,
        "off_target": off_target,
        "novel_findings": total_novel,
        "by_rule": dict(sorted(by_rule.items())),
        "false_positives": fps,
        "total_findings": total,
        "fp_rate": round(fps / total, 4) if total else 0.0,
    }


def main(corpus: pathlib.Path) -> int:
    manifest = json.loads((corpus / "manifest.json").read_text())
    defects = {d["id"]: d for d in manifest["defects"]}
    shots = corpus / "shots"
    suffixes = [""] + sorted(
        {p.stem.split("@")[1] for p in shots.glob("*@*.png")}, key=str
    )
    suffixes = [""] + [f"@{s}" for s in suffixes[1:]]

    runs = [grade(corpus, s, manifest["tokens"], defects) for s in suffixes]
    (corpus / "fp_budget.json").write_text(
        json.dumps({"ceiling": FP_CEILING, "runs": runs}, indent=1)
    )

    failed = False
    for r in runs:
        print(f"SCALE {r['shot']}")
        n_ctrl, n_off = len(r["control_findings"]), len(r["off_target"])
        verdict = "PASS" if n_ctrl == 0 else "FAIL"
        print(
            f"  gate 1  control silent      {verdict}  ({n_ctrl} finding(s) on clean.html)"
        )
        for c in r["control_findings"]:
            print(f"            [{c['rule']}] {c['target']}")
        verdict = "PASS" if n_off == 0 else "FAIL"
        print(
            f"  gate 2  every finding caused {verdict}  ({n_off} outside a blast radius)"
        )
        for c in r["off_target"]:
            print(f"            {c['page']}: [{c['rule']}] {c['target']}")
        ok = r["fp_rate"] <= FP_CEILING
        print(
            f"  gate 3  budget               {'PASS' if ok else 'FAIL'}  "
            f"{r['false_positives']}/{r['total_findings']} = {r['fp_rate'] * 100:.1f}% "
            f"against a {FP_CEILING * 100:.0f}% ceiling"
        )
        print(f"  fired: {', '.join(f'{k}x{v}' for k, v in r['by_rule'].items())}")
        failed |= n_ctrl > 0 or n_off > 0 or not ok

    print(
        "\nFP BUDGET " + ("BREACHED -- do not ship these rules" if failed else "HOLDS")
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(
        main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "corpus/out").resolve())
    )
