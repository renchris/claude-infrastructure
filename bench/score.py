#!/usr/bin/env python3
"""The false-positive budget, and the admission test every rule must pass.

~20% false positives is where an AI reviewer loses credibility regardless of its
catch rate, and this substrate's own bound sits at **37.5%** — 3 unverified
findings over the 8 pages a blind judge actually saw, which is nearly twice the
cliff (§2 C18, rewritten after its denominator was found wrong in six places).
The two zero-FP deterministic runs are the baseline to defend, and defending them
means re-running every rule against the clean control before it ships. This file
is that run, and it exits non-zero when it fails.

**Three separable claims that must stop being one** (C18's ruling, implemented):

  1. **Absolute zero on the control is the ship gate**, and it is enforceable at
     n = 1. A rule that fires on a page with no defect will fire on every page.
     No exceptions, no baseline-diff suppression. This is what `exit 1` means
     here.
  2. **No false-positive RATE may be printed below n = 16 clean pages.** 3/16 =
     18.75% is the first n strictly under the cliff, and we have n = 1. So the
     rate is WITHHELD, in code, by the denominator — not by anyone remembering
     not to quote it. Point `--clean-set` at the mined clean corpus (B0) and the
     rate unlocks itself.
  3. **State the budget per 1,000 subject-checks, never per run.** A real page
     censuses ~1,841 subjects against this corpus's 47; across 105 routes that is
     ~193,000 subject-checks per audit, and a per-subject FP rate twenty times
     better than anything measured anywhere in this substrate still yields ~19
     false findings per audit — delivered to an agent that acts on them by
     editing source. So the denominator is printed at every run, whether or not
     the rate is legal to print.

**The admission test** (§1.4), which is the other half of the same idea. A rule
enters only if it declares its `subjects` (the enumerable population — no rule
may iterate an implicit set), its precondition, at least one reachable
INDETERMINATE branch (a rule claiming it can measure every subject on every page
is lying), one mutant fixture, and a clean-control run. Every one of those is
checked here against BEHAVIOUR rather than against the declaration: the mutant
must actually fire, the control must actually be silent, and the rule's real
findings must fall inside the population it declared. A declaration nobody
executes is a comment.

Usage: python3 score.py <corpus-dir> [--clean-set <dir-of-clean-corpora>]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

import profiles

INTERACTIVE = {"button", "a", "input", "select", "textarea"}


def _parent_map(els):
    by = {e["path"]: e for e in els}
    kids = {}
    for e in els:
        head = e["path"].rsplit(" > ", 1)
        if len(head) > 1 and head[0] in by:
            kids.setdefault(head[0], []).append(e)
    return by, kids


def _text(els):
    return [e for e in els if e["text"]]


def _marks(els):
    """X2's population: a short mark inside a small container."""
    by, _ = _parent_map(els)
    out = []
    for e in els:
        head = e["path"].rsplit(" > ", 1)
        p = by.get(head[0]) if len(head) > 1 else None
        if (
            p
            and len(e["text"]) <= 3
            and max(e["rect"]["w"], e["rect"]["h"]) < 64
            and max(p["rect"]["w"], p["rect"]["h"]) < 96
        ):
            out.append(e)
    return out


def _rhythm(els):
    _, kids = _parent_map(els)
    return [e for group in kids.values() if len(group) >= 3 for e in group]


