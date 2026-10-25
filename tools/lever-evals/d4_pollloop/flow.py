#!/usr/bin/env python3
"""flow.py — the d4_pollloop flow as bin/cc-lever-eval drives it (plan § W7+ §2 D4 "Offline" and
"Population gate").

Programmatic only, no model runs. Every verdict is the REAL hook's (predicate.py replays it with its
log redirected). One case is one subagent poll-loop Bash call (build_cases.py); its value is the net
pp of denying it AT FULL COMPLIANCE, which makes every number here a HEADROOM: what the deny could
save if every denied agent re-issued as told. Compliance itself is measured by model runs, which
the plan allows only after this headroom passes.

PRICE OF ONE DENIED CALL (pp; write w, read r, both pp/Mtok; ctx = the calling request's context):
  saved   min(ncw, ctx) x w   when the call is a wait (is_wait) whose real gap outlived the 5-min
                              cache (reb): the re-write of the prior context that slicing avoids
  cost    (1 + extra slices) x ctx x r: the deny round trip, plus one warm read per extra 270 s
          slice a wait of `held` seconds needs (ceil(held/270) - 1); a non-wait pays the round trip
The plan's write weight for D4 is 0.20 (a re-price of the 0.245 fit): both ends are scored, the
worse decides a round, and the population gate prices at 0.20.

POPULATION GATE (check --population): at least 20 non-exempt would-deny calls a week, pricing at
least 1.0 pp/wk gross (rebuilds avoided, write 0.20), over the build's LAST 7 days (the whole
window when it is shorter); every week of the window is printed beside it. Otherwise PARK —
"approved, no target population" — re-checked weekly. Fails closed: no build, no cases, or a
replay whose positive control the hook did not log is PARK, never PASS.

Tunable (§3): the pattern — a round's candidate is {"hook": "<path to a candidate hook>"}, whose
_rx_* lines differ from the repo hook's. The message is the compliance flow's (S11).
"""

import json
import math
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
import build_cases  # noqa: E402
import predicate  # noqa: E402

NAME = "d4_pollloop"
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
IMPORTS = os.path.join(os.path.expanduser("~"), ".claude/hillclimb/_imports")
REF_IMPORT = os.path.join(
    IMPORTS, "d4-ref", "cases.jsonl"
)  # the census window, built by build_cases.py
REF_FIXTURE = os.path.join(REPO, "tests", "fixtures", "lever-eval-d4-calls.jsonl.gz")
SLICE_S = 270.0
GATE_N_WK, GATE_PP_WK, GATE_W, GATE_DAYS = 20.0, 1.0, 0.20, 7.0
# the design's census (noise-floor d4events.py over REF_START + 28 d): poll-loop REQUESTS in files the
# noise-floor scanner flagged; build_cases counts CALLS in every file, so check_repro restates it
CENSUS = dict(requests=3730, gap_over_300=326)
TOL = 0.05
AA_BAND = (0.02, 0.08)


class Weights(dict):
    """A read end: {write, read} pp per Mtok. Hashable by value for policy.READS."""


def _w(write, read):
    return Weights(write=write, read=read)


class policy:  # noqa: N801 — the namespace cc-lever-eval reads as F.policy
    READS = (("w0.245", _w(0.245, 0.0076)), ("w0.20", _w(0.20, 0.0076)))
    DEFAULT = ("candidate", "perfect_foresight", "never")
    TUNABLE = dict(hook=predicate.HOOK)

    @staticmethod
    def run(cases, pol, r, wk=1.0, params=None, per_case=None):
        vals = values(cases, pol, r, params)
        if per_case is not None:
            per_case.update({k: v * wk for k, v in vals.items()})
        den = [k for k, v in vals.items() if v != 0.0]
        return {
            "all": dict(net=sum(vals.values()) * wk, denied=len(den), cases=len(vals))
        }

    @staticmethod
    def line(label, res):
        a = res["all"]
        return "%-28s net %+8.4f pp/wk · %d of %d calls denied" % (
            label,
            a["net"],
            a["denied"],
            a["cases"],
        )


