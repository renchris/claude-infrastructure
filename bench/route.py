#!/usr/bin/env python3
"""The abstention router: turn what the deterministic layer could not decide
into a small, cropped, budgeted queue for the vision layer.

The deterministic layer's most valuable output is not a finding, it is an
abstention. `detect_dom.py` returns `contrast-indeterminate` rather than a pass
where the backdrop is a gradient; `detect_xcheck.py` returns
`xcheck-optical-centre-indeterminate` where a compensation is declared and
whether it is the RIGHT amount is a judgement. Every silent pass that should have
been an abstention is a defect shipped -- and every abstention that goes nowhere
is the same defect with a paper trail. This is the stage that gives them
somewhere to go.

What comes out is a queue, not a verdict. This module never calls a model. It
decides what WOULD be worth asking, crops the region the question is about, and
writes the ledger. Everything it emits is advisory by construction, which is the
June 2026 ruling holding: taste stays human, gates adjudicate correctness only.

Three things it does that a naive "send the abstentions" would not:

  COLLAPSE BY CLASS. Two `contrast-indeterminate` findings on two lines of the
  same hero are one question about one region, not two model calls. Abstentions
  of the same rule whose rects are adjacent are merged into a single crop.

  CROP, DO NOT DOWNSCALE. Cropping to the region in question took OS-Atlas-7B
  from 18.9% to 48.1% on ScreenSpot-Pro with no model change -- a larger delta
  than every model upgrade in that table combined. Crops are cut from the highest
  device-scale capture available and are never resized here.

  BUDGET, AND SAY WHAT THE BUDGET DROPPED. Per-app budgets come from
  `weights.json`: `crops` caps the cropped questions per surface, `gestalt` sets
  how many independent blind passes that surface is worth. Anything the budget
  excludes is written to the block ledger with the reason. A queue that silently
  truncates is a coverage claim that lies.

Every crop carries its own PROHIBITION in its caption: the grounder supplies
identity, the DOM supplies geometry. A model-produced bounding box is a 68-mAP
estimate of something getBoundingClientRect() returns exactly, for free, with no
hallucination risk -- so the judge is forbidden from computing any distance from
a crop, and the caption says so in the crop's own record.

Usage: python3 route.py <corpus-dir> [--app <profile>] [--control clean]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

from PIL import Image

# Two abstentions of the same class this close together are one question.
CROP_MERGE_PX = 24
# Context around the region. A crop tight to the text loses the backdrop the
# question is usually ABOUT.
CROP_PAD_PX = 32
# Claude's high-resolution tier. A crop wider than this is downscaled by the API
# whatever we do, so the router records the fact rather than discovering it later.
MAX_CROP_EDGE = 2576

PROHIBITION = (
    "Identity only. Do not measure, estimate or compute any distance, size or "
    "position from this image -- every number is already known exactly from the "
    "DOM and is supplied alongside. Answer only the question asked."
)


def load_weights(path: pathlib.Path, app: str) -> dict:
    cfg = json.loads(path.read_text())
    profiles = cfg["profiles"]
    if app not in profiles:
        sys.exit(
            f"unknown app profile {app!r}; weights.json has: "
            f"{', '.join(sorted(profiles))}"
        )
    p = dict(profiles[app])
    p["name"] = app
    p["never_downweighted"] = set(cfg["never_downweighted"])
    return p


def weight_of(prof: dict, rule: str) -> float:
    w = prof["weights"].get(rule, prof.get("default_weight", 1.0))
    # A weighting is about attention, never about silencing a correctness
    # finding. Clamping here rather than validating the config means a profile
    # cannot acquire this defect by being edited later.
    if rule in prof["never_downweighted"]:
        w = max(w, 1.0)
    return w


SEVERITY_RANK = {"high": 3, "medium": 2, "low": 1}


def is_abstention(f: dict) -> bool:
    return f["rule"].endswith("-indeterminate")


def claim_key(f: dict) -> tuple:
    """Identity spanning the claim, not only its location -- see detect_xcheck."""
    mag = f.get("offset_px")
    return (f["rule"], f["target"], None if mag is None else round(mag))


def rects_for(snap: dict) -> dict:
    return {e["path"]: e["rect"] for e in snap["elements"]}


def merge_rects(a: dict, b: dict) -> dict:
    x, y = min(a["x"], b["x"]), min(a["y"], b["y"])
    r, bo = max(a["right"], b["right"]), max(a["bottom"], b["bottom"])
    return {"x": x, "y": y, "right": r, "bottom": bo, "w": r - x, "h": bo - y}


def near(a: dict, b: dict, pad: int = CROP_MERGE_PX) -> bool:
    return not (
        a["right"] + pad < b["x"]
        or b["right"] + pad < a["x"]
        or a["bottom"] + pad < b["y"]
        or b["bottom"] + pad < a["y"]
    )


def collapse(items: list[dict]) -> list[dict]:
    """Merge same-rule abstentions whose regions are adjacent into one question."""
    groups: list[dict] = []
    for it in items:
        for g in groups:
            if g["rule"] == it["rule"] and near(g["rect"], it["rect"]):
                g["rect"] = merge_rects(g["rect"], it["rect"])
                g["members"].append(it)
                break
        else:
            groups.append(
                {"rule": it["rule"], "rect": dict(it["rect"]), "members": [it]}
            )
    # One pass can leave two groups that only became adjacent after merging.
    changed = True
    while changed:
        changed = False
        for i, g in enumerate(groups):
            for h in groups[i + 1 :]:
                if g["rule"] == h["rule"] and near(g["rect"], h["rect"]):
                    g["rect"] = merge_rects(g["rect"], h["rect"])
                    g["members"] += h["members"]
                    groups.remove(h)
                    changed = True
                    break
            if changed:
                break
    return groups


def pick_shot(shots: pathlib.Path, stem: str):
    """The highest device-scale capture of this page, and its scale factor.

    Crop and zoom rather than downscale: the review is better served by the
    densest pixels we captured, and choosing them here rather than at capture
    time keeps the decision in one place.
    """
    best, best_dpr = None, 0.0
    for p in shots.glob(f"{stem}*.png"):
        tail = p.stem[len(stem) :]
        dpr = 1.0 if not tail else float(tail.lstrip("@").rstrip("x") or 1.0)
        if p.stem != stem and not tail.startswith("@"):
            continue  # a different page whose name merely starts the same
        if dpr > best_dpr:
            best, best_dpr = p, dpr
    return best, best_dpr


def route(corpus: pathlib.Path, prof: dict, control: str) -> dict:
    snaps = corpus / "snapshots"
    shots = corpus / "shots"
    crops = corpus / "crops"
    crops.mkdir(exist_ok=True)

    findings: dict[str, list[dict]] = {}
    for name in ("findings_dom.json", "findings_xcheck.json"):
        f = corpus / name
        if not f.exists():
            sys.exit(f"missing {f} -- run the detectors first")
        src = name.removeprefix("findings_").removesuffix(".json")
        for page, fs in json.loads(f.read_text()).items():
            findings.setdefault(page, []).extend(dict(x, detector=src) for x in fs)

    # Subtract the control. A finding that is equally true of the clean baseline
    # is a property of the design, not a defect in this page -- and the key spans
    # the claim, so a control finding cannot swallow a real one on the same
    # element the way a (rule, target) key did.
    baseline = {claim_key(f) for f in findings.get(control, [])}

    pages = {}
    for page, fs in sorted(findings.items()):
        snap_f = snaps / f"{page}.json"
        if not snap_f.exists():
            continue
        rects = rects_for(json.loads(snap_f.read_text()))
        shot, dpr = pick_shot(shots, page)

        novel = (
            [f for f in fs if claim_key(f) not in baseline] if page != control else fs
        )
        absts, asserts = [], []
        for f in novel:
            r = rects.get(f["target"])
            if r is None:
                continue
            (absts if is_abstention(f) else asserts).append(dict(f, rect=r))

        queue, blocked = [], []

        # --- crop questions: one per collapsed abstention class ---------------
        groups = collapse(absts)
        groups.sort(
            key=lambda g: (
                -weight_of(prof, g["rule"])
                * max(SEVERITY_RANK.get(m["severity"], 2) for m in g["members"]),
                g["rect"]["y"],
            )
        )
        budget = prof["vlm_budget"]["crops"]
        for i, g in enumerate(groups):
            item = {
                "kind": "crop",
                "rule": g["rule"],
                "targets": [m["target"] for m in g["members"]],
                "question": g["members"][0]["detail"],
                "weight": round(weight_of(prof, g["rule"]), 3),
                "prohibition": PROHIBITION,
            }
            if i >= budget:
                blocked.append(
                    dict(
                        item, reason=f"over the {prof['name']} crop budget of {budget}"
                    )
                )
                continue
            if shot is None:
                blocked.append(dict(item, reason="no capture on disk for this page"))
                continue
            img = Image.open(shot)
            r = g["rect"]
            box = (
                max(0, int((r["x"] - CROP_PAD_PX) * dpr)),
                max(0, int((r["y"] - CROP_PAD_PX) * dpr)),
                min(img.width, int((r["right"] + CROP_PAD_PX) * dpr)),
                min(img.height, int((r["bottom"] + CROP_PAD_PX) * dpr)),
            )
            out = crops / f"{page}--{g['rule']}--{i}.png"
            img.crop(box).save(out)
            w, h = box[2] - box[0], box[3] - box[1]
            item |= {
                "image": str(out.relative_to(corpus)),
                "source_shot": shot.name,
                "device_scale": dpr,
                "crop_px": [w, h],
                # Say it here rather than discover it at the API. Over this edge
                # the request is downscaled whatever the pipeline intended, and
                # a silent resize destroys the evidence the crop exists to carry.
                "exceeds_hires_tier": max(w, h) > MAX_CROP_EDGE,
                "dom_facts": {
                    m["target"]: {"rect": m["rect"], "detail": m["detail"]}
                    for m in g["members"]
                },
            }
            queue.append(item)

        # --- the gestalt question: the residue no rule has jurisdiction over ---
        # Hierarchy, attention, "does this page make sense" are not abstentions
        # from any rule -- no rule was ever looking. They are what the whole
        # deterministic layer structurally cannot grow into, so they are minted
        # per page rather than per finding, and the per-app budget decides how
        # much they are worth. On a page whose every number the DOM already
        # knows, that budget is deliberately small.
        # `gestalt` is the number of INDEPENDENT blind passes this profile buys
        # per surface. More than one is not redundancy: a single pass is a sample
        # of one from a judge measured at 16-39% top-1 ranking reversals from
        # reordering alone, so a lane the profile actually relies on is sampled
        # more than once and the spread is the signal. Zero disables the lane.
        gbudget = prof["vlm_budget"]["gestalt"]
        for i in range(max(1, gbudget)):
            gestalt = {
                "kind": "gestalt",
                "rule": "unruled-residue",
                "pass": i + 1,
                "of": gbudget,
                "question": (
                    "Blind of our findings: what is wrong with this page that a "
                    "measurement could not state? Hierarchy, attention, whether the "
                    "page makes sense. Name nothing that has a number in the answer."
                ),
                "weight": round(prof.get("default_weight", 1.0), 3),
                "prohibition": PROHIBITION,
                "image": str(shot.relative_to(corpus)) if shot else None,
                "device_scale": dpr,
            }
            if gbudget < 1:
                blocked.append(
                    dict(
                        gestalt,
                        reason=f"{prof['name']} spends nothing on gestalt for this surface",
                    )
                )
                break
            if shot is None:
                blocked.append(dict(gestalt, reason="no capture on disk for this page"))
                break
            queue.append(gestalt)

        pages[page] = {
            "asserted": len(asserts),
            "abstained": len(absts),
            "queue": queue,
            "blocked": blocked,
        }

    return {
        "app": prof["name"],
        "profile_summary": prof["summary"],
        "control": control,
        "budget": prof["vlm_budget"],
        "pages": pages,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path)
    ap.add_argument("--app", default="default")
    ap.add_argument("--control", default="clean")
    ap.add_argument("--weights", type=pathlib.Path, default=None)
    a = ap.parse_args()

    corpus = a.corpus.resolve()
    wpath = a.weights or pathlib.Path(__file__).parent / "weights.json"
    prof = load_weights(wpath, a.app)
    res = route(corpus, prof, a.control)
    (corpus / "route.json").write_text(json.dumps(res, indent=1))

    nq = sum(len(p["queue"]) for p in res["pages"].values())
    nb = sum(len(p["blocked"]) for p in res["pages"].values())
    na = sum(p["abstained"] for p in res["pages"].values())
    print(f"profile {res['app']}: {res['profile_summary']}")
    print(
        f"  {na} abstention(s) over {len(res['pages'])} page(s) -> "
        f"{nq} queued item(s), {nb} blocked"
    )
    ctrl = res["pages"].get(a.control)
    if ctrl:
        crops_on_control = [q for q in ctrl["queue"] if q["kind"] == "crop"]
        print(
            f"  CONTROL {a.control}: {ctrl['asserted']} asserted, "
            f"{ctrl['abstained']} abstained, {len(crops_on_control)} crop(s) queued"
        )
    print()
    for page, p in sorted(res["pages"].items()):
        if not p["queue"] and not p["blocked"]:
            continue
        print(f"{page}")
        for q in p["queue"]:
            extra = (
                f" {q['crop_px'][0]}x{q['crop_px'][1]}px" if q["kind"] == "crop" else ""
            )
            print(f"    -> [{q['kind']:7}] {q['rule']:36} w={q['weight']}{extra}")
        for b in p["blocked"]:
            print(f"    xx [{b['kind']:7}] {b['rule']:36} {b['reason']}")


if __name__ == "__main__":
    main()
