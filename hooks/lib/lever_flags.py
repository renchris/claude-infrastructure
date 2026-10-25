#!/usr/bin/env python3
"""lever_flags.py — the usage levers' control plane: flag file, arm assignment, lineage.

Plan: docs/plans/USAGE_LEVERS.md § W7+ §2 (stage ladder, D1 "Arm") and §3 rows "Flag file and arm
lib", "Session stamp". Detailed schema: option C §1-2 in
docs/research/usage-levers-2026-10-23/telemetry-design-2026-10-24/measurements.json. Its bash twin is
hooks/lib/lever-flags.sh; the two MUST agree bit-for-bit on every arm (tests/lever-flags.bats).

FLAG FILE ~/.claude/state/levers/flags.json, one per machine (all four config dirs share $HOME):
  {v:1, rev, updated_at, updated_by, levers:{D1..D4:{decision, stage S0|S1|S2|S3, pct 0..100 (integer
  percent), holdback 0..50 (integer percent), mode shadow|live|off, salt, split_salt, params,
  params_id, candidate null|{id, params, share 0..100, round, round_salt}, thresholds_sha,
  stage_started_at, trip null|{id, at, rule, evidence, by, acked_at}}}}
Readers never write it; bin/cc-lever (operator) and cc-lever-guard (lower only) do.

EFFECTIVE PCT, highest precedence first. Everything here can only LOWER a lever:
  1. the existing hook kills (CC_IRS, CC_WORKFLOW_SHADOW, CC_IDLE_KEEPALIVE, CC_SUBAGENT_LONG_BASH
     = off) stop the hook entirely: arm "off", flag_src hook-kill.
  2. CC_LEVER_EXCLUDE=1 (eval and judge runs): arm "excluded", kept out of every population.
  3. CC_LEVER_ALL / CC_LEVER_Dn = off|control: pct 0, every unit control, flag_src env-off|env-control.
     Any other value is ignored: an env var can never raise.
  4. flags.json: pct counts only when mode=live, no trip is un-acked, and the guard heartbeat is no
     older than CC_LEVER_DEADMAN_S (1800 s); a stale heartbeat on a live lever is flag_src deadman.
     A file that exists but cannot be parsed (or a malformed lever entry) is pct 0, flag_src unreadable.
  5. no file: pct 0, flag_src default.

ARM. h = int(sha256(salt + ":" + unit)[:13], 16), u = h / 16**13. Decided in exact integers so bash
3.2 can match it: holdback iff live and h*100 >= (100 - holdback) * 2**52; else treat iff
h*100 < pct_eff * 2**52; else ctrl. The salt is fixed across S1-S3, so 10% ⊂ 50% ⊂ 100%. u is
logged truncated to 6 decimals (both libs compute it the same exact way). split: test iff
u(split_salt, unit) < 0.5. variant (treated units only, candidate present): cand iff
h(round_salt, unit)*100 < share * 2**52. Units: D1 and D2 the lineage root, D3 "sid:gap_start",
D4 the agent_id. Arms are per lever, never per account.

LINEAGE (D1 "Arm" bullet), first match wins:
  env CC_LEVER_LINEAGE (exported into a staged successor by scripts/handoff-fire.sh hf_succ_stage)
  → arms/<sid> (this session's own earlier answer; sticky, so a session never changes lineage)
  → lineage/<pane>.json (written by handoff-fire at recycle time; used once, by the first session
    other than its predecessor, within CC_LEVER_LINEAGE_TTL_S)
  → proc/<claude-pid>-<lstart> (the same claude process across /clear and compact)
  → the session's own sid.
The answer is cached in arms/<sid> as one plain-text line `lineage=<root> src=<src>` so a bash hook
reads it with builtins, and in the proc cache.

Stdout is used only by the CLI verbs below; library calls never print.
  lever_flags.py arm <lever> <unit>                → one JSON object
  lever_flags.py lineage --sid S [--pane P] [--claude-pid N] [--no-write] → "<root>\t<src>"
  lever_flags.py hash <salt> <unit>                → "<h> <u6>"
  lever_flags.py stamp < SessionStart payload      → appends one kind=session row; prints nothing
"""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time

