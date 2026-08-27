#!/usr/bin/env python3
"""The false-positive budget: run every rule against the clean control, and count
what the reviewer would say that is not about a real defect.

Why this is a separate program and not a line of output in the detectors. A
detector's own summary answers "did I find the defect", and every rule in this
bench can be made to answer that yes by loosening a tolerance. The question a
design reviewer is actually judged on is the other one -- of everything it said,
how much was noise -- and about 20% is where an AI reviewer stops being read at
all, whatever its catch rate. Our two zero-FP runs are the baseline to defend, so
the defence has to be executable and it has to run before a rule ships.

TWO CLASSES OF FALSE POSITIVE, both from the corpus manifest's own scoring
contract, because a control-only budget misses the larger half:

  CONTROL     any finding at all on clean.html. This is the hard gate: a rule
              that fires here is overfitted or noisy and its findings elsewhere
              are worth nothing. Non-zero exits 1.

  UNATTRIBUTED  a novel finding on a defect page that does not point at that
              page's injected defect. The page carries exactly one defect at a
              known location, so anything else the detector says about it is
              noise that a reader has to triage. This is the class that decides
              whether the report is worth reading, and it is invisible to a
              control run.

THE DENOMINATOR IS STATED, not assumed. It is every finding a reviewer would SHOW
a human: novel findings across the twelve defect pages, plus anything on the
control. Getting this wrong is not a rounding error -- the pipeline spec computed
its own FP bound on the wrong denominator and moved it from 23.1% to 37.5%.

Attribution is by SELECTOR, not by string equality. The manifest names a target
as CSS (`.kpi-card:nth-child(3)`, `.glyph-btn .glyph`) and a finding names one as
a rendered path (`div.kpi-row:nth-of-type(2) > div.kpi-card:nth-of-type(3)`). A
finding is attributed when the target's simple selectors appear in order along
the finding's path, which credits a finding on a DESCENDANT of the target -- the
contrast failure on the button inside the `.actions` block that the
hierarchy-inversion defect rewrites is about that defect -- while a finding on an
ancestor, or on a differently-indexed sibling, stays unattributed.

Usage: python3 fp_budget.py <corpus-dir> [--json <path>]
Exit:  0 = the control is quiet · 1 = at least one rule fires on the control
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
import rules

CLASS_RE = re.compile(r"\.([A-Za-z0-9_-]+)")
NTH_RE = re.compile(r":nth-(?:child|of-type)\((\d+)\)")


def selector_steps(sel: str) -> list[tuple[set[str], int | None]]:
    """`.a .b:nth-child(3)` -> [({'a'}, None), ({'b'}, 3)]. Descendant combinator
    only; the corpus authors targets that way and a child combinator would be a
    stricter claim than the manifest actually makes."""
    steps = []
    for part in sel.replace(" > ", " ").split():
        n = NTH_RE.search(part)
        steps.append((set(CLASS_RE.findall(part)), int(n.group(1)) if n else None))
    return [s for s in steps if s[0] or s[1]]


def attributed(path: str, sel: str) -> bool:
    """Does this finding's path name the manifest's target, or something inside it?"""
    steps = selector_steps(sel)
    if not steps:
        return False
    segs = path.split(" > ")
    i = 0
    for classes, nth in steps:
        while i < len(segs):
            seg = segs[i]
            i += 1
            have = set(CLASS_RE.findall(seg))
            if not classes <= have:
                continue
            if nth is not None:
                m = NTH_RE.search(seg)
                # No index in the path means the element is an only child of its
                # type, which satisfies :nth-child(1) and nothing else.
                if (int(m.group(1)) if m else 1) != nth:
                    continue
            break
        else:
            return False
    return True


def run(corpus: pathlib.Path) -> dict:
    manifest = json.loads((corpus / "manifest.json").read_text())
    tokens = manifest["tokens"]
    snaps, shots = corpus / "snapshots", corpus / "shots"
    defects = {d["id"]: d for d in manifest["defects"]}

    findings: dict[str, list[dict]] = {}
    for f in sorted(snaps.glob("*.json")):
        snap = json.loads(f.read_text())
        got = detect_dom.find(snap, tokens)
        png = shots / f"{f.stem}.png"
        if png.exists():
            got = got + detect_xcheck.check(snap, png)
        findings[f.stem] = got

    control = findings.get("clean", [])
    # Subtract the control by the FULL claim, never by (rule, target). Keying on
    # location alone let a real colour-token drift on the primary button vanish
    # because an unrelated token-drift finding already sat on that element in the
    # baseline -- the assertion-span-must-equal-its-subject failure, reproduced
    # live in this corpus and worth 1 of 9.
    base = {(c["rule"], c["target"], c["detail"]) for c in control}

    per_rule = collections.defaultdict(
        lambda: {"control": 0, "ok": 0, "unattributed": 0}
    )
    for c in control:
        per_rule[c["rule"]]["control"] += 1

    pages, unattributed, shown = {}, [], len(control)
    for name, fs in sorted(findings.items()):
        if name == "clean":
            continue
        novel = [f for f in fs if (f["rule"], f["target"], f["detail"]) not in base]
        sel = defects[name]["target"]
        sels = [sel] + defects[name].get("also_affects", [])
        hits, miss = [], []
        for f in novel:
            ok = any(attributed(f["target"], s) for s in sels)
            (hits if ok else miss).append(f)
            per_rule[f["rule"]]["ok" if ok else "unattributed"] += 1
        shown += len(novel)
        unattributed += [dict(f, page=name) for f in miss]
        # The manifest's own three-way scoring. A finding at the right element
        # whose CLASS is not the defect's class is a near miss, not a catch:
        # `hierarchy-inversion` rewrites two buttons, which trips `contrast` and
        # `token-drift` honestly, and scoring those as catching the hierarchy
        # defect would credit the deterministic layer with the one capability the
        # whole architecture says it cannot have.
        klass = defects[name]["klass"]
        caught = sorted(
            {f["rule"] for f in hits if rules.rule(f["rule"]).klass == klass}
        )
        near = sorted({f["rule"] for f in hits if rules.rule(f["rule"]).klass != klass})
        pages[name] = {
            "klass": klass,
            "detectable_by": defects[name]["detectable_by"],
            "target": sel,
            "caught_by": caught,
            "near_miss_by": near,
            "judgement_only": klass in rules.JUDGEMENT_ONLY,
            "unattributed": len(miss),
        }
    n_unattr = len(unattributed)
    seen_rules = {f["rule"] for fs in findings.values() for f in fs}
    return {
        "corpus_version": manifest["corpus_version"],
        "pages": pages,
        "per_rule": {k: dict(v) for k, v in sorted(per_rule.items())},
        "control_findings": control,
        "unattributed_findings": unattributed,
        "unclassified_rules": rules.unclassified(seen_rules),
        "denominator": {
            "what": "every finding a reviewer would show a human",
            "novel_on_variants_plus_control": shown,
            "control": len(control),
            "unattributed": n_unattr,
            "rate": round(n_unattr / shown, 4) if shown else 0.0,
        },
        "caught": sum(1 for p in pages.values() if p["caught_by"]),
        "gate": "PASS" if not control else "FAIL",
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path, nargs="?", default="corpus/out")
    ap.add_argument("--json", type=pathlib.Path)
    a = ap.parse_args()
    r = run(pathlib.Path(a.corpus).resolve())
    d = r["denominator"]

    print(
        f"FALSE-POSITIVE BUDGET   corpus {r['corpus_version']} · {len(r['pages']) + 1} pages"
    )
    print(
        f"  denominator: {d['what']} -- {d['novel_on_variants_plus_control']} findings\n"
    )
    print(f"  {'rule':28} {'control':>8} {'attributed':>11} {'unattributed':>13}")
    print(f"  {'-' * 28} {'-' * 8} {'-' * 11} {'-' * 13}")
    for name, v in r["per_rule"].items():
        flag = "  <-- FIRES ON CONTROL" if v["control"] else ""
        print(
            f"  {name:28} {v['control']:>8} {v['ok']:>11} {v['unattributed']:>13}{flag}"
        )
    print(
        f"  {'TOTAL':28} {d['control']:>8} "
        f"{d['novel_on_variants_plus_control'] - d['unattributed'] - d['control']:>11} "
        f"{d['unattributed']:>13}   -> {d['rate'] * 100:.1f}% unattributed"
    )

    print(
        f"\n  CATCH RATE BY CLASS   {r['caught']}/{len(r['pages'])} "
        f"-- the defect's own class was named, not merely something at its element\n"
    )
    print(f"  {'defect':22} {'by':7} {'class':22} verdict")
    for name, p in r["pages"].items():
        if p["caught_by"]:
            verdict = "caught: " + ", ".join(p["caught_by"])
        elif p["judgement_only"]:
            verdict = "NOT CAUGHT, and no rule may -- this class is the vision layer's"
        else:
            verdict = "NOT CAUGHT"
        if p["near_miss_by"]:
            verdict += f"  (near: {', '.join(p['near_miss_by'])})"
        print(f"  {name:22} {p['detectable_by']:7} {p['klass']:22} {verdict}")

    if r["unclassified_rules"]:
        print(
            f"\n  UNCLASSIFIED, scored as `unknown` and neither dischargeable nor "
            f"routable: {', '.join(r['unclassified_rules'])}"
        )

    for f in r["control_findings"]:
        print(f"\n  CONTROL [{f['rule']}] {f['target']}\n    {f['detail'][:150]}")
    for f in r["unattributed_findings"]:
        print(
            f"\n  UNATTRIBUTED on {f['page']} [{f['rule']}] {f['target']}\n    {f['detail'][:150]}"
        )

    print(f"\nGATE: {r['gate']} -- ", end="")
    print(
        "no rule fires on the clean control."
        if r["gate"] == "PASS"
        else f"{len(r['control_findings'])} finding(s) on the clean control; "
        "every finding those rules make elsewhere is worth nothing until this is zero."
    )
    if a.json:
        pathlib.Path(a.json).write_text(json.dumps(r, indent=1))
    return 0 if r["gate"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
