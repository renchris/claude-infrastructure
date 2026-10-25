#!/usr/bin/env python3
"""lever_events.py — the usage-lever scorer's inputs: eligible events per lever, their arms, and the
deduped, priced tokens of every session.

Plan: docs/plans/USAGE_LEVERS.md § W7+ §3 rows "Scorer" and "Telemetry rows", §2 "Plumbing gate";
wave S4. The stats on top of this (SRM, bootstrap, CUPED, looks) are S5's lever_stats.py.

TOKENS come from bin/cc-token-ledger scan(), imported, never re-implemented: message.id dedupe with
the earliest file owning a copied id, output as the max over a message's records (imputed where the
final record is missing), every real $HOME/.claude*/projects root deduped by realpath. scan() also
reports the parse accounting, hook-deny split and prompt-too-long refusals this scorer needs.

PRICE (pp of weekly quota per Mtok; §1(c), measured by the noise-floor build): cache read
0.0057-0.0076 (lo/hi; 0.0067 mid), every input-side write class (uncached input and both cache-write
TTLs) 0.245, output 0.404. pp lo/mid/hi differ only in the read weight; both ends are reported.

THE FOUR ROOTS are the accounts' transcript roots (accounts.json: next → ~/.claude-next, whose
projects/ is a symlink to ~/.claude/projects; next2-4 → -secondary/-tertiary/-quaternary). A root
that is missing or unreadable is PLUMBING, never a smaller population.

ELIGIBLE EVENTS: the points where a lever DECIDES, logged in both arms by the shadow hooks, with
`would` = the treatment would act there.
  D1  idle-recycle-shadow.jsonl  v=="ok" (an idle return evaluated)     would = would_advise_k2 (200k)
  D2  workflow-lean-shadow.jsonl every Workflow call parsed             would = would_deny
  D3  idle-keepalive.jsonl       kind=="gap" with dur >= wake_s         would = True (a due wake)
  D4  subagent-long-bash.jsonl   would_deny_class set                   would = not exempt
Units are lever_flags' (D1/D2 the lineage root, D3 "sid:gap_start", D4 the agent_id). An event's
arm is the LOGGED one where lever-arms.jsonl has it (kind=session for D1/D2, kind=event rows per
(lever, unit) once S2/S3 write them), else recomputed by lever_flags.arm() against the current flag
file, and every event says which (arm_src logged|recomputed).

Library only; bin/cc-lever-score is the CLI. Env seams: HOME (the roots), CC_LEVER_LOG_DIR,
CC_LEVER_STATE_DIR, CC_LEVER_FLAGS (lever_flags'), CC_LAND_LOG (ship-land's LAND_LOG),
CC_TOKEN_LEDGER_WORKERS.
"""

import calendar
import importlib.machinery
import importlib.util
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, "hooks", "lib"))
import lever_flags as lf  # noqa: E402

W_READ = {"lo": 0.0057, "mid": 0.0067, "hi": 0.0076}
W_WRITE = 0.245
W_OUT = 0.404
ACCOUNT_DIRS = (
    ".claude",
    ".claude-secondary",
    ".claude-tertiary",
    ".claude-quaternary",
)
SHADOW_LOGS = {
    "D1": "idle-recycle-shadow.jsonl",
    "D2": "workflow-lean-shadow.jsonl",
    "D3": "idle-keepalive.jsonl",
    "D4": "subagent-long-bash.jsonl",
}
ARMS_LOG = "lever-arms.jsonl"
LEDGER_LOG = "lever-ledger.jsonl"
# ship-land exits (T2, §2 shared guards): 0 landed; 6/5/11/143 failed; 42 excluded (a lock wait).
LAND_OK, LAND_FAILED, LAND_EXCLUDED = {0}, {5, 6, 11, 143}, {42}
EVAL_SLUG = "tmp-lev-eval"  # eval runs use a /tmp/lev-eval cwd (§3 "Evals")


def home():
    return os.environ.get("HOME") or os.path.expanduser("~")


# ── the token ledger, imported ────────────────────────────────────────────────────────────────
_TL = None


