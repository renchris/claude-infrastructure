#!/usr/bin/env python3
"""Acceptance tests for the perception pipeline. Plain asserts, no test runner.

Every test here asserts a property that was WRONG at some point and was caught by
a measurement rather than by reading the code. That is the admission rule: a test
that never had a failing version is documentation wearing an assert.

Requires a captured corpus:
    python3 corpus/build_corpus.py corpus/out
    python3 capture.py corpus/out --dpr 1,1.5
    python3 detect_dom.py corpus/out && python3 detect_xcheck.py corpus/out --x2

Usage: python3 test_pipeline.py [corpus-dir]
Exit:  0 all passed · 1 at least one failed
"""

from __future__ import annotations

import json
import pathlib
import sys

import numpy as np
from PIL import Image

import detect_dom
import detect_xcheck
import profiles
import route

CORPUS = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "corpus/out").resolve()
RESULTS: list[tuple[bool, str, str]] = []


def check(name: str, fn) -> None:
    try:
        detail = fn() or ""
        RESULTS.append((True, name, detail))
    except AssertionError as e:
        RESULTS.append((False, name, str(e)))
    except Exception as e:  # a test that errors is a test that failed
        RESULTS.append((False, name, f"{type(e).__name__}: {e}"))


def _snap(page: str) -> dict:
    return json.loads((CORPUS / "snapshots" / f"{page}.json").read_text())


def _png(page: str) -> pathlib.Path:
    return CORPUS / "shots" / f"{page}.png"


def _tokens() -> dict:
    return json.loads((CORPUS / "manifest.json").read_text())["tokens"]


def _xcheck(page: str) -> list[dict]:
    detect_xcheck.X2_ENABLED = True
    return detect_xcheck.check(_snap(page), _png(page))


def _glyph_container(findings: list[dict]) -> dict | None:
    for f in findings:
        if f["rule"].startswith("xcheck-optical-centre"):
            return f
    return None


# --------------------------------------------------------------------------
# The ship gate. Absolute zero asserted findings on a page with no defect.
# --------------------------------------------------------------------------
def test_control_is_quiet_dom():
    f = detect_dom.find(_snap("clean"), _tokens())
    bad = [x for x in f if x["verdict"] == "asserted"]
    assert not bad, f"{len(bad)} asserted finding(s) on the control: {bad[:2]}"
    return f"{len(f)} finding(s), 0 asserted"


def test_control_is_quiet_xcheck():
    f = _xcheck("clean")
    bad = [x for x in f if x["verdict"] == "asserted"]
    assert not bad, f"{len(bad)} asserted finding(s) on the control: {bad[:2]}"
    return f"{len(f)} finding(s), 0 asserted (X2 on)"


def test_dom_still_finds_all_nine():
    """The fixes must not cost the layer its measured 9/9."""
    man = json.loads((CORPUS / "manifest.json").read_text())
    dom_defects = [d["id"] for d in man["defects"] if d["detectable_by"] == "dom"]
    base = {
        (f["rule"], f["target"], f["detail"])
        for f in detect_dom.find(_snap("clean"), _tokens())
    }
    missed = []
    for did in dom_defects:
        found = [
            f
            for f in detect_dom.find(_snap(did), _tokens())
            if (f["rule"], f["target"], f["detail"]) not in base
        ]
        if not found:
            missed.append(did)
    assert not missed, f"no novel finding on {missed}"
    return f"{len(dom_defects)}/{len(dom_defects)} DOM-determined defects still caught"


# --------------------------------------------------------------------------
# X2 defect (a): the measurement was INVARIANT under the compensation it
# existed to verify. It compared ink to the element's own POST-transform box.
# --------------------------------------------------------------------------
def test_x2_is_no_longer_invariant():
    a = _glyph_container(_xcheck("clean"))
    b = _glyph_container(_xcheck("optical-centering"))
    assert a and b, "X2 produced no record on one of the two pages"
    dxa = a["facts"]["offset_x_px"]
    dxb = b["facts"]["offset_x_px"]
    delta = abs(dxa - dxb)
    assert delta > 1.0, (
        f"offset_x is {dxa} on clean and {dxb} on optical-centering "
        f"(delta {delta:.2f}px) -- the old bug measured them IDENTICAL"
    )
    # The corpus removes a translate(2px, 2px); a correct measurement recovers it.
    assert abs(delta - 2.0) < 0.35, (
        f"delta {delta:.2f}px does not match the injected 2px"
    )
    return f"clean {dxa:+.2f}px vs defect {dxb:+.2f}px = {delta:.2f}px, injected 2px"


