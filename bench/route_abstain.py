#!/usr/bin/env python3
"""The abstention router: the deterministic layer's queue for the eye.

The deterministic layer's most valuable output is not a finding, it is an
ABSTENTION. A silent pass that should have been an abstention is a defect
shipped, because an abstention routes somewhere and a pass routes nowhere. This
is the somewhere.

Two triggers, and deliberately only two -- PIPELINE_SPEC.md section 6 B19 cut
S4 from five triggers to "route T2 unconditionally, forward everything else as a
fact", because T1 on this corpus is 0 and the five-trigger machinery existed to
manage an empty queue of unknown real size:

  T1  every INDETERMINATE the deterministic pass emitted, MINUS the ones the
      cross-check closed. Contrast over a gradient is the worked example: the
      DOM abstains, the cross-check answers it with two numbers and a verdict at
      zero model cost, and re-asking an eye would spend a crop on a closed
      question.
  T2  the six classes no rule can screen -- hierarchy, gestalt, content-fit,
      semantic-coherence, optical-alignment, readability. Once per page, per
      fold, unconditional, never cut for budget. This is the arm that found three
      real defects nobody injected and no rule was looking for.

Three properties of the T1 subtraction are load-bearing, and each is code here
rather than discipline:

  * it is GATED ON THE CROSS-CHECK FILE EXISTING. An absent file resolves nothing
    and looks exactly like nothing needing resolution, so a cross-check outage
    would silently shrink the queue to zero at the moment it should grow. Here it
    grows: no file means no subtraction, and the plan says so in `degradation`.
  * the key spans the CLAIM, not just the location -- (rule-class, target). This
    corpus has already lost a real defect once to a dedup key that spanned less
    than its subject.
  * NOTHING WITH A NUMBER IN THE ANSWER IS ROUTED. Distances, gaps, sizes,
    ratios, contrast solid or gradient, token membership, bounding boxes, scores.
    The browser already knows every one of them exactly, and a model asked for
    one returns a plausible estimate of a fact. `check_question` enforces it and
    raises rather than emitting.

This router asks no model anything. It writes the queue -- crops, captions and a
decision record -- and stops. The eye that reads it is the session's own, which
is the only judge the June 2026 campaign left standing: taste stays human, and
this queue is advisory triage, never a gate.

Usage:
  python3 route_abstain.py <corpus-dir> [--app reso-landing-app] [--budget 2]
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib

from PIL import Image

# `profiles`, not `profile` -- the stdlib owns that name, and shadowing it from
# a script directory is a bug that only shows up in whatever imports it next.
import profiles as profile_mod

# The six classes with no deterministic screen. Each is a question about whether
# the page makes sense, and none has a number in its answer.
UNSCREENABLE = {
    "gestalt": "Does this screen make sense at a glance? Say what it is for, then "
    "what confuses you about it.",
    "hierarchy": "What does the eye land on first, second, third -- and is that the "
    "order the screen wants? Name the elements, in order.",
    "content-fit": "Is anything here promised and not delivered, or delivered and "
    "not promised? Quote the text that makes the promise.",
    "semantic-coherence": "Does every control say what it does, and does every group "
    "belong together? Name any control whose label and behaviour disagree.",
    "optical-alignment": "Does anything read as misaligned, crooked or off-centre, "
    "even where you would expect the CSS to be correct? Name the element.",
    "readability": "Is any text here hard to read as rendered -- washed out, too "
    "tight, clipped, or competing with what is behind it? Name it.",
}

# Which cross-check rule closes which abstention, on the same target. This is the
# whole subtraction, and it is deliberately a small explicit table: a rule added
# without a line here keeps routing to the eye, which is the safe direction.
CLOSES = {"contrast-indeterminate": {"xcheck-contrast-varies"}}

# If a question could be answered with a number, it is not a question for an eye.
BANNED = (
    "how many",
    "how far",
    "how much",
    "ratio",
    "px",
    "pixel",
    "measure",
    "score",
    "rank ",
    "rate ",
    "coordinate",
    "bounding box",
    "distance",
    "percent",
)

CONTEXT_PAD = 24  # CSS px of backdrop kept around a routed element
READ_MAX_EDGE = 2000  # the client clamp
READ_MAX_TOKENS = 4784  # ceil(w/28) * ceil(h/28), the high-resolution tier


def check_question(q: str) -> str:
    lowered = q.lower()
    for bad in BANNED:
        if bad in lowered:
            raise AssertionError(
                f"routed question asks for a number ({bad!r}): {q!r}. The browser "
                f"already knows it exactly; forward it as a fact instead."
            )
    return q


def fits_envelope(w: int, h: int) -> bool:
    return (
        w <= READ_MAX_EDGE
        and h <= READ_MAX_EDGE
        and math.ceil(w / 28) * math.ceil(h / 28) <= READ_MAX_TOKENS
    )


def band_of(y: float, page_h: float) -> str:
    return ("the top", "the middle", "the lower")[min(2, int(3 * y / max(page_h, 1)))]


def caption(
    label: str, band: str, frac: float, eff: float, neighbours: list[str]
) -> str:
    """Every crop carries its own prohibition, in the same image's caption.

    A crop that cannot support a verdict has to say so where the verdict would be
    made. A judge that is not told will answer anyway, and at eff below 2.0 the
    answer it gives about a 1px edge is a guess wearing a measurement's clothes.
    """
    lines = [
        f"region {label}",
        f"{band} of the page, about {frac:.0%} of its height, "
        f"beside: {', '.join(neighbours) if neighbours else 'nothing else in frame'}",
        f"effective resolution {eff:.2f}x CSS",
    ]
    if eff < 2.0:
        lines.append(
            "DO NOT assert any 1-2px alignment, hairline-width or colour-drift "
            "finding from this image. If you suspect one, name the region and stop."
        )
    return "\n".join(lines)


def shot_for(corpus: pathlib.Path, page: str) -> pathlib.Path | None:
    shots = sorted(
        (
            p
            for p in (corpus / "shots").glob(f"{page}*.png")
            if p.stem.split("@")[0] == page
        ),
        key=lambda p: p.stat().st_size,
    )
    return shots[-1] if shots else None


def route(corpus: pathlib.Path, app: str, budget: int, emit: bool) -> dict:
    dom_file = corpus / "findings_dom.json"
    xcheck_file = corpus / "findings_xcheck.json"
    dom = json.loads(dom_file.read_text()) if dom_file.exists() else {}
    xcheck = json.loads(xcheck_file.read_text()) if xcheck_file.exists() else {}
    prof = profile_mod.load(app)
    crops_dir = corpus / "route_crops"
    if emit:
        crops_dir.mkdir(exist_ok=True)

    plan: dict = {
        "app": app,
        "profile_stance": prof.cfg["stance"],
        "degradation": {
            # The one case where a larger model queue is the correct response to a
            # layer failure.
            "xcheck": "present" if xcheck_file.exists() else "absent",
            "subtraction": "applied"
            if xcheck_file.exists()
            else "NOT APPLIED -- "
            "the cross-check file is missing, so nothing is treated as closed and "
            "T1 is larger than it would otherwise be",
        },
        "budget_per_page": budget,
        # Every T2 question, once. Each is checked against the NEVER list at
        # build time, so a question that asks for a number cannot reach a plan.
        "unscreenable_classes": {c: check_question(q) for c, q in UNSCREENABLE.items()},
        "pages": {},
    }

    for page in sorted(dom):
        snap_file = corpus / "snapshots" / f"{page}.json"
        png = shot_for(corpus, page)
        if not snap_file.exists() or png is None:
            continue
        snap = json.loads(snap_file.read_text())
        by_path = {e["path"]: e for e in snap["elements"]}
        img = Image.open(png)
        scale = img.size[0] / snap["scroll"]["w"]
        page_h = snap["scroll"]["h"]

        closed = {
            (r, f["target"])
            for f in xcheck.get(page, [])
            for r, closers in CLOSES.items()
            if f["rule"] in closers
        }
        indeterminate = [f for f in dom[page] if f["rule"].endswith("-indeterminate")]
        unresolved = [
            f for f in indeterminate if (f["rule"], f["target"]) not in closed
        ]

        entries, n_crops = [], 0
        for f in unresolved:
            el = by_path.get(f["target"])
            if el is None:
                continue
            over_budget = n_crops >= budget
            r = el["rect"]
            x0 = max(0, (r["x"] - CONTEXT_PAD) * scale)
            y0 = max(0, (r["y"] - CONTEXT_PAD) * scale)
            x1 = min(img.size[0], (r["right"] + CONTEXT_PAD) * scale)
            y1 = min(img.size[1], (r["bottom"] + CONTEXT_PAD) * scale)
            w, h = int(x1 - x0), int(y1 - y0)
            label = f"c{len(entries) + 1:02d} -- {el['tag']}"
            if el["classes"]:
                label += "." + ".".join(el["classes"])
            neighbours = [
                e["tag"] + ("." + e["classes"][0] if e["classes"] else "")
                for e in snap["elements"]
                if e is not el
                and abs(e["rect"]["y"] - r["y"]) < 80
                and e["rect"]["w"] > 40
            ][:3]
            entry = {
                "trigger": "T1",
                "kind": "unresolved-abstention",
                "rule": f["rule"],
                "target": f["target"],
                "region": label,
                "why": f["detail"],
                # An abstention about a backdrop is routed as a question about
                # LEGIBILITY, never as a request for the ratio the deterministic
                # layer could not compute. The number is not the model's to give.
                "question": check_question(
                    "Is this text legible where it actually sits, over what is "
                    "actually behind it? Answer as a reader would."
                ),
                "caption": caption(
                    label, band_of(r["y"], page_h), r["y"] / page_h, scale, neighbours
                ),
            }
            if not fits_envelope(w, h):
                entry["image"] = None
                entry["crop_refused"] = (
                    f"{w}x{h} exceeds the read envelope; downscaling would destroy "
                    f"the evidence the crop exists to carry"
                )
            elif over_budget:
                entry["image"] = None
                entry["unadjudicated_by_budget"] = True
            else:
                name = f"{page}.{label.split(' ')[0]}.png"
                entry["image"] = f"route_crops/{name}"
                if emit:
                    img.crop((int(x0), int(y0), int(x1), int(y1))).save(
                        crops_dir / name
                    )
                n_crops += 1
            entries.append(entry)

        # T2 -- unconditional, budget-exempt, one per fold. Below the fold is its
        # own call at its own offset, never a taller image: a 2500px-tall shot
        # delivers 0.80x effective detail, worse than a plain DPR-1 viewport shot.
        vp_h = json.loads((corpus / "manifest.json").read_text())["viewport"]["height"]
        folds = max(1, math.ceil(page_h / vp_h))
        for fold in range(folds):
            fy0 = int(fold * vp_h * scale)
            fy1 = int(min(img.size[1], (fold + 1) * vp_h * scale))
            name = f"{page}.fold{fold + 1}.png"
            if emit:
                img.crop((0, fy0, img.size[0], fy1)).save(crops_dir / name)
            for cls in sorted(UNSCREENABLE, key=lambda c: -prof.weight(c)):
                # The question text lives once, in `unscreenable_classes`, and is
                # resolved by lookup. Repeating six identical prompts on every
                # page turned this decision record into 58 KB of duplicate prose,
                # which buries the part of it that differs per page.
                entries.append(
                    {
                        "trigger": "T2",
                        "kind": "unscreenable",
                        "rule": cls,
                        "target": f"{page} fold {fold + 1}",
                        "rank": prof.weight(cls),
                        "image": f"route_crops/{name}",
                    }
                )
            plan.setdefault("fold_captions", {})[f"{page} fold {fold + 1}"] = caption(
                f"fold {fold + 1}", "the whole", 1.0, scale, []
            )

        plan["pages"][page] = {
            "coverage": {
                # Findings, not subject-checks: this stage reads a findings file
                # and never sees the denominator. `fp_budget.py` owns that.
                "dom_findings": len(dom[page]),
                "indeterminate": len(indeterminate),
                "closed_by_xcheck": len(indeterminate) - len(unresolved),
                "routed_T1": sum(1 for e in entries if e["trigger"] == "T1"),
                "routed_T2": sum(1 for e in entries if e["trigger"] == "T2"),
                # An unanswered question must be visible as unanswered, not absent.
                "unadjudicated_by_budget": sum(
                    1 for e in entries if e.get("unadjudicated_by_budget")
                ),
            },
            "queue": entries,
        }
    return plan


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path)
    ap.add_argument("--app", default="default")
    ap.add_argument(
        "--budget", type=int, default=2, help="T1 crops per page; T2 is exempt"
    )
    ap.add_argument("--no-crops", action="store_true", help="plan only, write no PNGs")
    a = ap.parse_args()

    corpus = a.corpus.resolve()
    plan = route(corpus, a.app, a.budget, emit=not a.no_crops)
    (corpus / "route-plan.json").write_text(json.dumps(plan, indent=1))

    d = plan["degradation"]
    print(
        f"route plan -- app {plan['app']} ({plan['profile_stance']}), "
        f"cross-check {d['xcheck']}"
    )
    if d["xcheck"] == "absent":
        print(f"  !! {d['subtraction']}")
    t1 = t2 = closed = deficit = 0
    for page, p in sorted(plan["pages"].items()):
        c = p["coverage"]
        t1 += c["routed_T1"]
        t2 += c["routed_T2"]
        closed += c["closed_by_xcheck"]
        deficit += c["unadjudicated_by_budget"]
        if c["routed_T1"] or c["closed_by_xcheck"]:
            print(
                f"  {page:24} T1 {c['routed_T1']}  "
                f"(closed by cross-check: {c['closed_by_xcheck']})"
            )
    print(
        f"\nT1 {t1} routed, {closed} closed deterministically  |  "
        f"T2 {t2} ({len(plan['pages'])} pages x {len(UNSCREENABLE)} classes x folds)"
    )
    if deficit:
        print(f"!! {deficit} abstention(s) unadjudicated by budget -- raise --budget")
    print(f"-> {corpus / 'route-plan.json'}")


if __name__ == "__main__":
    main()
