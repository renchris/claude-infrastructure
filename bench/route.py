#!/usr/bin/env python3
"""The abstention router: decide what the deterministic pass could NOT answer, and
turn exactly that into a cropped queue for the vision layer.

The seam this implements is the whole architecture in one sentence. The
deterministic layer's most valuable output is not a finding, it is an ABSTENTION
-- `cannot compute a ratio, the backdrop is a gradient; 4.5:1 is UNVERIFIED here`
rather than a pass. Every silent pass that should have been an abstention is a
defect shipped, and the abstention set is exactly the vision layer's job queue.
It is also small, which is what makes the vision spend affordable at all.

FOUR THINGS THIS DOES, in order, and the third is the one that saves the money:

  1. SUBTRACT THE CONTROL. By the full claim, never by (rule, target): keying on
     location alone once swallowed a real colour-token drift because an unrelated
     finding already sat on that element in the baseline.

  2. SPLIT ASSERT FROM ABSTAIN, by the taxonomy in `rules.py` rather than by
     reading detail strings. Assertions are terminal and never reach a model.

  3. DISCHARGE. An abstention is not automatically a model call. Where a cheaper
     layer already answered the same question about the same element, the
     abstention is spent. The gradient is the worked example: the DOM abstains on
     contrast, and the pixel cross-check answers it with two numbers and no model
     at all, so it leaves the queue entirely rather than being paid for twice.

  4. COLLAPSE, CROP, AND COST IT. What survives is grouped by class, clustered so
     one crop covers neighbours without swelling to the whole page, cut from the
     highest-resolution capture available, and priced in image tokens with the
     patch formula ceil(w/28) x ceil(h/28). Crop and zoom rather than downscale --
     that lever moved a grounding benchmark 18.9% -> 48.1% with no model change,
     more than every model upgrade in the field combined.

WHAT THIS IS NOT. It does not call a model, and it does not gate: it writes a
queue and exits 0 whatever it finds. The June 2026 campaign ratified that taste
stays human and the VLM's sanctioned role is advisory triage, never a CI gate, so
there is deliberately no exit code here for a build to read. It also never opens a
browser and never computes a distance from anything a model drew -- every rect in
the queue comes from `getBoundingClientRect` via the snapshot.

Per-app weighting comes from `profiles.json`: one harness, three different
problems. A weight orders the report and sizes the gestalt budget; it never
decides whether a rule fires, and a suppressed class is always reported as
suppressed.

Usage: python3 route.py <corpus-dir> [--profile <name>] [--no-crops]
"""

from __future__ import annotations

import argparse
import collections
import json
import math
import pathlib
import sys

from PIL import Image

import rules

HERE = pathlib.Path(__file__).resolve().parent
PATCH = 28  # image-token patch edge; tokens = ceil(w/28) * ceil(h/28)
CROP_PAD = 24  # CSS px of context around a cropped region
MAX_CROP_GROWTH = 2.5  # a merged crop may not exceed this multiple of its parts
GESTALT_QUESTION = (
    "Does this page make sense at a glance? Where does the eye land first, and is "
    "that the thing the page is for? Is the visually heaviest element the most "
    "important one? Report nothing with a number in it -- spacing, sizes, ratios "
    "and offsets are measured elsewhere and your estimate of one would be wrong."
)
PROHIBITION = (
    "This crop is for judgement only. Do not report any distance, size, ratio or "
    "coordinate from it: every number about this region is already known exactly "
    "from the DOM, and a number read off pixels can only be worse. Say what is "
    "wrong, not how far."
)


def load_profile(name: str) -> tuple[dict, dict]:
    cfg = json.loads((HERE / "profiles.json").read_text())
    profs = cfg["profiles"]
    if name not in profs:
        sys.exit(f"unknown profile {name!r}; have: {', '.join(sorted(profs))}")
    return profs[name], cfg["severity_scale"]


def union(rects: list[dict]) -> dict:
    return {
        "x": min(r["x"] for r in rects),
        "y": min(r["y"] for r in rects),
        "right": max(r["right"] for r in rects),
        "bottom": max(r["bottom"] for r in rects),
    }


