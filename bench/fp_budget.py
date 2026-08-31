#!/usr/bin/env python3
"""The false-positive budget: re-run every rule against the clean control.

~20% false positives is where an AI reviewer loses credibility regardless of its
catch rate, and credibility is the resource this whole stack actually spends. The
zero-FP runs are the baseline to defend, so every rule added must be re-run
against the clean control BEFORE it ships -- which only means anything if it is a
command someone runs rather than a paragraph someone read.

Three numbers, and the third is the one nobody computes:

  CONTROL FP   findings on clean.html. The corpus's own scoring rule calls a run
               with zero of these "a precondition for the rest of the score
               meaning anything", so this is a GATE, not a metric. Any rule that
               fires here is overfitted or noisy and its findings elsewhere are
               worth nothing.
  RECALL       injected defects found, per detectable_by class. Reported per
               layer so a layer cannot borrow another's score.
  OFF-TARGET   findings on a defect page that name an element the defect did not
               touch. The manifest counts these as false positives too, and they
               are the ones a control run structurally cannot see -- a rule can
               be silent on a clean page and still spray a defect page.

🚨 A control this small cannot certify a rate, and saying so is the point. Rule
of three: zero findings over ONE control page bounds the true rate at 95%
confidence only by 3/1 -- which is no bound at all. The honest reading of a clean
run here is "this rule is not obviously broken", and the real denominator is a
corpus of pages that shipped and were never touched by a visual-bug fix, where
every finding is a false positive by construction at zero labelling cost. This
tool computes what the corpus can support and prints the width of what it cannot;
it does not launder one into the other.

Usage: python3 fp_budget.py <corpus-dir>
"""

from __future__ import annotations

import json
import pathlib
import sys

CONTROL = "clean"

# The corpus scores a true positive as "names the right defect CLASS and points at
# the right TARGET". Without this map the only checkable half is the target, and
# scoring on location alone is how a finding that is merely NEAR a defect gets
# counted as having found it -- the assertion-span-must-equal-its-subject failure
# this corpus was built to catch, reproduced by its own scorer.
#
# `visual-hierarchy` maps to nothing on purpose. No deterministic rule reaches it,
# it is the vision layer's job, and giving it a rule here would let a side effect
# of the injected CSS (the variant recolours two buttons, so token and contrast
# rules fire) launder itself into a hit for a defect nobody detected.
RULES_FOR_CLASS = {
    "spacing-inconsistency": {"spacing-rhythm"},
    "misalignment": {"misalignment"},
    "token-drift": {"token-drift"},
    "typographic-scale": {"type-scale"},
    "grid-violation": {"grid-violation"},
    "contrast": {"contrast", "xcheck-contrast-varies"},
    "overflow": {"overflow"},
    "accessibility": {"touch-target"},
    "optical-alignment": {"xcheck-optical-centre"},
    "visual-hierarchy": set(),
}


def parse_part(part: str) -> tuple[str, str | None]:
    """`.kpi-card:nth-child(3)` -> ('kpi-card', '3')"""
    nth = None
    if ":nth-child(" in part:
        head, _, rest = part.partition(":nth-child(")
        nth = rest.split(")")[0]
        part = head
    return part.lstrip("."), nth


def target_matches(defect_target: str, finding_path: str) -> bool:
    """Does a snapshot path satisfy the corpus's CSS-selector target?

    The corpus names targets as selectors (`.kpi-card:nth-child(4) .kpi-label`);
    the snapshot names them as paths (`div.kpi-row:nth-of-type(2) > ...`). Every
    part of the selector must appear, in order, as a segment of the path. Every
    sibling group in this corpus is single-tag, so nth-child and nth-of-type
    coincide -- true here, and it would need re-deriving on a mixed-tag page.
    """
    segs = finding_path.split(" > ")
    i = 0
    for part in defect_target.split():
        cls, nth = parse_part(part)
        while i < len(segs):
            seg = segs[i]
            i += 1
            if f".{cls}" in seg or seg.startswith(cls):
                if nth is None or f"nth-of-type({nth})" in seg:
                    break
        else:
            return False
    return True


def score_defect(did: str, defect: dict, layers: dict, baseline: dict) -> dict:
    """-> {verdict, by, near, abstained}. Four outcomes, and ABSTAIN is its own.

    An abstention counted as a hit is the worst available bookkeeping error: the
    whole architecture rests on `INDETERMINATE` being a routed question rather
    than a settled one, so scoring it as a detection reports the queue as empty
    at the exact moment it is full.
    """
    want = RULES_FOR_CLASS.get(defect["klass"], set())
    tp, near, abstained = [], [], []
    for layer, results in layers.items():
        for f in results.get(did, []):
            if (f["rule"], f["target"]) in baseline[layer]:
                continue
            if not target_matches(defect["target"], f["target"]):
                continue
            if f["rule"].endswith("-indeterminate"):
                abstained.append(layer)
            elif f["rule"] in want:
                tp.append(layer)
            else:
                near.append(f["rule"])
    verdict = "TP" if tp else ("NEAR" if near else ("ABSTAIN" if abstained else "MISS"))
    return {
        "verdict": verdict,
        "by": sorted(set(tp)),
        "near": sorted(set(near)),
        "abstained": sorted(set(abstained)),
    }


def load(corpus: pathlib.Path, name: str) -> dict:
    p = corpus / name
    if not p.exists():
        # Absence and empty are different states. A missing findings file means
        # the layer did not run, and scoring it as "no findings" would report a
        # broken layer as a perfect one.
        return {}
    return json.loads(p.read_text())


