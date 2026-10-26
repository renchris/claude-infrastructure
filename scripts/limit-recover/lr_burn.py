#!/usr/bin/env python3
"""lr_burn.py — the per-session burn meter (account rotation, component C2).

Design: docs/research/account-rotation-100p-2026-10-24/REPORT.md § C2; plan
docs/plans/ZERO_HITL_ROTATION.md wave B. Read-only: it moves nothing, starts nothing and writes only
its own offsets file.

WHAT IT ANSWERS. For each live Claude Code session, how many weekly-meter percentage points per hour
(b_wk) and 5-hour-meter points per hour (b_5h) it is burning now. That is the quantity a rebalancer
actually moves when it moves the session; idleness is not (an idle session burns about nothing).

METHOD, one tick:
  1. Tail every transcript written inside the window under each account's projects root: the main
     `<root>/<slug>/<sid>.jsonl` and everything below `<root>/<slug>/<sid>/` (subagents and
     Workflow agents), all attributed to <sid>. Offsets persist in <LR_STATE_DIR>/shed/burn.json, so a tick reads only new
     bytes, and at most BYTE_CAP per file. `*.jsonl.handed-off` transplant copies are never read.
  2. Dedupe billed responses on `message.id` (then `requestId`): the first record fixes the
     timestamp and input classes, output is the MAX over the message's records — the
     bin/cc-quota-price contract (the first streamed record carries a 1-10 token placeholder).
  3. Price each response in weekly pp with the hooks/lib/idle_gap.py weights: cache writes and
     uncached input at WRITE_PP, output at OUT_PP, cache reads at the midpoint of READ_PP.
  4. An account's measured pace is the least-squares slope of weekly_pct (session_pct for the
     5-hour meter) over the window in ~/.claude/logs/account-utilization.jsonl, stale rows dropped,
     same reset as the newest row only. A slope over the ~9 polls of an hour, not an endpoint
     delta: the meter logs integers, and an endpoint delta of a 1 pp/h staircase reads 0, 1 or 2.
  5. b_wk(session) = pace_wk × priced(session) / priced(account), and b_5h likewise. The absolute
     price only apportions; the account's own meter sets the scale. Over ALL the account's sessions
     (live or not) the shares therefore sum to the pace by construction.

THE ACCEPTANCE CHECK (`--replay END`): because of 5, "the shares sum to the pace" is an identity
inside one tick and proves nothing. The replay instead divides by an INDEPENDENT census — bin/
cc-quota-price's L1 walk, a one-shot full read with its own dedup — so the 10% bound measures what
this meter could get wrong: byte-capped incremental reads, offsets, dedup across ticks, subagent
attribution and the handed-off drop. It prints the absolute calibration (census pp/h ÷ pace) beside
it as information only; the weights are the round-2 fit, not something this module re-fits.

PUBLIC API (wave W8 extends this module; keep it small):
  price(inp, out, cc, cr) -> float          weekly pp of one billed response
  load_state(path) / save_state(path, st)   the offsets + in-window message store
  tick(st, now, roots=None, ...) -> int     read new bytes; returns bytes still unread (lag)
  paces(now, window_s, util_path) -> {acct: {"wk", "5h", "n", "why"}}
  live_sessions(roots=None) -> {sid: {"pid", "acct", "status"}}
  burn_rows(st, now, live, pace_by_acct, window_s) -> [row]
  measure(now=None, ...) -> [row]           load, tick, rows, save — the one-call entry point
  replay(t_end, ...) -> dict                the acceptance check above
Row: {sid, acct, b_wk, b_5h, last_stop_t, operator_t, ctx, pid, pp_60m, share, partial}
  b_wk / b_5h are None when the account's pace could not be measured (never a guessed 0).
  last_stop_t  epoch of the last main-chain assistant turn that ended (stop_reason not tool_use)
  operator_t   epoch of the last main-chain prompt a person typed (not a tool result, not a
               <task-notification> / <system-reminder> injection)
  ctx          input + cache tokens of the last main-chain response (the context it carries)
  partial      True when the window may be under-read: a first sight started mid-file, a line was
               skipped as over-cap, or bytes are still unread.

LIVENESS WITHOUT ps: <config>/sessions/<pid>.json plus kill -0 (45 ms measured, REPORT R13). The
pane join (`kitten @ ls`) belongs to the caller's census (wave W1) and is not repeated here.

KNOWN LIMITS, stated rather than hidden: one weight set prices every model (a Haiku subagent is
over-priced relative to Opus); a session moved inside the window has its copied pre-move records
billed to the new account for up to one window.

Python 3.9-safe, stdlib only. Exit: 0 ok · 2 usage · 3 replay FAIL or no verdict.
"""

