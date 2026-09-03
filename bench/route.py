#!/usr/bin/env python3
"""The abstention router: run the cheap layers first, send only the residue on.

The deterministic layer's most valuable output is not a finding, it is an
ABSTENTION. `detect_dom.py` returns `contrast-indeterminate` rather than a pass
wherever a backdrop is a gradient or an image, because every silent pass that
should have been an abstention is a defect shipped. This turns that set into a
work queue, and does three things to it that make the vision spend affordable:

  1. SUBTRACT what the cross-check has since settled. `detect_xcheck.py` answers
     contrast-over-a-gradient with two real numbers and a verdict, no model
     involved. An abstention whose target now carries a cross-check verdict is
     RESOLVED, not queued. On this corpus that empties tier 1 entirely -- the two
     `contrast-indeterminate` findings on the gradient page are both answered by
     `xcheck-contrast-varies` on the same two elements -- which is the whole
     argument for building the comparator before buying any pixels.

  2. CROP, never downscale. ScreenSeekeR moved OS-Atlas-7B from 18.9% to 48.1%
     on ScreenSpot-Pro by cropping instead of resizing, a larger delta than every
     model upgrade in that table combined. Crops here come from
     getBoundingClientRect via the snapshot -- exact, free, and un-hallucinable --
     padded for context and clamped to the frame. The grounder supplies identity;
     the DOM supplies geometry.

  3. RANK by the app's own weighting. `profiles.py` decides what a correct
     finding is worth for THIS application, and the same weights decide how much
     of the queue is worth sending.

The queue has two tiers, and the difference between them is not depth, it is
epistemic status:

  tier 1  ABSTENTION -- a rule ran on this exact element and returned
          INDETERMINATE. Derived, precise, and empty when the cheap layers have
          done their job.
  tier 2  AGENDA -- a standing question this app cares about that the
          deterministic layer cannot answer by construction (hierarchy,
          "does this page make sense", attention). Not derived from any finding,
          so it is a QUESTION and never a claim, and it is exempt from the
          false-positive budget for exactly that reason.

What this does NOT do: call a model. It writes a queue and the crops, and stops.
The June 2026 campaign ratified that taste stays human and the VLM is advisory
triage, never a quality gate; a router that invoked a judge would be reopening a
decision this work is explicitly not reopening.

Usage:
  python3 route.py <corpus-dir> [--profile reso-management-app] [--write-crops]
"""

from __future__ import annotations

import argparse
import json
import pathlib

import detect_dom
import detect_xcheck
import profiles

# Context around a crop. A model asked "is this text legible on its backdrop"
# needs to see the backdrop, and a 0px crop of a text run shows only the run.
CROP_PAD_PX = 24
# Claude's high-resolution tier tops out near 2576px on the long edge. Cropping
# below it is the point; a crop that exceeds it would be silently downscaled by
# the API and would inherit exactly the resolution loss cropping exists to avoid.
MAX_EDGE_PX = 2576


def crop_rect(rect: dict, frame: tuple[int, int], pad: int = CROP_PAD_PX) -> dict:
    """A padded, frame-clamped crop box in CSS px, from the DOM's own geometry."""
    w, h = frame
    x0 = max(0, int(rect["x"] - pad))
    y0 = max(0, int(rect["y"] - pad))
    x1 = min(w, int(rect["right"] + pad))
    y1 = min(h, int(rect["bottom"] + pad))
    return {"x": x0, "y": y0, "w": max(0, x1 - x0), "h": max(0, y1 - y0)}


def route_page(
    name: str, snap: dict, dom: list[dict], xchk: list[dict], profile: dict
) -> dict:
    """Partition one page's findings into reported / resolved / queued."""
    frame = (snap["scroll"]["w"], snap["scroll"]["h"])
    by_path = {e["path"]: e for e in snap["elements"]}

    # Targets the cross-check reached a verdict on. An abstention on one of these
    # has been answered off the pixels already and must not be paid for twice.
    settled = {f["target"] for f in xchk if f["rule"] != "contrast-indeterminate"}

    determined, abstentions, resolved = [], [], []
    for f in profiles.apply(profile, dom + xchk):
        if profiles.RULES.get(f["rule"]) != "abstention":
            determined.append(f)
        elif f["target"] in settled:
            answers = sorted({x["rule"] for x in xchk if x["target"] == f["target"]})
            resolved.append({**f, "settled_by": answers})
        else:
            abstentions.append(f)

    queue = []
    for f in sorted(abstentions, key=lambda f: -f["score"]):
        el = by_path.get(f["target"])
        if el is None:
            continue
        queue.append(
            {
                "tier": 1,
                "kind": "abstention",
                "page": name,
                "target": f["target"],
                "rule": f["rule"],
                "score": f["score"],
                "crop": crop_rect(el["rect"], frame),
                "question": (
                    "A deterministic rule ran here and returned INDETERMINATE: "
                    f"{f['detail']} Judge it off the pixels."
                ),
            }
        )

    for key in profile["agenda"]:
        sel, question = profiles.AGENDA[key]
        hits = [
            e
            for e in snap["elements"]
            if sel in e["classes"] and e["rect"]["w"] > 0 and e["rect"]["h"] > 0
        ]
        for el in hits[:1]:  # one crop per agenda item per page
            queue.append(
                {
                    "tier": 2,
                    "kind": "agenda",
                    "page": name,
                    "target": el["path"],
                    "rule": f"agenda:{key}",
                    "score": 0.0,
                    "crop": crop_rect(el["rect"], frame),
                    "question": question,
                }
            )

    return {
        "frame_w": frame[0],
        "determined": determined,
        "resolved_by_xcheck": resolved,
        "queue": queue,
    }