def held(g):
    return g["rt"] if g.get("rt") is not None else g.get("gap")


def price(g, r):
    """→ (saved, cost) of denying case g at weights r, in pp, at full compliance."""
    ctx = float(g.get("ctx") or 0)
    saved = 0.0
    if g.get("is_wait") and g.get("reb") and g.get("ncw"):
        saved = min(float(g["ncw"]), ctx) * r["write"] / 1e6
    h = held(g) or 0.0
    extra = max(0, int(math.ceil(h / SLICE_S)) - 1) if g.get("is_wait") else 0
    return saved, (1 + extra) * ctx * r["read"] / 1e6


def values(cases, pol, r, params=None):
    """→ {case_id: unscaled net pp of the policy's denies}."""
    if pol == "never":
        return {g["case_id"]: 0.0 for g in cases}
    if pol == "perfect_foresight":
        out = {}
        for g in cases:
            s, c = price(g, r)
            out[g["case_id"]] = max(0.0, s - c)
        return out
    if pol != "candidate":
        raise ValueError(
            "unknown D4 policy %r (known: %s)" % (pol, ", ".join(policy.DEFAULT))
        )
    hook = validate_params(params or {})["hook"]
    rows = predicate.replay(cases, hook)
    out = {}
    for g in cases:
        if predicate.would_deny(rows[g["case_id"]]):
            s, c = price(g, r)
            out[g["case_id"]] = s - c
        else:
            out[g["case_id"]] = 0.0
    return out


def case_id(g):
    return g["case_id"]


def build(days=28.0, start=None, end=None):
    if start is None:
        end = end if end is not None else time.time()
        start = end - days * 86400
    elif end is None:
        end = start + days * 86400
    return build_cases.build(start, end)


def import_cases(path):
    """A build_cases.py output (meta from its sibling .meta) or a gz fixture whose first line is
    {"_meta": …}. → (cases, meta)."""
    import gzip

    op = gzip.open if path.endswith(".gz") else open
    cases, meta = [], None
    with op(path, "rt") as fh:
        for ln in fh:
            if ln.strip():
                j = json.loads(ln)
                if meta is None and "_meta" in j:
                    meta = j["_meta"]
                else:
                    cases.append(j)
    if meta is None and os.path.exists(path + ".meta"):
        with open(path + ".meta") as fh:
            meta = json.load(fh)
    if meta is None:
        raise ValueError(
            "%s: no meta (neither a _meta line nor a .meta sibling)" % path
        )
    return cases, dict(meta, source=path, cases=len(cases))


def wk(meta):
    return 7 * 86400.0 / float(meta["window_s"])


def validate_params(p):
    bad = sorted(set(p) - set(policy.TUNABLE))
    if bad:
        raise ValueError("not tunable for D4 here: %s (tunable: hook)" % ", ".join(bad))
    full = dict(policy.TUNABLE)
    full.update(p)
    full["hook"] = os.path.abspath(full["hook"])
    if not os.path.isfile(full["hook"]):
        raise ValueError("hook %r does not exist" % full["hook"])
    if subprocess.run(
        [predicate.BASH, "-n", full["hook"]], capture_output=True
    ).returncode:
        raise ValueError(
            "hook %r fails `bash -n` under %s" % (full["hook"], predicate.BASH)
        )
    return full


def baseline_params(state):
    return validate_params(state.get("best_params") or {})


def evaluate(cases, params, r):
    return values(cases, "candidate", r, params)


def case_text(g):
    """The command is free text a candidate pattern could copy from a sealed test case."""
    return g.get("cmd") or ""


