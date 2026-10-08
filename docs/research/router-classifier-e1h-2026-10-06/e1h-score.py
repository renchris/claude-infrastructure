#!/usr/bin/env python3
"""RULE 1 of wave E1h as code: replay the frozen join-rule list over e1h-tune.py's per-call data and
say which configurations are eligible and which one is selected, or STOP. The rule's text is in
docs/plans/RESEARCH_PROGRAM_BUILD.md (wave E1h), committed before any tuning call; nothing here is a
choice made after seeing a result.

  e1h-score.py counts            the tuning base's counts (no classifier data needed)
  e1h-score.py TUNE.json         the per-configuration table and the RULE 1 outcome; its shown-only
                                 `other_decision` column is wave E1i's row-15 `other` rule

Reads the tuning base and its two-rater labels (outside the repo); never a sealed set, and it prints
no prompt.

The frozen rule list, for each thinking-off arm X and each thinking-on arm Y (the four joins are the
ones docs/research/reask-overflag-decision-2026-10-06/confirm-rule-replay.md replayed, same code):
  X alone            X's label if it arrived inside 9 s
  union(X, Y)        wave E1g's rule: a relay from either call; else X's label; else Y's
  confirms(X, Y)     careful-confirms: X's relay stands unless Y answered in time with a non-relay
                     label (then Y's label); Y's own relay stands
  veto(X, Y)         X relays and Y may only veto: as confirms, but Y's lone relay does not stand
A careful label counts only inside the 8.5 s hand-back the live router uses; a call that was INVALID,
timed out, or arrived late is no label, and no label from either call is a fallback (a miss).

Wave E1j (2026-10-08): the arm lists are arguments, and the E1j selection rule (committed to the plan's
E1j section before any tuning call) is `--rule e1j`:

  e1h-score.py TUNE.json [--fast A,B] [--careful C,D]          RULE 1 over those arms (default E1h's)
  e1h-score.py TUNE.json --rule e1j --fast F --primary P --secondary S [--diagnostic D]
      union(F, each careful arm) against E1j's bars; prints the selection, or that no Haiku 5.5 arm
      passed (then the selection is E1i's measured Haiku 4.5 union, from tune.json, to be pinned)

Wave E1m (2026-10-08): RULE E1m (ruling 8633d354bd41, committed to the plan's E1m section before any
tuning call) over two independent runs of union(F, C):

  e1h-score.py RUN1.json --rule e1m --run2 RUN2.json --fast F --primary C
      Haiku 4.5's tuning numbers matched on both runs (regex-missed >= 41/42 and pooled recall >= 162/163
      on each run, or 82/84 and 324/326 over the two runs pooled), and no regression on each run (relay
      decision on `other` >= 229/240, wrong relays <= 36/504, borderline >= 69/138); prints the pick.
"""

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

H = Path(
    os.environ.get("E1H_TUNING_BASE")
    or Path.home() / ".claude/autonomy/research/router-heldout"
)
REL = ("completeness", "pushback")
COMPLETENESS_STRATA = ("regex-matched", "regex-missed", "pushback")
FAST_LIM, CARE_LIM = 9.0, 8.5
FAST_ARMS = ("haiku-off", "sonnet-off")
CARE_ARMS = ("haiku-on", "sonnet-on")
# RULE 1's numbers
MIN_OTHER, MIN_RECALL, MIN_MISSED, MIN_BORDER, TIE = 0.95, 0.98, 0.95, 0.50, 0.05
# Wave E1j's bars, as counts over E1h's denominators (a different denominator is held to the same
# fraction): `other` on the relay decision, pooled recall, regex-missed recall, borderline relay rate
E1J_BARS = {
    "other_decision": (228, 240),
    "recall": (160, 163),
    "regex_missed": (40, 42),
    "borderline": (69, 138),
}
E1J_MAX_FALLBACK, E1J_MAX_P90_S = 0.03, 7.5
# Wave E1m's bars (RULE E1m): Haiku 4.5's union numbers in tune.json, matched per run or pooled over two
# runs, and the no-regression bars per run; `false_relay` is a ceiling, the rest are floors
E1M_MATCH = {"regex_missed": (41, 42), "recall": (162, 163)}
E1M_MATCH_POOLED = {"regex_missed": (82, 84), "recall": (324, 326)}
E1M_FLOORS = {"other_decision": (229, 240), "borderline": (69, 138)}
E1M_CEILINGS = {"false_relay": (36, 504)}


