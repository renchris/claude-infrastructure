#!/usr/bin/env python3
"""The abstention router: deterministic pass first, its residue becomes the queue.

This is §8 item 1 of the wave README, and P5-route's decision logic run against the
artifacts the bench actually produces. It reads a captured corpus plus both
detectors' findings and emits a PLAN -- which questions earn a model call, cropped
to the region in question, in what order, inside what budget. It makes no model
call itself, opens no socket and touches no browser.

--------------------------------------------------------------------------------
The governing rule
--------------------------------------------------------------------------------
    If the answer has a number in it, the model does not get the question.

Every deterministic finding is forwarded as a SETTLED FACT, never as a question.
The queue is built only from what the deterministic layers could not decide, and
the abstention -- not the finding -- is what makes that set small enough to afford.

Five things earn a call, and only five (P5-route §2). This implements the three
that a static corpus can produce; T3 (explicit operator request) and T4
(arbitration, which fires only after a judgement exists) are second-order and are
recorded in the plan schema so they cannot be forgotten.

--------------------------------------------------------------------------------
T1 and the subtraction, which is the cheapest win in the stage
--------------------------------------------------------------------------------
    T1 = abstentions raised by any layer
       - abstentions another layer RESOLVED

On the gradient page `detect_dom` abstains -- there is no second operand for a
contrast ratio -- and `detect_xcheck` then answers it outright: 5.89:1 at the left
edge, 1.73:1 at the right, for zero tokens. Routing that abstention anyway would
spend a model call re-asking a question 180 lines of NumPy already closed.

Note the correction to P5-route's shorthand. Its formula subtracts any target
carrying an `xcheck-*` finding, but `xcheck-optical-indeterminate` is ITSELF an
abstention -- under the shorthand an abstention would resolve itself and drop out
of the queue silently. A resolution has to be a CLAIM. That is one predicate,
`verdict.is_abstention`, shared with both detectors and the budget so the three can
never drift apart.

--------------------------------------------------------------------------------
T2, which is the call that must never be cut
--------------------------------------------------------------------------------
One page-level call per page, on the clean shot, asking the six classes no computed
style can answer. Three of the corpus's most valuable findings came from exactly
this call with nobody looking for them. A profile may damp its RANK; nothing may
weight it to zero (`profiles.py` rule 3), because a review without it is a linter
with a screenshot attached.

--------------------------------------------------------------------------------
Cropping: the ceiling nobody configures for
--------------------------------------------------------------------------------
A crop must clear all three of `raster <= 2000px`, `bytes <= 3,932,160`, and
`ceil(w/28) * ceil(h/28) <= 4784` visual tokens. The third binds first on square
crops and is the one that fails silently -- over it the API resizes on top of the
client clamp, so the crop paid for is not the crop the model sees.

So the router picks the LARGEST available device scale whose raster crop still
clears all three, rather than a fixed one. That is §4 lever 3 -- crop and zoom
rather than downscale -- expressed as arithmetic instead of as advice.

Usage: python3 route.py <corpus-dir> [--profile reso-management] [--out route/]
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys

from PIL import Image

import profiles
from verdict import is_abstention

# --- budget (P5-route §3.1) ---------------------------------------------------
CEILING = 12  # image blocks per SESSION; the published cliff is 20 and it REJECTS
PER_PAGE_MAX = 2  # 1 global + 1 region. A page needing three wants better rules.

# --- crop geometry ------------------------------------------------------------
BLEED_PX = 16  # CSS px each side: an alignment claim needs the edge it is off
CLUSTER_GAP_PX = 32  # 4 x the 8px grid unit; below this it is one visual group
MAX_RASTER = 2000  # Claude Code's client clamp
MAX_BYTES = 3_932_160  # over it, PNG is re-encoded palette:true == 256 colours
MAX_VISUAL_TOKENS = 4784  # the high-resolution tier; patches are 28px
PATCH = 28

# --- T2: the six classes no computed style answers (P5-route §2) --------------
UNSCREENABLE = {
    "hierarchy": "which element carries the most visual weight, and is it the one that should",
    "gestalt": "do the groupings a reader perceives match the groupings the markup asserts",
    "content-fit": "does any text promise something the render does not deliver",
    "semantic-coherence": "can a reader tell what every control does without being told",
    "optical-alignment": "does anything read as misaligned despite correct geometry",
    "readability": "is anything geometrically perfect and still hard to read",
}

# --- the NEVER list, as an assertion rather than as advice (P5-route §2) ------
# A question whose answer has a number in it is a ROUTING defect, not a model
# failure, so it is refused here rather than answered badly downstream.
NEVER_ASK = frozenset(
    {
        "spacing-rhythm",
        "grid-violation",
        "type-scale",
        "token-drift",
        "contrast",
        "overflow",
        "touch-target",
        "misalignment",
        "xcheck-contrast-varies",
        "xcheck-zero-ink",
    }
)


# A baseline abstention counts as "the same finding" when its measurement has not
# moved by more than the tolerance that makes the rule fire at all. Anything
# smaller is below the rule's own resolution, so calling it news would spend a
# model call on a number the rule could not have distinguished in the first place.
# Ordinal, like every constant here: it separates a 2.0px shift from a 1.0px one on
# this corpus and is not evidence about where the true boundary lies.
BASELINE_TOL = 1.0


def matches_baseline(f: dict, baseline: dict[tuple[str, str], list[dict]]) -> bool:
    """True when this abstention is already answered by the baseline capture.

    Compares MEASUREMENTS where both sides carry them, and falls back to the
    detail string only where they do not -- a rule that reports no structured
    measurement gets exact-match semantics, which is strict, not lax.
    """
    for b in baseline.get((f["rule"], f["target"]), []):
        m, bm = f.get("measure"), b.get("measure")
        if m and bm and set(m) == set(bm):
            if all(abs(m[k] - bm[k]) <= BASELINE_TOL for k in m):
                return True
        elif not m and not bm and f["detail"] == b["detail"]:
            return True
    return False


def rel(p: pathlib.Path, root: pathlib.Path) -> str:
    """Paths in the plan are relative to the corpus, never absolute.

    A plan is an artifact another session reads, and an absolute path pins it to
    the machine that wrote it -- which is exactly how the March corpus ended up
    describing a route that no longer existed anywhere.
    """
    try:
        return str(p.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(p)


def visual_tokens(w: int, h: int) -> int:
    return math.ceil(w / PATCH) * math.ceil(h / PATCH)


def fits(w_raster: int, h_raster: int, nbytes: int | None = None) -> bool:
    if w_raster > MAX_RASTER or h_raster > MAX_RASTER:
        return False
    if visual_tokens(w_raster, h_raster) > MAX_VISUAL_TOKENS:
        return False
    return not (nbytes is not None and nbytes > MAX_BYTES)


def shots_for(shots: pathlib.Path, stem: str) -> list[tuple[float, pathlib.Path]]:
    """Every captured device scale for one page, largest first.

    capture.py writes `<stem>.png` at dpr 1 and `<stem>@<n>x.png` above it.
    """
    found = [(1.0, shots / f"{stem}.png")] if (shots / f"{stem}.png").exists() else []
    for p in shots.glob(f"{stem}@*x.png"):
        try:
            found.append((float(p.stem.split("@")[-1].rstrip("x")), p))
        except ValueError:
            continue
    return sorted(found, key=lambda t: -t[0])


def cluster(boxes: list[dict], gap: float = CLUSTER_GAP_PX) -> list[list[dict]]:
    """Merge boxes whose gap is under one visual group's width.

    Splitting a group across two crops asks the model to judge grouping with the
    group cut in half, so the merge is deliberately generous.
    """
    out: list[list[dict]] = []
    for b in sorted(boxes, key=lambda r: (r["y"], r["x"])):
        for c in out:
            if any(
                b["x"] - (o["x"] + o["w"]) < gap
                and o["x"] - (b["x"] + b["w"]) < gap
                and b["y"] - (o["y"] + o["h"]) < gap
                and o["y"] - (b["y"] + b["h"]) < gap
                for o in c
            ):
                c.append(b)
                break
        else:
            out.append([b])
    return out


def hull(boxes: list[dict]) -> dict:
    x0 = min(b["x"] for b in boxes)
    y0 = min(b["y"] for b in boxes)
    x1 = max(b["x"] + b["w"] for b in boxes)
    y1 = max(b["y"] + b["h"] for b in boxes)
    return {"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0}


def make_crop(
    page_shots: list[tuple[float, pathlib.Path]],
    box: dict,
    page_css: dict,
    dest: pathlib.Path,
    root: pathlib.Path,
) -> dict | None:
    """Cut the smallest box containing the cluster, plus bleed, at the largest
    device scale that still clears all three ceilings. None when no scale fits."""
    x0 = max(0.0, box["x"] - BLEED_PX)
    y0 = max(0.0, box["y"] - BLEED_PX)
    x1 = min(float(page_css["w"]), box["x"] + box["w"] + BLEED_PX)
    y1 = min(float(page_css["h"]), box["y"] + box["h"] + BLEED_PX)
    for dpr, png in page_shots:
        rx0, ry0 = int(x0 * dpr), int(y0 * dpr)
        rx1, ry1 = int(round(x1 * dpr)), int(round(y1 * dpr))
        w, h = rx1 - rx0, ry1 - ry0
        if w <= 0 or h <= 0 or not fits(w, h):
            continue
        img = Image.open(png).convert("RGB").crop((rx0, ry0, rx1, ry1))
        dest.parent.mkdir(parents=True, exist_ok=True)
        img.save(dest)
        nbytes = dest.stat().st_size
        if nbytes > MAX_BYTES:  # would be re-encoded to 256 colours in flight
            dest.unlink()
            continue
        return {
            "image": rel(dest, root),
            "dpr": dpr,
            "css_box": [
                round(x0, 1),
                round(y0, 1),
                round(x1 - x0, 1),
                round(y1 - y0, 1),
            ],
            "raster": [w, h],
            "visual_tokens": visual_tokens(w, h),
            "bytes": nbytes,
        }
    return None


def plan_page(
    stem: str,
    corpus: pathlib.Path,
    dom: list[dict],
    xchk: list[dict],
    profile_name: str,
    out_dir: pathlib.Path,
    baseline: dict[tuple[str, str], list[dict]] | None = None,
) -> dict:
    snap = json.loads((corpus / "snapshots" / f"{stem}.json").read_text())
    rects = {e["path"]: e["rect"] for e in snap["elements"]}
    page_css = {"w": snap["scroll"]["w"], "h": snap["scroll"]["h"]}
    page_shots = shots_for(corpus / "shots", stem)

    findings = dom + xchk
    raised = [f for f in findings if is_abstention(f)]
    # A resolution must be a CLAIM. An abstention cannot resolve an abstention --
    # see the module docstring; P5-route's shorthand formula lets it, and the
    # consequence is a question that silently leaves the queue.
    resolved_targets = {f["target"] for f in findings if not is_abstention(f)}
    resolved = [f for f in raised if f["target"] in resolved_targets]
    open_ = [f for f in raised if f["target"] not in resolved_targets]

    # --- the third subtraction: an abstention identical to the baseline's ------
    # Measured, and it is the difference between an affordable queue and an
    # unaffordable one. The glyph button appears on every page of this corpus, so
    # X2's abstention fires 13 times for one component: 26 image blocks against a
    # ceiling of 12, i.e. the router demanding a context split to re-ask the same
    # question about the same button thirteen times.
    #
    # An abstention whose measurement matches the baseline EXACTLY is a property of
    # the design, not of the change under review, and it has already been answered
    # once. What is news is an abstention that MOVED. The key spans rule, target
    # AND detail -- the detail carries the number, so 2.9px and 4.3px are different
    # findings about the same element, which is the `assertion-span-must-equal-its-
    # subject` rule this corpus already reproduced once the hard way.
    #
    # On a corpus the baseline is the clean control. In production it is the last
    # reviewed capture of the same page; there is no third kind, and a review with
    # no baseline at all routes everything, which is the correct first run.
    baseline = baseline or {}
    t1 = [f for f in open_ if not matches_baseline(f, baseline)]
    unchanged = [f for f in open_ if matches_baseline(f, baseline)]

    calls: list[dict] = []
    unrouted: list[dict] = []

    # --- T2: one page-level call, on the clean shot, never cut for budget -----
    if page_shots:
        for dpr, png in page_shots:
            with Image.open(png) as im:
                w, h = im.size
            if fits(w, h, png.stat().st_size):
                calls.append(
                    {
                        "id": "C1",
                        "kind": "global",
                        "image": rel(png, corpus),
                        "dpr": dpr,
                        "raster": [w, h],
                        "visual_tokens": visual_tokens(w, h),
                        "asks": sorted(UNSCREENABLE),
                        "from": [],
                        "score": round(
                            max(
                                (
                                    profiles.weight(profile_name, k)
                                    for k in UNSCREENABLE
                                ),
                            ),
                            3,
                        ),
                    }
                )
                break

    # --- T1: cropped region calls for what nothing resolved ------------------
    room = PER_PAGE_MAX - len(calls)
    if t1 and room > 0:
        boxes = []
        for f in t1:
            r = rects.get(f["target"])
            if r:
                boxes.append({**r, "_f": f})
        clusters = cluster(boxes)
        scored = sorted(
            clusters,
            key=lambda c: -sum(profiles.score(profile_name, b["_f"]) for b in c),
        )
        for i, c in enumerate(scored):
            fs = [b["_f"] for b in c]
            asks = sorted({f["rule"] for f in fs})
            bad = [a for a in asks if a in NEVER_ASK]
            if bad:  # a routing defect, surfaced rather than sent
                unrouted.append(
                    {"targets": [f["target"] for f in fs], "why": f"NEVER-list: {bad}"}
                )
                continue
            if len(calls) >= PER_PAGE_MAX:
                unrouted.append(
                    {"targets": [f["target"] for f in fs], "why": "per-page budget"}
                )
                continue
            crop = make_crop(
                page_shots,
                hull(c),
                page_css,
                out_dir / f"clip/{stem}-C{i + 2}.png",
                corpus,
            )
            if crop is None:
                unrouted.append(
                    {"targets": [f["target"] for f in fs], "why": "no lossless crop"}
                )
                continue
            calls.append(
                {
                    "id": f"C{i + 2}",
                    "kind": "region",
                    **crop,
                    "asks": asks,
                    "from": [f["target"] for f in fs],
                    "score": round(sum(profiles.score(profile_name, f) for f in fs), 3),
                }
            )

    settled = [f for f in findings if not is_abstention(f)]
    return {
        "page": stem,
        "calls": calls,
        "unrouted": unrouted,
        "accounting": {
            "settled": len(settled),
            "abstentions_raised": len(raised),
            "abstentions_resolved_free": len(resolved),
            "abstentions_unchanged_vs_baseline": len(unchanged),
            "abstentions_routed": len(t1),
            "resolved_detail": [
                {"target": f["target"], "rule": f["rule"]} for f in resolved
            ],
        },
        "ranked": [
            {k: v for k, v in f.items() if k != "_f"}
            for f in profiles.rank(profile_name, settled)
        ],
    }


def main(
    corpus: pathlib.Path,
    profile_name: str,
    out_dir: pathlib.Path,
    baseline_stem: str | None = None,
) -> int:
    prof = profiles.profile(profile_name)
    dom_all = json.loads((corpus / "findings_dom.json").read_text())
    xchk_all = json.loads((corpus / "findings_xcheck.json").read_text())

    if baseline_stem is None:
        manifest = corpus / "manifest.json"
        if manifest.exists():
            ctrl = json.loads(manifest.read_text()).get("control", "")
            baseline_stem = pathlib.Path(ctrl).stem or None
    baseline: dict[tuple[str, str], list[dict]] = {}
    for f in dom_all.get(baseline_stem or "", []) + xchk_all.get(
        baseline_stem or "", []
    ):
        if is_abstention(f):
            baseline.setdefault((f["rule"], f["target"]), []).append(f)

    out_dir.mkdir(parents=True, exist_ok=True)
    pages = []
    ledger = 0
    for stem in sorted(dom_all):
        if not (corpus / "snapshots" / f"{stem}.json").exists():
            continue
        p = plan_page(
            stem,
            corpus,
            dom_all[stem],
            xchk_all.get(stem, []),
            profile_name,
            out_dir,
            baseline={} if stem == baseline_stem else baseline,
        )
        # The image ledger is cumulative over a SESSION: a conversation re-sends
        # every prior image block on every turn, so a page-by-page budget is not a
        # budget. Over the ceiling the review SPLITS across contexts; it never
        # downgrades an image, because a quantised screenshot produces a review
        # that reads exactly like a good one.
        for c in p["calls"]:
            ledger += 1
            c["ledger_index"] = ledger
            c["needs_fresh_context"] = ledger > CEILING
        pages.append(p)

    plan = {
        "schema": "design-route/1",
        "ok": True,
        "profile": {
            "name": profile_name,
            **{k: prof[k] for k in ("app", "stack", "thesis")},
        },
        "budget": {
            "image_blocks_planned": ledger,
            "ceiling": CEILING,
            "per_page_max": PER_PAGE_MAX,
            "over_ceiling": max(0, ledger - CEILING),
        },
        "pages": pages,
    }
    (out_dir / "route-plan.json").write_text(json.dumps(plan, indent=1))

    tot = {
        k: sum(p["accounting"][k] for p in pages)
        for k in (
            "settled",
            "abstentions_raised",
            "abstentions_resolved_free",
            "abstentions_unchanged_vs_baseline",
            "abstentions_routed",
        )
    }
    print(f"profile {profile_name}  ({prof['app']} — {prof['thesis']})")
    print(
        f"  {len(pages)} page(s): {tot['settled']} settled deterministically, "
        f"{tot['abstentions_raised']} abstention(s) raised"
    )
    print(
        f"  {tot['abstentions_resolved_free']} resolved FREE by the cross-check, "
        f"{tot['abstentions_unchanged_vs_baseline']} unchanged vs baseline "
        f"({baseline_stem}), {tot['abstentions_routed']} routed to the model"
    )
    print(
        f"  {ledger} image block(s) planned against a ceiling of {CEILING}"
        f"{'  <-- SPLIT REQUIRED' if ledger > CEILING else ''}"
    )
    region = [c for p in pages for c in p["calls"] if c["kind"] == "region"]
    for p in pages:
        for c in p["calls"]:
            if c["kind"] == "region":
                print(
                    f"    {p['page']:22} {c['id']} {c['asks']} "
                    f"{c['raster'][0]}x{c['raster'][1]}px @{c['dpr']}x "
                    f"= {c['visual_tokens']} tok"
                )
    if not region:
        print("    (no region calls: every abstention was resolved for free)")
    unrouted = [u for p in pages for u in p["unrouted"]]
    for u in unrouted:
        print(f"    UNROUTED {u['why']}: {u['targets']}")
    print(f"  plan -> {out_dir / 'route-plan.json'}")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", default="corpus/out", type=pathlib.Path)
    ap.add_argument("--profile", default="default", choices=sorted(profiles.PROFILES))
    ap.add_argument("--out", default=None, type=pathlib.Path)
    ap.add_argument(
        "--baseline",
        default=None,
        help="page stem whose abstentions are already answered (default: the "
        "manifest's control). Pass --baseline '' to route every abstention.",
    )
    a = ap.parse_args()
    c = a.corpus.resolve()
    sys.exit(main(c, a.profile, (a.out or c / "route").resolve(), a.baseline))
