#!/usr/bin/env python3
"""The abstention router: turn the deterministic pass's silence into a job queue.

The deterministic layer's most valuable output is not a finding, it is an
abstention. `contrast-indeterminate: cannot compute a ratio, the backdrop is a
gradient` is the layer saying, in code, exactly where it stopped being able to
see -- and every silent pass that should have been an abstention is a defect
shipped. This routes that set, and only that set, to the layer that can answer it.

It emits crop REQUESTS and, with --crops, the crops themselves, clipped out of the
frame `capture.py` already photographed. Re-rendering would be a different frame,
and then a pixel finding and a DOM finding would no longer be describing the same
thing, which is the property the single capture pass exists to give us.

Five things this file is careful about, each because it has a way of going wrong:

  T1 IS A SUBTRACTION, AND THE SUBTRACTION IS CODE.
      The queue is `INDETERMINATE - resolved_by(xcheck)`. The cross-check settles
      contrast-over-a-gradient for free (6.00:1 at the left edge, 1.78:1 at the
      right), so re-asking a model is spending a crop on a closed question. New
      rules will add new abstentions and nobody re-runs a subtraction by hand.

  ...AND IT IS GATED ON THE CROSS-CHECK FILE EXISTING.
      A missing findings file resolves nothing AND LOOKS EXACTLY LIKE nothing
      needing resolution. So the gate tests for the file, and T1 GROWS under a
      cross-check outage. This is the one place where a bigger model queue is the
      correct response to a layer failure, and the only defence against a
      fail-closed layer composing into a fail-never pipeline.

  T2 IS UNCONDITIONAL AND IS NEVER CUT FOR BUDGET.
      The six unscreenable classes are not derived from any finding, so the
      deterministic pass being quiet says nothing about them. A queue built only
      from abstentions would go empty on a page whose hierarchy is inverted --
      which is exactly the corpus's third pixels-only defect.

  GEOMETRY COMES FROM THE DOM, NEVER FROM A MODEL.
      Crop rects are unions of getBoundingClientRect values. A model-drawn box is
      an estimate of something the browser returns exactly, for free.

  NOTHING IS DROPPED SILENTLY.
      Everything the crop budget cannot cover is listed under
      `unadjudicated_by_budget`, and every rule class the profile required but the
      run could not supply an input for is listed under `unverified`. A quiet
      report and a clean page have to be distinguishable in the artifact itself.

Usage:
  python3 route_abstain.py <corpus-dir> [--profile corpus] [--crops] [--page NAME]
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys

# --- The delivery envelope (PIPELINE_SPEC C5/§1.6) --------------------------
# Both predicates must hold or the image is resized on the way in, which
# destroys the evidence silently. The token predicate is the general rule; the
# pixel caps are the transport's.
MAX_SIDE_PX = 2000
MAX_TOKENS = 4784
PATCH = 28
# A crop buys ISOLATION, never magnification: the review target is what a person
# sees at DPR 2, so a defect visible only at 4x is manufactured false-positive
# supply. Below this, the crop cannot carry a sub-pixel claim and has to say so.
EFF_FULL = 2.0
CONTEXT_PAD_PX = 24  # a subject with no surroundings cannot be judged against them


def tokens_for(w: int, h: int) -> int:
    return math.ceil(w / PATCH) * math.ceil(h / PATCH)


def legal_scale(w_css: float, h_css: float, want: float) -> float:
    """Largest scale <= want at which this rect satisfies the whole envelope."""
    s = want
    while s > 0.25:
        w, h = round(w_css * s), round(h_css * s)
        if w <= MAX_SIDE_PX and h <= MAX_SIDE_PX and tokens_for(w, h) <= MAX_TOKENS:
            return s
        s -= 0.05
    return 0.25


def union(rects: list[dict]) -> dict:
    return {
        "x": min(r["x"] for r in rects),
        "y": min(r["y"] for r in rects),
        "right": max(r["right"] for r in rects),
        "bottom": max(r["bottom"] for r in rects),
    }


def pad_and_clamp(r: dict, page_w: float, page_h: float, pad: float) -> dict:
    x = max(0.0, r["x"] - pad)
    y = max(0.0, r["y"] - pad)
    right = min(page_w, r["right"] + pad)
    bottom = min(page_h, r["bottom"] + pad)
    return {"x": x, "y": y, "w": right - x, "h": bottom - y}


def band_of(rect: dict, page_h: float) -> str:
    """Where on the page this sits, in the words a person would use."""
    mid = (rect["y"] + rect["h"] / 2) / max(page_h, 1.0)
    return (
        "upper third"
        if mid < 1 / 3
        else "middle third"
        if mid < 2 / 3
        else "lower third"
    )


def label_of(path: str) -> str:
    """The last two path segments, which is how a person names a region."""
    return " > ".join(path.split(" > ")[-2:])


def png_width(path: pathlib.Path) -> int:
    """Pixel width, straight out of the IHDR. 24 bytes, no image library.

    `eff` has to be MEASURED off the capture, never assumed. A crop cut from a 1x
    shot and resampled to 2x carries a caption saying eff 2.00 and no new
    information: it manufactures resolution and then licenses the sub-pixel claim
    the prohibition exists to withhold. Reading the artifact costs nothing and
    cannot go stale the way a recorded setting can.
    """
    with path.open("rb") as fh:
        head = fh.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    return int.from_bytes(head[16:20], "big")


class Route:
    def __init__(self, corpus: pathlib.Path, profile_name: str, suffix: str = ""):
        self.suffix = suffix
        cfg = json.loads((pathlib.Path(__file__).parent / "profiles.json").read_text())
        self.routing = cfg["routing"]
        # profiles.json carries its rationale inline, as $-prefixed keys. They are
        # documentation, never members of the sets they sit in.
        for key in ("abstention_classes", "unscreenable_classes"):
            self.routing[key] = {
                k: v for k, v in self.routing[key].items() if not k.startswith("$")
            }
        if profile_name not in cfg["profiles"]:
            sys.exit(
                f"unknown profile {profile_name!r}; have: "
                + ", ".join(sorted(cfg["profiles"]))
            )
        self.profile_name = profile_name
        self.profile = cfg["profiles"][profile_name]
        self.corpus = corpus
        self.manifest = json.loads((corpus / "manifest.json").read_text())

        dom_file = corpus / "findings_dom.json"
        if not dom_file.exists():
            sys.exit(
                f"no {dom_file}: run detect_dom.py first -- the router routes its silence"
            )
        self.dom = json.loads(dom_file.read_text())

        # THE GATE. Absence of the cross-check is a state the plan must carry,
        # not a zero it can quietly subtract.
        # Suffixed, so a run routed against the @1.5x capture subtracts the
        # cross-check of THAT capture. Crossing the two would silently resolve an
        # abstention using pixels the crop will not be cut from.
        self.xcheck_file = corpus / f"findings_xcheck{suffix}.json"
        self.xcheck_up = self.xcheck_file.exists()
        self.xcheck = json.loads(self.xcheck_file.read_text()) if self.xcheck_up else {}

    def weight(self, rule: str) -> float:
        return float(self.profile.get("weights", {}).get(rule, 1.0))

    def unverified(self) -> list[dict]:
        """Rule classes this profile requires an input for that the run lacks.

        Reported as UNVERIFIED rather than as a pass. A conformance rule with no
        token map did not find zero drift; it did not run.
        """
        out = []
        if "token-map" in self.profile.get("requires", []) and not self.manifest.get(
            "tokens"
        ):
            out.append(
                {
                    "classes": ["token-drift", "type-scale", "grid-violation"],
                    "verdict": "UNVERIFIED",
                    "why": (
                        "this profile requires a token map and the run supplied "
                        "none, so conformance was not checked -- absence of "
                        "findings here is not conformance"
                    ),
                }
            )
        return out

    def t1(self, page: str) -> tuple[list[dict], list[dict]]:
        """Abstentions minus what the cross-check closed. Returns (open, closed)."""
        classes = self.routing["abstention_classes"]
        abstentions = [f for f in self.dom.get(page, []) if f["rule"] in classes]
        resolved_here = self.xcheck.get(page, [])
        open_, closed = [], []
        for a in abstentions:
            closers = classes[a["rule"]]["resolved_by"]
            # Same subject, or an ancestor of it: the cross-check answers about the
            # text run it measured, and a wrapper's abstention is about the same ink.
            hit = next(
                (
                    x
                    for x in resolved_here
                    if x["rule"] in closers
                    and (
                        x["target"] == a["target"]
                        or x["target"].startswith(a["target"] + " > ")
                        or a["target"].startswith(x["target"] + " > ")
                    )
                ),
                None,
            )
            # The gate: with the cross-check down, nothing is closed, by construction.
            if hit and self.xcheck_up:
                closed.append({**a, "closed_by": hit["rule"], "answer": hit["detail"]})
            else:
                open_.append(a)
        return open_, closed

    def collapse(self, abstentions: list[dict], snap: dict) -> list[dict]:
        """One queue item per (class, reason), not per subject.

        95 abstentions against a crop budget of 2 is not a routing problem, it is
        a units problem: they are 95 instances of two or three questions. Asking
        the question once, over the region its subjects share, is the same
        question at 1/40th the cost.
        """
        by_path = {e["path"]: e for e in snap["elements"]}
        groups: dict[tuple, list[dict]] = {}
        for a in abstentions:
            reason = a["detail"].split(".")[0].strip()
            groups.setdefault((a["rule"], reason), []).append(a)
        items = []
        for (rule, reason), members in groups.items():
            rects = [
                by_path[m["target"]]["rect"] for m in members if m["target"] in by_path
            ]
            if not rects:
                continue
            items.append(
                {
                    "trigger": "T1",
                    "kind": "abstention",
                    "rule": rule,
                    "question": self.routing["abstention_classes"][rule]["asks"],
                    "reason": reason,
                    "subjects": [m["target"] for m in members],
                    "rect": union(rects),
                    "weight": self.weight(rule),
                }
            )
        return items

    def t2(self, snap: dict) -> list[dict]:
        """The six unscreenable classes, once per page, in this profile's order."""
        page_rect = {
            "x": 0.0,
            "y": 0.0,
            "right": float(snap["scroll"]["w"]),
            "bottom": float(snap["scroll"]["h"]),
        }
        order = self.profile.get(
            "queue_priority", list(self.routing["unscreenable_classes"])
        )
        items = []
        for i, cls in enumerate(order):
            q = self.routing["unscreenable_classes"].get(cls)
            if q is None:
                continue
            items.append(
                {
                    "trigger": "T2",
                    "kind": "unscreenable",
                    "rule": cls,
                    "question": q,
                    "reason": "no rule can ask this; the deterministic pass being quiet says nothing about it",
                    "subjects": [],
                    "rect": page_rect,
                    # Ordered by the profile, and never cut -- the weight is a
                    # sort key here, not a gate.
                    "weight": 1.0 - i * 1e-3,
                }
            )
        return items

    def weigh_findings(self, page: str) -> tuple[list[dict], list[dict]]:
        """Rank what the deterministic layers asserted, by THIS app's priorities.

        This is where three apps stop being one problem. A purchased marketing
        template scored against tokens we did not author produces a page of true
        statements that are not defects, and being right about the wrong question
        is how a reviewer reaches the ~20% credibility cliff without a single
        false positive. So conformance is DEMOTED for that app and surfaced for
        the one we author against our own tokens.

        Demoted, never deleted, and always counted in the report: a weighting
        that could hide a finding would be a way of tuning a page green, and the
        count is what stops it being one. Correctness -- contrast, overflow,
        target size -- carries weight 1.0 in every profile, because a contrast
        failure is a failure whoever wrote the CSS.
        """
        base = {"high": 1.0, "medium": 0.6, "low": 0.3}
        floor = float(self.profile.get("surface_floor", 0.0))
        abstention = set(self.routing["abstention_classes"])
        surfaced, demoted = [], []
        for f in self.dom.get(page, []) + self.xcheck.get(page, []):
            if f["rule"] in abstention:
                continue  # an abstention is a question; it is routed, not ranked
            w = self.weight(f["rule"])
            scored = {
                **f,
                "weight": w,
                "priority": round(base.get(f["severity"], 0.6) * w, 4),
            }
            (demoted if scored["priority"] < floor else surfaced).append(scored)
        surfaced.sort(key=lambda f: -f["priority"])
        demoted.sort(key=lambda f: -f["priority"])
        return surfaced, demoted

    def capture_scale(self, page: str, page_w: float) -> float:
        """Device pixels per CSS pixel in the shot this plan will be cut from."""
        shot = self.corpus / "shots" / f"{page}{self.suffix}.png"
        if not shot.exists() or page_w <= 0:
            return EFF_FULL
        return png_width(shot) / page_w

    def plan_page(self, page: str, snap: dict) -> dict:
        open_abs, closed_abs = self.t1(page)
        t1_items = self.collapse(open_abs, snap)
        t2_items = self.t2(snap)
        t1_items.sort(key=lambda i: -i["weight"])

        # T2 is budget-EXEMPT, so it does not spend the budget either. Charging
        # the unconditional six against the allowance starves the queue that
        # actually has evidence behind it: on the corpus, with the cross-check
        # down, it cut the one real abstention and kept six standing questions.
        budget = int(self.profile.get("crop_budget", 4))
        keep = t2_items + t1_items[:budget]
        cut = t1_items[budget:]
        keep.sort(key=lambda i: (i["kind"] != "abstention", -i["weight"]))

        surfaced, demoted = self.weigh_findings(page)

        page_w = float(snap["scroll"]["w"])
        page_h = float(snap["scroll"]["h"])
        capture_scale = self.capture_scale(page, page_w)
        for n, it in enumerate(keep, 1):
            clip = pad_and_clamp(it["rect"], page_w, page_h, CONTEXT_PAD_PX)
            eff = legal_scale(clip["w"], clip["h"], min(EFF_FULL, capture_scale))
            it["id"] = f"c{n:02d}"
            it["clip"] = {k: round(v, 2) for k, v in clip.items()}
            it["eff"] = round(eff, 3)
            it["caption"] = self.caption(it, clip, eff, page_h, snap)

        return {
            "page": page,
            "profile": self.profile_name,
            "emphasis": self.profile["emphasis"],
            "cross_check": "up" if self.xcheck_up else "DOWN -- nothing was subtracted",
            "coverage": {
                "dom_findings": len(self.dom.get(page, [])),
                "abstentions_raised": len(open_abs) + len(closed_abs),
                "abstentions_closed_by_xcheck": len(closed_abs),
                "abstentions_routed": len(open_abs),
                "crops_t1": len(keep) - len(t2_items),
                "crops_t2_unconditional": len(t2_items),
                "crop_budget_t1": budget,
                "findings_surfaced": len(surfaced),
                "findings_demoted": len(demoted),
            },
            "closed_without_a_model": closed_abs,
            "unverified": self.unverified(),
            "findings": surfaced,
            "demoted_below_floor": [
                {
                    "rule": d["rule"],
                    "target": d["target"],
                    "priority": d["priority"],
                    "why": (
                        f"{self.profile_name} weights {d['rule']} at {d['weight']:g}; "
                        f"below this profile's surface floor. Not a pass -- counted here."
                    ),
                }
                for d in demoted
            ],
            "unadjudicated_by_budget": [
                {
                    "rule": c["rule"],
                    "question": c["question"],
                    "subjects": c["subjects"],
                }
                for c in cut
            ],
            "queue": keep,
        }

    def caption(self, it, clip, eff, page_h, snap) -> str:
        """Everything the image cannot show about itself, in the image's own caption.

        Including its own prohibition. A judge that is not told the crop cannot
        support a 1px claim will answer the 1px question anyway.
        """
        frac = round(100 * (clip["w"] * clip["h"]) / (snap["scroll"]["w"] * page_h))
        label = label_of(it["subjects"][0]) if it["subjects"] else "the whole page"
        bits = [f"region {it['id']} -- {label}"]
        # "the middle third of the page" is a lie about a full-page image, and a
        # caption that describes the frame wrongly is worse than one that does not.
        bits.append(
            "the whole frame"
            if frac >= 99
            else f"{band_of(clip, page_h)} of the page, {frac}% of its area"
        )
        bits += [f"eff {eff:.2f}", f"QUESTION: {it['question']}"]
        if it["subjects"]:
            bits.append(
                f"{len(it['subjects'])} subject(s): "
                + ", ".join(label_of(s) for s in it["subjects"][:4])
            )
        if eff < EFF_FULL:
            bits.append(
                "do not assert any 1-2px alignment, hairline-width or colour-drift "
                "finding from this image; if you suspect one, name the region"
            )
        bits.append(
            "do not answer with a number: distances, gaps, sizes, ratios, contrast "
            "and token membership are measured elsewhere and are not yours to state"
        )
        return " | ".join(bits)


