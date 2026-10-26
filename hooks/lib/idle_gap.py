#!/usr/bin/env python3
"""idle_gap.py — the idle-gap ledger and cost model behind the log-only cache keepalive.

Plan: docs/plans/USAGE_LEVERS.md § W3. Research: docs/research/usage-levers-2026-10-23/round2/
REPORT.md decision 3 and round3-probe.md (cache reads are charged).

WHAT IT RECORDS. A main session's prompt cache lives 1 h. When the session sits idle longer, the
next request re-writes the whole context (a "rebuild"). A keepalive that wakes the session once,
3300 s after the gap STARTED, refreshes the cache for another hour. This module keeps one ledger
row per idle gap so the keepalive can be judged before it is ever allowed to wake anything:

  stop        (Stop hook, via hooks/cache-expiry-tracker.sh) closes this session's previous gap —
              when it ended, how long it ran, what the first request after it actually paid — and
              opens the next one with the context size at the gap start. Writes kind=gap rows.
  would-wake  (hooks/idle-keepalive.sh, the timer) records the moment the keepalive would have
              woken an idle session, with the context size and whether a mailbox watcher was armed
              at that moment. Writes kind=wake rows; it wakes only in treatment (S12). Since W6 the row also says
              whether the session's own background job was running at that moment (busy, by the
              launching tool) and whether a watcher already running would fire on its own before
              the cache expires (watcher_fires_before_ttl): the busy-scoped redesign wakes only
              when busy and not watcher_fires_before_ttl. Both come from hooks/lib/session_jobs.py.

W7+ S2 (docs/plans/USAGE_LEVERS.md § W7+ §2 D3, §3 "Telemetry rows") — version bumps, no change in
behaviour; readers of v1 gap / v2 wake rows keep working because only fields are ADDED:
  gap v2   episode_id  the original idle start (ISO), carried across gaps a wake splits, and unit
                       "<sid>:<episode epoch>" — the D3 arm unit, so arm, wake and gap rows join exactly
           ended_by    wake (a FIRED wake, which only a treatment branch can set, ended it) | record
           return_s    episode start → the operator's real return; null while a wake keeps it open
           wake_req, wake_tokens  the wake turn's requests and tokens (null unless ended_by=wake)
           busy, watcher_armed, watcher_fires_before_ttl, eligible, arm, variant  copied from the
                       wake decision made in this gap (null when the gap never reached its due time)
  wake v3  lever D3, arm, variant, unit_id, flag_src, u (from hooks/lib/lever-flags.sh lf_arm, computed
           by the timer at the due time), eligible = busy and not watcher_fires_before_ttl (D3's
           busy-scoped rule with watcher skip; null when the jobs are unreadable), fired = false.
  The wake decision is also kept in the gap's state file (state["wake"]) for the gap row above.

W7+ S12 (plan § W7+ §2 D1 and D3) — the treatment, reachable only at pct > 0 (see verdict() below):
  wake v3 adds pct_eff, headless and why_not (the first guard that held it), and fired = true only
           when D3 acts; would-wake then prints "wake" and the hook exits 2 (the asyncRewake wake).
  d1-due   (the timer, 15 idle min in, at >= 200k) writes kind=would_recycle with the IRS v2 field
           names in both arms; in treatment also the brief, kind=d1_recycle (the lever guard's row
           contract, plan §3 "Auto-rollback") and the treated D1 event in the IRS log, and prints
           the recycle for the hook to fire. One wake per gap across both levers (claim_wake).

COST MODEL (weekly-meter pp per Mtok; reads are charged, round 3):
  a keepalive wake = one cache read of the context + a short turn (~300 written, ~150 output tokens)
  a rebuild        = one cache write of the context, instead of the warm read the next turn would pay
  so a wake that prevents a rebuild nets  ctx*(W - R) - wake,  and any other wake nets  -wake.
  The per-gap break-even is the share of woken gaps that must be rescued: wake / (ctx*(W - R)).
R is a range (0.0057-0.0076, measured at 459k context); every pp figure is reported as [lo, hi].

Stdout stays EMPTY on every path: this runs inside a Stop hook, whose stdout the harness parses.
Fail-open: any error drops the row, never the hook. Python 3.9-safe (stdlib only).
"""

import json
import os
import re
import signal
import sys
import time
from datetime import datetime, timezone

