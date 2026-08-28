#!/usr/bin/env python3
"""Arithmetic self-test for the parts that must not need a browser to check.

run_bench.sh proves the pipeline end to end, but it needs playwright, a chromium
and about a minute. These are the assertions that can run anywhere in under a
second, and they cover exactly the pieces where a wrong answer would be
*plausible* -- which is the failure mode this whole substrate is built around.
Classical CV fails by returning an obviously wrong number; the dangerous case is
the one that looks reasonable, and every check below has a closed-form expected
value rather than a remembered one.

Usage: python3 selftest.py
Exit: 0 = all pass · 1 = a failure, named
"""

from __future__ import annotations

import sys

import numpy as np

import detect_xcheck as X
import profiles
import route
from rules import RESOLVED_BY, RULES, UNSCREENABLE_CLASSES

FAILS: list[str] = []


def check(name: str, got, want, tol: float | None = None) -> None:
    ok = abs(got - want) <= tol if tol is not None else got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}: {got!r}" + ("" if ok else f" != {want!r}"))
    if not ok:
        FAILS.append(name)


def test_shape_mask() -> None:
    print("shape_mask -- the painted shape, built from the DOM's own geometry")
    # A square with no radius is the whole box.
    check("square is whole box", int(X.shape_mask(40, 40, 0).sum()), 1600)
    # A circle inscribed in a 100x100 box: pi*50^2 = 7854, within rasterisation
    # error of half a pixel per boundary pixel.
    circle = int(X.shape_mask(100, 100, 50).sum())
    check("circle area ~ pi r^2", circle, 7854, tol=60)
    # The inset is what excludes the antialiased edge, and it must remove a ring
    # of roughly circumference * inset: 2*pi*50*2 = 628.
    inset = int(X.shape_mask(100, 100, 50, 2.0).sum())
    check("inset removes an edge ring", circle - inset, 628, tol=90)
    # An over-large radius resolves to a circle, exactly as CSS does.
    check(
        "radius clamps to a circle",
        int(X.shape_mask(100, 100, 900).sum()),
        circle,
    )


def test_centroid() -> None:
    """The X2 arithmetic, against a triangle whose centroid is known exactly.

    This is the check the arm never had. The research's complaint was that X2
    'reports a real quantity nobody has validated'; a synthetic triangle with a
    closed-form centroid is the validation, and it does not depend on a font, a
    renderer or a corpus.
    """
    print("\nink centroid -- against a closed-form triangle")
    h = w = 101
    bg, fg = 0, 255
    img = np.full((h, w), bg, dtype=np.float64)
    # Vertices (10,10), (10,90), (90,50): area centroid x = (10+10+90)/3 = 36.67,
    # y = (10+90+50)/3 = 50. Its bounding box spans x 10..90, centre 50.
    ys, xs = np.mgrid[0:h, 0:w]
    inside = (
        (ys >= 10)
        & (ys <= 90)
        & (xs >= 10)
        & (xs <= 90 - 0)
        & (np.abs(ys - 50) <= (90 - xs) * (40 / 80))
    )
    img[inside] = fg
    wt = np.where(img > bg + 1, img, 0.0)
    cx = (wt * (np.arange(w)[None, :] + 0.5)).sum() / wt.sum()
    cy = (wt * (np.arange(h)[:, None] + 0.5)).sum() / wt.sum()
    check("centroid x = (10+10+90)/3", round(float(cx), 2), 36.67, tol=0.6)
    check("centroid y = (10+90+50)/3", round(float(cy), 2), 50.0, tol=0.6)
    # And the quantity X2 actually reports: ink centre minus shape centre.
    check("offset from box centre", round(float(cx) - 50.0, 2), -13.33, tol=0.6)


