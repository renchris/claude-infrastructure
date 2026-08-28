#!/usr/bin/env python3
"""The abstention router: decide what, if anything, earns a model call.

The deterministic layer's most valuable output is not a finding, it is an
ABSTENTION. On a gradient backdrop it says `cannot compute a ratio ... 4.5:1 is
UNVERIFIED for this text` rather than a pass, and every silent pass that should
have been an abstention is a defect shipped. This is the stage that takes that
set seriously: the abstentions plus the classes no rule can screen become the
vision layer's queue, cropped to the region in question, and everything else is
forwarded as a FACT rather than asked as a question.

Three triggers, and only three.

  T1  every `*-indeterminate` the deterministic layer emitted, MINUS what the
      cross-check resolved, then COLLAPSED BY CLASS. Ninety-five abstentions on
      a real page are not ninety-five questions -- every text run on one hero
      gradient is one question, and one crop answers it. Collapsing on
      `(rule, cause)` is what makes the vision spend affordable.

  T2  the unscreenable classes -- hierarchy, gestalt, content-fit,
      semantic-coherence, optical-alignment, readability. Once per page,
      unconditional, NEVER cut for budget. These are the classes where the
      deterministic layer has no opinion at all, so cutting them is not saving
      money, it is deciding not to look.

  T3  an explicit operator question (`--ask`). Budget-exempt, because a person
      asking is not a heuristic firing.

🚨 THE T1 SUBTRACTION IS GATED ON THE CROSS-CHECK FILE EXISTING, and this is the
one place where a LARGER model queue is the correct response to a layer failure.
If `findings_xcheck.json` is absent, an empty file would resolve nothing and
would look exactly like nothing needing resolution -- a silent, confident,
smaller queue. So the subtraction tests for the file, records `xcheck: absent`,
and T1 GROWS.

THE NEVER LIST, enforced in code rather than in discipline: if the answer has a
number in it, the model does not get the question. Distances, gaps, sizes,
ratios, contrast, token membership, timings, and bounding boxes for anything are
already exact and free from the DOM. `_assert_no_numbers` runs over every
question this stage emits and raises rather than shipping one.

This stage NEVER gates and NEVER scores. It writes a queue and a coverage
deficit; taste stays human, and the June 2026 ruling that a VLM is advisory
triage rather than a CI gate is not reopened here.

Usage:
  python3 route.py <corpus-dir> [--profile reso-management] [--page clean]
                                [--ask "..."] [--no-crops]
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
import sys

from PIL import Image

import profiles

# --- the lossless envelope (PIPELINE_SPEC C5) ------------------------------
# Both predicates must hold. The token one is the general rule; 2000px and the
# byte cap are the read clamp. A square maximum is 966x966 CSS at DPR 2 -- not
# 1000x1000, which is the number everyone reaches for and which fails the token
# predicate.
MAX_EDGE = 2000
MAX_BYTES = 3_932_160
MAX_TOKENS = 4784
PATCH = 28

# Ceiling is 2.0 on a design argument, not a physical one: the review target is
# what a person sees at DPR 2. A defect visible only at 4x is manufactured
# false-positive supply. So a crop buys ISOLATION, never magnification.
EFF_CEILING = 2.0
PAD_CSS = 24  # context around a cropped region, in CSS px

NEVER = [
    (r"\bhow (many|much|far|wide|tall|big)\b", "asks for a quantity"),
    (r"\b(measure|compute|calculate|count)\b", "asks for a computation"),
    (r"\b(px|pixels?)\b", "asks in pixels"),
    (r"\b(ratio|contrast ratio|\d+(\.\d+)?:1)\b", "asks for a ratio"),
    (r"\b(coordinates?|bounding box|bbox|x,\s*y)\b", "asks for a box"),
    (r"\b(score|rate|grade|rank|out of \d+|\d+\s*[-/]\s*\d+)\b", "asks for a score"),
    (r"\b(ms|milliseconds?|duration|easing)\b", "asks for a timing"),
]


def _assert_no_numbers(question: str) -> None:
    """A question that has a number in its answer is a question the DOM owns."""
    for pat, why in NEVER:
        if re.search(pat, question, re.I):
            raise AssertionError(
                f"NEVER-list violation ({why}) in a routed question:\n  {question}\n"
                f"  The DOM answers this exactly and for free. Forward it as a fact."
            )


# --- the six unscreenable classes, each with the question it actually asks ---
# A class ships with the sentence that will be sent. Writing them here, once,
# rather than composing them at call time is what makes the NEVER-list assertion
# a build-time property instead of a runtime hope.
T2_QUESTIONS = {
    "hierarchy": (
        "Look at this screen the way someone seeing it for the first time would. "
        "What does your eye land on first, second, third? Is that the order the "
        "page seems to want? Name the elements, not their positions."
    ),
    "gestalt": (
        "Does this screen read as one designed thing, or as parts assembled? If "
        "something feels out of place or unfinished, say which element and what "
        "about it reads that way."
    ),
    "content-fit": (
        "Does the content fit the containers it is in -- labels, table cells, "
        "buttons, headings? Point at anything that looks truncated, crowded, "
        "stranded, or given far more room than it needs."
    ),
    "semantic-coherence": (
        "Read the words on this screen against what the screen shows. Does any "
        "label, caption or heading promise something the interface does not do or "
        "does not show? Quote the text and say what it led you to expect."
    ),
    "optical-alignment": (
        "Ignoring whether things are technically aligned, does anything LOOK "
        "off-centre or off-axis to you -- an icon in a button, a mark in a circle, "
        "text against an edge? Name the element."
    ),
    "readability": (
        "Is anything here hard to read or hard to tell apart from its background? "
        "Name the text and describe what makes it hard, in the words you would use "
        "to a colleague."
    ),
}


def envelope(w: int, h: int) -> float:
    """Largest scale s <= 1 for which (w*s, h*s) is inside the read envelope."""
    s = 1.0
    if w > MAX_EDGE or h > MAX_EDGE:
        s = min(s, MAX_EDGE / w, MAX_EDGE / h)
    # Token predicate. Solve iteratively: the ceilings make it non-continuous,
    # and one shrink step per pass converges in a handful of iterations.
    for _ in range(64):
        tw, th = math.ceil(w * s / PATCH), math.ceil(h * s / PATCH)
        if tw * th <= MAX_TOKENS:
            break
        s *= 0.97
    return s


def masters(corpus: pathlib.Path, page: str) -> list[tuple[pathlib.Path, float]]:
    """Every archived render of this page, highest device scale first.

    Crops come from the ARCHIVED frame, never from a fresh render. A second
    browser pass photographs a different frame, and a crop that came from a
    different frame cannot be argued against the snapshot beside it.
    """
    out = []
    for p in sorted((corpus / "shots").glob(f"{page}*.png")):
        stem = p.stem
        if stem == page:
            out.append((p, 1.0))
        else:
            m = re.fullmatch(rf"{re.escape(page)}@([\d.]+)x", stem)
            if m:
                out.append((p, float(m.group(1))))
    return sorted(out, key=lambda t: -t[1])


def cut(
    corpus: pathlib.Path,
    page: str,
    rect: dict | None,
    out_path: pathlib.Path,
) -> dict:
    """Crop the archived master to `rect` (CSS px), or the whole frame if None."""
    cands = masters(corpus, page)
    if not cands:
        return {"error": f"no archived master for {page}"}
    src, dpr = cands[0]
    img = Image.open(src)
    if rect is None:
        box = (0, 0, img.width, img.height)
    else:
        box = (
            max(0, int((rect["x"] - PAD_CSS) * dpr)),
            max(0, int((rect["y"] - PAD_CSS) * dpr)),
            min(img.width, int(math.ceil((rect["right"] + PAD_CSS) * dpr))),
            min(img.height, int(math.ceil((rect["bottom"] + PAD_CSS) * dpr))),
        )
    reg = img.crop(box)
    s = envelope(reg.width, reg.height)
    if s < 1.0:
        reg = reg.resize((max(1, int(reg.width * s)), max(1, int(reg.height * s))))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    reg.save(out_path)
    eff = min(EFF_CEILING, dpr * s)
    return {
        "file": out_path.name,
        "source_master": src.name,
        "source_dpr": dpr,
        "w": reg.width,
        "h": reg.height,
        "bytes": out_path.stat().st_size,
        "eff": round(eff, 3),
        "within_envelope": (
            reg.width <= MAX_EDGE
            and reg.height <= MAX_EDGE
            and out_path.stat().st_size <= MAX_BYTES
            and math.ceil(reg.width / PATCH) * math.ceil(reg.height / PATCH)
            <= MAX_TOKENS
        ),
    }


def caption(block: dict, page_rect: dict, crop_info: dict) -> str:
    """Every crop states its own role, its share of the page, and its LIMITS.

    A crop that cannot support a verdict has to say so in the same image, because
    a judge that is not told will answer anyway.
    """
    frac = ""
    if block.get("rect"):
        r = block["rect"]
        share = (r["w"] * r["h"]) / max(1.0, page_rect["w"] * page_rect["h"])
        frac = f" It covers about {share:.0%} of the page."
    lines = [
        f"region {block['id']} -- {block['label']}.{frac}",
        f"Rendering fidelity: eff {crop_info.get('eff', 0):.2f}.",
    ]
    if crop_info.get("eff", 0) < EFF_CEILING:
        lines.append(
            "Do not assert any hairline, one-or-two-step alignment, or colour-drift "
            "finding from this image; if you suspect one, name the region and say so."
        )
    lines.append(
        "Do not state any number in your answer. Distances, sizes, ratios and "
        "positions are measured exactly elsewhere; name elements in words."
    )
    return " ".join(lines)


def route(
    corpus: pathlib.Path,
    prof: profiles.Profile,
    pages: list[str] | None = None,
    ask: str | None = None,
    make_crops: bool = True,
) -> dict:
    dom_path = corpus / "findings_dom.json"
    xc_path = corpus / "findings_xcheck.json"
    if not dom_path.exists():
        sys.exit(f"no {dom_path}; run detect_dom.py first")
    dom = json.loads(dom_path.read_text())

    xcheck_state = "present" if xc_path.exists() else "absent"
    xc = json.loads(xc_path.read_text()) if xc_path.exists() else {}

    plan: dict = {
        "profile": prof.name,
        "profile_kind": prof.kind,
        "image_budget_per_page": prof.image_budget,
        "xcheck": xcheck_state,
        "xcheck_note": (
            "T1 was subtracted against a present cross-check."
            if xcheck_state == "present"
            else "CROSS-CHECK ABSENT -- nothing was subtracted from T1, so this "
            "queue is LARGER than it would otherwise be. That is deliberate: an "
            "empty resolution file resolves nothing and looks identical to "
            "nothing needing resolution."
        ),
        "pages": {},
    }

    for page in pages or sorted(dom):
        findings = dom.get(page, [])
        snap_path = corpus / "snapshots" / f"{page}.json"
        snap = json.loads(snap_path.read_text()) if snap_path.exists() else {}
        by_path = {e["path"]: e for e in snap.get("elements", [])}
        page_rect = {
            "w": snap.get("scroll", {}).get("w", 1),
            "h": snap.get("scroll", {}).get("h", 1),
        }

        # --- what the cross-check already answered --------------------------
        resolved = set()
        resolutions = []
        if xcheck_state == "present":
            for f in xc.get(page, []):
                r = f.get("resolves")
                if r:
                    resolved.add((r["rule"], r["target"]))
                    resolutions.append(r)

        # --- T1: abstentions, minus resolutions, collapsed by class ---------
        abstentions = [f for f in findings if f["rule"].endswith("-indeterminate")]
        open_abstentions = [
            f for f in abstentions if (f["rule"], f["target"]) not in resolved
        ]
        classes: dict[tuple, list] = {}
        for f in open_abstentions:
            key = (f["rule"], f.get("cause", f["detail"]))
            classes.setdefault(key, []).append(f)

        blocks = []
        for i, ((rule, cause), members) in enumerate(sorted(classes.items())):
            rects = [
                by_path[m["target"]]["rect"] for m in members if m["target"] in by_path
            ]
            union = None
            if rects:
                union = {
                    "x": min(r["x"] for r in rects),
                    "y": min(r["y"] for r in rects),
                    "right": max(r["right"] for r in rects),
                    "bottom": max(r["bottom"] for r in rects),
                }
                union["w"] = union["right"] - union["x"]
                union["h"] = union["bottom"] - union["y"]
            q = (
                "The automated layer could not answer this and says so: "
                f"{cause}. Looking only at this image, is the text here "
                "comfortable to read against what is behind it, or does any of it "
                "wash out? Name the text you mean."
            )
            _assert_no_numbers(q)
            blocks.append(
                {
                    "id": f"t1-{i:02d}",
                    "trigger": "T1",
                    "rule": rule,
                    "cause": cause,
                    "label": f"the {len(members)} abstained subject(s) under {cause}",
                    "subjects": [m["target"] for m in members],
                    "rect": union,
                    "question": q,
                    "weight": prof.weight(rule),
                    "rank": prof.weight(rule) * 3,
                }
            )

        # --- T2: the unscreenable classes, unconditional --------------------
        for i, cls in enumerate(prof.t2_classes):
            q = T2_QUESTIONS[cls]
            _assert_no_numbers(q)
            blocks.append(
                {
                    "id": f"t2-{i:02d}",
                    "trigger": "T2",
                    "rule": f"unscreenable:{cls}",
                    "cause": "no rule can screen this class",
                    "label": f"the whole frame, for {cls}",
                    "subjects": ["<page>"],
                    "rect": None,
                    "question": q,
                    "weight": 1.0,
                    "rank": 99,  # never cut for budget
                }
            )

        # --- T3: an explicit ask -------------------------------------------
        if ask:
            _assert_no_numbers(ask)
            blocks.append(
                {
                    "id": "t3-00",
                    "trigger": "T3",
                    "rule": "explicit",
                    "cause": "operator request",
                    "label": "the whole frame, as asked",
                    "subjects": ["<page>"],
                    "rect": None,
                    "question": ask,
                    "weight": 1.0,
                    "rank": 100,
                }
            )

        # --- budget: T2 and T3 are exempt; T1 competes for the remainder ----
        exempt = [b for b in blocks if b["trigger"] in ("T2", "T3")]
        contended = sorted(
            [b for b in blocks if b["trigger"] == "T1"], key=lambda b: -b["rank"]
        )
        admitted = exempt + contended[: prof.image_budget]
        deferred = contended[prof.image_budget :]

        if make_crops:
            for b in admitted:
                info = cut(
                    corpus,
                    page,
                    b["rect"],
                    corpus / "queue" / f"{page}__{b['id']}.png",
                )
                b["crop"] = info
                b["caption"] = caption(b, page_rect, info)

        # --- the deficit. An unanswered question must be visible as unanswered.
        plan["pages"][page] = {
            "blocks": admitted,
            "deferred_by_budget": [
                {k: b[k] for k in ("id", "rule", "cause", "subjects")} for b in deferred
            ],
            "resolved_by_xcheck": resolutions,
            "coverage": {
                "abstentions": len(abstentions),
                "resolved_by_xcheck": len(abstentions) - len(open_abstentions),
                "abstention_classes": len(classes),
                "adjudicated": len(admitted),
                "unadjudicated_by_budget": len(deferred),
                "forwarded_as_fact": len(
                    [f for f in findings if not f["rule"].endswith("-indeterminate")]
                ),
            },
        }
    return plan


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", default="corpus/out", type=pathlib.Path)
    ap.add_argument("--profile", default=None)
    ap.add_argument("--page", action="append", default=None)
    ap.add_argument("--ask", default=None)
    ap.add_argument("--no-crops", action="store_true")
    a = ap.parse_args()

    corpus = a.corpus.resolve()
    prof = profiles.load(a.profile)
    # The queue directory IS the plan, so it is rebuilt rather than added to. A
    # crop left over from a previous profile is an image nobody asked for that
    # nothing distinguishes from one somebody did.
    if not a.no_crops:
        for stale in (corpus / "queue").glob("*.png"):
            stale.unlink()
    plan = route(corpus, prof, a.page, a.ask, not a.no_crops)
    out = corpus / "route_plan.json"
    out.write_text(json.dumps(plan, indent=1))

    print(f"ROUTE  profile={prof.name} ({prof.kind})  budget={prof.image_budget}/page")
    print(f"  cross-check: {plan['xcheck']}")
    tot_q = tot_def = 0
    for page, p in sorted(plan["pages"].items()):
        c = p["coverage"]
        tot_q += c["adjudicated"]
        tot_def += c["unadjudicated_by_budget"]
        if c["abstentions"] or c["unadjudicated_by_budget"]:
            print(
                f"  {page:22} abstentions {c['abstentions']:2d} "
                f"-> resolved {c['resolved_by_xcheck']:2d} "
                f"-> {c['abstention_classes']} class(es); "
                f"queued {c['adjudicated']}, deferred {c['unadjudicated_by_budget']}"
            )
    print(f"  queued {tot_q} block(s); {tot_def} unadjudicated by budget")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