# ── weights: weekly meter, pp per Mtok ───────────────────────────────────────────────────────────
READ_PP = (
    0.0057,
    0.0076,
)  # round3-probe.md: 3.0-4.0pp over 527.0M reads at 458,656-token context
WRITE_PP = 0.245  # round2 fit4: cache writes
OUT_PP = 0.404  # round2 fit4: output
WAKE_WRITE_TOK = (
    300  # the wake prompt + reply entering the cache (round2 fgbtab2 estimate)
)
WAKE_OUT_TOK = 150  # the short reply (same estimate)

WAKE_S = int(os.environ.get("CC_KEEPALIVE_WAKE_S", "3300") or 3300)
TTL_S = int(os.environ.get("CC_PROMPT_CACHE_TTL_S", "3600") or 3600)
MAX_WAKES = int(os.environ.get("CC_KEEPALIVE_MAX_WAKES", "1") or 1)
TAIL_BYTES = int(os.environ.get("CC_IDLE_GAP_TAIL_BYTES", "4000000") or 4000000)

HOME = os.path.expanduser("~")
LOG = os.environ.get("CC_IDLE_KEEPALIVE_LOG") or os.path.join(
    HOME, ".claude/logs/idle-keepalive.jsonl"
)
STATE_DIR = os.environ.get("CC_IDLE_KEEPALIVE_STATE") or os.path.join(
    HOME, ".claude/state/idle-keepalive"
)
SID_RX = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,127}$")


def wake_cost(ctx, r):
    return (ctx * r + WAKE_WRITE_TOK * WRITE_PP + WAKE_OUT_TOK * OUT_PP) / 1e6


def rebuild_extra(ctx, r):
    return ctx * (WRITE_PP - r) / 1e6


def outcome(dur, wake_s=None, ttl_s=None, max_wakes=None):
    """→ (wakes, rebuild_without, rebuild_with, label) for a gap of `dur` seconds."""
    wake_s = WAKE_S if wake_s is None else wake_s
    ttl_s = TTL_S if ttl_s is None else ttl_s
    max_wakes = MAX_WAKES if max_wakes is None else max_wakes
    wakes, last, t = 0, 0, wake_s
    while wakes < max_wakes and dur > t:
        wakes, last, t = wakes + 1, t, t + wake_s
    without = dur >= ttl_s
    with_ = dur >= ((last + ttl_s) if wakes else ttl_s)
    if not wakes:
        label = "no_wake"
    elif not without:
        label = "wake_unneeded"
    elif not with_:
        label = "wake_saves"
    else:
        label = "wake_insufficient"
    return wakes, without, with_, label


def gap_costs(ctx, dur, **kw):
    """→ dict of [lo, hi] pp ranges for one gap (lo = the pessimistic end for the keepalive)."""
    wakes, without, with_, label = outcome(dur, **kw)
    saved = without and not with_
    net = sorted(
        round((rebuild_extra(ctx, r) if saved else 0.0) - wakes * wake_cost(ctx, r), 6)
        for r in READ_PP
    )
    rb = sorted(round(rebuild_extra(ctx, r), 6) for r in READ_PP)
    wk = sorted(round(wake_cost(ctx, r), 6) for r in READ_PP)
    # the share of woken gaps that must be rescued for the wake to pay; undefined at ctx 0
    be = (
        sorted(round(wake_cost(ctx, r) / rebuild_extra(ctx, r), 4) for r in READ_PP)
        if ctx
        else [None, None]
    )
    return dict(
        wakes=wakes,
        rebuild_without=without,
        rebuild_with=with_,
        outcome=label,
        wake_pp=wk,
        rebuild_extra_pp=rb,
        net_pp=net,
        breakeven_p=be,
    )


# ── transcript reading ───────────────────────────────────────────────────────────────────────────
def _ts(rec):
    s = rec.get("timestamp")
    if not isinstance(s, str):
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def tail_records(path):
    """→ (records, window_complete). Only user/assistant main-thread records, in file order."""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            if size > TAIL_BYTES:
                fh.seek(size - TAIL_BYTES)
            raw = fh.read()
    except OSError:
        return [], False
    lines = raw.split(b"\n")
    complete = size <= TAIL_BYTES
    if not complete:
        lines = lines[1:]  # the first tailed line is partial
    out = []
    for ln in lines:
        if b'"type":"user"' not in ln and b'"type":"assistant"' not in ln:
            continue
        try:
            rec = json.loads(ln)
        except ValueError:
            continue
        if (
            isinstance(rec, dict)
            and rec.get("type") in ("user", "assistant")
            and not rec.get("isSidechain")
        ):
            out.append(rec)
    return out, complete