def rule_table(results: dict) -> dict:
    """rule -> {control, pages_fired, total}"""
    table: dict[str, dict] = {}
    for page, findings in results.items():
        for f in findings:
            r = table.setdefault(f["rule"], {"control": 0, "pages": set(), "total": 0})
            r["total"] += 1
            r["pages"].add(page)
            if page == CONTROL:
                r["control"] += 1
    return table


def main(corpus: pathlib.Path) -> None:
    manifest = json.loads((corpus / "manifest.json").read_text())
    defects = {d["id"]: d for d in manifest["defects"]}
    layers = {
        "detect_dom": load(corpus, "findings_dom.json"),
        "detect_xcheck": load(corpus, "findings_xcheck.json"),
    }
    missing = [n for n, r in layers.items() if not r]
    if missing:
        print(f"!! layer(s) did not run, so nothing below scores them: {missing}\n")

    print("=" * 78)
    print("FALSE-POSITIVE BUDGET -- every rule against the clean control")
    print("=" * 78)
    gate_ok = True
    for layer, results in layers.items():
        if not results:
            continue
        ctrl = results.get(CONTROL, [])
        table = rule_table(results)
        print(
            f"\n{layer}: {len(ctrl)} finding(s) on {CONTROL}.html "
            f"{'-- GATE FAILS' if ctrl else '(gate passes)'}"
        )
        gate_ok &= not ctrl
        print(f"  {'rule':26} {'control FP':>10} {'pages fired':>12} {'findings':>9}")
        for rule, r in sorted(table.items()):
            flag = "  <-- FP" if r["control"] else ""
            print(
                f"  {rule:26} {r['control']:>10} "
                f"{len(r['pages']):>12} {r['total']:>9}{flag}"
            )
        for c in ctrl:
            print(f"    FP [{c['rule']}] {c['target']}: {c['detail'][:80]}")

    # --- Recall, per detectable_by class, per layer ---------------------------
    print("\n" + "=" * 78)
    print("RECALL -- injected defects found, by the class the corpus assigned them")
    print("=" * 78)
    baseline = {
        layer: {(f["rule"], f["target"]) for f in results.get(CONTROL, [])}
        for layer, results in layers.items()
    }
    print("  TP = right class at the right target | NEAR = right target, wrong")
    print("  claim | ABSTAIN = honestly indeterminate, routes | MISS = nothing\n")
    scored = {did: score_defect(did, d, layers, baseline) for did, d in defects.items()}
    for did, d in defects.items():
        s = scored[did]
        note = ", ".join(x.replace("detect_", "") for x in s["by"]) or (
            f"near: {', '.join(s['near'])}" if s["near"] else ""
        )
        if s["abstained"]:
            note += ("; " if note else "") + "abstained by dom -> routes"
        print(f"  [{d['detectable_by']:6}] {s['verdict']:8} {did:22} {note}")

    tp = {i for i, s in scored.items() if s["verdict"] == "TP"}
    for klass in ("dom", "pixels"):
        ids = {i for i, d in defects.items() if d["detectable_by"] == klass}
        print(f"  {klass:6} true positives: {len(tp & ids)}/{len(ids)}")
    allids = set(defects)
    print(f"  union of the deterministic layers: {len(tp)}/{len(allids)}")
    residue = sorted(allids - tp)
    print(f"  residue routed to the vision layer: {residue or 'none'}")
    print("  That residue IS the queue this stack exists to make small, and it is")
    print("  the class no rule can grow into: not a violation, a judgement about")
    print("  whether the page makes sense.")

    # --- Off-target: the false positives a control run cannot see -------------
    print("\n" + "=" * 78)
    print("OFF-TARGET -- findings on a defect page naming something the defect")
    print("did not touch. The control cannot see these; the manifest counts them.")
    print("=" * 78)
    print("A verdict, not a count. The injected CSS names exactly what changed, so")
    print("an off-target finding INSIDE an injected selector is a real consequence")
    print("of the defect; one outside every injected selector is the noise.\n")
    collateral, noise = 0, 0
    for did, d in defects.items():
        touched = [
            sel.strip()
            for chunk in d["css"].split("}")
            if "{" in chunk
            for sel in chunk.split("{")[0].split(",")
            if sel.strip()
        ]
        for layer, results in layers.items():
            for f in results.get(did, []):
                if (f["rule"], f["target"]) in baseline[layer]:
                    continue
                if target_matches(d["target"], f["target"]):
                    continue
                is_collateral = any(target_matches(sel, f["target"]) for sel in touched)
                collateral += is_collateral
                noise += not is_collateral
                print(
                    f"  {'COLLATERAL' if is_collateral else 'NOISE     '} "
                    f"{did:22} [{f['rule']:22}] {f['target'][:44]}"
                )
    print(f"\n  {collateral} collateral (inside an injected selector -- a true")
    print("    consequence of the defect, not a false positive)")
    print(f"  {noise} noise (outside every injected selector -- these are false")
    print("    positives the control page structurally cannot see)")

    # --- What this corpus can and cannot certify -----------------------------
    n_control_pages = 1
    print("\n" + "=" * 78)
    print(f"GATE: {'PASS -- zero control false positives' if gate_ok else 'FAIL'}")
    print(f"BOUND: {n_control_pages} control page. Rule of three puts the 95% upper")
    print("  bound on the true FP rate at 3/1 -- i.e. this run does not bound it at")
    print("  all, and no arithmetic over this corpus will. It shows the rules are")
    print("  not obviously broken. The denominator that would bound it is a mined")
    print("  corpus of pages that shipped and were never touched by a visual-bug")
    print("  fix, where every finding is a false positive by construction.")
    print("=" * 78)
    sys.exit(0 if gate_ok else 1)


if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "corpus/out").resolve())