def token_ledger():
    """bin/cc-token-ledger as a module (it has no .py suffix), loaded once."""
    global _TL
    if _TL is None:
        path = os.path.join(REPO, "bin", "cc-token-ledger")
        loader = importlib.machinery.SourceFileLoader("cc_token_ledger", path)
        spec = importlib.util.spec_from_loader("cc_token_ledger", loader)
        mod = importlib.util.module_from_spec(spec)
        sys.modules["cc_token_ledger"] = (
            mod  # scan()'s worker pool pickles parse_file by module name
        )
        loader.exec_module(mod)
        _TL = mod
    return _TL


# ── time ──────────────────────────────────────────────────────────────────────────────────────
_ISO = re.compile(
    r"^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d+)?(Z|[+-]\d\d:?\d\d)$"
)


def parse_ts(v):
    """Epoch seconds from an epoch number or an ISO-8601 stamp WITH an offset (Z, ±HHMM, ±HH:MM).
    A naive or malformed stamp → None: the caller counts it as a parse failure (§6, mixed offsets)."""
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v) if 1e9 < v < 1e10 else None
    if not isinstance(v, str):
        return None
    m = _ISO.match(v)
    if not m:
        return None
    y, mo, d, h, mi, s, off = m.groups()
    t = calendar.timegm((int(y), int(mo), int(d), int(h), int(mi), int(s), 0, 0, 0))
    if off != "Z":
        sign = 1 if off[0] == "+" else -1
        oh, om = int(off[1:3]), int(off[-2:])
        t -= sign * (oh * 3600 + om * 60)
    return float(t)


def iso(t):
    import time

    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def iso_naive(t):
    """scan()'s window format: UTC, no zone suffix."""
    import time

    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t))


# ── roots ─────────────────────────────────────────────────────────────────────────────────────
def account_roots():
    return [os.path.join(home(), d, "projects") for d in ACCOUNT_DIRS]


def root_status():
    """→ [{root, real, ok, why}] for the four account roots; ok means a listable directory."""
    out = []
    for r in account_roots():
        st = {"root": r.replace(home(), "~"), "real": None, "ok": False, "why": None}
        if not os.path.isdir(r):
            st["why"] = "missing"
        else:
            try:
                os.listdir(r)
                st["ok"], st["real"] = True, os.path.realpath(r)
            except OSError as e:
                st["why"] = "unreadable: %s" % e.strerror
        out.append(st)
    return out


def extra_roots():
    """Real $HOME/.claude*/projects roots that are no account's (scan() reads them too)."""
    named = {os.path.realpath(r) for r in account_roots()}
    seen = set()
    for r in token_ledger().config_roots():
        rp = os.path.realpath(r)
        if rp not in named and rp not in seen:
            seen.add(rp)
    return sorted(p.replace(home(), "~") for p in seen)


# ── jsonl stores ──────────────────────────────────────────────────────────────────────────────
def read_jsonl(path, since=None, until=None, ts_key="ts"):
    """→ (rows in window, {lines, bad, missing}). bad = not JSON, not an object, or an unparseable
    timestamp. Each kept row gains "_t" (epoch)."""
    rows, st = [], {"lines": 0, "bad": 0, "missing": False}
    try:
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
            if not isinstance(r, dict):
                st["bad"] += 1
                continue
            t = parse_ts(r.get(ts_key))
            if t is None:
                st["bad"] += 1
                continue
            if (since is not None and t < since) or (until is not None and t >= until):
                continue
            r["_t"] = t
            rows.append(r)
    return rows, st


def log_path(name):
    return os.path.join(lf.log_dir(), name)


def land_log_path():
    return os.environ.get("CC_LAND_LOG") or os.path.join(home(), ".claude", "land.log")


# ── arms ──────────────────────────────────────────────────────────────────────────────────────
class Arms:
    """lever-arms.jsonl indexed: session rows by sid, event rows by (lever, unit)."""

    def __init__(self, rows):
        self.rows = rows
        self.session = {}
        self.event = {}
        for r in sorted(rows, key=lambda r: r["_t"]):
            if r.get("kind") == "session" and isinstance(r.get("sid"), str):
                self.session.setdefault(
                    r["sid"], r
                )  # the first stamp of a sid is its lineage
            elif r.get("kind") == "event" and r.get("lever") in lf.LEVERS:
                self.event.setdefault((r["lever"], str(r.get("unit"))), r)
        self.first_t = min((r["_t"] for r in rows), default=None)

    def lineage(self, sid):
        """→ (root, src): the stamp's lineage, the resolver's cached answer, or the sid itself."""
        s = self.session.get(sid)
        if s and lf._safe(str(s.get("lineage") or "")):
            return s["lineage"], "arms"
        c = lf.read_sid_cache(sid) if lf._safe(sid or "") else None
        if c:
            return c[0], "cache"
        return sid, "self"

    def acct(self, sid):
        s = self.session.get(sid)
        return s.get("acct") if s else None


