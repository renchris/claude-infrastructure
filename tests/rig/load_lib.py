#!/usr/bin/env python3
"""load_lib — the load harness's instruments and verdicts (B1 §7-§9.8, W4). Driven by lr-load-harness.sh.

  load_lib.py lock acquire|release DIR RUN PID   mkdir lock holding (pid, start ident); stale takeover
  load_lib.py prod-gate [ROOT]                   rc 3 + reason when production has open limited work
  load_lib.py prod-sids ROOT SPECS…              rc 1 when production holds a record for a rig sid (S7)
  load_lib.py run-length FAULTS HB_S BOOT_S      seconds the run needs, from the matrix (F13)
  load_lib.py preflight WINDOWS ARMS             budgets (kitty fds, coalition, memory); rc 0 | 3
  load_lib.py sample RUN                         the sampler: bands, load, census, records, focus, aborts
  load_lib.py collect RUN ARM                    arm root → ARM/members.jsonl, arm.json, lanes.json
  load_lib.py assert RUN ARM                     P1-P4, H1-H9, T1-T5 → ARM/summary.json; the arm's half line
  load_lib.py pair RUN                           power and the pair verdict → pair.json, verdict.line, rc
  load_lib.py analyze DIR…                       t_first against the load bin over saved runs (report only)

Exit codes of `pair` (§8.4 + review C8): 0 PASS · 1 FAIL · 3 NO-VERDICT · 4 SIGNAL-DEAD · 5 PASS with
power from pass length only (T2/T3), which proves nothing about recovery outcomes.

What every verdict rests on. Preconditions fail to NO-VERDICT, never PASS or FAIL: our own bound
firing, load below the premise floor, a reaper TERM of an arm process, a production cohort, a fault
that did not fire. Hard assertions are read from the world where the world can say it (the stub's own
state, live processes, transcripts), not from the daemon's records ("Own records ≠ the world"). Every
reading carries load1 and the band beside it. Stdlib only; runs as `/usr/bin/python3 -I`.
"""

from __future__ import annotations

import json
import math
import os
import re
import subprocess
import sys
import time
from typing import Any, Dict, Iterable, List, Optional, Tuple

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
HARNESS = os.environ.get("LR_HARNESS_DIR", "/tmp/lr-harness")
PROD_ROOT = os.path.expanduser("~/.reso/limit-recover/recon")

# §5 constants (REPORT.md:437-443): the target bound and the run length are built from these
W_SOFT, P_MAX, T_ATT, D_SLOTS, B_MAX = 600.0, 180.0, 900.0, 6, 300.0
WAIT_MIN_S = 3.0  # band.log does not say which of the 3/5/20 s waits applied: subtract the least (C8)
HARD_HOLDS = ("HOLD-DRAFT", "HOLD-BGWORK")
HOLD_PAGE_AGE_S = {"HOLD-DRAFT": 900.0, "HOLD-BGWORK": 1200.0}  # types.MAX_AGE_S
CLOSED_OK = ("ENGAGED", "MOVED", "IN-PLACE")
OUTCOME = ("T1", "H3", "H6")  # power must come from one of these (C8)
PASS_LENGTH = ("T2", "T3")
SOFT_DISP = ("BACKOFF", "BACKOFF_PAGE", "RETRY")
# production records that never block a run: hard holds (an operator's draft or job) and the other
# lane's parked-reboot rows (4 idle ones open since early October)
PROD_NONBLOCKING = (
    "HOLD-DRAFT",
    "HOLD-BGWORK",
    "HOLD-MENU",
    "HOLD:repo-bare",
    "HOLD:iterm",
    "PARKED-REBOOT",
)
LOAD_FLOOR = 15.0  # load1/ncpu, the premise floor (P2)
P2_SHARE = 0.70
BUDGET_FDS, BUDGET_COAL, BUDGET_MEM_GB, BUDGET_SEG_PCT = 230, 650, 8.0, 45.0
PROCS_PER_MEMBER = 4  # E (§13): zsh, stub, actuator children at peak

# H1 (F9, C6): every load hold on the staged reconciler path, in any record, event or actlog
RE_LOAD_HOLD = re.compile(
    r"HELD:load|HOLD-LOAD|capacity-admit: REFUSING[^\n]*\bload\b|/core is above the [0-9.]+/core bound"
)
RE_TOKEN = re.compile(r"run:[0-9a-f]{8}:\d{8}T\d{6}Z:[0-9a-f]{8}")
RE_TOKEN_EXPIRY = re.compile(
    r"admission token could not be redeemed|token[^\n]{0,40}expired|budget-expired|fresh gate"
)
RE_SELF_CLAIM = "another actuator holds session"
RE_EXIT = re.compile(r"^(\S+) rc=(\S+) → ([A-Z_]+)(?:/(\S+))?")
RE_SPAWN = re.compile(r"^(\S+) pid=(\d+)")


# ── small readers ────────────────────────────────────────────────────────────────────────────────


def load(path: str, default: Any = None) -> Any:
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def jsonl(path: str) -> Iterable[Dict[str, Any]]:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                try:
                    row = json.loads(ln)
                except ValueError:
                    continue
                if isinstance(row, dict):
                    yield row
    except OSError:
        return


def dump(path: str, obj: Any) -> None:
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=1, sort_keys=True)
    os.replace(tmp, path)


def append(path: str, obj: Dict[str, Any]) -> None:
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(obj, separators=(",", ":"), sort_keys=True) + "\n")


