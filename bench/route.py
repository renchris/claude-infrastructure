#!/usr/bin/env python3
"""Route the deterministic layer's residue to the vision layer, and nothing else.

The deterministic layer's most valuable output is not a finding, it is an
ABSTENTION. On a gradient backdrop it returns `contrast-indeterminate: cannot
compute a ratio, the requirement is UNVERIFIED` rather than a pass, because every
silent pass that should have been an abstention is a defect shipped. That
abstention set is exactly the vision layer's job queue -- and it is small, which
is the entire reason the vision spend is affordable.

This is the router. It runs after SCREEN and before any model call, it opens no
browser and issues no request, and it decides four things:

  1. WHAT IS SETTLED.      A finding with a number in it is finished. It is never
                           shown to a model, because a model asked to confirm a
                           measured number can only agree expensively or disagree
                           wrongly.
  2. WHAT IS DISCHARGED.   An abstention the cross-check already answered leaves
                           the queue. `contrast-indeterminate` on a gradient is
                           discharged by `xcheck-contrast-varies`, which turns
                           "unrepresentable" into two numbers and a verdict. This
                           is the seam the README argues for, made executable: the
                           queue is measured before and after, and the difference
                           is the cross-check's whole justification.
  3. WHAT IS ASKED.        The survivors, collapsed BY CLASS rather than by
                           element -- eight text runs over one gradient hero are
                           one question -- and cropped to the region in question,
                           because cropping beats downscaling by a wider margin
                           than any model upgrade measured.
  4. WHAT IS UNREACHABLE.  Exactly one whole-page question per page, for the
                           judgements no rule can grow into: hierarchy, grouping,
                           whether the page makes sense. No abstention triggers
                           these, because no rule was ever looking.

Every request carries a prohibition, and the prohibitions are the architecture:
the crop requests forbid numbers (the DOM supplies geometry, exactly and for
free), and the gestalt request forbids scores (June 2026: taste stays human,
gates adjudicate correctness and coverage only). Nothing this file emits can
become an exit code.

Usage: python3 route.py <corpus-dir> [--app <name>] [--shot=@1.5x]
"""

from __future__ import annotations

import argparse
import collections
import json
import math
import pathlib

from PIL import Image

# Context around a crop, in CSS px. A crop tight to the element hides the thing it
# is usually being compared against; a crop much wider is a screenshot again.
CROP_PAD = 48
CROP_MIN = 160
# Claude's image tokens are patch-based: ceil(w/28) * ceil(h/28). Not the /750 our
# older docs carried.
PATCH = 28
# The abstention rule -> the cross-check finding that answers the same question.
# A discharge is only legitimate where the second rule answers the FIRST rule's
# question about the SAME element; anything looser is an abstention swallowed.
DISCHARGES = {"contrast-indeterminate": {"xcheck-contrast-varies"}}
SEVERITY = {"high": 3.0, "medium": 2.0, "low": 1.0}


def load_profile(root: pathlib.Path, app: str) -> dict:
    doc = json.loads((root / "profiles.json").read_text())
    if app not in doc["apps"]:
        raise SystemExit(
            f"no profile for {app!r}; profiles.json has {sorted(doc['apps'])}"
        )
    prof = dict(doc["apps"][app])
    prof["app"] = app
    prof["correctness_floor"] = set(doc["correctness_floor"])
    return prof


def weigh(prof: dict, finding: dict) -> tuple[float, float, str]:
    """-> (weight actually applied, weighted severity, why the weight is that).

    A correctness rule is clamped to 1.0 whatever the profile says. The clamp is
    reported rather than applied silently: a profile that tried to mute an
    accessibility failure should leave a mark in the plan.
    """
    rule = finding["rule"]
    asked = float(prof.get("weights", {}).get(rule, 1.0))
    base = SEVERITY.get(finding.get("severity", "medium"), 2.0)
    if rule in prof["correctness_floor"] and asked < 1.0:
        return 1.0, base, f"profile asked {asked:g}, clamped to the correctness floor"
    return asked, base * asked, "profile weight" if asked != 1.0 else "neutral"


def container_of(path: str, depth: int = 1) -> str:
    """The ancestor an abstention collapses onto. Eight text runs over one hero
    are one question about the hero, not eight questions about text."""
    parts = path.split(" > ")
    return " > ".join(parts[:-depth]) if len(parts) > depth else path