def arm_of(arms, flags, lever, unit, sid):
    """→ {arm, u, split, flag_src, arm_src} for one event."""
    if lever in ("D1", "D2"):
        s = arms.session.get(sid)
        a = ((s or {}).get("arms") or {}).get(lever)
        if isinstance(a, dict):
            return {
                "arm": a.get("arm"),
                "u": a.get("u"),
                "split": a.get("split"),
                "flag_src": a.get("flag_src"),
                "arm_src": "logged",
            }
    else:
        e = arms.event.get((lever, str(unit)))
        if e:
            return {
                "arm": e.get("arm"),
                "u": e.get("u"),
                "split": e.get("split"),
                "flag_src": e.get("flag_src"),
                "arm_src": "logged",
            }
    doc, src = flags
    a = lf.arm(lever, unit, doc, src)
    return {
        "arm": a["arm"],
        "u": a["u"],
        "split": a["split"],
        "flag_src": a["flag_src"],
        "arm_src": "recomputed",
    }


# ── events ────────────────────────────────────────────────────────────────────────────────────
def _acct_of(r):
    a = r.get("acct")
    if isinstance(a, str) and a:
        return a
    cd = r.get("config_dir")
    if isinstance(cd, str) and cd:
        return os.path.basename(cd.rstrip("/"))
    return None


def _extract(lever, r):
    """One shadow row → (sid, unit_or_None, t, would, extra) when it is an eligible event, else None.
    unit None means the lineage root of sid."""
    if lever == "D1":
        if r.get("v") != "ok":
            return None
        t = parse_ts(r.get("turn_start")) or r["_t"]
        return (
            r.get("sid"),
            None,
            t,
            bool(r.get("would_advise_k2")),
            {
                "would_150k": bool(r.get("would_advise")),
                "ctx": r.get("ctx_at_idle"),
                "gap_s": r.get("gap_s"),
            },
        )
    if lever == "D2":
        if r.get("hook") != "workflow-lean-shadow" or r.get("parse") != "ok":
            return None
        return (
            r.get("session_id"),
            None,
            r["_t"],
            bool(r.get("would_deny")),
            {
                "resume": r.get("resume_from_run_id") is not None,
                "calls": r.get("calls"),
            },
        )
    if lever == "D3":
        if r.get("kind") != "gap":
            return None
        dur, wake_s = r.get("dur"), r.get("wake_s") or 3300
        if not isinstance(dur, (int, float)) or dur < wake_s:
            return None
        start = r.get("start")
        if parse_ts(start) is None:
            return None
        return (
            r.get("sid"),
            "%s:%s" % (r.get("sid"), start),
            parse_ts(start),
            True,
            {"dur": dur, "ctx": r.get("ctx"), "outcome": r.get("outcome")},
        )
    if lever == "D4":
        if r.get("kind") != "subagent_bash" or not r.get("would_deny_class"):
            return None
        return (
            r.get("sid"),
            str(r.get("agent_id") or ""),
            r["_t"],
            r.get("exempt") is None,
            {"class": r.get("would_deny_class"), "exempt": r.get("exempt")},
        )
    return None


