#!/usr/bin/env python3
"""The abstention router: turn what the deterministic layer could not answer into
the vision layer's job queue, and forward everything it COULD answer as a fact.

This is README section 8 item 1 and PIPELINE_SPEC stage S4. The governing
sentence is the README's: *an abstention routes to the vision layer; a pass
routes nowhere.* Everything here follows from taking that literally.

Two triggers, and deliberately not the five the spec sketches
------------------------------------------------------------
PIPELINE_SPEC C7 rules that the five-trigger machinery -- a session-wide block
ledger, exemplar-to-class conversion, an arbitration re-ask -- is CUT until probe
U3 has measured whether a real page's abstentions collapse to about three classes
or about forty. T1 on this corpus is currently zero, and building a scheduler for
an empty queue of unknown size is an argument rather than a number. So:

  T1  abstentions, minus what the cross-check closed, then collapsed by class.
  T2  the six unscreenable classes, once per page, unconditional, never cut.

T3 (explicit operator request), T4 (arbitration) and T5 (no-DOM subjects) are not
implemented and are not stubbed, because a stub of a scheduler is indistinguishable
from a scheduler that never fires.

The three things that ARE load-bearing here
-------------------------------------------
**The subtraction is code.** PIPELINE_SPEC C16: the cross-check settles contrast
over a gradient deterministically, so re-asking a model about it spends a crop on
a closed question. Doing that subtraction by hand does not survive the next rule
somebody adds, so it is a table (`rules.RESOLVED_BY`) and a set intersection.

**The subtraction is gated on the cross-check having RUN.** If its findings file
is missing, an empty file resolves nothing and looks exactly like nothing needing
resolution. So the router tests for the file, and T1 *grows* under a cross-check
outage. This is the one place where a larger model queue is the correct response
to a layer failing.

**The deficit is printed.** A budget that silently drops abstentions converts them
back into the silent passes the abstention was invented to prevent. Dropped
classes appear in `unadjudicated_by_budget` and in the printed summary, so an
unanswered question is visible as unanswered rather than absent.

The NEVER list, made mechanical
-------------------------------
If the answer has a number in it, the model does not get the question --
distances, gaps, sizes, ratios, contrast solid or gradient, token membership,
timings, bounding boxes, and any score or ranking. That is not a discipline here:
`rules.Rule.routable` is true only for abstentions, T2 is raised from the class
list rather than from any rule, and `_assert_never_list` re-checks the finished
plan before it is written. A settled number reaches the model only through the
`facts` array, which is what it is for.

Usage: python3 route.py <corpus-dir> [--profile <app>] [--blocks N]
Writes: <corpus-dir>/route-plan.json
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib

from rules import RESOLVED_BY, RULES, SEVERITY_RANK, UNSCREENABLE_CLASSES

# --- crop envelope, from PIPELINE_SPEC section 1.6 --------------------------
# Both predicates must hold. The token one is the general rule; the pixel one is
# the client clamp. The square maximum that falls out is 966x966 CSS at scale 2,
# not the round 1000 it is often written as.
CROP_MAX_DEVICE_PX = 2000
CROP_PATCH = 28
CROP_MAX_TOKENS = 4784
# 2.0 is a design ceiling, not a limit of the machinery: the review target is
# what a person sees at DPR 2, and a defect visible only at 4x is manufactured
# false-positive supply.
CROP_SCALE_CEILING = 2.0
CROP_PAD_CSS_PX = 8
DEFAULT_BLOCKS = 2  # image blocks granted per page

PROHIBITION = (
    "do not assert any 1-2 px alignment, hairline-width or colour-drift finding "
    "from this image; if you suspect one, name the region"
)


def crop_request(rects: list[dict], page: dict) -> dict:
    """Plan a crop around some subjects. A REQUEST -- nothing is rasterised here.

    S4 never rasterises. A crop taken in a second browser pass is a different
    frame from the one the snapshot describes, and the whole value of capturing
    both artifacts in one pass is that a pixel finding and a DOM finding can be
    argued against each other with no "maybe the page moved" escape hatch.
    """
    x0 = max(0.0, min(r["x"] for r in rects) - CROP_PAD_CSS_PX)
    y0 = max(0.0, min(r["y"] for r in rects) - CROP_PAD_CSS_PX)
    x1 = min(page["w"], max(r["right"] for r in rects) + CROP_PAD_CSS_PX)
    y1 = min(page["h"], max(r["bottom"] for r in rects) + CROP_PAD_CSS_PX)
    w, h = max(1.0, x1 - x0), max(1.0, y1 - y0)

    scale = CROP_SCALE_CEILING
    while scale > 0.25:
        dw, dh = w * scale, h * scale
        tokens = math.ceil(dw / CROP_PATCH) * math.ceil(dh / CROP_PATCH)
        if (
            dw <= CROP_MAX_DEVICE_PX
            and dh <= CROP_MAX_DEVICE_PX
            and tokens <= CROP_MAX_TOKENS
        ):
            break
        scale -= 0.05
    return {
        "x": round(x0, 2),
        "y": round(y0, 2),
        "width": round(w, 2),
        "height": round(h, 2),
        "scale": round(scale, 3),
        # `eff` is the effective magnification the judge actually receives, and
        # it is what decides whether a fine-grained claim is admissible from
        # this image at all.
        "eff": round(scale, 3),
        "page_fraction": round((w * h) / (page["w"] * page["h"]), 4),
    }


def caption_for(qid: str, label: str, crop: dict | None, page: dict) -> str:
    """Every crop carries its own prohibition, in its own caption.

    A judge that is not told what an image cannot support will answer anyway, and
    the answer will be confident. The caption is the only place the constraint
    and the evidence travel together.
    """
    if crop is None:
        return (
            f"region {qid} -- the whole page ({page['w']:.0f}x{page['h']:.0f} CSS px). "
            f"Global frame: answer only about the page as a whole. Name regions, "
            f"never coordinates."
        )
    band = "upper" if crop["y"] < page["h"] / 3 else (
        "middle" if crop["y"] < 2 * page["h"] / 3 else "lower"
    )
    txt = (
        f"region {qid} -- {label!r}, {band} third of the page, "
        f"{crop['page_fraction'] * 100:.1f}% of its area, eff {crop['eff']:.2f}. "
        f"Name regions, never coordinates."
    )
    if crop["eff"] < CROP_SCALE_CEILING:
        txt += f" At this magnification, {PROHIBITION}."
    return txt


def label_for(paths: list[str]) -> str:
    """A human-readable region label. Findings name labels; attribution is a join.

    PIPELINE_SPEC C19 forbids the model emitting coordinates at all: a crop
    finding's coordinates need the crop rect times DPR times the scroll offset,
    three multiplications owned by three stages, and an off-by-one returns a real
    element that is the wrong one with no error anywhere.
    """
    leaves = [p.rsplit(" > ", 1)[-1].split(":")[0] for p in paths]
    uniq = sorted(set(leaves))
    head = ", ".join(uniq[:3])
    return head + (f" and {len(uniq) - 3} more" if len(uniq) > 3 else "")


def route_page(
    name: str,
    dom: list[dict],
    xcheck: list[dict] | None,
    snap: dict,
    weights: dict[str, float],
    blocks: int,
) -> dict:
    els = {e["path"]: e for e in snap["elements"]}
    page = {"w": snap["scroll"]["w"], "h": snap["scroll"]["h"]}
    all_findings = list(dom) + list(xcheck or [])

    abstentions = [f for f in all_findings if RULES[f["rule"]].abstention]
    settled = [f for f in all_findings if not RULES[f["rule"]].abstention]

    # --- T1 step 1: subtract what the cross-check actually closed ------------
    # Per subject, never per class. X3 answering the hero caption says nothing
    # about the hero title sitting on the same gradient, and treating it as if it
    # did is how a real unanswered question disappears.
    resolved_targets: dict[str, set[str]] = {}
    for f in xcheck or []:
        for abst, closers in RESOLVED_BY.items():
            if f["rule"] in closers:
                resolved_targets.setdefault(abst, set()).add(f["target"])

    open_abstentions, resolved = [], []
    for f in abstentions:
        if f["target"] in resolved_targets.get(f["rule"], ()):
            resolved.append(f)
        else:
            open_abstentions.append(f)

    # --- T1 step 2: collapse by class ---------------------------------------
    # Ninety-five abstentions are not ninety-five questions. One gradient behind
    # a hero is one question no matter how many text runs sit on it, and one crop
    # answers it. The key is (rule, backdrop signature) so the collapse spans the
    # claim rather than only its location.
    classes: dict[tuple, list[dict]] = {}
    for f in open_abstentions:
        meta = f.get("meta") or {}
        sig = (
            f["rule"],
            meta.get("backdrop_owner", f["target"]),
            meta.get("backdrop_kind", "unknown"),
        )
        classes.setdefault(sig, []).append(f)

    questions: list[dict] = []

    # --- T2: the six unscreenable classes, one page-global frame ------------
    # Unconditional and budget-exempt. It is the only trigger that fires on a
    # page with nothing wrong with it, and it is the arm the corpus actually
    # measured: two of two judgement defects plus three real defects nobody
    # injected and no rule was looking for.
    questions.append(
        {
            "id": "q00",
            "trigger": "T2",
            "kind": "unscreenable",
            "classes": list(UNSCREENABLE_CLASSES),
            "subjects": [],
            "n_subjects": 0,
            "crop": None,
            "consequence": float("inf"),
            "budget_exempt": True,
            "caption": caption_for("q00", "the whole page", None, page),
        }
    )

    # --- T1 candidates, ranked by consequence, not by document order --------
    cands = []
    for sig, group in classes.items():
        rule = RULES[sig[0]]
        rects = [els[f["target"]]["rect"] for f in group if f["target"] in els]
        if not rects:
            continue
        area = sum(r["w"] * r["h"] for r in rects)
        sev = max(SEVERITY_RANK.get(f["severity"], 1) for f in group)
        cands.append(
            {
                "sig": sig,
                "group": group,
                "rects": rects,
                # An abstention on a 12px legend and one on the primary call to
                # action are not interchangeable. Severity times the per-app
                # weight is the policy term; total painted area is the exact,
                # DOM-supplied proxy for how much of the page is affected.
                "consequence": sev * weights.get(rule.id, 1.0) * area,
            }
        )
    cands.sort(key=lambda c: (-c["consequence"], c["sig"]))

    room = max(0, blocks - 1)  # T2 always holds one block
    deficit = []
    for i, c in enumerate(cands):
        rule = RULES[c["sig"][0]]
        qid = f"q{i + 1:02d}"
        paths = [f["target"] for f in c["group"]]
        rec = {
            "id": qid,
            "trigger": "T1",
            "kind": "abstention",
            "rule": rule.id,
            "klass": rule.klass,
            "signature": {"backdrop_owner": c["sig"][1], "backdrop_kind": c["sig"][2]},
            "subjects": paths,
            "n_subjects": len(paths),
            "question": c["group"][0]["detail"],
            "consequence": round(c["consequence"], 1),
            "budget_exempt": False,
        }
        if i < room:
            crop = crop_request(c["rects"], page)
            rec["crop"] = crop
            rec["caption"] = caption_for(qid, label_for(paths), crop, page)
            questions.append(rec)
        else:
            rec["crop"] = None
            rec["reason"] = "unadjudicated_by_budget"
            deficit.append(rec)

    plan = {
        "page": name,
        "corpus_page_size": page,
        "degradation": {
            # The gate that makes the subtraction honest. `absent` means T1 was
            # NOT reduced, and that is a bigger queue on purpose.
            "xcheck": "present" if xcheck is not None else "absent",
        },
        "coverage": {
            "subjects": len(all_findings),
            "settled_forwarded_as_facts": len(settled),
            "abstentions": len(abstentions),
            "resolved_by_xcheck": len(resolved),
            "open_abstentions": len(open_abstentions),
            "abstention_classes": len(classes),
            "adjudicated": len([q for q in questions if q["trigger"] == "T1"]),
            "unadjudicated_by_budget": len(deficit),
        },
        # Settled findings ride along as VALUES for the judge to reason with.
        # They are never verdicts and never questions -- PIPELINE_SPEC C3.
        "facts": [
            {"rule": f["rule"], "target": f["target"], "value": f["detail"]}
            for f in settled + resolved
        ],
        "questions": questions,
        "unadjudicated_by_budget": deficit,
    }
    _assert_never_list(plan)
    return plan


def _assert_never_list(plan: dict) -> None:
    """Re-check the finished plan against the NEVER list before it is written.

    The guard is here as well as in the construction because the construction is
    what a future edit changes. A settled number becoming a question is silent,
    plausible and exactly the failure this pipeline is built to avoid, so it gets
    an assertion at the boundary rather than a comment.
    """
    for q in plan["questions"]:
        if q["trigger"] == "T2":
            bad = [c for c in q["classes"] if c not in UNSCREENABLE_CLASSES]
            assert not bad, f"T2 raised a screenable class: {bad}"
            continue
        rule = RULES[q["rule"]]
        assert rule.routable, (
            f"{q['id']} routes {rule.id}, whose answer is a {rule.answer}. "
            f"If the answer has a number in it the model does not get the "
            f"question -- it goes in `facts`."
        )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path)
    ap.add_argument(
        "--profile", default=None, help="app profile from review_profiles.json"
    )
    ap.add_argument("--blocks", type=int, default=DEFAULT_BLOCKS)
    a = ap.parse_args()
    corpus = a.corpus.resolve()

    import profiles as profiles_mod

    weights = profiles_mod.weights_for(a.profile)

    dom_path = corpus / "findings_dom.json"
    if not dom_path.exists():
        raise SystemExit(f"no findings_dom.json under {corpus}; run detect_dom.py first")
    dom = json.loads(dom_path.read_text())

    xpath = corpus / "findings_xcheck.json"
    xall = json.loads(xpath.read_text()) if xpath.exists() else None

    plans = {}
    for page, findings in sorted(dom.items()):
        snap = corpus / "snapshots" / f"{page}.json"
        if not snap.exists():
            continue
        plans[page] = route_page(
            page,
            findings,
            None if xall is None else xall.get(page, []),
            json.loads(snap.read_text()),
            weights,
            a.blocks,
        )
    (corpus / "route-plan.json").write_text(json.dumps(plans, indent=1))

    if xall is None:
        print(
            "⚠ findings_xcheck.json is ABSENT. The cross-check subtraction did "
            "not run, so T1 is LARGER than it would otherwise be. That is the "
            "intended response to the layer being down -- an empty file would "
            "have resolved nothing while looking like nothing needed resolving."
        )
    print(f"profile: {a.profile or 'default (all weights 1.0)'}   blocks/page: {a.blocks}")
    hdr = f"{'page':22} {'facts':>5} {'abst':>5} {'closed':>6} {'classes':>7} {'asked':>5} {'deficit':>7}"
    print(hdr)
    print("-" * len(hdr))
    for page, p in plans.items():
        c = p["coverage"]
        print(
            f"{page:22} {c['settled_forwarded_as_facts']:5d} {c['abstentions']:5d} "
            f"{c['resolved_by_xcheck']:6d} {c['abstention_classes']:7d} "
            f"{c['adjudicated']:5d} {c['unadjudicated_by_budget']:7d}"
        )
    tot_q = sum(len(p["questions"]) for p in plans.values())
    tot_d = sum(len(p["unadjudicated_by_budget"]) for p in plans.values())
    print(
        f"\n{tot_q} question(s) over {len(plans)} page(s) "
        f"({len(plans)} unconditional T2 + {tot_q - len(plans)} T1); "
        f"{tot_d} left unadjudicated by budget"
    )
    for page, p in plans.items():
        for d in p["unadjudicated_by_budget"]:
            print(f"  DEFICIT {page}/{d['id']}: {d['rule']} x{d['n_subjects']} subjects")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
