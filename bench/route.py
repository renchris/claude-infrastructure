#!/usr/bin/env python3
"""The abstention router: deterministic first, and its abstentions are the queue.

The deterministic layer's most valuable output is not a finding, it is an
ABSTENTION. `contrast-indeterminate: cannot compute a ratio, the backdrop is a
gradient` is worth more than a pass, because every silent pass that should have
been an abstention is a defect shipped. This routes on exactly that: the
deterministic pass runs first, everything it can decide it decides, and what is
left -- its INDETERMINATE set, plus the class of question no rule reaches at all
-- becomes a queue, cropped to the region in question.

Three properties are the whole design.

**The cross-check discharges before the queue is built.** `detect_xcheck`'s X3
arm answers contrast-over-a-gradient with two numbers off the pixels, so that
abstention is resolved without a model and never reaches the queue. A router that
forwarded every abstention would send the vision layer the one question we had
already answered for free.

**The queue is cropped and zoomed, never downscaled.** Cropping to the region and
enlarging it took an open grounding model from 18.9% to 48.1% on ScreenSpot-Pro
with no model change -- a larger delta than every model upgrade in that study
combined. Downscaling a full page to fit a token budget throws away the evidence
and inherits a worse score whatever model reads it.

**Every entry carries the DOM's numbers and forbids the reader from producing
their own.** The grounder supplies identity; the DOM supplies geometry. A
model-drawn box is an estimate of something `getBoundingClientRect` returns
exactly, for free, with no hallucination risk.

🚨 THIS CALLS NO MODEL, AND THAT IS DELIBERATE. It prepares a queue and stops.
The June 2026 campaign ratified that taste stays human and that gates adjudicate
correctness and coverage only, so what consumes this queue is a person, or an
agent reading a crop advisorily -- never an automatic quality gate, and never a
local VLM.

Usage: python3 route.py <corpus-dir> [--profile reso-management] [--no-x2]
"""

from __future__ import annotations

import argparse
import json
import pathlib

from PIL import Image

import detect_dom
import detect_xcheck
import profiles

# An abstention is discharged when another detector answers the same question
# about the same target. Keyed by the rule that supplies the answer.
DISCHARGES: dict[str, set[str]] = {
    "xcheck-contrast-varies": {"contrast-indeterminate"},
}

# Two abstentions about the same question on the same target are one queue entry,
# not two. The cross-check's version carries measured evidence -- the swing, the
# sample count, the reason no summary exists -- so it replaces the cascade's
# bare "cannot compute a ratio" rather than sitting beside it.
SUPERSEDES: dict[str, set[str]] = {
    "xcheck-backdrop-indeterminate": {"contrast-indeterminate"},
}

# Rules whose verdict is "I cannot decide this". Named by suffix so a new
# abstaining rule routes correctly without being listed here -- the alternative
# is a rule that abstains silently, which is the failure this file exists to stop.
ABSTAIN_SUFFIX = "-indeterminate"

# Crop policy. Claude's high-resolution tier accepts ~2576px on the long edge and
# caps at ~3.75 MP; a crop is enlarged toward that ceiling rather than a page
# being shrunk to fit it.
CROP_LONG_EDGE = 2000
CROP_MAX_MP = 3.75e6
CROP_MAX_ZOOM = 4.0
CROP_PAD_MIN = 24.0  # CSS px of context around the region
CROP_PAD_FRAC = 0.35

# What the reader is being asked, per abstaining rule. A queue entry with no
# question is a screenshot, and a screenshot is not a task.
QUESTIONS = {
    "contrast-indeterminate": (
        "Read the text in the marked region against what is actually behind it. "
        "The backdrop is a gradient or an image, so no single computed ratio "
        "exists. Say whether the text stays legible across its whole run, and "
        "where it stops being legible if it does."
    ),
    "xcheck-backdrop-indeterminate": (
        "Read the text in the marked region against what is actually behind it. "
        "The backdrop is patterned, so the contrast under this text alternates "
        "rather than ramping and no pair of numbers summarises it. Say whether a "
        "reader can read the whole string, and which part of it disappears."
    ),
    "_judgement": (
        "Look at this page as a first-time reader would in the first second. "
        "Does the element that is meant to be primary read as primary? Is "
        "anything visually heavier than its importance? Does the page make "
        "sense? These are judgements, not measurements -- do not report a "
        "number, and do not report anything a rule could have caught."
    ),
}