def load_events(since, until, arms, flags):
    """→ (events, {lever: store stats}). Events are sorted (lever, t, unit) for stable output."""
    events, stats = [], {}
    for lever, name in SHADOW_LOGS.items():
        rows, st = read_jsonl(log_path(name), since, until)
        st["events"] = 0
        stats[lever] = st
        seen = set()
        for r in rows:
            x = _extract(lever, r)
            if x is None:
                continue
            sid, unit, t, would, extra = x
            if not isinstance(sid, str) or not sid:
                continue
            lineage, lsrc = arms.lineage(sid)
            if unit is None:
                unit = lineage
            key = (unit, t) if lever in ("D1", "D2", "D4") else unit
            if (
                lever == "D3" and key in seen
            ):  # one gap, one event (rows repeat per tick)
                continue
            seen.add(key)
            ev = {
                "lever": lever,
                "unit": unit,
                "sid": sid,
                "lineage": lineage,
                "lineage_src": lsrc,
                "acct": _acct_of(r) or arms.acct(sid),
                "t": t,
                "would": would,
            }
            ev.update(extra)
            ev.update(arm_of(arms, flags, lever, unit, sid))
            events.append(ev)
            st["events"] += 1
    events.sort(key=lambda e: (e["lever"], e["t"], e["unit"], e["sid"]))
    return events, stats


# ── lands ─────────────────────────────────────────────────────────────────────────────────────
def land_class(code):
    if code in LAND_OK:
        return "ok"
    if code in LAND_FAILED:
        return "failed"
    if code in LAND_EXCLUDED:
        return "excluded"
    return "unknown"


def load_lands(since, until):
    """→ ({sid: {ok, failed, excluded, unknown}}, [unknown exit codes], store stats)."""
    rows, st = read_jsonl(land_log_path(), since, until)
    by_sid = defaultdict(lambda: {"ok": 0, "failed": 0, "excluded": 0, "unknown": 0})
    unknown = []
    for r in rows:
        if r.get("tool") != "ship-land":
            continue
        code = r.get("exit")
        c = (
            land_class(code)
            if isinstance(code, int) and not isinstance(code, bool)
            else "unknown"
        )
        if c == "unknown":
            unknown.append(code)
        sid = r.get("sid")
        if isinstance(sid, str) and sid:
            by_sid[sid][c] += 1
    return dict(by_sid), unknown, st


# ── sessions ──────────────────────────────────────────────────────────────────────────────────
def price(tok, end):
    """pp at one read-weight end, from the scan's token classes."""
    w = tok["uncached_input"] + tok["cache_write_5m"] + tok["cache_write_1h"]
    return (w * W_WRITE + tok["cache_read"] * W_READ[end] + tok["output"] * W_OUT) / 1e6


def scan_sessions(since, until):
    """→ (sessions {sid: dict}, scan meta, request index {sid: [(t, pp_mid)]}).

    One scan() over the window; a session is the tree under one main sid (its subagents and
    workflow agents included), the unit cc-token-ledger calls a task."""
    tl = token_ledger()
    workers = int(os.environ.get("CC_TOKEN_LEDGER_WORKERS") or 4)
    results, meta = tl.scan(iso_naive(since), iso_naive(until), workers=workers)
    sess = {}
    reqs = defaultdict(list)
    for f in results:
        ctx, cdir, slug, sid = f["cls"][0], f["cls"][1], f["cls"][2], f["cls"][3]
        s = sess.get(sid)
        if s is None:
            s = sess[sid] = {
                "sid": sid,
                "root": cdir,
                "slug": slug,
                "tokens": dict.fromkeys(tl.CLASSES, 0),
                "output_recorded": 0,
                "responses": 0,
                "responses_imputed": 0,
                "files": 0,
                "tool_results": 0,
                "tool_errors": 0,
                "tool_errors_hook": 0,
                "ptl_n": 0,
                "ptl_last": "",
                "last_real": "",
                "first_ts": "",
                "last_ts": "",
                "spans_start": False,
                "spans_end": False,
                "cc_version": None,
                "models": set(),
                "main_seen": False,
            }
        if ctx == "main" and not s["main_seen"]:
            s["main_seen"], s["root"], s["slug"] = True, cdir, slug
        s["files"] += 1
        s["tool_results"] += f["tool_n"]
        s["tool_errors"] += f["tool_err"] - f["tool_err_hook"]
        s["tool_errors_hook"] += f["tool_err_hook"]
        s["spans_start"] |= f["spans_start"]
        s["spans_end"] |= f["spans_end"]
        if ctx == "main":
            s["ptl_n"] += f["ptl_n"]
            s["ptl_last"] = max(s["ptl_last"], f["ptl_last"])
            if s["cc_version"] is None:
                s["cc_version"] = f["cc_version"]
        for r, oest in zip(f["kept"], f["est"]):
            ts = (r[tl.R_TS] or "")[:19]
            c5x = r[tl.R_C5] + max(r[tl.R_CCT] - r[tl.R_C5] - r[tl.R_C1], 0)
            tok = {
                "uncached_input": r[tl.R_IN],
                "cache_write_5m": c5x,
                "cache_write_1h": r[tl.R_C1],
                "cache_read": r[tl.R_CR],
                "output": oest,
            }
            for k, v in tok.items():
                s["tokens"][k] += v
            s["output_recorded"] += r[tl.R_OUT]
            s["responses"] += 1
            if not r[tl.R_FINAL] and r[tl.R_MODEL] != "<synthetic>":
                s["responses_imputed"] += 1
            if ts:
                s["first_ts"] = min(s["first_ts"] or ts, ts)
                s["last_ts"] = max(s["last_ts"], ts)
            if ctx == "main" and r[tl.R_MODEL] != "<synthetic>":
                s["models"].add(r[tl.R_MODEL])
                s["last_real"] = max(s["last_real"], ts)
            t = parse_ts(ts + "Z") if ts else None
            if t is not None:
                reqs[sid].append((t, price(tok, "mid")))
    for s in sess.values():
        s["models"] = sorted(s["models"])
        # a context-wall death: the main session's last word was the refusal
        s["ptl_death"] = bool(s["ptl_n"]) and s["ptl_last"] >= s["last_real"]
        s["pp"] = {e: price(s["tokens"], e) for e in ("lo", "mid", "hi")}
        s["eval"] = EVAL_SLUG in (s["slug"] or "")
    for v in reqs.values():
        v.sort()
    return sess, meta, dict(reqs)


