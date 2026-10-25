#!/usr/bin/env python3
"""flow.py — the d1_recycle flow as bin/cc-lever-eval drives it (plan § W7+ §2 D1 "Offline
(programmatic)").

Programmatic only: every number is a replay through sim.py (the W4 K/N model), no model runs. One
case is one main session; its value is the session's net pp under a rule. The hillclimbed policy is
`candidate` with the two tunables the K/N replay can price, k and n_min (the G4 regex and the brief
are the d1_successor flow's, S9). Its baseline is the last KEEP's params, or the approved lever
(200k after 15 min) before any KEEP. Every case carries the p90 re-prime the decision was priced
at, so a split half is self-contained.

Scale: a half's per-case nets summed, x 7 d / window, ÷ the half's share (cc-lever-eval's
half_stats). Both read-weight ends are scored and the WORSE end is decided on. The plan rules D1
out of the online candidate list ("D1 never"), so a KEEP here feeds S2's chain accounting, not a
switch-on.
"""

import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
import policy  # noqa: E402
import sim  # noqa: E402

NAME = "d1_recycle"
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
IMPORTS = os.path.join(os.path.expanduser("~"), ".claude/hillclimb/_imports")
REF_IMPORT = os.path.join(
    IMPORTS, "w4-rows"
)  # W4's 14-d rows, copied from /tmp/usage-audit/w4
REF_FIXTURE = os.path.join(REPO, "tests", "fixtures", "lever-eval-d1-sessions.jsonl.gz")
RP90_OUT = os.path.join(IMPORTS, "w4-rows", "rp90.out")
# decisions-2026-10-24/REPORT.md §1 (rp90.out): gross pp/week at N=15 min, mid read weight, p90 re-prime
TARGETS = {150_000: 16.36, 200_000: 15.39}
TARGET_N = 15
TOL = 0.05
AA_BAND = (0.02, 0.08)
SCAN = os.path.join(HERE, "scan.py")


def case_id(g):
    return g["case_id"]


def _attach(cases, meta):
    for g in cases:
        g.setdefault("rp", meta["rp_p90"])
        g.setdefault("E", meta["end"])
    return cases


def build(days=28.0, start=None, end=None):
    """Scan the four accounts' main transcripts with scan.py into <flow dir>/rows, then load."""
    import hc

    if start is None:
        end = end if end is not None else time.time()
        start = end - days * 86400
    elif end is None:
        end = start + days * 86400
    d = os.path.join(hc.flow_dir(NAME), "rows")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "window"), "w") as fh:
        fh.write("%d %d\n" % (start, end))
    procs = []
    for acct, (_a, root) in zip(sim.ACCTS, _roots()):
        procs.append(
            (
                acct,
                subprocess.Popen(
                    [
                        sys.executable,
                        "-I",
                        SCAN,
                        acct,
                        root,
                        str(start),
                        str(end),
                        os.path.join(d, "rows_%s.tsv" % acct),
                    ],
                    stderr=subprocess.PIPE,
                ),
            )
        )
    for acct, p in procs:
        err = p.communicate()[1]
        if p.returncode:
            raise OSError(
                "scan.py %s failed rc=%d: %s"
                % (acct, p.returncode, err.decode()[-300:])
            )
    return import_cases(d)


def _roots():
    env = os.environ.get("CC_LEVER_EVAL_ROOTS")
    if env:
        return [tuple(x.split("=", 1)) for x in env.split(",") if "=" in x]
    h = os.path.expanduser("~")
    return [
        (a, os.path.join(h, d, "projects"))
        for a, d in (
            ("next", ".claude-next"),
            ("next2", ".claude-secondary"),
            ("next3", ".claude-tertiary"),
            ("next4", ".claude-quaternary"),
        )
    ]


def import_cases(path):
    """A scan.py rows dir, or a sim.write_cases file (the fixture). → (cases, meta)."""
    if os.path.isdir(path):
        cases, meta = sim.from_rows(path)
    else:
        cases, meta = sim.read_cases(path)
    meta = dict(meta, source=path, cases=len(cases))
    meta.pop("first_reqs", None)
    return _attach(cases, meta), meta


def wk(meta):
    return 7 * 86400.0 / float(meta["window_s"])


def validate_params(p):
    bad = sorted(set(p) - set(policy.TUNABLE))
    if bad:
        raise ValueError(
            "not tunable for D1 here: %s (tunable: %s)"
            % (", ".join(bad), ", ".join(sorted(policy.TUNABLE)))
        )
    full = dict(policy.TUNABLE)
    full.update(p)
    if not (100_000 <= float(full["k"]) <= 1_000_000):
        raise ValueError("k %r outside [100000, 1000000] tokens" % full["k"])
    if not (policy.N_MIN_FLOOR <= float(full["n_min"]) <= 120):
        raise ValueError(
            "n_min %r outside [%d, 120]: under %d min cuts a live exchange"
            % (full["n_min"], policy.N_MIN_FLOOR, policy.N_MIN_FLOOR)
        )
    return full