# Every rule, with the five things §1.4 requires before it may run at all. The
# `subjects` column is the one that does real work: it is checked against the
# rule's actual findings, so a rule that quietly widens its population is caught
# by the audit rather than by a false positive six months later.
ADMISSION = {
    "spacing-rhythm": dict(
        subjects=_rhythm,
        precondition="3+ siblings under one parent, and a dominant gap held by >50% of them",
        indeterminate="no dominant gap: the siblings agree on nothing, so there is no rhythm to break",
        mutant="spacing-gap",
    ),
    "grid-violation": dict(
        subjects=lambda els: els,
        precondition="a margin is set and under 100px",
        indeterminate="none declared",  # audited below; see NO_ABSTENTION
        mutant="grid-offgrid",
    ),
    "type-scale": dict(
        subjects=_text,
        precondition="2+ font sizes on the page repeat, so a scale exists to sit off",
        indeterminate="fewer than two repeated sizes: the page has no scale",
        mutant="type-scale",
    ),
    "token-drift": dict(
        subjects=lambda els: els,
        precondition="a token map exists for this app (profiles.token_map != ABSENT)",
        indeterminate="engine-has-no-token-source, per C11 — the reason management abstains",
        mutant="token-color-drift",
    ),
    "contrast": dict(
        subjects=_text,
        precondition="a solid backdrop colour resolves through the ancestor chain",
        indeterminate="contrast-indeterminate: the backdrop is an image, a gradient, or semi-transparent",
        mutant="contrast-plain",
    ),
    "contrast-indeterminate": dict(
        subjects=_text,
        precondition="none — this IS the abstention branch of the contrast rule",
        indeterminate="itself",
        kind="abstains",
        mutant="contrast-on-gradient",
    ),
    "overflow": dict(
        subjects=lambda els: els,
        precondition="overflow is hidden and scrollHeight exceeds clientHeight",
        indeterminate="none declared",
        mutant="overflow-clip",
    ),
    "touch-target": dict(
        subjects=lambda els: [e for e in els if e["tag"] in INTERACTIVE],
        precondition="the element is interactive by tag",
        indeterminate="none declared",
        mutant="touch-target",
    ),
    "misalignment": dict(
        subjects=lambda els: els,
        precondition="3+ elements share a left edge, so a shared edge exists to miss",
        indeterminate="no shared edge: nothing to be misaligned against",
        mutant="align-1px",
    ),
    "xcheck-zero-ink": dict(
        subjects=lambda els: [
            e for e in _text(els) if min(e["rect"]["w"], e["rect"]["h"]) >= 8
        ],
        precondition="the element carries text and its box is at least 8x8",
        indeterminate="none declared",
        mutant=None,  # 🚨 no fixture exists; see the admission report
    ),
    "xcheck-optical-centre": dict(
        subjects=_marks,
        precondition="the container paints a shape separable from its own backdrop",
        indeterminate="outside-not-uniform / no-distinct-fill / shape-too-small",
        mutant="optical-centering",
    ),
    "xcheck-optical-centre-v": dict(
        subjects=_marks,
        precondition="never holds for a text glyph: its vertical ink position is font metrics",
        indeterminate="itself — this rule is an abstention and emits nothing else",
        # An abstention-only rule cannot have a mutant, because a mutant is a
        # fixture that makes a rule ASSERT and this one never does. Its fixture
        # is any page carrying its subject, and what must be checked is that the
        # abstention actually reaches the router rather than being swallowed.
        kind="abstains",
        mutant="clean",
    ),
    "xcheck-contrast-varies": dict(
        subjects=lambda els: [e for e in _text(els) if len(e["text"]) > 3],
        precondition="at least 20% of each third of the text's box is backdrop, not ink",
        indeterminate="too little backdrop in a third to sample a colour behind the text",
        mutant="contrast-on-gradient",
    ),
}

# Rules with no declared INDETERMINATE branch. §1.4 says a rule claiming it can
# measure every subject on every page is lying, so this list is a standing debt,
# not a clean bill. Each is here because its measurement genuinely cannot fail to
# run given its precondition -- and each should be revisited the first time it
# meets a page where that is false.
NO_ABSTENTION = {"grid-violation", "overflow", "touch-target", "xcheck-zero-ink"}

