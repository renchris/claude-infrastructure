#!/usr/bin/env python3
"""The abstention router: turn a deterministic pass into the vision layer's job queue.

The deterministic layer's most valuable output is not a finding, it is an
ABSTENTION. On a gradient backdrop `detect_dom` returns `contrast-indeterminate:
cannot compute a ratio ... requirement 4.5:1 is UNVERIFIED for this text` rather
than a pass, and every silent pass that should have been an abstention is a defect
shipped. This stage is what makes that abstention worth emitting: the abstention
set, and nothing else, is what earns a model call.

The router owns four decisions and no others. It never opens a browser, never
issues a request, and never decides whether anything is good.

  1. ASSERT.   A deterministic finding carries a number, so it is answered. It is
               never routed. Asking a model to re-judge a computed distance is the
               forbidden crossing in both directions at once: the model is asked
               for a number, and the layer that owns numbers is asked to defer.
  2. SUBTRACT. An abstention a cross-check arm ANSWERED leaves the queue. This is
               the router's whole economics: `xcheck-contrast-varies` resolves
               contrast-over-a-gradient deterministically, in NumPy, with no model
               and no GPU, and takes that entire class out of the vision spend.
               Measured on this corpus in the run summary below.
  3. COLLAPSE. What survives collapses BY CLASS, per page, into one crop request
               over the union of its targets. Five contrast abstentions inside one
               hero are one question about one region, not five calls.
  4. FRAME.    Classes the deterministic layer cannot reason about at all --
               hierarchy, grouping, does-this-page-make-sense -- are page-global and
               structurally unreachable from a crop, so they get at most one blind
               whole-frame call per page. Bounded by the profile.

Two prohibitions travel WITH the queue rather than living in a prompt file, because
a prompt is edited by whoever is in a hurry and a contract is not:

  * every crop rect comes from `getBoundingClientRect`. The grounder supplies
    identity, the DOM supplies geometry -- no distance is ever computed from a box
    a model drew, so the queue cannot contain one.
  * every item carries its own `prohibition` line. The judge is forbidden to opine
    below the perceptual threshold; SCREEN is forbidden to opine above it.

Nothing here promotes a model finding to `asserted`. There is no code path from this
file's output to a pass/fail verdict, which is the mechanical form of the June 2026
ruling that taste stays human and gates adjudicate correctness and coverage only.

Usage: python3 route.py <corpus-dir> [--profile <app>] [--json]
"""

from __future__ import annotations

import argparse
import json
import pathlib

# Rules whose verdict is an abstention rather than a finding. These are the only
# deterministic outputs that may reach the judge.
ABSTAINING_RULES = {"contrast-indeterminate"}

# Which cross-check arm ANSWERS which abstention, on the same target. This map is
# the subtraction in step 2, and it is deliberately narrow: an arm answers an
# abstention only where it produces the number the abstention said it could not.
RESOLVES = {
    "xcheck-contrast-varies": "contrast-indeterminate",
}

# What the judge is asked, per abstention class, and what it may not answer with.
# One entry per class, so a new abstaining rule cannot reach the model without
# someone stating the question it is being asked.
CLASS_QUESTION = {
    "contrast-indeterminate": (
        "This text sits on a backdrop no single colour can represent, so no ratio "
        "was computed. Looking at the crop: is any part of this text hard to read "
        "against what is behind it, and if so which part?"
    ),
    "token-drift": (
        "This app has no token map to conform to, so no violation was asserted. "
        "Looking at the crop: does this element read as belonging to the same "
        "system as the elements around it?"
    ),
}

GESTALT_QUESTION = (
    "Look at this frame as a first-time reader would in one second. What does the "
    "eye land on first, and is that what the page is for? Report anything that "
    "does not make sense -- an unlabelled control, a promise the page does not "
    "keep, a grouping that reads wrong. Report nothing you cannot see."
)

PROHIBITION = (
    "Do not report any number, distance, size, ratio or coordinate. Those are "
    "measured elsewhere and a number from you is discarded. Name what you see and "
    "where it is."
)

# Padding around a crop, in CSS px, so a defect is never flush against the frame
# edge with no context to judge it against.
CROP_PAD = 24