def item_id(prompt: str) -> str:
    return hashlib.sha256(prompt.encode()).hexdigest()[:12]


def jl(name: str) -> list:
    return [json.loads(line) for line in open(H / name)]


def base() -> dict:
    """{key: {src, stratum, labels: [a, b]}} for every tuning row; a row a rater did not label has
    fewer than two labels and is neither agreed nor borderline."""
    rows = {}
    fresh_labels = {}
    for vendor in ("anthropic", "openai"):
        p = H / f"tuning-v4-labels-{vendor}.jsonl"
        for r in jl(p.name) if p.exists() else []:
            fresh_labels.setdefault(r["id"], []).append(r["label"])
    for r in jl("tuning-v4.jsonl"):
        k = item_id(r["prompt"])
        rows[f"fresh:{k}"] = {
            "src": "fresh",
            "stratum": r["stratum"],
            "labels": fresh_labels.get(k, []),
        }
    for r in jl("retired-v2.jsonl"):
        rows[f"v2:{r['id']}"] = {
            "src": "v2",
            "stratum": r["stratum"],
            "labels": list(r["labels"].values()),
        }
    v1 = jl("tuning.jsonl")
    v1_labels = {}
    for vendor in ("anthropic", "openai"):
        for r in jl(f"tuning-labels-{vendor}.jsonl"):
            v1_labels.setdefault(int(r["id"][1:]), []).append(r["label"])
    for n, r in enumerate(v1):
        rows.setdefault(
            f"v1:{item_id(r['prompt'])}",
            {"src": "v1", "stratum": r["stratum"], "labels": v1_labels.get(n, [])},
        )
    return rows


def agreed(row: dict):
    labs = row["labels"]
    return labs[0] if len(labs) >= 2 and len(set(labs)) == 1 else None


def borderline(row: dict) -> bool:
    labs = row["labels"]
    return len(labs) >= 2 and len(set(labs)) > 1 and any(lab in REL for lab in labs)


def counts(rows: dict) -> dict:
    out = {}
    for row in rows.values():
        c = out.setdefault(row["src"], {}).setdefault(
            row["stratum"], {"rows": 0, "agreed": 0, "agreed_relay": 0, "borderline": 0}
        )
        c["rows"] += 1
        g = agreed(row)
        c["agreed"] += g is not None
        c["agreed_relay"] += g in REL
        c["borderline"] += borderline(row)
    return out


def valid(x: dict) -> bool:
    return x["label"] not in ("INVALID", "TIMEOUT")


def join(rule: str, F: dict, C: dict):
    """(label or None, decision time in s). confirm-rule-replay.md's code for rules a, b, b' and e."""
    fo = valid(F) and F["wall_s"] <= FAST_LIM
    f = F["wall_s"]
    if rule == "alone":
        return (F["label"], f) if fo else (None, 9.0)
    co = valid(C) and C["wall_s"] <= CARE_LIM
    c = C["wall_s"]
    cd = min(c, CARE_LIM)
    FL, CL = F["label"], C["label"]
    if rule == "union":
        rt = [t for ok, lab, t in ((fo, FL, f), (co, CL, c)) if ok and lab in REL]
        if rt:
            return (FL if fo and FL in REL and f <= min(rt) else CL), min(rt)
        if fo:
            return FL, max(f, cd)
        if co:
            return CL, c
        return None, 9.0
    if rule in ("confirms", "veto"):
        if fo and FL in REL:
            if co:
                return (FL if CL in REL else CL), max(f, c)
            return FL, max(f, cd)
        if rule == "confirms" and co and CL in REL:
            return CL, c
        if fo:
            return FL, (max(f, cd) if rule == "confirms" else f)
        if co:
            return CL, c
        return None, 9.0
    raise ValueError(rule)


def frac(pairs: list):
    n = len(pairs)
    return (sum(pairs) / n if n else 0.0), f"{sum(pairs)}/{n}"