FORBID = (
    "Do not measure. Every distance, size and colour on this page is already "
    "known exactly and is given in dom_facts; a coordinate you estimate from "
    "this image is a guess competing with a fact."
)


def is_abstention(rule: str) -> bool:
    return rule.endswith(ABSTAIN_SUFFIX)


def dom_facts(el: dict | None) -> dict:
    """The numbers the reader must be given rather than allowed to estimate."""
    if not el:
        return {}
    s = el["styles"]
    return {
        "rect_css_px": el["rect"],
        "color": s.get("color"),
        "font_size": s.get("font-size"),
        "font_weight": s.get("font-weight"),
        "background_color": s.get("background-color"),
        "background_image": s.get("background-image"),
        "text": el["text"][:80],
    }


def make_crop(img: Image.Image, rect: dict | None, scale: float, dest: pathlib.Path):
    """Crop to the region with context, then ENLARGE toward the high-res tier."""
    if rect is None:
        box = (0, 0, img.width, img.height)
    else:
        pad_x = max(CROP_PAD_MIN, rect["w"] * CROP_PAD_FRAC) * scale
        pad_y = max(CROP_PAD_MIN, rect["h"] * CROP_PAD_FRAC) * scale
        box = (
            max(0, int(rect["x"] * scale - pad_x)),
            max(0, int(rect["y"] * scale - pad_y)),
            min(img.width, int(rect["right"] * scale + pad_x)),
            min(img.height, int(rect["bottom"] * scale + pad_y)),
        )
    region = img.crop(box)
    w, h = region.size
    if w < 1 or h < 1:
        return None, 1.0
    zoom = min(
        CROP_LONG_EDGE / max(w, h), CROP_MAX_ZOOM, (CROP_MAX_MP / (w * h)) ** 0.5
    )
    if zoom > 1.0:
        # LANCZOS on a rendered edge: a UI edge is a true step function, so
        # enlarging it recovers shape rather than inventing it.
        region = region.resize((int(w * zoom), int(h * zoom)), Image.Resampling.LANCZOS)
    else:
        zoom = 1.0
    dest.parent.mkdir(parents=True, exist_ok=True)
    region.save(dest)
    return dest, round(zoom, 2)


