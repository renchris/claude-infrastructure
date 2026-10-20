"""telemetry.py — REPORT lever B6: make the next incident legible without forensics.

WRITE-ONLY for the rail: no decision in lr_recon reads ``recon/telemetry.jsonl``, ``close["tel"]``
or the heartbeat's phase keys (lint NoDecisionReadsTelemetry, test_telemetry.py). Zero forks: every
reading comes from what the pass already holds (its one ps read, its records, the child durations
run_bounded measures) or from in-process libproc/sysctl reads (band.py). It never raises into a
pass: every public method runs inside ``_guard``. Design: docs/research/lr-sustained-load-2026-10-20/
impl/B6-telemetry.md §3-§6, with the review's correctness items 1-15 and efficacy RC-1..RC-14.

SCHEMA v1, one compact JSON object per line, ``t`` (wall, 0.1 s) FIRST so a reader windows rows by
slicing ``{"t":<num>,``; every row also carries ``k`` (kind), ``v`` and ``pid``:
  start  once per daemon, before the first pass: lstart, code{fp,mtime}, band, and prev{pid,
         progress_age,phase,phase_age,seq,pass_age} — the PREVIOUS daemon's heartbeat, so a killed
         pass still yields "ran at least pass_age s" (a P_max reading the pass row never got)
  pass   a pass that is not quiet (§3.3): seq mode dur gap slept l1 open active placed ph{} ch{label:
         [n,sum,max,timeouts]} gates{"gate:reason":n} admits{} spawns{} band{self,min,roles,low,unk,
         ps} therm mem tel(ms CPU); optional abstain degraded exc werr faults trunc
  quiet  every 300 s, folding the quiet passes since the last row: seq0 seq1 n dur[p50,max] gap_max
         ph_max{} ch{label:[n,max,timeouts]} gates{} band_min low[] therm_max mem_max
  box    every 60 s while a record is moving, else 300 s, never more often than 60x its own CPU:
         seq l1 ncpu run{base_pri:n} thr procs of partial kitty{pid:[task,main_base,main_cur]}|null
         rail{role:[n,min,oldest_s]} adj{} cost(wall s) cpu(s); optional stalled err
  rec    a record's state changed (birth included), flap-coalesced: sid rid from to dwell att p0;
         optional flaps det death pre
  close  a record became terminal (born terminal included, ``born_terminal``): sid rid kind out via
         src dst att death det first first_by held_pre planned eng dwell{}; optional pre
  act    an actuator exit was scored: sid rid a rc wall end(log|seen) seen_lag att detail
  spawn  an actuator was spawned: sid rid a att gap (s since this record's last exit was seen) p0

``close["tel"]`` (one namespaced dict on the record, ignored by old code): st at dwell{} first
first_by held_pre planned ls lx pre. Kill switches: ``recon/telemetry.off`` (read every pass),
``LR_RECON_TELEMETRY=off`` (never built), ``LR_RECON_TELEMETRY_BOX=off`` (no thread census).
Readout: ``python3 -m lr_recon.telemetry readout [--since 1h] [--json] [--history] [--root DIR]``,
which ``cc-lr status --rail`` runs.
"""

from __future__ import annotations

import argparse
import calendar
import collections
import glob
import hashlib
import json
import os
import re
import sys
import threading
import time
from typing import Any, Callable, Dict, Iterable, List, Optional, Set, Tuple

try:
    from lr_recon import band
except Exception:  # noqa: BLE001 — a late-linked band.py must not take telemetry down
    band = None  # type: ignore[assignment]
from lr_recon import settle, store
from lr_recon import types as T

V, FILE, OFF_FILE = 1, "telemetry.jsonl", "telemetry.off"
MAX_BYTES, LINE_MAX = 8 << 20, 4096
SLOW_PASS_S, QUIET_EVERY_S = 30.0, 300.0
BOX_ACTIVE_S, BOX_QUIET_S, BOX_COST_FACTOR = 60.0, 300.0, 60.0
CENSUS_JOIN_S = (
    2.5  # the census checks its own 2 s deadline per pid; the loop waits at most this
)
FAULT_LIMIT, REARM_S = 20, 3600.0
FLAP_WINDOW_S, FLAP_SIDS, DWELL_KEYS_MAX, FLOOR = 60.0, 256, 24, 31
CH_LABELS_MAX, SPAWN_WALLS_MAX = 24, 256
KITTY_GLOB = "/tmp/kitty-*"
# The recovery actuators whose spawn is an ATTEMPT: __main__.FIRST_TURN, derived the same way.
FIRST = tuple(settle.MOVE_ACTUATORS) + ("C", "C-retry")
# REPORT §5's hard predicates as substates (display-only; pin to B3's set once it lands): a true
# busy turn (COMPOSER, BGWORK, SUBAGENTS), an unsent draft or pasted block (DRAFT, MENU), a live claim
# by another driver (HELD:team), the target capped (WAIT_RESET, WAIT_CAPACITY), and the operator's
# or the structure's own holds (FOCUS, iterm, repo-bare). HOLD-LOAD is NOT one: load is never a hold.
HARD_HOLD = frozenset(
    (
        "HOLD-COMPOSER",
        "HOLD-BGWORK",
        "HOLD-SUBAGENTS",
        "HOLD-DRAFT",
        "HOLD-MENU",
        "HELD:team",
        "WAIT_RESET",
        "WAIT_CAPACITY",
        "HOLD-FOCUS",
        "HOLD:iterm",
        "HOLD:repo-bare",
    )
)
OTHER_LANE = {"PARKED-REBOOT": "boot-resume"}  # substate → the lane that owns it
NOT_COVERED = ("move lane", "boot-resume")
# Rail roles, matched on argv STRUCTURE in the first 400 bytes (RC-6): argv0's basename, or an
# interpreter's script basename. A substring over the whole args matched Claude sessions whose
# prompt names a rail script (9 of 38 hits, measured) and bats suites at base 11.
RAIL = {
    "lr-reset-poller.sh": "poller",
    "lr-move-batch.sh": "move-batch",
    "lr-move-worker.sh": "move-worker",
    "lr-fleet.sh": "fleet",
    "lr-handoff.sh": "handoff",
    "handoff-fire.sh": "hf",
    "lr-fire-resume.sh": "resume",
    "lr-transplant.sh": "transplant",
}
ADJ = {"cc-dispatch": "dispatch"}
RAIL_ROLES = ("actuator",) + tuple(RAIL.values())
ADJ_ROLES = tuple(ADJ.values()) + ("session-parent",)
# Never rail, whatever their args say. Defense in depth: under exact-basename matching none of these
# can map to a role anyway (its removal is an equivalent mutant); it keeps a future looser match safe.
EXCLUDE0 = frozenset(("claude", "node", "expect", "jq", "bats", "cc-close-attrib"))
BATS = ("bats", "bats-exec-test", "bats-exec-suite", "bats-exec-file")
SESSION_HOSTS = ("claude", "cc-close-attrib")
INTERP = ("bash", "sh", "zsh", "dash", "python3", "python")
ROLE_SCAN_BYTES = 400


# ── helpers (kept here: store has no env-named size reader, and nothing reads json-or-None) ─────


def _max_bytes_env(env: Any, name: str, default: int) -> int:
    raw = str(env.get(name, "") or "")
    return int(raw) if raw.isdigit() and int(raw) > 0 else default


def _read_json(path: str) -> Optional[Dict[str, Any]]:
    try:
        with open(path, encoding="utf-8") as fh:
            obj = json.load(fh)
    except (OSError, ValueError):
        return None
    return obj if isinstance(obj, dict) else None


def _safe_event(paths: T.Paths, ev: str, detail: str) -> None:
    try:
        store.append_event(paths, T.Event(t=time.time(), ev=ev, detail=detail[:200]))
    except Exception:  # noqa: BLE001
        pass


def state_key(rec: T.Record) -> str:
    if rec.terminal is not None:
        return "T:" + rec.terminal.outcome
    base = "%s/%s" % (rec.phase, rec.substate or "-")
    return "ESC:" + base if rec.escalated else base


