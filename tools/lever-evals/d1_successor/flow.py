#!/usr/bin/env python3
"""flow.py — the d1_successor flow as bin/cc-lever-eval drives it (docs/plans/USAGE_LEVERS.md § W7+
§2 D1 "Offline d1-successor (model runs)" and "Gate S0→S1"; §3 "Evals", "Hillclimb loop").

The tuned surface is the production brief, scripts/lib/idle_recycle_brief.py (its DEFAULTS are
the params; one key changes per round). A case is one production operator return
(build_cases.py); a RUN is one case × one params set × one rep, a fresh `claude -p` (run.sh), graded
by code and then by the blind judge (grade.py). A case's value under a params set is its mean pass
points over reps (100 pass, 0 fail), so a half's paired delta is in POINTS: wk() returns
100 / n_cases, which cc-lever-eval's half_stats turns into a half's mean (the scale it applies is
wk / share = 100 / n_half). MIN_ACT is 10 points (hc.FLOWS).

  build      `cc-lever-eval build d1_successor [--days 28]`: scan + census + labels, select ~200
             `cc-lever-eval build d1_successor --from <dir>`: the 193 imported returns only (no scan)
  run        model runs: refused until the operator's `cc-lever-eval approve-harness d1_successor`,
             except `--smoke N` (N <= 5, reps 1), which proves the harness and writes to smoke/,
             never to results/ (score and round never read a smoke run)
  score / round  read results/<params sha>/ only; a case without a judged run there is refused
  check      repro (the imported label census), truncation, null, served-model, oracle, aa
  failures   train runs that failed, by cause

Runs live under /tmp/lev-eval/d1s/ (the eval cwd root); graded results under
~/.claude/hillclimb/d1_successor/{results,smoke}/. Stdlib only, Python 3.9-safe.
"""

import collections
import hashlib
import json
import math
import os
import random
import statistics
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "scripts", "lib"))
import build_cases as bc  # noqa: E402
import grade  # noqa: E402
import idle_recycle_brief as irb  # noqa: E402

NAME = "d1_successor"
RUN_SH = os.path.join(HERE, "run.sh")
REF_IMPORT = bc.STUDY
REF_FIXTURE = (
    bc.STUDY
)  # operator transcripts are never committed: the reference is the import
SMOKE_MAX = 5
PROD_MODEL = "claude-opus-5-5"
# the study's census of the 193 returns (idle-recycle-risk-b/ana.out census193, first labels):
# 19 context-dependent, 10 wrong-action risks; the second labeller's A differs on at most one
REPRO = dict(returns=193, H=19, A=10, replays=10)
WIRING_START = (
    78_000  # production successors' first-request input side (decisions REPORT)
)


class policy:
    """The generic CLI reads policy.READS; a points flow has one read."""

    READS = (("points", None),)


def _hc():
    import hc

    return hc


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


# ── build ────────────────────────────────────────────────────────────────────────────────────────
def build(days=28.0, start=None, end=None):
    if start is None:
        end = end if end is not None else time.time()
        start = end - days * 86400
    elif end is None:
        end = start + days * 86400
    rows = os.path.join(_hc().flow_dir(NAME), "rows")
    return bc.build(rows, _roots(), start, end)


def import_cases(path):
    """A cases.jsonl (meta from its sibling build.json), or the study's import dir (its 193 labelled
    returns, made into cases without a scan)."""
    if os.path.isdir(path):
        pts = bc.imported_points()
        cases = [
            c
            for c in (
                bc.make_case(p) for p in pts if p["path"] and os.path.exists(p["path"])
            )
            if c
        ]
        cases.sort(key=lambda c: c["case_id"])
        meta = dict(
            flow=NAME,
            source=path,
            n_cases=len(cases),
            n_imported=len(cases),
            n_points=len(pts),
            tags=dict(collections.Counter(c["tag"] for c in cases)),
            a_replays=sum(1 for c in cases if c["a_replay"]),
            window_s=14 * 86400.0,
            ts=time.time(),
        )
        return cases, meta
    cases = _hc().read_jsonl(path)
    meta = dict(flow=NAME, source=path, n_cases=len(cases))
    side = os.path.join(os.path.dirname(path), "build.json")
    if os.path.exists(side):
        with open(side) as fh:
            meta = dict(json.load(fh), source=path, n_cases=len(cases))
    return cases, meta