def crop_rect(rects: list[dict], page_w: float, page_h: float) -> dict:
    x0 = min(r["x"] for r in rects) - CROP_PAD
    y0 = min(r["y"] for r in rects) - CROP_PAD
    x1 = max(r["right"] for r in rects) + CROP_PAD
    y1 = max(r["bottom"] for r in rects) + CROP_PAD
    # Grow to the minimum before clamping, so a small mark still gets its context.
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if x1 - x0 < CROP_MIN:
        x0, x1 = cx - CROP_MIN / 2, cx + CROP_MIN / 2
    if y1 - y0 < CROP_MIN:
        y0, y1 = cy - CROP_MIN / 2, cy + CROP_MIN / 2
    x0, y0 = max(0.0, x0), max(0.0, y0)
    x1, y1 = min(page_w, x1), min(page_h, y1)
    return {
        "x": round(x0, 1),
        "y": round(y0, 1),
        "w": round(x1 - x0, 1),
        "h": round(y1 - y0, 1),
    }


def visual_tokens(w: float, h: float) -> int:
    return math.ceil(w / PATCH) * math.ceil(h / PATCH)


def route_page(
    page: str,
    dom: list[dict],
    xchk: list[dict],
    snap: dict,
    prof: dict,
) -> dict:
    by_path = {e["path"]: e for e in snap["elements"]}
    settled, abstained = [], []
    for f in dom + xchk:
        (abstained if f["rule"].endswith("-indeterminate") else settled).append(f)

    # --- 2. discharge: what the cross-check already answered -----------------
    answered = collections.defaultdict(set)
    for f in xchk:
        answered[f["target"]].add(f["rule"])
    queue, discharged = [], []
    for a in abstained:
        by = DISCHARGES.get(a["rule"], set()) & answered.get(a["target"], set())
        if by and prof.get("discharge", True):
            discharged.append({**a, "discharged_by": sorted(by)})
        else:
            queue.append(a)

    # --- 3. collapse by class, then crop -------------------------------------
    groups = collections.defaultdict(list)
    for a in queue:
        groups[(a["rule"], container_of(a["target"]))].append(a)

    page_w = snap["scroll"]["w"]
    page_h = snap["scroll"]["h"]
    requests = []
    budget = int(prof.get("vlm_budget_per_page", 2))
    ordered = sorted(
        groups.items(),
        key=lambda kv: -max(weigh(prof, a)[1] for a in kv[1]),
    )
    for (rule, container), members in ordered:
        rects = [
            by_path[m["target"]]["rect"] for m in members if m["target"] in by_path
        ]
        if not rects:
            continue
        rect = crop_rect(rects, page_w, page_h)
        w, sev, why = weigh(prof, members[0])
        requests.append(
            {
                "kind": "crop",
                "rule": rule,
                "container": container,
                "targets": [m["target"] for m in members],
                "collapsed_from": len(members),
                "rect": rect,
                "visual_tokens": visual_tokens(rect["w"], rect["h"]),
                "weight": w,
                "weighted_severity": round(sev, 2),
                "weight_reason": why,
                "question": (
                    f"This crop is the region a deterministic rule refused to judge. "
                    f"{members[0]['detail']} Look at the rendered pixels and say whether "
                    f"a reader can read this text where it actually sits."
                ),
                "prohibition": (
                    "Return no number and no coordinate. Every distance, size and ratio "
                    "on this page is already known exactly from the DOM; a number you "
                    "estimate can only be worse than one that was measured."
                ),
            }
        )

    # --- 4. the question no rule was ever looking for ------------------------
    if prof.get("gestalt", True):
        requests.append(
            {
                "kind": "gestalt",
                "rule": None,
                "container": None,
                "targets": [],
                "collapsed_from": 0,
                "rect": {"x": 0, "y": 0, "w": page_w, "h": page_h},
                "visual_tokens": visual_tokens(page_w, page_h),
                "weight": 1.0,
                "weighted_severity": 0.0,
                "weight_reason": "not a rule; no abstention triggers this",
                "trigger": "no-rule-covers-relational-judgement",
                "question": (
                    "Whole page, no facts supplied. Where does the eye land first, and is "
                    "that where it should land? Does anything read as more important than "
                    "it is? Say what does not make sense."
                ),
                "prohibition": (
                    "Return no number, no coordinate and no score. A rating here would be "
                    "a taste verdict wearing a measurement's clothes, and taste stays with "
                    "the operator (June 2026). This output is advisory and can never reach "
                    "an exit code."
                ),
            }
        )

    # --- the settled findings, ordered the way THIS app should read them ------
    # The weighting is not only a routing knob. The same corpus read as a design
    # system and read as a marketing page is a different report, and the ordering
    # is what an operator actually acts on.
    report = []
    for f in settled:
        w, sev, why = weigh(prof, f)
        report.append(
            {
                "rule": f["rule"],
                "target": f["target"],
                "severity": f.get("severity", "medium"),
                "weight": w,
                "weighted_severity": round(sev, 2),
                "weight_reason": why,
                "suppressed": w == 0.0,
                "detail": f["detail"],
            }
        )
    report.sort(key=lambda r: (-r["weighted_severity"], r["rule"]))

    over = max(0, len(requests) - budget)
    return {
        "page": page,
        "settled": len(settled),
        "abstained": len(abstained),
        "discharged": discharged,
        "queued": len(queue),
        "report": report,
        "requests": requests[:budget],
        "dropped_over_budget": over,
        "visual_tokens": sum(r["visual_tokens"] for r in requests[:budget]),
    }


