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
              at that moment. Writes kind=wake rows. It never wakes. Since W6 the row also says
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
    """Busy and watcher state at the wake moment; {} when the transcript cannot be read."""
    if not transcript:
        return {}
    try:
        sj = _session_jobs()
        return sj.running_at(
            sj.jobs(sj.records(transcript, TAIL_BYTES)), t, ttl_end=gap_start + TTL_S
        )
    except Exception:
        return {}


def parse_arm(s):
    """The timer's lf_arm_json object (hooks/lib/lever-flags.sh), or {} when absent or malformed."""
    try:
        a = json.loads(s) if s else {}
    except ValueError:
        return {}
    return a if isinstance(a, dict) and a.get("lever") == "D3" else {}


def cmd_would_wake(sid, launch, watcher, n, arm_json=""):
    if not SID_RX.match(sid):
        return
    t = now()
    st = load_state(sid) or {}
    ctx = int(st.get("ctx") or 0)
    wk = sorted(round(wake_cost(ctx, r), 6) for r in READ_PP)
    a = parse_arm(arm_json)
    jobs = jobs_at_wake(st.get("transcript"), t, float(launch))
    eligible = (
        bool(jobs["busy"]) and not jobs.get("watcher_fires_before_ttl")
        if "busy" in jobs
        else None
    )
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
        mode="shadow",
        lever="D3",
        arm=a.get("arm"),
        variant=a.get("variant"),
        unit_id=a.get("unit"),
        flag_src=a.get("flag_src"),
        u=a.get("u"),
        eligible=eligible,
        fired=False,  # no branch here wakes anything; the treatment wake is wave S12's
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
            {k: row.get(k) for k in WAKE_FIELDS}, n=int(n), at=t, fired=False
        )
        save_state(sid, st)


def main(argv):
    signal.signal(signal.SIGALRM, lambda *_: os._exit(0))
    signal.alarm(int(os.environ.get("CC_IDLE_GAP_BOUND_S", "4") or 4))
    try:
        if argv[:1] == ["stop"]:
            try:
                payload = json.loads(sys.stdin.read() or "{}")
            except ValueError:
                return 0
            if isinstance(payload, dict):
                cmd_stop(payload)
        elif argv[:1] == ["would-wake"] and len(argv) in (5, 6):
            cmd_would_wake(*argv[1:])
        else:
            sys.stderr.write(
                "usage: idle_gap.py stop < payload"
                " | would-wake <sid> <launch> <watcher> <n> [<arm json>]\n"
            )
            return 2
    except Exception as e:  # fail-open: a hook must never die on its ledger
        sys.stderr.write("idle_gap: %s\n" % e)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