def area(r: dict) -> float:
    return max(0.0, r["right"] - r["x"]) * max(0.0, r["bottom"] - r["y"])


def cluster(rects: list[dict]) -> list[list[int]]:
    """Greedily merge regions whose union stays close to the sum of its parts.

    Collapsing a class to ONE crop is right when its members sit together and
    wrong when they are at opposite ends of the page -- there the union is the
    whole page, which is not a crop, and the crop is the entire reason the vision
    spend is affordable. The growth bound is the test, and it is stated rather
    than tuned: a merge that more than doubles the ink-to-frame ratio has stopped
    being a crop of anything.
    """
    groups: list[list[int]] = []
    for i, r in enumerate(rects):
        for g in groups:
            members = [rects[j] for j in g] + [r]
            if area(union(members)) <= MAX_CROP_GROWTH * sum(area(m) for m in members):
                g.append(i)
                break
        else:
            groups.append([i])
    return groups


def tokens_for(w: int, h: int) -> int:
    return math.ceil(w / PATCH) * math.ceil(h / PATCH)


def best_shot(shots: pathlib.Path, stem: str) -> tuple[pathlib.Path | None, float]:
    """The highest-resolution capture of this page. Downsampling before a model
    call inherits the old score whatever model is bought, so the router picks the
    largest artifact rather than the default one."""
    best, px = None, 0
    for p in shots.glob(f"{stem}*.png"):
        with Image.open(p) as im:
            if im.width > px:
                best, px = p, im.width
    return best, px


def cut(shot: pathlib.Path, rect: dict, scale: float, out: pathlib.Path) -> dict:
    with Image.open(shot) as im:
        box = (
            max(0, int((rect["x"] - CROP_PAD) * scale)),
            max(0, int((rect["y"] - CROP_PAD) * scale)),
            min(im.width, int((rect["right"] + CROP_PAD) * scale)),
            min(im.height, int((rect["bottom"] + CROP_PAD) * scale)),
        )
        crop = im.crop(box)
        out.parent.mkdir(parents=True, exist_ok=True)
        crop.save(out)
        return {
            "path": str(out.relative_to(out.parent.parent)),
            "px": [crop.width, crop.height],
            "image_tokens": tokens_for(crop.width, crop.height),
            "from": shot.name,
        }