def confusion(cases, rows):
    """Precision/recall of the hook's would-deny against the is_wait label, plus where waits escape."""
    tp = fp = fn = 0
    miss = {}
    for g in cases:
        d, w, row = (
            predicate.would_deny(rows[g["case_id"]]),
            bool(g.get("is_wait")),
            rows[g["case_id"]],
        )
        tp += d and w
        fp += d and not w
        if w and not d:
            fn += 1
            if row is None:
                k = "not judged (timeout<=270 s, backgrounded or none)"
            elif predicate.exempt(row):
                k = "exempt (inner timeout < 300 s)"
            else:
                k = "judged, other class: %s" % (
                    row.get("would_deny_class") or row.get("why") or "none"
                )
            miss[k] = miss.get(k, 0) + 1
    prec = tp / float(tp + fp) if tp + fp else None
    rec = tp / float(tp + fn) if tp + fn else None
    return dict(tp=tp, fp=fp, fn=fn, precision=prec, recall=rec, waits_missed=miss)


def failures(cases, params, r=None):
    """Train-side: where the candidate's denies lose pp, and the waits it lets through."""
    r = policy.READS[1][1] if r is None else r
    rows = predicate.replay(cases, validate_params(params)["hook"])
    cause = {}
    for g in cases:
        s, c = price(g, r)
        d = predicate.would_deny(rows[g["case_id"]])
        if d and s - c < 0:
            k, loss = (
                (
                    "wrong_deny:not_a_wait"
                    if not g.get("is_wait")
                    else "deny_without_rebuild"
                ),
                c - s,
            )
        elif not d and s - c > 0:
            row = rows[g["case_id"]]
            k = "missed:" + (
                "not_judged"
                if row is None
                else "exempt"
                if predicate.exempt(row)
                else "pattern"
            )
            loss = s - c
        else:
            continue
        e = cause.setdefault(k, [0, 0.0])
        e[0] += 1
        e[1] += loss
    return sorted(
        ([k, n, round(pp, 4)] for k, (n, pp) in cause.items()), key=lambda x: -x[2]
    )


# ── checks ───────────────────────────────────────────────────────────────────────────────────────
def check_population(cases, meta):
    """→ (ok, rows). ok only on PASS; every row is printed."""
    if not cases:
        return False, ["PARK population: no data — the build holds 0 cases"]
    try:
        rows = predicate.replay(cases)
    except predicate.PlumbingError as e:
        return False, ["PARK population: no verdict — %s" % e]
    k = wk(meta)
    den = [g for g in cases if predicate.would_deny(rows[g["case_id"]])]
    gross = {rn: sum(price(g, r)[0] for g in den) * k for rn, r in policy.READS}
    net = {
        rn: sum(price(g, r)[0] - price(g, r)[1] for g in den) * k
        for rn, r in policy.READS
    }
    gw = _w(GATE_W, 0.0076)
    # the decision reads the build's LAST 7 days (the plan's headroom precondition: "on the last 7
    # days"), so a population that has since moved under the exemption cannot pass on its history
    end = float(meta.get("end") or max(g["t"] for g in cases))
    span = min(GATE_DAYS * 86400.0, float(meta["window_s"]))
    last = [g for g in den if g["t"] >= end - span]
    n_wk = len(last) * 7 * 86400.0 / span
    pp_wk = sum(price(g, gw)[0] for g in last) * 7 * 86400.0 / span
    ok = n_wk >= GATE_N_WK and pp_wk >= GATE_PP_WK
    exempt = sum(1 for g in cases if predicate.exempt(rows[g["case_id"]]))
    judged = sum(1 for g in cases if rows[g["case_id"]] is not None)
    vers = sorted({str(r.get("v")) for r in rows.values() if r})
    cm = confusion(cases, rows)
    out = [
        "%s population: %.1f non-exempt would-deny calls/wk (need >= %d), pricing %.3f pp/wk gross at "
        "write %.2f (need >= %.1f), over the last %.1f d"
        % (
            "PASS" if ok else "PARK",
            n_wk,
            GATE_N_WK,
            pp_wk,
            GATE_W,
            GATE_PP_WK,
            span / 86400,
        )
    ]
    start = end - float(meta["window_s"])
    for w in range(int(math.ceil(float(meta["window_s"]) / (7 * 86400.0) - 1e-9))):
        lo, hi = start + w * 7 * 86400, min(end, start + (w + 1) * 7 * 86400)
        inw = [g for g in den if lo <= g["t"] < hi or (hi == end and g["t"] == end)]
        out.append(
            "  week %d (%s): %d would-deny, %.3f pp gross at write %.2f"
            % (
                w + 1,
                time.strftime("%Y-%m-%d", time.gmtime(lo)),
                len(inw),
                sum(price(g, gw)[0] for g in inw),
                GATE_W,
            )
        )
    out.append(
        "  window %.1f d · %d poll-loop calls · %d judged by the hook (row v%s) · %d exempt by inner "
        "timeout · %d would-deny"
        % (
            float(meta["window_s"]) / 86400,
            len(cases),
            judged,
            "/".join(vers) or "-",
            exempt,
            len(den),
        )
    )
    out.append(
        "  headroom at full compliance, pp/wk: gross %s · net of round trips and slices %s"
        % (
            " ".join("%s %.3f" % kv for kv in gross.items()),
            " ".join("%s %+.3f" % kv for kv in net.items()),
        )
    )
    fmt = lambda x: "n/a" if x is None else "%.3f" % x  # noqa: E731
    out.append(
        "  vs is_wait (held >= 270 s): precision %s (%d/%d) · recall %s (%d/%d)"
        % (
            fmt(cm["precision"]),
            cm["tp"],
            cm["tp"] + cm["fp"],
            fmt(cm["recall"]),
            cm["tp"],
            cm["tp"] + cm["fn"],
        )
    )
    for kk, n in sorted(cm["waits_missed"].items(), key=lambda x: -x[1]):
        out.append("    waits not denied: %-48s %d" % (kk, n))
    if not ok:
        out.append(
            "  verdict PARK: approved, no target population; re-check weekly (`cc-lever-eval build %s` "
            "then `check %s --population`)" % (NAME, NAME)
        )
    return ok, out


