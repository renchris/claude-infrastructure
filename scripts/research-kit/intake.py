#!/usr/bin/env python3
"""intake.py — stage 1 of a research program: registration, the §3.1 rulings, the frame skeleton and
the contract page (REPORT.md §3.1, §3.2, §8 item 8; docs/plans/RESEARCH_PROGRAM_BUILD.md wave B2).

The `research-program` skill drives it; the operator never needs to. It writes only the program's
tracked records (`docs/research/<slug>/` in the deliverable repo) and registers the program through
`gate.sh register` — never the registry directly, because gate.sh is its only writer (§8 item 7).

  intake.py init     --program P --root <deliverable repo> --profile lite|standard|full
                     --deliverable "<one sentence, numbers, no superlatives>" --intent "<operator words>"
                     [--alias A ...]
  intake.py ruling   --program P --which definition-of-complete|exemption --adopt --quote "<words>"
  intake.py ruling   --program P --which ... --decline --quote "<words>"   (closes the program)
  intake.py ruling   --show                                               (the two rulings' text)
  intake.py map      --program P --fac FAC-NN (--row ID | --na "<reason>")
  intake.py map      --program P --frame "<historical frame>" (--axis ID | --excluded "<operator words>")
  intake.py set      --program P [--escape-cost-days N] [--release-gap-days N] [--reference-days N]
  intake.py contract-page --program P
  intake.py lint     --program P      gate row 1 minus the signature: what still blocks the frame
  intake.py status   --program P      the intake steps, done or not

Order matters in exactly one place, and the script enforces it: the contract page refuses until
`courier.sh preflight` has run, strictly earlier, with every vendor lane live (gate row 13 fails a
contract page that precedes the preflight, §3.2 step 6). It also refuses until both rulings are
recorded and the escape cost is a finite number (§3.2 step 2, question 10).

Exit codes, as the rest of the kit: 0 ok · 1 a check failed (lint, status) · 2 usage or refusal ·
3 a dead vendor lane at the contract page.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "lib"))
sys.path.insert(0, str(HERE.parents[1] / "scripts" / "lib"))
import kit  # noqa: E402
from courier import REVIEWER_EFFORT  # noqa: E402

SKILL = HERE.parents[1] / "skills" / "research-program"
CHECKLIST = SKILL / "checklist.jsonl"
DEAD = 3

# §3.1, both rulings, with the operator's own earlier words they are weighed against.
RULINGS = {
    "definition_of_complete": (
        '"Research 100.00/100.00" means, on one frozen snapshot: every row of the signed frame closed '
        "with a script-checked receipt (exactly 100.00%); review stopped under the pre-registered rule; "
        "the certificate prints the forecast of material changes after signoff (desk-detectable, "
        "invisible, total, each with a 95% bound); every item research cannot reach is listed with an "
        "owner, a date and a check; and you signed the content hash. It supersedes, inside program "
        'scope, your words of 09-14 ("ALWAYS fix until 100.00 ... including all new found work") and '
        '09-27 ("no take-backs, redo, or incremental research later down the line"). The only '
        "activities after the certificate, which you sign are not research: narrowing a carried set on "
        "its dated probe, scheduled residual checks, scheduled freshness and market checks, fixing a "
        "counted escape, one bounded frame-delta cycle for frame omissions found during certification, "
        "and the parked-ideas batch."
    ),
    "exemption": (
        "From intake through build, in any session working on this program: a refinement is filed to "
        "the apply-at-build list, not driven now; a decision closed by timebox, packet default or as a "
        'carried set carries a "research exhausted at timebox" receipt that satisfies the 90%-conviction '
        "rule; a completeness or pushback question is answered by relaying the certificate, and the "
        "residuals it names are not open work; new ideas park in the next version. Outside active "
        "programs nothing changes."
    ),
}
POST_CERT_ACTIVITIES = [
    "narrowing a carried set on its dated probe",
    "scheduled residual checks",
    "scheduled freshness and market checks",
    "fixing a counted escape",
    "one bounded frame-delta cycle for frame omissions found during certification (§5.4)",
    "the parked-ideas batch",
]
# §3.2 step 2, question 12: the operator's historical question frames. Each maps to a certificate
# line or is excluded in the operator's words (gate row 1).
HISTORICAL_FRAMES = ["deployed and live", "nothing can beat it", "no loose ends"]
# §6.1, as printed: typical total and ceiling in agent-days. The ceiling formula's own arithmetic is
# the report's; it is copied, not re-derived, so the contract page and the report cannot disagree.
# Method v1.2 (ruling 1bf69e5c1775): a frame stamped 1.2 takes the v1.2 gate rows; a frame with no
# stamp reads as 1.1, so programs that began before it keep the gate they signed.
METHOD_VERSION = "1.2"
# Registry states of a program that is past intake and not closed; build-certifying and
# build-certified are v1.2's built-artifact certification stage.
LIVE_STATES = ("registered", "certifying", "certified", "build-certifying", "build-certified")
PROFILE_DAYS = {"lite": (6.5, 12.0), "standard": (14.0, 28.0), "full": (20.0, 39.0)}
REFERENCE_FACTOR = 3.0  # §6.3


class Refused(kit.KitError):
    pass


def records(slug: str) -> Path:
    return kit.records_dir(slug)


def load_frame(slug: str) -> Dict[str, Any]:
    fr = kit.read_json(records(slug) / "frame.json")
    if not fr:
        raise Refused(f"no frame.json for {slug}; run intake.py init first")
    return fr


def save_frame(slug: str, fr: Dict[str, Any]) -> None:
    kit.write_json_atomic(records(slug) / "frame.json", fr)


def log(slug: str, event: str, **kw: Any) -> None:
    kit.append_jsonl(records(slug) / "intake.jsonl", dict(event=event, **kw))


def checklist() -> List[Dict[str, str]]:
    return kit.read_jsonl(CHECKLIST)


def superlative_check(text: str, what: str) -> None:
    import gate_rows_a  # deferred: it imports gate, which imports kit

    if gate_rows_a.numberless_superlative(text):
        raise Refused(
            f"{what} carries a numberless superlative ({gate_rows_a.SUPERLATIVE.pattern}); "
            "turn it into a number with a measured ceiling (§3.2 step 3)"
        )


# ── verbs ───────────────────────────────────────────────────────────────────────────────────────


def cmd_init(a: argparse.Namespace) -> int:
    kit.check_slug(a.program)
    kit.profile(a.profile)
    root = os.path.realpath(a.root)
    if not os.path.isabs(a.root) or not os.path.isdir(root):
        raise Refused(f"--root {a.root!r} is not an existing absolute directory")
    superlative_check(a.deliverable, "the deliverable sentence")
    rec = Path(root) / "docs" / "research" / a.program
    if os.environ.get("CC_RESEARCH_RECORDS"):
        rec = Path(os.environ["CC_RESEARCH_RECORDS"])
    if (rec / "frame.json").exists():
        raise Refused(f"{rec}/frame.json exists; intake runs once per program")
    reg = kit.registry_get(a.program)
    if reg and reg.get("state") != "closed":
        raise Refused(f"program {a.program} is already registered ({reg.get('state')})")
    # The research index is read before mining (§3.2 step 1). It is generated in claude-infrastructure,
    # so a stale one is reported with its regeneration command, never rewritten from here: this script
    # may run from the shared checkout, where a tracked write is forbidden.
    idx = subprocess.run(
        [sys.executable, str(HERE / "research-index.py"), "--check"],
        capture_output=True,
        text=True,
    )
    index_fresh = idx.returncode == 0
    g = subprocess.run(
        [str(HERE / "gate.sh"), "register", "--program", a.program, "--root", root]
        + [x for al in (a.alias or []) for x in ("--alias", al)],
        capture_output=True,
        text=True,
    )
    if g.returncode != 0:
        raise Refused(f"gate.sh register refused: {g.stderr.strip() or g.stdout.strip()}")
    frame = {
        "program": a.program,
        "version": 1,
        "method_version": METHOD_VERSION,
        "profile": a.profile,
        "deliverable_repo": root,
        "deliverable": a.deliverable,
        "intent_verbatim": a.intent,
        "reviewer_pins": {},
        "rulings": {},
        "fac_map": [{"fac": c["id"], "row": None, "na_reason": None} for c in checklist()],
        "reask_map": [{"frame": f, "axis": None, "excluded_quote": None} for f in HISTORICAL_FRAMES],
        "sources_required": [],
        "populations": [],
        "known_rows": [],
        "escape_cost_days": None,
    }
    kit.write_json_atomic(rec / "frame.json", frame)
    kit.write_json_atomic(
        rec / "budget.json",
        {"stages": {"1": {"started": kit.now_iso(), "ended": None}}, "overrun_packets": {}},
    )
    log(a.program, "init", profile=a.profile, index_fresh=index_fresh)
    print(f"{g.stdout.strip()}\nframe skeleton: {rec / 'frame.json'}")
    wider = wider_profile_note(a.profile)
    if wider:
        print(wider, file=sys.stderr)
    if not index_fresh:
        print(
            "research index STALE: regenerate it in a claude-infrastructure worktree with "
            "`scripts/research-kit/research-index.py` before mining (§3.2 step 1)",
            file=sys.stderr,
        )
    return 0


def cmd_ruling(a: argparse.Namespace) -> int:
    if a.show:
        for k, text in RULINGS.items():
            print(f"[{k}]\n{text}\n")
        return 0
    if not (a.program and a.which and (a.adopt or a.decline)):
        raise Refused("ruling needs --program, --which and --adopt or --decline (or --show)")
    if not (a.quote or "").strip():
        raise Refused("a ruling records the operator's own words: --quote may not be empty")
    key = a.which.replace("-", "_")
    fr = load_frame(a.program)
    if a.decline:
        # A declined ruling must not look recorded: gate row 1 reads only `at`. The program makes no
        # no-take-backs claim, so it is closed rather than left half-registered (§3.1).
        fr.setdefault("rulings", {}).pop(key, None)
        fr["declined"] = {"which": key, "at": kit.now_iso(), "quote": a.quote}
        save_frame(a.program, fr)
        log(a.program, "declined", which=key, quote=a.quote)
        subprocess.run(
            [str(HERE / "gate.sh"), "close", "--program", a.program],
            check=True,
            capture_output=True,
        )
        print(
            f"{key} DECLINED: {a.program} makes no no-take-backs claim and is closed; "
            "run ordinary research instead"
        )
        return 0
    if fr.get("declined"):
        raise Refused(f"{a.program} was declined ({fr['declined']['which']}); start a new program")
    fr.setdefault("rulings", {})[key] = {"at": kit.now_iso(), "quote": a.quote}
    save_frame(a.program, fr)
    log(a.program, "ruling", which=key, quote=a.quote)
    print(f"recorded {key}")
    return 0


def cmd_map(a: argparse.Namespace) -> int:
    fr = load_frame(a.program)
    if a.fac:
        if bool(a.row) == bool(a.na):
            raise Refused("map --fac needs exactly one of --row or --na")
        hit = next((m for m in fr["fac_map"] if m.get("fac") == a.fac), None)
        if hit is None:
            raise Refused(f"{a.fac} is not a checklist row (FAC-01..FAC-{len(checklist()):02d})")
        hit.update(row=a.row or None, na_reason=a.na or None)
    elif a.frame:
        if bool(a.axis) == bool(a.excluded):
            raise Refused("map --frame needs exactly one of --axis or --excluded")
        hit = next((m for m in fr["reask_map"] if m.get("frame") == a.frame), None)
        if hit is None:
            hit = {"frame": a.frame}
            fr["reask_map"].append(hit)
        hit.update(axis=a.axis or None, excluded_quote=a.excluded or None)
    else:
        raise Refused("map needs --fac or --frame")
    save_frame(a.program, fr)
    print("mapped")
    return 0


def finite_positive(v: Optional[str], what: str) -> Optional[float]:
    if v is None:
        return None
    try:
        x = float(v)
    except ValueError:
        raise Refused(f"{what} must be a number, got {v!r}")
    if not math.isfinite(x) or x <= 0:
        # §3.2 step 2 question 10: "Infinite" means never deploy, so the program does not start.
        raise Refused(f"{what} must be a finite positive number, got {v!r}")
    return x


def cmd_set(a: argparse.Namespace) -> int:
    fr = load_frame(a.program)
    for attr, key in (
        ("escape_cost_days", "escape cost (question 10)"),
        ("release_gap_days", "mean upstream release gap"),
        ("reference_days", "measured research time for this project type"),
    ):
        v = finite_positive(getattr(a, attr), key)
        if v is not None:
            fr[attr] = v
    save_frame(a.program, fr)
    print("set")
    return 0


def forecast(profile_name: str, n0: Optional[int] = None, base: bool = False) -> Dict[str, Any]:
    """estimate.py simulate at the measured inputs (method v1.2); base=True is the assumed contrast."""
    if n0 is None:
        n0 = kit.profile(profile_name)["design_holes"]
    p = subprocess.run(
        [sys.executable, str(HERE / "estimate.py"), "simulate", "--profile", profile_name,
         "--n0", str(n0)] + (["--base"] if base else []),
        capture_output=True,
        text=True,
    )
    if p.returncode != 0:
        raise Refused(f"estimate.py simulate failed: {p.stderr.strip()}")
    return json.loads(p.stdout)


def wider_profile_note(profile_name: str) -> Optional[str]:
    """Method v1.2: a profile wider than lite is warned about when the measured forecast says the extra
    review leaves no fewer holes. Both figures are simulated here, at the same holes at freeze, so the
    warning follows params-measured.json and stops by itself once a triage fix changes the comparison."""
    if profile_name == "lite":
        return None
    n0 = kit.profile(profile_name)["design_holes"]
    lite, wide = forecast("lite", n0), forecast(profile_name, n0)
    left = lambda f: round(f["desk_left"] + f["invisible_left"], 2)  # noqa: E731
    if left(wide) < left(lite):
        return None
    return (
        f"WARNING profile {profile_name}: at the measured inputs it leaves {left(wide):g} holes after "
        f"signoff against lite's {left(lite):g} ({n0} holes at freeze; desk-detectable "
        f"{wide['desk_left']:g} against {lite['desk_left']:g}), and reaches its round cap in "
        f"{wide['cap_pct']:g}% of simulated programs. Measured false material calls "
        f"({wide['inputs']['fpp']:g} per reviewer-read) scale with the reviewer count, so wider review "
        "adds false fixes faster than it finds holes (research-calibration REPORT §5; estimate.py "
        "simulate). Lite is the default until that rate falls."
    )


def cmd_contract_page(a: argparse.Namespace) -> int:
    fr = load_frame(a.program)
    missing = [k for k in RULINGS if not (fr.get("rulings", {}).get(k) or {}).get("at")]
    if missing:
        raise Refused(f"both §3.1 rulings come first; not recorded: {', '.join(missing)}")
    if not fr.get("escape_cost_days"):
        raise Refused("the escape cost (question 10) is not set: intake.py set --escape-cost-days N")
    pf = kit.read_json(kit.sealed_dir(a.program) / "preflight.json")
    if not pf:
        raise Refused("the vendor preflight has not run: scripts/research-kit/courier.sh preflight "
                      f"--program {a.program} (§3.2 step 6)")
    now = kit.now_iso()
    if not all(str(v.get("at") or "9") < now for v in pf.values()):
        raise Refused("the vendor preflight must run strictly before the contract page (gate row 13)")
    dead = sorted(v for v, r in pf.items() if not r.get("ok"))
    if dead and fr.get("degraded") != "two vendors":
        print(
            f"DEAD LANE {', '.join(dead)}: the program pauses on one operator step to restore it "
            "(for Google, one interactive sign-in to the Antigravity CLI, `agy`); the class-B default 'continue on two vendors' "
            "fires after 48 h (§3.8)",
            file=sys.stderr,
        )
        return DEAD
    pins = dict(fr.get("reviewer_pins") or {})
    for v, r in pf.items():
        if r.get("ok") and r.get("model_id"):
            pins.setdefault(v, r["model_id"])
    # Reviewer effort is pinned beside the model ids, so the frame signature covers it too; a frame
    # that already carries reviewer_effort keeps its own (courier.REVIEWER_EFFORT is the default).
    effort = dict(fr["reviewer_effort"] if "reviewer_effort" in fr else REVIEWER_EFFORT)
    prof = kit.profile(fr["profile"])
    f = forecast(fr["profile"])
    f_base = forecast(fr["profile"], base=True)
    wider = wider_profile_note(fr["profile"])
    typical, ceiling = PROFILE_DAYS[fr["profile"]]
    lines = [
        f"# Contract page — {a.program} (frame v{fr.get('version')})",
        "",
        f"Rendered {now} by scripts/research-kit/intake.py. The frame signature "
        f"(`cc-signoff research:{a.program}/frame`) pins this page through its hash in frame.json.",
        "",
        "## Definition of complete (§3.1, ruling 1)",
        "",
        RULINGS["definition_of_complete"],
        "",
        f"Recorded {fr['rulings']['definition_of_complete']['at']}: "
        f"\"{fr['rulings']['definition_of_complete']['quote']}\"",
        "",
        "## Post-certificate activities you sign are not research",
        "",
    ] + [f"- {x}" for x in POST_CERT_ACTIVITIES] + [
        "",
        f"## Profile: {prof['name']}",
        "",
        f"- Reviewers per round {prof['reviewers_per_round']} ({prof['per_slot_set']} per slot set), "
        f"quiet rounds to stop {prof['quiet_to_stop']}, hard cap {prof['hard_cap']} rounds, "
        f"original seeds {prof['seeds_original']}.",
        f"- Stages 1–6 budget {prof['stage_budget_days']:g} agent-days; typical total about "
        f"{typical:g} days; ceiling (every loop at its cap) about {ceiling:g} days (§6.1). Only you "
        "can exceed it, through the signing tool.",
        f"- Forecast at the design point ({prof['design_holes']} holes at freeze), at the measured "
        f"inputs (method v1.2; research-calibration REPORT §3): rounds {f['rounds_p50']} typical / "
        f"{f['rounds_p90']} at the 90th percentile, the round cap reached in {f['cap_pct']}% of "
        f"simulated programs; desk-detectable left {f['desk_left']}, invisible left "
        f"{f['invisible_left']}; chance of at least one material change after signoff {f['p_any']}; "
        f"chance the 95% bound is exceeded {f['take_back_pct']}%. Model output.",
        f"- Contrast, the pre-calibration assumed inputs (what this page stated before v1.2): desk-detectable "
        f"left {f_base['desk_left']}, invisible left {f_base['invisible_left']}, chance of at least one "
        f"material change after signoff {f_base['p_any']}.",
    ] + ([f"- **{wider}**"] if wider else []) + [
        "",
        "## Your escape cost",
        "",
        f"{fr['escape_cost_days']:g} research days per decision-changing hole found after build.",
        "",
        "## Vendor preflight (responding model ids, pinned for the program)",
        "",
    ] + [
        f"- {v}: {'live' if r.get('ok') else 'DEAD'} {r.get('model_id') or '-'} at {r.get('at')}"
        for v, r in sorted(pf.items())
    ] + [
        "",
        "Reviewer effort (certification reviewers only; verifiers and raters run at their CLI's "
        "default): " + (", ".join(f"{v} {e}" for v, e in sorted(effort.items())) or "none pinned"),
    ]
    if fr.get("degraded"):
        lines += ["", f"**degraded: {fr['degraded']}**"]
    if fr.get("release_gap_days"):
        p_rel = 1 - math.exp(-typical / fr["release_gap_days"])
        lines += ["", f"Chance an upstream release lands during the program: {p_rel:.2f} "
                  f"(mean gap {fr['release_gap_days']:g} days, §6.2)."]
    override = bool(fr.get("reference_days")) and typical > REFERENCE_FACTOR * fr["reference_days"]
    if override:
        lines += ["", f"**Override required (§6.3):** the typical total {typical:g} days exceeds "
                  f"{REFERENCE_FACTOR:g} × the measured {fr['reference_days']:g} days for this "
                  "project type. Signing the frame signs this override."]
    page = "\n".join(lines) + "\n"
    out = records(a.program) / "CONTRACT.md"
    out.write_text(page)
    fr["reviewer_pins"] = pins
    fr["reviewer_effort"] = effort
    fr["contract_page_at"] = now
    fr["contract_page_sha256"] = hashlib.sha256(page.encode()).hexdigest()
    fr["reference_override"] = override
    save_frame(a.program, fr)
    log(a.program, "contract-page", sha256=fr["contract_page_sha256"])
    print(f"contract page: {out}")
    return 0


def lint_fails(slug: str) -> List[str]:
    from gate import make_ctx
    import gate_rows_a

    row = gate_rows_a.row1(make_ctx(slug))
    return [e for e in row.evidence if "signature" not in e and "signed" not in e
            and not e.startswith("frame pin") and not e.startswith("open known rows")]


def cmd_lint(a: argparse.Namespace) -> int:
    fails = lint_fails(a.program)
    for e in fails:
        print(f"FAIL {e}")
    print("frame lint: " + ("clean (sign it next)" if not fails else f"{len(fails)} to fix"))
    return 1 if fails else 0


def cmd_status(a: argparse.Namespace) -> int:
    fr = load_frame(a.program)
    reg = kit.registry_get(a.program) or {}
    pf = kit.read_json(kit.sealed_dir(a.program) / "preflight.json")
    steps = [
        ("registered", reg.get("state") in LIVE_STATES),
        ("ruling: definition of complete", bool(fr.get("rulings", {}).get("definition_of_complete"))),
        ("ruling: exemption", bool(fr.get("rulings", {}).get("exemption"))),
        ("escape cost set", bool(fr.get("escape_cost_days"))),
        ("vendor preflight", bool(pf)),
        ("contract page", bool(fr.get("contract_page_at"))),
        ("frame lint clean", not lint_fails(a.program)),
    ]
    for name, ok in steps:
        print(f"{'done' if ok else 'TODO'}  {name}")
    print(f"then: cc-signoff research:{a.program}/frame  (operator, own terminal)")
    return 0 if all(ok for _, ok in steps) else 1


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="intake.py")
    sub = ap.add_subparsers(dest="verb", required=True)
    p = sub.add_parser("init")
    p.add_argument("--program", required=True)
    p.add_argument("--root", required=True)
    p.add_argument("--profile", required=True, choices=sorted(kit.PROFILES))
    p.add_argument("--deliverable", required=True)
    p.add_argument("--intent", required=True)
    p.add_argument("--alias", action="append")
    p.set_defaults(fn=cmd_init)
    p = sub.add_parser("ruling")
    p.add_argument("--program")
    p.add_argument("--which", choices=["definition-of-complete", "exemption"])
    g = p.add_mutually_exclusive_group()
    g.add_argument("--adopt", action="store_true")
    g.add_argument("--decline", action="store_true")
    g.add_argument("--show", action="store_true")
    p.add_argument("--quote")
    p.set_defaults(fn=cmd_ruling)
    p = sub.add_parser("map")
    p.add_argument("--program", required=True)
    p.add_argument("--fac")
    p.add_argument("--row")
    p.add_argument("--na")
    p.add_argument("--frame")
    p.add_argument("--axis")
    p.add_argument("--excluded")
    p.set_defaults(fn=cmd_map)
    p = sub.add_parser("set")
    p.add_argument("--program", required=True)
    p.add_argument("--escape-cost-days")
    p.add_argument("--release-gap-days")
    p.add_argument("--reference-days")
    p.set_defaults(fn=cmd_set)
    for verb, fn in (("contract-page", cmd_contract_page), ("lint", cmd_lint),
                     ("status", cmd_status)):
        p = sub.add_parser(verb)
        p.add_argument("--program", required=True)
        p.set_defaults(fn=fn)
    a = ap.parse_args(argv)
    try:
        return int(a.fn(a))
    except kit.KitError as e:
        print(f"intake.py: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
