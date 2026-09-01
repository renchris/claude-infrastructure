#!/usr/bin/env python3
"""The abstention router: turn what the deterministic layer could NOT answer into
a small, cropped queue for the vision layer -- and forward everything it COULD
answer as a fact, never as a question.

The seam this implements is the one the corpus measured. The deterministic
layer's most valuable output is not a finding, it is an abstention: on the
gradient page it returns `contrast-indeterminate: cannot compute a ratio,
backdrop is an image/gradient` rather than a pass. Every silent pass that should
have been an abstention is a defect shipped. The abstention set is exactly the
vision layer's job queue, and it is small, which is what makes the vision spend
affordable at all.

**Two triggers, because on this corpus the other three have volume zero.** The
ratified build order cuts this stage to roughly its honest size: route T2
unconditionally, forward everything else as a fact. What is here is that, plus
the T1 subtraction, because the subtraction is the part that must be code.

  T1  INDETERMINATE minus what the cross-check closed, collapsed by class.
  T2  the six unscreenable classes, once per page, unconditional, never cut for
      budget. Nothing screens them, so a budget cut here does not save a call --
      it deletes the only coverage they have.

🚨 **The T1 subtraction is gated on evidence the cross-check RAN ON THIS PAGE,
and T1 GROWS when it did not.** If the cross-check is down, an empty findings
file resolves nothing and looks exactly like nothing needing resolution --
fail-closed composing into fail-never. Testing that the file exists is not
enough, because "ran, found nothing" and "never ran" produce the same silence;
the page's own key is what separates them. A missing key widens the model queue
rather than narrowing it, and this is the one place in the pipeline where a
larger queue is the correct response to a layer failure.

🚨 **The NEVER list is enforced, not documented.** If the answer has a number in
it, the model does not get the question: distances, gaps, sizes, ratios, contrast
solid or gradient, token membership, animation timing, bounding boxes, and any
score, grade or ranking. `_assert_no_numbers` raises on a routed question
carrying a digit, so a future edit that quietly asks the eye to measure something
fails at the call rather than in a report. Numbers still travel -- as `facts`
riding beside the question, which is a different thing from asking for one.

This stage NEVER rasterises and NEVER gates. It emits crop *requests*; a crop
taken in a second browser pass is a different frame from the one the snapshot
describes, and the whole cross-layer argument rests on those being the same
frame. And it decides nothing about CI: its output is advisory triage, which is
the sanctioned role for the vision layer and the one the June 2026 campaign
ratified. Taste stays human.

Usage: python3 route.py <corpus-dir> [--app reso-management-app] [--page NAME]
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
import sys

import profiles

# The six classes nothing screens. They are routed once per page, unconditional,
# and each is phrased as the judgement it is rather than as a measurement.
UNSCREENABLE = {
    "hierarchy": "Does the eye land on the action this screen is for, or on something else?",
    "gestalt": "Do the things that belong together read as grouped, and the things that do not read as separate?",
    "content-fit": "Does the content look like it was written for this layout, or poured into it?",
    "semantic-coherence": "Does this screen make sense as one thing, or does it read as parts that met here?",
    "optical-alignment": "Do the marks read as aligned to a reader, whatever the boxes say?",
    "readability": "Is the text comfortable to read at this size, measure and rhythm?",
}

# Which cross-check rule closes which abstention class. The mapping is explicit
# so a new cross-check arm cannot silently start or stop resolving something.
RESOLVES = {
    "xcheck-contrast-varies": "contrast-indeterminate",
}

# An abstention only belongs in the vision queue if an EYE can answer it. This is
# the NEVER list applied to routing rather than to phrasing, and it is the half
# that is easy to miss: a question can be worded without a number and still be
# unanswerable by looking, because its answer is an identity rather than a
# judgement. "Is this the design token?" is not a thing anyone can see.
VISION_ANSWERABLE = {
    "contrast-indeterminate": "Is this text comfortable to read against what is actually behind it, across its whole width?",
    "xcheck-optical-centre-indeterminate": "Does this mark read as centred inside its container, to an eye rather than to a box model?",
}

# Abstentions no layer we have can close, each with the reason and the thing that
# would change it. These are COVERAGE, reported as a hole, and routing them would
# spend the image budget on a question that has no visual answer.
UNROUTABLE = {
    "token-drift": (
        "token membership is on the NEVER list -- the answer is an identity, not a "
        "judgement, and no eye can supply it",
        "an invertible class name (for Emotion: compiler.emotion.autoLabel='dev-only', "
        "labelFormat='[local]'), or a resolved token map with an explicit engine precedence",
    ),
    "grid-violation": (
        "the answer is a number the DOM already returns exactly",
        "a token map this app owns",
    ),
    "type-scale": (
        "the answer is a number the DOM already returns exactly",
        "a token map this app owns",
    ),
}

# Crop envelope. Both predicates must hold: the API's own pixel/byte clamp, and
# the patch-token budget, which is the binding one on a wide crop.
CROP_MAX_PX = 2000
CROP_TOKENS_MAX = 4784
PATCH = 28
CROP_PAD_CSS = 12.0  # a crop with no surround cannot answer "relative to what?"
# The review target is what a person sees at DPR 2. A defect visible only at 4x is
# manufactured false-positive supply, so a crop buys isolation, never magnification.
EFF_CEILING = 2.0

_DIGIT = re.compile(r"\d")


class RouteError(Exception):
    pass


def _assert_no_numbers(question: str, where: str) -> str:
    if _DIGIT.search(question):
        raise RouteError(
            f"routed question for {where} contains a number: {question!r}. If the "
            f"answer has a number in it, the model does not get the question -- the "
            f"DOM already returns it exactly, for free, with no hallucination risk. "
            f"Put the number in `facts`, not in the ask."
        )
    return question


def crop_request(rect: dict, page_w: float, page_h: float) -> dict:
    """A crop REQUEST in CSS px, with its own scale and its own prohibition.

    Never rasterises. Returns the rect, the effective scale the renderer may use
    without breaching the token budget, and -- when that scale lands below the
    DPR-2 review target -- the sentence the caption must carry, because a judge
    that is not told it cannot support a 1px claim will make one anyway.
    """
    x = max(0.0, rect["x"] - CROP_PAD_CSS)
    y = max(0.0, rect["y"] - CROP_PAD_CSS)
    w = min(page_w - x, rect["w"] + 2 * CROP_PAD_CSS)
    h = min(page_h - y, rect["h"] + 2 * CROP_PAD_CSS)

    # Largest scale whose patch count still fits, then clamped by the pixel cap
    # and by the ceiling. Solved rather than searched: tokens grow as scale^2.
    eff = EFF_CEILING
    for _ in range(64):
        tw, th = math.ceil(w * eff / PATCH), math.ceil(h * eff / PATCH)
        if (
            tw * th <= CROP_TOKENS_MAX
            and w * eff <= CROP_MAX_PX
            and h * eff <= CROP_MAX_PX
        ):
            break
        eff -= 0.02
    else:
        eff = 1.0
    eff = round(max(eff, 1.0), 2)
    req = {
        "rect_css": {
            "x": round(x, 2),
            "y": round(y, 2),
            "w": round(w, 2),
            "h": round(h, 2),
        },
        "scale": eff,
        "tokens": math.ceil(w * eff / PATCH) * math.ceil(h * eff / PATCH),
        "rasterised": False,
    }
    if eff < EFF_CEILING:
        req["caption_prohibition"] = (
            "do not assert any one-to-two pixel alignment, hairline-width or "
            "colour-drift finding from this image; if you suspect one, name the region"
        )
    return req


def region_label(target: str, snap_index: dict) -> str:
    """A name a person would use, so a finding never has to carry coordinates.

    Attribution becomes a lookup in the route plan rather than three coordinate
    multiplications owned by three stages -- an off-by-one there returns a real
    element in the wrong table row, and nothing reports an error.
    """
    el = snap_index.get(target)
    leaf = target.split(" > ")[-1]
    cls = leaf.split(":")[0]
    text = (el or {}).get("text", "").strip()
    if text:
        return f"{cls} -- {text[:38]!r}"
    return cls


def collapse_by_class(items: list[dict]) -> list[dict]:
    """One route per abstention CLASS, not per subject.

    A real page's census runs to ~1,841 subjects and abstentions arrive in the
    dozens; routing each one is an image budget nobody has. Routing the class once
    with its subjects listed is the same question asked once.
    """
    by_class: dict[str, dict] = {}
    for it in items:
        k = it["klass"]
        if k not in by_class:
            by_class[k] = {**it, "subjects": [], "subject_count": 0}
        by_class[k]["subjects"].append(it["region"])
        by_class[k]["subject_count"] += 1
    for v in by_class.values():
        v["subjects"] = v["subjects"][:8]
    return list(by_class.values())


def route(corpus: pathlib.Path, page: str, app: str, doc: dict | None = None) -> dict:
    doc = doc or profiles.load()
    prof_name, prof = profiles.profile_for(app, doc)

    snap = json.loads((corpus / "snapshots" / f"{page}.json").read_text())
    snap_index = {e["path"]: e for e in snap["elements"]}
    page_w = float(snap["scroll"]["w"])
    page_h = float(snap["scroll"]["h"])

    dom_path = corpus / "findings_dom.json"
    xchk_path = corpus / "findings_xcheck.json"
    dom_all = (
        json.loads(dom_path.read_text()).get(page, []) if dom_path.exists() else []
    )
    dom = profiles.weigh(dom_all, app, doc)

    # --- the subtraction, gated on the cross-check having RUN ON THIS PAGE ---
    # Not merely on the file existing. A present-but-empty file resolves nothing
    # and looks exactly like nothing needing resolution -- the same silence for
    # "ran, found nothing" and "never ran". The page key separates them: an entry
    # holding an empty list is a clean run; an absent key is an outage, and it
    # widens the queue instead of narrowing it.
    xchk_doc = json.loads(xchk_path.read_text()) if xchk_path.exists() else {}
    xcheck_available = page in xchk_doc
    resolved: set[tuple[str, str]] = set()
    xchk: list[dict] = []
    if xcheck_available:
        xchk = profiles.weigh(xchk_doc[page], app, doc)
        for f in xchk:
            if f["verdict"] != "asserted":
                continue
            closes = RESOLVES.get(f["rule"])
            if closes:
                resolved.add((closes, f["target"]))

    # --- T1: INDETERMINATE minus what the cross-check closed ----------------
    t1_raw, t1_dropped, unroutable_raw = [], [], []
    for f in dom + xchk:
        if f["verdict"] != "indeterminate":
            continue
        if (f["rule"], f["target"]) in resolved:
            t1_dropped.append(
                {"klass": f["rule"], "region": region_label(f["target"], snap_index)}
            )
            continue
        klass = f["rule"]
        base = klass.removesuffix("-indeterminate")
        if klass not in VISION_ANSWERABLE:
            why, needs = UNROUTABLE.get(
                base,
                (
                    "no layer in this pipeline answers this class",
                    "a rule, a cross-check arm, or a decision that it is out of scope",
                ),
            )
            unroutable_raw.append(
                {
                    "klass": klass,
                    "region": region_label(f["target"], snap_index),
                    "not_routed_because": why,
                    "would_need": needs,
                }
            )
            continue
        el = snap_index.get(f["target"])
        rect = f.get("facts", {}).get("rect") or (el or {}).get("rect")
        t1_raw.append(
            {
                "trigger": "T1",
                "klass": klass,
                "target": f["target"],
                "region": region_label(f["target"], snap_index),
                "question": _assert_no_numbers(VISION_ANSWERABLE[klass], f["target"]),
                "facts": f.get("facts", {}),
                "why_routed": f["detail"],
                "crop": crop_request(rect, page_w, page_h) if rect else None,
            }
        )
    t1 = collapse_by_class(t1_raw)
    unroutable = collapse_by_class(unroutable_raw)

    # --- T2: the six unscreenable classes, unconditional --------------------
    # Weighted by the app profile, but never to zero and never cut for budget:
    # nothing screens these, so cutting one deletes its only coverage rather than
    # deferring it. The weight decides how many IMAGES they get, not whether
    # they are asked.
    aes_w = prof["weights"]["aesthetics"]
    t2 = [
        {
            "trigger": "T2",
            "klass": k,
            "target": "<page>",
            "region": "the whole page, at viewport width",
            "question": _assert_no_numbers(q, k),
            "weight": aes_w,
            "crop": None,  # the global image; a crop cannot answer a page-global question
        }
        for k, q in UNSCREENABLE.items()
    ]

    forwarded = [f for f in dom + xchk if f["verdict"] == "asserted"]
    images = max(1, round(prof["vision_budget_images"] * max(aes_w, 0.25)))

    plan = {
        "page": page,
        "app": app,
        "profile": prof_name,
        "profile_label": prof["label"],
        "weights": prof["weights"],
        "xcheck_available": xcheck_available,
        "xcheck_outage_widens_queue": not xcheck_available,
        "routes": t1 + t2,
        "counts": {
            "T1_after_subtraction": len(t1),
            "T1_subjects": len(t1_raw),
            "T1_resolved_by_xcheck": len(t1_dropped),
            "T2_unconditional": len(t2),
            "forwarded_as_fact": len(forwarded),
            "unroutable": len(unroutable),
            "unroutable_subjects": len(unroutable_raw),
        },
        "resolved_by_xcheck": t1_dropped,
        # Abstentions no layer here can close. They are a COVERAGE HOLE and are
        # reported as one -- not queued, because spending an image on a question
        # with no visual answer is worse than admitting the hole, and not dropped,
        # because a dropped abstention is indistinguishable from a pass.
        "unroutable": unroutable,
        # Forwarded findings are the layer's ANSWERS. They travel to the report as
        # facts and are never re-asked; re-asking a settled question is how a
        # gradient crop gets spent on something the cross-check already closed.
        "forwarded": [
            {
                "rule": f["rule"],
                "target": f["target"],
                "detail": f["detail"],
                "layer": f["layer"],
                "family": f.get("family"),
                "weight": f.get("weight"),
                "surfacing": f.get("surfacing"),
            }
            for f in forwarded
        ],
        "coverage": {
            "dom": "asserted + indeterminate, both accounted",
            "xcheck": "available" if xcheck_available else "ABSENT -- T1 not reduced",
            "vision": f"{images} image(s) budgeted under the {prof_name} profile",
        },
        "image_budget": images,
        "gates_ci": False,
        "gates_ci_because": (
            "Advisory triage only. The June 2026 campaign ratified that taste stays "
            "human and gates adjudicate correctness and coverage only; CI gates on "
            "the deterministic layer, which scored 9/9 with zero control false "
            "positives and needs no API key."
        ),
    }
    return plan


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", default="corpus/out", type=pathlib.Path)
    ap.add_argument("--app", default="default")
    ap.add_argument("--page", help="one page; default every page in the corpus")
    a = ap.parse_args()
    corpus = a.corpus.resolve()

    pages = (
        [a.page]
        if a.page
        else sorted(p.stem for p in (corpus / "snapshots").glob("*.json"))
    )
    plans = {p: route(corpus, p, a.app) for p in pages}
    (corpus / "route_plan.json").write_text(json.dumps(plans, indent=1))

    first = plans[pages[0]]
    print(
        f"profile {first['profile']} ({first['profile_label']})   "
        f"cross-check {'available' if first['xcheck_available'] else 'ABSENT -- T1 widened'}"
    )
    print(
        f"{'page':24} {'T1':>3} {'subj':>5} {'closed':>7} {'T2':>3} {'facts':>6} "
        f"{'hole':>5} {'imgs':>5}"
    )
    for p in pages:
        c = plans[p]["counts"]
        print(
            f"{p:24} {c['T1_after_subtraction']:>3} {c['T1_subjects']:>5} "
            f"{c['T1_resolved_by_xcheck']:>7} {c['T2_unconditional']:>3} "
            f"{c['forwarded_as_fact']:>6} {c['unroutable']:>5} "
            f"{plans[p]['image_budget']:>5}"
        )
    tot = sum(p["counts"]["T1_after_subtraction"] for p in plans.values())
    closed = sum(p["counts"]["T1_resolved_by_xcheck"] for p in plans.values())
    hole = sum(p["counts"]["unroutable_subjects"] for p in plans.values())
    print(
        f"\nT1 across the corpus: {tot} route(s); the cross-check closed {closed} "
        f"abstention(s) at zero model cost."
    )
    if hole:
        seen = {}
        for pl in plans.values():
            for u in pl["unroutable"]:
                seen[u["klass"]] = u
        print(
            f"COVERAGE HOLE: {hole} abstention(s) no layer here closes. Not queued -- "
            f"an eye cannot answer them:"
        )
        for k, u in seen.items():
            print(
                f"  {k}: {u['not_routed_because']}\n    would need: {u['would_need']}"
            )
    print(f"wrote {corpus / 'route_plan.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