import argparse
import glob
import importlib.machinery
import importlib.util
import json
import os
import sys
import time
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, "hooks", "lib"))
import idle_gap  # noqa: E402  the weight SSOT; a missing import must fail loud, never fall back

HOME = os.path.expanduser("~")
STATE_DIR = os.environ.get("LR_STATE_DIR") or os.path.join(
    HOME, ".reso", "limit-recover"
)
STATE_PATH = os.path.join(STATE_DIR, "shed", "burn.json")
UTIL_PATH = os.environ.get("CC_UTIL_LOG") or os.path.join(
    HOME, ".claude", "logs", "account-utilization.jsonl"
)
WINDOW_S = 3600
BYTE_CAP = 8 << 20
RESET_TOLERANCE_S = (
    300  # same as bin/cc-quota-price: the endpoint jitters reset stamps sub-second
)
NOTIFICATION_PREFIXES = ("<task-notification>", "<system-reminder>")
STATE_V = 1

# The four real config dirs (bin/cc-quota-price DEFAULT_ROOTS). LR_BURN_ROOTS overrides with
# "path=acct" entries separated by ':' or newlines.
DEFAULT_ROOTS = [
    (os.path.join(HOME, ".claude", "projects"), "next"),
    (os.path.join(HOME, ".claude-secondary", "projects"), "next2"),
    (os.path.join(HOME, ".claude-tertiary", "projects"), "next3"),
    (os.path.join(HOME, ".claude-quaternary", "projects"), "next4"),
]

W_WRITE = idle_gap.WRITE_PP / 1e6
W_OUT = idle_gap.OUT_PP / 1e6
W_READ = (idle_gap.READ_PP[0] + idle_gap.READ_PP[1]) / 2 / 1e6


def price(inp, out, cc, cr):
    """Weekly pp of one billed response (token counts)."""
    return (inp + cc) * W_WRITE + out * W_OUT + cr * W_READ


def roots():
    raw = os.environ.get("LR_BURN_ROOTS")
    if not raw:
        return [(d, a) for d, a in DEFAULT_ROOTS if os.path.isdir(d)]
    out = []
    for part in raw.replace(":", "\n").split("\n"):
        if "=" in part:
            d, a = part.strip().split("=", 1)
            out.append((os.path.expanduser(d), a))
    return out