def _usage(rec):
    u = (
        (rec.get("message") or {}).get("usage")
        if isinstance(rec.get("message"), dict)
        else None
    )
    return u if isinstance(u, dict) else None


def context_size(recs):
    """→ (tokens, model) of the context as the last assistant request left it."""
    for rec in reversed(recs):
        if rec.get("type") != "assistant":
            continue
        u = _usage(rec)
        if not u:
            continue
        tok = sum(
            int(u.get(k) or 0)
            for k in (
                "input_tokens",
                "cache_creation_input_tokens",
                "cache_read_input_tokens",
                "output_tokens",
            )
        )
        return tok, (rec.get("message") or {}).get("model")
    return 0, None


def gap_end(recs, start, complete):
    """→ (end_epoch|None, end_src, obs_cw, obs_cr): the first user record after `start`, and what the
    first assistant request after it paid. end_src: record | window (the true end lies before the
    tail window, so this is late) | none."""
    end, src = None, "none"
    for rec in recs:
        t = _ts(rec)
        if t is not None and t > start and rec.get("type") == "user":
            end, src = t, "record"
            break
    if end is None and recs and not complete:
        t0 = next((_ts(r) for r in recs if _ts(r) is not None), None)
        if t0 is not None and t0 > start:
            end, src = t0, "window"
    cw = cr = None
    if end is not None:
        for rec in recs:
            t = _ts(rec)
            if (
                t is not None
                and t >= end
                and rec.get("type") == "assistant"
                and _usage(rec)
            ):
                u = _usage(rec)
                cw, cr = (
                    int(u.get("cache_creation_input_tokens") or 0),
                    int(u.get("cache_read_input_tokens") or 0),
                )
                break
    return end, src, cw, cr


def wake_turn(recs, end):
    """→ (requests, tokens) of the turn a wake opened: every main-thread request from `end` on."""
    n, tok = 0, dict(input=0, cw=0, cr=0, out=0)
    for rec in recs:
        t = _ts(rec)
        u = _usage(rec) if rec.get("type") == "assistant" else None
        if t is None or t < end or not u:
            continue
        n += 1
        for k, f in (
            ("input", "input_tokens"),
            ("cw", "cache_creation_input_tokens"),
            ("cr", "cache_read_input_tokens"),
            ("out", "output_tokens"),
        ):
            tok[k] += int(u.get(f) or 0)
    return n, tok


# Copied from the gap's wake decision onto its gap row (null when the gap never reached its due time).
WAKE_FIELDS = (
    "busy",
    "watcher_armed",
    "watcher_fires_before_ttl",
    "eligible",
    "arm",
    "variant",
)


def episode_of(st):
    """The episode start of a gap's state: its own start unless an earlier wake carried one over."""
    e = st.get("episode")
    return e if isinstance(e, (int, float)) and e <= st["start"] else st["start"]


# ── io ───────────────────────────────────────────────────────────────────────────────────────────
def acct():
    d = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
    return os.path.basename(d.rstrip("/")) or ".claude"


def append(row):
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a") as fh:
        fh.write(json.dumps(row, separators=(",", ":")) + "\n")


def state_path(sid):
    return os.path.join(STATE_DIR, sid + ".json")


def load_state(sid):
    try:
        with open(state_path(sid)) as fh:
            st = json.load(fh)
        return st if isinstance(st, dict) else None
    except (OSError, ValueError):
        return None


def save_state(sid, st):
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = state_path(sid) + ".tmp%d" % os.getpid()
    with open(tmp, "w") as fh:
        json.dump(st, fh)
    os.replace(tmp, state_path(sid))


def now():
    return float(os.environ.get("CC_IDLE_KEEPALIVE_NOW") or time.time())