def write_crops(corpus: pathlib.Path, routed: dict) -> int:
    """Materialise each queued crop as a PNG a session can Read directly.

    A CLI that writes files chooses its own output resolution and therefore stays
    inside the Read ladder by construction. An MCP tool returning image content
    is charged against MAX_MCP_OUTPUT_TOKENS with one session-global lever and no
    per-call escape hatch, which is why this is a CLI.
    """
    from PIL import Image

    outdir = corpus / "crops"
    outdir.mkdir(exist_ok=True)
    n = 0
    for page, part in routed.items():
        png = corpus / "shots" / f"{page}.png"
        if not png.exists() or not part["queue"]:
            continue
        img = Image.open(png)
        # Crops are in CSS px; the shot may be at a device scale. Derive the
        # factor from the artifacts themselves rather than trusting a flag.
        scale = img.width / part["frame_w"]
        for i, q in enumerate(part["queue"]):
            c = q["crop"]
            box = (
                int(c["x"] * scale),
                int(c["y"] * scale),
                int((c["x"] + c["w"]) * scale),
                int((c["y"] + c["h"]) * scale),
            )
            if box[2] - box[0] < 1 or box[3] - box[1] < 1:
                continue
            sub = img.crop(box)
            if max(sub.size) > MAX_EDGE_PX:
                sub.thumbnail((MAX_EDGE_PX, MAX_EDGE_PX))
            path = outdir / f"{page}.{i:02d}.{q['rule'].replace(':', '-')}.png"
            sub.save(path)
            q["crop_png"] = str(path.relative_to(corpus))
            n += 1
    return n


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path, nargs="?", default="corpus/out")
    ap.add_argument("--profile", default="default")
    ap.add_argument("--write-crops", action="store_true")
    a = ap.parse_args()

    corpus = pathlib.Path(a.corpus).resolve()
    profile = profiles.resolve(a.profile)
    tokens = json.loads((corpus / "manifest.json").read_text())["tokens"]

    routed = {}
    for f in sorted((corpus / "snapshots").glob("*.json")):
        png = corpus / "shots" / f"{f.stem}.png"
        if not png.exists():
            continue
        snap = json.loads(f.read_text())
        routed[f.stem] = route_page(
            f.stem,
            snap,
            detect_dom.find(snap, tokens),
            detect_xcheck.check(snap, png),
            profile,
        )

    n_crops = write_crops(corpus, routed) if a.write_crops else 0
    (corpus / f"queue_{a.profile}.json").write_text(
        json.dumps({"profile": a.profile, "pages": routed}, indent=1)
    )

    det = sum(len(p["determined"]) for p in routed.values())
    res = sum(len(p["resolved_by_xcheck"]) for p in routed.values())
    t1 = sum(1 for p in routed.values() for q in p["queue"] if q["tier"] == 1)
    t2 = sum(1 for p in routed.values() for q in p["queue"] if q["tier"] == 2)

    print(f"profile: {a.profile} -- {profile['note']}")
    print(f"  {len(routed)} pages")
    print(f"  {det:3d} determined findings   reported as-is, no model")
    print(f"  {res:3d} abstentions RESOLVED  answered by the cross-check, dequeued")
    print(f"  {t1:3d} tier-1 queue           abstentions still unanswered")
    print(f"  {t2:3d} tier-2 queue           standing agenda questions")
    if n_crops:
        print(f"  {n_crops:3d} crops written to {corpus / 'crops'}")
    print()
    for page, part in sorted(routed.items()):
        if not (part["queue"] or part["resolved_by_xcheck"]):
            continue
        print(page)
        for r in part["resolved_by_xcheck"]:
            print(
                f"    RESOLVED  {r['target'][:52]:52} "
                f"{r['rule']} -> {', '.join(r['settled_by'])}"
            )
        for q in part["queue"]:
            c = q["crop"]
            print(
                f"    QUEUE t{q['tier']}  {q['rule']:22} "
                f"crop {c['w']}x{c['h']} at ({c['x']},{c['y']})  {q['target'][:40]}"
            )


if __name__ == "__main__":
    main()
