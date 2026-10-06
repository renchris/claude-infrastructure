#!/usr/bin/env python3
"""RULE 1 of wave E1h as code: replay the frozen join-rule list over e1h-tune.py's per-call data and
say which configurations are eligible and which one is selected, or STOP. The rule's text is in
docs/plans/RESEARCH_PROGRAM_BUILD.md (wave E1h), committed before any tuning call; nothing here is a
choice made after seeing a result.

  e1h-score.py counts            the tuning base's counts (no classifier data needed)
  e1h-score.py TUNE.json         the per-configuration table and the RULE 1 outcome

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
"""

import hashlib
import json
import sys
from pathlib import Path

H = Path.home() / ".claude/autonomy/research/router-heldout"
REL = ("completeness", "pushback")
COMPLETENESS_STRATA = ("regex-matched", "regex-missed", "pushback")
FAST_LIM, CARE_LIM = 9.0, 8.5
FAST_ARMS = ("haiku-off", "sonnet-off")
CARE_ARMS = ("haiku-on", "sonnet-on")
# RULE 1's numbers
MIN_OTHER, MIN_RECALL, MIN_MISSED, MIN_BORDER, TIE = 0.95, 0.98, 0.95, 0.50, 0.05


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
    other, recall, missed, border, v1_other, false_relay, times = (
        [],
        [],
        [],
        [],
        [],
        [],
        [],
    )
    fallbacks = total = 0
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
    ):
        m[name], m[name + "_n"] = frac(pairs)
    m["fallback"] = f"{fallbacks}/{total}"
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


def main() -> int:
    rows = base()
    if sys.argv[1] == "counts":
        print(json.dumps(counts(rows), sort_keys=True, indent=1))
        return 0
    data = json.load(open(sys.argv[1]))
    calls = data["calls"]
    done = sum(1 for k in rows if k in calls)
    print(
        f"tuning rows with calls: {done} of {len(rows)}; meta {json.dumps(data['meta'], sort_keys=True)}"
    )
    table = [score(rows, calls, "alone", X, "") for X in FAST_ARMS]
    for rule in ("union", "confirms", "veto"):
        table += [score(rows, calls, rule, X, Y) for X in FAST_ARMS for Y in CARE_ARMS]
    # the careful arms alone are shown for the record; the frozen list does not make them candidates
    shown = [score(rows, calls, "alone", Y, "") for Y in CARE_ARMS]
    cols = (
        "other_n",
        "recall_n",
        "regex_missed_n",
        "borderline_n",
        "fallback",
        "v1_other_n",
        "false_relay_n",
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