def _sub(key: str) -> str:
    """The substate half of a state key ("" for terminal and escalated keys)."""
    if key.startswith(("T:", "ESC:")) or "/" not in key:
        return ""
    return key.split("/", 1)[1]


def death_ts(rec: T.Record) -> Optional[float]:
    """``close["death"]`` = "<uuid>@<iso ts>" (census.py); None when absent or unparseable."""
    raw = str(rec.close.get("death") or "")
    if "@" not in raw:
        return None
    iso = raw.rsplit("@", 1)[1].strip()
    try:
        import datetime as _dt

        return _dt.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError):
        return None


def lstart_epoch(s: Any) -> Optional[float]:
    """ProcRole/ProcRow lstart is UTC under LC_ALL=C (store.proc_lstart, observe.py)."""
    try:
        return float(calendar.timegm(time.strptime(str(s), "%a %b %d %H:%M:%S %Y")))
    except (ValueError, TypeError):
        return None


def _cap(d: Dict[str, float]) -> None:
    while len(d) > DWELL_KEYS_MAX:
        del d[min(d, key=lambda k: d[k])]


def _pct(xs: List[float], q: float) -> Optional[float]:
    if not xs:
        return None
    s = sorted(xs)
    return s[min(len(s) - 1, int(q * (len(s) - 1) + 0.5))]


def _code_fp() -> Dict[str, Any]:
    here = os.path.dirname(os.path.abspath(__file__))
    items = []
    for n in sorted(os.listdir(here)):
        if n.endswith(".py"):
            try:
                st = os.stat(os.path.join(here, n))
            except OSError:
                continue
            items.append((n, st.st_size, int(st.st_mtime)))
    fp = hashlib.sha1(repr(items).encode()).hexdigest()[:12]
    return {"fp": fp, "mtime": max((i[2] for i in items), default=0)}


# ── rail roles (RC-6) ────────────────────────────────────────────────────────────────────────────


def _argv(args: str) -> List[str]:
    return (args or "")[:ROLE_SCAN_BYTES].split()


def _name(a: List[str]) -> str:
    """argv0's basename, or an interpreter's script basename."""
    if not a:
        return ""
    b0 = os.path.basename(a[0])
    if b0 in INTERP and len(a) > 1 and a[1] != "-c":
        script = next((x for x in a[1:] if not x.startswith("-")), "")
        return os.path.basename(script) or b0
    return b0


def role_of(
    row: T.ProcRow, procs: Dict[int, T.ProcRow], kids: Dict[int, List[int]]
) -> Optional[str]:
    a = _argv(row.args)
    if not a or os.path.basename(a[0]) in EXCLUDE0:
        return None
    b0 = os.path.basename(a[0])
    role: Optional[str] = None
    if b0 in INTERP and len(a) > 1 and a[1] == "-c":
        # act.wrap: /bin/bash -c <WRAPPER, 194 B> lr-recon-act --record-id … (inside the scan)
        if "lr-recon-act" in a:
            i = a.index("lr-recon-act")
            role = "actuator" if a[i + 1 : i + 2] == ["--record-id"] else None
    else:
        name = _name(a)
        if name in EXCLUDE0:
            return None
        role = RAIL.get(name) or ADJ.get(name)
    if role is None or _under_bats(row, procs):
        return None
    if role == "resume" and _hosts_session(row.pid, procs, kids):
        return "session-parent"  # lr-fire-resume.sh → expect → claude hosts a resumed session
    return role


def _under_bats(row: T.ProcRow, procs: Dict[int, T.ProcRow]) -> bool:
    """A suite running a rail script from a worktree (often at background band) is not rail work."""
    seen, pid = 0, row.ppid
    while pid > 1 and seen < 8:
        up = procs.get(pid)
        if up is None:
            return False
        if _name(_argv(up.args)) in BATS:
            return True
        pid, seen = up.ppid, seen + 1
    return False


def _hosts_session(
    pid: int, procs: Dict[int, T.ProcRow], kids: Dict[int, List[int]]
) -> bool:
    todo, n = list(kids.get(pid, ())), 0
    while todo and n < 64:
        p = todo.pop()
        n += 1
        row = procs.get(p)
        if row is None:
            continue
        a = _argv(row.args)
        if a and os.path.basename(a[0]) in SESSION_HOSTS:
            return True
        todo.extend(kids.get(p, ()))
    return False


def _roles(rail: Dict[str, List[Any]], names: Iterable[str]) -> Dict[str, List[Any]]:
    return {r: list(v) for r, v in rail.items() if r in names}


# ── the writer ──────────────────────────────────────────────────────────────────────────────────


def _guard(fn: Callable[..., Any]) -> Callable[..., Any]:
    """P5 + RC-10: an exception counts a fault and returns None. At FAULT_LIMIT telemetry turns
    itself off for REARM_S (one telemetry-off event), then re-arms with a fresh budget (one
    telemetry-on event): a transient cause never blinds the daemon for its whole life."""

    def run(self: "Telemetry", *a: Any, **kw: Any) -> Any:
        if self.paused:
            return None
        if self.off:
            if self.mono() - self.off_at < REARM_S:
                return None
            self.off, self.faults = False, 0
            _safe_event(self.paths, "telemetry-on", "re-armed after %ds off" % REARM_S)
        try:
            return fn(self, *a, **kw)
        except Exception as e:  # noqa: BLE001
            self.faults += 1
            self.faults_unreported += 1
            if self.faults >= FAULT_LIMIT:
                self.off, self.off_at, self.cur = True, self.mono(), None
                _safe_event(
                    self.paths,
                    "telemetry-off",
                    "%d faults; last %r; re-arms in %ds" % (self.faults, e, REARM_S),
                )
            return None

    run.__name__ = fn.__name__
    run.__doc__ = fn.__doc__
    return run


