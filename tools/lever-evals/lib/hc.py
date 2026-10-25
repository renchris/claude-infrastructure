#!/usr/bin/env python3
"""hc.py — the hillclimb eval kernel shared by every lever eval flow (docs/plans/USAGE_LEVERS.md
§ W7+ §3 rows "Evals" and "Hillclimb loop").

WHAT IT OWNS. The pieces that must behave identically across flows, so no flow can quietly bend
them in its own favour:
  * state     ~/.claude/hillclimb/<flow>/ (CC_HILLCLIMB_DIR overrides the root), SCHEMA 2:
              cases.jsonl, build.json, train.jsonl, test.sealed.jsonl (mode 0400), split.json,
              state.json (harness approval, best params, rounds). Rounds also append to
              ~/.claude/logs/lever-rounds.jsonl (kind=round), and every round and report of a
              pp/wk flow a kind=offline row: the incumbent's offline pp/wk (flow, pp_wk, verdict,
              split), which cc-lever-score reads for ADVANCE's offline sign.
  * split     test iff int(sha1(case_id), 16) % 5 == 0. Assignment is by hash alone, so it is stable
              as cases are added; "stratified by account" is then a CHECK, not a re-draw: every
              account with at least 20 cases must land 10-30% in test, or the split is PLUMBING.
  * seal      the test half is readable only through read_test(unseal=True), which only the round
              and score-on-test paths pass. The analyzer (failures, check) gets train rows only.
  * decide()  the truth table below — the one place a round's verdict is computed.
  * approval  a round runs only while the flow's harness sha equals the sha the operator approved
              (`cc-lever-eval approve-harness <flow> --confirm <sha12>`): the grader, the replay
              and this kernel cannot change under an approved hillclimb.
  * leak      no 8-gram (word tokens) of a sealed test case may appear in a candidate's text.
  * eval env  every eval run sets CC_LEVER_EXCLUDE=1 and works in /tmp/lev-eval, so eval sessions
              can never be scored as production arms (eval rows in production are PLUMBING).

decide() — KEEP iff train > NF_train AND test CI95 lower > 0 AND test point >= MIN_ACT.
  Either half below -NF → REVERT (harm). Train up but test not KEEP-worthy → REVERT (overfit).
  Neither half moved past its noise floor → NOT-MERGED (within noise, never merged).
  Three non-KEEP edit rounds in a row → the next round is STALL: sort the train failures, make
  no edit. At most 6 rounds per flow, then CONFIRM on the next 7 d of fresh production cases.

Stdlib only, Python 3.9-safe.
"""

import hashlib
import json
import math
import os
import random
import re
import stat
import time
from datetime import datetime, timezone

SCHEMA = 2
MAX_ROUNDS = 6
STALL_AFTER = 3
TEST_MOD = 5
STRAT_MIN_CASES, STRAT_LO, STRAT_HI = 20, 0.10, 0.30
LEAK_N = 8
EVAL_CWD = "/tmp/lev-eval"

# the flow registry: verdict unit, smallest improvement acted on, whether rounds spend model runs,
# and the wave that builds the flow (a flow with built=False is refused, never stubbed)
FLOWS = {
    "d3_keepalive": dict(
        kind="pp_wk", min_act=1.0, model_runs=False, built=True, wave="S7a"
    ),
    "d1_recycle": dict(
        kind="pp_wk", min_act=1.0, model_runs=False, built=True, wave="S7b"
    ),
    # the real hook the predicate replays is part of the harness: its _rx_* lines are what a D4
    # round changes, so an approved hillclimb must not see them move under it
    "d4_pollloop": dict(
        kind="pp_wk",
        min_act=1.0,
        model_runs=False,
        built=True,
        wave="S7b",
        extra=("hooks/subagent-long-bash-shadow.sh",),
    ),
    "d1_successor": dict(
        kind="points", min_act=10.0, model_runs=True, built=False, wave="S9"
    ),
    # the grader's judge and rubric are part of the harness; agents/workflow-lean.md is not (it is
    # the surface a round tunes, injected per run), nor is the shadow hook build_cases reads
    "d2_lean": dict(
        kind="points",
        min_act=10.0,
        model_runs=True,
        built=True,
        wave="S10",
        extra=(
            "docs/research/token-efficiency-2026-09-23/eval/harness/f2/setup.sh",
            "docs/research/token-efficiency-2026-09-23/eval/harness/f2/workflow.js",
            "bin/cc-lever-judge",
            "config/lever-rubrics.json",
        ),
    ),
}

KEEP, REVERT, NOT_MERGED, STALL, CONFIRM, EDIT = (
    "KEEP",
    "REVERT",
    "NOT-MERGED",
    "STALL",
    "CONFIRM",
    "EDIT",
)

