#!/usr/bin/env python3
"""The abstention router: turn what the deterministic layer COULD NOT answer into
a small, cropped, fact-carrying queue for a vision pass.

The deterministic layer's most valuable output is not a finding, it is an
abstention. `detect_dom.py` rule 6 returns `contrast-indeterminate` rather than a
pass when the backdrop is a gradient or an image, because every silent pass that
should have been an abstention is a defect shipped. This module is what makes that
abstention worth having: it is the thing that routes.

Three states, and the whole design is that they are DISJOINT:

  DETERMINED  a rule returned a number. Never goes to a model. The DOM already
              knows the answer exactly and for free, and asking a model to
              re-derive it buys a 68-mAP estimate of a fact `getBoundingClientRect`
              returns exactly.
  RESOLVED    an abstention that the pixel cross-check answered. `detect_xcheck.py`
              samples the backdrop in the left and right thirds of a text run and
              turns "no single number represents this" into two numbers and a
              verdict. This is the state that matters commercially: it removes
              contrast-over-a-gradient from the queue entirely, at zero marginal
              cost, for about 180 lines of NumPy.
  QUEUED      an abstention nothing answered, plus one page-level residue job for
              the question no rule is even SHAPED to ask -- hierarchy, attention,
              "does this page make sense". That last one is why the queue can never
              be empty and why it must be capped: it is unbounded by construction,
              so the per-app profile buys a fixed number of them.

WHAT THIS DOES NOT DO, deliberately: it does not call a model. The June 2026
campaign ratified that taste stays human and gates adjudicate correctness and
coverage only, so the queue is an artifact a person or an agent reads, never an
autonomous verdict. The output of this file is a directory of crops and a JSON
brief. Nothing downstream of it is automated.

Two properties of the crops are load-bearing, both from the capture-fidelity
measurements:

  * CROP AND ZOOM, NEVER DOWNSCALE. ScreenSeekeR moved OS-Atlas-7B from 18.9% to
    48.1% on ScreenSpot-Pro with no model change -- a larger delta than every model
    upgrade in the same period combined. Crops are upscaled by an INTEGER
    nearest-neighbour factor, because a UI edge is a true step function and any
    smooth resampler turns the 1px misalignment you are asking about into a
    gradient.
  * A DOWNSCALE IS NEVER SILENT. A full-frame residue job can exceed the high-res
    tier's ~3.75 MP ceiling, and if it does, the loss is written into the job as
    `pixels_lost` rather than quietly happening. A pipeline that downsamples
    inherits the old score whatever model it buys, and the only thing worse is not
    knowing that it did.

Every job also carries a `facts` block and a `forbid` line. The facts are the
DOM's exact geometry and computed styles for the element in question; the forbid
line says the model may not compute any distance, size or coordinate from the
image. The grounder supplies identity, the DOM supplies geometry -- and a job that
ships the geometry alongside the crop is what makes that rule enforceable rather
than aspirational.

Usage: python3 route.py <corpus-dir> [--profile reso-management] [--out DIR]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

from PIL import Image

import detect_dom
import detect_xcheck
import profiles

# Rules whose verdict is "I could not answer this". Everything else a detector
# emits is an answer, including a clean one.
ABSTENTIONS = {"contrast-indeterminate"}

# Which cross-check finding, on the same element, counts as having ANSWERED which
# abstention. Keyed by the abstaining rule. This mapping is the router's whole
# claim, so it is written out rather than inferred from a substring match on the
# rule names -- an accidental prefix collision here would silently empty the queue.
RESOLVED_BY = {"contrast-indeterminate": {"xcheck-contrast-varies"}}

CROP_CONTEXT_PX = 24  # CSS px of surrounding page kept around a cropped element
CROP_MIN_LONG_EDGE = 768  # upscale until the crop is at least this wide/tall
CROP_MAX_LONG_EDGE = 2576  # the high-resolution tier's long edge
FRAME_MAX_PIXELS = 3_750_000  # ~3.75 MP: the tier's area ceiling

FORBID = (
    "Do not compute or estimate any distance, size, coordinate or colour value "
    "from this image. Every number you need is in `facts`, measured exactly by the "
    "browser. Answer only the question asked, and say 'cannot tell from this crop' "
    "rather than guessing."
)

RESIDUE_QUESTION = (
    "Nothing in the deterministic layer is shaped to ask this: looking at this page "
    "as a reader would in the first second, does its visual hierarchy match its "
    "intent? Name the element the eye lands on first and the element that SHOULD "
    "have been first, or say they agree. Judgement only -- no measurements."
)


def _int_upscale(img: Image.Image) -> tuple[Image.Image, int]:
    """Nearest-neighbour integer zoom, capped at the high-res tier's long edge."""
    long_edge = max(img.size)
    if long_edge <= 0:
        return img, 1
    # Ceiling, not floor: floor division leaves a 500px crop at factor 1 and
    # therefore BELOW the minimum it was supposed to guarantee -- the invariant
    # this function exists to hold, missed by 268px, silently.
    factor = max(1, -(-CROP_MIN_LONG_EDGE // long_edge))
    while factor > 1 and long_edge * factor > CROP_MAX_LONG_EDGE:
        factor -= 1
    if factor == 1:
        return img, 1
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST), factor


def _fit_frame(img: Image.Image) -> tuple[Image.Image, float]:
    """Downscale a full frame to the tier ceiling, returning the fraction lost.

    A fraction of 0.0 means every captured pixel survived. Anything else is
    evidence destroyed, and the caller writes it into the job.
    """
    n = img.width * img.height
    if n <= FRAME_MAX_PIXELS and max(img.size) <= CROP_MAX_LONG_EDGE:
        return img, 0.0
    s = min(
        (FRAME_MAX_PIXELS / n) ** 0.5,
        CROP_MAX_LONG_EDGE / max(img.size),
    )
    out = img.resize((max(1, int(img.width * s)), max(1, int(img.height * s))))
    return out, round(1.0 - (out.width * out.height) / n, 4)


def _facts_for(el: dict) -> dict:
    """The exact numbers the model is forbidden from re-deriving."""
    keep = (
        "display",
        "position",
        "font-size",
        "font-weight",
        "line-height",
        "color",
        "background-color",
        "background-image",
        "border-radius",
        "opacity",
        "transform",
    )
    return {
        "path": el["path"],
        "tag": el["tag"],
        "text": el["text"],
        "rect_css_px": el["rect"],
        "computed": {k: el["styles"].get(k) for k in keep if el["styles"].get(k)},
    }


def route_page(
    name: str,
    snap: dict,
    shot: pathlib.Path,
    dom_findings: list[dict],
    x_findings: list[dict],
    profile: dict,
    outdir: pathlib.Path,
) -> dict:
    by_path = {e["path"]: e for e in snap["elements"]}
    x_by_path: dict[str, set[str]] = {}
    for f in x_findings:
        x_by_path.setdefault(f["target"], set()).add(f["rule"])

    determined = [f for f in dom_findings if f["rule"] not in ABSTENTIONS] + [
        f for f in x_findings
    ]
    abstentions = [f for f in dom_findings if f["rule"] in ABSTENTIONS]

    resolved, queued = [], []
    for f in abstentions:
        answered = RESOLVED_BY.get(f["rule"], set()) & x_by_path.get(f["target"], set())
        if answered:
            g = dict(f)
            g["resolved_by"] = sorted(answered)
            resolved.append(g)
        else:
            queued.append(f)

    img = Image.open(shot).convert("RGB")
    scale = img.width / snap["scroll"]["w"]
    qdir = outdir / "queue" / name
    jobs: list[dict] = []

    # Abstention jobs first: they are specific, bounded and cheap, and if the
    # budget runs out it should run out on the open-ended question, not on the one
    # a rule already narrowed down to a single element.
    for f in queued:
        el = by_path.get(f["target"])
        if el is None:
            continue
        r = el["rect"]
        box = (
            max(0, int((r["x"] - CROP_CONTEXT_PX) * scale)),
            max(0, int((r["y"] - CROP_CONTEXT_PX) * scale)),
            min(img.width, int((r["right"] + CROP_CONTEXT_PX) * scale)),
            min(img.height, int((r["bottom"] + CROP_CONTEXT_PX) * scale)),
        )
        crop, factor = _int_upscale(img.crop(box))
        jobs.append(
            {
                "page": name,
                "kind": "abstention",
                "rule": f["rule"],
                "target": f["target"],
                "question": f["detail"],
                "facts": _facts_for(el),
                "forbid": FORBID,
                "crop_px": list(crop.size),
                "zoom": factor,
                "pixels_lost": 0.0,
                "_image": crop,
            }
        )

    # Exactly one residue job per page. It is the only unbounded question in the
    # system -- "is this good" has no completion condition -- so it is capped at
    # one by construction and then again by the profile's budget.
    frame, lost = _fit_frame(img)
    jobs.append(
        {
            "page": name,
            "kind": "residue",
            "rule": "no-rule-is-shaped-for-this",
            "target": "(page)",
            "question": RESIDUE_QUESTION,
            "facts": {
                "note": "geometry for any element you name is in the snapshot; ask for it",
                "viewport_css_px": snap["scroll"],
            },
            "forbid": FORBID,
            "crop_px": list(frame.size),
            "zoom": 1,
            "pixels_lost": lost,
            "_image": frame,
        }
    )

    budget = int(profile["queue"])
    deferred = jobs[budget:]
    jobs = jobs[:budget]
    if jobs:
        qdir.mkdir(parents=True, exist_ok=True)
    for i, j in enumerate(jobs):
        p = qdir / f"{i:02d}-{j['kind']}-{j['rule']}.png"
        j.pop("_image").save(p)
        j["crop"] = str(p.relative_to(outdir))
    for j in deferred:
        j.pop("_image", None)

    return {
        "page": name,
        "determined": len(determined),
        "resolved": resolved,
        "queued": jobs,
        "deferred": [
            {"kind": d["kind"], "rule": d["rule"], "target": d["target"]}
            for d in deferred
        ],
        "elements": len(snap["elements"]),
    }


def selftest(corpus: pathlib.Path) -> int:
    """RED-prove the router, because its healthy state and its broken state look
    identical from outside.

    A router that queues nothing is what success looks like on this corpus: both
    abstentions get answered by the cross-check, so QUEUED reads 0 and RESOLVED
    reads 2. A router that has silently stopped SEEING abstentions -- a renamed
    rule, a path that no longer matches, a detector that regressed to a confident
    pass -- also queues nothing. The two are indistinguishable in the summary, and
    the second one is a defect shipped.

    So this withholds the cross-check's answer and asserts the abstention comes
    back out the other side as a real cropped job on disk, then restores it and
    asserts it does not. Both directions, or the test only proves the router can
    say one thing.
    """
    import tempfile

    corpus = corpus.resolve()
    manifest = json.loads((corpus / "manifest.json").read_text())
    tokens = manifest["tokens"]
    snap_p = corpus / "snapshots" / "contrast-on-gradient.json"
    shot = corpus / "shots" / "contrast-on-gradient.png"
    if not snap_p.exists() or not shot.exists():
        print("selftest: corpus not captured; run build_corpus.py then capture.py")
        return 2
    snap = json.loads(snap_p.read_text())
    profile = dict(profiles.get("default"))
    profile["queue"] = 9  # do not let the budget be what empties the queue

    dom = detect_dom.find(snap, tokens)
    xch = detect_xcheck.check(snap, shot)
    abst = [f for f in dom if f["rule"] in ABSTENTIONS]
    fails = []
    if not abst:
        fails.append(
            "the deterministic layer produced NO abstention on the gradient page; "
            "there is nothing to route and rule 6 has regressed to a silent pass"
        )

    with tempfile.TemporaryDirectory() as td:
        out = pathlib.Path(td)
        # (1) answer withheld -> every abstention must be queued, as a real file
        red = route_page("red", snap, shot, dom, [], profile, out)
        if len(red["queued"]) != len(abst) + 1:  # +1 residue
            fails.append(
                f"with the cross-check withheld, {len(abst)} abstention(s) + 1 residue "
                f"should have queued; got {len(red['queued'])}"
            )
        for j in red["queued"]:
            if not (out / j["crop"]).exists():
                fails.append(f"job {j['rule']} names a crop that is not on disk")
            # The invariant is the RESULT, not the factor: a crop of a full-width
            # caption is already past the minimum and needs no zoom, while a crop
            # of a 30px icon is worthless unless it is zoomed. Asserting the
            # factor instead of the outcome is what made the first version of this
            # test fail on a correct router.
            if j["kind"] == "abstention" and max(j["crop_px"]) < CROP_MIN_LONG_EDGE:
                fails.append(
                    f"abstention crop is {j['crop_px']}, under the {CROP_MIN_LONG_EDGE}px "
                    "minimum long edge; crop-and-zoom is the largest measured lever in "
                    "the whole pipeline and this job threw it away"
                )
            if max(j["crop_px"]) > CROP_MAX_LONG_EDGE:
                fails.append(
                    f"crop {j['crop_px']} exceeds the {CROP_MAX_LONG_EDGE}px tier long "
                    "edge; the model will downscale it and the loss will be invisible"
                )
        if red["resolved"]:
            fails.append(
                "nothing could have resolved an abstention with no cross-check"
            )

        # (2) answer supplied -> the same abstentions must LEAVE the queue
        green = route_page("green", snap, shot, dom, xch, profile, out)
        if green["queued"] and any(j["kind"] == "abstention" for j in green["queued"]):
            fails.append(
                "the cross-check answered the gradient and the abstention was queued "
                "anyway -- RESOLVED_BY no longer matches what detect_xcheck emits"
            )
        if len(green["resolved"]) != len(abst):
            fails.append(
                f"{len(abst)} abstention(s) should have resolved; "
                f"got {len(green['resolved'])}"
            )

    for f in fails:
        print(f"  FAIL {f}")
    print(
        f"route selftest: {'FAILED' if fails else 'ok'} "
        f"({len(abst)} abstention(s) routed both ways)"
    )
    return 1 if fails else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--profile", default="default")
    ap.add_argument("--out", type=pathlib.Path, default=None)
    a = ap.parse_args(argv[1:])
    if a.selftest:
        return selftest(a.corpus)

    corpus = a.corpus.resolve()
    outdir = (a.out or corpus).resolve()
    outdir.mkdir(parents=True, exist_ok=True)
    profile = profiles.get(a.profile)
    manifest = json.loads((corpus / "manifest.json").read_text())
    tokens = manifest["tokens"]

    routed = []
    for f in sorted((corpus / "snapshots").glob("*.json")):
        shot = corpus / "shots" / f"{f.stem}.png"
        if not shot.exists():
            continue
        snap = json.loads(f.read_text())
        dom = profiles.apply(profile, detect_dom.find(snap, tokens))
        xch = profiles.apply(profile, detect_xcheck.check(snap, shot))
        routed.append(route_page(f.stem, snap, shot, dom, xch, profile, outdir))

    payload = {
        "profile": a.profile,
        "budget_per_page": profile["queue"],
        "pages": routed,
    }
    (outdir / "vlm_queue.json").write_text(json.dumps(payload, indent=1, default=str))

    n_el = sum(r["elements"] for r in routed)
    n_det = sum(r["determined"] for r in routed)
    n_res = sum(len(r["resolved"]) for r in routed)
    n_q = sum(len(r["queued"]) for r in routed)
    n_def = sum(len(r["deferred"]) for r in routed)
    print(f"profile {a.profile}  budget {profile['queue']} job(s)/page")
    print(f"  {len(routed)} pages, {n_el} elements")
    print(f"  DETERMINED {n_det:4d}  answered by a rule, never sent to a model")
    print(f"  RESOLVED   {n_res:4d}  abstentions the pixel cross-check answered")
    print(f"  QUEUED     {n_q:4d}  jobs written to {outdir / 'queue'}")
    print(f"  DEFERRED   {n_def:4d}  over budget this run")
    if n_el:
        print(
            f"  queue is {n_q / n_el * 100:.1f}% of elements -- this is the vision spend"
        )
    for r in routed:
        for g in r["resolved"]:
            print(
                f"    {r['page']}: {g['rule']} on {g['target'][-40:]} "
                f"-> answered by {','.join(g['resolved_by'])}, NOT queued"
            )
    lost = [j for r in routed for j in r["queued"] if j["pixels_lost"] > 0]
    if lost:
        print(f"  !! {len(lost)} job(s) lost pixels to the tier ceiling:")
        for j in lost[:5]:
            print(
                f"     {j['page']}/{j['kind']}: {j['pixels_lost'] * 100:.0f}% discarded"
            )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