def test_x2_measures_against_the_container():
    """The subject is the container. Measuring the mark against its own box is
    the invariance bug, so the mark itself must never be the target."""
    for page in ("clean", "optical-centering"):
        for f in _xcheck(page):
            if f["rule"].startswith("xcheck-optical-centre"):
                assert not f["target"].endswith("span.glyph"), (
                    f"X2 reported against the mark ({f['target']}) rather than its "
                    f"container -- that is the post-transform box, and it cannot move"
                )
    return "target is the container on both pages"


# --------------------------------------------------------------------------
# X2 defect (b): the square crop's corners -- page background outside a round
# button -- counted as ink and swamped a 16px glyph.
# --------------------------------------------------------------------------
def test_x2_mask_excludes_the_corners():
    snap = _snap("clean")
    img = np.asarray(Image.open(_png("clean")).convert("RGB")).astype(np.int16)
    scale = img.shape[1] / snap["scroll"]["w"]
    el = next(
        e for e in snap["elements"] if e["path"].endswith("glyph-btn:nth-of-type(2)")
    )
    r = el["rect"]
    x0, y0 = int(round(r["x"] * scale)), int(round(r["y"] * scale))
    mask = detect_xcheck.shape_mask(
        r, detect_xcheck.px(el["styles"]["border-radius"]), scale
    )
    reg = img[y0 : y0 + mask.shape[0], x0 : x0 + mask.shape[1]]

    def ink_fraction(sel):
        vals, counts = np.unique(reg[sel], axis=0, return_counts=True)
        surface = vals[counts.argmax()]
        d = np.abs(reg.astype(np.int32) - surface.astype(np.int32)).sum(axis=2)
        return float(((d > detect_xcheck.INK_DIST) & sel).sum()) / float(sel.sum())

    whole = np.ones(mask.shape, bool)
    assert ink_fraction(mask) < ink_fraction(whole) / 2, (
        "masking did not reduce the ink fraction -- the corners are still counted"
    )
    return (
        f"ink fraction {ink_fraction(whole):.3f} unmasked -> "
        f"{ink_fraction(mask):.3f} inside the painted shape"
    )


# --------------------------------------------------------------------------
# X2 defect (c), exposed by fixing the first two: the offset has no
# font-independent zero, so it must abstain rather than assert.
# --------------------------------------------------------------------------
def test_x2_abstains_rather_than_asserting():
    f = _glyph_container(_xcheck("optical-centering"))
    assert f, "X2 produced no record on the defect page"
    assert f["verdict"] == "indeterminate", (
        f"X2 asserted a {f['facts']['offset_x_px']}px offset. There is no "
        f"font-independent zero for it -- the same glyph is 3.7px low on this "
        f"renderer and 1.9px high on the one the corpus was authored against."
    )
    hx, hy = f["facts"]["mark_half_extent_px"]
    assert abs(f["facts"]["offset_x_px"]) <= hx and abs(f["facts"]["offset_y_px"]) <= hy
    return "verdict=indeterminate, inside the mark's own half-extent"


# --------------------------------------------------------------------------
# X3's sampler took the MODAL colour of each third, which on white-on-gradient
# text is the text's own white. It compared white to white and shipped silent.
# --------------------------------------------------------------------------
def test_x3_resolves_the_gradient():
    f = [
        x
        for x in _xcheck("contrast-on-gradient")
        if x["rule"] == "xcheck-contrast-varies"
    ]
    assert f, (
        "X3 found nothing on the gradient page -- the sampler is reading the ink again"
    )
    caption = [x for x in f if "hero-caption" in x["target"]]
    assert caption, "X3 missed the hero caption specifically"
    lo = min(
        caption[0]["facts"]["contrast_left"], caption[0]["facts"]["contrast_right"]
    )
    assert lo < 4.5, f"the failing end reads {lo}:1, which would not fail a reader"
    return (
        f"{caption[0]['facts']['contrast_left']}:1 left, "
        f"{caption[0]['facts']['contrast_right']}:1 right"
    )