HERE = os.path.dirname(os.path.realpath(__file__))
EVALS = os.path.dirname(HERE)


class SealedError(RuntimeError):
    pass


class HarnessError(RuntimeError):
    pass


# ── paths and state ──────────────────────────────────────────────────────────────────────────────
def root():
    return os.environ.get("CC_HILLCLIMB_DIR") or os.path.join(
        os.path.expanduser("~"), ".claude/hillclimb"
    )


def flow_dir(flow, create=True):
    if flow not in FLOWS:
        raise KeyError("unknown flow %r (known: %s)" % (flow, ", ".join(sorted(FLOWS))))
    d = os.path.join(root(), flow)
    if create:
        os.makedirs(d, exist_ok=True)
    return d


def rounds_log():
    return os.environ.get("CC_LEVER_ROUNDS_LOG") or os.path.join(
        os.path.expanduser("~"), ".claude/logs/lever-rounds.jsonl"
    )


def utc(t=None):
    return datetime.fromtimestamp(
        time.time() if t is None else t, timezone.utc
    ).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_atomic(path, text, mode=None):
    tmp = path + ".tmp%d" % os.getpid()
    with open(tmp, "w") as fh:
        fh.write(text)
    if mode is not None:
        os.chmod(tmp, mode)
    if os.path.exists(path) and not os.access(path, os.W_OK):
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
    os.replace(tmp, path)


def write_jsonl(path, rows, mode=None):
    _write_atomic(
        path, "".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows), mode
    )


def read_jsonl(path):
    with open(path) as fh:
        return [json.loads(ln) for ln in fh if ln.strip()]


def load_state(flow):
    p = os.path.join(flow_dir(flow), "state.json")
    try:
        with open(p) as fh:
            st = json.load(fh)
    except FileNotFoundError:
        return dict(schema=SCHEMA, flow=flow, harness={}, best_params=None, rounds=[])
    if st.get("schema") != SCHEMA:
        raise RuntimeError(
            "%s: schema %r, kernel speaks %d — migrate it first"
            % (p, st.get("schema"), SCHEMA)
        )
    return st


def save_state(flow, st):
    _write_atomic(
        os.path.join(flow_dir(flow), "state.json"),
        json.dumps(st, indent=1, sort_keys=True) + "\n",
    )


# ── split and seal ───────────────────────────────────────────────────────────────────────────────
def is_test(case_id):
    return int(hashlib.sha1(case_id.encode("utf-8")).hexdigest(), 16) % TEST_MOD == 0


def strat_problems(by_acct):
    """by_acct: {acct: [n_train, n_test]} → list of accounts whose test share is out of band."""
    bad = []
    for a, (ntr, nte) in sorted(by_acct.items()):
        n = ntr + nte
        if n >= STRAT_MIN_CASES and not (STRAT_LO <= nte / n <= STRAT_HI):
            bad.append(
                "%s test share %.3f of %d outside [%.2f, %.2f]"
                % (a, nte / n, n, STRAT_LO, STRAT_HI)
            )
    return bad


def test_sha(ids):
    return hashlib.sha256("\n".join(sorted(ids)).encode("utf-8")).hexdigest()


def split(flow, cases):
    """Write train.jsonl and the sealed test half. → split meta. Raises on a duplicate case_id or an
    out-of-band account (a split that cannot be stratified is not used)."""
    seen = set()
    train, test, by = [], [], {}
    for c in cases:
        cid = c["case_id"]
        if cid in seen:
            raise ValueError("duplicate case_id %r" % cid)
        seen.add(cid)
        half = test if is_test(cid) else train
        half.append(c)
        by.setdefault(c.get("acct", "?"), [0, 0])[half is test] += 1
    bad = strat_problems(by)
    if bad:
        raise ValueError("split not stratified by account: " + "; ".join(bad))
    d = flow_dir(flow)
    write_jsonl(os.path.join(d, "train.jsonl"), train)
    write_jsonl(os.path.join(d, "test.sealed.jsonl"), test, mode=stat.S_IRUSR)
    meta = dict(
        schema=SCHEMA,
        flow=flow,
        n_train=len(train),
        n_test=len(test),
        by_acct=by,
        test_sha=test_sha(c["case_id"] for c in test),
        sealed=True,
        ts=utc(),
    )
    _write_atomic(
        os.path.join(d, "split.json"), json.dumps(meta, indent=1, sort_keys=True) + "\n"
    )
    return meta


def read_train(flow):
    """The analyzer's view: train rows only."""
    return read_jsonl(os.path.join(flow_dir(flow), "train.jsonl"))