def score(rows: dict, calls: dict, rule: str, X: str, Y: str) -> dict:
    other, recall, missed, border, v1_other, false_relay, times, other_decision = (
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
    )
    fallbacks = total = 0
    miss: dict = {}
    for key, row in rows.items():
        per = calls.get(key)
        if not per:
            continue
        for i, F in enumerate(per[X]):
            lab, t = join(rule, F, per[Y][i] if Y else F)
            total += 1
            fallbacks += lab is None
            times.append(t)
            g = agreed(row)
            if g is not None and g not in REL:
                false_relay.append(lab in REL)
            if row["stratum"] == "other" and g is not None:
                (v1_other if row["src"] == "v1" else other).append(lab == g)
                if row["src"] != "v1":
                    # wave E1i's row-15 rule (heldout.py evaluate): the relay decision matches the
                    # gold's, a fallback a miss; shown only, RULE 1 does not read it
                    other_decision.append(
                        lab is not None and (lab in REL) == (g in REL)
                    )
                if row["src"] != "v1" and lab != g:
                    # what a miss on `other` is made of; shown only, RULE 1 does not read it
                    kind = (
                        "fallback"
                        if lab is None
                        else "relayed_wrongly"
                        if lab in REL and g not in REL
                        else "relay_missed"
                        if g in REL and lab not in REL
                        else "wrong_relay_label"
                        if g in REL
                        else "wrong_nonrelay_label"
                    )
                    miss[kind] = miss.get(kind, 0) + 1
            if row["stratum"] in COMPLETENESS_STRATA and g in REL:
                recall.append(lab in REL)
                if row["stratum"] == "regex-missed":
                    missed.append(lab in REL)
            if borderline(row):
                border.append(lab in REL)
    times.sort()
    m = {"config": f"{rule}({X}{', ' + Y if Y else ''})", "calls": total}
    for name, pairs in (
        ("other", other),
        ("recall", recall),
        ("regex_missed", missed),
        ("borderline", border),
        ("v1_other", v1_other),
        ("false_relay", false_relay),
        ("other_decision", other_decision),
    ):
        m[name], m[name + "_n"] = frac(pairs)
    m["fallback"] = f"{fallbacks}/{total}"
    m["other_misses"] = miss
    m["decide_median_s"] = times[len(times) // 2] if times else None
    m["decide_p90_s"] = times[int(len(times) * 0.9)] if times else None
    m["haiku_latest"] = "sonnet" not in X and "sonnet" not in (Y or "")
    m["eligible"] = (
        m["other"] >= MIN_OTHER
        and m["recall"] >= MIN_RECALL
        and m["regex_missed"] >= MIN_MISSED
        and m["borderline"] >= MIN_BORDER
    )
    return m


def e1j_bars(m: dict) -> dict:
    """{bar: (passed, reading)} for one union configuration under wave E1j's rule."""
    out = {}
    for name, (num, den) in E1J_BARS.items():
        got, n = (int(x) for x in m[name + "_n"].split("/"))
        out[name] = (n > 0 and got * den >= num * n, f"{got}/{n}")
    fell, total = (int(x) for x in m["fallback"].split("/"))
    out["fallback"] = (
        total > 0 and fell <= E1J_MAX_FALLBACK * total,
        f"{fell}/{total}",
    )
    out["p90"] = (
        m["decide_p90_s"] is not None and m["decide_p90_s"] <= E1J_MAX_P90_S,
        f"{m['decide_p90_s']} s",
    )
    return out


def invalid_reasons(calls: dict, arm: str) -> dict:
    """{reason: count} over an arm's INVALID and TIMEOUT calls (E1j's harness records why)."""
    out: dict = {}
    for per in calls.values():
        for c in per.get(arm, []):
            if c["label"] in ("INVALID", "TIMEOUT"):
                why = c.get("why") or c["label"]
                out[why] = out.get(why, 0) + 1
    return out


def rule_e1j(rows: dict, calls: dict, a: argparse.Namespace) -> int:
    careful = [a.primary, a.secondary] + ([a.diagnostic] if a.diagnostic else [])
    res = {}
    for Y in careful:
        m = score(rows, calls, "union", a.fast, Y)
        bars = e1j_bars(m)
        quality = all(bars[b][0] for b in E1J_BARS)
        latency = bars["fallback"][0] and bars["p90"][0]
        res[Y] = (quality, latency)
        tag = "diagnostic, never selectable" if Y == a.diagnostic else ""
        print(
            f"{m['config']:34s} "
            + " ".join(f"{b}={r}{'' if ok else ' FAIL'}" for b, (ok, r) in bars.items())
            + f" decide_median={m['decide_median_s']} s"
            + f" false_relay={m['false_relay_n']}"
            + f" quality={'pass' if quality else 'fail'} latency={'pass' if latency else 'fail'}"
            + (f" ({tag})" if tag else "")
        )
    for Y in [a.fast] + careful:
        inv = invalid_reasons(calls, Y)
        if inv:
            print(
                f"  {Y} INVALID/TIMEOUT: {sum(inv.values())}: "
                + json.dumps(inv, sort_keys=True)[:600]
            )
    pq, pl = res[a.primary]
    sq, sl = res[a.secondary]
    if pq and pl:
        sel = f"union({a.fast}, {a.primary}): the primary arm passes every bar"
    elif pq and not pl and sq and sl:
        sel = (
            f"union({a.fast}, {a.secondary}): the primary passes every quality bar and fails "
            "the latency bar alone, and the secondary passes every bar"
        )
    else:
        sel = None
    if sel:
        print("SELECTED: " + sel)
    else:
        print(
            "SELECTED: no Haiku 5.5 arm passed — the selection is the measured Haiku 4.5 union, "
            "union(sonnet-off, haiku-on) in tune.json (wave E1i's), to be pinned"
        )
    return 0


def held(m: dict, name: str, bar: tuple, ceiling: bool = False) -> tuple:
    """(passed, "got/n") for a count bar over the bar's own denominator (another denominator is held
    to the same fraction)."""
    num, den = bar
    got, n = (int(x) for x in m[name + "_n"].split("/"))
    ok = n > 0 and (got * den <= num * n if ceiling else got * den >= num * n)
    return ok, f"{got}/{n}"


def rule_e1m(rows: dict, a: argparse.Namespace) -> int:
    runs = []
    for path in (a.tune, a.run2):
        calls = json.load(open(path))["calls"]
        m = score(rows, calls, "union", a.fast, a.primary)
        bars = {b: held(m, b, v) for b, v in E1M_MATCH.items()}
        bars |= {b: held(m, b, v) for b, v in E1M_FLOORS.items()}
        bars |= {b: held(m, b, v, ceiling=True) for b, v in E1M_CEILINGS.items()}
        runs.append((path, m, bars))
        print(
            f"{Path(path).name}: {m['config']} "
            + " ".join(f"{b}={r}{'' if ok else ' FAIL'}" for b, (ok, r) in bars.items())
            + f" fallback={m['fallback']} decide_median={m['decide_median_s']} s"
            f" decide_p90={m['decide_p90_s']} s"
        )
    pooled = {}
    for b, (num, den) in E1M_MATCH_POOLED.items():
        got = sum(int(m[b + "_n"].split("/")[0]) for _, m, _ in runs)
        n = sum(int(m[b + "_n"].split("/")[1]) for _, m, _ in runs)
        pooled[b] = (n > 0 and got * den >= num * n, f"{got}/{n}")
    print(
        "pooled over the two runs: "
        + " ".join(f"{b}={r}{'' if ok else ' FAIL'}" for b, (ok, r) in pooled.items())
    )
    each = all(bars[b][0] for _, _, bars in runs for b in E1M_MATCH)
    match = each or all(ok for ok, _ in pooled.values())
    noreg = all(
        bars[b][0] for _, _, bars in runs for b in (*E1M_FLOORS, *E1M_CEILINGS)
    )
    print(
        f"match Haiku 4.5: {'pass' if match else 'FAIL'} ({'each run' if each else 'pooled' if match else 'neither each run nor pooled'}); "
        f"no regression on each run: {'pass' if noreg else 'FAIL'}"
    )
    if match and noreg:
        print(
            f"PICK: union({a.fast}, {a.primary}) — Haiku 5.5, re-tuned, passes every bar of RULE E1m"
        )
    else:
        print(
            "PICK: the Haiku 4.5 union — a bar of RULE E1m failed, so the rule locks in union(Sonnet "
            "fast call, Haiku 4.5 careful call)"
        )
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="e1h-score.py")
    ap.add_argument("tune", help="counts, or a tuning run's JSON")
    ap.add_argument("--rule", choices=("e1h", "e1j", "e1m"), default="e1h")
    ap.add_argument("--run2")
    ap.add_argument("--fast", default=",".join(FAST_ARMS))
    ap.add_argument("--careful", default=",".join(CARE_ARMS))
    ap.add_argument("--primary")
    ap.add_argument("--secondary")
    ap.add_argument("--diagnostic")
    a = ap.parse_args()
    rows = base()
    if a.tune == "counts":
        print(json.dumps(counts(rows), sort_keys=True, indent=1))
        return 0
    if a.rule == "e1m":
        if not (a.primary and a.run2) or "," in a.fast:
            ap.error("--rule e1m needs --run2, one --fast arm and --primary")
        return rule_e1m(rows, a)
    data = json.load(open(a.tune))
    calls = data["calls"]
    done = sum(1 for k in rows if k in calls)
    print(
        f"tuning rows with calls: {done} of {len(rows)}; meta {json.dumps(data['meta'], sort_keys=True)}"
    )
    if a.rule == "e1j":
        if not (a.primary and a.secondary) or "," in a.fast:
            ap.error("--rule e1j needs one --fast arm, --primary and --secondary")
        return rule_e1j(rows, calls, a)
    fast_arms, care_arms = a.fast.split(","), a.careful.split(",")
    table = [score(rows, calls, "alone", X, "") for X in fast_arms]
    for rule in ("union", "confirms", "veto"):
        table += [score(rows, calls, rule, X, Y) for X in fast_arms for Y in care_arms]
    # the careful arms alone are shown for the record; the frozen list does not make them candidates
    shown = [score(rows, calls, "alone", Y, "") for Y in care_arms]
    cols = (
        "other_n",
        "recall_n",
        "regex_missed_n",
        "borderline_n",
        "fallback",
        "v1_other_n",
        "false_relay_n",
        "other_decision_n",
    )
    for m in table + shown:
        tag = (
            "ELIGIBLE"
            if m["eligible"] and m in table
            else "shown only"
            if m in shown
            else "-"
        )
        print(
            f"{m['config']:34s} "
            + " ".join(f"{c[:-2] if c.endswith('_n') else c}={m[c]}" for c in cols)
            + f" other={m['other']:.3f} recall={m['recall']:.3f} missed={m['regex_missed']:.3f}"
            f" border={m['borderline']:.3f} decide={m['decide_median_s']}/{m['decide_p90_s']}s {tag}"
            f" other_misses={json.dumps(m['other_misses'], sort_keys=True)}"
        )
    eligible = [m for m in table if m["eligible"]]
    if not eligible:
        print(
            "RULE 1: STOP — no configuration is eligible (other >= 0.95, recall >= 0.98 pooled and "
            ">= 0.95 in regex-missed, borderline >= 0.50). Nothing is landed, v4 is not sealed, no read."
        )
        return 0
    top = max(m["borderline"] for m in eligible)
    tied = [m for m in eligible if top - m["borderline"] <= TIE]
    order = sorted(tied, key=lambda m: (-m["other"], not m["haiku_latest"]))
    print("RULE 1: eligible: " + ", ".join(m["config"] for m in eligible))
    print(
        f"  step 1, borderline within {TIE} of the best ({top:.3f}): "
        + ", ".join(m["config"] for m in tied)
    )
    print(
        "  steps 2-3, by other, then a haiku_latest model: "
        + " > ".join(
            f"{m['config']} ({m['other']:.3f}{', haiku_latest' if m['haiku_latest'] else ''})"
            for m in order
        )
    )
    same = [
        m
        for m in order
        if (m["other"], m["haiku_latest"])
        == (order[0]["other"], order[0]["haiku_latest"])
    ]
    if len(same) > 1:
        print(
            "  step 4 decides among "
            + ", ".join(m["config"] for m in same)
            + ": the lower warm median latency"
        )
    print(f"SELECTED (before the warm latency check): {order[0]['config']}")
    print(
        "NEXT ELIGIBLE, in order: "
        + ", ".join(
            m["config"] for m in order[1:] + [m for m in eligible if m not in tied]
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