def test_x3_agrees_with_the_cascade_on_a_solid_backdrop():
    """The sampler must be right where the cascade is also right, or its
    disagreement elsewhere means nothing."""
    assert not [
        x for x in _xcheck("contrast-plain") if x["rule"] == "xcheck-contrast-varies"
    ], "X3 claims a varying backdrop on a page whose backdrop is solid white"
    return "silent on contrast-plain, where the DOM already answers"


# --------------------------------------------------------------------------
# The dedup key must span the CLAIM, not just its location. Keying on
# (rule, target) suppressed a real defect using the control's own finding.
# --------------------------------------------------------------------------
def test_dedup_key_spans_the_claim():
    ctrl = _xcheck("clean")
    defect = _xcheck("optical-centering")
    two = {(f["rule"], f["target"]) for f in ctrl}
    three = {(f["rule"], f["target"], f["detail"]) for f in ctrl}
    by_two = [f for f in defect if (f["rule"], f["target"]) not in two]
    by_three = [f for f in defect if (f["rule"], f["target"], f["detail"]) not in three]
    assert len(by_three) > len(by_two), (
        "the 2-tuple and 3-tuple keys agree here, so this test proves nothing"
    )
    return f"2-tuple key finds {len(by_two)}, 3-tuple key finds {len(by_three)}"


# --------------------------------------------------------------------------
# The router.
# --------------------------------------------------------------------------
def test_router_subtracts_what_the_xcheck_closed():
    p = route.route(CORPUS, "contrast-on-gradient", "default")
    assert p["counts"]["T1_resolved_by_xcheck"] == 2, (
        f"expected both contrast abstentions closed, got "
        f"{p['counts']['T1_resolved_by_xcheck']}"
    )
    assert not [r for r in p["routes"] if r["klass"] == "contrast-indeterminate"], (
        "a closed abstention is still in the vision queue"
    )
    return "2 abstentions closed at zero model cost, 0 left in the queue"


def test_router_widens_when_the_xcheck_is_absent(tmpname="_t_outage"):
    """Fail-closed composing into fail-never: an absent cross-check must GROW
    the queue, because an empty result and a missing result look identical."""
    p_ok = route.route(CORPUS, "contrast-on-gradient", "default")
    xchk = CORPUS / "findings_xcheck.json"
    saved = xchk.read_text()
    try:
        doc = json.loads(saved)
        doc.pop("contrast-on-gradient", None)
        xchk.write_text(json.dumps(doc))
        p_down = route.route(CORPUS, "contrast-on-gradient", "default")
    finally:
        xchk.write_text(saved)
    assert p_down["counts"]["T1_subjects"] > p_ok["counts"]["T1_subjects"], (
        f"queue did not grow under a cross-check outage: "
        f"{p_ok['counts']['T1_subjects']} -> {p_down['counts']['T1_subjects']}"
    )
    assert not p_down["xcheck_available"]
    return (
        f"T1 subjects {p_ok['counts']['T1_subjects']} -> "
        f"{p_down['counts']['T1_subjects']} when the page key is missing"
    )


def test_router_routes_the_unscreenable_unconditionally():
    p = route.route(CORPUS, "clean", "reso-management-app")
    t2 = {r["klass"] for r in p["routes"] if r["trigger"] == "T2"}
    assert t2 == set(route.UNSCREENABLE), f"T2 is {t2}"
    return f"{len(t2)} classes routed even on the clean control"


def test_router_never_asks_for_a_number():
    for page in ("clean", "contrast-on-gradient", "hierarchy-inversion"):
        for app in ("default", "reso-landing-app", "reso-web-app"):
            for r in route.route(CORPUS, page, app)["routes"]:
                assert not route._DIGIT.search(r["question"]), (
                    f"routed question carries a number: {r['question']!r}"
                )
    try:
        route._assert_no_numbers("Is this gap 16px?", "test")
    except route.RouteError:
        pass
    else:
        raise AssertionError("_assert_no_numbers accepted a question with a number")
    return "no routed question carries a digit, and the guard rejects one that does"


