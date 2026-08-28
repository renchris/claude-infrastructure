#!/usr/bin/env python3
"""ROUTE: decide what reaches a frontier model, in what form, with what context.

The deterministic layer's most valuable output is not a finding, it is an
ABSTENTION. `detect_dom` returns `contrast-indeterminate` rather than a pass
wherever no second operand for a contrast ratio exists, and every silent pass
that should have been an abstention is a defect shipped. This stage turns that
abstention set into the vision layer's job queue -- cropped to the region in
question, so the model is asked a small question about a large image rather than
a large question about a small one.

Two properties make the queue affordable, and both are load-bearing:

**The cross-check subtracts from it before it is priced.** An abstention that
`detect_xcheck` closed is not routed. On the corpus's gradient page the
comparator turned "unrepresentable" into `6.15:1 at the left edge and 1.73:1 at
the right` -- a full verdict, for no model call at all. Routing it anyway would
spend ~1,600 visual tokens re-asking a question 200 lines of NumPy already
answered. This is the single most likely way the stage rots, because every new
rule adds new abstentions and nobody re-runs the subtraction by hand. So the
subtraction is code, not discipline.

**The queue is not the only call.** One page-level call is unconditional and must
never be cut for budget: the classes for which no computed style is the answer --
hierarchy, gestalt, content-fit, semantic-coherence, optical-alignment,
readability. Three of the corpus's most valuable findings came from exactly this
call, on a clean image, with nobody looking for them. Cut it and the reviewer is
a linter with a screenshot.

What this stage never does, and the reason is one line: **if the answer has a
number in it, the model does not get the question.** Distances, gaps, ratios,
token membership, animation timing and above all bounding boxes are settled by
the DOM, exactly and for free. It also never asks for a score, a grade or a
ranking -- ratified June 2026, taste stays human, and this stage produces
advisory triage, never a gate.

Crops are CUT from the screenshot the snapshot describes, never re-rendered. Two
images from two browser passes cannot be argued against each other.

Usage:  python3 route.py <corpus-dir> [--profile NAME] [--ceiling N]
Writes: <corpus-dir>/route-plan.json, <corpus-dir>/clip/*.png, <corpus-dir>/route-steps.sh
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

from PIL import Image

import profiles

# --- the constants, each with the failure it prevents ------------------------
# Claude Code's client clamp. Over it the PNG is re-encoded with palette:true,
# i.e. quantised to <=256 colours, which destroys exactly the gradient evidence a
# contrast call exists to read -- silently, with no error to the session.
CLAMP_PX, CLAMP_BYTES = 2000, 3_932_160
# Opus 5's high-resolution tier: ceil(w/28) * ceil(h/28) <= 4784 patches. This is
# the ceiling nobody configures for and it binds BEFORE the client clamp on
# square crops: 1000x1000 CSS @2 is 5,184 tokens, over the tier, so the API
# resizes on top of the clamp and the crop you paid for is not the one the model
# sees. Solving ceil(n/28)^2 <= 4784 gives n <= 1932 raster px.
PATCH, PATCH_BUDGET = 28, 4784
# Two findings closer than 32 CSS px are almost always inside one visual group,
# and splitting a group across two crops asks the model to judge grouping with
# the group cut in half. 32 == 4 x the 8px grid unit.
CLUSTER_GAP = 32.0
# Enough to include the boundary the finding is ABOUT -- an alignment claim needs
# the edge it is misaligned from -- without importing a neighbouring group.
BLEED = 16.0
# Image blocks per SESSION, not per request: the cliff is cumulative across
# conversation history and fails by rejection. 40% headroom under the observed
# cliff at 20 leaves room for the agent's own screenshots.
CEILING = 12


def visual_tokens(w: int, h: int) -> int:
    return -(-w // PATCH) * -(-h // PATCH)


def admissible(w: int, h: int, nbytes: int) -> str | None:
    """None when the crop survives all three ceilings, else which one it broke."""
    if w > CLAMP_PX or h > CLAMP_PX:
        return f"client clamp: {w}x{h} raster exceeds {CLAMP_PX}px"
    if visual_tokens(w, h) > PATCH_BUDGET:
        return (
            f"visual-token tier: {visual_tokens(w, h)} patches exceeds {PATCH_BUDGET}"
        )
    if nbytes > CLAMP_BYTES:
        return f"palette quantisation: {nbytes} bytes exceeds {CLAMP_BYTES}"
    return None


# --- T1: the abstention residue ----------------------------------------------
def is_abstention(f: dict) -> bool:
    return f["rule"].endswith("-indeterminate")


def t1_residue(dom: list[dict], xcheck: list[dict]) -> tuple[list[dict], list[dict]]:
    """Abstentions from EITHER layer, minus the ones a VERDICT closed.

    T1 = {f in dom + xcheck : f is an abstention}
       - {f : exists a non-abstaining xcheck finding on f.target}

    The `is_abstention` guard on the subtrahend is the whole correctness of this
    function, and leaving it out is the failure P5 predicts by name: new rules add
    new abstentions, and a subtraction keyed on "any cross-check finding exists
    here" would read the cross-check's OWN abstention as having closed the DOM's.
    The queue would then shrink exactly when a second layer said it could not
    answer either -- a silent pass built out of two honest refusals.
    """
    closed = {
        x["target"]
        for x in xcheck
        if x["rule"].startswith("xcheck-") and not is_abstention(x)
    }
    abstentions = [f for f in dom + xcheck if is_abstention(f)]
    routed, settled = [], []
    seen: set[tuple[str, str]] = set()
    for f in abstentions:
        if f["target"] in closed:
            settled.append(f)
            continue
        # Both layers abstaining about the same element is one question, not two.
        key = (f["target"], f["rule"].split("-")[-1])
        if key in seen:
            continue
        seen.add(key)
        routed.append(f)
    return routed, settled


# --- clustering ---------------------------------------------------------------
def rect_of(target: str, by_path: dict) -> dict | None:
    el = by_path.get(target)
    return el["rect"] if el else None


def merge_within(boxes: list[dict], gap: float) -> list[dict]:
    """Union boxes whose padded extents touch. Order-independent by construction."""
    clusters: list[dict] = []
    for b in boxes:
        cur = dict(b)
        merged = True
        while merged:
            merged = False
            for c in list(clusters):
                if (
                    cur["x"] - gap < c["right"]
                    and c["x"] - gap < cur["right"]
                    and cur["y"] - gap < c["bottom"]
                    and c["y"] - gap < cur["bottom"]
                ):
                    clusters.remove(c)
                    cur = {
                        "x": min(cur["x"], c["x"]),
                        "y": min(cur["y"], c["y"]),
                        "right": max(cur["right"], c["right"]),
                        "bottom": max(cur["bottom"], c["bottom"]),
                        "findings": cur["findings"] + c["findings"],
                    }
                    merged = True
                    break
        clusters.append(cur)
    return clusters


def plan_page(
    page: str,
    snap: dict,
    dom: list[dict],
    xcheck: list[dict],
    shot: pathlib.Path,
    prof: profiles.Profile,
    clip_dir: pathlib.Path,
    granted: int,
) -> dict:
    by_path = {e["path"]: e for e in snap["elements"]}
    img = Image.open(shot)
    scale = img.size[0] / snap["scroll"]["w"]

    routed, settled = t1_residue(dom, xcheck)
    # A profile that down-weighted a rule to zero has said it does not want that
    # axis reviewed. Paying 1,600 visual tokens for its abstention would spend the
    # budget on precisely the axis the profile just declined.
    suppressed = [f for f in routed if not prof.keeps(f)]
    routed = [f for f in routed if prof.keeps(f)]

    calls: list[dict] = []
    unrouted: list[dict] = []

    # T2 -- one page-level call, unconditional, never cut for budget.
    gw, gh = img.size
    why = admissible(gw, gh, shot.stat().st_size)
    calls.append(
        {
            "id": "C1",
            "kind": "global",
            "image": shot.name,
            "raster": [gw, gh],
            "visual_tokens": visual_tokens(gw, gh),
            "asks": list(prof.t2_classes),
            **({"clamp_warning": why} if why else {}),
        }
    )

    # T1 -- region calls over the residue the cross-check could not close.
    boxes = []
    for f in routed:
        r = rect_of(f["target"], by_path)
        if r is None:
            unrouted.append(
                {"id": f["target"], "why": "no box in snapshot", "class": f["rule"]}
            )
            continue
        boxes.append(
            {**{k: r[k] for k in ("x", "y", "right", "bottom")}, "findings": [f]}
        )

    clusters = merge_within(boxes, CLUSTER_GAP)
    clusters.sort(key=lambda c: sum(prof.score(f) for f in c["findings"]), reverse=True)

    room = min(prof.per_page_max, max(0, granted - 1))
    for i, c in enumerate(clusters):
        fs = c["findings"]
        if len(calls) - 1 >= room:
            unrouted.extend(
                {"id": f["target"], "why": "budget", "class": f["rule"]} for f in fs
            )
            continue
        x0 = max(0.0, c["x"] - BLEED)
        y0 = max(0.0, c["y"] - BLEED)
        x1 = min(float(snap["scroll"]["w"]), c["right"] + BLEED)
        y1 = min(float(snap["scroll"]["h"]), c["bottom"] + BLEED)
        box = (
            int(round(x0 * scale)),
            int(round(y0 * scale)),
            int(round(x1 * scale)),
            int(round(y1 * scale)),
        )
        cw, ch = box[2] - box[0], box[3] - box[1]
        cid = f"C{len(calls) + 1}"
        out = clip_dir / f"{page}-{cid}@{cw}x{ch}.png"
        img.crop(box).save(out)
        why = admissible(cw, ch, out.stat().st_size)
        if why:
            # Exit 5's condition. Folding into the global call is honest: the
            # question still gets asked, at lower resolution, and the plan says so.
            out.unlink()
            calls[0].setdefault("folded", []).append(
                {"css_box": [x0, y0, x1 - x0, y1 - y0], "why": why}
            )
            unrouted.extend(
                {"id": f["target"], "why": f"not lossless: {why}", "class": f["rule"]}
                for f in fs
            )
            continue
        calls.append(
            {
                "id": cid,
                "kind": "region",
                "image": f"clip/{out.name}",
                "raster": [cw, ch],
                "visual_tokens": visual_tokens(cw, ch),
                "css_box": [
                    round(x0, 1),
                    round(y0, 1),
                    round(x1 - x0, 1),
                    round(y1 - y0, 1),
                ],
                "from": [f["target"] for f in fs],
                "asks": sorted({f["rule"] for f in fs}),
            }
        )

    # The settled findings, in the order this app wants to read them. This is the
    # other half of what a profile is for: routing decides what a model is asked,
    # weighting decides what a person is shown first, and on a purchased template
    # the second matters more because the conformance findings are the ones that
    # arrive by the hundred and bury the correctness findings underneath them.
    verdicts = [f for f in dom + xcheck if not is_abstention(f)]
    kept = sorted((f for f in verdicts if prof.keeps(f)), key=prof.score, reverse=True)
    dropped: dict[str, int] = {}
    for f in verdicts:
        if not prof.keeps(f):
            dropped[f["rule"]] = dropped.get(f["rule"], 0) + 1

    coverage_dom = "complete" if prof.token_source else "partial-no-token-source"
    return {
        "schema": "design-route/1",
        "ok": True,
        "page": page,
        "profile": prof.name,
        "budget": {
            "image_blocks_granted": granted,
            "image_blocks_used": len(calls),
            "ceiling": CEILING,
            "per_page_max": prof.per_page_max,
        },
        "settled": {
            "deterministic": len(verdicts),
            "abstentions_closed_by_xcheck": [f["target"] for f in settled],
            "abstentions_suppressed_by_profile": [f["target"] for f in suppressed],
        },
        "report": [{**f, "score": round(prof.score(f), 2)} for f in kept],
        # Never a silent filter: a profile that hid its own activity would be
        # indistinguishable from a detector that found nothing.
        "suppressed_by_profile": dropped,
        "calls": calls,
        "unrouted": unrouted,
        "coverage": {"dom": coverage_dom, "pixel": "complete", "judgement": "planned"},
    }


ASK_TEMPLATE = {
    "hierarchy": "Which element does your eye land on first, and is that the one the page wants you to act on?",
    "gestalt": "Is anything grouped with the wrong neighbours, or left orphaned from the group it belongs to?",
    "content-fit": "Does any label, caption or heading promise something the rendering does not deliver?",
    "semantic-coherence": "Is there a control whose purpose a first-time user could not name?",
    "optical-alignment": "Does anything read as misaligned even though it would measure correct?",
    "readability": "Is anything harder to read than it needs to be -- scanning, alignment of numerals, line length?",
    "contrast-indeterminate": "The backdrop here is a gradient or image, so no single contrast ratio exists. Where the text sits, is it legible?",
}


def steps_for(plans: dict, corpus: pathlib.Path) -> str:
    """The ordered tool calls an agent runs verbatim.

    Ordering is this stage's main lever, and in a Claude Code session ordering is
    tool-call order: the agent cannot build a message array, so an image only ever
    arrives as a tool_result AFTER the instruction that caused it. Region crops
    come before the page shot so the specific question is not answered from a
    memory of the whole frame.
    """
    lines = [
        "#!/bin/sh",
        "# Generated by route.py. Each Read is one image block against the session",
        "# ceiling; the questions are advisory triage, never a gate.",
        "",
    ]
    for page, plan in sorted(plans.items()):
        if len(plan["calls"]) == 1 and not plan["calls"][0].get("folded"):
            continue
        lines.append(f"# ---- {page} ({plan['profile']}) ----")
        for call in sorted(plan["calls"], key=lambda c: c["kind"] != "region"):
            asks = "; ".join(ASK_TEMPLATE.get(a, a) for a in call["asks"])
            lines.append(
                f"# {call['id']} {call['kind']} {call['visual_tokens']} tok: {asks}"
            )
            lines.append(f"# Read {corpus / call['image']}")
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "corpus", type=pathlib.Path, nargs="?", default=pathlib.Path("corpus/out")
    )
    ap.add_argument("--profile", default=profiles.DEFAULT)
    ap.add_argument("--ceiling", type=int, default=CEILING)
    a = ap.parse_args()

    corpus = a.corpus.resolve()
    prof = profiles.get(a.profile)
    bad = profiles.validate()
    if bad:
        for b in bad:
            print(f"INVALID  {b}", file=sys.stderr)
        raise SystemExit(2)

    dom_all = json.loads((corpus / "findings_dom.json").read_text())
    xchk_all = json.loads((corpus / "findings_xcheck.json").read_text())
    clip = corpus / "clip"
    clip.mkdir(exist_ok=True)
    for old in clip.glob("*.png"):
        old.unlink()

    plans: dict[str, dict] = {}
    budget_left = a.ceiling
    for snap_file in sorted((corpus / "snapshots").glob("*.json")):
        page = snap_file.stem
        shot = corpus / "shots" / f"{page}.png"
        if not shot.exists():
            continue
        plan = plan_page(
            page,
            json.loads(snap_file.read_text()),
            dom_all.get(page, []),
            xchk_all.get(page, []),
            shot,
            prof,
            clip,
            budget_left,
        )
        plans[page] = plan

    (corpus / "route-plan.json").write_text(json.dumps(plans, indent=1))
    steps = corpus / "route-steps.sh"
    steps.write_text(steps_for(plans, corpus))
    steps.chmod(0o755)

    n_region = sum(
        1 for p in plans.values() for c in p["calls"] if c["kind"] == "region"
    )
    closed = sum(
        len(p["settled"]["abstentions_closed_by_xcheck"]) for p in plans.values()
    )
    reported = sum(len(p["report"]) for p in plans.values())
    dropped: dict[str, int] = {}
    for p in plans.values():
        for rule, n in p["suppressed_by_profile"].items():
            dropped[rule] = dropped.get(rule, 0) + n
    print(f"profile {prof.name}  ({prof.stack})")
    print(f"  asks per page   {', '.join(prof.t2_classes)}")
    print(
        f"  {len(plans)} pages -> {len(plans)} global call(s) + {n_region} region call(s)"
    )
    print(f"  abstentions closed by the cross-check, never routed: {closed}")
    print(
        f"  findings reported: {reported}"
        + (f"; suppressed by profile: {dropped}" if dropped else "")
    )
    print()
    for page, p in sorted(plans.items()):
        regions = [c for c in p["calls"] if c["kind"] == "region"]
        note = ""
        if p["settled"]["abstentions_closed_by_xcheck"]:
            note = f"  ({len(p['settled']['abstentions_closed_by_xcheck'])} abstention(s) settled free)"
        sup = p["settled"]["abstentions_suppressed_by_profile"]
        if sup:
            note += f"  ({len(sup)} suppressed by profile)"
        print(f"  {page:24} {len(regions)} region call(s){note}")
        for c in regions:
            print(
                f"      {c['id']} {c['raster'][0]}x{c['raster'][1]} raster, "
                f"{c['visual_tokens']} tok, asks {c['asks']}"
            )
        if p["unrouted"]:
            for u in p["unrouted"]:
                print(f"      UNROUTED {u['class']} on {u['id'][:50]}: {u['why']}")


if __name__ == "__main__":
    main()
