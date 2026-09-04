#!/usr/bin/env python3
"""The abstention router: decide what the vision layer is asked, and what it is not.

The deterministic layer's most valuable output is not a finding, it is an
abstention. `contrast-indeterminate: cannot compute a ratio, the backdrop is a
gradient -- 4.5:1 is UNVERIFIED for this text` is worth more than a pass, because
every silent pass that should have been an abstention is a defect shipped. This
stage is what makes that true in practice: the abstention set IS the vision
layer's job queue, and it is small, which is what makes the vision spend
affordable at all.

Two triggers, and deliberately not the five the spec designs (§1.5). B19 cut S4
to roughly this size for a reason worth restating: five triggers, a block ledger
and a collapse-by-class exist to manage a queue whose real size nobody has
measured. Machinery for an empty queue is an argument, not a number. The cut
machinery is revived by probe U3.

⚠️ **T1 is no longer 0 on this corpus, and that is a change to a number the spec
quotes.** B19's cut rested on `T1 == 0`: with the cross-check subtracting the
gradient case, nothing was left to route. Fixing X2 added one abstention per page
-- vertical optical centring, which no artifact here can settle -- so T1 is now
12 crops over 13 pages. The cut still stands, because 12 questions of ONE class
are not 12 questions: the collapse and the fold both hold them at one image each,
and none is dropped. But the sentence "T1 on the corpus today is 0" is now false,
and a rule that abstains honestly is exactly how it stopped being true.

  T1  every INDETERMINATE, MINUS what the cross-check already settled.
  T2  the six unscreenable classes, once per page, unconditional, never cut for
      budget. This is the gestalt call, and it is the arm that was actually
      measured: 2/2 judgement defects plus three real defects nobody injected.

🚨 **The T1 subtraction is CODE, not discipline, and it is gated on the
cross-check's file EXISTING** (§2 C16 / C8). Contrast over a gradient is settled
deterministically -- two numbers and a verdict, no model call -- so re-asking it
would spend a 3,200-token crop on a closed question. But if the cross-check is
DOWN, an empty findings file resolves nothing and looks exactly like nothing
needing resolution. So a missing file is not a subtraction of zero: T1 GROWS, and
the plan says so. This is the one case where a larger model queue is the correct
response to a layer failure.

**The NEVER list.** If the answer has a number in it, the model is not asked the
question. Distances, gaps, sizes, ratios, contrast (solid OR gradient), token
membership, animation timing, bounding boxes, and any score, grade or ranking.
Every job carries its own prohibition into its caption, because a judge that is
not told will answer anyway.

Usage: python3 route.py <corpus-dir> [--app <profile>] [--emit-crops]
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib

import profiles

# Which cross-check FAIL settles which abstention class. This table IS the T1
# subtraction; keeping it here rather than in a rule's name is what lets a new
# abstention be routed without anyone remembering to update a list.
RESOLVERS = {"xcheck-contrast-varies": "readability"}

# The delivery envelope (§2 C5). Both predicates must hold, and the token one is
# the general rule: 2000x2000 passes every dimension check, is accepted, and is
# then RESAMPLED by the API at 72*72 = 5,184 visual tokens against a 4,784 tier.
# Every geometric claim about such an image is a claim about a frame that was
# resized after we certified it.
READ_CLAMP_PX = 2000  # the agent-path client clamp
TIER_TOKENS = 4784  # the API-path visual-token tier
PATCH = 28  # image tokens are ceil(w/28) x ceil(h/28), NOT w*h/750
CROP_PAD_CSS = 24  # a crop with no context cannot be judged against its neighbours
# The fold floor, derived rather than chosen: `detect_dom.TARGET_MIN`, the
# smallest thing this system's own rules say a person must be able to hit. A
# subject whose longest side is under it cannot be resolved inside a whole-page
# frame, so its question gets its own crop; anything larger is asked in place.
FOLD_FLOOR_CSS = 44.0
# The request-side image-block bound (§2 C1). The conversation ledger is a
# different resource with a different owner; this is the one the cliff is about,
# and it belongs to whoever assembles the request -- recorded here so that stage
# does not have to re-derive it.
BLOCKS_PER_REQUEST = 8


def tokens_for(w_px: float, h_px: float) -> int:
    """Patch-based, per §7's correction to our own docs. The /750 formula that
    every budget in the March corpus was built on is not the formula."""
    return math.ceil(w_px / PATCH) * math.ceil(h_px / PATCH)


def eff_for(w_css: float, h_css: float, master_scale: float) -> dict:
    """Effective rendered pixels per CSS pixel, on each delivery path (§2 C6).

    They are different numbers and a finding weighted by `eff` has to name which
    path delivered it. The agent path meets a 2000px client clamp; the API path
    meets the token tier instead and sees ~21% more detail on a full frame.
    """
    read = min(
        master_scale, READ_CLAMP_PX / max(w_css, 1), READ_CLAMP_PX / max(h_css, 1)
    )
    api = master_scale
    while api > 0.05 and tokens_for(w_css * api, h_css * api) > TIER_TOKENS:
        api -= 0.01
    return {"eff_read": round(read, 3), "eff_api": round(api, 3)}


def region_label(el: dict) -> str:
    """A name, not a coordinate (§2 C19). A crop finding names a label and
    attribution becomes a lookup in this plan -- which replaces three
    multiplications owned by three stages with a join, and removes the whole
    class of off-by-one that returns a real element one table row up."""
    leaf = el["path"].rsplit(" > ", 1)[-1]
    text = (el.get("text") or "").strip()
    return f"{leaf}{' — ' + text[:32] if text else ''}"


def prohibition(eff: float) -> str:
    """Every crop states what it cannot support, in its own caption. Below eff
    2.00 a 1-2px claim is a claim about a resampled frame."""
    base = (
        "Name nothing with a number in it: no distance, gap, size, ratio, contrast "
        "value, token name, timing, bounding box, score or ranking. Those are "
        "measured elsewhere and are given to you as values, never as questions."
    )
    if eff < 2.0:
        return (
            base + f" This image is at eff {eff:.2f}, below 2.00: do not assert any "
            "1-2px alignment, hairline-width or colour-drift finding from it. If you "
            "suspect one, name the region instead."
        )
    return base


def load(corpus: pathlib.Path):
    dom = corpus / "findings_dom.json"
    xch = corpus / "findings_xcheck.json"
    return (
        json.loads(dom.read_text()) if dom.exists() else {},
        json.loads(xch.read_text()) if xch.exists() else None,  # None = layer DOWN
        json.loads((corpus / "manifest.json").read_text()),
    )


def plan_page(page, snap, dom_f, xch_f, profile, master_scale, viewport):
    """-> (jobs, deficit_note). One page's routing decision."""
    by_path = {e["path"]: e for e in snap["elements"]}
    findings = profiles.apply(profile, list(dom_f) + list(xch_f or []))

    # --- T1: abstentions, minus what the cross-check settled -------------------
    settled = {
        (f["target"], RESOLVERS[f["rule"]])
        for f in (xch_f or [])
        if f["rule"] in RESOLVERS and f.get("verdict", "FAIL") == "FAIL"
    }
    absts = [f for f in findings if f.get("verdict") == "INDETERMINATE"]
    live = [a for a in absts if (a["target"], a.get("routeTo")) not in settled]

    # Collapse per page by (routeTo, rule): one crop answers a class, and a
    # gradient behind a hero is ONE question however many text runs sit on it.
    # The fuller (rule, backdrop_signature) collapse waits on U3 -- until someone
    # has histogrammed abstentions over real routes, a more elaborate collapse is
    # machinery for a queue of unknown size.
    seen, collapsed = set(), []
    for a in live:
        key = (a.get("routeTo"), a["rule"])
        if key in seen:
            continue
        seen.add(key)
        collapsed.append(a)

    jobs, folded = [], []
    for a in collapsed:
        el = by_path.get(a["target"])
        if el is None:
            continue
        r = el["rect"]
        x = max(0.0, r["x"] - CROP_PAD_CSS)
        y = max(0.0, r["y"] - CROP_PAD_CSS)
        w = min(snap["scroll"]["w"] - x, r["w"] + 2 * CROP_PAD_CSS)
        h = min(snap["scroll"]["h"] - y, r["h"] + 2 * CROP_PAD_CSS)
        eff = eff_for(w, h, master_scale)
        entry = {
            "region": f"region {len(jobs) + len(folded):02d} — {region_label(el)}",
            "asks": a.get("routeTo"),
            "because": a["detail"],
            "rect_css": {
                "x": round(x, 1),
                "y": round(y, 1),
                "w": round(w, 1),
                "h": round(h, 1),
            },
            **eff,
            # Values, never verdicts (§2 C3). The judge may be told what was
            # measured; it may not be told what we concluded.
            "values": {"subject": a["target"], "rule": a["rule"]},
        }
        # 🚨 A second image is not free, and this is the line where a routing
        # layer quietly buys one. T2 already asks all six unscreenable classes on
        # this page, unconditionally -- so an abstention whose class is one of the
        # six is ALREADY being asked, and a crop re-asks it in a smaller frame.
        # Whether that smaller frame buys anything is exactly what probe U4 exists
        # to settle and has not (B17 cut S5's planning half on the same ground).
        #
        # So the split is on the one thing that does not need U4: whether the
        # subject is even RESOLVABLE in the frame that already asks its class. The
        # floor is TARGET_MIN, 44 CSS px -- the smallest thing this system's own
        # rules say a person must be able to hit. A subject below that, sitting in
        # a 1280px-wide frame, is being asked about at a size the judge can barely
        # resolve, and a crop costs 16 visual tokens against the gestalt call's
        # 3,381. Above it, the region folds: it is named in the gestalt call's
        # caption, the question IS asked, and no second block is spent.
        #
        # Either way the image is WRITTEN. Refusing to write destroys evidence;
        # refusing to deliver costs nothing (§2 C1), so a folded region is written
        # and marked undeliverable rather than never rendered.
        # The subject's EXTENT, not its smallest side: a 1168x16 caption spans
        # the frame and is trivially locatable in it, while a 12x16 glyph is a
        # speck. Using min() would have sent both to their own crop, because a
        # line of 14px text is 16px tall whatever its width.
        subject_extent_css = max(r["w"], r["h"])
        if (
            entry["asks"] in profiles.UNSCREENABLE
            and subject_extent_css >= FOLD_FLOOR_CSS
        ):
            entry["folded_into"] = "T2"
            entry["deliverable"] = False
            folded.append(entry)
        else:
            jobs.append(
                {
                    "trigger": "T1",
                    "page": page,
                    "kind": "crop",
                    "deliverable": True,
                    "tokens_api": tokens_for(w * eff["eff_api"], h * eff["eff_api"]),
                    "never": prohibition(eff["eff_api"]),
                    **entry,
                }
            )

    # --- T2: the six unscreenable classes, one call, unconditional -------------
    # Never cut for budget, never cropped: the measured arm was a viewport frame,
    # and 4 of 5 unique findings from a real blind pass are page-global
    # quantifications a crop structurally cannot reach.
    w, h = viewport["width"], viewport["height"]
    eff = eff_for(w, h, master_scale)
    jobs.append(
        {
            "trigger": "T2",
            "page": page,
            "kind": "gestalt",
            "region": "region ** — the whole first fold",
            "asks": profiles.route_order(profile),
            "because": (
                "no rule screens these classes; they are judgements about whether the "
                "page makes sense, not measurements"
            ),
            "rect_css": {"x": 0, "y": 0, "w": w, "h": h},
            **eff,
            "tokens_api": tokens_for(w * eff["eff_api"], h * eff["eff_api"]),
            "never": prohibition(eff["eff_api"]),
            "blind": True,  # no fact-pack, no verdicts: §6 B5, until U5 answers
            "deliverable": True,
            # The abstentions this call is now carrying, by name. Without this
            # list the fold is indistinguishable from a drop.
            "focus": folded,
        }
    )

    deficit = len(absts) - len(collapsed)
    return jobs, deficit, len(folded)


