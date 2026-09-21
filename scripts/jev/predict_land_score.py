#!/usr/bin/env python3
"""predict_land_score.py — joins the baseline arm and (optionally) the Jev arm onto the labels and
answers the three acceptance conditions A10 froze, so they cannot be moved afterwards:

  (a) AUROC >= 0.75 on the held-out rows, with a 95% CI whose LOWER bound clears 0.65
  (b) an operating point with precision >= 0.85 at recall >= 0.20 on REFUSED
  (c) it BEATS the static baseline — the same analyzers over the same diffs — by a margin whose
      CI excludes zero

(c) is reported first and loudest. The receipt says it "is the one that would have killed the
deference arm a week early, and it is the one most likely to kill this", and it is the only one of
the three that needs no call at all. A pipeline that prints it last invites reading (a) as the
verdict when (a) is satisfiable by a lint.

TWO THINGS THIS FILE REFUSES TO DO, both because the alternative is a number that reads like a
measurement and is not:
  · it never prints an AUROC for a single-class corpus. predict_land_corpus.auroc returns None
    there and None is carried through, because 0.5 would read as "chance" — a verdict — when the
    truth is that no comparison was possible.
  · it never scores the Jev arm on rows where the call ABSTAINED. An abstain is not a low
    probability; evaluate.mjs gives it its own exit code precisely so the two cannot be pooled, and
    substituting 0 would credit the model with a confident negative it never made.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(os.environ.get("CC_PY", __file__))))
from predict_land_corpus import (  # noqa: E402
    auroc_ci, best_point_at_recall, precision_diff_ci, pr_curve,
)

MIN_RECALL = float(os.environ.get("CC_MIN_RECALL", "0.20"))
MIN_PRECISION = float(os.environ.get("CC_MIN_PRECISION", "0.85"))
# The sub-booleans, in the order the question block declares them. `q_refuse` is the ROLL-UP and is
# held out of the decomposition on purpose: the comparison that answers "did decomposing help" is
# max(subs) against the roll-up, and pooling the roll-up into the subs would make it unanswerable.
SUBS = ["q_smoke", "q_smoke_sibling", "q_hermeticity", "q_counted_pin", "q_dead"]
ROLLUP = "q_refuse"


def load(path, require=None):
    """Rows from a JSONL file. `require` names a key a row must carry to be a DATA row.

    The baseline stream leads with a one-line `{"analyzers":{...}}` header, and it has to be
    separated here rather than skipped silently: a header pooled into the scored rows would be one
    more row with no label, and a stream whose header was dropped would lose the only record of
    WHICH comparator condition (c) was measured against.
    """
    if not path or not os.path.exists(path):
        return [], {}
    rows, meta = [], {}
    for line in open(path):
        if not line.strip():
            continue
        d = json.loads(line)
        if require and require not in d:
            meta.update(d if isinstance(d, dict) else {})
            continue
        rows.append(d)
    return rows, meta


def is_refused(row):
    """The positive class. Reported under BOTH definitions, because they are not the same question:
    `any-nonzero` is what A10 proposed and includes refusals no diff determines; `gate-red` is the
    exit code whose producer calls it a verdict about the tree. A headline computed under the first
    and read as the second is the contamination the null arithmetic exists to price."""
    return row.get("exit") not in (0, None)


def is_gate_red(row):
    return row.get("class") == "GATE_RED"


def jev_prob(row, qid):
    """P(true) for one boolean, or None when the call abstained or the answer is absent."""
    j = row.get("jev") or {}
    if not j.get("ok"):
        return None
    a = (j.get("answers") or {}).get(qid) or {}
    p = a.get("probability")
    return p if isinstance(p, (int, float)) else None


def summarise(scores, labels, name):
    if not scores:
        return {"instrument": name, "n": 0, "verdict": "NO-ROWS"}
    ci = auroc_ci(scores, labels)
    pt = best_point_at_recall(scores, labels, MIN_RECALL)
    prev = (sum(1 for y in labels if y) / len(labels)) if labels else None
    return {
        "instrument": name, "n": len(scores), "n_positive": sum(1 for y in labels if y),
        "prevalence": None if prev is None else round(prev, 4),
        "auroc": ci["auroc"], "auroc_lo": ci["lo"], "auroc_hi": ci["hi"],
        "best_at_min_recall": pt,
        # The coin, restated beside every instrument rather than once at the top. A precision quoted
        # without it is read against 0.5, and the true comparator is the prevalence.
        "coin_precision": None if prev is None else round(prev, 4),
        "operating_points": len(pr_curve(scores, labels)),
    }


def main():
    base_rows, base_meta = load(os.environ.get("CC_BASELINE"), require="baseline")
    ask_rows, _ = load(os.environ.get("CC_ASK"), require="jev")
    if not base_rows:
        sys.stderr.write("predict_land_score: no baseline rows — nothing to score\n")
        return 3

    ask_by_head = {}
    for r in ask_rows:
        ask_by_head[r.get("head")] = r

    out = {"min_recall": MIN_RECALL, "min_precision": MIN_PRECISION,
           "comparator": base_meta.get("analyzers", "UNRECORDED"), "definitions": {}}

    for defname, labeller in (("any-nonzero", is_refused), ("gate-red", is_gate_red)):
        # The baseline arm scores every row. The Jev arm scores only rows it actually answered, so
        # the two are compared on the INTERSECTION — an instrument evaluated on a larger, easier row
        # set than its comparator wins by population, not by skill.
        b_scores, b_labels = [], []
        for r in base_rows:
            b_scores.append(r["baseline"]["score"])
            b_labels.append(1 if labeller(r) else 0)
        block = {"baseline": summarise(b_scores, b_labels, "static-analyzers")}

        paired_b, paired_r, paired_s, paired_y = [], [], [], []
        abstained = 0
        for r in base_rows:
            a = ask_by_head.get(r.get("head"))
            if a is None:
                continue
            roll = jev_prob(a, ROLLUP)
            subs = [jev_prob(a, q) for q in SUBS]
            if roll is None and all(s is None for s in subs):
                abstained += 1
                continue
            paired_b.append(r["baseline"]["score"])
            paired_r.append(roll if roll is not None else 0.0)
            paired_s.append(max([s for s in subs if s is not None] or [0.0]))
            paired_y.append(1 if labeller(r) else 0)

        block["jev_answered"] = len(paired_y)
        block["jev_abstained"] = abstained
        if paired_y:
            block["rollup"] = summarise(paired_r, paired_y, "jev/" + ROLLUP)
            block["decomposed_max"] = summarise(paired_s, paired_y, "jev/max(" + ",".join(SUBS) + ")")
            block["baseline_on_paired"] = summarise(paired_b, paired_y, "static-analyzers (paired subset)")
            # CONDITION (c): the model must beat the baseline on the SAME rows, paired.
            block["condition_c_rollup_vs_baseline"] = precision_diff_ci(
                paired_r, paired_b, paired_y, MIN_RECALL)
            block["condition_c_decomposed_vs_baseline"] = precision_diff_ci(
                paired_s, paired_b, paired_y, MIN_RECALL)
            # DID DECOMPOSING BUY ANYTHING. This is the item's own question, and it is the one a
            # single-boolean run cannot answer at all.
            block["decomposition_vs_rollup"] = precision_diff_ci(
                paired_s, paired_r, paired_y, MIN_RECALL)
            # Per-sub-boolean, against the arm it was aimed at. A decomposition whose parts cannot
            # be scored separately is a decomposition in name only.
            per_sub = {}
            for q in SUBS:
                s, y = [], []
                for r in base_rows:
                    a = ask_by_head.get(r.get("head"))
                    if a is None:
                        continue
                    p = jev_prob(a, q)
                    if p is None:
                        continue
                    s.append(p)
                    y.append(1 if labeller(r) else 0)
                per_sub[q] = summarise(s, y, "jev/" + q)
            block["per_sub_boolean"] = per_sub
        out["definitions"][defname] = block

    # The semantic stratum, reported BESIDE the whole rather than folded into it. The receipt is
    # explicit: "if the headline passes only because of shellcheck rows, the arm is a lint with a
    # bill." smoke and hermeticity are the arms where a model can be right for a reason no analyzer
    # can reach, so they are the only rows that can answer whether this is more than a lint.
    sem_arms = {"smoke", "smoke-sibling", "hermeticity"}
    sem = [r for r in base_rows if r.get("arm") in sem_arms]
    out["semantic_stratum"] = {
        "arms": sorted(sem_arms), "n": len(sem),
        "note": "rows whose named arm no static analyzer can reach; scored separately on purpose",
    }
    if sem:
        s_scores = [r["baseline"]["score"] for r in sem]
        s_labels = [1] * len(sem)  # every row here IS a refusal; AUROC is undefined, and says so
        out["semantic_stratum"]["baseline"] = summarise(s_scores, s_labels, "static-analyzers/semantic")

    verdicts = []
    prim = out["definitions"].get("any-nonzero", {})
    if not prim.get("jev_answered"):
        verdicts.append("NO JEV ARM — baseline only. Conditions (a) and (b) are unanswered, and (c) "
                        "has no second instrument to compare against.")
    else:
        ci = prim.get("rollup", {})
        if ci.get("auroc") is None:
            verdicts.append("(a) UNANSWERABLE — one class only in the scored rows.")
        elif ci["auroc"] >= 0.75 and (ci.get("auroc_lo") or 0) >= 0.65:
            verdicts.append("(a) PASS — AUROC %.3f, CI lower %.3f." % (ci["auroc"], ci["auroc_lo"]))
        else:
            verdicts.append("(a) FAIL — AUROC %.3f, CI lower %.3f." % (ci["auroc"], ci.get("auroc_lo") or 0))
        pt = (prim.get("rollup") or {}).get("best_at_min_recall")
        if pt and pt["precision"] >= MIN_PRECISION:
            verdicts.append("(b) PASS — precision %.3f at recall %.3f." % (pt["precision"], pt["recall"]))
        else:
            verdicts.append("(b) FAIL — no operating point reaches precision %.2f at recall %.2f."
                            % (MIN_PRECISION, MIN_RECALL))
        c = prim.get("condition_c_rollup_vs_baseline") or {}
        if c.get("excludes_zero"):
            verdicts.append("(c) PASS — beats the static baseline by %.3f, CI [%.3f, %.3f]."
                            % (c["delta"], c["lo"], c["hi"]))
        else:
            verdicts.append("(c) FAIL — margin over the static baseline does not exclude zero (%s)."
                            % (c.get("why") or "CI [%s, %s]" % (c.get("lo"), c.get("hi"))))
    out["verdicts"] = verdicts

    sys.stdout.write(json.dumps(out, sort_keys=True, indent=2) + "\n")
    for v in verdicts:
        sys.stderr.write("  " + v + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