def wk(meta):
    return 100.0 / max(1, int(meta.get("n_cases") or 0))


def validate_params(p):
    return irb.validate_params(p)


def baseline_params(state):
    return validate_params(state.get("best_params") or {})


def params_sha(params):
    return hashlib.sha256(
        json.dumps(validate_params(params), sort_keys=True).encode()
    ).hexdigest()[:12]


def case_text(g):
    return "\n".join(
        x
        for x in (
            g.get("prompt"),
            (g.get("ref") or {}).get("reply"),
            g.get("ref_action_text"),
        )
        if x
    )


# ── results store ────────────────────────────────────────────────────────────────────────────────
def results_dir(params, smoke=False):
    sub = "smoke" if smoke else "results"
    return os.path.join(_hc().flow_dir(NAME), sub, params_sha(params))


def load_results(params):
    """{case_id: [final grade per rep]} for a params set (results/ only, never smoke/)."""
    d = results_dir(params)
    out = collections.defaultdict(list)
    if not os.path.isdir(d):
        return out
    for fn in sorted(os.listdir(d)):
        if fn.endswith(".json"):
            with open(os.path.join(d, fn)) as fh:
                r = json.load(fh)
            out[r["case_id"]].append(r)
    return out


def evaluate(cases, params, r=None):
    """→ {case_id: mean points over judged reps}. Refused (ValueError) when any case has no judged
    run under these params: a score never invents a missing run."""
    res = load_results(params)
    out, missing = {}, []
    for g in cases:
        pts = [
            x["points"]
            for x in res.get(g["case_id"], [])
            if x.get("points") is not None
        ]
        if not pts:
            missing.append(g["case_id"])
            continue
        out[g["case_id"]] = sum(pts) / len(pts)
    if missing:
        raise ValueError(
            "%d of %d case(s) have no judged run under params %s (e.g. %s) — run "
            "`cc-lever-eval run d1_successor --params '%s'` first"
            % (
                len(missing),
                len(cases),
                params_sha(params),
                missing[0],
                json.dumps(validate_params(params), sort_keys=True),
            )
        )
    return out


# ── runs ─────────────────────────────────────────────────────────────────────────────────────────
def run_one(case, params, rep, run_root):
    d = os.path.join(run_root, "%s.r%d" % (case["case_id"], rep))
    os.makedirs(d, exist_ok=True)
    cp = os.path.join(d, "case.json")
    with open(cp, "w") as fh:
        json.dump(case, fh, sort_keys=True)
    os.chmod(cp, 0o600)
    p = subprocess.run(
        [
            "/bin/bash",
            RUN_SH,
            cp,
            d,
            json.dumps(validate_params(params), sort_keys=True),
        ],
        capture_output=True,
        text=True,
        env=_hc().eval_env(),
    )
    return d, p.returncode, (p.stderr or "")[-300:]