def text(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def pct(xs: List[float], q: float) -> Optional[float]:
    """Nearest rank, the rule report._p95 and rig_lib._pct use."""
    xs = sorted(x for x in xs if x is not None)
    if not xs:
        return None
    return xs[max(0, int(round(q * len(xs) + 0.5)) - 1)]


def _runq() -> Any:
    try:
        import runq  # type: ignore  # tests/rig/runq.py (W4)

        return runq
    except Exception:  # noqa: BLE001 — an instrument that cannot load reads as "no reading"
        return None


def ident(pid: int) -> str:
    rq = _runq()
    try:
        return str(rq.ident(pid) or "") if rq else ""
    except Exception:  # noqa: BLE001
        return ""


def base_of(pid: int) -> Optional[int]:
    rq = _runq()
    try:
        return rq.base_of(pid) if rq and pid > 0 else None
    except Exception:  # noqa: BLE001
        return None


def ncpu_topology() -> Tuple[int, int]:
    def sysctl(name: str) -> int:
        try:
            out = subprocess.run(
                ["/usr/sbin/sysctl", "-n", name],
                capture_output=True,
                text=True,
                timeout=10,
            ).stdout.strip()
            return int(out)
        except (OSError, ValueError, subprocess.SubprocessError):
            return 0

    n = os.cpu_count() or 1
    return n, sysctl("hw.perflevel0.logicalcpu") or n


# ── lock (C13: there is no flock on this box) ───────────────────────────────────────────────────


def lock(op: str, d: str, run: str, pid: int) -> int:
    owner = os.path.join(d, "owner.json")
    if op == "release":
        cur = load(owner, {})
        if cur.get("pid") == pid and cur.get("run") == run:
            try:
                os.unlink(owner)
                os.rmdir(d)
            except OSError:
                pass
        return 0
    me = {"pid": pid, "ident": ident(pid), "run": run, "at": time.time()}
    for _ in range(2):
        try:
            os.mkdir(d)
            dump(owner, me)
            return 0
        except FileExistsError:
            cur = load(owner, {})
            live = (
                cur.get("pid")
                and ident(int(cur["pid"])) == cur.get("ident")
                and cur.get("ident")
            )
            if live:
                print(
                    "NO-VERDICT lock: run %s (pid %s) holds %s"
                    % (cur.get("run"), cur.get("pid"), d)
                )
                return 3
            # stale: its owner is gone (or the pid now names someone else). Take it over.
            try:
                if os.path.exists(owner):
                    os.unlink(owner)
                os.rmdir(d)
            except OSError:
                pass
    print("NO-VERDICT lock: could not take %s" % d)
    return 3


# ── production gate (S7) ────────────────────────────────────────────────────────────────────────


def prod_records(root: str) -> List[Dict[str, Any]]:
    d = os.path.join(root, "sessions")
    out = []
    for n in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if n.endswith(".json") and n.count(".") == 1:
            r = load(os.path.join(d, n))
            if isinstance(r, dict):
                out.append(r)
    return out


def prod_blocking(recs: List[Dict[str, Any]]) -> List[str]:
    """Open production records kind == limited outside the hard holds and the parked-reboot lane:
    a recovery the premise bounds, which two act-mode rig daemons at 31 would compete with."""
    out = []
    for r in recs:
        if r.get("terminal") is not None or r.get("kind") != "limited":
            continue
        if (r.get("substate") or "") in PROD_NONBLOCKING:
            continue
        if (r.get("close") or {}).get("via") in CLOSED_OK:
            continue  # already recovered; only its confirmation window is open, nothing competes
        out.append(
            "%s %s/%s" % (str(r.get("sid", "?"))[:8], r.get("phase"), r.get("substate"))
        )
    return out


def prod_gate(root: str) -> int:
    block = prod_blocking(prod_records(root))
    if block:
        print(
            "NO-VERDICT production-busy: %s (retry later; never a wait)"
            % ", ".join(block[:6])
        )
        return 3
    print(
        "production gate: clear (%d records, none open-limited outside hard holds/parked-reboot)"
        % len(prod_records(root))
    )
    return 0


def prod_sids(root: str, specs: List[str]) -> int:
    want = set()
    for p in specs:
        for s in load(p, []) or []:
            want.add(s.get("sid"))
    hit = sorted(r["sid"][:8] for r in prod_records(root) if r.get("sid") in want)
    print(
        "production records for rig sids: %d%s"
        % (len(hit), (" · " + ",".join(hit)) if hit else "")
    )
    return 1 if hit else 0


# ── run length (F13) ────────────────────────────────────────────────────────────────────────────


def max_t_done(faults: Dict[str, Any]) -> float:
    """go + max T_done over the matrix: the latest death, the deepest queue position, plus T_att,
    and every hard hold's page window."""
    import rig_lib  # type: ignore

    specs = rig_lib.expand(faults)
    nonheld = [
        s for s in specs if s["expect"] not in HARD_HOLDS and not s["stale_request"]
    ]
    t0 = 0.0
    for s in specs:
        k = s["knobs"]
        t0 = max(
            t0,
            float(
                k.get("busy_for_s")
                if k.get("busy_for_s") is not None
                else k.get("die_at_s") or 0
            ),
        )
    k_max = max(0, len(nonheld) - 1)
    done = t0 + W_SOFT + P_MAX + math.ceil(k_max / float(D_SLOTS)) * T_ATT + T_ATT
    for s in specs:
        if s["expect"] in HARD_HOLDS:
            done = max(done, t0 + HOLD_PAGE_AGE_S[s["expect"]] + 2 * P_MAX)
    return done


def run_length(faults: Dict[str, Any], hb_s: float, boot_s: float) -> int:
    return int(hb_s + boot_s + max_t_done(faults) + 600)


# ── preflight budgets (§13) ─────────────────────────────────────────────────────────────────────


def kitty_pid() -> int:
    sock = os.environ.get("CC_TERM_KITTY_TO", "")
    m = re.search(r"kitty-(\d+)", sock)
    return int(m.group(1)) if m else 0


def capacity_row() -> Dict[str, Any]:
    last: Dict[str, Any] = {}
    for row in jsonl(os.path.expanduser("~/.claude/logs/capacity-alarm.jsonl")):
        last = row
    return last


def coalition(kpid: int) -> Optional[int]:
    rq = _runq()
    try:
        return len(rq.descendants(kpid)) if rq and kpid else None
    except Exception:  # noqa: BLE001
        return None


def preflight(windows: int, arms: int, kp: int = 0) -> int:
    kp = kp or kitty_pid()
    rq = _runq()
    fds = rq.fd_count(kp) if rq and kp else None
    cap = capacity_row()
    coal = cap.get("coal_true_procs")
    if not isinstance(coal, int):
        coal = coalition(kp)
    members = max(0, windows - arms)
    proj = (coal or 0) + PROCS_PER_MEMBER * members
    head, seg = cap.get("headroom_gb"), cap.get("seg_pct")
    l1 = os.getloadavg()[0]
    n, pc = ncpu_topology()
    rows = [
        (
            "kitty fds + 3×windows",
            "%s + 3×%d = %s" % (fds, windows, (fds or 0) + 3 * windows),
            "≤ %d" % BUDGET_FDS,
            fds is not None and fds + 3 * windows <= BUDGET_FDS,
        ),
        (
            "kitty coalition projection",
            "%s + %d×%d = %d" % (coal, PROCS_PER_MEMBER, members, proj),
            "< %d" % BUDGET_COAL,
            coal is not None and proj < BUDGET_COAL,
        ),
        (
            "memory headroom GB",
            str(head),
            "≥ %.0f" % BUDGET_MEM_GB,
            head is None or float(head) >= BUDGET_MEM_GB,
        ),
        (
            "compressor segments %",
            str(seg),
            "< %.0f" % BUDGET_SEG_PCT,
            seg is None or float(seg) < BUDGET_SEG_PCT,
        ),
    ]
    print(
        "preflight · load1 %.0f (%.1f/core, %d cpu, %d P) · band %s · kitty pid %s base %s"
        % (l1, l1 / n, n, pc, base_of(os.getpid()), kp or "?", base_of(kp))
    )
    ok = True
    for name, val, lim, good in rows:
        print("  %-28s %-28s %-8s %s" % (name, val, lim, "ok" if good else "REFUSE"))
        ok = ok and bool(good)
    if not ok:
        print("NO-VERDICT budget: preflight refused (retry later; never a wait)")
        return 3
    return 0


# ── the sampler ─────────────────────────────────────────────────────────────────────────────────


def _rec(root: str, sid: str) -> Optional[Dict[str, Any]]:
    return load(os.path.join(root, "state", "sessions", sid + ".json"))


def _pidfile(p: str) -> int:
    try:
        return int(open(p).read().split()[0])
    except (OSError, ValueError, IndexError):
        return 0


def _snap(rec: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if not rec:
        return {}
    return {
        "phase": rec.get("phase"),
        "sub": rec.get("substate"),
        "nea": rec.get("next_eligible_at"),
        "att": rec.get("attempt"),
        "term": (rec.get("terminal") or {}).get("outcome"),
        "esc": bool(rec.get("escalated")),
        "procs": [
            [p.get("pid"), p.get("lstart"), p.get("role")]
            for p in rec.get("procs") or []
            if isinstance(p, dict)
        ],
    }


def _focus(sock: str, roots: List[str]) -> Tuple[Optional[int], bool, Optional[int]]:
    """(focused window id, is it a rig window, the focused window's os-window id)."""
    kitten = os.environ.get(
        "LR_REAL_KITTEN", "/Applications/kitty.app/Contents/MacOS/kitten"
    )
    try:
        out = subprocess.run(
            [kitten, "@", "--to", sock, "ls"],
            capture_output=True,
            text=True,
            timeout=10,
        ).stdout
        ls = json.loads(out)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None, False, None
    for ow in ls:
        if not ow.get("is_focused"):
            continue
        for t in ow.get("tabs", []):
            if not t.get("is_focused"):
                continue
            for w in t.get("windows", []):
                if w.get("is_focused"):
                    cwd = str(w.get("cwd") or "")
                    cwd = cwd[len("/private") :] if cwd.startswith("/private/") else cwd
                    title = str(w.get("title") or "")
                    rig = any(
                        cwd == r or cwd.startswith(r + "/") for r in roots
                    ) or title.startswith("lrh-")
                    return int(w["id"]), rig, ow.get("id")
    return None, False, None


def _reaper_hits(roots: List[str], since: float) -> List[str]:
    log = os.environ.get(
        "CC_REAPER_LOG", os.path.expanduser("~/.claude/logs/cc-reaper.log")
    )
    hits = []
    try:
        if os.path.getmtime(log) < since:
            return []
        with open(log, errors="replace") as fh:
            fh.seek(max(0, os.path.getsize(log) - 512 * 1024))
            for ln in fh:
                if "TERM" in ln and any(r in ln for r in roots):
                    hits.append(ln.strip()[:200])
    except OSError:
        pass
    return hits


def sample(run: str) -> int:
    meta = load(os.path.join(run, "meta.json"), {})
    every, census_every = (
        float(meta.get("every_s", 5)),
        float(meta.get("census_every_s", 15)),
    )
    arms = meta.get("arms", {})
    roots = [a["root"] for a in arms.values()]
    specs = {
        name: load(os.path.join(a["root"], "specs.json"), []) or []
        for name, a in arms.items()
    }
    hp, hid = int(meta.get("harness_pid") or 0), meta.get("harness_ident") or ""
    deadline = float(meta.get("deadline") or time.time() + 3600)
    started = float(meta.get("started") or time.time())
    sock = meta.get("sock", "")
    kp = int(meta.get("kitty_pid") or 0)
    n, pc = int(meta.get("ncpu") or 1), int(meta.get("pcores") or 1)
    rq = _runq()
    last_census, last_slow = 0.0, 0.0
    last: Dict[str, Any] = {}
    focus_home: Optional[int] = meta.get("focus_home")
    thefts = 0
    stop = os.path.join(run, "sampler.stop")
    reason = ""
    while True:
        now = time.time()
        if os.path.exists(stop):
            break
        if os.path.exists(os.path.join(HARNESS, "OFF")):
            reason = "OFF"
        elif now > deadline:
            reason = "deadline"
        elif hp and hid and ident(hp) != hid:
            reason = "harness-gone"
        l1, l5, l15 = os.getloadavg()
        row: Dict[str, Any] = {
            "t": round(now, 2),
            "load": [round(l1, 1), round(l5, 1), round(l15, 1)],
            "ncpu": n,
            "pc": pc,
        }
        gap4 = l1 >= 280
        if rq and (
            now - last_census >= census_every or (gap4 and now - last_census >= every)
        ):
            t1 = time.monotonic()
            c = rq.census()
            row["runq"] = (c or {}).get("runq")
            row["runq_s"] = round(time.monotonic() - t1, 2)
            row["gap4"] = gap4
            last_census = now
        own = load(os.path.join(run, "loadgen.ctl.own"))
        if own:
            row["own"] = {k: own.get(k) for k in ("bg", "ut", "df")}
        row["arms"] = {}
        for name, a in arms.items():
            r = a["root"]
            sup, dmn = (
                _pidfile(os.path.join(r, "supervisor.pid")),
                _pidfile(os.path.join(r, "state", "daemon.pid")),
            )
            kids = [base_of(p) for p in (rq.descendants(sup) if rq and sup else [])]
            kids = [k for k in kids if k is not None]
            hb = load(os.path.join(r, "state", "heartbeat"), {}) or {}
            row["arms"][name] = {
                "sup": [sup, base_of(sup)],
                "daemon": [dmn, base_of(dmn)],
                "kids": [
                    len(kids),
                    min(kids) if kids else None,
                    max(kids) if kids else None,
                ],
                "pass": [hb.get("pass_seq"), hb.get("pass_at")],
            }
            for s in specs[name]:
                snap = _snap(_rec(r, s["sid"]))
                key = name + s["sid"]
                if snap and snap != last.get(key):
                    last[key] = snap
                    append(
                        os.path.join(run, "recs-%s.jsonl" % name),
                        dict(snap, t=round(now, 2), sid=s["sid"]),
                    )
        if kp:
            row["kitty"] = [kp, base_of(kp), rq.fd_count(kp) if rq else None]
        if now - last_slow >= 30:
            last_slow = now
            if kp:
                row["coal"] = coalition(kp)
            if not reason and prod_blocking(prod_records(PROD_ROOT)):
                reason = "production-busy"
            hits = _reaper_hits(roots, started)
            if hits and not reason:
                reason = "reaper"
                append(os.path.join(run, "reaper.jsonl"), {"t": now, "hits": hits[:5]})
        k = row.get("kitty") or [None, None, None]
        if not reason and k[2] is not None and k[2] > BUDGET_FDS:
            reason = "budget:kitty-fds"
        if (
            not reason
            and isinstance(row.get("coal"), int)
            and row["coal"] >= BUDGET_COAL
        ):
            reason = "budget:coalition"
        for r in roots:
            if not reason and os.path.exists(
                os.path.join(r, "state", "containment.hit")
            ):
                reason = "containment"
        # S5: focus. A rig window holding focus is a theft: count it and hand focus back.
        if sock:
            wid, rig, _ow = _focus(sock, roots)
            if wid is not None and not rig:
                focus_home = wid
            elif wid is not None and rig:
                thefts += 1
                append(
                    os.path.join(run, "focus.jsonl"),
                    {"t": now, "wid": wid, "back_to": focus_home},
                )
                if focus_home:
                    kitten = os.environ.get(
                        "LR_REAL_KITTEN",
                        "/Applications/kitty.app/Contents/MacOS/kitten",
                    )
                    subprocess.run(
                        [
                            kitten,
                            "@",
                            "--to",
                            sock,
                            "focus-window",
                            "--match",
                            "id:%d" % focus_home,
                        ],
                        capture_output=True,
                        timeout=10,
                    )
            row["thefts"] = thefts
        append(os.path.join(run, "samples.jsonl"), row)
        if reason:
            break
        time.sleep(max(0.5, every - (time.time() - now)))
    if reason and reason not in ("OFF",):
        dump(os.path.join(run, "abort.json"), {"reason": reason, "t": time.time()})
        for r in roots:
            try:
                open(os.path.join(r, "stop"), "a").close()
            except OSError:
                pass
    if reason == "OFF":
        dump(os.path.join(run, "abort.json"), {"reason": "OFF", "t": time.time()})
    # S6: the generator's stop must not depend on its own GIL; kill it from here by verified ident
    ctl = os.path.join(run, "loadgen.ctl")
    if os.path.exists(ctl + ".pid"):
        subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                os.path.join(HERE, "loadgen.py"),
                "kill",
                "--ctl",
                ctl,
            ],
            capture_output=True,
            timeout=30,
        )
    return 0


