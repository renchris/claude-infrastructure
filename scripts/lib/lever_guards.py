#!/usr/bin/env python3
"""lever_guards.py — the usage levers' shared guards (docs/plans/USAGE_LEVERS.md § W7+ §2 "Shared
guards"; wave S5). Guards catch large harm, trigger rollbacks, and never count as evidence of a gain.

THE GUARD PATH READS NO TRANSCRIPT. Its inputs are small stores only: the per-session ledger rows
cc-lever-score writes (~/.claude/logs/lever-ledger.jsonl), claude-crashes.jsonl, lever-judge.jsonl
(S8), the flag file, and a directory listing of the four projects roots. Bound: 60 s.

RATIO GUARDS — one-sided (treatment WORSE), Holm-corrected per lever, alpha 0.01 hourly and 0.05
at a look; per-session units, stratified CR1 delta-method SE (lever_stats.ratio_diff_z):
  T1  tool errors per 100 requests (hook denies are excluded; they are reported per arm apart)
  T2  failed lands per landed land: exits 5/6/11/143 failed, 42 excluded, any other code PLUMBING
  T4  CRASH rows in claude-crashes.jsonl per session
  T5  judged re-ask rate per session (rows kind=reask in lever-judge.jsonl; the judge lands in S8,
      until then T5 is "pending" and does not blind the lever)
  No treated denominator: "ok" (nothing treated to harm). No control denominator (per-unit arms
  leave few all-control sessions): tested against config/levers.json's pre-registered baseline.
COUNT ALARM, no Holm:
  T3  prompt-too-long main-session deaths in TREATED sessions over the window: trips at >= 2 at S1,
      >= 3 at S2/S3 (false-trip 0.27% / 0.67% / 4.1% at 10/50/100% [C]); needs all four roots listable.

A session's arm for a lever: D1/D2 the ledger row's arms[L].arm; D3/D4 the arm of its FIRST event
for L (ledger first_arm), a coin flip whatever the session's length, so long sessions cannot crowd
the treated arm; no event, outside the population. Fewer than min_ctrl_sessions control sessions
with a denominator: the guard tests against the baseline alone. Eval rows never count.

LEVER VERDICT: BREACH (a Holm-rejected ratio guard or a T3 trip) > PLUMBING (T2 unknown exit) >
IDLE (pct 0 and no treated session in the window: nothing to guard) > NO-DATA (blind: a stale or
missing ledger, an unread root, a guard with neither a control denominator nor a baseline, or a
live lever with no treated session) > OK.
"""

import json
import os
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
import lever_events as le  # noqa: E402
import lever_stats as ls  # noqa: E402

lf = le.lf
RATIO = ("T1", "T2", "T4", "T5")
CRASH_LOG = "claude-crashes.jsonl"
JUDGE_LOG = "lever-judge.jsonl"


def _ts(v):
    """Ledger first/last_ts are scan()'s naive UTC; tolerate a zoned stamp too."""
    if isinstance(v, str) and len(v) == 19:
        return le.parse_ts(v + "Z")
    return le.parse_ts(v)


def read_ledger(path=None):
    """→ (rows, {lines, bad, missing, age_s}). Rows keep only well-formed ledger objects."""
    path = path or le.log_path(le.LEDGER_LOG)
    rows, st = [], {"lines": 0, "bad": 0, "missing": False, "age_s": None}
    try:
        st["age_s"] = max(0.0, _now() - os.stat(path).st_mtime)
        fh = open(path, "rb")
    except OSError:
        st["missing"] = True
        return rows, st
    with fh:
        for raw in fh:
            if not raw.strip():
                continue
            st["lines"] += 1
            try:
                r = json.loads(raw)
            except ValueError:
                st["bad"] += 1
                continue
            if (
                isinstance(r, dict)
                and r.get("kind") == "ledger"
                and isinstance(r.get("sid"), str)
            ):
                rows.append(r)
            else:
                st["bad"] += 1
    return rows, st


def _now():
    v = os.environ.get("CC_NOW", "")
    try:
        return float(v)
    except ValueError:
        return time.time()


def read_counts_by_sid(name, since, until, want):
    """{sid: n} over a small jsonl store; `want(row)` selects the counted rows. Missing → None."""
    path = le.log_path(name)
    if not os.path.exists(path):
        return None, {"lines": 0, "bad": 0, "missing": True}
    rows, st = le.read_jsonl(path, since, until)
    out = {}
    for r in rows:
        sid = r.get("sid")
        if isinstance(sid, str) and want(r):
            out[sid] = out.get(sid, 0) + 1
    return out, st


def session_arm(row, lever):
    if lever in ("D1", "D2"):
        a = ((row.get("arms") or {}).get(lever) or {}).get("arm")
        return (
            "treat" if a == "treat" else ("ctrl" if a in ("ctrl", "holdback") else None)
        )
    a = (row.get("first_arm") or {}).get(lever)
    return "treat" if a == "treat" else ("ctrl" if a in ("ctrl", "holdback") else None)