class Telemetry:
    """One per daemon process (P3: only daemon() builds it, after the reconciler's flock)."""

    def __init__(
        self,
        paths: T.Paths,
        env: Optional[Any] = None,
        wall: Optional[Callable[[], float]] = None,
        mono: Optional[Callable[[], float]] = None,
        thread_time: Optional[Callable[[], float]] = None,
        read_pri: Optional[Callable[..., Optional[int]]] = None,
        census: Optional[Callable[[], Optional[Dict[str, Any]]]] = None,
        kitty_pri: Optional[Callable[[int], Any]] = None,
        loadavg: Optional[Callable[[], Tuple[float, float, float]]] = None,
        thermal: Optional[Callable[[], Optional[int]]] = None,
        pressure: Optional[Callable[[], Optional[int]]] = None,
        kitty_glob: str = KITTY_GLOB,
    ) -> None:
        e = os.environ if env is None else env
        self.paths, self.path = paths, paths.p(FILE)
        self.max = _max_bytes_env(e, "LR_RECON_TELEM_MAX_BYTES", MAX_BYTES)
        self.box_on = e.get("LR_RECON_TELEMETRY_BOX", "on") != "off"
        self.wall = wall or time.time
        self.mono = mono or time.monotonic
        self.thread_time = thread_time or time.thread_time
        self.loadavg = (
            loadavg or os.getloadavg
        )  # RECORDED, never read by a gate (REPORT §5 G1)
        b = band
        self.read_pri = read_pri or (b.base_priority if b else (lambda pid=None: None))
        self.census = (
            census if census is not None else (b.runnable_by_base if b else None)
        )
        self.kitty_pri = kitty_pri or (b.main_thread if b else (lambda pid: None))
        self.thermal = thermal or (b.thermal_level if b else (lambda: None))
        self.pressure = pressure or (b.pressure_level if b else (lambda: None))
        self.kitty_glob = kitty_glob
        self.off = self.paused = False
        self.off_at = 0.0
        self.faults = self.faults_unreported = self.werr = 0
        self.seq = 0
        self.cur: Optional[Dict[str, Any]] = None
        self.t_end: Optional[float] = None
        self.quiet: Optional[Dict[str, Any]] = None
        self.last_degraded: Tuple[str, ...] = ()
        self.last_active = 0
        self.flaps: "collections.OrderedDict[str, Dict[str, Any]]" = (
            collections.OrderedDict()
        )
        self.next_box = 0.0
        self.rail: Dict[str, List[Any]] = {}
        self.census_thread: Optional[threading.Thread] = None
        self.spawn_wall: "collections.OrderedDict[int, float]" = (
            collections.OrderedDict()
        )
        self.pre_terminal: Optional[Set[str]] = (
            None  # None until start(): every untagged terminal is pre-B6
        )
        self.pre_open: Set[str] = set()
        self.last_alert = ""

    # lifecycle — called by __main__ only

    def check_switch(self) -> None:
        """NOT guarded (a stat per pass, P9): ``recon/telemetry.off`` pauses without a restart."""
        self.paused = os.path.exists(self.paths.p(OFF_FILE))
        if self.paused:
            self.cur = None

    @_guard
    def start(
        self,
        prev: Optional[Dict[str, Any]],
        records: Iterable[T.Record] = (),
        lstart: str = "",
    ) -> None:
        recs = list(records)
        untagged = [r for r in recs if "st" not in (r.close.get("tel") or {})]
        # RC-1: only the records ALREADY terminal at load are pre-B6; one born terminal later
        # (census.impossible_record / not_needed_record) gets a close row, never a silent drop
        self.pre_terminal = {r.sid for r in untagged if r.terminal is not None}
        self.pre_open = {r.sid for r in untagged if r.terminal is None}
        p = prev or {}
        now = self.wall()

        def num(k: str) -> Optional[float]:
            v = p.get(k)
            return float(v) if isinstance(v, (int, float)) and v else None

        hb_wall, pw, pa, ph_at = (
            num("wall"),
            num("progress_wall"),
            num("pass_at"),
            num("phase_at"),
        )
        phase = str(p.get("phase") or "")
        self._row(
            {
                "k": "start",
                "lstart": lstart,
                "code": _code_fp(),
                "band": self.read_pri(None),
                "prev": {
                    "pid": p.get("pid"),
                    "progress_age": None if pw is None else round(now - pw, 1),
                    "phase": phase,
                    "phase_age": None if ph_at is None else round(now - ph_at, 1),
                    "seq": p.get("pass_seq"),
                    "pass_age": round(hb_wall - pa, 1)
                    if (hb_wall and pa and phase not in ("", "idle"))
                    else None,
                },
            }
        )

    @_guard
    def pass_begin(self, seq: int, slept: float = 0.0) -> None:
        m = self.mono()
        self.seq = int(seq)
        self.cur = {
            "t0": m,
            "p0": round(self.wall(), 1),
            "gap": None if self.t_end is None else round(m - self.t_end, 2),
            "slept": round(slept or 0.0, 1),
            "ph": {},
            "pn": "",
            "pt": m,
            "ch": {},
            "gates": collections.Counter(),
            "admits": collections.Counter(),
            "spawns": collections.Counter(),
            "gaps": {},
            "recrows": 0,
            "active": 0,
            "band": None,
            "cost": 0.0,
        }

    @_guard
    def phase(self, name: str) -> None:
        c = self.cur
        if c is None:
            return
        m = self.mono()
        if c["pn"]:
            c["ph"][c["pn"]] = c["ph"].get(c["pn"], 0.0) + (m - c["pt"])
        c["pn"], c["pt"] = name, m

    @_guard
    def child(self, label: str, dur: float, late: bool) -> None:
        """clock's run_bounded hook (bound loop thread only)."""
        c = self.cur
        if c is None:
            return
        ch = c["ch"]
        if label not in ch and len(ch) >= CH_LABELS_MAX:
            label = "other"
        v = ch.setdefault(label, [0, 0.0, 0.0, 0])
        v[0] += 1
        v[1] += dur
        v[2] = max(v[2], dur)
        v[3] += int(bool(late))

    @_guard
    def gate(self, gate: str, reason: str) -> None:
        """Every refusal counts, each pass — the events log keeps only changes (one row a day)."""
        if self.cur is not None:
            self.cur["gates"][("%s:%s" % (gate, reason))[:60]] += 1

    @_guard
    def admitted(self, why: str) -> None:
        if self.cur is not None:
            self.cur["admits"][str(why)[:40]] += 1

    @_guard
    def pre_spawn(self, rec: T.Record, which: str) -> None:
        """Before act.spawn, so spawn's own record saves carry the stamps (item 10): a restart in
        the minutes before the end-of-pass save can no longer lose ``first``. ``held_pre`` nets the
        hard-hold time out of first − det (RC-2)."""
        c = self.cur
        if c is None:
            return
        now = round(self.wall(), 1)
        tel = rec.close.setdefault("tel", {})
        lx = tel.get("lx")
        c["gaps"][rec.sid] = None if lx is None else round(now - float(lx), 1)
        tel["ls"] = now
        if which in FIRST and "first" not in tel:
            tel["first"], tel["first_by"] = now, which
            tel["held_pre"] = round(_held(tel, now), 1)

    @_guard
    def spawned(self, rec: T.Record, which: str, pid: int = 0) -> None:
        c = self.cur
        if c is None:
            return
        c["spawns"][which] += 1
        if pid:
            self.spawn_wall[int(pid)] = (rec.close.get("tel") or {}).get(
                "ls"
            ) or self.wall()
            while len(self.spawn_wall) > SPAWN_WALLS_MAX:
                self.spawn_wall.popitem(last=False)
        self._row(
            {
                "k": "spawn",
                "sid": rec.sid[:8],
                "rid": rec.record_id,
                "a": which,
                "att": rec.attempt,
                "gap": c["gaps"].pop(rec.sid, None),
                "p0": c["p0"],
            }
        )

    @_guard
    def act_exit(
        self,
        rec: T.Record,
        pr: T.ProcRole,
        rc: Optional[int],
        detail: str = "",
        log: str = "",
    ) -> None:
        """RC-4: the settle detail rides along, and the wall is exit-based (the actlog's mtime),
        not exit-SEEN, which adds a load-stretched pass gap; ``seen_lag`` keeps that gap."""
        if self.cur is None:
            return
        now = self.wall()
        try:
            mt: Optional[float] = os.stat(log).st_mtime if log else None
        except OSError:
            mt = None
        t0 = self.spawn_wall.pop(pr.pid, None) or lstart_epoch(pr.lstart)
        end = mt if mt is not None else now
        rec.close.setdefault("tel", {})["lx"] = round(now, 1)
        self._row(
            {
                "k": "act",
                "sid": rec.sid[:8],
                "rid": rec.record_id,
                "a": pr.argv_hash,
                "rc": rc,
                "wall": None if t0 is None else round(max(0.0, end - t0), 1),
                "end": "log" if mt is not None else "seen",
                "seen_lag": None if mt is None else round(max(0.0, now - mt), 1),
                "att": rec.attempt,
                "detail": str(detail or "")[:80],
            }
        )

    @_guard
    def observed(self, snap: T.Snapshot) -> None:
        """Right after observe(): the rail's bands from the pass's own ps read (no fork)."""
        c = self.cur
        if c is None:
            return
        t0 = self.thread_time()
        procs = snap.procs
        kids: Dict[int, List[int]] = {}
        for row in procs.values():
            kids.setdefault(row.ppid, []).append(row.pid)
        roles: Dict[str, List[Any]] = {}
        low: List[List[Any]] = []
        unk = 0
        now = self.wall()
        for row in procs.values():
            if row.zombie:
                continue
            role = role_of(row, procs, kids)
            if role is None:
                continue
            ent = roles.setdefault(role, [0, None, None])
            ent[0] += 1
            age = lstart_epoch(row.lstart)
            if age is not None:
                ent[2] = max(ent[2] or 0, int(now - age))
            pri = self.read_pri(row.pid)
            if pri is None:
                unk += role in RAIL_ROLES
                continue
            ent[1] = pri if ent[1] is None else min(ent[1], pri)
            if role in RAIL_ROLES and pri < FLOOR and len(low) < 5:
                low.append([role, row.pid, pri])
        me = self.read_pri(None)
        mins = [v[1] for r, v in roles.items() if r in RAIL_ROLES and v[1] is not None]
        if me is not None:
            mins.append(me)
        c["band"] = {
            "self": me,
            "min": min(mins) if mins else None,
            "roles": {r: v[:2] for r, v in roles.items()},
            "low": low,
            "unk": unk,
            "ps": "ps" not in (snap.degraded or ()),
        }
        self.rail = roles
        cost = self.thread_time() - t0
        c["role_ms"] = round(cost * 1000, 2)
        c["cost"] += cost

    @_guard
    def note_states(
        self, records: Iterable[T.Record], active_of: Callable[[T.Record], bool]
    ) -> None:
        """Before _report (item 8: cohort_status's in_state_s reads ``at``), after dispatch. Dwell
        and stamps ride this pass's record write; a record whose state is unchanged is untouched."""
        c = self.cur
        if c is None:
            return
        t0 = self.thread_time()
        now = round(self.wall(), 1)
        for rec in records:
            k = state_key(rec)
            if rec.open and active_of(rec):
                c["active"] += 1
            tel = rec.close.get("tel")
            if not isinstance(tel, dict) or "st" not in tel:
                if rec.terminal is not None:
                    if self.pre_terminal is None or rec.sid in self.pre_terminal:
                        continue  # pre-B6 terminal: no row, no write
                    tel = rec.close.setdefault("tel", {})
                    tel["st"], tel["at"] = k, now
                    self._row(self._close_row(rec, born=True))
                    continue
                tel = rec.close.setdefault("tel", {})
                tel["st"], tel["at"] = k, now
                if rec.sid in self.pre_open:
                    # first sighting, not detection: its first attempt is unknown
                    tel["pre"] = 1
                if _sub(k) == "PLANNED":
                    tel.setdefault("planned", now)
                self._rec_row(rec, "", k, 0.0, birth=True)
                continue
            if tel["st"] == k:
                continue
            dwell = max(0.0, now - float(tel.get("at") or now))
            d = tel.setdefault("dwell", {})
            d[tel["st"]] = round(d.get(tel["st"], 0.0) + dwell, 1)
            _cap(d)
            prev = tel["st"]
            tel["st"], tel["at"] = k, now
            if _sub(k) == "PLANNED":
                tel.setdefault("planned", now)
            if not self._flap(rec.sid, prev, k, now):
                self._rec_row(rec, prev, k, dwell)
            if rec.terminal is not None:
                self._row(self._close_row(rec))
        c["cost"] += self.thread_time() - t0

    @_guard
    def pass_end(
        self, summary: Optional[Dict[str, Any]], exc: Optional[BaseException]
    ) -> None:
        c = self.cur
        if c is None:
            return
        t0 = self.thread_time()
        m = self.mono()
        if c["pn"]:
            c["ph"][c["pn"]] = c["ph"].get(c["pn"], 0.0) + (m - c["pt"])
        dur = m - c["t0"]
        s = summary or {}
        deg = tuple(sorted(s.get("degraded") or ()))
        c["therm"], c["mem"] = self.thermal(), self.pressure()
        full = bool(
            exc is not None
            or s.get("abstain")
            or self.seq == 1
            or dur >= SLOW_PASS_S
            or c["active"]
            or c["spawns"]
            or c["admits"]
            or c["recrows"]
            or any(v[3] for v in c["ch"].values())
            or deg != self.last_degraded
            or (c["band"] or {}).get("low")
        )
        if full:
            self._flush_quiet()
            c["cost"] += self.thread_time() - t0
            self._row(self._pass_row(c, s, dur, deg, exc))
        else:
            self._fold_quiet(c, dur)
            if self.quiet and m - self.quiet["m0"] >= QUIET_EVERY_S:
                self._flush_quiet()
        self.last_degraded, self.t_end, self.last_active = deg, self.mono(), c["active"]
        self.last_alert = _alert(dur, c)  # §6.4, consumed by _report on the next pass
        self.cur = None

    @_guard
    def box(self) -> None:
        """The runnable census by base priority, OFF the loop thread (ctypes releases the GIL):
        the loop waits at most CENSUS_JOIN_S, a census stuck in the kernel is never stacked, and
        the throttle keys on the census's own CPU (RC-8), which contention does not inflate."""
        now = self.mono()
        if not self.box_on or now < self.next_box:
            return
        th = self.census_thread
        if th is not None and th.is_alive():
            self.next_box = now + BOX_ACTIVE_S
            return
        res: Dict[str, Any] = {}
        stalled = False
        if self.census is not None:
            census = self.census

            def work() -> None:
                c0, w0 = self.thread_time(), self.mono()
                try:
                    res["cen"] = census()
                except Exception as e:  # noqa: BLE001
                    res["err"] = repr(e)[:120]
                res["cpu"], res["wall"] = self.thread_time() - c0, self.mono() - w0

            th = threading.Thread(target=work, name="lr-census", daemon=True)
            self.census_thread = th
            th.start()
            th.join(CENSUS_JOIN_S)
            stalled = th.is_alive()
        cen = res.get("cen") or {}
        cpu = float(res.get("cpu") or 0.0)
        try:
            l1: Optional[float] = round(float(self.loadavg()[0]), 1)
        except (OSError, IndexError, TypeError, ValueError):
            l1 = None
        row: Dict[str, Any] = {
            "k": "box",
            "seq": self.seq,
            "l1": l1,
            "ncpu": os.cpu_count() or 0,
            "run": cen.get("run"),
            "thr": cen.get("thr"),
            "procs": cen.get("procs"),
            "of": cen.get("of"),
            "partial": bool(cen.get("partial")) or stalled,
            "kitty": self._kitty() or None,
            "rail": _roles(self.rail, RAIL_ROLES),
            "adj": _roles(self.rail, ADJ_ROLES),
            "cost": round(float(res.get("wall") or 0.0), 3),
            "cpu": round(cpu, 4),
        }
        if stalled:
            row["stalled"] = True
        if "err" in res:
            row["err"] = res["err"]
        self._row(row)
        base = BOX_ACTIVE_S if self.last_active else BOX_QUIET_S
        self.next_box = now + max(base, BOX_COST_FACTOR * cpu)
        if "err" in res:
            raise RuntimeError(
                "census: %s" % res["err"]
            )  # counted as a fault by the guard

    # internals

    def _kitty(self) -> Dict[str, List[Any]]:
        """RC-9: pids from the ``/tmp/kitty-<pid>`` socket names, alive iff proc_pidinfo reads them,
        so a ps-degraded pass still sees kitty's band. Empty means unknown, never fine."""
        pids = set()
        for p in glob.glob(self.kitty_glob):
            tail = p.rsplit("-", 1)[-1]
            if tail.isdigit():
                pids.add(int(tail))
        out: Dict[str, List[Any]] = {}
        for pid in sorted(pids)[:8]:
            task = self.read_pri(pid)
            if task is None:
                continue
            mt = self.kitty_pri(pid) or (None, None)
            out[str(pid)] = [task, mt[0], mt[1]]
        return out

    def _flap(self, sid: str, a: str, b: str, now: float) -> bool:
        ent = self.flaps.get(sid)
        if ent is None:
            ent = self.flaps[sid] = {"last": {}, "n": 0}
            while len(self.flaps) > FLAP_SIDS:
                self.flaps.popitem(last=False)
        last = ent["last"].get((a, b))
        if last is not None and now - last < FLAP_WINDOW_S:
            ent["n"] += 1
            return True
        ent["last"][(a, b)] = now
        return False

    def _rec_row(
        self, rec: T.Record, a: str, b: str, dwell: float, birth: bool = False
    ) -> None:
        c = self.cur or {}
        row: Dict[str, Any] = {
            "k": "rec",
            "sid": rec.sid[:8],
            "rid": rec.record_id,
            "from": a,
            "to": b,
            "dwell": round(dwell, 1),
            "att": rec.attempt,
            "p0": c.get("p0"),
        }
        ent = self.flaps.get(rec.sid)
        if ent and ent["n"]:
            row["flaps"], ent["n"] = ent["n"], 0
        if birth:
            row["det"] = rec.timeline.detected
            row["death"] = death_ts(rec)
            if (rec.close.get("tel") or {}).get("pre"):
                row["pre"] = True
        if self.cur is not None:
            self.cur["recrows"] += 1
        self._row(row)

    def _close_row(self, rec: T.Record, born: bool = False) -> Dict[str, Any]:
        tel = rec.close.get("tel") or {}
        tl = rec.timeline
        pre = bool(tel.get("pre"))
        row: Dict[str, Any] = {
            "k": "close",
            "sid": rec.sid[:8],
            "rid": rec.record_id,
            "kind": rec.kind,
            "out": rec.terminal.outcome if rec.terminal else "",
            "via": str(rec.close.get("via") or ""),
            "src": rec.source_acct,
            "dst": rec.target_acct,
            "att": rec.attempt,
            "death": death_ts(rec),
            "det": tl.detected,
            "first": None if pre else tel.get("first"),
            "first_by": None if pre else tel.get("first_by"),
            "held_pre": tel.get("held_pre"),
            "planned": tel.get("planned") or tl.planned,
            "eng": tl.engaged,
            "dwell": tel.get("dwell") or {},
        }
        if born:
            row["born_terminal"] = True
        if pre:
            row["pre"] = True
        return row

    def _pass_row(
        self,
        c: Dict[str, Any],
        s: Dict[str, Any],
        dur: float,
        deg: Tuple[str, ...],
        exc: Optional[BaseException],
    ) -> Dict[str, Any]:
        try:
            l1: Optional[float] = round(float(self.loadavg()[0]), 1)
        except (OSError, IndexError, TypeError, ValueError):
            l1 = None
        row: Dict[str, Any] = {
            "k": "pass",
            "seq": self.seq,
            "mode": s.get("mode"),
            "dur": round(dur, 2),
            "gap": c["gap"],
            "slept": c["slept"],
            "l1": l1,
            "open": s.get("open"),
            "active": c["active"],
            "placed": s.get("placed"),
            "ph": {k: round(v, 2) for k, v in c["ph"].items()},
            "ch": {
                k: [v[0], round(v[1], 2), round(v[2], 2), v[3]]
                for k, v in c["ch"].items()
            },
            "gates": dict(c["gates"]),
            "admits": dict(c["admits"]),
            "spawns": dict(c["spawns"]),
            "band": c["band"],
            "therm": c.get("therm"),
            "mem": c.get("mem"),
            "tel": round(c["cost"] * 1000, 2),
        }
        if "role_ms" in c:
            row["role_ms"] = c["role_ms"]
        if s.get("abstain"):
            row["abstain"] = s["abstain"]
        if deg != self.last_degraded:
            row["degraded"] = list(deg)
        if exc is not None:
            row["exc"] = repr(exc)[:200]
        return row

    def _fold_quiet(self, c: Dict[str, Any], dur: float) -> None:
        q = self.quiet
        if q is None:
            q = self.quiet = {
                "m0": self.mono(),
                "seq0": self.seq,
                "n": 0,
                "durs": [],
                "gap_max": 0.0,
                "ph_max": {},
                "ch": {},
                "gates": collections.Counter(),
                "band_min": None,
                "low": [],
                "therm_max": None,
                "mem_max": None,
            }
        q["seq1"] = self.seq
        q["n"] += 1
        q["durs"].append(round(dur, 2))
        q["gap_max"] = max(q["gap_max"], c["gap"] or 0.0)
        for k, v in c["ph"].items():
            q["ph_max"][k] = max(q["ph_max"].get(k, 0.0), round(v, 2))
        for k, v in c["ch"].items():
            e = q["ch"].setdefault(k, [0, 0.0, 0])
            e[0] += v[0]
            e[1] = max(e[1], round(v[2], 2))
            e[2] += v[3]
        q["gates"].update(c["gates"])
        bmin = (c["band"] or {}).get("min")
        if bmin is not None:
            q["band_min"] = bmin if q["band_min"] is None else min(q["band_min"], bmin)
        for key, val in (("therm_max", c.get("therm")), ("mem_max", c.get("mem"))):
            if val is not None:
                q[key] = val if q[key] is None else max(q[key], val)

    def _flush_quiet(self) -> None:
        q, self.quiet = self.quiet, None
        if not q or not q["n"]:
            return
        self._row(
            {
                "k": "quiet",
                "seq": q.get("seq1"),
                "seq0": q["seq0"],
                "seq1": q.get("seq1"),
                "n": q["n"],
                "dur": [_pct(q["durs"], 0.5), max(q["durs"])],
                "gap_max": round(q["gap_max"], 2),
                "ph_max": q["ph_max"],
                "ch": q["ch"],
                "gates": dict(q["gates"]),
                "band_min": q["band_min"],
                "low": q["low"],
                "therm_max": q["therm_max"],
                "mem_max": q["mem_max"],
            }
        )

    def _row(self, obj: Dict[str, Any]) -> None:
        """P4: ``t`` first, ≤ LINE_MAX, one os.write on O_APPEND. A failed write counts ``werr``,
        shown on the next row that lands; faults since the last row ride the same way."""
        row: Dict[str, Any] = {"t": round(self.wall(), 1)}
        row.update(obj)
        row.setdefault("v", V)
        row["pid"] = os.getpid()
        if self.werr:
            row["werr"] = self.werr
        if self.faults_unreported:
            row["faults"] = self.faults_unreported
        line = _bounded(row, LINE_MAX)
        try:
            store.append_bounded(self.path, line, self.max)
        except OSError:
            self.werr += 1
            return
        self.werr = 0
        self.faults_unreported = 0