def read_test(flow, unseal=False):
    if not unseal:
        raise SealedError(
            "%s: the test split is sealed; only round / score --split test --unseal read it"
            % flow
        )
    d = flow_dir(flow)
    rows = read_jsonl(os.path.join(d, "test.sealed.jsonl"))
    with open(os.path.join(d, "split.json")) as fh:
        want = json.load(fh)["test_sha"]
    if test_sha(r["case_id"] for r in rows) != want:
        raise SealedError(
            "%s: sealed test split does not match split.json (tampered or re-built)"
            % flow
        )
    return rows


# ── harness approval ─────────────────────────────────────────────────────────────────────────────
def harness_files(flow):
    d = os.path.join(EVALS, flow)
    out = [os.path.join(HERE, "hc.py")]
    for dp, _dn, fns in os.walk(d):
        for fn in fns:
            if fn.endswith((".py", ".json", ".sh", ".js")) and "__pycache__" not in dp:
                out.append(os.path.join(dp, fn))
    repo = os.path.dirname(os.path.dirname(EVALS))
    out.extend(os.path.join(repo, p) for p in FLOWS[flow].get("extra", ()))
    return sorted(out)


def harness_sha(flow):
    h = hashlib.sha256()
    for p in harness_files(flow):
        h.update(os.path.relpath(p, EVALS).encode("utf-8") + b"\0")
        with open(p, "rb") as fh:
            h.update(fh.read())
        h.update(b"\0")
    return h.hexdigest()


def approve_harness(flow, confirm):
    """The operator's act. `confirm` must be the first 12 hex of the CURRENT harness sha, so consent
    names exactly the bytes being approved."""
    sha = harness_sha(flow)
    if not confirm or confirm != sha[:12]:
        raise HarnessError(
            "--confirm must be %s (the current %s harness sha)" % (sha[:12], flow)
        )
    st = load_state(flow)
    st["harness"] = dict(sha=sha, approved_at=utc(), by=os.environ.get("USER", "?"))
    save_state(flow, st)
    return sha


def require_approved(flow):
    st = load_state(flow)
    want = (st.get("harness") or {}).get("sha")
    have = harness_sha(flow)
    if want != have:
        raise HarnessError(
            "%s harness %s is not approved (approved: %s) — operator: cc-lever-eval approve-harness %s --confirm %s"
            % (flow, have[:12], (want or "none")[:12], flow, have[:12])
        )
    return have


# ── leak check ───────────────────────────────────────────────────────────────────────────────────
def grams(text, n=LEAK_N):
    w = re.findall(r"\w+", text.lower())
    return {" ".join(w[i : i + n]) for i in range(len(w) - n + 1)}


def leak_check(candidate_text, test_texts, n=LEAK_N):
    """→ sorted list of n-grams the candidate shares with any test case text (empty = clean)."""
    cg = grams(candidate_text, n)
    if not cg:
        return []
    hit = set()
    for t in test_texts:
        hit |= cg & grams(t, n)
    return sorted(hit)


# ── eval environment ─────────────────────────────────────────────────────────────────────────────
def eval_env(base=None):
    env = dict(os.environ if base is None else base)
    env["CC_LEVER_EXCLUDE"] = "1"
    return env


def enter_eval_context():
    """Mark this process and every child as an eval run and move to the neutral cwd."""
    os.environ["CC_LEVER_EXCLUDE"] = "1"
    os.makedirs(EVAL_CWD, exist_ok=True)
    os.chdir(EVAL_CWD)


# ── statistics ───────────────────────────────────────────────────────────────────────────────────
def _strata(rows):
    """rows: (stratum, cluster, value) → {stratum: [cluster totals]}"""
    acc = {}
    for s, c, v in rows:
        acc.setdefault(s, {}).setdefault(c, 0.0)
        acc[s][c] += v
    return {s: list(cs.values()) for s, cs in acc.items()}


def cluster_bootstrap(rows, scale=1.0, reps=2000, seed=0):
    """Total of `value` x scale with a percentile CI95: clusters resampled with replacement within
    each stratum (cluster = session, stratum = account). → (point, lo, hi, sd)."""
    st = _strata(rows)
    point = sum(sum(v) for v in st.values()) * scale
    rng = random.Random(seed)
    tot = []
    for _ in range(reps):
        t = 0.0
        for cs in st.values():
            n = len(cs)
            t += sum(cs[rng.randrange(n)] for _ in range(n))
        tot.append(t * scale)
    tot.sort()
    m = sum(tot) / reps
    sd = math.sqrt(sum((x - m) ** 2 for x in tot) / (reps - 1)) if reps > 1 else 0.0
    return point, tot[int(0.025 * reps)], tot[min(reps - 1, int(0.975 * reps))], sd


def noise_floor(rows, scale=1.0, reps=2000, seed=0):
    """NF of a half's paired delta total: 1.96 x its cluster-bootstrap SD (a deterministic replay has
    no run-to-run noise, so case sampling is the whole floor)."""
    return 1.96 * cluster_bootstrap(rows, scale, reps, seed)[3]