def main(corpus: pathlib.Path, app: str, emit_crops: bool) -> None:
    profile = profiles.get(app)
    dom, xch, manifest = load(corpus)
    run = (
        json.loads((corpus / "run.json").read_text())
        if (corpus / "run.json").exists()
        else {}
    )
    snaps = corpus / "snapshots"

    xcheck_up = xch is not None
    plan = {
        "app": app,
        "intent": profile["intent"],
        "route_order": profiles.route_order(profile),
        "xcheck": "up" if xcheck_up else "ABSENT",
        # The honest consequence of a down layer, stated in the artifact rather
        # than left for a reader to infer from a queue that looks normal.
        "xcheck_note": (
            ""
            if xcheck_up
            else "cross-check findings file missing: NOTHING was subtracted from T1, so "
            "this queue is LARGER than a healthy run's, not smaller. A gradient "
            "contrast question that is normally settled for free is being paid for."
        ),
        "run": {k: run.get(k) for k in ("platform", "browser", "font") if k in run},
        "pages": {},
    }

    total_deficit = total_folded = 0
    for f in sorted(snaps.glob("*.json")):
        snap = json.loads(f.read_text())
        # Take the LARGEST master this run photographed, not the 1x one. If the
        # pipeline downsamples we inherit the old score whatever model we buy --
        # Opus 4.6 → 4.7 on ScreenSpot-Pro went 69.0% → 79.5%, attributed mainly
        # to accepting ~3.3x more pixels. `eff_api` caps it back down to the tier,
        # so starting high costs nothing and starting low cannot be recovered.
        masters = sorted(
            (corpus / "shots").glob(f"{f.stem}.png"),
        ) + sorted((corpus / "shots").glob(f"{f.stem}@*x.png"))
        master_scale, master_file = 1.0, None
        for shot in masters:
            from PIL import Image

            with Image.open(shot) as im:
                s = im.size[0] / snap["scroll"]["w"]
            if s > master_scale or master_file is None:
                master_scale, master_file = s, shot.name
        jobs, deficit, nfolded = plan_page(
            f.stem,
            snap,
            dom.get(f.stem, []),
            (xch or {}).get(f.stem, []),
            profile,
            master_scale,
            manifest["viewport"],
        )
        total_deficit += deficit
        total_folded += nfolded
        for j in jobs:
            j["master"] = master_file
        plan["pages"][f.stem] = jobs

    # C7 ruling 2: an unanswered question must be visible as unanswered, not
    # absent. A dropped abstention routes NOWHERE, which is the silent pass the
    # abstention was invented to prevent, re-entering through the routing layer.
    all_jobs = [j for js in plan["pages"].values() for j in js]
    plan["coverage"] = {
        "subjects": sum(len(v) for v in dom.values())
        + sum(len(v) for v in (xch or {}).values()),
        "jobs": len(all_jobs),
        "t1": sum(1 for j in all_jobs if j["trigger"] == "T1"),
        "t2": sum(1 for j in all_jobs if j["trigger"] == "T2"),
        "collapsed_into_a_class": total_deficit,
        "folded_into_t2": total_folded,
        "unadjudicated_by_budget": 0,  # nothing is cut for budget: T2 is exempt
        "tokens_api": sum(j["tokens_api"] for j in all_jobs),
        # The image ledger, for whoever assembles the requests. Blocks, not
        # tokens, are what meets the cliff.
        "blocks": {
            "deliverable": sum(1 for j in all_jobs if j.get("deliverable")),
            "per_request_ceiling": BLOCKS_PER_REQUEST,
            "written_undeliverable": total_folded,
        },
    }
    (corpus / "route-plan.json").write_text(json.dumps(plan, indent=1))

    if emit_crops:
        write_crops(corpus, plan)

    c = plan["coverage"]
    print(f"route-plan  app={app}  intent={profile['intent']}  xcheck={plan['xcheck']}")
    if plan["xcheck_note"]:
        print(f"  ⚠️  {plan['xcheck_note']}")
    print(
        f"  {c['t1']} T1 crop(s) + {c['t2']} T2 gestalt call(s) over "
        f"{len(plan['pages'])} page(s); of {c['subjects']} finding(s): "
        f"{c['collapsed_into_a_class']} abstention(s) collapsed into a class, "
        f"{c['folded_into_t2']} folded into the T2 call that already asks their "
        f"class, {c['unadjudicated_by_budget']} dropped for budget"
    )
    print(
        f"  {c['tokens_api']:,} visual tokens on the API path (ceil(w/28)*ceil(h/28))"
    )
    ctrl = plan["pages"].get("clean", [])
    print(
        f"  CONTROL clean.html -> {sum(1 for j in ctrl if j['trigger'] == 'T1')} crop(s) "
        f"+ {sum(1 for j in ctrl if j['trigger'] == 'T2')} gestalt "
        f"({sum(j['tokens_api'] for j in ctrl):,} tok) — a clean page still costs the "
        f"unconditional call, and that is the floor of any per-page estimate"
    )
    for page, jobs in sorted(plan["pages"].items()):
        for j in jobs:
            if j["trigger"] == "T1":
                print(f"    T1 {page:20} {j['region'][:42]:44} asks:{j['asks']}")
            for k in j.get("focus", []):
                print(
                    f"    ↳  {page:20} {k['region'][:42]:44} asks:{k['asks']} "
                    f"(in the gestalt call, no second image)"
                )