def baseline_params(state):
    return validate_params(state.get("best_params") or {})


def evaluate(cases, params, r):
    """→ {case_id: unscaled net pp} for the candidate rule at read weight r."""
    out = {}
    policy.run(cases, "candidate", r, params=params, per_case=out)
    return out


def case_text(g):
    """D1 replay cases are numbers and hashed ids only; the leak check bites in d1_successor."""
    return ""


def failures(cases, params, r=None):
    """Train-side census of the sessions where the rule LOSES pp, by how it lost."""
    r = policy.READS[1][1] if r is None else r
    net, det = {}, {}
    policy.run(cases, "candidate", r, params=params, per_case=net, detail=det)
    cause = {}
    for g in cases:
        v = net[g["case_id"]]
        if v >= 0:
            continue
        fired, tfired = det[g["case_id"]]
        if not fired:
            k = "terminal_only"  # charged a recycle at the window end, no request after it to save on
        elif len(g["r"]) - fired[0] <= 3:
            k = "short_tail"  # recycled with at most 2 requests left to run cheaper
        else:
            k = "reprime_over_saving"
        c = cause.setdefault(k, [0, 0.0])
        c[0] += 1
        c[1] += -v
    return sorted(
        ([k, n, round(pp, 4)] for k, (n, pp) in cause.items()), key=lambda x: -x[2]
    )


# ── checks: each → (ok, detail) ──────────────────────────────────────────────────────────────────
def parse_rp90(path):
    """{K: saved_pp_week_total} for the N=15 rp_p90 rows rp90.out printed, or {} when absent."""
    got = {}
    try:
        with open(path) as fh:
            for ln in fh:
                m = re.match(
                    r"^(\d+) 15 rp_p90 .*\"saved_pp_week_total\": ([-\d.]+)", ln
                )
                if m:
                    got[int(m.group(1))] = float(m.group(2))
    except OSError:
        pass
    return got


