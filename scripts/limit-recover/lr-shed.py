#!/usr/bin/python3
"""lr-shed.py — the LATE-BAND IDLE SHED (D2b, packet 76a584cc935b; LR_SUSTAINED_LOAD W16).

Before an account hits its weekly wall, its idle, healthy sessions (at rest >= 30 min, an empty
composer, not focused, no /goal, team or background job) may move to another account, so they are
not among the sessions the wall limits. SHIPPED SHADOW-ONLY: until the operator rules on the packet,
`shed/mode` reads `shadow` at most and every decision is logged, nothing moves.

Design: docs/research/lr-sustained-load-2026-10-20/impl/D2-warning-band-shedding.md §6.3, with the
correctness review (D1-D17) and the efficacy review (E1-E10) folded in. Plan:
docs/plans/LR_SUSTAINED_LOAD_IMPL.md § W16.

  lr-shed.py --tick            one pass (the reset poller's lrp_shed_kick starts it detached)
  lr-shed.py --report [--json] one line per band window: the shadow-review surface
  lr-shed.py --status          mode, why, breaker, lock holder

FILES (all under LR_STATE_DIR, default ~/.reso/limit-recover):
  shed/mode            the operator's: first token off|shadow|on. ABSENT = off (the kill switch:
                       `rm ~/.reso/limit-recover/shed/mode`, and the kick starts nothing at all)
  shed/breaker         written here on a casualty or a strand; while present, `on` acts as shadow
  shed/state.json      windows, cooldowns, paged keys (tmp, fsync, rename)
  shed/decisions.jsonl one row <= 1 KB per decision, a single write(); rotated at 4 MB to .1
  shed/run.lock        the single-flight lock: ONE writer, this process, O_EXCL with (pid, lstart)
                       (review D1: the kick writing the pid locked the controller out of itself)

WHAT IT NEVER DOES. It reads no load figure (no decision may wait for load, which sits at 15-40 per
core by design). Our own timeout is "unknown, retry next tick", never a verdict: an unknown band
neither opens nor closes a window. It queues nothing while any limited reconciler record is open
(review E1: a queue gate, not a load gate), and every shed batch takes one move slot at most.

Seams (tests): LR_SHED_CA_BIN, LR_SHED_CCLR_BIN, LR_SHED_PAGE_BIN, CC_UTIL_LOG, LR_SHED_NOW, and
LR_SHED_{BAND,PLAN,PLACE,MOVE}_TO / LR_SHED_TICK_BUDGET_S for the bounds.
"""

import calendar
import json
import math
import os
import signal
import subprocess
import sys
import tempfile
import time

HOME = os.path.expanduser("~")
STATE = os.environ.get("LR_STATE_DIR") or os.path.join(HOME, ".reso", "limit-recover")
SHED = os.path.join(STATE, "shed")
RECON = os.environ.get("LR_RECON_ROOT") or os.path.join(STATE, "recon")
MOVE = os.path.join(STATE, "move")
HERE = os.path.dirname(os.path.realpath(__file__))


def env_int(name, default, lo=0, hi=None):
    """A knob from the environment. Malformed or out of range = the default (review D12: a typo
    must fail toward doing less, never toward a wider shed)."""
    raw = os.environ.get(name, "")
    try:
        v = int(raw)
    except ValueError:
        return default
    if v < lo or (hi is not None and v > hi):
        return default
    return v