LEVERS = ("D1", "D2", "D3", "D4")
DECISIONS = {
    "D1": "43da49891e75",
    "D2": "a4c54d1744d1",
    "D3": "c0f9d5368147",
    "D4": "3df527edd333",
}
HOOK_KILLS = {
    "D1": "CC_IRS",
    "D2": "CC_WORKFLOW_SHADOW",
    "D3": "CC_IDLE_KEEPALIVE",
    "D4": "CC_SUBAGENT_LONG_BASH",
}
STAGES = ("S0", "S1", "S2", "S3")
MODES = ("shadow", "live", "off")
TWO52 = 1 << 52


def home():
    return os.environ.get("HOME") or os.path.expanduser("~")


def state_dir():
    return os.environ.get("CC_LEVER_STATE_DIR") or os.path.join(
        home(), ".claude", "state", "levers"
    )


def flags_path():
    return os.environ.get("CC_LEVER_FLAGS") or os.path.join(state_dir(), "flags.json")


def heartbeat_path():
    return os.environ.get("CC_LEVER_HEARTBEAT") or os.path.join(
        state_dir(), "guard.heartbeat"
    )


def _int_env(name, default):
    v = os.environ.get(name, "")
    return int(v) if v.isdigit() else default


def deadman_s():
    return _int_env("CC_LEVER_DEADMAN_S", 1800)


def utc_now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


# ── hash ──────────────────────────────────────────────────────────────────────────────────────
def h52(salt, unit):
    return int(
        hashlib.sha256((str(salt) + ":" + str(unit)).encode("utf-8")).hexdigest()[:13],
        16,
    )


def u6(h):
    """floor(u * 10^6) / 10^6, the logged form; bash computes the same integer."""
    return (h * 1000000 >> 52) / 1000000.0


def below(h, pct):
    """u < pct/100, exactly."""
    return h * 100 < pct * TWO52


# ── flag file ─────────────────────────────────────────────────────────────────────────────────
SALT_OK = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")


SAFE_OK = SALT_OK | {":"}


def _intval(v, lo, hi):
    """An integral JSON number in [lo, hi] (10 and 10.0 alike, never a bool) → int, else None.
    jq cannot tell 10 from 10.0, so neither may this; the bash twin applies the same rule."""
    try:
        if isinstance(v, bool) or not isinstance(v, (int, float)) or v != int(v):
            return None
    except (OverflowError, ValueError):     # inf, nan
        return None
    return int(v) if lo <= v <= hi else None


def _salt(v):
    return v if isinstance(v, str) and set(v) <= SALT_OK else None


def _norm_lever(e):
    """A flags.json lever entry → the normalized dict both libs decide on, or None (malformed)."""
    if not isinstance(e, dict):
        return None
    n = {"stage": e.get("stage", "S0"), "mode": e.get("mode", "shadow"),
         "pct": _intval(e.get("pct", 0), 0, 100), "holdback": _intval(e.get("holdback", 0), 0, 50),
         "salt": _salt(e.get("salt", "")), "split_salt": _salt(e.get("split_salt", "")),
         "params_id": e.get("params_id"), "thresholds_sha": e.get("thresholds_sha"),
         "candidate": None, "trip_open": False}
    if n["stage"] not in STAGES or n["mode"] not in MODES or None in (
            n["pct"], n["holdback"], n["salt"], n["split_salt"]):
        return None
    c = e.get("candidate")
    if c is not None:
        if not isinstance(c, dict):
            return None
        share, rs = _intval(c.get("share", 0), 0, 100), _salt(c.get("round_salt", ""))
        if share is None or rs is None:
            return None
        n["candidate"] = {"id": c.get("id"), "share": share, "round_salt": rs}
    t = e.get("trip")
    if t is not None and not isinstance(t, dict):
        return None
    if isinstance(t, dict):
        ack = t.get("acked_at")
        n["trip_open"] = not (isinstance(ack, str) and ack != "")
    return n