def evaluate(
    rows,
    ledger_st,
    flags,
    cfg,
    since,
    until,
    look=False,
    crashes=None,
    judge=None,
    roots_ok=True,
):
    """→ {lever: result} for every lever. Pure over its inputs (the CLI does the reading)."""
    g = cfg["guards"]
    alpha = g["look_alpha"] if look else g["hourly_alpha"]
    stale = (
        ledger_st.get("missing")
        or (ledger_st.get("age_s") is None)
        or ledger_st["age_s"] > g["ledger_max_age_s"]
    )
    doc, src = flags
    out = {}
    for L in lf.LEVERS:
        e = (
            lf._norm_lever(((doc or {}).get("levers") or {}).get(L))
            if src == "file"
            else None
        )
        stage = (e or {}).get("stage", "S0")
        pct = (e or {}).get("pct", 0) if (e or {}).get("mode") == "live" else 0
        pop = []
        for r in rows:
            if r.get("eval"):
                continue
            t = _ts(r.get("last_ts"))
            if t is None or t < since or t >= until:
                continue
            a = session_arm(r, L)
            if a:
                pop.append((a, r))
        n_treat = sum(1 for a, _ in pop if a == "treat")
        guards = {}

        def ratio_guard(name, num, den):
            rr = [
                (r.get("acct") or "?", r["sid"], a, float(num(r)), float(den(r)))
                for a, r in pop
            ]
            if not sum(x[4] for x in rr if x[2] == "treat"):
                return {
                    "status": "ok",
                    "detail": "no treated exposure: nothing to harm",
                }
            base = (g.get(name) or {}).get("baseline")
            n_ctrl = sum(1 for x in rr if x[2] == "ctrl" and x[4] > 0)
            if n_ctrl < g["min_ctrl_sessions"]:  # too few controls to compare against
                rr = [x for x in rr if x[2] == "treat"]
            res = ls.ratio_diff_z(rr, base)
            if res is None:
                return {
                    "n_ctrl": n_ctrl,
                    "status": "no-data",
                    "detail": "no control denominator and no baseline",
                }
            return dict(res, status="ok")

        guards["T1"] = ratio_guard(
            "T1",
            lambda r: r.get("tool_errors", 0),
            lambda r: r.get("responses", 0) / 100.0,
        )
        for a in ("treat", "ctrl"):
            guards["T1"]["hook_denies_" + a] = sum(
                r.get("tool_errors_hook", 0) for x, r in pop if x == a
            )
        unknown = sum((r.get("lands") or {}).get("unknown", 0) for _, r in pop)
        if unknown:
            guards["T2"] = {
                "status": "plumbing",
                "detail": "%d land(s) with an unknown exit code" % unknown,
            }
        else:
            guards["T2"] = ratio_guard(
                "T2",
                lambda r: (r.get("lands") or {}).get("failed", 0),
                lambda r: (r.get("lands") or {}).get("ok", 0),
            )
        if crashes is None:
            guards["T4"] = {"status": "no-data", "detail": CRASH_LOG + " absent"}
        else:
            guards["T4"] = ratio_guard(
                "T4", lambda r: crashes.get(r["sid"], 0), lambda r: 1
            )
        if judge is None:
            guards["T5"] = {
                "status": "pending",
                "detail": "the re-ask judge lands in wave " + g["T5"]["owner"],
            }
        else:
            jn = {s: v for s, v in judge.items()}
            guards["T5"] = ratio_guard(
                "T5",
                lambda r: jn.get(r["sid"], (0, 0))[0],
                lambda r: jn.get(r["sid"], (0, 0))[1],
            )
        # T3: a count alarm over treated sessions
        deaths = sum(
            1 for a, r in pop if a == "treat" and (r.get("ptl") or {}).get("death")
        )
        trip_ge = g["T3"]["trip_ge"].get(stage, g["T3"]["trip_ge"]["S1"])
        if not roots_ok:
            guards["T3"] = {
                "status": "no-data",
                "detail": "a projects root is unread",
                "deaths": deaths,
            }
        else:
            guards["T3"] = {
                "status": "breach" if deaths >= trip_ge else "ok",
                "deaths": deaths,
                "trip_ge": trip_ge,
            }
        rej = ls.holm(
            {k: guards[k].get("p") for k in RATIO if guards[k]["status"] == "ok"}, alpha
        )
        for k, v in rej.items():
            if v:
                guards[k]["status"] = "breach"
        sts = [v["status"] for v in guards.values()]
        if "breach" in sts:
            verdict = "BREACH"
        elif "plumbing" in sts:
            verdict = "PLUMBING"
        elif pct == 0 and n_treat == 0:
            verdict = "IDLE"
        elif (
            stale or "no-data" in sts or n_treat == 0
        ):  # live with no treated session: blind
            verdict = "NO-DATA"
        else:
            verdict = "OK"
        out[L] = {
            "lever": L,
            "stage": stage,
            "pct": pct,
            "verdict": verdict,
            "alpha": alpha,
            "look": bool(look),
            "sessions": {"treat": n_treat, "ctrl": len(pop) - n_treat},
            "ledger": "stale" if stale else "fresh",
            "guards": guards,
        }
    return out


def run(cfg, since, until, look=False):
    """Read the small stores and evaluate. → (results, inputs summary)."""
    rows, st = read_ledger()
    crashes, cst = read_counts_by_sid(
        CRASH_LOG, since, until, lambda r: r.get("class") == "CRASH"
    )
    judge = None
    jpath = le.log_path(JUDGE_LOG)
    if os.path.exists(jpath):
        jrows, _ = le.read_jsonl(jpath, since, until)
        judge = {}
        for r in jrows:
            if r.get("kind") == "reask" and isinstance(r.get("sid"), str):
                x, n = judge.get(r["sid"], (0, 0))
                judge[r["sid"]] = (x + (1 if r.get("reask") else 0), n + 1)
    roots_ok = all(r["ok"] for r in le.root_status())
    res = evaluate(
        rows, st, le.read_flags(), cfg, since, until, look, crashes, judge, roots_ok
    )
    return res, {
        "ledger_rows": len(rows),
        "ledger_age_s": st.get("age_s"),
        "ledger_missing": st.get("missing"),
        "crash_sids": len(crashes or {}),
        "roots_ok": roots_ok,
    }