Q_S = env_int(
    "LR_SHED_IDLE_S", 1800, 1800
)  # at rest at least this long; never below 30 min
MAX_PER_TICK = env_int(
    "LR_SHED_MAX", 4, 1, 4
)  # per source account per tick; never above 4
COOLDOWN_S = env_int(
    "LR_SHED_COOLDOWN_S", 21600, 0
)  # a sid MOVED by a shed is not re-shed for 6 h
TRIP_CONFIRM_S = 300  # the TTW arm only: two looks >= 5 min apart open (the level arm opens at once, E2)
RELEASE_CONFIRM_S = 1200  # two looks >= 20 min apart close (release is not !trip)
# PER-ARM BOUNDS (review D14). Measured on the W16 build, 2026-10-21 ~11:40Z, at priority 31 and
# load1 86-112 on 10 cores (9-11/core, BELOW the 15-40 premise): a cache-only --shed-band 0.2-0.4 s;
# `cc-lr plan --from next --json` (9 live rows) 17.8 s and 34.6 s; `cc-lr move --dry-run` of 2 rows
# 24.0 s. Each bound sits 7-12x above its reading to cover the premise's 3-4x higher load; the
# owed Tier-L T6 run re-reads them at 25 and 40/core (a queued batch in the `on` arm) and the shadow
# log records every arm's wall time, so a bound that starves shows up as `unknown` rows, not silence.
# Their sum for one account (60 + 240 + 120 + 300 = 720 s) stays under the tick budget, so the first
# banded account can always finish (the inner bound must stay under the pass bound). The budget is
# read on time.monotonic(), never on the LR_SHED_NOW seam (review D14/E6).
BAND_TO = env_int("LR_SHED_BAND_TO", 60, 1)
PLAN_TO = env_int("LR_SHED_PLAN_TO", 240, 1)
PLACE_TO = env_int("LR_SHED_PLACE_TO", 120, 1)
MOVE_TO = env_int("LR_SHED_MOVE_TO", 300, 1)
TICK_BUDGET_S = env_int("LR_SHED_TICK_BUDGET_S", 900, 1)
# A SHED BATCH IN FLIGHT HAS A BOUNDED RELEASE (review E3 and D3). Its runner's own WATCH bound is
# UNTIL (0) + slot wait 600 + prove 300 + 300 = 1200 s (lr-move-batch.sh), and an intent lives
# until_idle + 900 s, so a batch older than two intent lifetimes whose runner is gone is
# `settled:unknown` and releases its source. A runner still alive holds it, to a hard ceiling.
INFLIGHT_S = env_int("LR_SHED_INFLIGHT_S", 1800, 60)
INFLIGHT_HARD_S = env_int("LR_SHED_INFLIGHT_HARD_S", 3600, 60)
KEEP_S = 7 * 86400
LOG_MAX = 4 * 1024 * 1024
CASUALTY = ("STRANDED", "FAILED")
MOVED = ("MOVED", "MOVED-NEW-PANE", "MOVED-UNREGISTERED")
# Children never carry the invoking pane's identity (review D17): a manual --tick from a session
# would otherwise bind the batch's mail and its `self` handling to that pane (bin/cc-lr
# cl_this_pane, cl_requester_sid).
SCRUB = (
    "CLAUDE_CODE_SESSION_ID",
    "KITTY_WINDOW_ID",
    "CC_PANE_ID",
    "ITERM_SESSION_ID",
    "TMUX_PANE",
)
# The shed's own census and move environment (reviews D7, D8): a dead source would turn background
# jobs and /goal holds into moves, and a draft is never carried by a shed.
SHED_ENV = {
    "LR_DEAD_SOURCE_RELEASE": "off",
    "CC_LR_MOVE_GOAL_HOLD": "always",
    "LR_MOVE_CARRY_DRAFT": "off",
}


def now_s():
    raw = os.environ.get("LR_SHED_NOW", "")
    try:
        return float(raw)
    except ValueError:
        return time.time()


def read(p):
    try:
        with open(p, encoding="utf-8") as fh:
            return fh.read()
    except (OSError, UnicodeDecodeError):
        return ""


def load_json(p, default=None):
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def write_atomic(p, text):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    fd, tmp = tempfile.mkstemp(
        prefix=".%s." % os.path.basename(p), dir=os.path.dirname(p)
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.rename(tmp, p)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def log(**row):
    """One decision row, <= 1 KB, appended with a single write() (rotated at 4 MB to .1)."""
    row = dict({"ts": round(now_s(), 1)}, **row)
    line = json.dumps(row, sort_keys=True, separators=(",", ":"))
    if len(line) > 1000:
        for k in ("picks", "hist", "err", "cause", "excluded"):
            if k in row and len(line) > 1000:
                row[k] = str(row[k])[:120] + "…"
                line = json.dumps(row, sort_keys=True, separators=(",", ":"))
        line = line[:1000]
    p = os.path.join(SHED, "decisions.jsonl")
    try:
        os.makedirs(SHED, exist_ok=True)
        if os.path.getsize(p) > LOG_MAX:
            os.replace(p, p + ".1")
    except OSError:
        pass
    try:
        fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
        try:
            os.write(fd, (line + "\n").encode("utf-8"))
        finally:
            os.close(fd)
    except OSError:
        pass


# ── the mode ─────────────────────────────────────────────────────────────────────────────────────


def first_token(text):
    t = text.split()
    return t[0] if t else ""


def effective_mode():
    """(mode, why). A malformed mode file is OFF (D12); `on` acts as shadow while the breaker is
    present or the global zero-human marker is absent."""
    if os.environ.get("LR_SHED", "on") == "off":
        return "off", "env"
    mp = os.path.join(SHED, "mode")
    if not os.path.exists(mp):
        return "off", "no-mode-file"
    m = first_token(read(mp))
    if m not in ("off", "shadow", "on"):
        return "off", "bad-mode-file"
    if m == "on" and os.path.exists(os.path.join(SHED, "breaker")):
        return "shadow", "breaker"
    if m == "on" and not os.path.exists(os.path.join(STATE, "autorecover.on")):
        return "shadow", "zero-human"
    return m, ""


# ── processes ────────────────────────────────────────────────────────────────────────────────────


def child_env(extra=None):
    e = {k: v for k, v in os.environ.items() if k not in SCRUB}
    e.update(extra or {})
    return e


def run(argv, timeout, env=None):
    """(rc, stdout, stderr, wall_s). Its own session; on timeout the whole GROUP is killed and the
    answer is rc 124 — OUR bound firing: unknown, retry next tick, never a verdict."""
    t0 = time.monotonic()
    try:
        p = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env if env is not None else child_env(),
            start_new_session=True,
        )
    except OSError as e:
        return 126, "", str(e), round(time.monotonic() - t0, 1)
    try:
        out, err = p.communicate(timeout=timeout)
        rc = p.returncode
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            out, err = p.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            out, err = b"", b""
        rc = 124
    dec = lambda b: b.decode("utf-8", "replace") if isinstance(b, bytes) else (b or "")  # noqa: E731
    return rc, dec(out), dec(err), round(time.monotonic() - t0, 1)