# ── collect (§7) ────────────────────────────────────────────────────────────────────────────────


def _epoch_lstart(s: str) -> Optional[float]:
    try:
        return time.mktime(
            time.strptime(" ".join(str(s).split()), "%a %b %d %H:%M:%S %Y")
        )
    except (ValueError, TypeError):
        return None


def _band_lines(root: str) -> List[Tuple[float, Optional[int]]]:
    out = []
    for ln in text(os.path.join(root, "state", "band.log")).splitlines():
        parts = ln.split()
        if not parts or not parts[0].isdigit():
            continue
        m = re.search(r"pri=(\d+)", ln)
        out.append((float(parts[0]), int(m.group(1)) if m else None))
    return out


def _band_calls(root: str) -> List[Tuple[float, int, Optional[int], str]]:
    out = []
    for ln in text(os.path.join(root, "state", "band-calls.log")).splitlines():
        p = ln.split("\t")
        if len(p) >= 4 and p[0].isdigit():
            out.append(
                (
                    float(p[0]),
                    int(p[1]) if p[1].isdigit() else 0,
                    int(p[2]) if p[2].lstrip("-").isdigit() else None,
                    p[3],
                )
            )
    return out


def _nearest(
    samples: List[Dict[str, Any]], t: float, key: str
) -> Optional[Dict[str, Any]]:
    best, bd = None, 1e18
    for s in samples:
        if key in s and abs(s["t"] - t) < bd:
            best, bd = s, abs(s["t"] - t)
    return best if bd <= 60 else None


def _bins(samples: List[Dict[str, Any]], t: float) -> Dict[str, Any]:
    s = _nearest(samples, t, "load")
    c = _nearest(samples, t, "runq")
    out: Dict[str, Any] = {}
    if s:
        lc = s["load"][0] / float(s.get("ncpu") or 1)
        out["load1"] = s["load"][0]
        out["load_bin"] = (
            "<15"
            if lc < 15
            else "15-20"
            if lc < 20
            else "20-30"
            if lc < 30
            else "30-40"
            if lc < 40
            else ">=40"
        )
        k = s.get("kitty") or [None, None]
        out["kitty_napped"] = k[1] is not None and k[1] < 31
    if c and c.get("runq") is not None:
        r31 = float((c["runq"] or {}).get("31", 0)) / float(c.get("pc") or 1)
        out["r31_per_p"] = round(r31, 2)
        out["r31_bin"] = (
            "r31<1"
            if r31 < 1
            else "r31-low"
            if r31 < 2
            else "r31-mid"
            if r31 < 4
            else "r31-high"
        )
    return out


def _fault_fired(
    spec: Dict[str, Any],
    st: Dict[str, Any],
    ev_text: str,
    act_text: str,
    kd: List[List[str]],
    wid: str,
    faults_log: str,
) -> Optional[bool]:
    """P3: did this member's fault actually fire? None = the member carries no fault."""
    k = spec.get("knobs") or {}
    checks: List[bool] = []
    if k.get("kitty_delay_s"):
        checks.append(any(r[1] == wid and r[2] != "fail" for r in kd))
    if k.get("send_text_fail_n"):
        checks.append(
            sum(1 for r in kd if r[1] == wid and r[2] == "fail")
            >= int(k["send_text_fail_n"])
        )
    if k.get("composer_unreadable_s"):
        checks.append(
            "HELD:composer-unreadable" in act_text or "composer-unreadable" in ev_text
        )
    if k.get("busy_for_s") is not None:
        checks.append(bool(st.get("busy_until")))
    if k.get("goal_meta_after_limit"):
        checks.append(bool(st.get("goal_meta_at")))
    if k.get("heavy_lead_subagents"):
        checks.append(bool(st.get("subagents_written")))
    if k.get("first_turn"):
        checks.append(bool(st.get("first_turn_done")))
    if k.get("slow_boots") or isinstance(k.get("boot_delay_s"), list):
        checks.append(any(b[1] > 180 for b in st.get("boots") or []))
    if spec.get("daemon_fault"):
        checks.append(
            any(
                ln.split("\t")[1:4:2] == [spec["sid"], "fired"]
                for ln in faults_log.splitlines()
                if ln.count("\t") >= 3
            )
        )
    if not checks:
        return None
    return all(checks)


def _live_holders(root: str, sid: str) -> Tuple[int, int]:
    """H9 from the world: (live processes holding sid, account stores holding a live transcript)."""
    rq = _runq()
    holders, stores = set(), 0
    for cfg in sorted(os.listdir(root)):
        d = os.path.join(root, cfg)
        if not (cfg.startswith("cfg-") and os.path.isdir(d)):
            continue
        sd = os.path.join(d, "sessions")
        for n in os.listdir(sd) if os.path.isdir(sd) else []:
            row = load(os.path.join(sd, n), {}) or {}
            pid = int(row.get("pid") or 0)
            if row.get("sessionId") != sid or pid <= 0:
                continue
            try:
                os.kill(pid, 0)
            except OSError:
                continue
            argv = rq.argv(pid) if rq else sid
            if sid in (argv or ""):
                holders.add(pid)
        pd = os.path.join(d, "projects")
        for slug in os.listdir(pd) if os.path.isdir(pd) else []:
            if os.path.exists(os.path.join(pd, slug, sid + ".jsonl")):
                stores += 1
                break
    return len(holders), stores


def _tokens(root: str, sid: str) -> Dict[str, int]:
    """H7: each submit token, counted over every user record in every store's transcript."""
    seen: Dict[str, int] = {}
    for cfg in sorted(os.listdir(root)):
        pd = os.path.join(root, cfg, "projects")
        if not (cfg.startswith("cfg-") and os.path.isdir(pd)):
            continue
        for slug in os.listdir(pd):
            p = os.path.join(pd, slug, sid + ".jsonl")
            for row in jsonl(p):
                if row.get("type") != "user" or row.get("isMeta"):
                    continue
                c = row.get("message", {}).get("content")
                body = c if isinstance(c, str) else json.dumps(c)
                for tok in set(RE_TOKEN.findall(body or "")):
                    seen[tok] = seen.get(tok, 0) + 1
    return seen


