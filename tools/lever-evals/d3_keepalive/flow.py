#!/usr/bin/env python3
"""flow.py — the d3_keepalive flow as bin/cc-lever-eval drives it (plan § W7+ §2 D3 "Offline").

Programmatic only: every number here is a replay through policy.py, no model runs. The hillclimbed
policy is `candidate` — busy-scoped, at most ONE wake per gap (never tunable, §3), with the three
tunables the plan names: wake_s, skip_watcher, min_ctx_k. Its baseline is the last KEEP's params,
or policy.TUNABLE before any KEEP.

A round's numbers are fleet pp/week: a half's per-case net deltas summed, x 7 d / case window,
÷ the half's share of all cases. Both read-weight ends are scored and the WORSE end is the one
decided on (§2: ADVANCE needs the CI lower bound > 0 "at both read-weight ends").
"""

import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
import build_cases  # noqa: E402
import policy  # noqa: E402

NAME = "d3_keepalive"
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
IMPORTS = os.path.join(os.path.expanduser("~"), ".claude/hillclimb/_imports")
REF_IMPORT = os.path.join(IMPORTS, "lean-idle-rv", "G2.json")
REF_FIXTURE = os.path.join(REPO, "tests", "fixtures", "lever-eval-d3-g2.jsonl.gz")
RECOMPUTE_OUT = os.path.join(IMPORTS, "conv-tests", "c0f9d5368147", "recompute.out")
REF_WINDOW_S = (
    1792864800.0 - 1791655200.0
)  # rv/rrep.py S..E: the 14 d the reference cases cover

# recompute.out lines 18-21, "engine check": the replay must land within ±5% of each (plan §2 D3)
TARGETS = {
    ("literal", "low"): 3.79,
    ("literal", "high"): 2.67,
    ("r2_busy", "low"): 5.07,
    ("r2_busy", "high"): 4.23,
}
TOL = 0.05
RECOMPUTE_LABEL = {"literal": "AS CODED s=0.89", "r2_busy": "R2 busy2"}
# policies priced in the same world model as perfect foresight (observed rebuild, chain refresh);
# shadow_model prices the TTL model instead, so it is reported, never held to the oracle
SAME_WORLD = ("literal", "once", "chain", "r2_busy", "r4_busy_nowatch", "candidate")
AA_BAND = (0.02, 0.08)


def case_id(g):
    return g.get("case_id") or "%s:%d" % (g["sid"], int(g["stop"]))


def build(days=28.0, start=None, end=None):
    import time

    if start is None:
        end = end if end is not None else time.time()
        start = end - days * 86400
    elif end is None:
        end = start + days * 86400
    return build_cases.build(start, end)


def import_cases(path):
    """Cases from a file as flow cases. → (cases, meta). The window is the reference cases' 14 d,
    unless the file is a build_cases.py output with a sibling <path>.meta (its stdout line)."""
    cases = policy.load_cases(path)
    for g in cases:
        g["case_id"] = case_id(g)
    meta = dict(
        schema=2, flow=NAME, source=path, window_s=REF_WINDOW_S, cases=len(cases)
    )
    if os.path.exists(path + ".meta"):
        with open(path + ".meta") as fh:
            meta = dict(json.load(fh), source=path)
    return cases, meta


def wk(meta):
    return 7 * 86400.0 / float(meta["window_s"])


def validate_params(p):
    bad = sorted(set(p) - set(policy.TUNABLE))
    if bad:
        raise ValueError(
            "not tunable for D3: %s (tunable: %s)"
            % (", ".join(bad), ", ".join(sorted(policy.TUNABLE)))
        )
    full = dict(policy.TUNABLE)
    full.update(p)
    if not (60 <= float(full["wake_s"]) <= policy.TTL):
        raise ValueError(
            "wake_s %r outside [60, %d]: a later wake finds the cache gone"
            % (full["wake_s"], policy.TTL)
        )
    if not isinstance(full["skip_watcher"], bool):
        raise ValueError("skip_watcher must be true or false")
    if float(full["min_ctx_k"]) < 0:
        raise ValueError("min_ctx_k must be >= 0")
    return full


def baseline_params(state):
    return validate_params(state.get("best_params") or {})