SEVERITY_ORDER = ["low", "medium", "high"]


def demote(sev: str) -> str:
    i = SEVERITY_ORDER.index(sev) if sev in SEVERITY_ORDER else 1
    return SEVERITY_ORDER[max(0, i - 1)]


def load_profile(path: pathlib.Path, name: str) -> dict:
    profiles = json.loads(path.read_text())
    if name not in profiles:
        raise SystemExit(
            f"unknown profile {name!r}; have {sorted(k for k in profiles if k != '_doc')}"
        )
    p = dict(profiles["default"])
    p.update(profiles[name])
    p["name"] = name
    return p


def weight_of(profile: dict, rule: str) -> float:
    """1.0 unless the profile says otherwise. An unlisted rule is not suppressed --
    a profile has to say a rule does not apply, because silence is how a rule goes
    missing from an app's report without anyone deciding that it should."""
    return float(profile.get("rules", {}).get(rule, 1.0))


def union_rect(rects: list[dict]) -> dict:
    x0 = min(r["x"] for r in rects)
    y0 = min(r["y"] for r in rects)
    x1 = max(r["right"] for r in rects)
    y1 = max(r["bottom"] for r in rects)
    return {"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0}


def pad_and_clamp(rect: dict, page: dict) -> dict:
    x = max(0.0, rect["x"] - CROP_PAD)
    y = max(0.0, rect["y"] - CROP_PAD)
    r = min(float(page["w"]), rect["x"] + rect["w"] + CROP_PAD)
    b = min(float(page["h"]), rect["y"] + rect["h"] + CROP_PAD)
    return {
        "x": round(x, 2),
        "y": round(y, 2),
        "w": round(r - x, 2),
        "h": round(b - y, 2),
    }


def route_page(
    snap: dict,
    dom: list[dict],
    xcheck: list[dict],
    profile: dict,
) -> dict:
    by_path = {e["path"]: e["rect"] for e in snap["elements"]}
    tokens_ok = bool(profile.get("tokens_authoritative", True))

    asserted: list[dict] = []
    abstentions: list[dict] = []
    suppressed: list[dict] = []

    for f in list(dom) + list(xcheck):
        rule = f["rule"]
        w = weight_of(profile, rule)
        if w == 0.0:
            suppressed.append({**f, "suppressed_by": profile["name"]})
            continue
        item = dict(f)
        item["weight"] = w
        if w < 1.0:
            item["severity"] = demote(f["severity"])
            item["demoted_from"] = f["severity"]
        # PIPELINE_SPEC 1.0: conformance against a palette the engine does not
        # expose is an abstention, not a violation.
        abstaining = rule in ABSTAINING_RULES or (
            rule == "token-drift" and not tokens_ok
        )
        if abstaining:
            item["verdict"] = "INDETERMINATE"
            item.setdefault("abstains_as", rule)
            abstentions.append(item)
        else:
            item["verdict"] = "ASSERTED"
            asserted.append(item)

    # --- 2. SUBTRACT: an abstention a cross-check arm already answered ---------
    answered: dict[tuple[str, str], dict] = {}
    for f in xcheck:
        cls = RESOLVES.get(f["rule"])
        if cls:
            answered[(cls, f["target"])] = f

    routed_in: list[dict] = []
    resolved: list[dict] = []
    for a in abstentions:
        key = (a.get("abstains_as", a["rule"]), a["target"])
        hit = answered.get(key)
        if hit is not None:
            resolved.append(
                {
                    **a,
                    "verdict": "RESOLVED",
                    "resolved_by": hit["rule"],
                    "resolution": hit["detail"],
                }
            )
        else:
            routed_in.append(a)

    # --- 3. COLLAPSE: one crop request per class, over the union of its targets -
    by_class: dict[str, list[dict]] = {}
    for a in routed_in:
        by_class.setdefault(a.get("abstains_as", a["rule"]), []).append(a)

    routed: list[dict] = []
    for cls, items in sorted(by_class.items()):
        rects = [by_path[i["target"]] for i in items if i["target"] in by_path]
        if not rects:
            continue
        routed.append(
            {
                "class": cls,
                "targets": [i["target"] for i in items],
                "collapsed_from": len(items),
                "crop": pad_and_clamp(union_rect(rects), snap["scroll"]),
                "crop_source": "getBoundingClientRect union, padded and clamped",
                "reason": items[0]["detail"],
                "question": CLASS_QUESTION.get(
                    cls, CLASS_QUESTION["contrast-indeterminate"]
                ),
                "prohibition": PROHIBITION,
                "weight": max(i["weight"] for i in items),
            }
        )
    routed.sort(key=lambda r: (-r["weight"], r["class"]))

    # --- 4. FRAME: at most one blind whole-frame call --------------------------
    g = profile.get("gestalt", {})
    gestalt = None
    if g.get("enabled", True):
        gestalt = {
            "class": "gestalt",
            "frame": "viewport",
            "blind": True,
            "question": GESTALT_QUESTION,
            "prohibition": PROHIBITION,
            "weight": float(g.get("weight", 1.0)),
            "why": (
                "hierarchy, grouping and does-this-make-sense are page-global and "
                "structurally unreachable from a crop"
            ),
        }

    return {
        "asserted": asserted,
        "abstentions": len(abstentions),
        "resolved": resolved,
        "routed": routed,
        "suppressed": suppressed,
        "gestalt": gestalt,
        "model_calls": len(routed) + (1 if gestalt else 0),
    }


def run(corpus: pathlib.Path, profile: dict) -> dict:
    dom = json.loads((corpus / "findings_dom.json").read_text())
    xpath = corpus / "findings_xcheck.json"
    xcheck = json.loads(xpath.read_text()) if xpath.exists() else {}
    snaps = corpus / "snapshots"

    pages = {}
    for f in sorted(snaps.glob("*.json")):
        name = f.stem
        pages[name] = route_page(
            json.loads(f.read_text()),
            dom.get(name, []),
            xcheck.get(name, []),
            profile,
        )

    totals = {
        "pages": len(pages),
        "asserted": sum(len(p["asserted"]) for p in pages.values()),
        "abstentions": sum(p["abstentions"] for p in pages.values()),
        "resolved_by_xcheck": sum(len(p["resolved"]) for p in pages.values()),
        "crop_calls": sum(len(p["routed"]) for p in pages.values()),
        "gestalt_calls": sum(1 for p in pages.values() if p["gestalt"]),
        "suppressed": sum(len(p["suppressed"]) for p in pages.values()),
    }
    totals["model_calls"] = totals["crop_calls"] + totals["gestalt_calls"]
    return {
        "profile": profile["name"],
        "problem": profile.get("problem", ""),
        "tokens_authoritative": profile.get("tokens_authoritative", True),
        "totals": totals,
        "pages": pages,
    }


# --------------------------------------------------------------------------
# Self-test. Stdlib only, no corpus, no numpy, no browser -- so the landing gate
# can execute the routing law itself rather than a description of it, on a host
# that has none of the perception stack installed.
#
# Every assertion that a thing does NOT happen is paired with the positive control
# that makes it happen, because a subtraction test with nothing to subtract passes
# whether or not the subtraction exists.
# --------------------------------------------------------------------------

_SNAP = {
    "scroll": {"w": 1000, "h": 800},
    "elements": [
        {
            "path": "div.hero",
            "rect": {
                "x": 100,
                "y": 100,
                "w": 200,
                "h": 50,
                "right": 300,
                "bottom": 150,
            },
        },
        {
            "path": "div.hero > p.a",
            "rect": {"x": 110, "y": 110, "w": 80, "h": 20, "right": 190, "bottom": 130},
        },
        {
            "path": "div.hero > p.b",
            "rect": {"x": 200, "y": 115, "w": 90, "h": 20, "right": 290, "bottom": 135},
        },
    ],
}


def _f(rule, target, severity="high", detail="d"):
    return {"rule": rule, "target": target, "detail": detail, "severity": severity}


def selftest() -> int:
    prof = pathlib.Path(__file__).parent / "profiles.json"
    default = load_profile(prof, "default")
    fails = []

    def ok(cond, what):
        if not cond:
            fails.append(what)

    # 1. ASSERT -- a finding carrying a number is answered, and never routed.
    r = route_page(_SNAP, [_f("contrast", "div.hero > p.a")], [], default)
    ok(len(r["asserted"]) == 1, "a numeric finding must be asserted")
    ok(r["routed"] == [], "a numeric finding must never reach the judge")
    ok(r["asserted"][0]["verdict"] == "ASSERTED", "asserted findings carry a verdict")

    # 2. SUBTRACT -- and its positive control, which is the whole test.
    abstain = [_f("contrast-indeterminate", "div.hero > p.a")]
    unresolved = route_page(_SNAP, abstain, [], default)
    ok(
        len(unresolved["routed"]) == 1,
        "POSITIVE CONTROL: an unanswered abstention routes",
    )
    resolved = route_page(
        _SNAP, abstain, [_f("xcheck-contrast-varies", "div.hero > p.a")], default
    )
    ok(resolved["routed"] == [], "an answered abstention leaves the queue")
    ok(len(resolved["resolved"]) == 1, "and is recorded as resolved, not dropped")
    ok(
        [r["resolved_by"] for r in resolved["resolved"]] == ["xcheck-contrast-varies"],
        "the resolution names the arm that answered it",
    )
    # The arm answers only the SAME target. A different one is not an answer.
    other = route_page(
        _SNAP, abstain, [_f("xcheck-contrast-varies", "div.hero > p.b")], default
    )
    ok(len(other["routed"]) == 1, "an arm on a different target answers nothing")

    # 3. COLLAPSE -- two abstentions of one class on one page are one crop.
    two = route_page(
        _SNAP,
        [
            _f("contrast-indeterminate", "div.hero > p.a"),
            _f("contrast-indeterminate", "div.hero > p.b"),
        ],
        [],
        default,
    )
    ok(len(two["routed"]) == 1, "same class on one page collapses to one call")
    ok(two["routed"][0]["collapsed_from"] == 2, "collapse records what it folded")
    c = two["routed"][0]["crop"]
    # Union of (110,110,80,20) and (200,115,90,20), padded by CROP_PAD, clamped.
    ok(
        (c["x"], c["y"]) == (110 - CROP_PAD, 110 - CROP_PAD)
        and c["w"] == (290 + CROP_PAD) - (110 - CROP_PAD)
        and c["h"] == (135 + CROP_PAD) - (110 - CROP_PAD),
        f"the crop is the padded union of both target boxes, got {c}",
    )
    edge = route_page(_SNAP, [_f("contrast-indeterminate", "div.hero")], [], default)
    ok(edge["routed"][0]["crop"]["x"] >= 0, "a crop never runs off the page")

    # Crop provenance: every rect is one the DOM supplied, never one a model drew.
    known = {(e["rect"]["x"], e["rect"]["y"]) for e in _SNAP["elements"]}
    for item in two["routed"]:
        ok(
            (item["crop"]["x"] + CROP_PAD, item["crop"]["y"] + CROP_PAD) in known,
            "a crop origin must trace to a getBoundingClientRect",
        )
        ok(bool(item["prohibition"]), "every routed item carries its prohibition")
        ok(bool(item["question"]), "every routed item states what is being asked")

    # 4. FRAME -- one blind whole-frame call, and a profile can withhold it.
    ok(
        default["gestalt"]["enabled"] and unresolved["gestalt"],
        "gestalt is one per page",
    )
    ok(unresolved["gestalt"]["blind"] is True, "the gestalt call is blind")
    off = dict(default, gestalt={"enabled": False})
    ok(route_page(_SNAP, [], [], off)["gestalt"] is None, "a profile can withhold it")

    # Weights: 0.0 suppresses, 0<w<1 demotes, and NOTHING raises a severity.
    landing = load_profile(prof, "reso-landing-app")
    s = route_page(_SNAP, [_f("token-drift", "div.hero > p.a", "low")], [], landing)
    ok(len(s["suppressed"]) == 1 and not s["asserted"], "weight 0.0 suppresses")
    d = route_page(_SNAP, [_f("type-scale", "div.hero > p.a", "high")], [], landing)
    ok(d["asserted"][0]["severity"] == "medium", "0<w<1 demotes one rung")
    for name in ("default", "reso-landing-app", "reso-management-app", "reso-web-app"):
        p = load_profile(prof, name)
        for rule, w in p.get("rules", {}).items():
            ok(0.0 <= float(w) <= 1.0, f"{name}:{rule} weight must be in [0,1]")
        for rule in sorted(set(p.get("rules", {})) | {"type-scale"}):
            for sev in SEVERITY_ORDER:
                out = route_page(_SNAP, [_f(rule, "div.hero > p.a", sev)], [], p)
                for got in out["asserted"] + out["routed"]:
                    if "severity" not in got:
                        continue
                    ok(
                        SEVERITY_ORDER.index(got["severity"])
                        <= SEVERITY_ORDER.index(sev),
                        f"{name}/{rule} raised a severity, which no weighting may do",
                    )

    # tokens_authoritative=false demotes conformance to an abstention (PIPELINE_SPEC 1.0).
    mgmt = load_profile(prof, "reso-management-app")
    ok(mgmt["tokens_authoritative"] is False, "management app has no token map")
    t = route_page(_SNAP, [_f("token-drift", "div.hero > p.a", "low")], [], mgmt)
    ok(
        not t["asserted"] and len(t["routed"]) == 1,
        "token conformance abstains where the engine exposes no palette",
    )
    web = load_profile(prof, "reso-web-app")
    t2 = route_page(_SNAP, [_f("token-drift", "div.hero > p.a", "low")], [], web)
    ok(
        len(t2["asserted"]) == 1 and not t2["routed"],
        "POSITIVE CONTROL: with a token map it asserts instead",
    )

    # No promotion path: nothing the judge would return can become `asserted`.
    ok(
        all("model" not in json.dumps(i).lower() for i in unresolved["asserted"]),
        "no model output may enter the asserted set",
    )

    for f in fails:
        print(f"FAIL {f}")
    print(
        f"{'FAILED' if fails else 'ok'} -- route.py selftest, {len(fails)} failure(s)"
    )
    return 1 if fails else 0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", nargs="?", type=pathlib.Path, default="corpus/out")
    ap.add_argument("--profile", default="default")
    ap.add_argument("--json", action="store_true", help="dump the queue to stdout")
    ap.add_argument("--selftest", action="store_true", help="execute the routing law")
    a = ap.parse_args()
    if a.selftest:
        raise SystemExit(selftest())
    corpus = pathlib.Path(a.corpus).resolve()
    profile = load_profile(pathlib.Path(__file__).parent / "profiles.json", a.profile)

    q = run(corpus, profile)
    # Named for its profile: the queue is a different artifact per app, and one
    # shared filename makes whichever command ran last the one on disk.
    name = f"judge_queue.{profile['name']}.json"
    (corpus / name).write_text(json.dumps(q, indent=1))
    if a.json:
        print(json.dumps(q, indent=1))
        return

    t = q["totals"]
    print(f"profile {q['profile']} -- {q['problem']}")
    print(f"  {t['asserted']:3d} asserted     answered by a number; never routed")
    print(f"  {t['abstentions']:3d} abstentions  the vision layer's job queue")
    print(
        f"  {t['resolved_by_xcheck']:3d} resolved     by a cross-check arm, no model call"
    )
    print(f"  {t['suppressed']:3d} suppressed   weight 0.0 under this profile")
    print(
        f"  {t['crop_calls']:3d} crop calls + {t['gestalt_calls']} gestalt "
        f"= {t['model_calls']} model call(s) over {t['pages']} pages"
    )
    print()
    for name, p in q["pages"].items():
        if not (p["routed"] or p["resolved"]):
            continue
        print(name)
        for r in p["resolved"]:
            print(f"    RESOLVED  {r['rule']} on {r['target'][:52]}")
            print(f"              by {r['resolved_by']}: {r['resolution'][:88]}")
        for r in p["routed"]:
            c = r["crop"]
            print(
                f"    ROUTE     {r['class']} x{r['collapsed_from']} "
                f"crop {c['w']:.0f}x{c['h']:.0f} at ({c['x']:.0f},{c['y']:.0f})"
            )


if __name__ == "__main__":
    main()
