#!/usr/bin/env python3
"""Wave E1k's real-load A/B report (RULE E1k in docs/plans/RESEARCH_PROGRAM_BUILD.md, committed before
the run): hedge on vs off through the live router, rows alternating by arm.

  e1k-ab-report.py CALLS.json TRACE.jsonl SIDECAR.jsonl [--redact-trace OUT.jsonl]

CALLS.json is e1i-latency.py --hedge-ab's output; TRACE.jsonl the router's CC_RESEARCH_CLASSIFY_TRACE;
SIDECAR.jsonl e1k-sidecar.py's samples of the warm daemon's children. Prints, per arm and load band
(the call's 1-min load at its end, as E1j's table), rows, fallbacks, median, p90 and rows held with
one call silent; the hedge's fire and win counts per kind; the stall attribution; and the verdict:
PASS = hedge-on fallback <= 0.03 with >= 40 hedge-on rows above load 150; FAIL = above 0.03 with that
many; else "high load not exercised" (no verdict). --redact-trace writes the trace with any non-label
answer text replaced by its length (an answer can carry prompt text; E1j's learning).
"""

import json
import re
import sys
from statistics import median
from typing import Any, Dict, List, Optional

BANDS = [
    ("under 100", 0, 100),
    ("100-150", 100, 150),
    ("150-250", 150, 250),
    ("250 and over", 250, 1e9),
]
MAX_FALLBACK, MIN_HIGH, HIGH = 0.03, 40, 150
KINDS = ("fast", "careful")


def p90(xs: List[float]) -> Optional[float]:
    s = sorted(xs)
    return s[int(len(s) * 0.9)] if s else None


def band(load: float) -> str:
    return next(name for name, lo, hi in BANDS if lo <= load < hi)


def join(calls: List[Dict[str, Any]], trace: List[Dict[str, Any]]) -> None:
    """Attach each call's router rows (final, stall, held): the router's t0 falls just after the call's t."""
    order = sorted(calls, key=lambda c: c["t"])
    for c in order:
        c["rows"] = {}
    for r in trace:
        t = r.get("t")
        if t is None:
            continue
        cands = [c for c in order if c["t"] - 0.05 <= t <= c["t"] + 5]
        if not cands:
            continue
        c = max(cands, key=lambda c: c["t"])
        c["rows"][r.get("row") or "final"] = r