def run_cases(
    cases, params, reps=1, smoke=False, workers=1, seed=0, judge=True, out=sys.stdout
):
    """Run, code-grade and judge; write one final grade per run under results/ (or smoke/)."""
    import concurrent.futures as cf

    psha = params_sha(params)
    run_root = os.path.join(bc.EVAL_ROOT, "d1s", ("smoke-" if smoke else "") + psha)
    os.makedirs(run_root, exist_ok=True)
    jobs = [(c, k) for k in range(1, reps + 1) for c in cases]
    done = []
    with cf.ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        for d, rc, err in ex.map(
            lambda ck: run_one(ck[0], params, ck[1], run_root), jobs
        ):
            out.write(
                "run %s rc %d%s\n"
                % (
                    os.path.basename(d),
                    rc,
                    (" — " + err.strip()) if rc and err.strip() else "",
                )
            )
            done.append(d)
    batch = {}
    if judge:
        for i in range(0, len(done), 15):
            b, _lab = grade.judge(done[i : i + 15], seed=seed + i)
            if b:
                batch[b.get("batch")] = b.get("verdict")
                out.write("judge batch %s: %s\n" % (b.get("batch"), b.get("verdict")))
    rd = results_dir(params, smoke)
    os.makedirs(rd, exist_ok=True)
    finals = []
    for d in done:
        try:
            with open(os.path.join(d, "grade.json")) as fh:
                g = json.load(fh)
        except (OSError, ValueError):
            g = dict(
                case_id=os.path.basename(d).split(".")[0],
                cls="error",
                rc=None,
                models=[],
            )
        try:
            with open(os.path.join(d, "judged.json")) as fh:
                j = json.load(fh)
        except (OSError, ValueError):
            j = None
        f = grade.final(g, (j or {}).get("labels"))
        f.update(
            rep=int(os.path.basename(d).rsplit(".r", 1)[1]),
            params=psha,
            run_dir=d,
            batch=(j or {}).get("batch"),
            ref_claims=(j or {}).get("ref"),
        )
        with open(os.path.join(rd, os.path.basename(d) + ".json"), "w") as fh:
            json.dump(f, fh, sort_keys=True)
        finals.append(f)
    try:
        with open(os.path.join(_hc().flow_dir(NAME), "build.json")) as fh:
            meta = json.load(fh)
    except (OSError, ValueError):
        meta = None
    summarize(cases, finals, out, meta)
    return finals


def summarize(cases, finals, out=sys.stdout, meta=None):
    by = {c["case_id"]: c for c in cases}
    judged = [f for f in finals if f.get("points") is not None]
    n_pass = sum(1 for f in judged if f["pass_"])
    wrong = [f for f in judged if f.get("wrong_action")]
    reqs = [f.get("requests") or 0 for f in finals if f.get("cls") != "error"]
    a_fail = sum(
        1 for f in judged if by.get(f["case_id"], {}).get("a_replay") and not f["pass_"]
    )
    firsts = [f.get("first_input") or 0 for f in finals if f.get("first_input")]
    out.write(
        "runs %d · judged %d · pass %d (%.1f points) · wrong actions %d · A-replay failures %d · "
        "classes %s · median requests %s · median first input %s (production %d) · models %s\n"
        % (
            len(finals),
            len(judged),
            n_pass,
            100.0 * n_pass / len(judged) if judged else float("nan"),
            len(wrong),
            a_fail,
            dict(collections.Counter(f.get("cls") for f in finals)),
            statistics.median(reqs) if reqs else "-",
            statistics.median(firsts) if firsts else "-",
            WIRING_START,
            sorted({m for f in finals for m in f.get("models") or [] if m}),
        )
    )
    out.write(gate(cases, finals, meta) + "\n")