def parse(text):
    try:
        v = json.loads(text)
    except ValueError:
        return None
    return v if isinstance(v, dict) else None


def ca_bin():
    return (
        os.environ.get("LR_SHED_CA_BIN")
        or os.environ.get("CC_ACCOUNTS_BIN")
        or os.path.join(HOME, "bin", "claude-accounts")
    )


def cclr_bin():
    if os.environ.get("LR_SHED_CCLR_BIN"):
        return os.environ["LR_SHED_CCLR_BIN"]
    sib = os.path.normpath(os.path.join(HERE, "..", "..", "bin", "cc-lr"))
    return sib if os.path.isfile(sib) else os.path.join(HOME, ".claude", "bin", "cc-lr")


def page_once(st, key, title, msg):
    """One page per key, ever: the controller remembers the key, and lr-page-once.sh latches it too."""
    if key in st["paged"]:
        return
    st["paged"][key] = now_s()
    pb = os.environ.get("LR_SHED_PAGE_BIN")
    argv = [pb] if pb else ["/bin/bash", os.path.join(HERE, "lr-page-once.sh")]
    rc, _o, err, _w = run(argv + [key, title, msg], 60)
    log(ev="page", key=key, rc=rc, err=err[-160:])


# ── the lock: one writer, O_EXCL, (pid, lstart) ──────────────────────────────────────────────────