def read_flags(path=None):
    """→ (doc|None, src): src default (no file) · unreadable · file."""
    path = path or flags_path()
    try:
        with open(path, "rb") as f:
            doc = json.loads(f.read().decode("utf-8"))
    except FileNotFoundError:
        return None, "default"
    except Exception:
        return None, "unreadable"
    if not isinstance(doc, dict) or not isinstance(doc.get("levers"), dict):
        return None, "unreadable"
    return doc, "file"


def heartbeat_age(now=None):
    try:
        m = os.stat(heartbeat_path()).st_mtime
    except OSError:
        return None
    return int(now or time.time()) - int(m)          # whole seconds, as the bash twin reads them


def heartbeat_fresh(now=None):
    a = heartbeat_age(now)
    return a is not None and a <= deadman_s()


def trip_open(e):
    """An un-acked trip latches a lever at pct 0. Acked means acked_at is a non-empty string."""
    t = e.get("trip") if isinstance(e, dict) else None
    if not isinstance(t, dict):
        return False
    ack = t.get("acked_at")
    return not (isinstance(ack, str) and ack != "")


def effective(lever, doc=None, src=None, now=None):
    """→ dict(entry, pct_eff, flag_src, arm_forced) for one lever, before any unit is hashed."""
    if src is None:
        doc, src = read_flags()
    env = os.environ
    if env.get(HOOK_KILLS[lever], "") == "off":
        return {
            "entry": None,
            "pct_eff": 0,
            "flag_src": "hook-kill",
            "arm_forced": "off",
        }
    if env.get("CC_LEVER_EXCLUDE", "") == "1":
        return {
            "entry": None,
            "pct_eff": 0,
            "flag_src": "excluded",
            "arm_forced": "excluded",
        }
    entry = None
    if src == "file":
        entry = _norm_lever(doc["levers"].get(lever))
        if entry is None:
            src = "unreadable"
    out = {"entry": entry, "pct_eff": 0, "flag_src": src, "arm_forced": None}
    for name in ("CC_LEVER_ALL", "CC_LEVER_" + lever):
        v = env.get(name, "")
        if v in ("off", "control"):
            out["flag_src"] = "env-" + v
            return out
    if entry is None:
        return out
    pct = entry["pct"]
    if entry["mode"] == "live" and pct > 0 and not entry["trip_open"]:
        if heartbeat_fresh(now):
            out["pct_eff"] = pct
        else:
            out["flag_src"] = "deadman"
    return out


def arm(lever, unit, doc=None, src=None, now=None):
    """The arm of one unit for one lever, as the dict a lever-arms row carries."""
    if lever not in LEVERS:
        raise ValueError("unknown lever %r" % lever)
    if src is None:
        doc, src = read_flags()
    eff = effective(lever, doc, src, now)
    e = eff["entry"] or {}
    row = {
        "lever": lever,
        "decision": DECISIONS[lever],
        "unit": str(unit),
        "stage": e.get("stage", "S0"),
        "mode": e.get("mode", "shadow"),
        "pct_eff": eff["pct_eff"],
        "flag_src": eff["flag_src"],
        "flag_rev": (doc or {}).get("rev") if eff["entry"] is not None else None,
        "arm": "ctrl",
        "u": None,
        "split": None,
        "variant": None,
        "variant_id": None,
        "params_id": e.get("params_id"),
        "thresholds_sha": e.get("thresholds_sha"),
    }
    if eff["arm_forced"]:
        row["arm"] = eff["arm_forced"]
        return row
    salt = e.get("salt") or ""
    if not salt:
        return row  # no salt (no file / unreadable): control, no u to log
    h = h52(salt, unit)
    row["u"] = u6(h)
    p, hb = eff["pct_eff"], e.get("holdback", 0)
    if p > 0 and hb > 0 and not below(h, 100 - hb):
        row["arm"] = "holdback"
    elif below(h, p):
        row["arm"] = "treat"
    if e.get("split_salt"):
        row["split"] = "test" if below(h52(e["split_salt"], unit), 50) else "train"
    c = e.get("candidate")
    if row["arm"] == "treat" and isinstance(c, dict):
        cand = below(h52(c.get("round_salt") or "", unit), c.get("share", 0))
        row["variant"] = "cand" if cand else "inc"
        row["variant_id"] = c.get("id") if cand else e.get("params_id")
    return row