def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ── subcommands ──────────────────────────────────────────────────────────────────────────────────
def cmd_stop(payload):
    if os.environ.get("CLAUDE_CODE_ENTRYPOINT") == "sdk-cli":
        return  # non-interactive (-p, piped stdout): no idle gap follows its Stop
    sid, tp = payload.get("session_id") or "", payload.get("transcript_path") or ""
    if not SID_RX.match(sid) or not tp:
        return
    # whole seconds: the gap start is compared with second-resolution records
    t = int(now())
    recs, complete = tail_records(tp)
    st = load_state(sid)
    episode = t
    if st and isinstance(st.get("start"), (int, float)) and st["start"] < t:
        end, src, cw, cr = gap_end(recs, st["start"], complete)
        if end is None:
            end, src = t, "stop"
        dur = max(0.0, end - st["start"])
        ctx = int(st.get("ctx") or 0)
        ep = episode_of(st)
        wk = st.get("wake") if isinstance(st.get("wake"), dict) else {}
        woke = (
            wk.get("fired") is True
            and isinstance(wk.get("at"), (int, float))
            and wk["at"] <= end
        )
        if woke:
            episode = ep  # the wake split the episode: the next gap continues it
            wreq, wtok = wake_turn(recs, end)
        else:
            wreq = wtok = None
        row = dict(
            kind="gap",
            v=2,
            ts=iso(t),
            sid=sid,
            acct=st.get("acct") or acct(),
            start=iso(st["start"]),
            end=iso(end),
            dur=round(dur, 1),
            end_src=src,
            ctx=ctx,
            model=st.get("model"),
            wake_s=WAKE_S,
            ttl_s=TTL_S,
            max_wakes=MAX_WAKES,
            would_wake_at=iso(st["start"] + WAKE_S),
            obs_cw=cw,
            obs_cr=cr,
            episode_id=iso(ep),
            unit="%s:%d" % (sid, ep),
            ended_by="wake" if woke else "record",
            return_s=None if woke else round(max(0.0, end - ep), 1),
            wake_req=wreq,
            wake_tokens=wtok,
        )
        row.update({k: wk.get(k) for k in WAKE_FIELDS})
        row.update(gap_costs(ctx, dur))
        append(row)
    ctx, model = context_size(recs)
    save_state(
        sid,
        dict(
            sid=sid,
            start=t,
            episode=episode,
            ctx=ctx,
            model=model,
            acct=acct(),
            transcript=tp,
        ),
    )