def check_repro(ref_cases, ref_meta):
    rows, ok = [], True
    receipt = parse_rp90(RP90_OUT)
    for K, want in sorted(TARGETS.items()):
        r = sim.row(ref_cases, ref_meta, K, TARGET_N, "mid")
        got = r["saved_pp_week_exact"]
        dev = abs(got - want) / want
        good = dev <= TOL
        if K in receipt and abs(receipt[K] - want) > 1e-9:
            good = False
            rows.append(
                "%dk: TARGET %.2f disagrees with rp90.out %.2f"
                % (K // 1000, want, receipt[K])
            )
        ok &= good
        rows.append(
            "%dk/%dm: replay %.4f pp/wk vs anchor %.2f (dev %.2f%%, tol %d%%), recycles %d "
            "(+%d terminal) %s"
            % (
                K // 1000,
                TARGET_N,
                got,
                want,
                100 * dev,
                int(100 * TOL),
                r["recycles_14d"],
                r["terminal_recycles_14d"],
                "ok" if good else "FAIL",
            )
        )
    rows.append("re-prime p90 %s" % json.dumps(ref_meta["rp_p90"], sort_keys=True))
    rows.append(
        "receipt %s"
        % (
            "cross-checked: " + RP90_OUT
            if receipt
            else "absent; targets from flow.TARGETS"
        )
    )
    return ok, rows


def check_oracle(cases):
    """D1 has no perfect-foresight policy to bound it, so this slot runs the accounting identity
    instead: per-session nets sum to the total, and the total equals its parts (recycle turns +
    later requests + terminal recycles), at both read ends."""
    rows, ok = [], True
    for rn, r in policy.READS:
        pc = {}
        base, new, _n, _t, _ps, parts = sim.simulate(
            cases, policy.rules("candidate", None), r, per_case=pc
        )
        tot = sum(base.values()) - sum(new.values())
        sp = parts["recycle_turn"] + parts["later_requests"] + parts["terminal"]
        good = abs(tot - sum(pc.values())) < 1e-9 and abs(tot - sp) < 1e-9
        ok &= good
        rows.append(
            "candidate %s: total %.6f = sum of sessions %.6f = parts %.6f %s"
            % (rn, tot, sum(pc.values()), sp, "ok" if good else "FAIL")
        )
    rows.append(
        "no D1 oracle exists (a recycle's worth depends on the future); the identity stands in"
    )
    return ok, rows


def check_null(cases):
    rows, ok = [], True
    for rn, r in policy.READS:
        pc = {}
        a = policy.run(cases, "never", r, per_case=pc)["all"]
        good = a["net"] == 0.0 and a["recycles"] == 0 and a["terminal"] == 0
        good &= len(pc) == len(cases) and not any(pc.values())
        ok &= good
        rows.append(
            "never %s: net %r recycles %d over %d cases %s"
            % (rn, a["net"], a["recycles"], len(pc), "ok" if good else "FAIL")
        )
    return ok, rows


def check_aa(cases, hc):
    vals = evaluate(cases, policy.TUNABLE, policy.READS[1][1])
    fpr = hc.aa_fpr([(g["acct"], g["sid"], vals[g["case_id"]]) for g in cases])
    ok = AA_BAND[0] <= fpr <= AA_BAND[1]
    return ok, [
        "pseudo-salt A/A over %d sessions, 200 salts: false-positive rate %.3f, band [%.2f, %.2f] %s"
        % (len(cases), fpr, AA_BAND[0], AA_BAND[1], "ok" if ok else "FAIL")
    ]


def check_served_model(cases):
    return True, ["n/a: d1_recycle is a programmatic replay, it serves no model"]


def check_truncation(cases, n=40, cuts=4):
    """The rule may read only the past: on a prefix of a session cut after request j, the recycles
    it fires are exactly the full session's recycles at indices <= j (terminal excluded: the
    window end is the one future fact a terminal recycle is defined on)."""
    rule = policy.rules("candidate", None)
    full = {}
    sim.simulate(cases, rule, policy.READS[0][1], terminal=False, detail=full)
    pick = sorted(
        (g for g in cases if full[g["case_id"]][0]), key=lambda g: g["case_id"]
    )[:n]
    bad = checked = 0
    for g in pick:
        L = g["r"]
        for c in range(1, cuts + 1):
            j = max(1, len(L) * c // (cuts + 1))
            h = dict(g, r=L[: j + 1])
            d = {}
            sim.simulate([h], rule, policy.READS[0][1], terminal=False, detail=d)
            checked += 1
            if d[g["case_id"]][0] != [i for i in full[g["case_id"]][0] if i <= j]:
                bad += 1
    ok = bad == 0 and checked > 0
    return ok, [
        "prefix replays of %d recycled sessions x %d cuts: %d of %d fire differently from the "
        "full session %s" % (len(pick), cuts, bad, checked, "ok" if ok else "FAIL")
    ]


FIXTURE_K, FIXTURE_N = 150_000, 15


def fixture(cases, meta, path=REF_FIXTURE):
    """Write the committed reference fixture: each session trimmed to what any rule with
    K >= 150k and N >= 15 min can read, sids hashed. Before a session's first such idle point
    off = 0, so every earlier request prices the same in both arms and nets 0; only the request
    before that point (its gap and context) is kept. A session with no such point, in-session or
    terminal, nets 0 under every such rule and is dropped. Both re-primes were measured on the whole
    population and travel in meta, so the fixture reproduces the anchors exactly, not approximately."""
    import hashlib

    def ctx(x):
        return x[sim.INP] + x[sim.CW] + x[sim.CR]

    out = []
    for g in cases:
        L = g["r"]
        i0 = next(
            (
                i - 1
                for i in range(1, len(L))
                if L[i][sim.TURN]
                and ctx(L[i - 1]) >= FIXTURE_K
                and L[i][sim.TS] - L[i - 1][sim.TS] >= FIXTURE_N * 60
            ),
            None,
        )
        if i0 is None:
            if (
                g["closed"]
                or ctx(L[-1]) < FIXTURE_K
                or g["E"] - L[-1][sim.TS] < FIXTURE_N * 60
            ):
                continue
            i0 = len(L) - 1
        h = hashlib.sha1(g["sid"].encode()).hexdigest()[:12]
        out.append(
            dict(
                case_id=h,
                sid=h,
                acct=g["acct"],
                E=g["E"],
                closed=g["closed"],
                jobs=[j for j in g["jobs"] if j[1] >= L[i0][sim.TS]],
                r=[[round(x[0], 3)] + x[1:] for x in L[i0:]],
            )
        )
    m = {k: v for k, v in meta.items() if k not in ("source", "cases")}
    m.update(
        source="fixture: lever-eval-d1-sessions (K>=%dk, N>=%dm trim)"
        % (FIXTURE_K // 1000, FIXTURE_N),
        fixture_sessions=len(out),
    )
    sim.write_cases(path, out, m)
    return len(out)