def _held(tel: Dict[str, Any], now: float) -> float:
    """Seconds this record spent in HARD_HOLD states so far, the current open interval included."""
    held = sum(
        float(v) for k, v in (tel.get("dwell") or {}).items() if _sub(k) in HARD_HOLD
    )
    st = str(tel.get("st") or "")
    if _sub(st) in HARD_HOLD and tel.get("at"):
        held += max(0.0, now - float(tel["at"]))
    return held


def _bounded(row: Dict[str, Any], limit: int) -> str:
    """F3: drop the long tails (top-12 ch by sum, top-16 gates, …); still over: a stub row."""
    s = store.dumps(row)
    if len(s.encode("utf-8")) <= limit - 1:
        return s
    for key, keep in (
        ("ch", 12),
        ("gates", 16),
        ("admits", 8),
        ("spawns", 8),
        ("dwell", 8),
        ("ph_max", 12),
    ):
        d = row.get(key)
        if isinstance(d, dict) and len(d) > keep:

            def weight(k: str, d: Dict[str, Any] = d) -> float:
                v = d[k]
                return float(v[1] if isinstance(v, list) else v)

            row[key] = {k: d[k] for k in sorted(d, key=weight, reverse=True)[:keep]}
            s = store.dumps(row)
            if len(s.encode("utf-8")) <= limit - 1:
                return s
    stub = {k: row.get(k) for k in ("t", "k", "v", "pid", "seq") if k in row}
    stub["trunc"] = len(s.encode("utf-8"))
    return store.dumps(stub)


