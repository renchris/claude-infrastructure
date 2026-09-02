#!/usr/bin/env python3
"""Negative tests. A gate that cannot fail is a green light with no teeth.

Every assertion here breaks something on purpose and demands that the pipeline
notice. They run against the captured corpus, so `capture.py` must have run.

Usage: python3 test_bench.py [corpus-dir]
"""

from __future__ import annotations

import io
import json
import contextlib
import pathlib
import sys

import detect_dom
import detect_xcheck
import fp_budget
import route

CORPUS = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "corpus/out").resolve()
HERE = pathlib.Path(__file__).resolve().parent
FAILURES: list[str] = []


def check(name: str, ok: bool, got: object = "") -> None:
    print(
        f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"   got {got!r}" if not ok else "")
    )
    if not ok:
        FAILURES.append(name)


def quiet(fn, *a, **kw):
    with contextlib.redirect_stdout(io.StringIO()):
        return fn(*a, **kw)


def main() -> int:
    manifest = json.loads((CORPUS / "manifest.json").read_text())
    defects = {d["id"]: d for d in manifest["defects"]}
    tokens = manifest["tokens"]

    print("the fixed X2 arm")
    xchk = detect_xcheck.run(CORPUS)
    check("silent on the control", xchk["clean"] == [], xchk["clean"])
    hits = [
        f for f in xchk["optical-centering"] if f["rule"] == "xcheck-optical-centre"
    ]
    check("fires on optical-centering", len(hits) == 1, len(hits))
    elsewhere = {
        p: [f for f in fs if f["rule"] == "xcheck-optical-centre"]
        for p, fs in xchk.items()
        if p != "optical-centering"
    }
    check("fires nowhere else", not any(elsewhere.values()), elsewhere)
    # The defect it was blind to: the arm must now be VARIANT under the injected
    # transform. Same page, same rule, and the only difference is the compensation.
    check(
        "measures the container, not the moving box",
        "centres this mark's box" in hits[0]["detail"]
        and "container" in hits[0]["detail"],
        hits[0]["detail"][:60],
    )

    print("the fixed X3 backdrop sampling")
    gradient = [
        f for f in xchk["contrast-on-gradient"] if f["rule"] == "xcheck-contrast-varies"
    ]
    check("reports a varying backdrop", len(gradient) == 2, len(gradient))
    check("and not on the control", not [f for f in xchk["clean"]], xchk["clean"])

    print("the FP budget gate can fail")
    saved = detect_xcheck.CENTROID_TOL_PX
    detect_xcheck.CENTROID_TOL_PX = 0.01
    rc = quiet(fp_budget.main, CORPUS)
    detect_xcheck.CENTROID_TOL_PX = saved
    check("a broken tolerance breaks the gate", rc == 1, rc)
    check("and the gate is green again after", quiet(fp_budget.main, CORPUS) == 0)

    print("the blast-radius matcher")
    radius = fp_budget.blast_radius(defects["contrast-on-gradient"])
    names = {c for c, _ in radius}
    check(
        "reads the CSS selectors, not the target",
        names == {"hero", "hero-caption"},
        names,
    )
    check(
        "a sibling under a restyled container is caused",
        fp_budget.in_radius(
            "div.hero:nth-of-type(1) > div.hero-title:nth-of-type(1)", radius
        ),
    )
    check(
        "an element outside it is not",
        not fp_budget.in_radius("div.panel:nth-of-type(5)", radius),
    )
    nth = fp_budget.blast_radius(defects["spacing-gap"])
    check(
        "nth-child is honoured",
        fp_budget.in_radius("div.kpi-row > div.kpi-card:nth-of-type(3)", nth)
        and not fp_budget.in_radius("div.kpi-row > div.kpi-card:nth-of-type(2)", nth),
    )

    print("the correctness floor")
    prof = route.load_profile(HERE, "reso-landing-app")
    prof["weights"] = dict(prof["weights"], contrast=0.0, **{"touch-target": 0.1})
    w, sev, why = route.weigh(prof, {"rule": "contrast", "severity": "high"})
    check("a profile cannot mute contrast", w == 1.0 and sev == 3.0, (w, sev))
    check("and the attempt is recorded", "clamped" in why, why)
    w2, _, _ = route.weigh(prof, {"rule": "token-drift", "severity": "low"})
    check("a taste rule still moves", w2 == 0.2, w2)

    print("the abstention router")
    dom = {
        f.stem: detect_dom.find(json.loads(f.read_text()), tokens)
        for f in sorted((CORPUS / "snapshots").glob("*.json"))
    }
    snap = json.loads((CORPUS / "snapshots" / "contrast-on-gradient.json").read_text())
    bench = route.load_profile(HERE, "bench")
    on = route.route_page(
        "g",
        dom["contrast-on-gradient"],
        xchk["contrast-on-gradient"],
        snap,
        {**bench, "discharge": True},
    )
    off = route.route_page(
        "g",
        dom["contrast-on-gradient"],
        xchk["contrast-on-gradient"],
        snap,
        {**bench, "discharge": False},
    )
    check("the cross-check empties the queue", on["queued"] == 0, on["queued"])
    check("and without it the queue is not empty", off["queued"] == 2, off["queued"])
    crops = [r for r in off["requests"] if r["kind"] == "crop"]
    check("two abstentions collapse to one crop", len(crops) == 1, len(crops))
    check(
        "the crop costs less than the page",
        crops[0]["visual_tokens"] < 1518,
        crops[0]["visual_tokens"],
    )
    check(
        "a settled finding is never routed",
        all(r["rule"] != "contrast" for r in off["requests"]),
    )
    check(
        "every request forbids a number",
        all("no number" in r["prohibition"] for r in off["requests"]),
    )
    gest = [r for r in off["requests"] if r["kind"] == "gestalt"]
    check("the gestalt call forbids a score", "no score" in gest[0]["prohibition"])

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILURE(S): " + "; ".join(FAILURES))
        return 1
    print("all negative tests hold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