def attribute(
    t0: float, wall: float, kind: str, sc: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """RULE E1k's attribution for one call of `kind` pending on the warm path."""
    before = [s for s in sc if s.get("pid") and s["t"] <= t0]
    if not before:
        return {"cause": "unattributed", "why": "no sample before the row"}
    last_t = max(s["t"] for s in before)
    live = [s for s in before if s["t"] == last_t and s["kind"] == kind]
    if not live:
        return {"cause": "unattributed", "why": "no live worker of the kind"}
    w = max(live, key=lambda s: s["etime_s"])  # Pool.take hands out the oldest
    pid = w["pid"]
    earlier = [s for s in sc if s.get("pid") == pid and s["t"] <= t0 - 3]
    base = max(earlier, key=lambda s: s["t"])["cpu_s"] if earlier else 0.0
    out = {
        "pid": pid,
        "age_s": w["etime_s"],
        "cpu_at_take": w["cpu_s"],
        "cpu_rise_3s": round(w["cpu_s"] - base, 2),
        "pri": w["pri"],
    }
    during = [s for s in sc if s.get("pid") == pid and t0 < s["t"] <= t0 + wall]
    out["samples"] = len(during)
    if during:
        out["cpu_in_call"] = round(max(s["cpu_s"] for s in during) - w["cpu_s"], 2)
    if w["cpu_s"] - base >= 0.5:
        out["cause"] = "still starting"
    elif not during:
        out["cause"] = "unattributed"
    else:
        r = sum(s["state"].startswith("R") for s in during) / len(during)
        sl = sum(s["state"].startswith("S") for s in during) / len(during)
        out["R_share"], out["S_share"] = round(r, 2), round(sl, 2)
        out["cause"] = (
            "starved mid-call"
            if r >= 0.5
            else "waiting, not starved"
            if sl > 0.5
            else "unattributed"
        )
    return out


def redact(row: Dict[str, Any]) -> Dict[str, Any]:
    def scrub(v: Any) -> Any:
        if isinstance(v, str):
            return re.sub(
                r"classifier answered (['\"])(.*?)\1, not one route label",
                lambda m: (
                    f"classifier answered <{len(m.group(2))} chars>, not one route label"
                ),
                v,
            )
        if isinstance(v, dict):
            return {k: scrub(x) for k, x in v.items()}
        return v

    return scrub(row)


def main() -> int:
    calls = json.load(open(sys.argv[1]))["calls"]
    trace = [json.loads(line) for line in open(sys.argv[2]) if line.strip()]
    sc = [json.loads(line) for line in open(sys.argv[3]) if line.strip()]
    if "--redact-trace" in sys.argv:
        with open(sys.argv[sys.argv.index("--redact-trace") + 1], "w") as fh:
            for r in trace:
                fh.write(json.dumps(redact(r), sort_keys=True) + "\n")
    join(calls, trace)
    t_first = min(c["t"] for c in calls)
    print(
        f"rows {len(calls)}; first row started {t_first:.2f}; 1-min load {min(c['load'] for c in calls)}-{max(c['load'] for c in calls)}"
    )
    print()
    print(
        "| arm | 1-min load | rows | fallbacks | median | p90 | held, one call silent |"
    )
    print("|---|---|---|---|---|---|---|")
    for arm in (True, False):
        mine = [c for c in calls if c["hedge"] is arm]
        for name, lo, hi in BANDS + [("all", 0, 1e9)]:
            b = [c for c in mine if lo <= c["load"] < hi]
            if not b:
                continue
            w = [c["wall_s"] for c in b]
            fell = sum(c["label"] is None for c in b)
            held = sum("held" in c["rows"] for c in b)
            print(
                f"| hedge {'on' if arm else 'off'} | {name} | {len(b)} | {fell} | {median(w):.2f} s | {p90(w):.2f} s | {held} |"
            )
    print()
    on = [c for c in calls if c["hedge"]]
    print(
        "| kind | hedge fired (hedge-on rows) | won | fired on a row that fell back |"
    )
    print("|---|---|---|---|")
    for k in KINDS:
        hed = [
            ((c["rows"].get("final") or {}).get("hedge") or {}).get(k) or {} for c in on
        ]
        fired = sum(bool(h.get("fired")) for h in hed)
        won = sum(bool(h.get("won")) for h in hed)
        ff = sum(bool(h.get("fired")) and c["label"] is None for h, c in zip(hed, on))
        print(f"| {k} | {fired} | {won} | {ff} |")
    missing = sum("final" not in c["rows"] for c in on)
    print(f"\nhedge-on rows with no router row (killed before it): {missing}")
    # attribution
    print("\n| arm | kind | cause | calls |")
    print("|---|---|---|---|")
    tally: Dict[tuple, int] = {}
    detail = []
    for c in calls:
        rows = c["rows"]
        t0 = next((r["t"] for r in rows.values() if "t" in r), c["t"])
        pending = []
        if c["hedge"]:
            h = (rows.get("final") or {}).get("hedge") or {}
            pending = [k for k in KINDS if (h.get(k) or {}).get("fired")]
            if not rows.get("final"):
                for rk in ("stall", "held"):
                    r = rows.get(rk) or {}
                    pending += [
                        k
                        for k in KINDS
                        if (r.get(k) or {}).get("hedge", {}).get("fired")
                        and k not in pending
                    ]
        else:
            for rk in ("stall", "held"):
                r = rows.get(rk) or {}
                pending += [
                    k
                    for k in KINDS
                    if (r.get(k) or {}).get("path") == "warm"
                    and not (r.get(k) or {}).get("answered")
                    and k not in pending
                ]
        for k in pending:
            a = attribute(t0, c["wall_s"], k, sc)
            key = ("on" if c["hedge"] else "off", k, a["cause"])
            tally[key] = tally.get(key, 0) + 1
            detail.append(
                {
                    "n": c["n"],
                    "arm": key[0],
                    "kind": k,
                    "load": c["load"],
                    "fell_back": c["label"] is None,
                    **a,
                }
            )
    for key in sorted(tally):
        print(f"| hedge {key[0]} | {key[1]} | {key[2]} | {tally[key]} |")
    high_on = [c for c in on if c["load"] > HIGH]
    rate = sum(c["label"] is None for c in on) / len(on) if on else 0.0
    if len(high_on) < MIN_HIGH:
        verdict = f"high load not exercised ({len(high_on)} hedge-on rows above load {HIGH}, need {MIN_HIGH}); no verdict"
    else:
        verdict = (
            ("PASS" if rate <= MAX_FALLBACK else "FAIL")
            + f": hedge-on fallback {sum(c['label'] is None for c in on)}/{len(on)} = {rate:.3f} (<= {MAX_FALLBACK}), {len(high_on)} hedge-on rows above load {HIGH}"
        )
    print(f"\nverdict (RULE E1k): {verdict}")
    if "--detail" in sys.argv:
        print(json.dumps(detail, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