def rasterise(corpus: pathlib.Path, plan: dict, suffix: str) -> int:
    """Clip the crops out of the frame that was already captured.

    Out of the SAME frame, deliberately. A second browser pass is a second render
    and the two can differ; the whole reason capture.py takes the screenshot and
    the snapshot together is that a pixel finding and a DOM finding have to be
    arguing about one page.
    """
    from PIL import Image

    shot = corpus / "shots" / f"{plan['page']}{suffix}.png"
    if not shot.exists():
        return 0
    img = Image.open(shot).convert("RGB")
    snap = json.loads((corpus / "snapshots" / f"{plan['page']}.json").read_text())
    src_scale = img.width / snap["scroll"]["w"]
    outdir = corpus / "crops" / plan["page"]
    outdir.mkdir(parents=True, exist_ok=True)
    n = 0
    # The six unscreenable questions share one global image. Writing six
    # byte-identical PNGs and calling each of them "the global image" is how a
    # page ends up with three different things by that name -- and it spends the
    # image ledger six times for one frame.
    seen: dict[tuple, str] = {}
    for it in plan["queue"]:
        c = it["clip"]
        key = (c["x"], c["y"], c["w"], c["h"], it["eff"])
        if key in seen:
            it["image"] = seen[key]
            it["shares_image_with"] = True
            continue
        box = (
            round(c["x"] * src_scale),
            round(c["y"] * src_scale),
            round((c["x"] + c["w"]) * src_scale),
            round((c["y"] + c["h"]) * src_scale),
        )
        region = img.crop(box)
        target = (round(c["w"] * it["eff"]), round(c["h"] * it["eff"]))
        if target != region.size:
            region = region.resize(target, Image.LANCZOS)
        path = outdir / f"{it['id']}.png"
        region.save(path)
        it["image"] = str(path.relative_to(corpus))
        seen[key] = it["image"]
        n += 1
    return n


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", default="corpus/out", type=pathlib.Path)
    ap.add_argument("--profile", default="corpus")
    ap.add_argument("--page", default="", help="route one page instead of all")
    ap.add_argument("--crops", action="store_true", help="also write the crop PNGs")
    ap.add_argument("--shot-suffix", default="", help="e.g. @1.5x")
    a = ap.parse_args()

    corpus = a.corpus.resolve()
    r = Route(corpus, a.profile, a.shot_suffix)
    snaps = sorted((corpus / "snapshots").glob("*.json"))
    if a.page:
        snaps = [s for s in snaps if s.stem == a.page]
        if not snaps:
            sys.exit(f"no snapshot for page {a.page!r}")

    plans = {}
    total_crops = 0
    for s in snaps:
        snap = json.loads(s.read_text())
        plan = r.plan_page(s.stem, snap)
        if a.crops:
            total_crops += rasterise(corpus, plan, a.shot_suffix)
        plans[s.stem] = plan
    (corpus / "route_plan.json").write_text(json.dumps(plans, indent=1))

    if not r.xcheck_up:
        print(
            "!! CROSS-CHECK DOWN -- no abstention was subtracted and the queue is\n"
            "   LARGER than it should be. That is the correct direction: a missing\n"
            "   findings file resolves nothing and must not look like nothing needing\n"
            "   resolution.\n"
        )
    print(f"profile {a.profile}  ({r.profile['emphasis']})")
    print(
        f"{'page':22} {'abst':>5} {'closed':>7} {'routed':>7} {'T1':>4} {'T2':>4} "
        f"{'cut':>4} {'surf':>5} {'demoted':>8}"
    )
    for name, p in plans.items():
        c = p["coverage"]
        print(
            f"{name:22} {c['abstentions_raised']:5d} {c['abstentions_closed_by_xcheck']:7d} "
            f"{c['abstentions_routed']:7d} {c['crops_t1']:4d} {c['crops_t2_unconditional']:4d} "
            f"{len(p['unadjudicated_by_budget']):4d} {c['findings_surfaced']:5d} "
            f"{c['findings_demoted']:8d}"
        )
    closed = sum(p["coverage"]["abstentions_closed_by_xcheck"] for p in plans.values())
    routed = sum(p["coverage"]["abstentions_routed"] for p in plans.values())
    dem = sum(p["coverage"]["findings_demoted"] for p in plans.values())
    print(
        f"\n{closed} abstention(s) answered for free by the cross-check; "
        f"{routed} routed to the vision layer."
    )
    if dem:
        print(
            f"{dem} finding(s) demoted below this profile's surface floor "
            f"({r.profile.get('surface_floor', 0.0)}) -- listed under "
            f"demoted_below_floor in route_plan.json, never dropped."
        )
    if a.crops:
        print(f"{total_crops} crop(s) written under {corpus / 'crops'}")
    for name, p in plans.items():
        for u in p["unverified"]:
            print(f"  UNVERIFIED on {name}: {', '.join(u['classes'])} -- {u['why']}")
            break


if __name__ == "__main__":
    main()