def write_crops(corpus: pathlib.Path, plan: dict) -> None:
    """Cut the crops from the master this run already photographed.

    S5 was cut to a ~40-LOC re-clip utility (B17) and this is it. It re-clips the
    SAME frame rather than driving a second browser pass, which is the property
    that matters: a crop from a second pass is a different render, and every
    argument comparing a pixel finding to a DOM finding rests on them describing
    one frame.
    """
    from PIL import Image

    out = corpus / "crops"
    out.mkdir(exist_ok=True)
    for page, jobs in plan["pages"].items():
        shot = corpus / "shots" / (jobs[0].get("master") or f"{page}.png")
        if not shot.exists():
            continue
        with Image.open(shot) as im:
            snap = json.loads((corpus / "snapshots" / f"{page}.json").read_text())
            s = im.size[0] / snap["scroll"]["w"]
            # Folded regions are written too, and stay marked undeliverable. The
            # image is the evidence a human looks at when they want to see what
            # the router decided not to buy a call for.
            targets = [j for j in jobs if j["kind"] == "crop"]
            targets += [k for j in jobs for k in j.get("focus", [])]
            for i, j in enumerate(targets):
                r = j["rect_css"]
                box = (
                    int(r["x"] * s),
                    int(r["y"] * s),
                    min(im.size[0], int((r["x"] + r["w"]) * s)),
                    min(im.size[1], int((r["y"] + r["h"]) * s)),
                )
                tile = im.crop(box)
                # Enforced HERE as well as at request assembly (§2 C5): the crop
                # writer refuses to spend bytes on an image the tier will resample.
                if tokens_for(*tile.size) > TIER_TOKENS:
                    j["written"] = "REFUSED: over the 4,784-token tier"
                    continue
                name = f"{page}-c{i:02d}.png"
                tile.save(out / name)
                j["written"] = name
    (corpus / "route-plan.json").write_text(json.dumps(plan, indent=1))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "corpus", type=pathlib.Path, nargs="?", default=pathlib.Path("corpus/out")
    )
    ap.add_argument("--app", default=profiles.DEFAULT)
    ap.add_argument("--emit-crops", action="store_true")
    a = ap.parse_args()
    main(a.corpus.resolve(), a.app, a.emit_crops)
