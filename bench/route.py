#!/usr/bin/env python3
"""The abstention router: decide what a vision model is asked, and what it is not.

The deterministic layer's most valuable output is not a finding, it is an
ABSTENTION. `detect_dom` returns `contrast-indeterminate` -- "cannot compute a
ratio, the backdrop is a gradient; 4.5:1 is UNVERIFIED for this text" -- rather
than a pass, and every silent pass that should have been an abstention is a
defect shipped. This stage is what makes that worth something: the abstention set
is exactly the vision layer's job queue, and it is small, which is what makes the
vision spend affordable at all.

It reads a captured corpus directory and writes a decision record. It never opens
a browser, never calls a model, and never adjudicates anything.

--------------------------------------------------------------------------------
Five triggers, and only five
--------------------------------------------------------------------------------
  T1  INDETERMINATE residue -- abstentions the free cross-check could NOT close,
      collapsed by class. On this corpus that is ZERO: `detect_xcheck` turns the
      gradient's "unrepresentable" into 4.81:1 at the left edge and 1.38:1 at the
      right, a full verdict, for no model call at all.
  T2  the six unscreenable classes, once per page, unconditional. Never cut for
      budget: three of the corpus's most valuable findings came from exactly this
      call, on a clean image, with nobody looking for them. Cutting it converts
      the reviewer into a linter with a screenshot.
  T3  explicit operator request (`--ask`). Budget-exempt, recorded as such so a
      later audit can separate operator-driven spend from autonomous spend.
  T4  arbitration -- the judge contradicts a DOM finding. Not reachable here: it
      is second-order and no judgement exists in this directory. Recorded as
      unreachable-with-a-reason rather than omitted.
  T5  no-DOM subjects (canvas, WebGL, PDF comps). Not reachable on this corpus.

🚨 THE T1 SUBTRACTION IS CODE, NOT DISCIPLINE, AND IT IS GATED ON THE CROSS-CHECK
FILE EXISTING. New rules add new abstentions and nobody re-runs a subtraction by
hand. And the gate matters in the direction that looks wrong: if the cross-check
is DOWN, an empty findings file resolves nothing and *looks exactly like nothing
needed resolving*, so a missing file must make T1 GROW. It is the one case where
a larger model queue is the correct response to a layer failure.

--------------------------------------------------------------------------------
The NEVER list, enforced rather than documented
--------------------------------------------------------------------------------
> If the answer has a number in it, the model does not get the question.

Distances, gaps, sizes, ratios, contrast (solid OR gradient), token membership,
animation timing, bounding boxes for anything, and any score/grade/ranking are
settled elsewhere for free and exactly. `assert_never_list` runs over every ask
this stage emits and exits non-zero if one is routed -- a list that is only prose
is a list that drifts, and the failure is silent because a model asked for a
number it cannot see does not refuse, it invents one.

Usage:
  python3 route.py <corpus-dir> [--profile NAME] [--page STEM] [--ask "Q"] [--crops]
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from detect_dom import Page  # noqa: E402  (same directory, deliberate)

PROFILES_PATH = pathlib.Path(__file__).resolve().parent / "profiles.json"

# --- The crop envelope. All three must hold; the binding one is not the famous
# one. Solving ceil(n/28)^2 <= 4784 gives ceil(n/28) <= 69, so n <= 1932 px
# raster = 966x966 CSS at DPR 2 -- NOT the round 1000x1000, which is 5,184 tokens
# and over the tier, so the API resizes on top of the client clamp and the crop
# you paid for is not the crop the model sees.
CLAMP_PX = 2000  # client clamp: over it, images are rejected/quantised silently
TOKEN_TIER = 4784  # high-resolution visual-token tier
PATCH = 28  # image tokens are patch-based: ceil(w/28) * ceil(h/28)
BYTES_MAX = 3_932_160  # over it, PNG is re-encoded palette:true = <=256 colours

# Anything whose answer is a number. Routing one of these spends ~1,600 tokens to
# re-ask a question that getBoundingClientRect already answered exactly, for free.
# These are the literal `detect_dom` rule names plus the generic categories, so
# the assertion trips on the realistic mistake: wiring a rule straight through to
# a model as though its name were a question.
NEVER_ROUTE = {
    "contrast",
    "spacing-rhythm",
    "grid-violation",
    "type-scale",
    "token-drift",
    "misalignment",
    "touch-target",
    "overflow",
    "animation-timing",
    "bounding-box",
    "distance",
    "gap",
    "size",
    "ratio",
    "score",
    "grade",
    "ranking",
}

# An abstention is not itself a question a model can answer -- `contrast-
# indeterminate` names a computation that FAILED, and handing a model the name of
# a failed computation invites it to complete the computation, which is precisely
# the number it must never be asked for. So every routable abstention maps to the
# PERCEPTUAL class actually asked, and a rule with no mapping is a hard refusal
# rather than a rule name forwarded verbatim.
ASK_FOR_RULE = {
    # "is this text legible across its whole width against what is behind it" is
    # a judgement with no number in the answer. "What is the ratio" is the same
    # question with a number in it, and it is settled by the cross-check for free.
    "contrast-indeterminate": "readability",
}


def load_profiles() -> dict:
    return json.loads(PROFILES_PATH.read_text())


def resolve_profile(profiles: dict, name: str) -> dict:
    if name not in profiles["profiles"]:
        sys.exit(
            f"unknown profile {name!r}; have {sorted(profiles['profiles'])}\n"
            "A profile is a routing policy, not a default -- picking one silently "
            "would weight this run as some app it is not."
        )
    merged = dict(profiles["defaults"])
    merged.update({k: v for k, v in profiles["profiles"][name].items()})
    merged["name"] = name
    return merged


def visual_tokens(w: int, h: int) -> int:
    return math.ceil(w / PATCH) * math.ceil(h / PATCH)


def admissible(w_raster: int, h_raster: int, nbytes: int | None = None) -> tuple:
    """-> (ok, reason). Every rejection names which of the three ceilings bound."""
    if w_raster > CLAMP_PX or h_raster > CLAMP_PX:
        return False, f"over the {CLAMP_PX}px client clamp ({w_raster}x{h_raster})"
    vt = visual_tokens(w_raster, h_raster)
    if vt > TOKEN_TIER:
        return False, f"{vt} visual tokens over the {TOKEN_TIER} tier"
    if nbytes is not None and nbytes > BYTES_MAX:
        return False, f"{nbytes} bytes over {BYTES_MAX}; PNG would be quantised"
    return True, "ok"


def pick_global_image(shots: pathlib.Path, stem: str) -> dict | None:
    """The largest admissible capture of the whole frame.

    Largest, because a downsample is inherited: pin the high-resolution tier and
    the pixels are there; downsample first and no model purchase gets them back.
    Admissible, because over the clamp the client quantises to 256 colours
    WITHOUT telling the session -- and a colour question routed onto a quantised
    image is unanswerable and reads answerable.
    """
    from PIL import Image

    best = None
    for png in sorted(shots.glob(f"{stem}.png")) + sorted(shots.glob(f"{stem}@*.png")):
        w, h = Image.open(png).size
        ok, why = admissible(w, h, png.stat().st_size)
        if not ok:
            continue
        vt = visual_tokens(w, h)
        if best is None or vt > best["visual_tokens"]:
            best = {
                "image": png.name,
                "raster": [w, h],
                "visual_tokens": vt,
                "bytes": png.stat().st_size,
            }
    return best


def backdrop_signature(pg: Page, el: dict) -> str:
    """Collapse key: WHICH backdrop could not be resolved, not which text run.

    95 abstentions are not 95 questions. One gradient behind a hero is ONE class
    however many text runs sit on it, and one crop answers a class. Routing
    subjects instead of classes is what turns an affordable queue into a budget
    overrun that then silently drops most of it -- converting honest abstentions
    back into silent passes, which is the exact failure the abstention exists to
    prevent.
    """
    cur = el
    depth = 0
    while cur is not None and depth < 12:
        img = (cur["styles"].get("background-image") or "none").strip()
        if img != "none":
            return f"{cur['path']}|{img[:80]}"
        cur = pg.parent_of(cur)
        depth += 1
    return f"{el['path']}|unresolved"


def cluster(boxes: list[dict], gap_px: float) -> list[dict]:
    """Merge boxes within gap_px. Two findings closer than 32 CSS px are almost
    always inside one visual group, and splitting a group across two crops asks
    the model to judge grouping with the group cut in half."""
    out: list[dict] = []
    for b in sorted(boxes, key=lambda r: (r["y"], r["x"])):
        for c in out:
            near_x = b["x"] - gap_px <= c["right"] and c["x"] - gap_px <= b["right"]
            near_y = b["y"] - gap_px <= c["bottom"] and c["y"] - gap_px <= b["bottom"]
            if near_x and near_y:
                c["x"] = min(c["x"], b["x"])
                c["y"] = min(c["y"], b["y"])
                c["right"] = max(c["right"], b["right"])
                c["bottom"] = max(c["bottom"], b["bottom"])
                c["members"].extend(b["members"])
                break
        else:
            out.append(dict(b, members=list(b["members"])))
    return out


def new_ledger(ceiling: int) -> dict:
    return {
        "ceiling": ceiling,
        "contexts": [{"index": 0, "spent": 0, "entries": []}],
        "splits": [],
    }


def spend(ledger: dict, stem: str, call: dict) -> None:
    """Charge one image block, splitting the review across contexts when full.

    A Claude Code session re-sends its whole conversation on every turn, so an
    image Read on turn 3 is still an image block in the request built on turn 14:
    the >20-block cliff is cumulative over the SESSION, not per call, and it
    fails by REJECTION rather than degradation -- you cannot un-send an image.
    The ceiling is 12, and the 8 blocks of headroom are sized to the consumer,
    which is an agent that will take its own before/after screenshots while
    fixing what this review found.

    On exhaustion the response is neither dropping the T2 call nor downgrading
    the image. Dropping T2 makes the reviewer a linter with a screenshot;
    downgrading is the fail-safe-mimics-healthy trap, because a quantised
    screenshot produces a review that reads exactly like a good one. So the run
    SPLITS: the remaining pages go to a fresh context with its own ledger, and
    the boundary is recorded so the split is a fact rather than an intention.

    T3 alone is exempt -- an operator who asked for a specific look has already
    decided it is worth the block.
    """
    if call.get("budget_exempt"):
        call["deliverable"] = True
        call["context"] = ledger["contexts"][-1]["index"]
        return
    ctx = ledger["contexts"][-1]
    if ctx["spent"] + 1 > ledger["ceiling"]:
        ledger["splits"].append(
            {"before_page": stem, "reason": "image ledger exhausted", "at": call["id"]}
        )
        ctx = {"index": ctx["index"] + 1, "spent": 0, "entries": []}
        ledger["contexts"].append(ctx)
    ctx["spent"] += 1
    ctx["entries"].append({"page": stem, "id": call["id"], "kind": call["kind"]})
    call["deliverable"] = True
    call["context"] = ctx["index"]


def route_page(
    stem: str, corpus: pathlib.Path, prof: dict, ledger: dict, explicit: str | None
) -> dict:
    snap = json.loads((corpus / "snapshots" / f"{stem}.json").read_text())
    pg = Page(snap)
    dom = json.loads((corpus / "findings_dom.json").read_text()).get(stem, [])

    # --- The subtraction, gated on the file EXISTING (see the module docstring) --
    xpath = corpus / "findings_xcheck.json"
    xcheck_up = xpath.exists()
    xres = (
        {f["target"] for f in json.loads(xpath.read_text()).get(stem, [])}
        if xcheck_up
        else set()
    )

    abstentions = [f for f in dom if f["rule"].endswith("-indeterminate")]
    t1 = [f for f in abstentions if f["target"] not in xres]

    # --- T1: collapse subjects into classes -----------------------------------
    classes: dict[str, dict] = {}
    for f in t1:
        el = pg.by_path.get(f["target"])
        if el is None:
            continue
        key = f"{f['rule']}::{backdrop_signature(pg, el)}"
        w = prof["severity_weight"].get(f.get("severity", "medium"), 1.0)
        w *= prof["rule_weight"].get(f["rule"], 1.0)
        c = classes.setdefault(
            key,
            {
                "class_key": key,
                "rule": f["rule"],
                "subjects": [],
                "weight": 0.0,
                "x": el["rect"]["x"],
                "y": el["rect"]["y"],
                "right": el["rect"]["right"],
                "bottom": el["rect"]["bottom"],
                "members": [],
            },
        )
        c["subjects"].append(f["target"])
        c["members"].append(key)
        c["weight"] += w
        c["x"] = min(c["x"], el["rect"]["x"])
        c["y"] = min(c["y"], el["rect"]["y"])
        c["right"] = max(c["right"], el["rect"]["right"])
        c["bottom"] = max(c["bottom"], el["rect"]["bottom"])

    calls: list[dict] = []
    unrouted: list[dict] = []

    # --- T2: one global call, unconditional -----------------------------------
    gi = pick_global_image(corpus / "shots", stem)
    if gi is None:
        unrouted.append(
            {"kind": "global", "why": "no admissible full-frame capture", "class": "T2"}
        )
    else:
        calls.append(
            {
                "id": "C1",
                "trigger": "T2",
                "kind": "global",
                "budget_exempt": False,
                "asks": list(prof["t2_emphasis"]),
                **gi,
            }
        )

    # --- Region calls: only T1 (and T4, which is unreachable here) -------------
    def ask_for(rule: str) -> str:
        if rule not in ASK_FOR_RULE:
            sys.exit(
                f"refusing: abstention rule {rule!r} has no perceptual ask mapped.\n"
                "Forwarding a rule name as a question is how a numeric question "
                "reaches a model -- add it to ASK_FOR_RULE deliberately."
            )
        return ASK_FOR_RULE[rule]

    def fold_into_global(c: dict, why: str) -> None:
        """A question that cannot get its own crop is still asked, on the global
        image, and the loss is recorded. The crop buys ISOLATION, not the right
        to ask -- so dropping the question because the crop did not fit would
        convert an honest abstention back into a silent pass, which is the one
        outcome the abstention exists to prevent."""
        unrouted.append(
            {
                "kind": "region",
                "why": why,
                "class": c["class_key"],
                "disposition": "folded into the global call",
            }
        )
        if calls and calls[0]["kind"] == "global":
            ask = ask_for(c["rule"])
            if ask not in calls[0]["asks"]:
                calls[0]["asks"].append(ask)
            calls[0].setdefault("folded_in", []).append(c["class_key"])

    room = max(0, prof["per_page_max"] - len(calls))
    picked = sorted(
        cluster(list(classes.values()), prof["gap_px"]), key=lambda c: -c["weight"]
    )
    for i, c in enumerate(picked):
        if room <= 0:
            fold_into_global(c, "budget")
            continue
        bleed = prof["bleed_px"]
        box = [
            max(0.0, c["x"] - bleed),
            max(0.0, c["y"] - bleed),
            c["right"] - c["x"] + 2 * bleed,
            c["bottom"] - c["y"] + 2 * bleed,
        ]
        wr, hr = round(box[2] * 2), round(box[3] * 2)  # DPR 2
        ok, why = admissible(wr, hr)
        if not ok:
            # Never ship a crop the model will silently receive at a different
            # size than the one planned: over the clamp it is quantised or
            # rejected, and a review run on a quantised image reads exactly like
            # a good one.
            fold_into_global(c, f"not lossless: {why}")
            continue
        calls.append(
            {
                "id": f"C{len(calls) + 1}",
                "trigger": "T1",
                "kind": "region",
                "budget_exempt": False,
                "css_box": [round(v, 2) for v in box],
                "raster": [wr, hr],
                "visual_tokens": visual_tokens(wr, hr),
                "from": c["subjects"],
                "asks": [ask_for(c["rule"])],
                "abstention_rule": c["rule"],
                "region_label": f"region c{i + 1:02d}",
            }
        )
        room -= 1

    # --- T3: explicit, budget-exempt ------------------------------------------
    if explicit:
        calls.append(
            {
                "id": f"C{len(calls) + 1}",
                "trigger": "T3",
                "kind": "explicit",
                "budget_exempt": True,
                "asks": [explicit],
                "image": gi["image"] if gi else None,
            }
        )

    for c in calls:
        spend(ledger, stem, c)

    return {
        "page": stem,
        "settled": len(dom) - len(t1),
        "abstentions": len(abstentions),
        "abstentions_closed_by_xcheck": len(abstentions) - len(t1),
        "t1_subjects": len(t1),
        "t1_classes": len(classes),
        "cross_check": "up" if xcheck_up else "DOWN -- nothing subtracted, T1 grows",
        "calls": calls,
        "unrouted": unrouted,
        "coverage": {
            "dom": "complete",
            "pixel": "complete" if xcheck_up else "absent",
            "judgement": "planned",
            # Print the deficit. An unanswered question must be visible as
            # unanswered, not absent -- a dropped abstention routes nowhere, and
            # that is indistinguishable from a pass in every downstream report.
            "subjects": len(abstentions),
            "classes": len(classes),
            "adjudicated_own_crop": sum(1 for c in calls if c["trigger"] == "T1"),
            "folded_into_global": sum(1 for u in unrouted if u.get("disposition")),
            "unadjudicated_by_budget": sum(
                1 for u in unrouted if u["why"] == "budget" and not u.get("disposition")
            ),
        },
    }


def assert_never_list(plan: dict) -> list[str]:
    """If the answer has a number in it, the model does not get the question."""
    bad = []
    for page in plan["pages"]:
        for call in page["calls"]:
            if call["trigger"] == "T3":
                continue  # operator-authored and budget-exempt by ruling
            for ask in call["asks"]:
                if ask in NEVER_ROUTE:
                    bad.append(f"{page['page']}/{call['id']}: {ask}")
    return bad


def write_crops(corpus: pathlib.Path, plan: dict) -> int:
    """Cut region crops from the SAME raster the global shot came off.

    In production this belongs to the capture stage, which must re-clip inside
    its original browser pass: a crop from a second navigation is a different
    frame, and two images from different frames cannot be argued against each
    other. Here the crop is taken from the already-captured PNG, which is that
    same frame by construction -- the property is what matters, not the stage.
    """
    from PIL import Image

    clip = corpus / "clip"
    clip.mkdir(exist_ok=True)
    n = 0
    for page in plan["pages"]:
        src = None
        for call in page["calls"]:
            if call["kind"] == "global":
                src = corpus / "shots" / call["image"]
        for call in page["calls"]:
            if call["kind"] != "region" or src is None:
                continue
            img = Image.open(src)
            sx = (
                img.size[0]
                / json.loads(
                    (corpus / "snapshots" / f"{page['page']}.json").read_text()
                )["scroll"]["w"]
            )
            x, y, w, h = call["css_box"]
            box = (
                round(x * sx),
                round(y * sx),
                round((x + w) * sx),
                round((y + h) * sx),
            )
            out = clip / f"{page['page']}.{call['id']}.png"
            img.crop(box).save(out)
            call["image"] = f"clip/{out.name}"
            call["bytes"] = out.stat().st_size
            n += 1
    return n


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path, nargs="?", default="corpus/out")
    ap.add_argument("--profile", default="bench-corpus")
    ap.add_argument("--page", help="route one page instead of the whole corpus")
    ap.add_argument("--ask", help="T3: an explicit operator question, budget-exempt")
    ap.add_argument("--crops", action="store_true", help="write the region crops")
    a = ap.parse_args()

    corpus = pathlib.Path(a.corpus).resolve()
    prof = resolve_profile(load_profiles(), a.profile)

    # Preconditions. Each refusal beats a default: absence-of-file and empty-list
    # are different states, and defaulting one to the other changes verdicts.
    for required in ("manifest.json", "findings_dom.json"):
        if not (corpus / required).exists():
            sys.exit(
                f"refusing: {corpus / required} is absent (run the detector first)"
            )

    stems = (
        [a.page]
        if a.page
        else sorted(p.stem for p in (corpus / "snapshots").glob("*.json"))
    )
    ledger = new_ledger(prof["ceiling"])
    plan = {
        "schema": "design-route/1",
        "profile": prof["name"],
        "profile_character": prof.get("character", ""),
        "per_page_max": prof["per_page_max"],
        "advisory_rules": prof["advisory_rules"],
        "triggers_unreachable": {
            "T4": "arbitration is second-order; no judgement exists in this directory",
            "T5": "no no-DOM subjects (canvas/WebGL/PDF) in this corpus",
        },
        "pages": [route_page(s, corpus, prof, ledger, a.ask) for s in stems],
        "budget": ledger,
    }

    violations = assert_never_list(plan)
    if violations:
        sys.exit(
            "NEVER-list violation -- these have numeric answers and must never be "
            "routed to a model:\n  " + "\n  ".join(violations)
        )

    n_crops = write_crops(corpus, plan) if a.crops else 0
    (corpus / "route_plan.json").write_text(json.dumps(plan, indent=1))

    region = sum(1 for p in plan["pages"] for c in p["calls"] if c["kind"] == "region")
    closed = sum(p["abstentions_closed_by_xcheck"] for p in plan["pages"])
    absts = sum(p["abstentions"] for p in plan["pages"])
    print(f"profile {prof['name']}  ({prof.get('character', '')})")
    print(f"  T2 emphasis      {', '.join(prof['t2_emphasis'])}")
    ctxs = ledger["contexts"]
    print(
        f"  per_page_max     {prof['per_page_max']}   ledger "
        f"{'+'.join(str(c['spent']) for c in ctxs)}/{ledger['ceiling']} "
        f"across {len(ctxs)} context(s)"
    )
    print(
        f"  abstentions      {absts} raised, {closed} closed by the cross-check "
        f"for zero model cost"
    )
    print(f"  T1 model queue   {absts - closed} subject(s) -> {region} region call(s)")
    print(f"  T2 global calls  {len(plan['pages'])} (one per page, unconditional)")
    if n_crops:
        print(f"  crops written    {n_crops} -> {corpus / 'clip'}")
    for p in plan["pages"]:
        extra = [c for c in p["calls"] if c["kind"] != "global"]
        if extra or p["unrouted"]:
            print(f"  {p['page']}")
            for c in extra:
                print(
                    f"      [{c['trigger']}] {c['id']} {c['kind']} "
                    f"{c.get('visual_tokens', '-')} tok  asks={c['asks']}"
                )
            for u in p["unrouted"]:
                print(
                    f"      {u.get('disposition', 'UNROUTED').upper():24} "
                    f"{u['class'].split('|')[0]}\n          because: {u['why']}"
                )
    print(f"  -> {corpus / 'route_plan.json'}")


if __name__ == "__main__":
    main()