def iso_to_epoch(s):
    if not isinstance(s, str) or not s:
        return None
    try:
        d = datetime.fromisoformat(s.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.timestamp()


# ── state ────────────────────────────────────────────────────────────────────────────────────────
def new_state():
    # files: path -> {off, ino, sid, acct, main, skip, gap_t}
    # msgs:  key -> [ts, sid, acct, inp, out, cc, cr]   (in-window billed responses, deduped)
    # sess:  sid -> {last_stop_t, operator_t, ctx}
    return {"v": STATE_V, "files": {}, "msgs": {}, "sess": {}}


def load_state(path):
    try:
        with open(path) as fh:
            st = json.load(fh)
        if isinstance(st, dict) and st.get("v") == STATE_V:
            return st
    except (OSError, ValueError):
        pass
    return new_state()


def save_state(path, st):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.%d.tmp" % (path, os.getpid())
    with open(tmp, "w") as fh:
        json.dump(st, fh, separators=(",", ":"))
    os.replace(tmp, path)


# ── L1: incremental tail ─────────────────────────────────────────────────────────────────────────
def _discover(rts, floor):
    """[(path, sid, acct, is_main, stat)] for transcripts written at or after `floor`."""
    out = []
    for root, acct in rts:
        for f in glob.glob(os.path.join(root, "*", "*.jsonl")):
            out.append((f, os.path.basename(f)[:-6], acct, True))
        # everything below <slug>/<sid>/ is that session's: subagents/*.jsonl, and Workflow agents
        # one level deeper at subagents/workflows/<wf>/agent-*.jsonl (a replayed hour missed 12%
        # of next3's burn when only the first level was walked)
        pat = os.path.join(root, "*", "*", "**", "*.jsonl")
        for f in glob.glob(pat, recursive=True):
            rel = os.path.relpath(f, root).split(os.sep)
            out.append((f, rel[1], acct, False))
    seen, res = set(), []
    for f, sid, acct, main in out:
        try:
            rp = os.path.realpath(f)
            s = os.stat(rp)
        except OSError:
            continue
        if rp in seen or s.st_mtime < floor:
            continue
        seen.add(rp)
        res.append((rp, sid, acct, main, s))
    return res


def _dedup_key(m, d):
    return m.get("id") or d.get("requestId")


def _operator_prompt(d):
    if d.get("isMeta") or d.get("isSidechain"):
        return False
    c = (d.get("message") or {}).get("content")
    if isinstance(c, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
            return False
        c = "".join(
            b.get("text", "")
            for b in c
            if isinstance(b, dict) and b.get("type") == "text"
        )
    return (
        isinstance(c, str)
        and bool(c.strip())
        and not c.lstrip().startswith(NOTIFICATION_PREFIXES)
    )


def _ingest(st, line, fe, now, fname):
    if b'"usage"' not in line and b'"user"' not in line:
        return
    try:
        d = json.loads(line)
    except (ValueError, UnicodeDecodeError):
        return
    ts = iso_to_epoch(d.get("timestamp"))
    m = d.get("message")
    if ts is None or not isinstance(m, dict):
        return
    sid = fe["sid"]
    if d.get("type") == "user":
        if fe["main"] and ts <= now and _operator_prompt(d):
            s = st["sess"].setdefault(sid, {})
            s["operator_t"] = max(ts, s.get("operator_t") or 0)
        return
    u = m.get("usage")
    if not isinstance(u, dict):
        return
    inp, out = int(u.get("input_tokens") or 0), int(u.get("output_tokens") or 0)
    cc, cr = (
        int(u.get("cache_creation_input_tokens") or 0),
        int(u.get("cache_read_input_tokens") or 0),
    )
    key = _dedup_key(m, d) or "%s#%d" % (fname, fe["off"])
    have = st["msgs"].get(key)
    if have is not None:
        have[4] = max(have[4], out)
        return
    if ts > now:
        return
    st["msgs"][key] = [ts, sid, fe["acct"], inp, out, cc, cr]
    if fe["main"] and not d.get("isSidechain"):
        s = st["sess"].setdefault(sid, {})
        if ts >= (s.get("ctx_t") or 0):
            s["ctx_t"], s["ctx"] = ts, inp + cc + cr
        if m.get("stop_reason") not in (None, "tool_use"):
            s["last_stop_t"] = max(ts, s.get("last_stop_t") or 0)


def tick(st, now, rts=None, window_s=WINDOW_S, byte_cap=BYTE_CAP, first_tail=BYTE_CAP):
    """Read new bytes of every in-window transcript; return the bytes still unread (lag).

    first_tail: on a file's first sight, start this many bytes before its end (None = from 0).
    """
    floor = now - window_s
    live = set()
    for path, sid, acct, main, s in _discover(
        rts if rts is not None else roots(), floor
    ):
        live.add(path)
        fe = st["files"].get(path)
        if fe is None or fe.get("ino") != s.st_ino or s.st_size < fe["off"]:
            start = 0 if first_tail is None else max(0, s.st_size - first_tail)
            fe = {
                "off": start,
                "ino": s.st_ino,
                "sid": sid,
                "acct": acct,
                "main": main,
                "skip": start > 0,
                "gap_t": None,
                "gap_open": start > 0,
            }
            st["files"][path] = fe
        if fe["off"] >= s.st_size:
            fe["lag"] = 0
            continue
        try:
            with open(path, "rb") as fh:
                fh.seek(fe["off"])
                buf = fh.read(byte_cap)
        except OSError:
            continue
        pos = 0
        # discard up to the next newline: the tail of a line we did not start on
        if fe["skip"]:
            nl = buf.find(b"\n")
            if nl < 0:
                fe["off"] += len(buf)
                fe["lag"] = max(0, s.st_size - fe["off"])
                continue
            pos, fe["skip"] = nl + 1, False
            fe["off"] += pos  # the loop below advances off by whole lines only
        end = buf.rfind(b"\n")
        # one line longer than the cap: skip it, and say so through gap_t
        if end < pos and len(buf) == byte_cap:
            fe["off"] += len(buf)
            fe["skip"], fe["gap_open"] = True, True
            fe["lag"] = max(0, s.st_size - fe["off"])
            continue
        while pos <= end:
            nl = buf.find(b"\n", pos)
            line = buf[pos:nl]
            if fe.get("gap_open") and b'"timestamp"' in line:
                # first record after a skipped region: anything in-window before it may be missed
                try:
                    fe["gap_t"] = iso_to_epoch(json.loads(line).get("timestamp"))
                    fe["gap_open"] = False
                except (ValueError, UnicodeDecodeError):
                    pass
            _ingest(st, line, fe, now, path)
            fe["off"] += nl + 1 - pos
            pos = nl + 1
        fe["lag"] = max(0, s.st_size - fe["off"])
    # prune: messages older than the window, files no longer written
    cut = floor - 300
    st["msgs"] = {k: v for k, v in st["msgs"].items() if v[0] >= cut}
    st["files"] = {p: fe for p, fe in st["files"].items() if p in live}
    return sum(fe.get("lag", 0) for fe in st["files"].values())


def priced(st, now, window_s=WINDOW_S):
    """{acct: {sid: pp}} over (now - window_s, now]."""
    out = {}
    for ts, sid, acct, inp, o, cc, cr in st["msgs"].values():
        if now - window_s < ts <= now:
            a = out.setdefault(acct, {})
            a[sid] = a.get(sid, 0.0) + price(inp, o, cc, cr)
    return out


# ── L2: the account's measured pace ──────────────────────────────────────────────────────────────
def _util_rows(path, since, until):
    """Non-stale utilization rows with since <= ts <= until, read backwards from the log's end."""
    rows, chunk = [], 1 << 20
    try:
        fh = open(path, "rb")
    except OSError:
        return rows
    with fh:
        fh.seek(0, 2)
        end = fh.tell()
        pos, carry = end, b""
        while pos > 0:
            n = min(chunk, pos)
            pos -= n
            fh.seek(pos)
            data = fh.read(n) + carry
            lines = data.split(b"\n")
            carry = lines.pop(0) if pos > 0 else b""
            oldest = None
            for ln in lines:
                try:
                    d = json.loads(ln)
                except (ValueError, UnicodeDecodeError):
                    continue
                ts = iso_to_epoch(d.get("ts"))
                if ts is None:
                    continue
                oldest = ts if oldest is None else min(oldest, ts)
                if since <= ts <= until and not d.get("stale") and d.get("acct"):
                    rows.append((ts, d))
            if oldest is not None and oldest < since:
                break
    rows.sort(key=lambda r: r[0])
    return rows


def _slope(pts):
    """Least-squares pp/h through [(epoch, pct)]."""
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    var = sum((p[0] - mx) ** 2 for p in pts)
    if var <= 0:
        return None
    return max(0.0, sum((p[0] - mx) * (p[1] - my) for p in pts) / var * 3600)


def _same(a, b):
    ea, eb = iso_to_epoch(a), iso_to_epoch(b)
    if ea is None or eb is None:
        return a == b
    return abs(ea - eb) <= RESET_TOLERANCE_S


def _pace_of(rows, pct_key, reset_key, window_s):
    rows = [r for r in rows if r.get(pct_key) is not None]
    if not rows:
        return None, "no rows"
    last = rows[-1].get(reset_key)
    pts = [(r["_ts"], float(r[pct_key])) for r in rows if _same(r.get(reset_key), last)]
    if len(pts) < 2 or pts[-1][0] - pts[0][0] < window_s / 3:
        return None, "span too short after reset" if len(pts) < len(
            rows
        ) else "span too short"
    return _slope(pts), "ok"


def paces(now, window_s=WINDOW_S, util_path=None):
    by = {}
    for ts, d in _util_rows(util_path or UTIL_PATH, now - window_s, now):
        d["_ts"] = ts
        by.setdefault(d["acct"], []).append(d)
    out = {}
    for acct, rows in by.items():
        wk, why = _pace_of(rows, "weekly_pct", "weekly_reset_at", window_s)
        h5, why5 = _pace_of(rows, "session_pct", "session_reset_at", window_s)
        out[acct] = {"wk": wk, "5h": h5, "n": len(rows), "why": why, "why_5h": why5}
    return out


# ── liveness and rows ────────────────────────────────────────────────────────────────────────────
def live_sessions(rts=None):
    out = {}
    for root, acct in rts if rts is not None else roots():
        for p in glob.glob(os.path.join(os.path.dirname(root), "sessions", "*.json")):
            try:
                with open(p) as fh:
                    d = json.load(fh)
                pid, sid = int(d["pid"]), d["sessionId"]
            except (OSError, ValueError, KeyError, TypeError):
                continue
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                continue
            except PermissionError:
                pass
            out[sid] = {"pid": pid, "acct": acct, "status": d.get("status")}
    return out


def burn_rows(st, now, live, pace_by_acct, window_s=WINDOW_S):
    pr = priced(st, now, window_s)
    gap = {}
    for fe in st["files"].values():
        missed = fe.get("gap_t") is not None and fe["gap_t"] > now - window_s
        if missed or fe.get("skip") or fe.get("lag"):
            gap[fe["sid"]] = True
    out = []
    for sid, info in sorted(live.items()):
        acct = info["acct"]
        a = pr.get(acct, {})
        tot = sum(a.values())
        pp = a.get(sid, 0.0)
        share = pp / tot if tot > 0 else 0.0
        pace = pace_by_acct.get(acct) or {}
        s = st["sess"].get(sid, {})
        out.append(
            {
                "sid": sid,
                "acct": acct,
                "pid": info.get("pid"),
                "b_wk": None
                if pace.get("wk") is None
                else round(pace["wk"] * share, 4),
                "b_5h": None
                if pace.get("5h") is None
                else round(pace["5h"] * share, 4),
                "last_stop_t": s.get("last_stop_t"),
                "operator_t": s.get("operator_t"),
                "ctx": s.get("ctx"),
                "pp_60m": round(pp, 4),
                "share": round(share, 4),
                "partial": bool(gap.get(sid)),
            }
        )
    return out


def measure(
    now=None,
    state_path=None,
    window_s=WINDOW_S,
    byte_cap=BYTE_CAP,
    util_path=None,
    save=True,
):
    now = time.time() if now is None else now
    path = state_path or STATE_PATH
    st = load_state(path)
    tick(st, now, None, window_s, byte_cap, byte_cap)
    rows = burn_rows(
        st, now, live_sessions(), paces(now, window_s, util_path), window_s
    )
    if save:
        save_state(path, st)
    return rows


# ── acceptance: the replayed hour ────────────────────────────────────────────────────────────────
def _census_pp(t0, t1, rts):
    """{acct: pp} over (t0, t1] from bin/cc-quota-price's L1 census — an independent reader."""
    qp = os.path.join(REPO, "bin", "cc-quota-price")
    loader = importlib.machinery.SourceFileLoader("cc_quota_price", qp)
    spec = importlib.util.spec_from_loader("cc_quota_price", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    old = os.environ.get("CC_QP_ROOTS")
    os.environ["CC_QP_ROOTS"] = "\n".join("%s=%s" % (d, a) for d, a in rts)
    try:
        recs, _meta = mod.census(since=t0)
    finally:
        if old is None:
            os.environ.pop("CC_QP_ROOTS", None)
        else:
            os.environ["CC_QP_ROOTS"] = old
    out = {}
    for r in recs:
        if t0 < r["ts"] <= t1:
            out[r["acct"]] = out.get(r["acct"], 0.0) + price(
                r["input"], r["output"], r["cache_creation"], r["cache_read"]
            )
    return out


def replay(
    t_end, window_s=WINDOW_S, byte_cap=BYTE_CAP, util_path=None, rts=None, tol=0.10
):
    """Replay (t_end - window_s, t_end] through the incremental meter, from a fresh state, in
    byte-capped ticks until caught up; compare the share sum against the independent census."""
    rts = rts if rts is not None else roots()
    st = new_state()
    ticks = 0
    while True:
        ticks += 1
        if tick(st, t_end, rts, window_s, byte_cap, None) == 0 or ticks >= 100000:
            break
    meter = priced(st, t_end, window_s)
    census = _census_pp(t_end - window_s, t_end, rts)
    pc = paces(t_end, window_s, util_path)
    accts = []
    for acct in sorted(set(meter) | set(census) | set(pc)):
        pace = (pc.get(acct) or {}).get("wk")
        m_pp = sum(meter.get(acct, {}).values())
        c_pp = census.get(acct, 0.0)
        row = {
            "acct": acct,
            "pace_wk": pace,
            "census_pp": round(c_pp, 4),
            "meter_pp": round(m_pp, 4),
            "sessions": len(meter.get(acct, {})),
            "verdict": "NO-VERDICT",
        }
        if pace and c_pp > 0:
            ssum = sum(pace * pp / c_pp for pp in meter.get(acct, {}).values())
            dev = abs(ssum - pace) / pace
            row.update(
                {
                    "sum_b_wk": round(ssum, 4),
                    "dev": round(dev, 4),
                    "calibration": round(c_pp / (pace * window_s / 3600), 3),
                    "verdict": "PASS" if dev <= tol else "FAIL",
                }
            )
            top = sorted(meter[acct].items(), key=lambda kv: -kv[1])[:5]
            row["top"] = [
                {"sid": s[:8], "b_wk": round(pace * pp / c_pp, 4)} for s, pp in top
            ]
        else:
            row["why"] = (
                "no billed responses" if c_pp <= 0
                else "pace unmeasured" if pace is None else "meter did not move")
        accts.append(row)
    verdicts = [a["verdict"] for a in accts if a["verdict"] != "NO-VERDICT"]
    overall = (
        "NO-VERDICT"
        if not verdicts
        else ("PASS" if all(v == "PASS" for v in verdicts) else "FAIL")
    )
    return {
        "t_end": t_end,
        "window_s": window_s,
        "ticks": ticks,
        "byte_cap": byte_cap,
        "tol": tol,
        "accounts": accts,
        "verdict": overall,
    }


def _fmt_t(t):
    return (
        "-"
        if not t
        else datetime.fromtimestamp(t, timezone.utc).strftime("%m-%dT%H:%MZ")
    )


def render_replay(r):
    lines = [
        "lr_burn replay (%s, %ds window], %d ticks at %d MiB cap, tolerance %d%%"
        % (
            _fmt_t(r["t_end"] - r["window_s"]),
            r["window_s"],
            r["ticks"],
            r["byte_cap"] >> 20,
            round(r["tol"] * 100),
        )
    ]
    lines.append(
        "%-6s %8s %9s %10s %10s %7s %6s  %s"
        % (
            "acct",
            "pace",
            "sum_b_wk",
            "census_pp",
            "meter_pp",
            "dev",
            "calib",
            "verdict",
        )
    )
    for a in r["accounts"]:
        lines.append(
            "%-6s %8s %9s %10.4f %10.4f %7s %6s  %s%s"
            % (
                a["acct"],
                "-" if a["pace_wk"] is None else "%.3f" % a["pace_wk"],
                "%.3f" % a["sum_b_wk"] if "sum_b_wk" in a else "-",
                a["census_pp"],
                a["meter_pp"],
                "%.1f%%" % (a["dev"] * 100) if "dev" in a else "-",
                "%.2f" % a["calibration"] if "calibration" in a else "-",
                a["verdict"],
                "" if "why" not in a else " (%s)" % a["why"],
            )
        )
        for t in a.get("top", []):
            lines.append("         %s  b_wk %.4f pp/h" % (t["sid"], t["b_wk"]))
    lines.append(
        "verdict=%s (pace in weekly pp/h; sum_b_wk = per-session shares of the "
        "independent census; calib = census pp/h / pace, information only)"
        % r["verdict"]
    )
    return "\n".join(lines)


def main(argv):
    ap = argparse.ArgumentParser(prog="lr_burn.py", description=__doc__.split("\n")[0])
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--now", type=float, help="epoch override")
    ap.add_argument("--window", type=int, default=WINDOW_S)
    ap.add_argument("--byte-cap", type=int, default=BYTE_CAP)
    ap.add_argument("--state", help="offsets file (default %s)" % STATE_PATH)
    ap.add_argument(
        "--no-save", action="store_true", help="read the state but do not write it"
    )
    ap.add_argument(
        "--replay", metavar="END", help="ISO end of the hour to replay (acceptance)"
    )
    a = ap.parse_args(argv)
    if a.replay:
        t = iso_to_epoch(a.replay)
        if t is None:
            ap.error("--replay wants an ISO timestamp")
        r = replay(t, a.window, a.byte_cap)
        print(json.dumps(r) if a.json else render_replay(r))
        return 0 if r["verdict"] == "PASS" else 3
    rows = measure(a.now, a.state, a.window, a.byte_cap, save=not a.no_save)
    if a.json:
        print(json.dumps(rows))
        return 0
    rows.sort(key=lambda r: -(r["b_wk"] or 0))
    print(
        "%-8s %-6s %8s %8s %8s %7s %-11s %-11s %s"
        % (
            "sid",
            "acct",
            "b_wk",
            "b_5h",
            "pp_60m",
            "ctx_k",
            "last_stop",
            "operator",
            "partial",
        )
    )
    for r in rows:
        print(
            "%-8s %-6s %8s %8s %8.3f %7s %-11s %-11s %s"
            % (
                r["sid"][:8],
                r["acct"],
                "-" if r["b_wk"] is None else "%.3f" % r["b_wk"],
                "-" if r["b_5h"] is None else "%.3f" % r["b_5h"],
                r["pp_60m"],
                "-" if r["ctx"] is None else r["ctx"] // 1000,
                _fmt_t(r["last_stop_t"]),
                _fmt_t(r["operator_t"]),
                "yes" if r["partial"] else "",
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