def wilson_hi(k, n, z=1.959964):
    if not n:
        return float("nan")
    p = k / n
    c = (p + z * z / (2 * n) + z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / (
        1 + z * z / n
    )
    return min(1.0, c)


def gate(cases, finals, meta=None):
    """Plan §2 D1 "Gate S0→S1", as measured on these runs (the verdict is the test split's, at the
    full baseline): projected wrong actions a week (point, Wilson upper 95%), A-replay failures,
    first-turn median requests and read tokens."""
    by = {c["case_id"]: c for c in cases}
    judged = [f for f in finals if f.get("points") is not None]
    k = sum(1 for f in judged if f.get("wrong_action"))
    wk = None
    if meta and meta.get("n_census_returns") and meta.get("window_s"):
        wk = meta["n_census_returns"] * 7 * 86400.0 / float(meta["window_s"])
    a_fail = sum(
        1 for f in judged if by.get(f["case_id"], {}).get("a_replay") and not f["pass_"]
    )
    reqs = [f.get("requests") or 0 for f in finals if f.get("cls") not in ("error",)]
    rd = [f.get("read_tokens") or 0 for f in finals if f.get("cls") not in ("error",)]
    if not judged or wk is None:
        proj = "projected wrong actions/wk: n/a (%s)" % (
            "no judged run" if not judged else "no census rate"
        )
    else:
        proj = (
            "projected wrong actions/wk %.2f, upper95 %.2f (gate <= 1, <= 2; %d of %d judged, %.1f returns/wk)"
            % (k / len(judged) * wk, wilson_hi(k, len(judged)) * wk, k, len(judged), wk)
        )
    return (
        "gate: %s · A-replay failures %d (gate <= 2) · first-turn median requests %s (<= 10) · read tokens %s (<= 10000)"
        % (
            proj,
            a_fail,
            statistics.median(reqs) if reqs else "-",
            statistics.median(rd) if rd else "-",
        )
    )


def cmd_run(a, hc):
    """`cc-lever-eval run d1_successor [--params P] [--cases train|all|PATH] [--reps R] [--smoke N]`."""
    params = validate_params(json.loads(a.params) if a.params else {})
    if a.smoke:
        if not (1 <= a.smoke <= SMOKE_MAX):
            raise ValueError(
                "--smoke takes 1..%d cases (a harness proof, not a baseline)"
                % SMOKE_MAX
            )
        try:
            cases = hc.read_train(NAME)
        except OSError:
            cases = hc.read_jsonl(os.path.join(hc.flow_dir(NAME), "cases.jsonl"))
        rng = random.Random(a.seed or 0)
        pick = [c for c in cases if c.get("a_replay")][:1]
        rest = [c for c in cases if c not in pick and c.get("tag") not in ("I",)]
        rng.shuffle(rest)
        sel = (pick + rest)[: a.smoke]
        run_cases(sel, params, reps=1, smoke=True, workers=a.workers, seed=a.seed or 0)
        return 0
    hc.require_approved(NAME)
    if a.cases == "train":
        cases = hc.read_train(NAME)
    elif a.cases == "all":
        cases = hc.read_jsonl(os.path.join(hc.flow_dir(NAME), "cases.jsonl"))
    else:
        cases = import_cases(a.cases)[0]
    run_cases(cases, params, reps=a.reps or 2, workers=a.workers, seed=a.seed or 0)
    return 0


# ── checks: each → (ok, detail) ──────────────────────────────────────────────────────────────────
def check_repro(cases, meta):
    tags = collections.Counter(c["tag"] for c in cases if c.get("tag_src") != "v1")
    h = tags["H"] + tags["A"]
    rep = sum(1 for c in cases if c.get("a_replay"))
    n = meta.get("n_points", len(cases))
    ok = (
        n == REPRO["returns"]
        and h == REPRO["H"]
        and abs(tags["A"] - REPRO["A"]) <= 1
        and rep == REPRO["replays"]
    )
    return ok, [
        "labelled returns %d (study %d) · context-dependent %d (%d) · wrong-action %d (%d ± 1) · A "
        "replays %d (%d) · cases built %d"
        % (
            n,
            REPRO["returns"],
            h,
            REPRO["H"],
            tags["A"],
            REPRO["A"],
            rep,
            REPRO["replays"],
            len(cases),
        )
    ]


def check_truncation(train, n=12):
    """The future never enters a fixture: no transcript line stamped after the idle point, and the
    operator prompt is absent from the brief unless the predecessor's own conversation had it."""
    rng = random.Random(0)
    sample = list(train)
    rng.shuffle(sample)
    bad, rows = [], []
    root = os.path.join(bc.EVAL_ROOT, "d1s", "check-truncation")
    for c in sample[:n]:
        fx = os.path.join(root, c["case_id"])
        try:
            m = bc.fixture(c, fx, repo=False)
        except (OSError, ValueError) as e:
            bad.append("%s: fixture failed: %s" % (c["case_id"], e))
            continue
        late = 0
        with open(os.path.join(fx, "predecessor.jsonl"), "rb") as fh:
            for ln in fh:
                i = ln.find(b'"timestamp":"')
                if i >= 0:
                    t = bc.ep(
                        ln[i + 13 : i + 45].split(b'"')[0].decode("utf-8", "replace")
                    )
                    if t is not None and t > c["t_idle"] + 1:
                        late += 1
        with open(os.path.join(fx, "brief.txt")) as fh:
            brief = fh.read()
        with open(os.path.join(fx, "predecessor.jsonl")) as fh:
            pred = fh.read()
        p = c["prompt"].strip()
        leak = len(p) >= 20 and p in brief and p not in pred
        if late or leak:
            bad.append(
                "%s: %d line(s) after the idle point%s"
                % (c["case_id"], late, ", prompt in brief" if leak else "")
            )
        rows.append(m["transcript_lines"])
    ok = not bad and bool(rows)
    return ok, bad[:6] + ["%d fixture(s) cut, %d bad" % (len(rows), len(bad))]


def check_null(train):
    """An empty reply must fail every case by code alone (no judge call)."""
    fails = 0
    for c in train:
        g = dict(case_id=c["case_id"], cls="none", reply="")
        fails += grade.final(g, None)["pass_"] is False
    return fails == len(train) and bool(train), [
        "empty reply fails %d of %d case(s)" % (fails, len(train))
    ]


def _all_results(train):
    ids = {c["case_id"] for c in train}
    d = os.path.join(_hc().flow_dir(NAME), "results")
    rows = []
    if os.path.isdir(d):
        for ps in sorted(os.listdir(d)):
            for fn in sorted(os.listdir(os.path.join(d, ps))):
                with open(os.path.join(d, ps, fn)) as fh:
                    r = json.load(fh)
                if r["case_id"] in ids:
                    rows.append(r)
    return rows


def check_served_model(train):
    rows = _all_results(train)
    models = collections.Counter(m for r in rows for m in r.get("models") or [])
    ok = bool(rows) and set(models) == {PROD_MODEL}
    return ok, [
        "served models over %d run(s): %s (want only %s)"
        % (len(rows), dict(models) or "none", PROD_MODEL)
    ]


def check_oracle(train):
    """The production reply, judged blind beside the successors, must pass >= 90% where the operator's
    next prompt was not a correction; else the key or the rubric is broken."""
    by = {c["case_id"]: c for c in train}
    seen, n, ok_n = set(), 0, 0
    for r in _all_results(train):
        c = by[r["case_id"]]
        if (
            r["case_id"] in seen
            or c.get("followup_is_correction")
            or not r.get("ref_claims")
        ):
            continue
        seen.add(r["case_id"])
        n += 1
        ok_n += grade.final(dict(r, cls="answer"), r["ref_claims"])["pass_"] is True
    ok = n > 0 and ok_n >= 0.9 * n
    return ok, [
        "production reply passes %d of %d judged case(s) (need >= 90%%)" % (ok_n, n)
    ]


def check_aa(train, hc):
    """Two reps of one params set: the A/A difference's noise floor must sit under 10 points."""
    by_ps = collections.defaultdict(lambda: collections.defaultdict(dict))
    for r in _all_results(train):
        if r.get("points") is not None:
            by_ps[r["params"]][r["case_id"]][r["rep"]] = r["points"]
    best = None
    acct = {c["case_id"]: (c["acct"], c["sid"]) for c in train}
    for ps, cs in by_ps.items():
        rows = [
            (acct[k][0], acct[k][1], v[1] - v[2])
            for k, v in cs.items()
            if 1 in v and 2 in v
        ]
        if len(rows) < 10:
            continue
        _p, _lo, _hi, sd = hc.cluster_bootstrap(rows, 1.0 / len(rows), reps=1000)
        nf = 1.96 * sd
        if best is None or nf < best[1]:
            best = (ps, nf, len(rows))
    if best is None:
        return False, ["no params set has two judged reps on >= 10 train cases"]
    return best[1] < 10.0, [
        "A/A NF %.2f points over %d case(s) at params %s (need < 10)"
        % (best[1], best[2], best[0])
    ]


def failures(cases, params):
    """Train runs under params that did not pass, tallied by cause → [[cause, n, lost points]]."""
    res = load_results(params)
    tally = collections.Counter()
    for c in cases:
        for r in res.get(c["case_id"], []):
            if r.get("pass_") is not False:
                continue
            cl = r.get("claims") or {}
            if r.get("cls") in ("error", "none"):
                k = r["cls"]
            elif r.get("acted_on_brief"):
                k = "acted_on_brief"
            elif r.get("wrong_action"):
                k = "wrong_action"
            elif cl.get("C3") == "N":
                k = "no_ask_when_ambiguous"
            elif cl.get("C4") == "Y":
                k = "contradicts_brief"
            else:
                k = "missed_referent"
            tally[k] += 1
    return sorted(([k, n, 100.0 * n] for k, n in tally.items()), key=lambda x: -x[2])