def _session_jobs():
    """hooks/lib/session_jobs.py, beside this file's REAL path (-I drops the script dir from
    sys.path, and a brand-new lib file has no ~/.claude/hooks/lib symlink until install.sh runs)."""
    import importlib.util

    p = os.path.join(os.path.dirname(os.path.realpath(__file__)), "session_jobs.py")
    spec = importlib.util.spec_from_file_location("session_jobs", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def jobs_at_wake(transcript, t, gap_start):
    """→ (busy and watcher state at the wake moment, headless): ({}, None) when the transcript cannot
    be read. Headless is the transcript's own entrypoint (sdk-cli), as the lever guard's state_at
    reads it, so a streaming SDK session the hook's argv test lets through still never wakes."""
    if not transcript:
        return {}, None
    try:
        sj = _session_jobs()
        recs = sj.records(transcript, TAIL_BYTES)
        eps = [
            r.get("entrypoint") for r in recs if isinstance(r.get("entrypoint"), str)
        ]
        return (
            sj.running_at(sj.jobs(recs), t, ttl_end=gap_start + TTL_S),
            (sj.HEADLESS_ENTRYPOINT in eps) if eps else None,
        )
    except Exception:
        return {}, None


def parse_arm(s, lever="D3"):
    """The timer's lf_arm_json object (hooks/lib/lever-flags.sh), or {} when absent or malformed."""
    try:
        a = json.loads(s) if s else {}
    except ValueError:
        return {}
    return a if isinstance(a, dict) and a.get("lever") == lever else {}


# ── treatment (W7+ S12; docs/plans/USAGE_LEVERS.md § W7+ §2 D1 and D3) ─────────────────────────────
# A lever ACTS only when the arm the timer computed at its due time is treat at pct_eff > 0 (which
# lever-flags.sh gives only to a live lever with a fresh guard heartbeat and no un-acked trip, so at
# S0 / pct 0 nothing here can act), every guard holds, and the gap's ONE wake is still unspent. The
# wake is claimed with O_EXCL on <state>/wakes/<sid>.<gap start> (gap_key), shared by D1 and D3, so a second
# wake in one gap is impossible from any process (never tunable, plan §3). The kill switches are
# re-checked here although lf_arm already lowered the arm for them: they must win on every path.
KILL = {
    "D1": ("CC_IDLE_KEEPALIVE", "CC_IRS"),
    "D3": ("CC_IDLE_KEEPALIVE",),
}


def lever_off(lever):
    if any(os.environ.get(v, "") == "off" for v in KILL.get(lever, ())):
        return True
    return any(
        os.environ.get(v, "") in ("off", "control")
        for v in ("CC_LEVER_ALL", "CC_LEVER_" + lever)
    )


def verdict(lever, a, guards):
    """→ (act, why_not): the arm and kill switches first, then each (name, holds) guard in order."""
    if lever_off(lever):
        return False, "kill-switch"
    if a.get("arm") != "treat":
        return False, "arm-%s" % (a.get("arm") or "none")
    pe = a.get("pct_eff")
    if isinstance(pe, bool) or not isinstance(pe, (int, float)) or pe <= 0:
        return False, "pct0"
    for name, holds in guards:
        if holds is not True:
            return False, name
    return True, None


def gap_key(st, launch):
    """The gap's identity for its one wake: the gap state's own start (the Stop that opened it, the
    same for every timer of that gap) when the state is this gap's, else the timer's launch."""
    s = st.get("start")
    return (
        s
        if isinstance(s, (int, float)) and abs(s - float(launch)) <= 300
        else float(launch)
    )


def claim_wake(sid, key):
    """True once per (sid, gap): the gap's one wake, for whichever lever takes it first."""
    p = os.path.join(STATE_DIR, "wakes", "%s.%d" % (sid, int(float(key))))
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        os.close(os.open(p, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
    except OSError:
        return False
    lo = (
        time.time() - 2 * 86400
    )  # the markers of gaps two days gone can never be claimed again
    try:
        for e in os.scandir(os.path.dirname(p)):
            if e.stat().st_mtime < lo:
                os.unlink(e.path)
    except OSError:
        pass
    return True


def cmd_would_wake(sid, launch, watcher, n, arm_json="", headless="false"):
    if not SID_RX.match(sid):
        return
    t = now()
    st = load_state(sid) or {}
    ctx = int(st.get("ctx") or 0)
    wk = sorted(round(wake_cost(ctx, r), 6) for r in READ_PP)
    a = parse_arm(arm_json)
    jobs, tx_hl = jobs_at_wake(st.get("transcript"), t, float(launch))
    eligible = (
        bool(jobs["busy"]) and not jobs.get("watcher_fires_before_ttl")
        if "busy" in jobs
        else None
    )
    hl = headless == "true" or tx_hl is True
    # D3: busy-scoped with watcher skip, never headless, one wake per gap (claimed last)
    fire, why_not = verdict(
        "D3",
        a,
        [
            ("busy", jobs.get("busy")),
            ("watcher-fires", eligible),
            ("headless", not hl),
        ],
    )
    if fire and not claim_wake(sid, gap_key(st, launch)):
        fire, why_not = False, "wake-spent"
    row = dict(
        kind="wake",
        v=3,
        ts=iso(t),
        sid=sid,
        acct=st.get("acct") or acct(),
        n=int(n),
        gap_start=iso(float(launch)),
        late_s=round(t - (float(launch) + int(n) * WAKE_S), 1),
        ctx=ctx,
        model=st.get("model"),
        watcher_armed={"true": True, "false": False}.get(watcher),
        wake_pp=wk,
        mode="live" if fire else "shadow",
        lever="D3",
        arm=a.get("arm"),
        variant=a.get("variant"),
        unit_id=a.get("unit"),
        flag_src=a.get("flag_src"),
        u=a.get("u"),
        pct_eff=a.get("pct_eff"),
        headless=hl,
        eligible=eligible,
        fired=fire,  # the hook wakes (exit 2) only on the "wake" this prints, after the row is written
        why_not=why_not,
    )
    row.update(jobs)
    append(row)
    # Keep the decision on this gap's state for its gap row, only while the state is still this
    # gap's (a Stop since the timer launched would have opened a newer one).
    if (
        isinstance(st.get("start"), (int, float))
        and abs(st["start"] - float(launch)) <= 300
    ):
        st["wake"] = dict(
            {k: row.get(k) for k in WAKE_FIELDS}, n=int(n), at=t, fired=fire
        )
        save_state(sid, st)
    if fire:
        sys.stdout.write("wake\n")


def _brief_lib():
    """scripts/lib/idle_recycle_brief.py beside this file's REAL path (wave S9's production brief)."""
    import importlib.util

    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    sys.path.insert(
        0, os.path.dirname(os.path.realpath(__file__))
    )  # its `import session_jobs`
    p = os.path.join(root, "scripts", "lib", "idle_recycle_brief.py")
    spec = importlib.util.spec_from_file_location("idle_recycle_brief", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _capped(row, drop):
    """The row as one ≤ 2 KB line, dropping the `drop` keys in order until it fits; None if it never does."""
    for k in [None] + list(drop):
        if k:
            row.pop(k, None)
        s = json.dumps(row, separators=(",", ":"))
        if len(s.encode()) <= 2047:
            return row
    return None


def cmd_d1_due(sid, launch, arm_json, lineage_src, k, n_min, headless="false"):
    """D1 at its due time (n_min idle minutes into the gap, context >= k thousand): one kind=would_recycle
    row with the IRS v2 field names in BOTH arms; in treatment, with G1 (nothing busy, by the launching
    tool) and G4 (no pending question) holding and the gap's wake unspent, also the brief (G3/G5, S9's
    idle_recycle_brief.py), the kind=d1_recycle row of the S6b contract, and the treated D1 event in
    the IRS log with turn_start = the due time (lever_chain.py scores it), then prints
    "recycle<TAB>brief path<TAB>recycle_id" for the hook to fire handoff-fire.sh --recycle with."""
    if not SID_RX.match(sid):
        return
    launch, k, n = float(launch), int(k), int(n_min)
    st = load_state(sid) or {}
    if not isinstance(st.get("start"), (int, float)) or abs(st["start"] - launch) > 300:
        return  # not this gap's state: a Stop since launch opened a newer one
    ctx = int(st.get("ctx") or 0)
    if ctx < k * 1000:
        return
    t = now()
    tp = st.get("transcript")
    sj = _session_jobs()
    recs = sj.records(tp, TAIL_BYTES) if tp else []
    idle = [
        _ts(r)
        for r in recs
        if r.get("type") == "assistant" and (_ts(r) or 0) <= launch + 1
    ]
    idle_start = max([x for x in idle if x is not None] or [launch])
    gap_s = int(t - idle_start)
    run = sj.running_at(sj.jobs(recs), t) if recs else {}
    pq, why = sj.pending_question(recs, idle_start) if recs else (None, None)
    eps = [r.get("entrypoint") for r in recs if isinstance(r.get("entrypoint"), str)]
    hl = headless == "true" or "sdk-cli" in eps
    a = parse_arm(arm_json, "D1")
    k1 = int(os.environ.get("CC_IRS_K", "150") or 150)
    would = gap_s >= n * 60 and ctx >= k1 * 1000
    would_k2 = gap_s >= n * 60 and ctx >= k * 1000
    ok = None if not recs else (run.get("busy") is False and pq is False)
    irs = dict(
        schema=2,
        v="ok",
        sid=sid,
        config_dir=os.environ.get("CLAUDE_CONFIG_DIR") or "",
        k_thousand=k1,
        n_min=n,
        k2_thousand=k,
        idle_start=int(idle_start),
        turn_start=int(t),
        gap_s=gap_s,
        ctx_at_idle=ctx,
        would_advise=would,
        would_advise_k2=would_k2,
        prompt_head=None,  # the prompt that ENDS this gap has not arrived: the timer cannot know it
        prompt_sha=None,
        busy_tool=run.get("busy"),
        busy_kinds=run.get("busy_kinds"),
        busy_oldest_s=run.get("busy_oldest_s"),
        watcher_running=run.get("watcher_running"),
        pending_question=pq,
        pq_why=why,
        guarded=None if ok is None else would and ok,
        guarded_k2=None if ok is None else would_k2 and ok,
        lever="D1",
        arm=a.get("arm"),
        variant=a.get("variant"),
        lineage=a.get("unit") or sid,
        lineage_src=lineage_src or None,
        d1={
            k_: v
            for k_, v in a.items()
            if k_ not in ("lever", "decision", "unit", "arm", "variant")
        },
    )
    fire, why_not = verdict(
        "D1",
        a,
        [
            ("unreadable", bool(recs) or None),
            ("not-due", would_k2),
            ("busy", run.get("busy") is False),
            ("pending-question", pq is False),
            ("headless", not hl),
        ],
    )
    brief = meta = None
    if fire:
        try:
            brief, meta = _brief_lib().build(dict(irs, transcript=tp), recs, None, tp)
        except Exception as e:  # no brief, no recycle: G3/G5 travel only through it
            fire, why_not = False, "brief-error:%s" % type(e).__name__
    if fire and not claim_wake(sid, gap_key(st, launch)):
        fire, why_not = False, "wake-spent"
    rid = "%s-%d-%s" % (sid[:8], int(t), os.urandom(4).hex()) if fire else None
    path = None
    if fire:
        path = os.path.join(STATE_DIR, "d1-briefs", rid + ".md")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write(brief)
    row = _capped(
        dict(
            irs,
            kind="would_recycle",
            ts=iso(t),
            acct=st.get("acct") or acct(),
            gap_start=iso(launch),
            headless=hl,
            fired=fire,
            why_not=why_not,
            recycle_id=rid,
        ),
        ("busy_kinds", "d1"),
    )
    if row:
        append(row)
    if not fire:
        return
    rec = _capped(
        dict(
            kind="d1_recycle",
            v=1,
            ts=iso(t),
            sid=sid,
            acct=st.get("acct") or acct(),
            lineage=irs["lineage"],
            gap_start=iso(launch),
            recycle_id=rid,
            fired=True,
            arm=a,
            busy=run.get("busy"),
            pending_question=pq,
            g1_kill=run.get("busy") is True,
            g4_violation=pq is True,
            headless=hl,
            idle_start=irs["idle_start"],
            turn_start=irs["turn_start"],
            gap_s=gap_s,
            ctx_at_idle=ctx,
            brief=path,
            brief_meta={
                x: (meta or {}).get(x) for x in ("n_questions", "n_steps", "n_watchers")
            },
        ),
        ("brief_meta", "brief"),
    )
    if rec is None:
        return  # the contract row could not be written: no recycle without it
    append(rec)
    ev = _capped(
        dict(
            irs,
            ts=int(t),
            ts_z=iso(t),
            src="idle-keepalive",
            fired=True,
            recycle_id=rid,
        ),
        ("busy_kinds",),
    )
    irs_log = os.environ.get("CC_IRS_LOG") or os.path.join(
        HOME, ".claude/logs/idle-recycle-shadow.jsonl"
    )
    try:
        os.makedirs(os.path.dirname(irs_log), exist_ok=True)
        with open(irs_log, "a") as fh:
            fh.write(json.dumps(ev, separators=(",", ":")) + "\n")
    except (OSError, TypeError):
        pass
    sys.stdout.write("recycle\t%s\t%s\n" % (path, rid))


def main(argv):
    signal.signal(signal.SIGALRM, lambda *_: os._exit(0))
    # d1-due reads the whole tail and builds a brief, so it gets a longer bound; a timeout drops its
    # rows and its recycle together (it prints nothing until both rows are written)
    dflt = "30" if argv[:1] == ["d1-due"] else "4"
    signal.alarm(int(os.environ.get("CC_IDLE_GAP_BOUND_S", dflt) or dflt))
    try:
        if argv[:1] == ["stop"]:
            try:
                payload = json.loads(sys.stdin.read() or "{}")
            except ValueError:
                return 0
            if isinstance(payload, dict):
                cmd_stop(payload)
        elif argv[:1] == ["would-wake"] and len(argv) in (5, 6, 7):
            cmd_would_wake(*argv[1:])
        elif argv[:1] == ["d1-due"] and len(argv) in (7, 8):
            cmd_d1_due(*argv[1:])
        else:
            sys.stderr.write(
                "usage: idle_gap.py stop < payload"
                " | would-wake <sid> <launch> <watcher> <n> [<arm json> [<headless>]]"
                " | d1-due <sid> <launch> <arm json> <lineage src> <k> <n_min> [<headless>]\n"
            )
            return 2
    except Exception as e:  # fail-open: a hook must never die on its ledger
        sys.stderr.write("idle_gap: %s\n" % e)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