def test_router_never_gates_ci():
    p = route.route(CORPUS, "clean", "default")
    assert p["gates_ci"] is False
    return "advisory triage only; taste stays human"


def test_crop_requests_fit_the_envelope():
    seen = 0
    for page in ("contrast-on-gradient", "clean"):
        for r in route.route(CORPUS, page, "default")["routes"]:
            c = r.get("crop")
            if not c:
                continue
            seen += 1
            assert c["rasterised"] is False, "the router rasterised a crop"
            assert c["tokens"] <= route.CROP_TOKENS_MAX, f"{c['tokens']} tokens"
            assert c["scale"] <= route.EFF_CEILING, "a crop bought magnification"
            assert c["rect_css"]["w"] * c["scale"] <= route.CROP_MAX_PX
    assert seen, "no crop requests were produced, so this test proves nothing"
    return f"{seen} crop request(s), all inside the token and pixel envelope"


# --------------------------------------------------------------------------
# Profiles.
# --------------------------------------------------------------------------
def test_profiles_refuse_to_weaken_a_pinned_family():
    doc = profiles.load()
    doc["profiles"]["reso-landing-app"]["weights"]["correctness"] = 0.5
    try:
        import tempfile

        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
            json.dump(doc, fh)
            tmp = pathlib.Path(fh.name)
        profiles.load(tmp)
    except profiles.ProfileError:
        return "a profile lowering `correctness` is refused at load"
    raise AssertionError(
        "load() accepted a profile that weakens contrast/overflow/target"
    )


def test_zero_weight_abstains_it_does_not_skip():
    p = route.route(CORPUS, "radius-drift", "reso-web-app")
    assert not [f for f in p["forwarded"] if f["family"] == "conformance"], (
        "conformance asserted under a zero weight"
    )
    holes = {u["klass"] for u in p["unroutable"]}
    assert "token-drift" in holes, (
        "the zero-weighted finding vanished. A skipped check and a clean check are "
        "the same bytes, which is the failure this pipeline exists to avoid."
    )
    return "token-drift becomes a reported coverage hole, not silence"


def test_unanswerable_abstentions_are_not_queued():
    """The NEVER list applied to ROUTING: a question can be worded without a
    number and still have no visual answer."""
    p = route.route(CORPUS, "radius-drift", "reso-web-app")
    queued = {r["klass"] for r in p["routes"] if r["trigger"] == "T1"}
    assert "token-drift" not in queued, "token membership was sent to an eye"
    return "identity questions stay out of the image budget"


def test_apps_actually_differ():
    """A weighting file that changes nothing is decoration."""
    plans = {
        app: route.route(CORPUS, "radius-drift", app)
        for app in ("reso-landing-app", "reso-management-app", "reso-web-app")
    }
    budgets = {a: p["image_budget"] for a, p in plans.items()}
    surfacing = {
        a: [f["surfacing"] for f in p["forwarded"] if f["family"] == "conformance"]
        for a, p in plans.items()
    }
    assert len(set(budgets.values())) > 1, (
        f"every app gets the same image budget: {budgets}"
    )
    assert surfacing["reso-landing-app"] != surfacing["reso-management-app"], (
        "marketing and design-system profiles surface conformance identically"
    )
    return f"image budgets {budgets}; landing={surfacing['reso-landing-app']}, mgmt={surfacing['reso-management-app']}"


def main() -> int:
    if not (CORPUS / "snapshots").exists():
        print(f"no captured corpus at {CORPUS}. Build and capture it first:")
        print("  python3 corpus/build_corpus.py corpus/out")
        print("  python3 capture.py corpus/out --dpr 1,1.5")
        return 1
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            check(name[5:].replace("_", " "), fn)
    width = max(len(n) for _, n, _ in RESULTS)
    for ok, name, detail in RESULTS:
        print(f"  {'PASS' if ok else 'FAIL'}  {name:{width}}  {detail}")
    failed = [r for r in RESULTS if not r[0]]
    print(f"\n{len(RESULTS) - len(failed)}/{len(RESULTS)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