def evaluate(cases, params, r):
    """→ {case_id: unscaled net pp} for the candidate policy at read weight r."""
    out = {}
    policy.run(cases, "candidate", r, wk=1.0, params=params, per_case=out)
    return out


def case_text(g):
    """D3 cases carry no free text (numbers, ids, a turn kind), so the leak check is empty here by
    construction; the text flows (d1_successor, d2_lean) are where it bites."""
    return ""


def failures(cases, params, r=None):
    """Train-side failure census against perfect foresight: where the candidate loses pp, and why."""
    r = policy.IG.READ_PP[1] if r is None else r
    cand, pf = {}, {}
    policy.run(cases, "candidate", r, wk=1.0, params=params, per_case=cand)
    policy.run(cases, "perfect_foresight", r, wk=1.0, per_case=pf)
    full = validate_params(params)
    cause = {}
    for g in cases:
        cid = case_id(g)
        loss = pf[cid] - cand[cid]
        if loss <= 0:
            continue
        if cand[cid] < 0:
            k = "woke_no_rescue"
        elif full["min_ctx_k"] and g["ctx"] < full["min_ctx_k"] * 1000:
            k = "missed:ctx_floor"
        else:
            try:
                v = policy.DecisionView(g, g["stop"] + float(full["wake_s"]))
                busy, watch = v["busy2"], v["watch2"]
            except policy.TruncationError:
                busy = watch = None
            if busy is None:
                k = "missed:no_feature_at_wake"
            elif not busy:
                k = "missed:not_busy"
            elif watch and full["skip_watcher"]:
                k = "missed:watcher_skipped"
            else:
                k = "missed:one_wake_too_few"
        c = cause.setdefault(k, [0, 0.0])
        c[0] += 1
        c[1] += loss
    return sorted(
        ([k, n, round(pp, 4)] for k, (n, pp) in cause.items()), key=lambda x: -x[2]
    )


# ── checks: each → (ok, detail) ──────────────────────────────────────────────────────────────────
def parse_recompute(path):
    """The engine-check totals as recompute.out printed them, or {} when the receipt is absent."""
    got = {}
    try:
        with open(path) as fh:
            text = fh.read()
    except OSError:
        return got
    for pol, lab in RECOMPUTE_LABEL.items():
        for rn in ("low", "high"):
            m = re.search(
                r"^\s*%s med %s\s*\|[^|]*\|\s*([-\d.]+)\s*\|" % (re.escape(lab), rn),
                text,
                re.M,
            )
            if m:
                got[(pol, rn)] = float(m.group(1))
    return got


def check_repro(ref_cases, ref_meta):
    rows, ok = [], True
    receipt = parse_recompute(RECOMPUTE_OUT)
    for (pol, rn), want in sorted(TARGETS.items()):
        r = dict(policy.READS)[rn]
        got = policy.run(ref_cases, pol, r, wk=wk(ref_meta))["all"]["net"]
        dev = abs(got - want) / want
        good = dev <= TOL
        if (pol, rn) in receipt and abs(receipt[(pol, rn)] - want) > 1e-9:
            good = False
            rows.append(
                "%s %s: TARGET %.2f disagrees with recompute.out %.2f"
                % (pol, rn, want, receipt[(pol, rn)])
            )
        ok &= good
        rows.append(
            "%s %s: replay %.4f vs recompute.out %.2f (dev %.2f%%, tol %d%%) %s"
            % (pol, rn, got, want, 100 * dev, int(100 * TOL), "ok" if good else "FAIL")
        )
    rows.append(
        "receipt %s"
        % (
            "cross-checked: " + RECOMPUTE_OUT
            if receipt
            else "absent; targets from flow.TARGETS"
        )
    )
    return ok, rows


def check_oracle(cases):
    """Perfect foresight scores at least every same-world policy, gap by gap and in total."""
    rows, ok = [], True
    for rn, r in policy.READS:
        pf = {}
        tpf = policy.run(cases, "perfect_foresight", r, wk=1.0, per_case=pf)["all"][
            "net"
        ]
        for pol in SAME_WORLD:
            pc = {}
            tp = policy.run(cases, pol, r, wk=1.0, per_case=pc)["all"]["net"]
            worse = [cid for cid, v in pc.items() if v > pf[cid] + 1e-12]
            good = not worse and tpf + 1e-9 >= tp
            ok &= good
            rows.append(
                "%s %s: PF %.4f >= %.4f, gaps where policy beats PF: %d %s"
                % (
                    pol,
                    rn,
                    tpf,
                    tp,
                    len(worse),
                    "ok" if good else "FAIL " + ",".join(worse[:3]),
                )
            )
    return ok, rows