# ── lineage ───────────────────────────────────────────────────────────────────────────────────
def _safe(s):
    """ASCII [A-Za-z0-9._:-], no "..", at most 128 chars — the bash twin's lf_safe."""
    return bool(s) and set(s) <= SAFE_OK and ".." not in s and len(s) <= 128


def self_pane():
    if os.environ.get("CC_TERM") == "kitty" and os.environ.get("KITTY_WINDOW_ID"):
        return os.environ["KITTY_WINDOW_ID"]
    return os.environ.get("ITERM_SESSION_ID", "").rsplit(":", 1)[-1]


def _lstart(pid):
    try:
        out = subprocess.run(
            ["/bin/ps", "-o", "lstart=", "-p", str(pid)],
            capture_output=True,
            text=True,
            timeout=3,
            env={"TZ": "UTC", "LC_ALL": "C", "PATH": "/bin:/usr/bin"},
        )
        return "".join(out.stdout.split()) or None
    except Exception:
        return None


def _write_atomic(path, text):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def read_sid_cache(sid):
    try:
        with open(os.path.join(state_dir(), "arms", sid)) as f:
            kv = dict(p.split("=", 1) for p in f.read().split() if "=" in p)
    except (OSError, ValueError):
        return None
    root = kv.get("lineage", "")
    return (root, kv.get("src", "cache")) if _safe(root) else None


def resolve_lineage(sid, pane=None, claude_pid=None, write=True, now=None):
    """→ (root, src) with src env|cache|lineage-file|proc|self. Never raises on IO."""
    now = now or time.time()
    root, src = None, None
    env = os.environ.get("CC_LEVER_LINEAGE", "")
    if _safe(env):
        root, src = env, "env"
    if root is None and _safe(sid):
        c = read_sid_cache(sid)
        if c:
            return c  # sticky: this session already answered
    pane = self_pane() if pane is None else pane
    pane_file = (
        os.path.join(state_dir(), "lineage", pane + ".json") if _safe(pane) else None
    )
    if root is None and pane_file:
        try:
            with open(pane_file) as f:
                pf = json.load(f)
            ttl = _int_env("CC_LEVER_LINEAGE_TTL_S", 1800)
            ok = (
                isinstance(pf, dict)
                and _safe(pf.get("root", ""))
                and pf.get("pred_sid") != sid
                and pf.get("succ_sid") in (None, "", sid)
                and isinstance(pf.get("epoch"), int)
                and 0 <= now - pf["epoch"] <= ttl
            )
            if ok:
                root, src = pf["root"], "lineage-file"
                if write and pf.get("succ_sid") != sid:
                    pf["succ_sid"] = sid
                    _try(
                        lambda: _write_atomic(
                            pane_file, json.dumps(pf, sort_keys=True) + "\n"
                        )
                    )
        except (OSError, ValueError):
            pass
    proc_file = None
    if claude_pid is None:
        claude_pid = os.environ.get("CC_HOOK_PARENT_PID") or None
    if claude_pid and str(claude_pid).isdigit():
        ls = _lstart(claude_pid)
        if ls:
            proc_file = os.path.join(state_dir(), "proc", "%s-%s" % (claude_pid, ls))
    if root is None and proc_file:
        try:
            with open(proc_file) as f:
                kv = dict(p.split("=", 1) for p in f.read().split() if "=" in p)
            if _safe(kv.get("lineage", "")):
                root, src = kv["lineage"], "proc"
        except (OSError, ValueError):
            pass
    if root is None:
        root, src = sid, "self"
    if write and _safe(sid) and _safe(root or ""):
        line = "lineage=%s src=%s\n" % (root, src)
        _try(lambda: _write_atomic(os.path.join(state_dir(), "arms", sid), line))
        if proc_file and src != "proc":
            _try(lambda: _write_atomic(proc_file, line))
    return root, src