def route_page(
    name: str,
    snap: dict,
    png: pathlib.Path,
    tokens: dict,
    prof: profiles.Profile,
    outdir: pathlib.Path,
) -> dict:
    findings = detect_dom.find(snap, tokens) + detect_xcheck.check(snap, png)
    findings = prof.rank(findings)

    def _pairs(table):
        return {
            (weaker, f["target"]): f["rule"]
            for f in findings
            if f["rule"] in table
            for weaker in table[f["rule"]]
        }

    discharged_by = _pairs(DISCHARGES)
    superseded_by = _pairs(SUPERSEDES)

    decided, abstentions, discharged = [], [], []
    for f in findings:
        key = (f["rule"], f["target"])
        if not is_abstention(f["rule"]):
            decided.append(f)
        elif key in discharged_by:
            f["discharged_by"] = discharged_by[key]
            discharged.append(f)
        elif key in superseded_by:
            f["superseded_by"] = superseded_by[key]
        else:
            abstentions.append(f)

    by_path = {e["path"]: e for e in snap["elements"]}
    img = Image.open(png).convert("RGB")
    scale = img.width / snap["scroll"]["w"]

    queue = []
    for f in abstentions:
        el = by_path.get(f["target"])
        crop, zoom = make_crop(
            img,
            el["rect"] if el else None,
            scale,
            outdir / "queue" / f"{name}--{len(queue):02d}.png",
        )
        queue.append(
            {
                "page": name,
                "reason": f["rule"],
                "target": f["target"],
                "priority": f["priority"],
                "why_queued": f["detail"],
                "question": QUESTIONS.get(f["rule"], "Describe what is wrong here."),
                "dom_facts": dom_facts(el),
                "crop": str(crop.relative_to(outdir)) if crop else None,
                "crop_zoom": zoom,
                "forbid": FORBID,
            }
        )

    if prof.judgement:
        crop, zoom = make_crop(img, None, scale, outdir / "queue" / f"{name}--page.png")
        queue.append(
            {
                "page": name,
                "reason": "judgement",
                "target": "(whole page)",
                "priority": 1.0,
                "why_queued": (
                    "no rule reaches hierarchy, attention or whether the page "
                    "makes sense; this is the residue by construction, not a "
                    "gap in the rules"
                ),
                "question": QUESTIONS["_judgement"],
                "dom_facts": {},
                "crop": str(crop.relative_to(outdir)) if crop else None,
                "crop_zoom": zoom,
                "forbid": FORBID,
            }
        )

    queue.sort(key=lambda q: -q["priority"])
    over = max(0, len(queue) - prof.queue_budget)
    queue = queue[: prof.queue_budget]

    return {
        "decided": decided,
        "abstentions": abstentions,
        "discharged": discharged,
        "queue": queue,
        "over_budget": over,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", default="corpus/out", type=pathlib.Path)
    ap.add_argument("--profile", default="bench")
    ap.add_argument("--no-x2", action="store_true", help="disable the X2 arm")
    a = ap.parse_args()

    corpus = a.corpus.resolve()
    prof = profiles.get(a.profile)
    tokens = json.loads((corpus / "manifest.json").read_text())["tokens"]

    pages = {}
    for f in sorted((corpus / "snapshots").glob("*.json")):
        png = corpus / "shots" / f"{f.stem}.png"
        if not png.exists():
            continue
        pages[f.stem] = route_page(
            f.stem, json.loads(f.read_text()), png, tokens, prof, corpus
        )

    out = {
        "profile": prof.id,
        "stance": prof.stance,
        "judgement_queue": prof.judgement,
        "queue_budget": prof.queue_budget,
        "pages": {
            n: {k: v for k, v in p.items() if not k.startswith("_")}
            for n, p in pages.items()
        },
    }
    (corpus / "route.json").write_text(json.dumps(out, indent=1))

    n_dec = sum(len(p["decided"]) for p in pages.values())
    n_abs = sum(len(p["abstentions"]) for p in pages.values())
    n_dis = sum(len(p["discharged"]) for p in pages.values())
    n_q = sum(len(p["queue"]) for p in pages.values())
    n_over = sum(p["over_budget"] for p in pages.values())

    print(f"profile {prof.id}: {prof.stance}")
    print(
        f"{len(pages)} pages -> {n_dec} decided deterministically · "
        f"{n_dis} abstention(s) discharged by the cross-check · "
        f"{n_abs} left abstaining · {n_q} queued for a human/vision read"
        + (f" ({n_over} dropped at budget)" if n_over else "")
    )
    if n_dec + n_abs:
        print(
            f"  vision share: {n_abs}/{n_dec + n_abs + n_dis} "
            f"({n_abs / (n_dec + n_abs + n_dis):.1%}) of everything raised"
        )
    print()
    for name, p in sorted(pages.items()):
        if not p["queue"] and not p["discharged"]:
            continue
        print(name)
        for d in p["discharged"]:
            print(
                f"    discharged  [{d['rule']}] {d['target'].rsplit(' > ', 1)[-1]}"
                f"  <- answered by {d['discharged_by']}, never queued"
            )
        for q in p["queue"]:
            print(
                f"    queued p{q['priority']:<5.2f} [{q['reason']}] "
                f"{q['target'].rsplit(' > ', 1)[-1]}  -> {q['crop']} @{q['crop_zoom']}x"
            )


if __name__ == "__main__":
    main()