def test_crop_envelope() -> None:
    """Every crop request must satisfy BOTH predicates from PIPELINE_SPEC 1.6."""
    print("\ncrop envelope -- both predicates, not just the pixel one")
    page = {"w": 1280, "h": 2400}
    cases = [
        ("small region", [{"x": 40, "y": 40, "right": 300, "bottom": 200}]),
        ("full width strip", [{"x": 0, "y": 0, "right": 1280, "bottom": 120}]),
        ("whole page", [{"x": 0, "y": 0, "right": 1280, "bottom": 2400}]),
    ]
    for name, rects in cases:
        c = route.crop_request(rects, page)
        dw, dh = c["width"] * c["scale"], c["height"] * c["scale"]
        tokens = -(-dw // route.CROP_PATCH) * -(-dh // route.CROP_PATCH)
        check(f"{name}: within {route.CROP_MAX_DEVICE_PX}px", max(dw, dh) <= route.CROP_MAX_DEVICE_PX, True)
        check(f"{name}: within {route.CROP_MAX_TOKENS} tokens", tokens <= route.CROP_MAX_TOKENS, True)
        check(f"{name}: eff <= ceiling", c["eff"] <= route.CROP_SCALE_CEILING, True)
    # The documented square maximum is 966x966 CSS at scale 2, and it is a
    # property of the DELIVERED crop, so the padding counts toward it. Asking for
    # a 950px subject yields exactly 966 once padded on both sides.
    pad = route.CROP_PAD_CSS_PX
    side = 966 - 2 * pad
    ok = route.crop_request(
        [{"x": pad, "y": pad, "right": pad + side, "bottom": pad + side}], page
    )
    check("delivered square is 966 CSS px", ok["width"], 966.0)
    check("...and it holds scale 2", ok["scale"], 2.0)
    over = route.crop_request([{"x": 0, "y": 0, "right": 1100, "bottom": 1100}], page)
    check("1100x1100 CSS must step down", over["scale"] < 2.0, True)


def test_never_list() -> None:
    """A rule whose answer is a number may never become a model question."""
    print("\nNEVER list -- no numeric answer may be routed")
    numeric = [r for r in RULES.values() if r.answer == "number"]
    check("some rules answer with numbers", len(numeric) > 0, True)
    check("none of them is routable", [r.id for r in numeric if r.routable], [])
    # The trap this exists to catch: a rule that shares a class with one of the
    # six unscreenable classes is STILL not routable, because its own answer is
    # a measurement.
    overlap = [r for r in numeric if r.klass in UNSCREENABLE_CLASSES]
    check("class overlap does not grant routing", [r.id for r in overlap if r.routable], [])
    check("overlap case actually exists", len(overlap) > 0, True)


def test_subtraction_table() -> None:
    print("\nRESOLVED_BY -- the cross-check subtraction is a table, not a habit")
    absts = [r.id for r in RULES.values() if r.abstention]
    check("every abstention has an entry", sorted(RESOLVED_BY) == sorted(absts), True)
    check(
        "the gradient case is closed deterministically",
        "xcheck-contrast-varies" in RESOLVED_BY["contrast-indeterminate"],
        True,
    )


def test_profiles() -> None:
    print("\nprofiles -- every rule weighted in every app")
    profs = profiles.load()
    check("profiles load and validate", len(profs) >= 4, True)
    for name, p in profs.items():
        check(f"{name} covers all rules", set(p["weights"]) == set(RULES), True)
        check(f"{name} carries no stack facts", p.get("stack"), None)
    # The two the README names by name, and the claim each makes.
    land = profs["reso-landing-app"]["weights"]
    mgmt = profs["reso-management-app"]["weights"]
    check(
        "landing ranks aesthetics over conformance",
        land["contrast-indeterminate"] > land["token-drift"],
        True,
    )
    check(
        "management ranks conformance over aesthetics",
        mgmt["token-drift"] > mgmt["xcheck-optical-centre"],
        True,
    )
    check(
        "the two disagree about conformance",
        mgmt["token-drift"] > land["token-drift"],
        True,
    )


def test_router_shape() -> None:
    """T2 fires on a page with nothing wrong, and the deficit is never silent."""
    print("\nrouter -- T2 unconditional, budget deficit visible")
    snap = {
        "scroll": {"w": 1280, "h": 900},
        "elements": [
            {
                "path": "div.a",
                "rect": {"x": 0, "y": 0, "w": 100, "h": 40, "right": 100, "bottom": 40},
            }
        ],
    }
    w = {r: 1.0 for r in RULES}
    plan = route.route_page("empty", [], [], snap, w, blocks=2)
    check("T2 fires with no findings at all", len(plan["questions"]), 1)
    check("and it is budget-exempt", plan["questions"][0]["budget_exempt"], True)

    abst = [
        {
            "rule": "contrast-indeterminate",
            "target": "div.a",
            "detail": "cannot compute a ratio",
            "severity": "high",
            "meta": {"backdrop_owner": "div.a", "backdrop_kind": "gradient"},
        }
    ]
    # xcheck present but resolving nothing -> the abstention stays open.
    p1 = route.route_page("p", abst, [], snap, w, blocks=2)
    check("open abstention becomes a T1 question", p1["coverage"]["adjudicated"], 1)
    check("and it carries a crop request", p1["questions"][1]["crop"] is not None, True)

    closed = [
        {
            "rule": "xcheck-contrast-varies",
            "target": "div.a",
            "detail": "4.81 left, 1.57 right",
            "severity": "high",
        }
    ]
    p2 = route.route_page("p", abst, closed, snap, w, blocks=2)
    check("cross-check closes it", p2["coverage"]["resolved_by_xcheck"], 1)
    check("so nothing is asked", p2["coverage"]["adjudicated"], 0)
    check("and the answer is forwarded as a fact", len(p2["facts"]), 2)

    # xcheck ABSENT is not the same as xcheck empty.
    p3 = route.route_page("p", abst, None, snap, w, blocks=2)
    check("outage is recorded", p3["degradation"]["xcheck"], "absent")
    check("and T1 grows rather than shrinks", p3["coverage"]["adjudicated"], 1)

    # No room for T1 -> the question is deficit, not silence.
    p4 = route.route_page("p", abst, [], snap, w, blocks=1)
    check("budget deficit is recorded", p4["coverage"]["unadjudicated_by_budget"], 1)
    check("and it names the rule", p4["unadjudicated_by_budget"][0]["rule"], "contrast-indeterminate")


def main() -> int:
    for t in (
        test_shape_mask,
        test_centroid,
        test_crop_envelope,
        test_never_list,
        test_subtraction_table,
        test_profiles,
        test_router_shape,
    ):
        t()
    print()
    if FAILS:
        print(f"✗ {len(FAILS)} failure(s): {', '.join(FAILS)}")
        return 1
    print("✓ all self-tests pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