def aa_fpr(rows, reps=200, salt="aa"):
    """Pseudo-salt A/A: split clusters into two pseudo-arms by sha256(salt:i:cluster) and test the
    difference of mean cluster totals at |z| >= 1.96. → share of reps that came out 'significant'."""
    clusters = {}
    for _s, c, v in rows:
        clusters[c] = clusters.get(c, 0.0) + v
    items = sorted(clusters.items())
    hits = 0
    for i in range(reps):
        a, b = [], []
        for c, v in items:
            h = int(
                hashlib.sha256(("%s:%d:%s" % (salt, i, c)).encode()).hexdigest()[:13],
                16,
            )
            (a if h % 2 else b).append(v)
        if len(a) < 2 or len(b) < 2:
            continue
        ma, mb = sum(a) / len(a), sum(b) / len(b)
        va = sum((x - ma) ** 2 for x in a) / (len(a) - 1)
        vb = sum((x - mb) ** 2 for x in b) / (len(b) - 1)
        se = math.sqrt(va / len(a) + vb / len(b))
        if se > 0 and abs(ma - mb) / se >= 1.959964:
            hits += 1
    return hits / reps


# ── the decision ─────────────────────────────────────────────────────────────────────────────────
def decide(train, nf_train, test_point, test_lo, nf_test, min_act):
    """→ (verdict, reason). train/test in the flow's unit (pp/wk or points)."""
    if train < -nf_train or test_point < -nf_test:
        return (
            REVERT,
            "harm: a half fell below -NF (train %.3f vs -%.3f, test %.3f vs -%.3f)"
            % (
                train,
                nf_train,
                test_point,
                nf_test,
            ),
        )
    if train > nf_train and test_lo > 0 and test_point >= min_act:
        return (
            KEEP,
            "train %.3f > NF %.3f, test CI95 lower %.3f > 0, test %.3f >= MIN_ACT %.3f"
            % (
                train,
                nf_train,
                test_lo,
                test_point,
                min_act,
            ),
        )
    if train > nf_train:
        return (
            REVERT,
            "train up (%.3f > NF %.3f), test flat (point %.3f, CI95 lower %.3f, MIN_ACT %.3f)"
            % (
                train,
                nf_train,
                test_point,
                test_lo,
                min_act,
            ),
        )
    return NOT_MERGED, "within noise: train %.3f <= NF %.3f" % (train, nf_train)


def next_action(rounds):
    """→ EDIT | STALL | CONFIRM for the next round, from the verdicts so far. STALL rounds count
    toward the cap and reset the non-KEEP streak (the streak counts edit rounds only)."""
    if len(rounds) >= MAX_ROUNDS:
        return CONFIRM
    streak = 0
    for r in reversed(rounds):
        if r["verdict"] in (KEEP, STALL):
            break
        streak += 1
    return STALL if streak >= STALL_AFTER else EDIT


def _append_rounds_line(line):
    p = rounds_log()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    fd = os.open(p, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        os.write(fd, (line + "\n").encode("utf-8"))
    finally:
        os.close(fd)


def record_offline(flow, pp_wk, lo, verdict, split, params, harness=None):
    """Append the incumbent's offline savings as a kind=offline row of lever-rounds.jsonl: the row
    cc-lever-score's ADVANCE reads for "the offline replay agrees in sign" (pp/wk flows only)."""
    row = dict(kind="offline", flow=flow, ts=utc(), pp_wk=round(pp_wk, 4), lo=round(lo, 4),
               verdict=verdict, split=split, params=params, harness=harness)
    line = json.dumps(row, separators=(",", ":"), sort_keys=True)
    if len(line) > 2048:
        row.pop("params")
        line = json.dumps(dict(row, truncated=True), separators=(",", ":"), sort_keys=True)
    _append_rounds_line(line)
    return row


def record_round(flow, row):
    """Append a round to state.json and lever-rounds.jsonl (one write, UTC Z, ≤ 2 KB)."""
    st = load_state(flow)
    row = dict(row, flow=flow, n=len(st["rounds"]) + 1, ts=utc())
    st["rounds"].append(row)
    if row["verdict"] == KEEP and row.get("candidate") is not None:
        st["best_params"] = row["candidate"]
    save_state(flow, st)
    line = json.dumps(dict(kind="round", **row), separators=(",", ":"), sort_keys=True)
    if len(line) > 2048:
        line = json.dumps(
            dict(
                kind="round",
                flow=flow,
                n=row["n"],
                ts=row["ts"],
                verdict=row["verdict"],
                truncated=True,
            ),
            separators=(",", ":"),
        )
    _append_rounds_line(line)
    return row
