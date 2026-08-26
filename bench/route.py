#!/usr/bin/env python3
"""The abstention router: decide what, if anything, earns a model call.

This is the seam the research README names as the whole architecture. The
deterministic layer runs first, and its most valuable output is not a finding --
it is an `INDETERMINATE`. Every silent pass that should have been an abstention
is a defect shipped; every abstention is a question a pixel-reading layer can
answer. So the abstention set IS the vision layer's job queue, and because it is
small, the vision spend is affordable.

Three things happen here and nothing else:

  1. RESOLVE. An abstention that a cross-check arm has already answered never
     reaches the queue. `contrast-indeterminate` says "no single ratio exists
     here"; `xcheck-contrast-varies` answers it with two ratios and a verdict, off
     the pixels, with no model. Measured on this corpus: that empties the crop
     queue completely. `--without-xcheck` re-runs the same routing with the
     cross-check layer withheld, so the value of that layer is a number rather
     than a claim.

  2. COLLAPSE and CROP. What survives is grouped by (class, container) -- two
     abstentions under one gradient are one question, not two -- and cut out of
     the capture as a crop. Cropping rather than downscaling is the single
     largest measured accuracy lever in the whole pipeline (ScreenSeekeR took an
     unchanged model from 18.9% to 48.1% on ScreenSpot-Pro), and it is free.

  3. LABEL. Every request carries its own prohibition, and the plan carries the
     June 2026 ruling as a field rather than as prose: these requests are
     ADVISORY. Nothing here gates anything. Taste stays human; the deterministic
     layer adjudicates correctness and coverage.

The router opens no browser and calls no model. It reads a completed run and
writes `route_plan.json` plus the crops that plan references. What consumes the
plan is out of scope by design -- a queue that builds itself is a queue you can
inspect before you spend anything on it.

Usage: python3 route.py <corpus-dir> [--app <name>] [--without-xcheck] [--no-crops]
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib

from PIL import Image

# Rules whose verdict is "I cannot answer this", not "this is wrong".
ABSTENTIONS = {"contrast-indeterminate"}

# Which cross-check arm settles which abstention. An entry here is a claim that
# the arm answers the SAME question on the SAME subject -- not merely that both
# fired on one element.
RESOLVED_BY = {"contrast-indeterminate": {"xcheck-contrast-varies"}}

# What to ask, per abstention class. Each is a question a person can answer by
# looking, and none of them has a number in the answer.
QUESTIONS = {
    "contrast-indeterminate": (
        "Is this text legible against its backdrop along its whole width? If it "
        "weakens anywhere, say where -- start, middle or end of the run."
    ),
    "_gestalt": (
        "Look at this page as a whole. Name what the eye lands on first, second "
        "and third, and say whether that order matches what the page is for. If "
        "something reads as more important than it is, name it."
    ),
}

# Attached to every request. The judge is forbidden to opine below the perceptual
# threshold: the DOM holds every number exactly and for free, so a model estimate
# can only ever overwrite an exact value with a worse one.
PROHIBITION = (
    "Answer only the question asked. Do not state, estimate or compute any "
    "number -- no pixel distances, sizes, contrast ratios or coordinates. Those "
    "are already known exactly and your estimate would replace a measurement "
    "with a guess. If this image does not let you answer, reply UNANSWERABLE."
)

CROP_PAD_CSS = 24  # context around the subject; a crop with no surround is unreadable
MAX_IMAGE_MP = 3.75  # the high-resolution tier's ceiling; above it the API downscales


def est_image_tokens(w: int, h: int) -> int:
    """Patch-based, per the vendor's own formula -- NOT the (w*h)/750 in our
    older docs, which this research wave corrected."""
    return math.ceil(w / 28) * math.ceil(h / 28)


def load_weights(path: pathlib.Path, app: str) -> dict:
    cfg = json.loads(path.read_text())
    if app not in cfg["apps"]:
        raise SystemExit(
            f"unknown app {app!r}; weights.json defines {sorted(cfg['apps'])}"
        )
    prof = cfg["apps"][app]
    fam_of = {r: fam for fam, rules in cfg["families"].items() for r in rules}
    floors = cfg["never_below_1"]
    weights = {}
    for fam in cfg["families"]:
        w = float(prof["families"].get(fam, 1.0))
        # A taste profile may never de-prioritise a correctness or accessibility
        # failure. Marketing aesthetics is a reason to care MORE about hierarchy,
        # never a reason to care less about a 2.5:1 contrast ratio.
        weights[fam] = max(w, 1.0) if fam in floors else w
    return {
        "app": app,
        "rationale": prof["rationale"],
        "gestalt": prof["gestalt"],
        "family_of": fam_of,
        "family_weight": weights,
        "clamped": sorted(
            f for f in floors if float(prof["families"].get(f, 1.0)) < 1.0
        ),
    }


def best_shot(shots: pathlib.Path, page: str) -> tuple[pathlib.Path, float] | None:
    """The largest capture that still fits under the no-downscale ceiling.

    Sending a smaller image than the tier accepts inherits the old score whatever
    model is bought; sending a larger one gets silently resized, which destroys
    the evidence without saying so.
    """
    best = None
    for f in sorted(shots.glob(f"{page}.png")) + sorted(shots.glob(f"{page}@*.png")):
        with Image.open(f) as im:
            w, h = im.size
        if w * h / 1e6 > MAX_IMAGE_MP:
            continue
        if best is None or w * h > best[1] * best[2]:
            best = (f, w, h)
    if best is None:
        return None
    return best[0], best[1]


def container_of(path: str) -> str:
    head = path.rsplit(" > ", 1)
    return head[0] if len(head) > 1 else path


def slug(s: str) -> str:
    keep = "".join(c if c.isalnum() else "-" for c in s)
    return "-".join(p for p in keep.split("-") if p)[-48:]


def union_rect(rects: list[dict]) -> dict:
    return {
        "x": min(r["x"] for r in rects),
        "y": min(r["y"] for r in rects),
        "right": max(r["right"] for r in rects),
        "bottom": max(r["bottom"] for r in rects),
    }


def build(corpus: pathlib.Path, prof: dict, use_xcheck: bool, cut_crops: bool) -> dict:
    dom = json.loads((corpus / "findings_dom.json").read_text())
    xpath = corpus / "findings_xcheck.json"
    xchk = json.loads(xpath.read_text()) if (use_xcheck and xpath.exists()) else {}
    snaps = corpus / "snapshots"
    shots = corpus / "shots"
    crops = corpus / "crops"
    if cut_crops:
        crops.mkdir(exist_ok=True)

    control = "clean"
    control_findings = dom.get(control, []) + xchk.get(control, [])

    queue, resolved, pages = [], [], []
    for page in sorted(dom):
        snap_file = snaps / f"{page}.json"
        if not snap_file.exists():
            continue
        snap = json.loads(snap_file.read_text())
        rect_of = {e["path"]: e["rect"] for e in snap["elements"]}
        settled = {
            (f["rule"], f["target"])
            for f in xchk.get(page, [])
            for cls, arms in RESOLVED_BY.items()
            if f["rule"] in arms
        }
        settled_targets = {t for _, t in settled}

        # --- 1. resolve, then 2. collapse ---------------------------------
        groups: dict[tuple[str, str], list[dict]] = {}
        for f in dom.get(page, []):
            if f["rule"] not in ABSTENTIONS:
                continue
            if f["target"] in settled_targets:
                resolved.append(
                    {
                        "page": page,
                        "class": f["rule"],
                        "target": f["target"],
                        "settled_by": sorted(r for r, t in settled if t == f["target"]),
                    }
                )
                continue
            groups.setdefault((f["rule"], container_of(f["target"])), []).append(f)

        for (cls, cont), fs in sorted(groups.items()):
            rects = [rect_of[f["target"]] for f in fs if f["target"] in rect_of]
            if not rects:
                continue
            u = union_rect(rects)
            fam = prof["family_of"].get(cls, "A")
            item = {
                "id": f"q{len(queue) + 1:02d}",
                "page": page,
                "kind": "crop",
                "class": cls,
                "family": fam,
                "weight": round(prof["family_weight"].get(fam, 1.0), 2),
                "container": cont,
                "targets": [f["target"] for f in fs],
                "collapsed_from": len(fs),
                "rect_css": u,
                "question": QUESTIONS.get(cls, QUESTIONS["_gestalt"]),
                "prohibition": PROHIBITION,
                "role": "advisory",
            }
            shot = best_shot(shots, page)
            if shot and cut_crops:
                path, sw = shot
                with Image.open(path) as im:
                    scale = im.size[0] / snap["scroll"]["w"]
                    box = (
                        max(0, int((u["x"] - CROP_PAD_CSS) * scale)),
                        max(0, int((u["y"] - CROP_PAD_CSS) * scale)),
                        min(im.size[0], int((u["right"] + CROP_PAD_CSS) * scale)),
                        min(im.size[1], int((u["bottom"] + CROP_PAD_CSS) * scale)),
                    )
                    out = crops / f"{page}__{slug(cls + '-' + cont)}.png"
                    im.crop(box).save(out)
                    cw, ch = box[2] - box[0], box[3] - box[1]
                item["image"] = str(out.relative_to(corpus))
                item["image_px"] = [cw, ch]
                item["est_image_tokens"] = est_image_tokens(cw, ch)
                item["cut_from"] = path.name
            queue.append(item)

        # --- 3. the residue: one blind look per page ----------------------
        if prof["gestalt"]["enabled"]:
            shot = best_shot(shots, page)
            g = {
                "id": f"g{len(pages) + 1:02d}",
                "page": page,
                "kind": "gestalt",
                "class": "_gestalt",
                "family": "V",
                "weight": round(prof["family_weight"].get("V", 1.0), 2),
                "question": QUESTIONS["_gestalt"],
                "prohibition": PROHIBITION,
                "role": "advisory",
                "blind": True,
            }
            if shot:
                path, _ = shot
                with Image.open(path) as im:
                    w, h = im.size
                g["image"] = str(path.relative_to(corpus))
                g["image_px"] = [w, h]
                g["est_image_tokens"] = est_image_tokens(w, h)
            pages.append(g)

    queue.sort(key=lambda q: (-q["weight"], q["page"], q["id"]))
    return {
        "app": prof["app"],
        "rationale": prof["rationale"],
        "family_weight": prof["family_weight"],
        "weight_floors_applied_to": prof["clamped"],
        # The June 2026 ruling, as a field. A future edit that wires any of this
        # into a gate has to delete this line, which is a reviewable diff rather
        # than a drift.
        "role": "advisory",
        "never_gates": True,
        "control_clean": not control_findings,
        "control_findings": control_findings,
        "xcheck_layer": "on" if use_xcheck else "WITHHELD",
        "counts": {
            "crop_requests": len(queue),
            "abstentions_resolved_without_a_model": len(resolved),
            "gestalt_requests": len(pages),
            "est_image_tokens": sum(
                i.get("est_image_tokens", 0) for i in queue + pages
            ),
        },
        "resolved": resolved,
        "queue": queue + pages,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path, nargs="?", default="corpus/out")
    ap.add_argument("--app", default="bench-corpus")
    ap.add_argument("--weights", type=pathlib.Path, default=None)
    ap.add_argument(
        "--without-xcheck",
        action="store_true",
        help="route as if the cross-check layer did not exist, to price it",
    )
    ap.add_argument("--no-crops", action="store_true")
    ap.add_argument("--out", default="route_plan.json")
    a = ap.parse_args()

    corpus = pathlib.Path(a.corpus).resolve()
    wpath = a.weights or pathlib.Path(__file__).parent / "weights.json"
    prof = load_weights(wpath, a.app)

    plan = build(corpus, prof, not a.without_xcheck, not a.no_crops)
    (corpus / a.out).write_text(json.dumps(plan, indent=1))

    c = plan["counts"]
    print(f"app {plan['app']}  ({plan['rationale']})")
    print(f"  weights {plan['family_weight']}  xcheck {plan['xcheck_layer']}")
    if plan["weight_floors_applied_to"]:
        print(
            f"  !! profile declares {plan['weight_floors_applied_to']} below 1.0 and "
            f"was CLAMPED. Accessibility and correctness are floored; fix weights.json."
        )
    if not plan["control_clean"]:
        print(
            f"  !! CONTROL IS DIRTY: {len(plan['control_findings'])} finding(s) on "
            f"clean.html. Every count below is worthless until that is 0."
        )
    print(
        f"  {c['abstentions_resolved_without_a_model']} abstention(s) settled by the "
        f"cross-check, with no model call"
    )
    print(
        f"  {c['crop_requests']} crop request(s) + {c['gestalt_requests']} blind "
        f"gestalt request(s) = ~{c['est_image_tokens']} image tokens"
    )
    for q in plan["queue"][:8]:
        img = q.get("image_px", ["?", "?"])
        print(
            f"    [{q['weight']:.2f}] {q['id']} {q['kind']:7} {q['page']:22} "
            f"{q['class']:24} {img[0]}x{img[1]}"
        )
    if len(plan["queue"]) > 8:
        print(f"    ... {len(plan['queue']) - 8} more in {a.out}")


if __name__ == "__main__":
    main()