CONV = os.path.join(IMPORTS, "conv-tests", "3df527edd333")
NOISE_DATA = os.path.join(IMPORTS, "lev-design", "noise-floor", "data")


def hand_cases(
    sample=os.path.join(CONV, "sample.json"), sims=os.path.join(CONV, "sims.jsonl")
):
    """The conv-test's 20 hand-read poll loops (hand="wait") and their 20 re-issues as told
    (hand="reissue"), as cases. [] when the import is absent."""
    try:
        with open(sample) as fh:
            S = json.load(fh)
        with open(sims) as fh:
            R = [json.loads(ln) for ln in fh if ln.strip()]
    except OSError:
        return []
    out = []
    for r in S:
        aid = r["file"].rsplit("/", 1)[-1][len("agent-") : -len(".jsonl")]
        out.append(
            dict(
                case_id="hand:" + r["id"],
                hand="wait",
                cmd=r["cmd"],
                timeout_ms=r["to"],
                bg=False,
                agent_id=aid,
                sid="hand",
                acct=r["acct"],
                t=r["t"],
                rt=r["rt"],
                gap=r["gap"],
                ctx=r["ctx"],
                ncw=r["ncc"],
                reb=bool(r["reb"]),
                is_wait=True,
            )
        )
    for s in R:
        c = s["call"]
        out.append(
            dict(
                case_id="reissue:%02d" % s["n"],
                hand="reissue",
                cmd=c["command"],
                timeout_ms=c.get("timeout"),
                bg=bool(c.get("run_in_background")),
                agent_id="reissue",
                sid="hand",
                acct="hand",
                t=0,
                rt=None,
                gap=None,
                ctx=0,
                ncw=None,
                reb=False,
                is_wait=False,
            )
        )
    return out