def cut_crops(corpus: pathlib.Path, plan: dict, suffix: str) -> int:
    """Write the crops the plan asked for, from the capture that already happened.

    Cropping rather than downscaling is the single largest measured lever in this
    pipeline -- larger than every model upgrade combined -- and it is free, because
    the pixels are already on disk.
    """
    outdir = corpus / "crops"
    outdir.mkdir(exist_ok=True)
    written = 0
    for page, cell in plan["pages"].items():
        png = corpus / "shots" / f"{page}{suffix}.png"
        if not png.exists():
            continue
        img = Image.open(png)
        scale = img.width / cell["page_w"]
        for i, req in enumerate(cell["requests"]):
            if req["kind"] != "crop":
                continue
            r = req["rect"]
            box = tuple(
                int(round(v * scale))
                for v in (r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])
            )
            path = outdir / f"{page}.{i:02d}.{req['rule']}.png"
            img.crop(box).save(path)
            req["crop"] = str(path.relative_to(corpus))
            written += 1
    return written


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", default="corpus/out", type=pathlib.Path)
    ap.add_argument("--app", default="bench")
    ap.add_argument("--shot", default="@1.5x")
    ap.add_argument(
        "--no-discharge",
        action="store_true",
        help="keep every abstention in the queue even where the cross-check "
        "already answered it. The counterfactual: run it against the default to "
        "measure what the cross-check is worth, in model calls not saved.",
    )
    a = ap.parse_args()
    corpus = a.corpus.resolve()
    prof = load_profile(pathlib.Path(__file__).resolve().parent, a.app)
    prof["discharge"] = not a.no_discharge

    dom = json.loads((corpus / "findings_dom.json").read_text())
    xchk = json.loads((corpus / "findings_xcheck.json").read_text())
    # The control's own findings are not this page's news. Subtracting them here
    # rather than in each detector keeps the baseline one decision in one place.
    base = {
        (f["rule"], f["target"], f["detail"])
        for f in dom.get("clean", []) + xchk.get("clean", [])
    }

    def novel(fs):
        return [f for f in fs if (f["rule"], f["target"], f["detail"]) not in base]

    pages = {}
    for page in sorted(dom):
        snap_file = corpus / "snapshots" / f"{page}.json"
        if not snap_file.exists():
            continue
        snap = json.loads(snap_file.read_text())
        cell = route_page(page, novel(dom[page]), novel(xchk.get(page, [])), snap, prof)
        cell["page_w"] = snap["scroll"]["w"]
        cell["page_h"] = snap["scroll"]["h"]
        pages[page] = cell

    plan = {
        "app": prof["app"],
        "character": prof["character"],
        "shot": a.shot or "@1x",
        "weights": prof.get("weights", {}),
        "correctness_floor": sorted(prof["correctness_floor"]),
        "discharge_enabled": prof["discharge"],
        "pages": pages,
    }
    n_crops = cut_crops(corpus, plan, a.shot)
    (corpus / "route_plan.json").write_text(json.dumps(plan, indent=1))

    tot_abst = sum(p["abstained"] for p in pages.values())
    tot_disc = sum(len(p["discharged"]) for p in pages.values())
    tot_q = sum(p["queued"] for p in pages.values())
    tot_settled = sum(p["settled"] for p in pages.values())
    gestalt = sum(
        1 for p in pages.values() for r in p["requests"] if r["kind"] == "gestalt"
    )
    print(f"ROUTE  app={prof['app']}  ({prof['character']})")
    print(
        f"  {len(pages)} pages, {tot_settled} settled finding(s) -- never shown to a model"
    )
    print(f"  abstentions            {tot_abst}")
    print(f"  discharged by xcheck   {tot_disc}   <- these never become a model call")
    print(f"  cropped VLM queue      {tot_q}  ({n_crops} crop file(s) written)")
    print(f"  gestalt calls          {gestalt}  (1/page, no rule reaches these)")
    print(f"  visual tokens          {sum(p['visual_tokens'] for p in pages.values())}")
    for page, p in pages.items():
        if not p["requests"] and not p["discharged"]:
            continue
        bits = [f"{r['kind']}:{r['rule'] or 'whole-page'}" for r in p["requests"]]
        disc = (
            f"  discharged={[d['rule'] for d in p['discharged']]}"
            if p["discharged"]
            else ""
        )
        print(f"    {page:24} {', '.join(bits)}{disc}")


if __name__ == "__main__":
    main()