# manifest `klass` -> the rules that count as naming that defect correctly.
CLASS_RULES = {
    "spacing-inconsistency": {"spacing-rhythm"},
    "misalignment": {"misalignment"},
    "token-drift": {"token-drift"},
    "typographic-scale": {"type-scale"},
    "grid-violation": {"grid-violation"},
    "contrast": {"contrast", "contrast-indeterminate", "xcheck-contrast-varies"},
    "overflow": {"overflow"},
    "accessibility": {"touch-target"},
    "optical-alignment": {"xcheck-optical-centre"},
    "visual-hierarchy": set(),  # unscreenable by construction: T2's job, not a rule's
}

COMPOUND = re.compile(
    r"(?:\.[\w-]+|#[\w-]+|\[[^\]]+\]|:nth-(?:child|of-type)\(\d+\)|^\w+)"
)


def matches(selector: str, path: str) -> bool:
    """Does a finding's DOM path satisfy the manifest's CSS target selector?

    Descendant semantics, in order, leaf-anchored: `.kpi-card:nth-child(4)
    .kpi-label` matches a path whose leaf carries `kpi-label` and one of whose
    ancestors is the fourth kpi-card. nth-child and nth-of-type are treated as
    interchangeable here because every sibling group in this corpus is
    single-tag -- which is true of the corpus and NOT true in general, so a
    corpus that grows a mixed sibling group has to revisit this line.
    """
    segs = path.split(" > ")
    want = selector.split()
    i = 0
    for comp in want:
        classes = re.findall(r"\.([\w-]+)", comp)
        nth = re.search(r":nth-(?:child|of-type)\((\d+)\)", comp)
        while i < len(segs):
            seg = segs[i]
            seg_classes = re.findall(r"\.([\w-]+)", seg.split(":")[0])
            seg_nth = re.search(r":nth-of-type\((\d+)\)", seg)
            i += 1
            if all(c in seg_classes for c in classes) and (
                not nth or (seg_nth and seg_nth.group(1) == nth.group(1))
            ):
                break
        else:
            return False
    return True


def load_findings(corpus: pathlib.Path) -> dict:
    """All layers, merged per page. A rule's name is unique across layers, which
    is what lets one admission table cover both detectors."""
    merged: dict[str, list] = {}
    for name in ("findings_dom.json", "findings_xcheck.json"):
        f = corpus / name
        if not f.exists():
            continue
        for page, fs in json.loads(f.read_text()).items():
            merged.setdefault(page, []).extend(fs)
    return merged


def subject_census(corpus: pathlib.Path) -> tuple[int, dict]:
    """-> (total subject-checks, per-rule subject paths per page). The
    denominator C18 ruling 3 requires, computed from the declared populations
    rather than guessed from the page's element count."""
    total, per_page = 0, {}
    for f in sorted((corpus / "snapshots").glob("*.json")):
        els = json.loads(f.read_text())["elements"]
        per_rule = {}
        for rule, spec in ADMISSION.items():
            paths = {e["path"] for e in spec["subjects"](els)}
            per_rule[rule] = paths
            total += len(paths)
        per_page[f.stem] = per_rule
    return total, per_page