def route(
    corpus: pathlib.Path, profile_name: str, crops: bool, discharge: bool = True
) -> dict:
    prof, sev_scale = load_profile(profile_name)
    weights = prof.get("class_weights", {})
    dom = json.loads((corpus / "findings_dom.json").read_text())
    xck = json.loads((corpus / "findings_xcheck.json").read_text())
    snaps, shots = corpus / "snapshots", corpus / "shots"

    per_page = {k: list(dom.get(k, [])) + list(xck.get(k, [])) for k in dom | xck}
    base = {(c["rule"], c["target"], c["detail"]) for c in per_page.get("clean", [])}

    report, suppressed, queue = [], collections.Counter(), []
    discharged, stats = [], collections.Counter()

    for page in sorted(per_page):
        if page == "clean":
            continue
        snap_file = snaps / f"{page}.json"
        if not snap_file.exists():
            continue
        snap = json.loads(snap_file.read_text())
        rect_of = {e["path"]: e["rect"] for e in snap["elements"]}
        shot, px = best_shot(shots, page)
        scale = (px / snap["scroll"]["w"]) if px else 1.0

        novel = [
            f
            for f in per_page[page]
            if (f["rule"], f["target"], f["detail"]) not in base
        ]
        stats["findings"] += len(novel)
        asserts = [f for f in novel if rules.rule(f["rule"]).kind == rules.ASSERT]
        abstains = [f for f in novel if rules.rule(f["rule"]).kind == rules.ABSTAIN]
        stats["asserted"] += len(asserts)

        # --- 3. discharge -------------------------------------------------
        answered = {(f["target"], f["rule"]) for f in asserts}
        live = []
        for f in abstains:
            by = (
                rules.DISCHARGES.get(f["rule"], frozenset())
                if discharge
                else frozenset()
            )
            hit = next((t for t, r in answered if t == f["target"] and r in by), None)
            if hit is not None:
                rule_hit = next(r for t, r in answered if t == hit and r in by)
                discharged.append(
                    {
                        "page": page,
                        "target": f["target"],
                        "abstention": f["rule"],
                        "discharged_by": rule_hit,
                    }
                )
                stats["discharged"] += 1
            else:
                live.append(f)

        # --- report body, weighted ----------------------------------------
        for f in asserts:
            klass = rules.rule(f["rule"]).klass
            w = weights.get(klass, 1.0)
            if w == 0:
                suppressed[klass] += 1
                continue
            report.append(
                {
                    "page": page,
                    "rule": f["rule"],
                    "klass": klass,
                    "target": f["target"],
                    "detail": f["detail"],
                    "severity": f["severity"],
                    "rank": round(w * sev_scale.get(f["severity"], 2), 3),
                }
            )

        # --- 4. collapse by class, cluster, crop --------------------------
        by_class: dict[str, list[dict]] = collections.defaultdict(list)
        for f in live:
            by_class[rules.rule(f["rule"]).klass].append(f)
        for klass, group in sorted(by_class.items()):
            w = weights.get(klass, 1.0)
            known = [f for f in group if f["target"] in rect_of]
            stats["no_rect"] += len(group) - len(known)
            if not known:
                continue
            rects = [rect_of[f["target"]] for f in known]
            for idx in cluster(rects):
                members = [known[i] for i in idx]
                box = union([rects[i] for i in idx])
                item = {
                    "page": page,
                    "kind": "abstention",
                    "klass": klass,
                    "rules": sorted({m["rule"] for m in members}),
                    "targets": [m["target"] for m in members],
                    "question": rules.rule(members[0]["rule"]).question,
                    "prohibition": PROHIBITION,
                    "region": box,
                    "rank": round(
                        w * max(sev_scale.get(m["severity"], 2) for m in members), 3
                    ),
                }
                if crops and shot:
                    item["crop"] = cut(
                        shot,
                        box,
                        scale,
                        corpus / "crops" / f"{page}-{klass}-{idx[0]}.png",
                    )
                queue.append(item)

    # --- gestalt: the classes no rule may claim ---------------------------
    #
    # Spend the scarce judgement calls on the RESIDUE -- the pages the cheap
    # layers had least to say about. A page carrying six asserted findings has
    # already been described; a page carrying none is either fine or hiding
    # something no rule can reach, and only one of those is worth a model call.
    #
    # The honest limit, stated because it would otherwise read as targeting: a
    # judgement-only defect is BY CONSTRUCTION invisible to any ranking a rule can
    # compute, so this orders a SWEEP, it does not aim one. In this corpus the
    # hierarchy-inversion page carries two asserted findings -- side effects of the
    # same CSS -- so residue ranking pushes it DOWN, and a budget under 12 can miss
    # the one page that needed the call. That is a property of budgets, not a bug
    # in the ranking, and it is why the skipped pages are named below rather than
    # counted.
    g = prof.get("gestalt", {})
    skipped: list[str] = []
    asserted_per_page = collections.Counter(f["page"] for f in report)
    pages = sorted(
        (p for p in per_page if p != "clean"), key=lambda p: (asserted_per_page[p], p)
    )
    if g.get("enabled"):
        budget = int(g.get("budget_per_run", 0))
        for page in pages[:budget]:
            shot, px = best_shot(shots, page)
            item = {
                "page": page,
                "kind": "gestalt",
                "klass": "|".join(sorted(rules.JUDGEMENT_ONLY)),
                "rules": [],
                "targets": ["<page>"],
                "question": GESTALT_QUESTION,
                "prohibition": PROHIBITION,
                "region": None,
                "rank": round(
                    weights.get(next(iter(rules.JUDGEMENT_ONLY)), 1.0) * 3, 3
                ),
            }
            if shot:
                with Image.open(shot) as im:
                    item["crop"] = {
                        "path": f"shots/{shot.name}",
                        "px": [im.width, im.height],
                        "image_tokens": tokens_for(im.width, im.height),
                        "from": shot.name,
                    }
            queue.append(item)
        skipped = pages[budget:]

    report.sort(key=lambda f: (-f["rank"], f["page"], f["rule"]))
    queue.sort(key=lambda q: (-q["rank"], q["page"], q["klass"]))
    return {
        "profile": profile_name,
        "profile_label": prof.get("label", ""),
        "report": report,
        "suppressed_by_weight_zero": dict(suppressed),
        "discharged": discharged,
        "queue": queue,
        "budget": {
            "findings_after_control": stats["findings"],
            "asserted_no_model_call": stats["asserted"],
            "abstentions_discharged": stats["discharged"],
            "queued": len(queue),
            "image_tokens": sum(
                q.get("crop", {}).get("image_tokens", 0) for q in queue
            ),
            "abstentions_without_a_rect": stats["no_rect"],
            "gestalt_pages_not_queued": skipped,
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path, nargs="?", default="corpus/out")
    ap.add_argument("--profile", default="default")
    ap.add_argument("--no-crops", action="store_true")
    ap.add_argument(
        "--no-discharge",
        action="store_true",
        help="queue every abstention, including ones a cheaper layer already "
        "answered. The counterfactual: run it against the default to see exactly "
        "what the cross-check is saving, in calls and in image tokens.",
    )
    a = ap.parse_args()
    corpus = pathlib.Path(a.corpus).resolve()
    r = route(corpus, a.profile, not a.no_crops, not a.no_discharge)
    b = r["budget"]

    print(f"ROUTE   profile {r['profile']} ({r['profile_label']})\n")
    print(f"  {b['findings_after_control']:3d} findings after subtracting the control")
    print(f"  {b['asserted_no_model_call']:3d} asserted -- terminal, no model call")
    print(
        f"  {b['abstentions_discharged']:3d} abstention(s) discharged by a cheaper layer"
    )
    for d in r["discharged"]:
        print(
            f"        {d['page']}: {d['abstention']} on {d['target'].split(' > ')[-1]} "
            f"answered by {d['discharged_by']}"
        )
    print(
        f"  {b['queued']:3d} queued for the vision layer, {b['image_tokens']} image tokens\n"
    )

    for q in r["queue"]:
        where = (
            "whole page"
            if q["region"] is None
            else (
                f"{q['region']['right'] - q['region']['x']:.0f}x"
                f"{q['region']['bottom'] - q['region']['y']:.0f}px at "
                f"{q['region']['x']:.0f},{q['region']['y']:.0f}"
            )
        )
        px = q.get("crop", {}).get("px")
        cost = q.get("crop", {}).get("image_tokens", 0)
        print(
            f"  [{q['rank']:5.1f}] {q['page']:22} {q['kind']:10} {q['klass']:18} "
            f"{where}  {'x'.join(map(str, px)) if px else '-':>11}  {cost:>5} tok"
        )
        for t in q["targets"][:3]:
            print(f"            -> {t}")

    if r["suppressed_by_weight_zero"]:
        print("\n  SUPPRESSED at weight 0 by this profile (found, not shown):")
        for k, n in sorted(r["suppressed_by_weight_zero"].items()):
            print(f"    {k:24} {n} finding(s)")
    if b["gestalt_pages_not_queued"]:
        spent = sum(1 for q in r["queue"] if q["kind"] == "gestalt")
        skipped = b["gestalt_pages_not_queued"]
        print(
            f"\n  GESTALT BUDGET {spent} of {spent + len(skipped)} candidate page(s). "
            f"NOT reviewed for hierarchy, and NAMED rather than counted because a "
            f"judgement defect is invisible to the ranking that skipped them:"
        )
        for p in skipped:
            print(f"    {p}")
    if b["abstentions_without_a_rect"]:
        print(
            f"\n  {b['abstentions_without_a_rect']} abstention(s) had no rect in the "
            "snapshot and could not be cropped."
        )

    print(f"\n  top of the weighted report ({len(r['report'])} findings):")
    for f in r["report"][:6]:
        print(
            f"    [{f['rank']:5.1f}] {f['page']:22} {f['rule']:24} {f['detail'][:64]}"
        )

    (corpus / "queue.json").write_text(json.dumps(r, indent=1))
    print(f"\n  -> {corpus / 'queue.json'}")
    return 0  # advisory by construction: taste stays human, this never gates


if __name__ == "__main__":
    sys.exit(main())