def check_null(cases):
    rows, ok = [], True
    for rn, r in policy.READS:
        pc = {}
        a = policy.run(cases, "never", r, wk=1.0, per_case=pc)["all"]
        good = (
            a.get("net", 0.0) == 0.0
            and a.get("wakes", 0.0) == 0.0
            and not any(pc.values())
        )
        good &= len(pc) == len(cases)
        ok &= good
        rows.append(
            "never %s: net %r wakes %r over %d cases %s"
            % (rn, a.get("net"), a.get("wakes", 0.0), len(pc), "ok" if good else "FAIL")
        )
    return ok, rows


def check_aa(cases, hc):
    vals = evaluate(cases, policy.TUNABLE, policy.IG.READ_PP[1])
    fpr = hc.aa_fpr([(g["acct"], g["sid"], vals[case_id(g)]) for g in cases])
    ok = AA_BAND[0] <= fpr <= AA_BAND[1]
    return ok, [
        "pseudo-salt A/A over %d cases, 200 salts: false-positive rate %.3f, band [%.2f, %.2f] %s"
        % (len(cases), fpr, AA_BAND[0], AA_BAND[1], "ok" if ok else "FAIL")
    ]


def check_served_model(cases):
    return True, ["n/a: d3_keepalive is a programmatic replay, it serves no model"]


def check_truncation(cases):
    """(1) a policy reading an outcome field raises; (2) a case without job intervals refuses its
    busy/watch at any moment but stop+3300; (3) where a case has job intervals, the view's busy/watch
    at stop+3300 equal the builder's stored busy2/watch2; (4) every same-world policy at default
    params replays without touching the future."""
    rows, ok = [], True
    g0 = dict(cases[0])
    try:
        policy.DecisionView(g0, g0["stop"] + policy.WAKE)["reb"]
        rows.append("outcome field readable at decision time FAIL")
        ok = False
    except policy.TruncationError:
        rows.append("outcome field refused at decision time ok")
    g1 = {k: v for k, v in g0.items() if k != "jobs"}
    try:
        policy.DecisionView(g1, g1["stop"] + policy.WAKE - 600)["busy2"]
        rows.append("busy2 readable 600 s before its feature time FAIL")
        ok = False
    except policy.TruncationError:
        rows.append("busy2 refused away from its feature time ok")
    withjobs = [g for g in cases if g.get("jobs") is not None]
    mism = 0
    for g in withjobs:
        v = policy.DecisionView(g, g["stop"] + policy.WAKE)
        mism += (v["busy2"] != g["busy2"]) or (v["watch2"] != g["watch2"])
    ok &= mism == 0
    rows.append(
        "job-interval features vs stored busy2/watch2 at stop+3300: %d of %d disagree %s"
        % (mism, len(withjobs), "ok" if not mism else "FAIL")
    )
    try:
        for pol in SAME_WORLD:
            policy.run(cases, pol, policy.IG.READ_PP[0], wk=1.0)
        rows.append("all same-world policies replay on decision-time features ok")
    except policy.TruncationError as e:
        ok = False
        rows.append("policy read the future: %s FAIL" % e)
    return ok, rows


def fixture_rows(g2_path):
    """The committed reference fixture: G2 rows reduced to what the replay reads, sid hashed."""
    keep = (
        "acct",
        "stop",
        "end",
        "term",
        "end_kind",
        "exit",
        "alive",
        "mt",
        "ctx",
        "reb",
        "saved",
        "kill",
        "later",
        "busy2",
        "watch2",
        "prev",
    )
    for g in policy.load_cases(g2_path):
        r = {k: g[k] for k in keep}
        r["sid"] = hashlib.sha1(g["sid"].encode()).hexdigest()[:12]
        r["case_id"] = "%s:%d" % (r["sid"], int(g["stop"]))
        yield r