def collect(run: str, arm: str) -> int:
    meta = load(os.path.join(run, "meta.json"), {})
    root = meta["arms"][arm]["root"]
    out = os.path.join(run, arm)
    os.makedirs(out, exist_ok=True)
    specs = load(os.path.join(root, "specs.json"), []) or []
    samples = list(jsonl(os.path.join(run, "samples.jsonl")))
    snaps = list(jsonl(os.path.join(run, "recs-%s.jsonl" % arm)))
    events = list(jsonl(os.path.join(root, "state", "events.jsonl")))
    lst: Dict[int, float] = {}
    for s in snaps:
        for pid, ls, _role in s.get("procs") or []:
            e = _epoch_lstart(ls)
            if pid and e:
                lst[int(pid)] = e
    wid_of = {}
    for ln in text(os.path.join(root, "windows.sid")).splitlines():
        p = ln.split("\t")
        if len(p) == 2:
            wid_of[p[1]] = p[0]
    kd = [
        ln.split("\t")
        for ln in text(os.path.join(root, "state", "kitty-delay.log")).splitlines()
        if ln.count("\t") >= 3
    ]
    faults_log = text(os.path.join(root, "state", "faults.log"))
    pages = text(os.path.join(root, "state", "pages.log"))
    held = (load(os.path.join(root, "state", "held.json"), {}) or {}).get(
        "held_since", {}
    )
    adir = os.path.join(root, "state", "actlogs")
    actlogs = sorted(os.listdir(adir)) if os.path.isdir(adir) else []
    members = []
    for spec in specs:
        sid = spec["sid"]
        st = load(os.path.join(root, "tmp", "stub", sid + ".json"), {}) or {}
        rec = _rec(root, sid) or {}
        mine = [e for e in events if e.get("sid") == sid]
        ev_text = "\n".join(str(e.get("detail", "")) for e in mine) + json.dumps(rec)
        act_text = "\n".join(
            text(os.path.join(adir, a)) for a in actlogs if a.startswith(sid[:8] + ".")
        )
        spawns, exits = [], []
        for e in mine:
            if e.get("ev") == "spawn":
                m = RE_SPAWN.match(str(e.get("detail", "")))
                if m:
                    pid = int(m.group(2))
                    spawns.append(
                        {
                            "act": m.group(1),
                            "pid": pid,
                            "t_ev": e["t"],
                            "t": lst.get(pid, e["t"]),
                        }
                    )
            elif e.get("ev") == "exit":
                m = RE_EXIT.match(str(e.get("detail", "")))
                if m:
                    exits.append(
                        {
                            "act": m.group(1),
                            "rc": m.group(2),
                            "disp": m.group(3),
                            "sub": m.group(4),
                            "t": e["t"],
                        }
                    )
        attempts = []
        used: set = set()
        for sp in spawns:
            ex = next(
                (
                    x
                    for i, x in enumerate(exits)
                    if i not in used and x["act"] == sp["act"] and x["t"] >= sp["t_ev"]
                ),
                None,
            )
            if ex is not None:
                used.add(exits.index(ex))
            att = {
                "act": sp["act"],
                "pid": sp["pid"],
                "t_spawn": sp["t"],
                "t_exit": ex["t"] if ex else None,
                "rc": ex["rc"] if ex else None,
                "disp": ex["disp"] if ex else None,
                "sub": ex["sub"] if ex else None,
            }
            att.update(_bins(samples, sp["t"]))
            # the record's own promise for this exit (next_eligible_at), read from the sampler's snapshots
            if ex:
                nea = next(
                    (
                        s.get("nea")
                        for s in snaps
                        if s.get("sid") == sid
                        and s["t"] >= ex["t"] - 1
                        and s.get("nea")
                    ),
                    None,
                )
                att["nea"] = nea
            attempts.append(att)
        tl, close, term = (
            rec.get("timeline") or {},
            rec.get("close") or {},
            rec.get("terminal") or {},
        )
        t0 = st.get("died_at")
        holders, stores = _live_holders(root, sid)
        toks = _tokens(root, sid)
        k = spec.get("knobs") or {}
        draft = k.get("draft") or {}
        m = {
            "sid": sid,
            "group": spec.get("group"),
            "expect": spec.get("expect"),
            "scope": spec.get("scope") or {},
            "kind": rec.get("kind"),
            "t0": t0,
            "t_detect": tl.get("detected"),
            "t_first": attempts[0]["t_spawn"] if attempts else None,
            "attempts": attempts,
            "closed_via": close.get("via"),
            "closed_at": close.get("at"),
            "terminal": term.get("outcome"),
            "terminal_at": term.get("at"),
            "escalated": bool(rec.get("escalated"))
            or any(x["disp"] in ("ESCALATED", "IMPOSSIBLE") for x in exits)
            or term.get("outcome") == "IMPOSSIBLE",
            "open_sub": rec.get("substate") if not term else None,
            "load_holds": len(RE_LOAD_HOLD.findall(ev_text + "\n" + act_text)),
            "self_claim": act_text.count(RE_SELF_CLAIM),
            "token_expiry": len(RE_TOKEN_EXPIRY.findall(act_text)),
            "tokens_dup": sorted(t for t, c in toks.items() if c > 1),
            "tokens": len(toks),
            "holders": holders,
            "stores": stores,
            "draft_ok": None
            if not draft
            else (
                st.get("draft_now") == draft.get("text", "draft")
                and not st.get("draft_mut")
            ),
            "held_since": held.get(sid),
            "paged_at": next(
                (
                    float(ln.split("\t")[0])
                    for ln in pages.splitlines()
                    if (sid[:8] in ln or sid in ln) and ln.split("\t")[0].isdigit()
                ),
                None,
            ),
            "fault_fired": _fault_fired(
                spec, st, ev_text, act_text, kd, wid_of.get(sid, "?"), faults_log
            ),
            "boots": st.get("boots") or [],
            "admit_waits": [
                e["t"] for e in mine if e.get("ev") in ("admit-refused", "boot-slots")
            ],
        }
        members.append(m)
    with open(os.path.join(out, "members.jsonl"), "w") as fh:
        for m in members:
            fh.write(json.dumps(m, sort_keys=True) + "\n")
    bl = _band_lines(root)
    calls = _band_calls(root)
    rr = load(os.path.join(root, "rig-result.json"), {}) or {}
    sdir = os.path.join(root, "state", "sessions")
    want = {s["sid"] for s in specs} | {
        s["sid"] for s in load(os.path.join(root, "specs-extra.json"), []) or []
    }
    foreign = [
        n
        for n in (os.listdir(sdir) if os.path.isdir(sdir) else [])
        if n.endswith(".json") and n.count(".") == 1 and n[:-5] not in want
    ]
    passes = sorted(
        {
            a["arms"][arm]["pass"][1]
            for a in samples
            if a.get("arms", {}).get(arm, {}).get("pass", [None, None])[1]
        }
    )
    got = str(rr.get("got") or "")
    sup_times = text(os.path.join(root, "state", "supervisor.times")).split()
    facts = {
        "arm": arm,
        "band": meta["arms"][arm].get("band"),
        "tree": meta["arms"][arm].get("tree"),
        "band_log": [[t, p] for t, p in bl],
        "band_calls": [[t, pid, b, role] for t, pid, b, role in calls],
        "pass_at": passes,
        "foreign": len(foreign),
        "refusal_rc": rr.get("refusal_rc"),
        "drive_rc": rr.get("drive_rc"),
        "audit_rc": rr.get("audit_rc"),
        "verdict": rr.get("verdict"),
        "double_typer": _num(got, "double-typer"),
        "split_brain": _num(got, "split-brain"),
        "lost_records": _num(got, "lost-records"),
        "abstains": sum(1 for e in events if e.get("ev") == "abstain"),
        "shim_calls": len(text(os.path.join(root, "state", "shims.log")).splitlines()),
        "supervisor_times": sup_times,
        "typed_relaunch": "CC_PANE_SUCCESSOR=off" in text(os.path.join(root, "env.sh")),
        # rig_lib.t5, written only for a matrix with a move_batch (W4b)
        "t5": rr.get("t5"),
        "end": time.time(),
        "start": float(meta.get("started") or 0),
    }
    dump(os.path.join(out, "arm.json"), facts)
    dump(os.path.join(out, "lanes.json"), lanes(members))
    print(
        "collect %s: %d members · %d band.log lines · %d in-path band rows · foreign %d"
        % (arm, len(members), len(bl), len(calls), len(foreign))
    )
    return 0


def _num(line: str, key: str) -> Optional[int]:
    m = re.search(re.escape(key) + r" (\d+)", line)
    return int(m.group(1)) if m else None