def _dur(s: Optional[float]) -> str:
    if s is None:
        return "-"
    s = float(s)
    if s < 60:
        return "%.1fs" % s if s < 10 else "%ds" % s
    if s < 3600:
        return "%dm%02ds" % (s // 60, s % 60)
    return "%dh%02dm" % (s // 3600, (s % 3600) // 60)


def _alert(dur: float, c: Dict[str, Any]) -> str:
    """§6.4: only a measured anomaly of the last pass. A child timeout alone is not one: under
    the binding premise our own timeout means "unknown, retry"."""
    low = (c.get("band") or {}).get("low") or []
    if low:
        role, pid, pri = low[0]
        return "%s %d pri %d" % (role, pid, pri)
    if dur > P_MAX_S:
        ph = c.get("ph") or {}
        top = max(ph, key=lambda k: ph[k]) if ph else ""
        return "slow pass %s%s" % (
            _dur(dur),
            " (%s %s)" % (top, _dur(ph[top])) if top else "",
        )
    return ""


# ── the readout (§6): cc-lr status --rail ───────────────────────────────────────────────────────

P_MAX_S, W_SOFT_S, B_MAX_S, ALIVE_S, NOOP_S = 180.0, 600.0, 300.0, 60.0, 10.0
_T = re.compile(r'^\{"t":(-?[0-9.]+),')
READ_MAX = 4 << 20


def _envf(env: Any, name: str, default: float) -> float:
    try:
        return float(env.get(name, "") or default)
    except ValueError:
        return default


def _tail_lines(path: str, nbytes: int) -> List[str]:
    try:
        with open(path, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - nbytes))
            data = fh.read()
    except OSError:
        return []
    lines = data.decode("utf-8", "replace").splitlines()
    return lines[1:] if size > nbytes and lines else lines


def _rows(path: str, since: float) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for gen in (path + ".1", path):
        for ln in _tail_lines(gen, READ_MAX):
            m = _T.match(ln)
            if not m or float(m.group(1)) < since:
                continue
            try:
                obj = json.loads(ln)
            except ValueError:
                continue
            if isinstance(obj, dict):
                out.append(obj)
    return out


def _newest(path: str) -> Optional[Dict[str, Any]]:
    for gen in (path, path + ".1"):
        for ln in reversed(_tail_lines(gen, 64 * 1024)):
            try:
                obj = json.loads(ln)
            except ValueError:
                continue
            if isinstance(obj, dict):
                return obj
    return None


def _records(paths: T.Paths) -> List[Dict[str, Any]]:
    out = []
    try:
        names = sorted(os.listdir(paths.sessions))
    except OSError:
        return out
    for n in names:
        if n.endswith(".json"):
            r = _read_json(os.path.join(paths.sessions, n))
            if r is not None:
                out.append(r)
    return out


def _events(paths: T.Paths, since: float) -> List[Dict[str, Any]]:
    out = []
    for ln in _tail_lines(paths.events, 2 << 20):
        try:
            ev = json.loads(ln)
        except ValueError:
            continue
        if isinstance(ev, dict) and float(ev.get("t") or 0) >= since:
            out.append(ev)
    return out


def _stats(xs: List[float]) -> Dict[str, Any]:
    return {
        "n": len(xs),
        "p50": _pct(xs, 0.5),
        "p90": _pct(xs, 0.9),
        "max": max(xs) if xs else None,
    }


def readout(
    paths: T.Paths,
    now: float,
    since_s: float = 3600.0,
    history: bool = False,
    env: Optional[Any] = None,
) -> Dict[str, Any]:
    e = os.environ if env is None else env
    p_max = _envf(e, "LR_RAIL_P_MAX_S", P_MAX_S)
    w_soft = _envf(e, "LR_RAIL_W_SOFT_S", W_SOFT_S)
    b_max = _envf(e, "LR_RAIL_B_MAX_S", B_MAX_S)
    alive_s = _envf(e, "LR_RAIL_ALIVE_S", ALIVE_S)
    noop_s = _envf(e, "LR_RAIL_NOOP_S", NOOP_S)
    since = now - since_s
    path = paths.p(FILE)
    files = [p for p in (path, path + ".1") if os.path.exists(p)]
    rows = _rows(path, since) if files else []
    newest = _newest(path) if files else None
    hb = _read_json(paths.heartbeat) or {}
    reasons: List[str] = []
    d: Dict[str, Any] = {
        "verdict": "ok",
        "scope": "reconciler",
        "not_covered": list(NOT_COVERED),
        "reasons": reasons,
        "window_s": since_s,
        "now": now,
    }
    # daemon: alive iff the heartbeat's own wall is ≤ 60 s old (the watchdog's STALE_HB_S)
    hb_wall = float(hb.get("wall") or 0)
    seq_hb = int(hb.get("pass_seq") or 0)
    phase = str(hb.get("phase") or "")
    pass_at = float(hb.get("pass_at") or 0)
    running = bool(phase) and phase != "idle" and pass_at > 0
    started = lstart_epoch(" ".join(str(hb.get("lstart") or "").split()))
    d["daemon"] = {
        "pid": hb.get("pid"),
        "alive": bool(hb) and now - hb_wall <= alive_s,
        "hb_age": round(now - hb_wall, 1) if hb_wall else None,
        "up_s": round(now - started) if started else None,
        "phase": phase,
        "phase_age": round(now - float(hb["phase_at"]), 1)
        if hb.get("phase_at")
        else None,
        "pass_seq": seq_hb,
        "running_s": round(now - pass_at, 1) if running else None,
        "child_bound_s": hb.get("child_bound_s"),
        "step_due_in": round(float(hb["step_due"]) - now, 1)
        if hb.get("step_due")
        else None,
    }
    full = [r for r in rows if r.get("k") == "pass"]
    quiet = [r for r in rows if r.get("k") == "quiet"]
    boxes = [r for r in rows if r.get("k") == "box"]
    closes = [r for r in rows if r.get("k") == "close"]
    acts = [r for r in rows if r.get("k") == "act"]
    spawns_r = [r for r in rows if r.get("k") == "spawn"]
    # passes, phases, children, gates
    durs = [float(r.get("dur") or 0) for r in full]
    gaps = [float(r["gap"]) for r in full if isinstance(r.get("gap"), (int, float))]
    d["passes"] = {
        "full": len(full),
        "quiet_rows": len(quiet),
        "n": len(full) + sum(int(q.get("n") or 0) for q in quiet),
        "p50": _pct(durs, 0.5),
        "p90": _pct(durs, 0.9),
        "max": max(durs) if durs else None,
        "quiet_max": max(
            (float((q.get("dur") or [0, 0])[1] or 0) for q in quiet), default=None
        ),
        "gap_p50": _pct(gaps, 0.5),
    }
    ph: Dict[str, List[float]] = {}
    for r in full:
        for k, v in (r.get("ph") or {}).items():
            ph.setdefault(k, []).append(float(v))
    for q in quiet:
        for k, v in (q.get("ph_max") or {}).items():
            ph.setdefault(k, []).append(float(v))
    d["phases"] = {k: [_pct(v, 0.9), max(v)] for k, v in ph.items()}
    ch: Dict[str, Dict[str, Any]] = {}
    for r in full:
        for k, v in (r.get("ch") or {}).items():
            e2 = ch.setdefault(k, {"n": 0, "maxes": [], "timeouts": 0})
            e2["n"] += int(v[0])
            e2["maxes"].append(float(v[2]))
            e2["timeouts"] += int(v[3])
    for q in quiet:
        for k, v in (q.get("ch") or {}).items():
            e2 = ch.setdefault(k, {"n": 0, "maxes": [], "timeouts": 0})
            e2["n"] += int(v[0])
            e2["maxes"].append(float(v[1]))
            e2["timeouts"] += int(v[2])
    d["children"] = {
        k: [
            v["n"],
            _pct(v["maxes"], 0.9),
            max(v["maxes"]) if v["maxes"] else None,
            v["timeouts"],
        ]
        for k, v in ch.items()
    }
    gates: collections.Counter = collections.Counter()
    admits: collections.Counter = collections.Counter()
    spawns: collections.Counter = collections.Counter()
    for r in full + quiet:
        gates.update(r.get("gates") or {})
    for r in full:
        admits.update(r.get("admits") or {})
        spawns.update(r.get("spawns") or {})
    d["gates"], d["admits"], d["spawns"] = dict(gates), dict(admits), dict(spawns)
    # band, kitty, box
    banded = [r for r in full if isinstance(r.get("band"), dict)]
    d["band"] = banded[-1]["band"] if banded else None
    d["box"] = boxes[-1] if boxes else None
    therm = [r.get("therm") for r in full] + [q.get("therm_max") for q in quiet]
    mem = [r.get("mem") for r in full] + [q.get("mem_max") for q in quiet]
    evs = _events(paths, since)
    held_load = sum(1 for ev in evs if "HELD:load" in str(ev.get("detail") or ""))
    dl: collections.Counter = collections.Counter(
        str(ev.get("detail") or "").split(" (")[0][:40]
        for ev in evs
        if ev.get("ev") == "deadline-held"
    )
    d["counters"] = {
        "therm_max": max((x for x in therm if x is not None), default=None),
        "mem_max": max((x for x in mem if x is not None), default=None),
        "held_load": held_load,
        "deadline_held": dict(dl),
    }
    # records: open from disk, closed from close rows
    p_obs = max(durs) if durs else p_max
    recs = _records(paths)
    open_rows, other_lane, stuck = [], [], []
    det_first, det_first_net, det_planned = [], [], []
    n_censored = 0
    for r in recs:
        if r.get("terminal") is not None:
            continue
        close = r.get("close") or {}
        tel = close.get("tel") if isinstance(close.get("tel"), dict) else {}
        tl = r.get("timeline") or {}
        det = tl.get("detected")
        sub = str(r.get("substate") or "")
        key = "%s/%s" % (r.get("phase"), sub or "-")
        sid8 = str(r.get("sid") or "")[:8]
        pre = bool(tel.get("pre"))
        first = None if pre else tel.get("first")
        at = tel.get("at")
        held = _held(tel, now) if tel else 0.0
        o = {
            "sid": sid8,
            "state": key,
            "in_state_s": round(now - float(at), 1) if at else None,
            "detected_s": round(now - float(det), 1) if det else None,
            "first_s": round(now - float(first), 1) if first else None,
            "first": "unknown" if pre else ("yes" if first else "no"),
            "held_s": round(held, 1),
        }
        if sub in OTHER_LANE:
            other_lane.append(dict(o, owner=OTHER_LANE[sub]))
            continue
        open_rows.append(o)
        if tel.get("planned") and det:
            det_planned.append(float(tel["planned"]) - float(det))
        if not pre and not first and det:
            n_censored += 1
            det_first.append(now - float(det))
            det_first_net.append(now - float(det) - held)
        if sub in HARD_HOLD or r.get("escalated"):
            continue
        ls, lx = tel.get("ls"), tel.get("lx")
        if (
            lx
            and (ls is None or float(ls) < float(lx))
            and now - float(lx) > b_max + p_obs
        ):
            stuck.append(
                "record %s in %s: no retry %s after its last exit (> B_max %ds + P_obs %ds)"
                % (sid8, key, _dur(now - float(lx)), b_max, p_obs)
            )
        elif ls is None and not pre and det and now - float(det) - held > w_soft:
            stuck.append(
                "record %s in %s: not attempted %s after detection, net of holds (> W_soft %ds)"
                % (sid8, key, _dur(now - float(det) - held), w_soft)
            )
    d["open"], d["other_lane"] = open_rows, other_lane
    unatt: collections.Counter = collections.Counter()
    born = 0
    for r in closes:
        det = r.get("det")
        born += bool(r.get("born_terminal"))
        if r.get("pre"):
            continue
        if r.get("planned") and det:
            det_planned.append(float(r["planned"]) - float(det))
        if r.get("first") and det:
            v = float(r["first"]) - float(det)
            det_first.append(v)
            det_first_net.append(v - float(r.get("held_pre") or 0))
        else:
            unatt[str(r.get("out") or "?")] += 1
    death_det = [
        float(r["det"]) - float(r["death"])
        for r in closes
        if r.get("det") and r.get("death")
    ]
    det_eng = [
        float(r["eng"]) - float(r["det"])
        for r in closes
        if r.get("eng") and r.get("det")
    ]
    walls: Dict[str, List[float]] = {}
    noop = 0
    for r in acts:
        if isinstance(r.get("wall"), (int, float)):
            walls.setdefault(str(r.get("a")), []).append(float(r["wall"]))
            noop += r.get("rc") not in (0, None) and float(r["wall"]) < noop_s
    allw = [w for v in walls.values() for w in v]
    d["closed"] = {
        "n": len(closes),
        "born_terminal": born,
        "death_detect": _stats(death_det),
        "detect_first": dict(
            _stats(det_first), n_censored=n_censored, n_closed_unattempted=dict(unatt)
        ),
        "detect_first_net": _stats(det_first_net),
        "detect_planned": _stats(det_planned),
        "detect_engaged": _stats(det_eng),
        "actuator_wall": dict(
            _stats(allw), by={k: len(v) for k, v in walls.items()}, noop=noop
        ),
        "retry_gap_max": max(
            (
                float(r["gap"])
                for r in spawns_r
                if isinstance(r.get("gap"), (int, float))
            ),
            default=None,
        ),
    }
    if history:
        eng_all = [
            float(r["timeline"]["engaged"]) - float(r["timeline"]["detected"])
            for r in recs
            if (r.get("timeline") or {}).get("engaged")
            and (r.get("timeline") or {}).get("detected")
        ]
        d["history"] = {"detect_engaged": _stats(eng_all)}
    # telemetry's own health
    faults = sum(int(r.get("faults") or 0) for r in rows)
    werr = sum(int(r.get("werr") or 0) for r in rows)
    offs = [ev for ev in evs if ev.get("ev") == "telemetry-off"]
    d["telemetry"] = {
        "rows": len(rows),
        "files": len(files),
        "faults": faults,
        "werr": werr,
        "newest_age": round(now - float(newest["t"]), 1)
        if newest and newest.get("t")
        else None,
    }

    # ── verdict: computed, never narrated ──
    def no_data(why: str) -> Dict[str, Any]:
        d["verdict"] = "NO DATA"
        reasons[:] = [why]
        return d

    if not files:
        return no_data("no telemetry file under %s" % paths.root)
    if not d["daemon"]["alive"]:
        return no_data(
            "daemon down — heartbeat %s old; reconciler unknown"
            % _dur(d["daemon"]["hb_age"])
        )
    newest_seq = max(
        (int(r.get("seq") or 0) for r in rows),
        default=int((newest or {}).get("seq") or 0),
    )
    newest_age = d["telemetry"]["newest_age"]
    # A running pass writes nothing until it ends and quiet passes fold for up to QUIET_EVERY_S, so
    # neither a seq lag nor an old row alone means stopped: both, net of the running pass's age.
    idle_age = (
        None if newest_age is None else newest_age - (d["daemon"]["running_s"] or 0.0)
    )
    if seq_hb - newest_seq >= 2 and (
        idle_age is None or idle_age > max(600.0, 2 * QUIET_EVERY_S)
    ):
        why = "telemetry stopped (pass %d, newest row at pass %d, %s old)" % (
            seq_hb,
            newest_seq,
            _dur(newest_age),
        )
        if os.path.exists(paths.p(OFF_FILE)):
            why += "; %s is present" % OFF_FILE
        elif offs:
            why += "; telemetry-off: %s" % str(offs[-1].get("detail") or "")[:80]
        return no_data(why)
    if not rows and not running:
        return no_data("no telemetry row in the last %s" % _dur(since_s))
    if (
        running
        and d["daemon"]["running_s"] is not None
        and d["daemon"]["running_s"] > p_max
    ):
        reasons.append(
            "pass %d running %s, phase %s for %s, child bound %ss, step due in %s"
            % (
                seq_hb,
                _dur(d["daemon"]["running_s"]),
                phase,
                _dur(d["daemon"]["phase_age"]),
                hb.get("child_bound_s") or 0,
                _dur(d["daemon"]["step_due_in"]),
            )
        )
    b = d["band"]
    if b:
        for role, pid, pri in b.get("low") or []:
            reasons.append(
                "%s %s reads priority %s, below %d" % (role, pid, pri, FLOOR)
            )
        if b.get("self") is None:
            reasons.append("band unknown for the reconciler itself")
        elif b["self"] < FLOOR:
            reasons.append(
                "reconciler reads priority %s, below %d" % (b["self"], FLOOR)
            )
        if b.get("unk"):
            reasons.append("band unknown for %d rail processes" % b["unk"])
    bx = d["box"]
    if bx is not None:
        kit = bx.get("kitty")
        if not kit:
            reasons.append("kitty band unknown")
        else:
            for kpid, v in kit.items():
                lows = [x for x in v[:2] if isinstance(x, int) and x < FLOOR]
                if lows or v[0] is None:
                    reasons.append(
                        "kitty %s task %s main %s, below %d" % (kpid, v[0], v[1], FLOOR)
                    )
    slow = [x for x in durs if x > p_max]
    if slow:
        reasons.append(
            "%d full pass(es) over P_max %ds (max %s)"
            % (len(slow), p_max, _dur(max(slow)))
        )
    reasons.extend(stuck)
    if faults or werr:
        reasons.append(
            "telemetry faults %d, write errors %d in the window" % (faults, werr)
        )
    if offs:
        reasons.append(
            "telemetry turned itself off: %s" % str(offs[-1].get("detail") or "")[:80]
        )
    d["verdict"] = "WARN" if reasons else "ok"
    return d


def _since(s: str) -> float:
    m = re.match(r"^([0-9.]+)([smhd]?)$", s.strip())
    if not m:
        raise ValueError("--since takes 90s, 30m, 1h or 2d")
    return (
        float(m.group(1)) * {"": 1, "s": 1, "m": 60, "h": 3600, "d": 86400}[m.group(2)]
    )


def _st(x: Dict[str, Any]) -> str:
    if not x.get("n"):
        return "n 0"
    return "p50 %s p90 %s max %s (n %d)" % (
        _dur(x["p50"]),
        _dur(x["p90"]),
        _dur(x["max"]),
        x["n"],
    )


def render(d: Dict[str, Any]) -> List[str]:
    head = "reconciler: %s" % d["verdict"]
    if d["reasons"]:
        head += " — " + " · ".join(d["reasons"])
    elif d["verdict"] == "ok":
        t = d.get("telemetry") or {}
        head += " — %d rows, newest %s ago" % (
            t.get("rows", 0),
            _dur(t.get("newest_age")),
        )
    lines = [
        head,
        "not covered: %s (this readout sees the reconciler only)"
        % ", ".join(d["not_covered"]),
    ]
    if d["verdict"] == "NO DATA":
        return lines
    dm = d["daemon"]
    now_s = (
        "pass %d running %s, %s" % (dm["pass_seq"], _dur(dm["running_s"]), dm["phase"])
        if dm.get("running_s") is not None
        else "idle (pass %d)" % dm["pass_seq"]
    )
    lines.append(
        "window %s · daemon %s up %s · heartbeat %s · now: %s"
        % (
            _dur(d["window_s"]),
            dm.get("pid"),
            _dur(dm.get("up_s")),
            _dur(dm.get("hb_age")),
            now_s,
        )
    )
    b = d.get("band")
    if b:
        parts = ["self %s" % ("?" if b.get("self") is None else b["self"])]
        for role, v in sorted((b.get("roles") or {}).items()):
            parts.append("%s %s ×%d" % (role, "?" if v[1] is None else v[1], v[0]))
        if not b.get("ps", True):
            parts.append("rail band not observed this pass (ps degraded)")
        lines.append("band   " + " · ".join(parts))
    bx = d.get("box")
    if bx:
        kit = bx.get("kitty")
        ktxt = (
            " · ".join(
                "kitty %s task %s main %s" % (k, v[0], v[1]) for k, v in kit.items()
            )
            if kit
            else "kitty unknown"
        )
        adj = bx.get("adj") or {}
        atxt = " · ".join(
            "%s %s ×%d (oldest %s)"
            % (r, "?" if v[1] is None else v[1], v[0], _dur(v[2]))
            for r, v in adj.items()
        )
        lines.append(
            "kitty  %s%s" % (ktxt, " · adjacent: " + atxt + " ⚠" if atxt else "")
        )
        run = bx.get("run") or {}
        rtxt = " ".join(
            "%s:%s" % (k, run[k]) for k in sorted(run, key=lambda x: int(x))
        )
        lines.append(
            "box    runnable by base priority %s of %s threads (%s/%s procs readable%s) · load1 %s (recorded only)"
            % (
                rtxt or "?",
                bx.get("thr"),
                bx.get("procs"),
                bx.get("of"),
                ", partial" if bx.get("partial") else "",
                bx.get("l1"),
            )
        )
    p = d["passes"]
    lines.append(
        "passes %d full + %d quiet rows (%d passes) · full p50 %s p90 %s max %s · quiet max %s · gap p50 %s"
        % (
            p["full"],
            p["quiet_rows"],
            p["n"],
            _dur(p["p50"]),
            _dur(p["p90"]),
            _dur(p["max"]),
            _dur(p["quiet_max"]),
            _dur(p["gap_p50"]),
        )
    )
    if d["phases"]:
        lines.append(
            "phases p90/max  "
            + " · ".join(
                "%s %.1f/%.1f" % (k, v[0], v[1]) for k, v in d["phases"].items()
            )
        )
    if d["children"]:
        lines.append(
            "child  n p90 max timeouts  "
            + " · ".join(
                "%s %d %.1f %.1f %d" % (k, v[0], v[1] or 0, v[2] or 0, v[3])
                for k, v in d["children"].items()
            )
        )
    g = " · ".join(
        "%s %d" % kv for kv in sorted(d["gates"].items(), key=lambda kv: -kv[1])
    )
    a = ", ".join("%s %d" % kv for kv in d["admits"].items())
    s = ", ".join("%s %d" % kv for kv in d["spawns"].items())
    lines.append(
        "gates  %s — admitted %s · spawned %s" % (g or "none", a or "0", s or "0")
    )
    c = d["counters"]
    lines.append(
        "hw     thermal max %s · memory pressure max %s · HELD:load %d · deadline-held %s"
        % (
            c["therm_max"],
            c["mem_max"],
            c["held_load"],
            ", ".join("%s %d" % kv for kv in c["deadline_held"].items()) or "0",
        )
    )
    if d["open"]:
        lines.append(
            "open %d  " % len(d["open"])
            + " · ".join(
                "%s %s %s (detected %s ago; first attempt %s)"
                % (
                    o["sid"],
                    o["state"],
                    _dur(o["in_state_s"]),
                    _dur(o["detected_s"]),
                    "unknown"
                    if o["first"] == "unknown"
                    else (
                        "%s ago" % _dur(o["first_s"])
                        if o["first_s"] is not None
                        else "none"
                    ),
                )
                for o in d["open"][:6]
            )
        )
    if d["other_lane"]:
        lines.append(
            "other lane %d  " % len(d["other_lane"])
            + " · ".join(
                "%s %s owned by %s, %s"
                % (o["sid"], o["state"], o["owner"], _dur(o["detected_s"]))
                for o in d["other_lane"][:6]
            )
        )
    cl = d["closed"]
    df = cl["detect_first"]
    lines.append(
        "closed %d (%d born terminal)  death→detect %s · detect→PLANNED %s"
        % (
            cl["n"],
            cl["born_terminal"],
            _st(cl["death_detect"]),
            _st(cl["detect_planned"]),
        )
    )
    lines.append(
        "       detect→first %s, %d censored, closed unattempted %s · net of holds %s"
        % (
            _st(df),
            df["n_censored"],
            ", ".join("%s %d" % kv for kv in df["n_closed_unattempted"].items()) or "0",
            _st(cl["detect_first_net"]),
        )
    )
    aw = cl["actuator_wall"]
    lines.append(
        "       detect→engaged %s · actuator wall %s (%s) · no-op %d · retry gap max %s"
        % (
            _st(cl["detect_engaged"]),
            _st(aw),
            ", ".join("%s %d" % kv for kv in aw["by"].items()) or "-",
            aw["noop"],
            _dur(cl["retry_gap_max"]),
        )
    )
    if d.get("history"):
        lines.append(
            "history detect→engaged over every record on disk: %s"
            % _st(d["history"]["detect_engaged"])
        )
    return lines


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="lr_recon.telemetry")
    ap.add_argument("cmd", choices=("readout",))
    ap.add_argument("--since", default="1h")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--history", action="store_true")
    ap.add_argument("--root", default=None)
    a = ap.parse_args(argv)
    try:
        d = readout(
            T.Paths.from_env(root=a.root), time.time(), _since(a.since), a.history
        )
    except Exception as e:  # noqa: BLE001 — unreadable is its own exit code, never a verdict
        print("reconciler: unreadable — %r" % e, file=sys.stderr)
        return 2
    if a.json:
        print(json.dumps(d, separators=(",", ":"), default=str))
    else:
        print("\n".join(render(d)))
    return 1 if d["verdict"] == "NO DATA" else 0


if __name__ == "__main__":
    sys.exit(main())