def window_pp(reqs, sid, t0, t1):
    """pp_mid of a session's requests with t0 <= t < t1 (S5 prices events through this)."""
    return sum(p for t, p in reqs.get(sid, ()) if t0 <= t < t1)


# ── the ledger row ────────────────────────────────────────────────────────────────────────────
def ledger_rows(sess, arms, flags, events, lands, since, until):
    """One row per session, sorted by sid. Arms: the session's D1/D2 (its lineage's) plus a
    per-arm event count for every lever. Intention to treat: the cost runs to the window's end."""
    ev_by_sid = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))
    for e in events:
        ev_by_sid[e["sid"]][e["lever"]][e["arm"] or "?"] += 1
    rows = []
    for sid in sorted(sess):
        s = sess[sid]
        lineage, lsrc = arms.lineage(sid)
        stamp = arms.session.get(sid) or {}
        acct = stamp.get("acct")
        arm_d = {}
        for L in ("D1", "D2"):
            a = arm_of(arms, flags, L, lineage, sid)
            arm_d[L] = {"arm": a["arm"], "u": a["u"], "src": a["arm_src"]}
        row = {
            "v": 1,
            "kind": "ledger",
            "sid": sid,
            "lineage": lineage,
            "lineage_src": lsrc,
            "acct": acct or s["root"],
            "acct_src": "arms" if acct else "transcript",
            "arms": arm_d,
            "events": {
                L: dict(sorted(c.items()))
                for L, c in sorted(ev_by_sid.get(sid, {}).items())
            },
            "tokens": dict(s["tokens"], output_recorded=s["output_recorded"]),
            "responses": s["responses"],
            "responses_imputed": s["responses_imputed"],
            "contexts": s["files"],
            "pp": {k: round(v, 6) for k, v in s["pp"].items()},
            "tool_results": s["tool_results"],
            "tool_errors": s["tool_errors"],
            "tool_errors_hook": s["tool_errors_hook"],
            "lands": lands.get(
                sid, {"ok": 0, "failed": 0, "excluded": 0, "unknown": 0}
            ),
            "ptl": {"n": s["ptl_n"], "death": s["ptl_death"]},
            "eval": bool(s["eval"] or stamp.get("excluded")),
            "first_ts": s["first_ts"],
            "last_ts": s["last_ts"],
            "spans_start": s["spans_start"],
            "spans_end": s["spans_end"],
            "cc_version": s["cc_version"],
            "models": s["models"][:4],
            "window": {"since": iso(since), "until": iso(until)},
        }
        rows.append(row)
    return rows


def read_flags():
    return lf.read_flags()