def lanes(members: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Per actuator letter and per kind: p50/p90/max of detect→first attempt and attempt→engaged."""
    by: Dict[str, Dict[str, List[float]]] = {}
    for m in members:
        if not m["attempts"]:
            continue
        a0 = m["attempts"][0]
        for key in ("act:" + a0["act"], "kind:%s" % m.get("kind")):
            d = by.setdefault(key, {"detect_to_attempt": [], "attempt_to_engaged": []})
            if m.get("t_detect") is not None:
                d["detect_to_attempt"].append(a0["t_spawn"] - m["t_detect"])
            if m.get("closed_at") is not None and m.get("closed_via") in CLOSED_OK:
                d["attempt_to_engaged"].append(m["closed_at"] - a0["t_spawn"])
    return {
        k: {
            q: {
                "p50": pct(v, 0.5),
                "p90": pct(v, 0.9),
                "max": max(v) if v else None,
                "n": len(v),
            }
            for q, v in d.items()
        }
        for k, d in by.items()
    }


# ── assert (§8) ─────────────────────────────────────────────────────────────────────────────────


def _mode(expect: Dict[str, str], a: str) -> str:
    return expect.get(a, "hard")


def _gaps(ts: List[float]) -> List[float]:
    ts = sorted(ts)
    return [b - a for a, b in zip(ts, ts[1:])]


def _boundary_after(bounds: List[float], t: float, k: int) -> Optional[float]:
    after = [b for b in bounds if b >= t]
    return after[k - 1] if len(after) >= k else None


def assess(run: str, arm: str) -> int:
    meta = load(os.path.join(run, "meta.json"), {})
    d = os.path.join(run, arm)
    members = list(jsonl(os.path.join(d, "members.jsonl")))
    facts = load(os.path.join(d, "arm.json"), {}) or {}
    samples = list(jsonl(os.path.join(run, "samples.jsonl")))
    expect = (
        load(meta.get("expect_file") or os.path.join(HERE, "load-expect.json"), {})
        or {}
    )
    expect = {k: v for k, v in expect.items() if not k.startswith("_")}
    band = facts.get("band") or "inherit"
    want = 31 if band == "inherit" else 20
    pre: Dict[str, Tuple[bool, str]] = {}
    # P1: bands pinned, read in the call path (F14). Cure: 100% of band.log at 31 and every in-path
    # read ≥ 31. Red: the daemon and the placer at 20.
    bl = [p for _t, p in facts.get("band_log", []) if p is not None]
    calls = facts.get("band_calls", [])
    daemon = [
        s["arms"][arm]["daemon"][1]
        for s in samples
        if s.get("arms", {}).get(arm, {}).get("daemon", [0, None])[1] is not None
    ]
    if want == 31:
        bad_bl = [p for p in bl if p < 31]
        bad_calls = [c for c in calls if c[2] is not None and c[2] < 31]
        ok = (
            bool(bl or daemon)
            and not bad_bl
            and not bad_calls
            and all(x >= 31 for x in daemon)
        )
        why = "band.log %d/%d at 31 · in-path %d/%d ≥31 · daemon samples %d/%d ≥31" % (
            len(bl) - len(bad_bl),
            len(bl),
            len(calls) - len(bad_calls),
            len(calls),
            sum(1 for x in daemon if x >= 31),
            len(daemon),
        )
    else:
        placer = [c for c in calls if c[3] == "placer" and c[2] is not None]
        ok = (
            bool(bl or daemon)
            and all(p <= 20 for p in bl)
            and all(x <= 20 for x in daemon)
            and all(c[2] <= 20 for c in placer)
        )
        why = "band.log %d/%d ≤20 · placer %d/%d ≤20 · daemon samples %d/%d ≤20" % (
            sum(1 for p in bl if p <= 20),
            len(bl),
            sum(1 for c in placer if c[2] <= 20),
            len(placer),
            sum(1 for x in daemon if x <= 20),
            len(daemon),
        )
    pre["P1"] = (ok, why)
    # P2 (F7): load1/ncpu ≥ 15 and ≥ 1 runnable base-31 thread per P-core on ≥ 70% of census
    # samples, with sampler gaps over 3× the interval under 10% of the run
    cs = [s for s in samples if s.get("runq") is not None]
    good = [
        s
        for s in cs
        if s["load"][0] / float(s.get("ncpu") or 1) >= LOAD_FLOOR
        and float((s["runq"] or {}).get("31", 0)) / float(s.get("pc") or 1) >= 1.0
    ]
    every = float(meta.get("every_s", 5))
    ts = [s["t"] for s in samples]
    gaps = _gaps(ts)
    span = (ts[-1] - ts[0]) if len(ts) > 1 else 0.0
    gap_s = sum(g for g in gaps if g > 3 * every)
    share = len(good) / float(len(cs)) if cs else 0.0
    pre["P2"] = (
        bool(cs) and share >= P2_SHARE and (span <= 0 or gap_s / span < 0.10),
        "%d%% of %d census samples ≥15/core with r31 ≥1/P · gaps %.0fs of %.0fs"
        % (round(100 * share), len(cs), gap_s, span),
    )
    # P3: every fault fired; > 20% not fired ⇒ NO-VERDICT, and a non-firing member's own rows too
    fz = [m for m in members if m.get("fault_fired") is not None]
    nf = [m for m in fz if not m["fault_fired"]]
    pre["P3"] = (
        not fz or len(nf) / float(len(fz)) <= 0.20,
        "faults %d/%d fired%s"
        % (
            len(fz) - len(nf),
            len(fz),
            (" · not: " + ",".join(m["group"] for m in nf)) if nf else "",
        ),
    )
    # P4: rig sane
    p4 = (
        facts.get("drive_rc")
        in (0, 1, 4)  # 1 = the rig's own timeout, 4 = stopped early
        and facts.get("foreign", 1) == 0
        and facts.get("refusal_rc") == 0
        and facts.get("verdict") != "NO-VERDICT containment"
    )
    pre["P4"] = (
        bool(p4),
        "drive rc %s · foreign %s · refusal rc %s%s"
        % (
            facts.get("drive_rc"),
            facts.get("foreign"),
            facts.get("refusal_rc"),
            " · containment"
            if facts.get("verdict") == "NO-VERDICT containment"
            else "",
        ),
    )
    abort = load(os.path.join(run, "abort.json"))
    if abort:
        pre["P0"] = (False, "aborted: %s" % abort.get("reason"))
    # ── per-member assertions ─────────────────────────────────────────────────────────────────
    nfids = {m["sid"] for m in nf}
    live = [
        m
        for m in members
        if m["sid"] not in nfids
        and m.get("t0") is not None
        or m.get("expect") in HARD_HOLDS
    ]
    nonheld = sorted(
        [
            m
            for m in live
            if m.get("expect") not in HARD_HOLDS and m.get("t0") is not None
        ],
        key=lambda m: m["t0"],
    )
    bounds = sorted(
        set([t for t, _p in facts.get("band_log", [])] or facts.get("pass_at", []))
    )
    p_obs = max([g - WAIT_MIN_S for g in _gaps(bounds)] or [0.0])
    end = float(facts.get("end") or time.time())
    rows: Dict[str, Dict[str, Optional[bool]]] = {
        a: {} for a in ("H2", "H3", "H4", "H6", "H7", "H8", "H9", "T1", "T3")
    }
    detail: Dict[str, List[str]] = {a: [] for a in rows}
    for m in nonheld:
        # k_r (C17): overdue non-held records detected earlier — still waiting for a first attempt
        det = m.get("t_detect")
        k = sum(
            1
            for o in nonheld
            if o is not m
            and o.get("t_detect") is not None
            and det is not None
            and o["t_detect"] < det
            and (o.get("t_first") is None or o["t_first"] > det)
        )
        bound = W_SOFT + P_MAX + math.ceil(k / float(D_SLOTS)) * T_ATT
        t_done = m["t0"] + bound + T_ATT
        m["k"], m["bound"], m["t_done"] = k, bound, t_done
        if m.get("t_first") is None and end < m["t0"] + bound:
            rows["T1"][m["sid"]] = (
                None  # not attempted yet, and its bound has not passed
            )
        else:
            rows["T1"][m["sid"]] = (
                m.get("t_first") is not None and m["t_first"] - m["t0"] <= bound
            )
        if end < t_done and m.get("closed_via") not in CLOSED_OK:
            rows["H3"][m["sid"]] = (
                None  # the arm stopped watching before T_done: no verdict
            )
        else:
            rows["H3"][m["sid"]] = (
                m.get("closed_via") in CLOSED_OK
                and m.get("closed_at") is not None
                and m["closed_at"] <= t_done
            )
        if m.get("expect") == "ENGAGED":
            rows["H2"][m["sid"]] = not m.get("escalated")
        # H6 (C3/F8): BACKOFF/RETRY only. The daemon's own promise is ≤ 300 s for a soft class, and the
        # next spawn comes by the 2nd pass boundary after it, past any wait an admission event names.
        ok6: Optional[bool] = True
        for i, a in enumerate(m["attempts"]):
            if a.get("disp") not in SOFT_DISP or a.get("t_exit") is None:
                continue
            promise = a.get("nea") or a["t_exit"] + (
                10.0 if a["disp"] == "RETRY" else B_MAX
            )
            if promise - a["t_exit"] > B_MAX + 1:
                ok6 = False
                detail["H6"].append(
                    "%s promise %.0fs" % (m["sid"][:8], promise - a["t_exit"])
                )
                continue
            nxt = m["attempts"][i + 1] if i + 1 < len(m["attempts"]) else None
            waits = [
                w
                for w in m.get("admit_waits", [])
                if w >= promise and (nxt is None or w <= nxt["t_spawn"])
            ]
            ref = max([promise] + waits)
            due = _boundary_after(bounds, ref, 2)
            if nxt is None:
                if (
                    due is not None
                    and due < end
                    and m.get("closed_via") not in CLOSED_OK
                ):
                    ok6 = False
                    detail["H6"].append(
                        "%s no retry after %s" % (m["sid"][:8], a["disp"])
                    )
            elif due is not None and nxt["t_spawn"] > due + 1:
                ok6 = False
                detail["H6"].append(
                    "%s retry %.0fs late" % (m["sid"][:8], nxt["t_spawn"] - due)
                )
        rows["H6"][m["sid"]] = ok6
        rows["T3"][m["sid"]] = all(
            (a["t_exit"] - a["t_spawn"]) <= T_ATT
            for a in m["attempts"]
            if a.get("t_exit") is not None
        )
    for m in members:
        if m["sid"] in nfids:
            continue  # its fault never fired: its own rows are NO-VERDICT (P3)
        if m.get("expect") in HARD_HOLDS:
            # H4 (C4/C5): still open, never IMPOSSIBLE, paged by the 2nd pass after entry + max age
            hs = m.get("held_since")
            ok4: Optional[bool] = m.get("terminal") is None and not m.get("escalated")
            if hs is None:
                ok4 = None if ok4 else ok4
            else:
                due = _boundary_after(bounds, hs + HOLD_PAGE_AGE_S[m["expect"]], 2)
                if due is None or due > end:
                    ok4 = (
                        None if ok4 else ok4
                    )  # the window closed before the page was due
                elif ok4:
                    ok4 = m.get("paged_at") is not None and m["paged_at"] <= due + 1
            rows["H4"][m["sid"]] = ok4
        if m.get("draft_ok") is not None:
            rows["H8"][m["sid"]] = bool(m["draft_ok"])
        rows["H7"][m["sid"]] = not m.get("tokens_dup")
        rows["H9"][m["sid"]] = (
            m.get("holders", 0) <= 1 and m.get("stores", 0) == 1
            if m.get("expect") != "NOT_NEEDED"
            else None
        )
    res: Dict[str, Dict[str, Any]] = {}

    def verdict(a: str, oks: Dict[str, Optional[bool]], scope_name: str = "") -> None:
        vals = [v for v in oks.values() if v is not None]
        mode = _mode(expect, a) if not scope_name else scope_name
        if not oks:
            v = "N/A"  # no member this assertion applies to (e.g. H8 without a draft member)
        elif not vals:
            v = "NO-VERDICT"
        elif all(vals):
            v = "PASS" if mode == "hard" else "XPASS"
        else:
            v = "FAIL" if mode == "hard" else "XFAIL"
        key = a if not scope_name else "%s[%s]" % (a, scope_name.split(":", 1)[-1])
        res[key] = {
            "v": v,
            "mode": mode,
            "n": len(vals),
            "fail": [s[:8] for s, x in oks.items() if x is False],
        }

    for a, oks in rows.items():
        plain = {
            s: v
            for s, v in oks.items()
            if a not in (_member(members, s).get("scope") or {})
        }
        verdict(a, plain)
        scoped: Dict[str, Dict[str, Optional[bool]]] = {}
        for s, v in oks.items():
            sc = (_member(members, s).get("scope") or {}).get(a)
            if sc:
                scoped.setdefault(sc, {})[s] = v
        for sc, o in scoped.items():
            verdict(a, o, sc)
    # arm-level assertions
    lh = sum(m.get("load_holds", 0) for m in members)
    typed = bool(facts.get("typed_relaunch"))
    res["H1"] = {
        "v": "PASS" if lh == 0 else "FAIL",
        "mode": "hard" if not typed else "report",
        "n": lh,
        "fail": [m["sid"][:8] for m in members if m.get("load_holds")],
    }
    if typed:
        res["H1"]["v"] = (
            "REPORT"  # the typed-relaunch arm reports its load holds separately (C6/F9/F11)
        )
    h5 = [
        facts.get("double_typer"),
        facts.get("split_brain"),
        facts.get("lost_records"),
    ]
    res["H5"] = {
        "v": "NO-VERDICT"
        if any(x is None for x in h5)
        else ("PASS" if not any(h5) else "FAIL"),
        "mode": "hard",
        "n": 3,
        "fail": []
        if not any(x for x in h5 if x)
        else ["double-typer %s split-brain %s lost-records %s" % tuple(h5)],
    }
    prod_gap = float(meta.get("prod_max_gap_s") or 0.0)
    t2 = max(p_obs, prod_gap - WAIT_MIN_S if prod_gap else 0.0)
    mode2 = _mode(expect, "T2")
    res["T2"] = {
        "v": ("PASS" if t2 <= P_MAX else "FAIL")
        if mode2 == "hard"
        else ("XPASS" if t2 <= P_MAX else "XFAIL"),
        "mode": mode2,
        "n": len(bounds),
        "p_obs": round(p_obs, 1),
        "prod_gap": prod_gap,
    }
    if not bounds:
        res["T2"]["v"] = "NO-VERDICT"
    sc = sum(m.get("self_claim", 0) for m in members)
    mode4 = _mode(expect, "T4")
    res["T4"] = {
        "v": ("PASS" if sc == 0 else "FAIL")
        if mode4 == "hard"
        else ("XPASS" if sc == 0 else "XFAIL"),
        "mode": mode4,
        "n": sc,
    }
    # T5 from the rig's own reading (rig_lib.t5): NO-VERDICT unless a queued member turned limited
    t5 = facts.get("t5") if isinstance(facts.get("t5"), dict) else {}
    mode5, v5 = _mode(expect, "T5"), str(t5.get("v") or "NO-VERDICT")
    if v5 in ("PASS", "FAIL") and mode5 != "hard":
        v5 = "X" + v5
    res["T5"] = {
        "v": v5 if v5 in ("PASS", "FAIL", "XPASS", "XFAIL") else "NO-VERDICT",
        "mode": mode5,
        "n": int(t5.get("n") or 0),
        "fail": list(t5.get("fail") or []),
        "why": "" if t5 else "no move_batch in this matrix (W4b)",
    }
    pre_ok = all(v[0] for v in pre.values())
    hard_fail = [a for a, r in res.items() if r["mode"] == "hard" and r["v"] == "FAIL"]
    hard_nv = [
        a for a, r in res.items() if r["mode"] == "hard" and r["v"] == "NO-VERDICT"
    ]
    summary = {
        "arm": arm,
        "band": want,
        "pre": {k: {"ok": v[0], "why": v[1]} for k, v in pre.items()},
        "pre_ok": pre_ok,
        "res": res,
        "hard_fail": hard_fail,
        "hard_nv": hard_nv,
        "detail": {k: v for k, v in detail.items() if v},
        "p_obs": p_obs,
        "members": [
            {
                k: m.get(k)
                for k in ("sid", "group", "t0", "t_first", "bound", "k", "closed_via")
            }
            for m in members
        ],
        "line": arm_line(arm, want, pre, res, members, samples, facts, meta),
    }
    dump(os.path.join(d, "summary.json"), summary)
    print(summary["line"])
    return 0 if pre_ok and not hard_fail else (3 if not pre_ok else 1)


def _member(members: List[Dict[str, Any]], sid: str) -> Dict[str, Any]:
    return next((m for m in members if m["sid"] == sid), {})


def arm_line(
    arm: str,
    want: int,
    pre: Dict[str, Tuple[bool, str]],
    res: Dict[str, Dict[str, Any]],
    members: List[Dict[str, Any]],
    samples: List[Dict[str, Any]],
    facts: Dict[str, Any],
    meta: Dict[str, Any],
) -> str:
    loads = [s["load"][0] / float(s.get("ncpu") or 1) for s in samples]
    r31 = [
        float((s["runq"] or {}).get("31", 0)) / float(s.get("pc") or 1)
        for s in samples
        if s.get("runq") is not None
    ]
    bl = [p for _t, p in facts.get("band_log", []) if p is not None]
    first = [
        m["attempts"][0]["t_spawn"] - m["t_detect"]
        for m in members
        if m["attempts"] and m.get("t_detect") is not None
    ]
    eng = [
        m["closed_at"] - m["attempts"][0]["t_spawn"]
        for m in members
        if m["attempts"] and m.get("closed_at") and m.get("closed_via") in CLOSED_OK
    ]
    hard = [
        a
        for a in sorted(res)
        if a.startswith("H") and res[a]["mode"] == "hard" and res[a]["v"] != "N/A"
    ]
    hp = sum(1 for a in hard if res[a]["v"] == "PASS")
    fz = [m for m in members if m.get("fault_fired") is not None]

    def f(x: Optional[float]) -> str:
        return "-" if x is None else "%.0fs" % x

    tgt = " ".join(
        "%s %s%s"
        % (
            a,
            res[a]["v"],
            "[%s]" % res[a]["mode"].split(":", 1)[1] if ":" in res[a]["mode"] else "",
        )
        for a in sorted(res)
        if a.startswith("T") or "[" in a
    )
    bad = " ".join("%s %s" % (a, res[a]["v"]) for a in hard if res[a]["v"] != "PASS")
    pre_bad = " ".join("%s(%s)" % (k, v[1]) for k, v in sorted(pre.items()) if not v[0])
    return (
        "%s band %d (%s/%s) · load/core p50 %s r31/P p50 %s · %s · H %d/%d%s · %s · detect→attempt p50 %s p90 %s max %s · "
        "attempt→engaged p50 %s p90 %s · faults %d/%d fired · token-expiry %d · abstains %s%s"
        % (
            arm,
            want,
            min(bl) if bl else "-",
            max(bl) if bl else "-",
            "%.1f" % pct(loads, 0.5) if loads else "-",
            "%.1f" % pct(r31, 0.5) if r31 else "-",
            pre["P2"][1].split(" of ")[0] + " in premise",
            hp,
            len(hard),
            (" (" + bad + ")") if bad else "",
            tgt,
            f(pct(first, 0.5)),
            f(pct(first, 0.9)),
            f(max(first) if first else None),
            f(pct(eng, 0.5)),
            f(pct(eng, 0.9)),
            sum(1 for m in fz if m["fault_fired"]),
            len(fz),
            sum(m.get("token_expiry", 0) for m in members),
            facts.get("abstains"),
            (" · PRE " + pre_bad) if pre_bad else "",
        )
    )


# ── pair (§8.4) ─────────────────────────────────────────────────────────────────────────────────


def _good(v: str) -> bool:
    return v in ("PASS", "XPASS")


def _bad(v: str) -> bool:
    return v in ("FAIL", "XFAIL")


def pair(run: str) -> int:
    meta = load(os.path.join(run, "meta.json"), {})
    arms = list(meta.get("arms", {}))
    sm = {a: load(os.path.join(run, a, "summary.json"), {}) or {} for a in arms}
    cure, red = sm.get("cure", {}), sm.get("red")
    thefts = max(
        [s.get("thefts", 0) for s in jsonl(os.path.join(run, "samples.jsonl"))] or [0]
    )
    l1 = [s["load"][0] for s in jsonl(os.path.join(run, "samples.jsonl"))]
    head = (
        "lr-load-harness %s · tree %s · lanes: reconciler · load1 p50 %s (band beside each arm) · focus-thefts %d · G1 debt %d"
        % (
            meta.get("id", "?"),
            str(meta.get("arms", {}).get("cure", {}).get("tree", "?"))[:9],
            "%.0f" % pct(l1, 0.5) if l1 else "-",
            thefts,
            g1_debt(),
        )
    )
    abort = load(os.path.join(run, "abort.json"))
    halves = [cure.get("line", "cure: no summary")] + (
        [red.get("line", "red: no summary")] if red is not None else []
    )
    power: List[str] = []
    if (
        not cure
        or not cure.get("pre_ok")
        or (red is not None and not red.get("pre_ok"))
    ):  # an abort is the P0 precondition of every arm (assess), so it lands here
        why = (
            "aborted: %s" % abort["reason"]
            if abort
            else "a precondition failed (see PRE)"
        )
        v, rc = "NO-VERDICT (%s; retry later, never a wait)" % why, 3
    elif cure.get("hard_fail"):
        v, rc = "FAIL (cure: %s)" % ",".join(cure["hard_fail"]), 1
    elif red is None:
        v, rc = "CURE-ONLY PASS (one arm: power not assessed)", 0
    else:
        cr, rr = cure.get("res", {}), red.get("res", {})
        power = [
            a
            for a in cr
            if a.split("[")[0] in OUTCOME + PASS_LENGTH
            and _good(cr[a]["v"])
            and _bad(rr.get(a, {}).get("v", ""))
        ]
        outcome = [a for a in power if a.split("[")[0] in OUTCOME]
        if outcome:
            v, rc = "POWER via %s → PASS" % ",".join(power), 0
        elif power:
            v, rc = "POWER via %s → PASS (power: pass-length only)" % ",".join(power), 5
        else:
            v, rc = (
                "SIGNAL-DEAD (the red arm failed nothing the cure passed; next: --red tree:<parent>@31)",
                4,
            )
    line = "%s · %s · %s" % (head, " | ".join(halves), v)
    dump(
        os.path.join(run, "pair.json"),
        {"verdict": v, "rc": rc, "power": power, "line": line},
    )
    with open(os.path.join(run, "verdict.line"), "w") as fh:
        fh.write(line + "\n")
    print(line)
    return rc


def g1_debt() -> int:
    n = 0
    for ln in text(os.path.join(HERE, "g1-allow.tsv")).splitlines():
        p = ln.split("\t")
        if len(p) >= 3 and p[2].startswith("debt:"):
            n += 1
    return n


# ── drive: the long-lived run driver (Python, so the reaper's orphan-bash arm never takes it) ───


def _lstart(pid: int) -> str:
    try:
        out = subprocess.run(
            ["/bin/ps", "-o", "lstart=", "-p", str(pid)],
            capture_output=True,
            text=True,
            env=dict(os.environ, LC_ALL="C"),
            timeout=30,
        ).stdout
        return " ".join(out.split())
    except (OSError, subprocess.SubprocessError):
        return ""


def _log(run: str, msg: str) -> None:
    line = "[harness %s] %s" % (time.strftime("%H:%M:%S"), msg)
    print(line, flush=True)
    with open(os.path.join(run, "driver.log"), "a") as fh:
        fh.write(line + "\n")


def prod_max_gap(t0: float, t1: float) -> float:
    """F16-F17: production's own pass gaps in the run window (read-only), beside the rig's."""
    ts = []
    for ln in text(os.path.join(PROD_ROOT, "band.log")).splitlines():
        p = ln.split()
        if p and p[0].isdigit() and t0 <= float(p[0]) <= t1:
            ts.append(float(p[0]))
    return max(_gaps(ts) or [0.0])


def drive(run: str) -> int:
    """Run one pair (or one arm) end to end from meta.json; writes verdict.line and done.json.
    Every gate fails to NO-VERDICT (rc 3) and never waits for load."""
    meta = load(os.path.join(run, "meta.json"), {})
    me = os.getpid()
    meta["harness_pid"], meta["harness_ident"] = me, ident(me)
    dump(os.path.join(run, "meta.json"), meta)
    lockdir = os.path.join(HARNESS, "lock")
    rc = lock("acquire", lockdir, meta["id"], me)
    if rc:
        return _finish(run, 3, "NO-VERDICT lock: another Tier-L run holds %s" % lockdir)
    try:
        return _drive(run, meta)
    finally:
        lock("release", lockdir, meta["id"], me)


def _finish(run: str, rc: int, line: str) -> int:
    if not os.path.exists(
        os.path.join(run, "verdict.line")
    ):  # a gate refused before any pair
        with open(os.path.join(run, "verdict.line"), "w") as fh:
            fh.write(line + "\n")
    dump(os.path.join(run, "done.json"), {"rc": rc, "line": line, "t": time.time()})
    _log(run, "done rc=%d · %s" % (rc, line))
    return rc


def _drive(run: str, meta: Dict[str, Any]) -> int:
    if os.path.exists(os.path.join(HARNESS, "OFF")):
        return _finish(run, 3, "NO-VERDICT off: %s/OFF exists" % HARNESS)
    b = base_of(os.getpid())
    if b is None or b < 31:
        return _finish(
            run,
            3,
            "NO-VERDICT band:caller-clamped (driver base %s < 31: cc-bats, postland or a launchd job without ProcessType)"
            % b,
        )
    if prod_blocking(prod_records(PROD_ROOT)):
        return _finish(
            run,
            3,
            "NO-VERDICT production-busy: %s (retry later; never a wait)"
            % ", ".join(prod_blocking(prod_records(PROD_ROOT))[:4]),
        )
    arms = meta["arms"]
    nmem = int(meta["n"]) + int(meta.get("n_extra") or 0)
    windows = sum(
        nmem + (nmem + 1) // 2 for _ in arms
    )  # ≤2 members + a control per OS window
    if preflight(windows, len(arms), int(meta.get("kitty_pid") or 0)) != 0:
        return _finish(
            run, 3, "NO-VERDICT budget: preflight refused (retry later; never a wait)"
        )
    tests = os.path.join(meta["cure_tree"], "tests", "rig")
    sampler = subprocess.Popen(
        ["/usr/bin/python3", "-I", os.path.join(tests, "load_lib.py"), "sample", run],
        stdin=subprocess.DEVNULL,
        stdout=open(os.path.join(run, "sampler.out"), "ab"),
        stderr=subprocess.STDOUT,
    )
    gen = None
    if meta.get("bg_topup") or meta.get("df_topup"):
        ctl = os.path.join(run, "loadgen.ctl")
        open(ctl, "w").close()
        gen = subprocess.Popen(
            [
                "/usr/bin/python3",
                "-I",
                os.path.join(tests, "loadgen.py"),
                "run",
                "--bg",
                str(meta.get("bg_topup") or 0),
                "--ut",
                "0",
                "--df",
                str(meta.get("df_topup") or 0),
                "--parent",
                str(os.getpid()),
                "--parent-ident",
                ident(os.getpid()),
                "--max-s",
                str(meta["max_s"]),
                "--ctl",
                ctl,
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        _log(
            run,
            "top-up generator pid %d (bg %s, df %s): operator-allowed by LR_HARNESS_TOPUP"
            % (gen.pid, meta.get("bg_topup"), meta.get("df_topup")),
        )
    procs: Dict[str, subprocess.Popen] = {}
    rig = os.path.join(tests, "lr-recon-rig.sh")
    owner_ls = _lstart(os.getpid())
    try:
        for name in [a for a in ("cure", "red") if a in arms]:
            a = arms[name]
            env = dict(os.environ)
            env.update(
                {
                    "LR_RIG_ROOT": a["root"],
                    "LR_RIG_TREE": a["tree_dir"],
                    "LR_RIG_BAND": a["band"],
                    "LR_RIG_HB_WAIT_S": str(a["hb_wait_s"]),
                    "LR_RIG_BOOT_WAIT_S": str(meta["boot_wait_s"]),
                    "LR_RIG_KEEP": "1",
                    "LR_RIG_OWNER_PID": str(os.getpid()),
                    "LR_RIG_OWNER_LSTART": owner_ls,
                    "LR_RIG_KITTY_SLOW": "1",
                    "LR_RIG_HOLD_WINDOW": "1",
                    "LR_RIG_WATCHDOG_BAND": "utility",  # F23: production's watchdog runs at 20
                    "LR_RIG_AUTORECOVER": meta.get("autorecover", "on"),
                    "LR_RIG_TYPED_RELAUNCH": "1" if meta.get("typed_relaunch") else "0",
                    "CC_TERM_KITTY_TO": meta["sock"],
                }
            )
            out = open(os.path.join(run, "%s.out" % name), "ab")
            procs[name] = subprocess.Popen(
                [
                    "/bin/bash",
                    rig,
                    "--n",
                    str(meta["n"]),
                    "--faults",
                    meta["matrix"],
                    "--timeout",
                    str(int(meta["arm_timeout_s"])),
                ],
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=out,
                stderr=subprocess.STDOUT,
            )
            _log(
                run,
                "arm %s started (pid %d, band %s, tree %s)"
                % (name, procs[name].pid, a["band"], a["tree"][:9]),
            )
            # S5: one arm opens its windows at a time; the next waits for windows.done (bounded: ours)
            t_w = time.time()
            while (
                not os.path.exists(os.path.join(a["root"], "windows.done"))
                and procs[name].poll() is None
            ):
                if time.time() - t_w > 600:
                    dump(
                        os.path.join(run, "abort.json"),
                        {"reason": "setup: %s windows not open in 600 s" % name},
                    )
                    break
                time.sleep(2)
            if os.path.exists(os.path.join(run, "abort.json")):
                break
        # watch: the cure arm to its end; the red arm to its end, or stopped once power is shown
        cure_done = False
        last_probe = 0.0
        while any(p.poll() is None for p in procs.values()):
            if os.path.exists(os.path.join(run, "abort.json")) or os.path.exists(
                os.path.join(HARNESS, "OFF")
            ):
                for a in arms.values():
                    open(os.path.join(a["root"], "stop"), "a").close()
            if "cure" in procs and procs["cure"].poll() is not None and not cure_done:
                cure_done = True
                collect(run, "cure")
                assess(run, "cure")
                _log(run, "cure arm finished (rc %s)" % procs["cure"].returncode)
            if (
                cure_done
                and "red" in procs
                and procs["red"].poll() is None
                and time.time() - last_probe > 120
            ):
                last_probe = time.time()
                collect(run, "red")
                assess(run, "red")
                cs = load(os.path.join(run, "cure", "summary.json"), {}) or {}
                rs = load(os.path.join(run, "red", "summary.json"), {}) or {}
                shown = [
                    k
                    for k, v in (cs.get("res") or {}).items()
                    if k.split("[")[0] in OUTCOME
                    and _good(v["v"])
                    and _bad((rs.get("res") or {}).get(k, {}).get("v", ""))
                ]
                if shown and rs.get("pre_ok"):
                    _log(run, "red early stop: power via %s" % ",".join(shown))
                    open(os.path.join(arms["red"]["root"], "stop"), "a").close()
            time.sleep(5)
        for name in procs:
            collect(run, name)
    finally:
        open(os.path.join(run, "sampler.stop"), "a").close()
        try:
            sampler.wait(timeout=120)
        except subprocess.TimeoutExpired:
            sampler.kill()
        if gen is not None and gen.poll() is None:
            subprocess.run(
                [
                    "/usr/bin/python3",
                    "-I",
                    os.path.join(tests, "loadgen.py"),
                    "kill",
                    "--ctl",
                    os.path.join(run, "loadgen.ctl"),
                ],
                capture_output=True,
                timeout=30,
            )
    t_end = time.time()
    meta = load(os.path.join(run, "meta.json"), {})
    meta["prod_max_gap_s"] = prod_max_gap(float(meta["started"]), t_end)
    meta["ended"] = t_end
    dump(os.path.join(run, "meta.json"), meta)
    for name in procs:
        assess(run, name)
    rc = pair(run)
    # teardown, by each arm's own rig script (verified kills, windows by root), then again 30 s on
    for sweep in (0, 1):
        if sweep:
            time.sleep(30)
        for name in procs:
            env = dict(
                os.environ,
                LR_RIG_ROOT=arms[name]["root"],
                CC_TERM_KITTY_TO=meta["sock"],
            )
            subprocess.run(
                ["/bin/bash", rig, "--teardown"],
                env=env,
                capture_output=True,
                timeout=300,
            )
    specs = [os.path.join(a["root"], "specs.json") for a in arms.values()]
    if prod_sids(PROD_ROOT, specs):
        _log(run, "S7: production holds a record for a rig sid (listed above)")
        rc = 3 if rc == 0 else rc
    if meta.get("out"):
        os.makedirs(meta["out"], exist_ok=True)
        for name in procs:
            for f in ("summary.json", "lanes.json", "members.jsonl"):
                src = os.path.join(run, name, f)
                if os.path.exists(src):
                    with (
                        open(src, "rb") as a_,
                        open(
                            os.path.join(meta["out"], "%s-%s" % (name, f)), "wb"
                        ) as b_,
                    ):
                        b_.write(a_.read())
        with open(os.path.join(meta["out"], "verdict.line"), "w") as fh:
            fh.write(text(os.path.join(run, "verdict.line")))
    return _finish(run, rc, text(os.path.join(run, "verdict.line")).strip())


def calibrate() -> int:
    """boot_cpu_s from real boots, read-only: CPU-s of live claude processes aged 10-30 s."""
    rq = _runq()
    out = subprocess.run(
        ["/bin/ps", "-axo", "pid=,etime=,comm="],
        capture_output=True,
        text=True,
        timeout=60,
    ).stdout
    vals = []
    for ln in out.splitlines():
        p = ln.split(None, 2)
        if len(p) < 3 or os.path.basename(p[2]) not in ("claude", "claude.exe"):
            continue
        mm_ss = p[1].split(":")
        if len(mm_ss) != 2 or "-" in p[1]:
            continue
        age = int(mm_ss[0]) * 60 + int(mm_ss[1])
        if 10 <= age <= 30 and rq:
            c = rq.cpu_s(int(p[0]))
            if c is not None:
                vals.append(c)
    l1 = os.getloadavg()[0]
    print(
        "calibrate · load1 %.0f · band %s · %d claude process(es) aged 10-30 s · boot CPU-s p50 %s max %s"
        % (
            l1,
            base_of(os.getpid()),
            len(vals),
            "%.2f" % pct(vals, 0.5) if vals else "-",
            "%.2f" % max(vals) if vals else "-",
        )
    )
    return 0 if vals else 1


# ── analyze (report only) ───────────────────────────────────────────────────────────────────────


def analyze(dirs: List[str]) -> int:
    """t_first − t0 per attempt, stratified by the load bin and the r31 bin at its spawn (F7: attempts,
    not runs), beside P_obs. With few runs it is indicative, never a gate."""
    by: Dict[str, List[float]] = {}
    pobs = []
    for d in dirs:
        for arm in ("cure", "red"):
            for m in jsonl(os.path.join(d, arm, "members.jsonl")):
                if (
                    m.get("t_first") is None
                    or m.get("t0") is None
                    or not m.get("attempts")
                ):
                    continue
                a = m["attempts"][0]
                key = "%s %s %s" % (arm, a.get("load_bin", "?"), a.get("r31_bin", "?"))
                by.setdefault(key, []).append(m["t_first"] - m["t0"])
            s = load(os.path.join(d, arm, "summary.json"), {}) or {}
            if s.get("p_obs") is not None:
                pobs.append(s["p_obs"])
    print(
        "analyze %d run(s) · P_obs max %s"
        % (len(dirs), "%.0fs" % max(pobs) if pobs else "-")
    )
    for k in sorted(by):
        v = by[k]
        print(
            "  %-28s n=%-3d t_first p50 %5.0fs p90 %5.0fs max %5.0fs"
            % (k, len(v), pct(v, 0.5), pct(v, 0.9), max(v))
        )
    return 0


def main(argv: List[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, a = argv[1], argv[2:]
    if cmd == "lock":
        return lock(a[0], a[1], a[2], int(a[3]))
    if cmd == "prod-gate":
        return prod_gate(a[0] if a else PROD_ROOT)
    if cmd == "prod-sids":
        return prod_sids(a[0], a[1:])
    if cmd == "run-length":
        print(run_length(load(a[0]), float(a[1]), float(a[2])))
        return 0
    if cmd == "preflight":
        return preflight(int(a[0]), int(a[1]))
    if cmd == "sample":
        return sample(a[0])
    if cmd == "collect":
        return collect(a[0], a[1])
    if cmd == "assert":
        return assess(a[0], a[1])
    if cmd == "pair":
        return pair(a[0])
    if cmd == "drive":
        return drive(a[0])
    if cmd == "calibrate":
        return calibrate()
    if cmd == "analyze":
        return analyze(a)
    print("load_lib: unknown command %s" % cmd, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