def lstart(pid):
    """The pid's start time, normalised; "" = no such process; None = could not be read (a ps
    timeout is never "dead")."""
    try:
        cp = subprocess.run(
            ["/bin/ps", "-o", "lstart=", "-p", str(pid)],
            capture_output=True,
            text=True,
            timeout=20,
            env=dict(os.environ, TZ="UTC", LC_ALL="C"),
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    return " ".join(cp.stdout.split())


def alive(pid, ls):
    """True while pid runs AND is the same process (pid reuse wraps on this box in ~41 min)."""
    try:
        os.kill(int(pid), 0)
    except (OSError, ValueError):
        return False
    if not ls:
        return True
    cur = lstart(pid)
    return cur is None or cur == ls


LOCK = os.path.join(SHED, "run.lock")


def take_lock():
    os.makedirs(SHED, exist_ok=True)
    me = "%d %s" % (os.getpid(), lstart(os.getpid()) or "")
    for _ in range(2):
        try:
            fd = os.open(LOCK, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        except FileExistsError:
            held = read(LOCK).split(" ", 1)
            pid, ls = (held + ["", ""])[:2]
            if pid.isdigit() and (
                alive(pid, ls.strip()) or (not ls.strip() and _young(LOCK))
            ):
                return False
            # The holder is gone: rename, and keep the tomb only if it still names what was judged.
            tomb = "%s.stale.%d" % (LOCK, os.getpid())
            try:
                os.rename(LOCK, tomb)
            except OSError:
                return False
            if read(tomb).split(" ", 1)[0] != pid:
                if not os.path.exists(LOCK):
                    os.rename(tomb, LOCK)
                return False
            os.unlink(tomb)
            log(ev="lock-reaped", holder=pid)
            continue
        with os.fdopen(fd, "w") as fh:
            fh.write(me)
        return True
    return False


def _young(p):
    try:
        return time.time() - os.path.getmtime(p) < 60
    except OSError:
        return False


def release_lock():
    if read(LOCK).split(" ", 1)[0] == str(os.getpid()):
        try:
            os.unlink(LOCK)
        except OSError:
            pass


# ── state ────────────────────────────────────────────────────────────────────────────────────────


def load_state():
    st = load_json(os.path.join(SHED, "state.json"), {}) or {}
    st.setdefault("v", 1)
    for k in ("windows", "cooldown", "paged", "batches"):
        if not isinstance(st.get(k), dict):
            st[k] = {}
    return st


def save_state(st):
    write_atomic(
        os.path.join(SHED, "state.json"), json.dumps(st, sort_keys=True, indent=1)
    )


def iso_epoch(s):
    if not s:
        return None
    try:
        from datetime import datetime

        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError):
        return None


def window(st, a, now):
    """The band window keyed on the account and its minute-rounded weekly reset (review D5: a key
    built from the sweep-time countdown drifted every tick and the window never aged)."""
    rk = a.get("reset_key")
    if not isinstance(rk, int):
        return None
    key = "%s:%d" % (a["acct"], rk)
    w = st["windows"].get(key)
    if w is None:
        w = st["windows"][key] = {
            "acct": a["acct"],
            "reset_at": a.get("reset_at"),
            "reset_epoch": rk * 60,
            "open": False,
            "trip_at": None,
            "fail_at": None,
            "opened_at": None,
            "closed_at": None,
            "closed_by": None,
            "sheds": 0,
            "picks": 0,
            "unknown_n": 0,
            "looks": 0,
            "audited": False,
            "final_pct": None,
            "first_seen": now,
        }
    return w


def step_hysteresis(w, v, trip, now):
    """PURE. Our blindness neither opens nor closes. The LEVEL arm opens on its first look: the
    weekly level cannot fall inside a window, so a confirmation there only spends lead (review E2).
    The TTW arm flaps with the pace, so it needs two looks >= TRIP_CONFIRM_S apart. Release is NOT
    the negation of trip: two failing looks >= RELEASE_CONFIRM_S apart."""
    w["looks"] = w.get("looks", 0) + 1
    if v.startswith("unknown") or v == "off":
        w["unknown_n"] = w.get("unknown_n", 0) + 1
        return
    if not w["open"]:
        if v == "band":
            if trip == "level":
                w.update(
                    open=True,
                    opened_at=now,
                    trip_at=w.get("trip_at") or now,
                    fail_at=None,
                )
                return
            w["trip_at"] = w.get("trip_at") or now
            if now - w["trip_at"] >= TRIP_CONFIRM_S:
                w.update(open=True, opened_at=now, fail_at=None)
        else:
            w["trip_at"] = None
    else:
        if v in ("band-guard", "out", "hold-credits", "walled"):
            w["fail_at"] = w.get("fail_at") or now
            if now - w["fail_at"] >= RELEASE_CONFIRM_S:
                w.update(open=False, closed_at=now, closed_by=v, trip_at=None)
        else:
            w["fail_at"] = None


def select(rows, cooldown, pending, now):
    """PURE. A plain `move` row only (never a draft carry, never a wait), at rest >= Q_S, not MOVED
    by a shed inside COOLDOWN_S, not already queued in a shed batch. Cold cache first: free to move."""
    ok = [
        r
        for r in rows
        if isinstance(r, dict)
        and r.get("act") == "move"
        and r.get("disposition") == "move"
        and isinstance(r.get("idle_s"), int)
        and not isinstance(r.get("idle_s"), bool)
        and r["idle_s"] >= Q_S
        and r.get("sid")
        and now - cooldown.get(r["sid"], 0) >= COOLDOWN_S
        and r["sid"] not in pending
    ]
    ok.sort(key=lambda r: (r.get("cache") != "cold", -r["idle_s"]))
    return ok[:MAX_PER_TICK]


def histogram(rows):
    """Every pick row says what the census saw, so `0 picks` from a blind census (every row
    composer-unknown) cannot read as `no idle session` (review E7)."""
    h = {}
    for r in rows:
        d = str(r.get("disposition") or "-") if isinstance(r, dict) else "-"
        h[d] = h.get(d, 0) + 1
    return h


# ── shed batches, discovered from disk (review D3) ───────────────────────────────────────────────


def batch_ts(name):
    try:
        return float(calendar.timegm(time.strptime(name[:16], "%Y%m%dT%H%M%SZ")))
    except ValueError:
        return None


def shed_batches(now):
    """Every batch whose plan says origin=shed, from the move dir (not from what this controller
    remembers queueing: a bound firing between the request and the batch id loses that)."""
    out = []
    try:
        names = os.listdir(MOVE)
    except OSError:
        return out
    for n in sorted(names):
        t = batch_ts(n)
        if t is None or now - t > KEEP_S:
            continue
        bdir = os.path.join(MOVE, n)
        plan = load_json(os.path.join(bdir, "plan.json"))
        if not isinstance(plan, dict) or plan.get("origin") != "shed":
            continue
        sids = [
            r.get("sid")
            for r in plan.get("rows") or []
            if isinstance(r, dict) and r.get("act") in ("move", "wait") and r.get("sid")
        ]
        ts = plan.get("ts") if isinstance(plan.get("ts"), (int, float)) else t
        out.append(
            {
                "batch": n,
                "dir": bdir,
                "from": plan.get("from"),
                "to": plan.get("to"),
                "ts": ts,
                "sids": sids,
                "settled": os.path.isdir(os.path.join(bdir, "summary.settled")),
            }
        )
    return out


def verdicts(b):
    v = {}
    for s in b["sids"]:
        r = load_json(os.path.join(b["dir"], "%s.json" % s))
        if isinstance(r, dict) and r.get("verdict"):
            v[s] = (str(r["verdict"]), str(r.get("reason") or ""))
    return v


def runner_alive(b):
    pid = read(os.path.join(b["dir"], "runner", "pid")).strip()
    ls = " ".join(read(os.path.join(b["dir"], "runner", "lstart")).split())
    return pid.isdigit() and alive(pid, ls)


def inflight(b, now):
    """(in_flight, why). Settled means summary.settled/ exists (review D2: summary.json is written
    while members still run). Unsettled holds the source only within a bounded release (E3)."""
    if b["settled"]:
        return False, "settled"
    age = now - b["ts"]
    if age < INFLIGHT_S:
        return True, "young"
    if age < INFLIGHT_HARD_S and runner_alive(b):
        return True, "runner-alive"
    return False, "settled:unknown"


def breaker_scan(st, batches, now):
    """Read every shed batch's member verdicts. A casualty writes shed/breaker (on -> shadow), pages
    once, and aborts every unsettled shed batch (review D10). MOVED sets the cooldown; nothing else
    does (review D11/E5: a transient NOTMOVED leaves the sid re-pickable)."""
    bad = []
    for b in batches:
        for s, (v, why) in verdicts(b).items():
            if v in MOVED:
                st["cooldown"][s] = max(st["cooldown"].get(s, 0), b["ts"])
            elif v in CASUALTY:
                bad.append((b["batch"], s, v, why))
    if not bad:
        return False
    bp = os.path.join(SHED, "breaker")
    if not os.path.exists(bp):
        write_atomic(
            bp,
            json.dumps(
                {
                    "why": "casualty",
                    "casualties": [list(x[:3]) for x in bad[:8]],
                    "ts": now,
                }
            )
            + "\n",
        )
        log(
            ev="breaker",
            why="casualty",
            batch=bad[0][0],
            sid=bad[0][1][:8],
            verdict=bad[0][2],
        )
    for b in batches:
        if not b["settled"] and not os.path.exists(os.path.join(b["dir"], "abort")):
            try:
                open(os.path.join(b["dir"], "abort"), "a").close()
                log(ev="abort", batch=b["batch"], why="breaker")
            except OSError:
                pass
    for bt, s, v, why in bad:
        page_once(
            st,
            "shed-casualty-%s" % bt,
            "D2 shed casualty",
            "shed batch %s: %s %s (%s); the shed is now shadow-only. Read: cc-lr move --status %s. "
            "Clear: rm %s" % (bt, s[:8], v, why[:120], bt, bp),
        )
    return True


def ledger_level_before(acct, t_end, span_s=1800):
    """The last weekly level the utilization ledger recorded for `acct` within span_s before t_end,
    or None: no sample in the last 30 min before the reset is unknown, not a level (review E8)."""
    p = os.environ.get("CC_UTIL_LOG") or os.path.join(
        HOME, ".claude", "logs", "account-utilization.jsonl"
    )
    best = None
    try:
        with open(p, "rb") as fh:
            fh.seek(0, 2)
            size = fh.tell()
            fh.seek(max(0, size - 16 * 1024 * 1024))
            data = fh.read().decode("utf-8", "replace")
    except OSError:
        return None
    for ln in data.splitlines():
        if acct not in ln:
            continue
        try:
            u = json.loads(ln)
        except ValueError:
            continue
        if not isinstance(u, dict) or u.get("acct") != acct or u.get("stale") is True:
            continue
        t, pct = iso_epoch(u.get("ts")), u.get("weekly_pct")
        if (
            t is None
            or not isinstance(pct, (int, float))
            or not (t_end - span_s <= t < t_end)
        ):
            continue
        if best is None or t > best[0]:
            best = (t, float(pct))
    return None if best is None else best[1]


def strand_audit(st, now):
    """A window whose reset has passed: did the account still close its week at >= 99 % after
    shed moves? Below that, sheds may have stranded quota: trip the breaker and page. A window
    with no ledger sample in the last 30 min before its reset is unknown: no page, no breaker."""
    for key, w in st["windows"].items():
        if w.get("audited") or w.get("reset_epoch", now) > now - 600:
            continue
        final = ledger_level_before(w["acct"], w["reset_epoch"])
        w.update(audited=True, final_pct=final)
        if w.get("sheds", 0) <= 0:
            continue
        if final is None:
            log(
                ev="strand-audit",
                acct=w["acct"],
                window=key,
                verdict="unknown",
                sheds=w["sheds"],
            )
            continue
        log(
            ev="strand-audit",
            acct=w["acct"],
            window=key,
            final=final,
            sheds=w["sheds"],
            verdict="strand" if final < 99 else "ok",
        )
        if final < 99:
            if os.environ.get("LR_SHED_STRAND_BREAKER", "on") != "off":
                write_atomic(
                    os.path.join(SHED, "breaker"),
                    json.dumps(
                        {"why": "strand", "window": key, "final": final, "ts": now}
                    )
                    + "\n",
                )
            page_once(
                st,
                "shed-strand-%s" % key.replace(":", "-"),
                "D2 shed strand",
                "%s closed its week at %s%% after %d shed move(s); up to %.1f pp may have stranded. "
                "The shed is now shadow-only. Clear: rm %s"
                % (
                    w["acct"],
                    final,
                    w["sheds"],
                    100 - final,
                    os.path.join(SHED, "breaker"),
                ),
            )


def prune(st, now):
    for k in [
        k for k, w in st["windows"].items() if w.get("reset_epoch", now) < now - KEEP_S
    ]:
        del st["windows"][k]
    for k in [k for k, t in st["cooldown"].items() if now - t > max(COOLDOWN_S, 86400)]:
        del st["cooldown"][k]


def open_limited(now):
    """Open reconciler records of kind `limited` (no terminal). While any exists the shed queues
    nothing (review E1): the recovery cohort owns the boot slots. Unparseable files count as none."""
    n = 0
    d = os.path.join(RECON, "sessions")
    try:
        names = os.listdir(d)
    except OSError:
        return 0
    for f in names:
        if not f.endswith(".json"):
            continue
        r = load_json(os.path.join(d, f))
        if (
            isinstance(r, dict)
            and r.get("kind", "limited") == "limited"
            and not r.get("terminal")
        ):
            n += 1
    return n


# ── placement (review D17: not every pick onto targets[0]) ───────────────────────────────────────


def place(picks, src, held, kwork):
    """{sid: acct} from `claude-accounts --place` with idle movers, every banded or walled account
    (the source included) excluded. An unmeasured k_work places nothing there; a timeout places
    nothing (unknown, retry)."""
    tmp = tempfile.mkdtemp(prefix="lr-shed-place-")
    mf, kf, fd = (os.path.join(tmp, x) for x in ("movers.jsonl", "kwork.json", "facts"))
    try:
        os.mkdir(fd)
        with open(mf, "w") as fh:
            for p in picks:
                fh.write(
                    json.dumps({"sid": p["sid"], "src": src, "kind": "idle", "w": 1})
                    + "\n"
                )
        with open(kf, "w") as fh:
            json.dump(kwork, fh)
        facts = os.path.join(RECON, "facts")
        rc, out, err, wall = run(
            [
                ca_bin(),
                "--place",
                "--lane",
                "general",
                "--recovery",
                "--movers",
                mf,
                "--facts",
                facts if os.path.isdir(facts) else fd,
                "--kwork",
                kf,
                "--exclude",
                ",".join(sorted(held)),
                "--json",
                "--max-wait",
                "0",
            ],
            PLACE_TO,
        )
    finally:
        for p in (mf, kf):
            try:
                os.unlink(p)
            except OSError:
                pass
        for p in (fd, tmp):
            try:
                os.rmdir(p)
            except OSError:
                pass
    data = parse(out) if rc == 0 else None
    got = {}
    for p in picks:
        r = (data or {}).get(p["sid"])
        if (
            isinstance(r, dict)
            and r.get("acct")
            and r["acct"] != src
            and r["acct"] not in held
        ):
            got[p["sid"]] = r["acct"]
    return got, rc, wall, (err or "")[-160:]


# ── one tick ─────────────────────────────────────────────────────────────────────────────────────


def tick():
    t0 = time.monotonic()
    if not take_lock():
        return 0
    try:
        return _tick(t0)
    finally:
        release_lock()


def _tick(t0):
    mode, why = effective_mode()
    if mode == "off":
        return 0
    now = now_s()
    st = load_state()
    batches = shed_batches(now)
    # D2: the breaker reads first, so a failing band read can never also blind it.
    if breaker_scan(st, batches, now):
        mode, why = effective_mode()
    facts = os.path.join(RECON, "facts")
    rc, out, err, wall = run(
        [ca_bin(), "--shed-band", "--json", "--max-wait", "0"]
        + (["--facts", facts] if os.path.isdir(facts) else []),
        BAND_TO,
    )
    band = parse(out) if rc == 0 else None
    if (
        band is None
        or band.get("wait_data")
        or not isinstance(band.get("accounts"), list)
    ):
        log(
            ev="band",
            verdict="unknown",
            cause="rc=%s%s"
            % (rc, " wait-data" if band and band.get("wait_data") else ""),
            wall_s=wall,
            mode=mode,
            why=why,
            err=err[-160:],
        )
        log(ev="tick", mode=mode, blind=True, accounts=0, unknown=0)
        strand_audit(st, now)
        prune(st, now)
        save_state(st)
        return 0
    strand_audit(st, now)
    mode, why = effective_mode()
    targets = [t for t in band.get("targets") or [] if isinstance(t, str)]
    held = {
        a.get("acct")
        for a in band["accounts"]
        if isinstance(a, dict) and a.get("verdict") in ("band", "band-guard", "walled")
    }
    kwork = {
        a["acct"]: a.get("k_work")
        for a in band["accounts"]
        if isinstance(a, dict) and a.get("acct")
    }
    pending = {
        s
        for b in batches
        if inflight(b, now)[0]
        for s in b["sids"]
        if s not in verdicts(b)
    }
    n_unknown = 0
    yielded = None
    for a in band["accounts"]:
        if not isinstance(a, dict) or not a.get("acct"):
            continue
        v = str(a.get("verdict") or "unknown:missing")
        if v.startswith("unknown"):
            n_unknown += 1
        w = window(st, a, now)
        brief = {
            k: a.get(k)
            for k in (
                "used_pct",
                "ttw_hi_h",
                "ttw_lo_h",
                "reset_h",
                "trip",
                "cache_age_s",
                "ledger_age_s",
            )
            if a.get(k) is not None
        }
        if w is None:
            log(
                ev="band",
                acct=a["acct"],
                verdict=v,
                open=None,
                mode=mode,
                why=why,
                **brief,
            )
            continue
        step_hysteresis(w, v, a.get("trip"), now)
        log(
            ev="band",
            acct=a["acct"],
            verdict=v,
            open=w["open"],
            mode=mode,
            why=why,
            **brief,
        )
        if not (w["open"] and v == "band"):
            continue  # the guard is re-read EVERY tick
        if time.monotonic() - t0 > TICK_BUDGET_S - (PLAN_TO + PLACE_TO + MOVE_TO):
            log(ev="budget", acct=a["acct"], elapsed_s=round(time.monotonic() - t0, 1))
            break
        src_batches = [b for b in batches if b["from"] == a["acct"]]
        busy = [(b["batch"], inflight(b, now)[1]) for b in src_batches]
        if any(i[1] in ("young", "runner-alive") for i in busy):
            log(
                ev="in-flight",
                acct=a["acct"],
                batches=[b for b, r in busy if r != "settled"][:4],
            )
            continue
        for b, r in busy:
            if r == "settled:unknown" and b not in st["batches"]:
                st["batches"][b] = now
                log(
                    ev="settled-unknown",
                    acct=a["acct"],
                    batch=b,
                    why="no settle marker past the bounded release",
                )
        if not [t for t in targets if t != a["acct"]]:
            log(ev="no-target", acct=a["acct"])
            continue
        if yielded is None:
            yielded = open_limited(now)
        if yielded and mode == "on":
            log(ev="yield", acct=a["acct"], why="recovery", limited_open=yielded)
            continue
        tgt0 = [t for t in targets if t != a["acct"]][0]
        rc, out, err, wall = run(
            [cclr_bin(), "plan", "--from", a["acct"], "--to", tgt0, "--json"],
            PLAN_TO,
            env=child_env(SHED_ENV),
        )
        rows = (parse(out) or {}).get("rows") if rc == 0 else None
        if not isinstance(rows, list):
            log(
                ev="census",
                acct=a["acct"],
                verdict="unknown",
                cause="rc=%s" % rc,
                wall_s=wall,
                err=err[-160:],
            )
            continue
        picks = select(rows, st["cooldown"], pending, now)
        dest, prc, pwall, perr = (
            place(picks, a["acct"], held, kwork) if picks else ({}, 0, 0.0, "")
        )
        w["picks"] = w.get("picks", 0) + len(picks)
        log(
            ev="pick",
            acct=a["acct"],
            cands=len(rows),
            hist=histogram(rows),
            mode=mode,
            picks=["%s>%s" % (p["sid"][:8], dest.get(p["sid"], "-")) for p in picks],
            census_s=wall,
            place_rc=prc,
            place_s=pwall,
            place_err=perr or None,
            would_yield=bool(yielded) or None,
        )
        by_to = {}
        for p in picks:
            if p["sid"] in dest:
                by_to.setdefault(dest[p["sid"]], []).append(p["sid"])
        if not by_to:
            continue
        if mode != "on":
            # SHADOW ENDS HERE, but times the actuation front it cannot run (review E7): the move's
            # own census and strict router read, then a return before any write.
            for to, sids in sorted(by_to.items()):
                drc, dout, derr, dwall = run(
                    [
                        cclr_bin(),
                        "move",
                        "--from",
                        a["acct"],
                        "--sids",
                        ",".join(sids),
                        "--to",
                        to,
                        "--dry-run",
                    ],
                    MOVE_TO,
                    env=child_env(SHED_ENV),
                )
                router = next(
                    (
                        ln.split(":", 1)[0]
                        for ln in dout.splitlines()
                        if ln.startswith(("target-unroutable", "target-unverified"))
                    ),
                    "ranked" if drc == 0 else "unknown",
                )
                log(
                    ev="dry-run",
                    acct=a["acct"],
                    to=to,
                    n=len(sids),
                    rc=drc,
                    wall_s=dwall,
                    router=router,
                    err=derr[-160:] or None,
                )
            continue
        for to, sids in sorted(by_to.items()):
            qfd, qf = tempfile.mkstemp(prefix="lr-shed-queued-")
            os.close(qfd)
            rc, out, err, wall = run(
                [
                    cclr_bin(),
                    "move",
                    "--from",
                    a["acct"],
                    "--sids",
                    ",".join(sids),
                    "--to",
                    to,
                    "--wait",
                    "0",
                    "--slots",
                    "1",
                ],
                MOVE_TO,
                env=child_env(
                    dict(
                        SHED_ENV,
                        CC_LR_MOVE_ORIGIN="shed",
                        CC_LR_MOVE_HOLD_FOCUSED="1",
                        CC_LR_MOVE_QUEUED_OUT=qf,
                    )
                ),
            )
            bid = read(qf).strip()
            try:
                os.unlink(qf)
            except OSError:
                pass
            if bid:
                w["sheds"] = w.get("sheds", 0) + len(sids)
                pending.update(sids)
            log(
                ev="move",
                acct=a["acct"],
                to=to,
                batch=bid or None,
                n=len(sids),
                rc=rc,
                wall_s=wall,
                err=err[-200:] or None,
            )
    log(
        ev="tick",
        mode=mode,
        blind=False,
        accounts=len(band["accounts"]),
        unknown=n_unknown,
        elapsed_s=round(time.monotonic() - t0, 1),
    )
    prune(st, now)
    save_state(st)
    return 0


# ── read-backs ───────────────────────────────────────────────────────────────────────────────────


def decisions():
    out = []
    for p in (
        os.path.join(SHED, "decisions.jsonl.1"),
        os.path.join(SHED, "decisions.jsonl"),
    ):
        for ln in read(p).splitlines():
            r = parse(ln)
            if r:
                out.append(r)
    return out


def pct(xs, q):
    xs = sorted(xs)
    return None if not xs else xs[min(len(xs) - 1, int(math.ceil(q * len(xs))) - 1)]


def report(as_json):
    st = load_state()
    rows = decisions()
    now = now_s()
    batches = shed_batches(now)
    ticks = [r for r in rows if r.get("ev") == "tick"]
    blind = sum(1 for r in ticks if r.get("blind") or r.get("unknown"))
    dry = [
        r["wall_s"]
        for r in rows
        if r.get("ev") == "dry-run" and isinstance(r.get("wall_s"), (int, float))
    ]
    wins = []
    for key, w in sorted(
        st["windows"].items(), key=lambda kv: kv[1].get("reset_epoch", 0)
    ):
        vc = {}
        for b in batches:
            if b["from"] == w["acct"] and b["ts"] >= w.get("first_seen", 0) - 86400:
                for v, _why in verdicts(b).values():
                    vc[v] = vc.get(v, 0) + 1
        wins.append(
            {
                "window": key,
                "acct": w["acct"],
                "reset_at": w.get("reset_at"),
                "open": w.get("open"),
                "opened_at": w.get("opened_at"),
                "picks": w.get("picks", 0),
                "sheds": w.get("sheds", 0),
                "verdicts": vc,
                "final_pct": w.get("final_pct"),
                "closed_by": w.get("closed_by"),
                "unknown_n": w.get("unknown_n", 0),
                "looks": w.get("looks", 0),
            }
        )
    summ = {
        "ticks": len(ticks),
        "blind_ticks": blind,
        "blind_share": round(blind / len(ticks), 3) if ticks else None,
        "dry_run_p50_s": pct(dry, 0.5),
        "dry_run_p90_s": pct(dry, 0.9),
        "dry_runs": len(dry),
    }
    mode, why = effective_mode()
    if as_json:
        print(
            json.dumps(
                {"v": 1, "mode": mode, "why": why, "windows": wins, "summary": summ},
                sort_keys=True,
            )
        )
        return 0
    print(
        "shed mode %s%s · ticks %d · blind %s · dry-run p50 %s s p90 %s s (n %d)"
        % (
            mode,
            " (%s)" % why if why else "",
            summ["ticks"],
            summ["blind_share"],
            summ["dry_run_p50_s"],
            summ["dry_run_p90_s"],
            summ["dry_runs"],
        )
    )
    for w in wins:
        print(
            "%-6s reset %s  opened %s  picks %d  sheds %d  verdicts %s  final %s  closed-by %s  unknown %d/%d"
            % (
                w["acct"],
                w["reset_at"],
                w["opened_at"],
                w["picks"],
                w["sheds"],
                w["verdicts"] or "-",
                w["final_pct"],
                w["closed_by"],
                w["unknown_n"],
                w["looks"],
            )
        )
    return 0


def status():
    mode, why = effective_mode()
    held = read(LOCK).split(" ", 1)
    print(
        "mode %s%s · breaker %s · lock %s"
        % (
            mode,
            " (%s)" % why if why else "",
            "present" if os.path.exists(os.path.join(SHED, "breaker")) else "absent",
            "pid %s" % held[0] if held and held[0] else "free",
        )
    )
    return 0


def main(argv):
    if "--tick" in argv:
        return tick()
    if "--report" in argv:
        return report("--json" in argv)
    if "--status" in argv:
        return status()
    print(__doc__.split("\n\n")[0], file=sys.stderr)
    print("usage: lr-shed.py --tick | --report [--json] | --status", file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