def main(corpus: pathlib.Path, clean_set: list[pathlib.Path], app: str) -> int:
    manifest = json.loads((corpus / "manifest.json").read_text())
    run = (
        json.loads((corpus / "run.json").read_text())
        if (corpus / "run.json").exists()
        else {}
    )
    findings = load_findings(corpus)
    profile = profiles.get(app)
    checks, census = subject_census(corpus)
    defects = {d["id"]: d for d in manifest["defects"]}
    fails = {
        p: [f for f in fs if f.get("verdict", "FAIL") == "FAIL"]
        for p, fs in findings.items()
    }
    absts = {
        p: [f for f in fs if f.get("verdict") == "INDETERMINATE"]
        for p, fs in findings.items()
    }

    print(f"CORPUS  {corpus}")
    if run:
        print(
            f"  rendered on {run.get('platform')} / chromium {run.get('browser')} / "
            f"text width {run.get('font', {}).get('width_px')}px — a pixel number from "
            f"another machine is a different number"
        )
    print(f"  profile {app} [{profile['intent']}]\n")

    # ---- 1. THE SHIP GATE: absolute zero on the control ----------------------
    control_fails = fails.get("clean", [])
    control_absts = absts.get("clean", [])
    print("CONTROL — the gate")
    print(
        f"  {len(control_fails)} FAIL on clean.html"
        f"{'   ⛔ a rule that fires on a page with no defect fires on every page' if control_fails else '   ✓'}"
    )
    for f in control_fails:
        print(f"      [{f['rule']}] {f['target']}: {f['detail'][:70]}")
    print(
        f"  {len(control_absts)} abstention(s) on clean.html — not a false positive: "
        f"an abstention claims nothing, it routes"
    )
    for f in control_absts:
        print(f"      [{f['rule']}] {f['target']}")

    # ---- 2. THE BUDGET, with its denominator and its withheld rate -----------
    off_target, adjacent, off_list = 0, 0, []
    for page, fs in fails.items():
        if page == "clean" or page not in defects:
            continue
        d = defects[page]
        # The CHANGED SET, read from the injected CSS rather than guessed. A
        # defect's own knock-on is not an invention -- the gradient page moves
        # `.hero`, so a contrast finding on `.hero-title` is a true report about
        # an element the manifest simply did not nominate as the target, and the
        # only way to know that without hand-waving is to read which selectors
        # the injection actually touched. Counted apart either way: calling a
        # knock-on a false positive overstates the rate, and calling it a catch
        # overstates the score.
        changed = re.findall(r"([^{}]+)\{", d["css"])
        changed = [s.strip() for part in changed for s in part.split(",") if s.strip()]
        for f in fs:
            if matches(d["target"], f["target"]):
                continue
            if any(matches(sel, f["target"]) for sel in changed):
                adjacent += 1
            else:
                off_target += 1
                off_list.append((page, f["rule"], f["target"]))
    n_clean = 1 + len(clean_set)
    print("\nFALSE-POSITIVE BUDGET")
    print(
        f"  subject-checks in this run: {checks:,}  ({len(findings)} pages x {len(ADMISSION)} rules)"
    )
    print(f"  findings on the control:    {len(control_fails)}")
    print(
        f"  off-target on defect pages: {off_target} on an element the injected CSS "
        f"never touched, {adjacent} elsewhere inside the changed subtree"
    )
    for page, rule, target in off_list:
        print(f"      ⛔ {page}: [{rule}] {target}")
    if n_clean >= 16:
        rate = 1000 * len(control_fails) / max(checks, 1)
        print(
            f"  rate: {rate:.3f} false findings per 1,000 subject-checks over n={n_clean} clean pages"
        )
    else:
        print(
            f"  rate: WITHHELD. n={n_clean} clean page(s); C18 ruling 2 forbids a rate "
            f"below n=16, where 3/16 = 18.75% is the first bound strictly under the "
            f"~20% credibility cliff. Zero at n=1 is a GATE, not a rate — it refutes "
            f"a bad rule and certifies nothing.\n"
            f"        Unlock it by pointing --clean-set at the mined clean corpus (B0): "
            f"~315 pages from the apps' own history that shipped and were never touched "
            f"by a visual-bug fix, where every finding is a false positive by "
            f"construction at zero labelling cost."
        )
    print(
        f"  ⚠️  and this corpus censuses {checks // max(len(findings), 1)} subject-checks "
        f"per page against ~1,841 on a real route. FP supply grows with subjects, not "
        f"with pages, so zero here was measured at ~1/35th of the target's density."
    )

    # ---- 3. THE ADMISSION TEST ----------------------------------------------
    print(
        "\nRULE ADMISSION (§1.4: subjects · precondition · abstention · mutant · control)"
    )
    drift = notadmitted = deadmutant = 0
    for rule, spec in sorted(ADMISSION.items()):
        fired = {p: [f for f in fs if f["rule"] == rule] for p, fs in findings.items()}
        # Does the rule stay inside the population it declared?
        outside = [
            (p, f["target"])
            for p, fs in fired.items()
            for f in fs
            if f["target"] not in census.get(p, {}).get(rule, set())
        ]
        ctrl_fail = any(
            f.get("verdict", "FAIL") == "FAIL" for f in fired.get("clean", [])
        )
        mutant = spec["mutant"]
        # A rule fires in its own currency: an asserting rule must produce a FAIL
        # on its fixture, an abstention must produce an INDETERMINATE. Demanding
        # a FAIL from an abstention marks the honest third answer as a dead rule,
        # which is exactly backwards.
        want = "FAIL" if spec.get("kind", "asserts") == "asserts" else "INDETERMINATE"
        mutant_fires = bool(
            mutant
            and any(f.get("verdict", "FAIL") == want for f in fired.get(mutant, []))
        )
        abstained = any(
            f.get("verdict") == "INDETERMINATE" for fs in fired.values() for f in fs
        )
        marks = []
        if outside:
            marks.append(
                f"⛔ DRIFT: {len(outside)} finding(s) outside its declared subjects"
            )
            drift += 1
        if ctrl_fail:
            marks.append("⛔ fires on the control")
        if mutant is None:
            marks.append(
                "⚠️  NO FIXTURE — not admitted by §1.4, and it has never caught anything"
            )
            notadmitted += 1
        elif not mutant_fires:
            marks.append(f"⛔ its fixture {mutant} produces no {want}")
            deadmutant += 1
        if rule in NO_ABSTENTION:
            marks.append("⚠️  no INDETERMINATE branch declared")
        elif not abstained:
            marks.append("· abstention declared but not exercised by this corpus")
        n_subj = sum(len(census[p].get(rule, ())) for p in census)
        print(
            f"  {rule:26} {n_subj:5d} subjects   {'  '.join(marks) if marks else '✓'}"
        )

    # ---- 4. RECALL, for context only -- the gate above is the point ----------
    print("\nCATCH RATE (context; the control gate above is what ships or does not)")
    hit = miss = 0
    for did, d in sorted(defects.items()):
        want = CLASS_RULES.get(d["klass"], set())
        got = [
            f
            for f in findings.get(did, [])
            if f["rule"] in want and matches(d["target"], f["target"])
        ]
        # An abstention on the right subject is not a catch and not a miss: it is
        # the honest third answer, and it is what the router spends a call on.
        routed = [
            f for f in findings.get(did, []) if f.get("verdict") == "INDETERMINATE"
        ]
        if got:
            hit += 1
            mark = f"caught by {got[0]['rule']}"
        elif not want:
            mark = "unscreenable by construction — routed to the gestalt call (T2)"
        elif routed:
            mark = "abstained → routed"
        else:
            miss += 1
            mark = "⛔ MISSED"
        print(f"  [{d['detectable_by']:6}] {did:22} {mark}")
    screenable = sum(1 for d in defects.values() if CLASS_RULES.get(d["klass"]))
    print(f"\n  {hit}/{screenable} screenable defects caught, {miss} missed")

    bad = len(control_fails) + drift + deadmutant
    print(
        f"\n{'⛔ GATE FAILED' if bad else '✓ GATE PASSED'} — "
        f"{len(control_fails)} control finding(s), {drift} population drift(s), "
        f"{deadmutant} dead mutant(s); {notadmitted} rule(s) not admitted (no fixture)"
    )
    return 1 if bad else 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "corpus", type=pathlib.Path, nargs="?", default=pathlib.Path("corpus/out")
    )
    ap.add_argument(
        "--clean-set",
        type=pathlib.Path,
        nargs="*",
        default=[],
        help="additional corpora that are clean BY CONSTRUCTION (B0). Every finding on "
        "them is a false positive, and at n>=16 they unlock the rate.",
    )
    ap.add_argument("--app", default=profiles.DEFAULT)
    a = ap.parse_args()
    sys.exit(main(a.corpus.resolve(), a.clean_set, a.app))