def census(cases, meta, data=NOISE_DATA):
    """The design's 3,730 restated in its own method, or None when it cannot be: noise-floor
    d4events.py counted poll-loop REQUESTS (one per request, however many poll calls it made) with a
    following request, only in subagent files its scanner flagged — and that scanner looked for
    tool_use blocks in the FIRST streamed record of each request only, so files whose poll call sat in
    a later record were never reread. build_cases counts every call in every file; this re-applies
    the census's three restrictions to show the two populations are the same transcripts."""
    if abs(
        float(meta.get("start", 0)) - build_cases.REF_START
    ) > 1 or not os.path.isdir(data):
        return None
    flagged = set()
    for a in ("next", "next2", "next3", "next4"):
        p = os.path.join(data, a + ".files.tsv")
        if not os.path.exists(p):
            return None
        with open(p) as fh:
            hdr = fh.readline().rstrip("\n").split("\t")
            for ln in fh:
                r = dict(zip(hdr, ln.rstrip("\n").split("\t")))
                if r.get("is_sub") == "1" and int(r.get("poll_loops") or 0) > 0:
                    flagged.add(r["path"].split("/projects/", 1)[1])
    seen, n, n300 = set(), 0, 0
    for g in sorted(cases, key=lambda g: g["t"]):
        f = g.get("file") or ""
        if "/projects/" not in f or f.split("/projects/", 1)[1] not in flagged:
            continue
        if g.get("gap") is None or g.get("rid") in seen:
            continue
        seen.add(g.get("rid"))
        n += 1
        n300 += g["gap"] > 300
    return dict(requests=n, gap_over_300=n300)


def check_repro(ref_cases, ref_meta):
    """(1) replay_pred.py's known answers, on the hand-read cases the ref carries: the 20 hand-read
    poll loops are all logged as poll-loop would-denies, and their 20 re-issues (270 s slices) are
    not judged again. (2) When the ref is the census window built from transcripts, the design's
    census restated in its own method (requests, in files the noise-floor scanner flagged) lands
    within ±5% of 3,730 / 326."""
    rows, ok = [], True
    hand = [g for g in ref_cases if g.get("hand")] or hand_cases()
    rep = predicate.replay(hand)
    orig = [g for g in hand if g.get("hand") == "wait"]
    sims = [g for g in hand if g.get("hand") == "reissue"]
    if orig or sims:
        nd = sum(predicate.would_deny(rep[g["case_id"]]) for g in orig)
        nj = sum(rep[g["case_id"]] is not None for g in sims)
        good = len(orig) == 20 and nd == 20 and len(sims) == 20 and nj == 0
        ok &= good
        rows.append(
            "hand-read originals logged as poll-loop would-deny: %d/%d · re-issues judged again: %d/%d %s"
            % (nd, len(orig), nj, len(sims), "ok" if good else "FAIL")
        )
    cen = census(ref_cases, ref_meta)
    if cen:
        rows.append(
            "census restated over %d calls built from transcripts (all files, every call)"
            % len(ref_cases)
        )
        for k, want in sorted(CENSUS.items()):
            got = cen[k]
            dev = abs(got - want) / float(want)
            good = dev <= TOL
            ok &= good
            rows.append(
                "census %s: %d vs design %d (dev %.2f%%, tol %d%%) %s"
                % (k, got, want, 100 * dev, int(100 * TOL), "ok" if good else "FAIL")
            )
    if not (orig or sims or cen):
        ok = False
        rows.append(
            "no reference answers in %s (neither hand-read cases nor a census) FAIL"
            % ref_meta.get("source")
        )
    return ok, rows


def check_oracle(cases):
    """Perfect foresight (deny exactly the calls that pay) scores at least the hook, call by call."""
    rows, ok = [], True
    for rn, r in policy.READS:
        pf = values(cases, "perfect_foresight", r)
        hk = values(cases, "candidate", r)
        worse = [k for k in hk if hk[k] > pf[k] + 1e-12]
        good = not worse and sum(pf.values()) + 1e-12 >= sum(hk.values())
        ok &= good
        rows.append(
            "%s: PF %.4f >= hook %.4f, calls where the hook beats PF: %d %s"
            % (
                rn,
                sum(pf.values()),
                sum(hk.values()),
                len(worse),
                "ok" if good else "FAIL",
            )
        )
    return ok, rows


def check_null(cases):
    rows, ok = [], True
    for rn, r in policy.READS:
        v = values(cases, "never", r)
        good = len(v) == len(cases) and not any(v.values())
        ok &= good
        rows.append(
            "never %s: %d cases, nonzero %d %s"
            % (rn, len(v), sum(1 for x in v.values() if x), "ok" if good else "FAIL")
        )
    return ok, rows