def _try(fn):
    try:
        fn()
    except Exception:
        pass


# ── session stamp (hooks/lever-arm-start.sh) ──────────────────────────────────────────────────
SESSION_LEVERS = ("D1", "D2")          # lineage-unit levers; D3 (gap) and D4 (agent) arm per event
MAX_ROW = 2048


def log_dir():
    return os.environ.get("CC_LEVER_LOG_DIR") or os.path.join(home(), ".claude", "logs")


def acct():
    d = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(home(), ".claude")
    return os.path.basename(d.rstrip("/")) or ".claude"


def append_row(name, row):
    """One row, one write(), at most MAX_ROW bytes: O_APPEND keeps concurrent writers whole."""
    line = (json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    if len(line) > MAX_ROW:
        return False
    os.makedirs(log_dir(), exist_ok=True)
    fd = os.open(os.path.join(log_dir(), name), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        os.write(fd, line)
    finally:
        os.close(fd)
    return True


def stamp(payload):
    """The kind=session row for one SessionStart: lineage, and the D1/D2 arms of that lineage."""
    sid = str(payload.get("session_id") or "")
    if not _safe(sid):
        return None
    root, lsrc = resolve_lineage(sid)
    doc, src = read_flags()
    arms = {}
    for L in SESSION_LEVERS:
        a = arm(L, root, doc, src)
        arms[L] = {k: a[k] for k in ("arm", "u", "flag_src", "split", "pct_eff", "stage")}
    row = {"v": 1, "kind": "session", "ts": utc_now(), "sid": sid, "lineage": root,
           "lineage_src": lsrc, "acct": acct(), "source": str(payload.get("source") or "")[:32],
           "entrypoint": os.environ.get("CLAUDE_CODE_ENTRYPOINT", "")[:32],
           "pane": self_pane()[:64], "excluded": os.environ.get("CC_LEVER_EXCLUDE", "") == "1",
           "flag_src": src, "flag_rev": (doc or {}).get("rev") if src == "file" else None, "arms": arms}
    append_row("lever-arms.jsonl", row)
    return row


def main(argv):
    if len(argv) >= 3 and argv[0] == "hash":
        h = h52(argv[1], argv[2])
        print("%d %.6f" % (h, u6(h)))
        return 0
    if len(argv) == 3 and argv[0] == "arm" and argv[1] in LEVERS:
        print(json.dumps(arm(argv[1], argv[2]), sort_keys=True))
        return 0
    if argv == ["stamp"]:
        try:
            payload = json.loads(sys.stdin.read() or "{}")
        except ValueError:
            return 0
        if isinstance(payload, dict):
            _try(lambda: stamp(payload))
        return 0
    if argv and argv[0] == "lineage":
        a = {"--sid": None, "--pane": None, "--claude-pid": None}
        write, i = True, 1
        while i < len(argv):
            if argv[i] == "--no-write":
                write, i = False, i + 1
            elif argv[i] in a and i + 1 < len(argv):
                a[argv[i]], i = argv[i + 1], i + 2
            else:
                return 2
        if not _safe(a["--sid"] or ""):
            return 2
        root, src = resolve_lineage(a["--sid"], a["--pane"], a["--claude-pid"], write)
        print("%s\t%s" % (root, src))
        return 0
    sys.stderr.write(__doc__.split("Stdout is used")[1])
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