def check_aa(cases, hc):
    vals = evaluate(cases, {}, policy.READS[1][1])
    fpr = hc.aa_fpr([(g["acct"], g["sid"], vals[g["case_id"]]) for g in cases])
    ok = AA_BAND[0] <= fpr <= AA_BAND[1]
    return ok, [
        "pseudo-salt A/A over %d calls, 200 salts: false-positive rate %.3f, band [%.2f, %.2f] %s"
        % (len(cases), fpr, AA_BAND[0], AA_BAND[1], "ok" if ok else "FAIL")
    ]


def check_served_model(cases):
    return True, ["n/a: d4_pollloop replays a hook, it serves no model"]


def check_truncation(cases, n=60):
    """The hook may see only decision-time fields: its payload carries no outcome, and scrambling
    every outcome field of a case leaves the hook's verdict unchanged."""
    out_fields = ("rt", "gap", "ncw", "reb", "is_wait", "ctx")
    leaked = [
        g["case_id"]
        for g in cases
        if any(
            f in json.dumps(predicate.payload(g))
            for f in ('"rt"', '"gap"', '"ncw"', '"reb"', '"is_wait"')
        )
    ]
    pick = sorted(cases, key=lambda g: g["case_id"])[:n]
    a = predicate.replay(pick)
    scr = [
        dict(g, case_id=g["case_id"] + ":scr", **{f: None for f in out_fields})
        for g in pick
    ]
    b = predicate.replay(scr)

    def strip(r):
        return (
            None
            if r is None
            else (r.get("would_deny_class"), r.get("why"), r.get("exempt"))
        )

    diff = sum(strip(a[g["case_id"]]) != strip(b[g["case_id"] + ":scr"]) for g in pick)
    ok = not leaked and diff == 0
    return ok, [
        "payload outcome fields: %d cases leak · verdicts changed by scrambling outcomes: %d of %d %s"
        % (len(leaked), diff, len(pick), "ok" if ok else "FAIL")
    ]


FIXTURE_DENY, FIXTURE_OTHER = 60, 140


def fixture(cases, meta, path=REF_FIXTURE):
    """Write the committed reference fixture: the 40 hand-read cases (hand_cases()), plus a
    deterministic sample of the census build — the first FIXTURE_DENY would-denies and the first
    FIXTURE_OTHER other calls by sha1(case_id), so every hook outcome (would-deny, exempt, other
    class, not judged) is present. sid hashed, transcript path and request id dropped. It is a
    SAMPLE, so it carries no census and its population verdict means nothing; the bats gate tests
    plant their own windows."""
    import gzip
    import hashlib

    hand = hand_cases()
    if len(hand) != 40:
        raise ValueError("hand-read import incomplete: %d of 40 cases" % len(hand))
    rows = predicate.replay(cases)
    order = sorted(cases, key=lambda g: hashlib.sha1(g["case_id"].encode()).hexdigest())
    den = [g for g in order if predicate.would_deny(rows[g["case_id"]])][:FIXTURE_DENY]
    oth = [g for g in order if not predicate.would_deny(rows[g["case_id"]])][
        :FIXTURE_OTHER
    ]
    out = list(hand)
    for g in den + oth:
        h = dict(g, sid=hashlib.sha1(g["sid"].encode()).hexdigest()[:12])
        h.pop("file", None)
        h.pop("rid", None)
        out.append(h)
    m = dict(
        schema=2,
        flow=NAME,
        window_s=meta["window_s"],
        cases=len(out),
        source="fixture: lever-eval-d4-calls (40 hand-read + %d would-deny + %d other, sampled by sha1)"
        % (len(den), len(oth)),
    )
    tmp = path + ".tmp%d" % os.getpid()
    with gzip.open(tmp, "wt") as fh:
        fh.write(json.dumps({"_meta": m}, separators=(",", ":")) + "\n")
        for g in out:
            fh.write(json.dumps(g, separators=(",", ":")) + "\n")
    os.replace(tmp, path)
    return len(out)
