"""admit.py: first-turn admission for one ACTIVE period (§C6, §6).

Four gates guard a limited session's FIRST TURN (the continue prompt), in this order:
  1. the frozen restore budget R (growth past the pre-limit population is refused),
  2. the wall-clock pace: a token bucket of PACE_BURST that refills one per PACE_EVERY_S of WALL
     time, with no load term (it replaced the CPU brake, 2026-10-20),
  3. the per-target-account pacer (at most 3 first turns per account per 20 s of WALL time; under
     load ENGAGED takes minutes, so more than 3 may be submitted-not-ENGAGED at once, still bounded
     by the pace and BootSlots),
  4. the library's memory terms via ``cc_capacity_probe`` (a PROBE: it charges nothing).

WHY THE BRAKE WENT (docs/research/lr-sustained-load-2026-10-20/REPORT.md §3.2, lever A4). It
admitted while load1/ncpu <= max(2.5, L_open), else once 20 s after the last admission. On this
machine load stays at 15-40 per core by design, and the session it gates does not move load1, so
the load term never opened; and its 20 s floor was measured against the PASS's ``now``, one value
for the whole pass, which made it one admission per pass. The pace, the drip and the pacer now read
their own wall clock (``self.wall``) at decide time (B7 D3: a pacer slot stamped at the pass ``now``
never freed inside a pass, which capped first turns at 3 per account per pass), never earlier than
the census instant, and the pacer re-reads it after the probe. The pass ``now`` keeps its one job:
the identity of a pass in the restore budget's refusal run, which must count passes, not members.

A relaunch with no prompt needs none of them. A LIMITED session whose first turn is refused is still
relaunched unprompted (RELAUNCHED-UNPROMPTED is a named wait that frees the source seat), so a refusal
here never blocks the relaunch: the CALLER decides, this module only answers.

The bounded gate: probe refusals never spend the library's own refusal budget, so the reconciler owns
the counter. After 3 consecutive probe refusals in a cohort the probe is overridden at most once per
30 s of wall time ("drip") and ``page_due`` is raised once for that cohort. Only the probe is
overridden: R (past its own run), the pace and the pacer stay binding, and none of them reads load,
so the drip's bound holds at any load.

State is plain attributes and every external effect (the bash library, the environment) is injected.
"""

import atexit
import calendar
import ctypes
import hashlib
import json
import os
import re
import shlex
import subprocess
import time
from typing import Any, Callable, Dict, List, Mapping, Optional, Sequence, Set, Tuple

from lr_recon.clock import atomic_write, run_bounded

# argv -> (rc, stdout). rc < 0 means the runner itself failed: RC_SPAWN_ERROR or RC_TIMEOUT.
Runner = Callable[[List[str]], Tuple[int, str]]
RC_SPAWN_ERROR = -1  # the child never ran (OSError at spawn)
RC_TIMEOUT = -2  # the runner's own bound fired before the child answered

REPO_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)
LIB_REL = "scripts/lib/capacity-admit.sh"

PACE_EVERY_S = 20.0  # gate 2 refills one first-turn admission per 20 s of wall time
PACE_BURST = (
    6  # and holds at most this many: BootSlots.START, the boots one wave may start
)
PACER_RELEASE_S = 20.0  # a pacer slot frees itself 20 s after its submit
DRIP_AFTER = 3  # consecutive probe refusals before the drip opens
DRIP_EVERY_S = 30.0
JITTER_MAX_S = 60

_SID_OK = re.compile(r"^[A-Za-z0-9._-]+$")


def _env_int(env: Mapping[str, str], key: str, default: int) -> int:
    raw = env.get(key, "")
    try:
        val = int(raw)
    except ValueError:
        return default
    return val if val > 0 else default


def default_runner(argv: List[str]) -> Tuple[int, str]:
    """Run argv with no stdin and a hard bound, never a raise: a timeout is RC_TIMEOUT and a spawn
    failure RC_SPAWN_ERROR, kept apart so a refusal can say which (2026-10-20, next3 cohort: six
    "probe-error" refusals at load ~259 were the 30 s bound firing on a demoted child, and read the
    same as a broken library)."""
    try:
        cp = run_bounded(
            argv, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30
        )
    except subprocess.TimeoutExpired:
        return RC_TIMEOUT, ""
    except OSError:
        return RC_SPAWN_ERROR, ""
    return cp.returncode, cp.stdout


def jitter_s(sid: str) -> float:
    """Deterministic 0-60 s offset for in-place reset wakes (WAIT_RESET, HELD:team leads).

    A hash of the sid, so a restarted daemon picks the same offset and a cohort that resets at one
    instant spreads over a minute instead of hitting one account at once (§C6 gate 3)."""
    digest = hashlib.sha256(sid.encode("utf-8")).hexdigest()
    return float(int(digest[:8], 16) % (JITTER_MAX_S + 1))


# ── W11 (B3): the per-record deadline ────────────────────────────────────────────────────────────
# A LIMITED record carries deadline_at = timeline.detected + W_soft. Past it the record is OVERDUE
# and its first turn skips the soft gates (restore-r, the pace and the pacer, which are still
# charged, the probe and its drip) inside a lane of width D, with a per-account cap, while the hard
# stop reads clear. A full lane or a tripped stop only removes the bypass: the call falls through to
# today's gates unchanged, so an overdue record is never treated worse than today. Every HARD gate
# runs before decide() and none of them is touched (design §3). No term here reads the load average.
# Kill switches, read every pass: recon/deadline.off (today's gates exactly), recon/deadline.shadow
# (log would-admit only).
DEADLINE_SOFT_S = (
    600.0  # W_soft: the move lane's soft gates bind for 10 min after detection
)
DEADLINE_WAKE_S = 300.0  # W_wake: a reset wake's own clock, from its due time
DEADLINE_HARD_S = (
    900.0  # W_hard: an overdue record (and a hard-stop trip) pages this long past
)
DEADLINE_WIDTH = (
    6  # D: deadline first turns submitted and not yet ENGAGED (BootSlots.START)
)
DEADLINE_PER_ACCT = (
    3  # of which at most this many on one target account (correctness F-A)
)
T_ATT_S = 900.0  # the attempt budget: a lane member leaves D after it, an actuator past it pages
WAKE_AFTER_S = (
    120.0  # __main__.WAKE_AFTER_S: a reset wake is due at eta + this + its jitter
)
WAKE_SUBSTATES = ("WAIT_RESET", "HELD:team")
# the hard stop (positive evidence of a physical limit only; unknown is never a stop)
SEG_HARD_PCT = (
    60.0  # compressor-sentinel pct that trips; release needs <= SEG_HARD_PCT - 10
)
PRESSURE_HARD = 4  # kern.memorystatus_vm_pressure_level critical
THERMAL_HARD = 3  # thermal 2 is this box's steady state at 15/core (measured): 2 would be a load gate
SENTINEL_FRESH_S = 60.0
RELEASE_GAP_S = 30.0  # a trip releases after two clear reads at least this far apart
UNKNOWN_RELEASE_S = (
    300.0  # a tripped source whose reads turn unknown releases after this
)
SLOT_PRIORITY = (
    "slot-priority"  # under lr_root/locks/: the move lane caps itself while it stands
)
SLOT_YIELD_OFF = (
    "slot-yield.off"  # under lr_root/locks/: the move lane ignores the file
)
SLOT_PRIORITY_MIN_S = 180.0


def _env(env: Optional[Mapping[str, str]]) -> Mapping[str, str]:
    """F-B 1: None is the process environment, never a missing attribute on every pass."""
    return os.environ if env is None else env


def _env_float(env: Optional[Mapping[str, str]], key: str, default: float) -> float:
    try:
        val = float(_env(env).get(key, "") or default)
    except (TypeError, ValueError):
        return default
    return val if val > 0 else default


def _num(v: Any) -> Optional[float]:
    """A sentinel field as a number, or None: a torn, blank, bool or string field is no reading."""
    if isinstance(v, bool) or v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return float(str(v).strip())
    except ValueError:
        return None


def deadline_mode(
    off_file: str, shadow_file: str, env: Optional[Mapping[str, str]] = None
) -> str:
    """'off' | 'shadow' | 'on'. A file in recon/ wins (operator, read every pass, no reload)."""
    e = _env(env)
    try:
        if os.path.exists(off_file) or e.get("LR_DEADLINE") == "off":
            return "off"
        if os.path.exists(shadow_file) or e.get("LR_DEADLINE") == "shadow":
            return "shadow"
    except (OSError, TypeError, ValueError):
        return "off"  # an unreadable switch is today's gates, never a bypass
    return "on"


def ensure_deadline(rec: Any, env: Optional[Mapping[str, str]] = None) -> bool:
    """Set once: detected + W_soft. Never reset by an attempt, a hop or a restart (REPORT §5).
    Returns whether it was set now. Idle moves get none. Never raises."""
    try:
        if rec.kind == "limited" and rec.deadline_at is None and rec.timeline.detected:
            rec.deadline_at = float(rec.timeline.detected) + _env_float(
                env, "LR_DEADLINE_SOFT_S", DEADLINE_SOFT_S
            )
            return True
    except (AttributeError, TypeError, ValueError):
        pass
    return False


def wake_due(rec: Any, wake_after_s: float = WAKE_AFTER_S) -> Optional[float]:
    """When a reset wake is due (_wakes' own test), or None: not a wake, or a reset nobody knows."""
    w = rec.wait
    if (
        rec.phase != "PRE-MOVE"
        or rec.substate not in WAKE_SUBSTATES
        or w is None
        or w.detail
        == "wait-data"  # a strand plan.movers re-offers: a mover, not a wake
        or w.eta is None
    ):
        return None
    return float(w.eta) + (
        0.0 if w.detail == "stay" else wake_after_s + jitter_s(rec.sid)
    )


def sync_deadline(rec: Any, env: Optional[Mapping[str, str]] = None) -> bool:
    """Efficacy 8: a record that leaves a reset wait for a move takes max(deadline_at, wake_due +
    W_wake), the same treatment as a sleep. Without it a weekly-reset strand re-offered by
    plan.movers came back overdue by hours and jumped every fresh detection. The wake's due time
    is remembered while it waits (close.wake_due) and applied once it has left. Never raises."""
    try:
        due = wake_due(rec)
        if due is not None:
            rec.close["wake_due"] = due
            return False
        last = rec.close.get("wake_due")
        if last is None:
            return False
        rec.close.pop("wake_due", None)
        new = float(last) + _env_float(env, "LR_DEADLINE_WAKE_S", DEADLINE_WAKE_S)
        if rec.kind == "limited" and (rec.deadline_at is None or rec.deadline_at < new):
            rec.deadline_at = new
            return True
    except (AttributeError, TypeError, ValueError):
        pass
    return False


def deadline_of(
    rec: Any,
    env: Optional[Mapping[str, str]] = None,
    wake_after_s: float = WAKE_AFTER_S,
) -> Optional[float]:
    """The record's deadline: a reset wake's due + W_wake while it waits on a reset, else
    deadline_at (or detected + W_soft before ensure_deadline has run). None: no deadline (idle,
    terminal, or a reset nobody knows). Never raises (F-B): an unreadable record has none."""
    try:
        if rec.terminal is not None or rec.kind != "limited":
            return None
        if rec.phase == "PRE-MOVE" and rec.substate in WAKE_SUBSTATES:
            due = wake_due(rec, wake_after_s)
            w = rec.wait
            if due is not None:
                return due + _env_float(env, "LR_DEADLINE_WAKE_S", DEADLINE_WAKE_S)
            if w is None or w.detail != "wait-data":
                return None  # waiting on a reset nobody knows: physics, not a gate
        if rec.deadline_at is not None:
            return float(rec.deadline_at)
        d = rec.timeline.detected
        return (
            float(d) + _env_float(env, "LR_DEADLINE_SOFT_S", DEADLINE_SOFT_S)
            if d
            else None
        )
    except (AttributeError, TypeError, ValueError):
        return None


def overdue(rec: Any, now: float, env: Optional[Mapping[str, str]] = None) -> bool:
    """Past its deadline. Unknown (any error) is NOT overdue: the bypass needs evidence."""
    d = deadline_of(rec, env)
    try:
        return d is not None and float(now) >= d
    except (TypeError, ValueError):
        return False


# ── the hard stop: read in-process, never forks, never raises ────────────────────────────────────
_LIBC: List[Any] = []
_THERM_TOK: List[Optional[int]] = [None]


def _libc() -> Any:
    if not _LIBC:
        _LIBC.append(ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True))
    return _LIBC[0]


def _thermal_cancel() -> None:
    tok = _THERM_TOK[0]
    _THERM_TOK[0] = None
    if tok is not None:
        try:
            _libc().notify_cancel(tok)
        except Exception:  # noqa: BLE001 — at exit nothing may raise
            pass


def thermal_level() -> Optional[int]:
    """The thermal pressure notify state (0 nominal … 3 trapping), None when unreadable. F-B: the
    token is registered ONCE per process, with argtypes/restype set, and cancelled at exit; a
    per-call register leaked one notify port per pass."""
    try:
        lib = _libc()
        if _THERM_TOK[0] is None:
            lib.notify_register_check.argtypes = [
                ctypes.c_char_p,
                ctypes.POINTER(ctypes.c_int),
            ]
            lib.notify_register_check.restype = ctypes.c_uint32
            lib.notify_get_state.argtypes = [
                ctypes.c_int,
                ctypes.POINTER(ctypes.c_uint64),
            ]
            lib.notify_get_state.restype = ctypes.c_uint32
            lib.notify_cancel.argtypes = [ctypes.c_int]
            lib.notify_cancel.restype = ctypes.c_uint32
            tok = ctypes.c_int(0)
            if lib.notify_register_check(
                b"com.apple.system.thermalpressurelevel", ctypes.byref(tok)
            ):
                return None
            _THERM_TOK[0] = int(tok.value)
            atexit.register(_thermal_cancel)
        st = ctypes.c_uint64(0)
        if lib.notify_get_state(_THERM_TOK[0], ctypes.byref(st)):
            return None
        return int(st.value)
    except Exception:  # noqa: BLE001 — unreadable is unknown, never a stop
        return None


def pressure_level() -> Optional[int]:
    """kern.memorystatus_vm_pressure_level: 1 normal, 2 warn, 4 critical; None when unreadable."""
    try:
        v, sz = ctypes.c_int(0), ctypes.c_size_t(ctypes.sizeof(ctypes.c_int))
        if _libc().sysctlbyname(
            b"kern.memorystatus_vm_pressure_level",
            ctypes.byref(v),
            ctypes.byref(sz),
            None,
            ctypes.c_size_t(0),
        ):
            return None
        return int(v.value)
    except Exception:  # noqa: BLE001
        return None


class HardStop:
    """'' = no positive evidence of a physical limit. Unknown is NOT a stop (operator premise) and is
    named 'unknown', never 'ok'. Three sources, each with its own release rule ("release != !trip"):
      sentinel  trips on strk > 0 or pct >= SEG_HARD_PCT; a clear read is fresh, strk 0, pct <= 50;
      pressure  trips at level >= PRESSURE_HARD; a clear read is any lower level;
      thermal   trips at level >= THERMAL_HARD; a clear read is any lower level.
    A tripped source releases after two clear reads >= RELEASE_GAP_S apart. A tripped source whose
    reads turn unknown (a stale sentinel, a failed sysctl) stays tripped for at most
    UNKNOWN_RELEASE_S, then releases with a ``hardstop-unknown-release`` event (correctness F-I:
    the sentinel log goes stale for hours, and a release that needed a fresh row pinned the bypass
    off). Every read is in-process: no fork, no subprocess, no timeout of ours to misread."""

    SOURCES = ("sentinel", "pressure", "thermal")

    def __init__(
        self,
        env: Optional[Mapping[str, str]] = None,
        sentinel_log: Optional[str] = None,
        pressure: Optional[Callable[[], Optional[int]]] = None,
        thermal: Optional[Callable[[], Optional[int]]] = None,
        wall: Optional[Callable[[], float]] = None,
    ) -> None:
        self.env = env
        self.sentinel_log = sentinel_log
        self.pressure = pressure or pressure_level
        self.thermal = thermal or thermal_level
        self.wall = wall or time.time
        self.state = "unknown"
        self.tripped: Dict[
            str, Dict[str, Any]
        ] = {}  # source -> {since, why, clear_at, unknown_at}
        self.events: List[Tuple[str, str]] = []  # (ev, detail), drained by the caller

    def _log(self) -> str:
        if self.sentinel_log:
            return self.sentinel_log
        e = _env(self.env)
        return e.get("CC_SENTINEL_LOG") or os.path.join(
            e.get("HOME") or os.path.expanduser("~"),
            ".claude",
            "logs",
            "compressor-sentinel.jsonl",
        )

    def _sentinel(self, wall: float) -> Tuple[str, str]:
        """('trip'|'clear'|'mid'|'unknown', why) from the last row, fresh iff its ts is <= 60 s old."""
        try:
            with open(self._log(), "rb") as fh:
                fh.seek(0, os.SEEK_END)
                size = fh.tell()
                fh.seek(max(0, size - 4096))
                tail = fh.read().decode("utf-8", "replace")
            lines = [ln for ln in tail.splitlines() if ln.strip()]
            row = json.loads(lines[-1]) if lines else None
            if not isinstance(row, dict):
                return "unknown", "sentinel row unreadable"
            ts = calendar.timegm(
                time.strptime(str(row.get("ts")), "%Y-%m-%dT%H:%M:%SZ")
            )
            if abs(wall - ts) > SENTINEL_FRESH_S:
                return "unknown", "sentinel stale"
            strk, pct = _num(row.get("strk")), _num(row.get("pct"))
            if strk is not None and strk > 0:
                return "trip", "compressor breach (sentinel strk %d)" % int(strk)
            if pct is not None and pct >= SEG_HARD_PCT:
                return "trip", "compressor %.1f%%" % pct
            if pct is None:
                return "unknown", "sentinel pct unreadable"
            return ("clear" if pct <= SEG_HARD_PCT - 10 else "mid"), ""
        except Exception:  # noqa: BLE001 — torn, blank, string or absent: unknown, never a stop
            return "unknown", "sentinel unreadable"

    @staticmethod
    def _level(
        fn: Callable[[], Optional[int]], hard: int, name: str
    ) -> Tuple[str, str]:
        try:
            lvl = fn()
        except Exception:  # noqa: BLE001
            lvl = None
        if lvl is None or isinstance(lvl, bool):
            return "unknown", ""
        try:
            lvl = int(lvl)
        except (TypeError, ValueError):
            return "unknown", ""
        return ("trip", "%s level %d" % (name, lvl)) if lvl >= hard else ("clear", "")

    def check(self) -> str:
        """The first tripped source's reason, or ''. Never raises (F-B)."""
        try:
            return self._check()
        except Exception as e:  # noqa: BLE001
            self.state = "unknown"
            self.events.append(("hardstop-error", repr(e)[:160]))
            return ""

    def _check(self) -> str:
        wall = self.wall()
        reads = {
            "sentinel": self._sentinel(wall),
            "pressure": self._level(self.pressure, PRESSURE_HARD, "memory pressure"),
            "thermal": self._level(self.thermal, THERMAL_HARD, "thermal"),
        }
        for src in self.SOURCES:
            verdict, why = reads[src]
            t = self.tripped.get(src)
            if t is None:
                if verdict == "trip":
                    self.tripped[src] = {
                        "since": wall,
                        "why": why,
                        "clear_at": None,
                        "unknown_at": None,
                    }
                    self.events.append(("hardstop-trip", "%s: %s" % (src, why)))
                continue
            if verdict == "trip":
                t.update(why=why, clear_at=None, unknown_at=None)
            elif verdict == "clear":
                t["unknown_at"] = None
                if t["clear_at"] is None:
                    t["clear_at"] = wall
                elif wall - t["clear_at"] >= RELEASE_GAP_S:
                    del self.tripped[src]
                    self.events.append(
                        ("hardstop-release", "%s: two clear reads" % src)
                    )
            elif verdict == "mid":
                t.update(
                    clear_at=None, unknown_at=None
                )  # not over the line, not clear of it
            else:
                t["clear_at"] = None
                if t["unknown_at"] is None:
                    t["unknown_at"] = wall
                elif wall - t["unknown_at"] >= UNKNOWN_RELEASE_S:
                    del self.tripped[src]
                    self.events.append(
                        (
                            "hardstop-unknown-release",
                            "%s: tripped on %s, unreadable for %ds; released to unknown"
                            % (src, t["why"], int(wall - t["unknown_at"])),
                        )
                    )
        if self.tripped:
            self.state = "tripped"
            src = min(self.tripped, key=lambda s: self.tripped[s]["since"])
            return "%s" % self.tripped[src]["why"]
        known = reads["sentinel"][0] != "unknown" or reads["pressure"][0] != "unknown"
        self.state = "ok" if known else "unknown"
        return ""

    def tripped_since(self) -> Optional[float]:
        return min((t["since"] for t in self.tripped.values()), default=None)


# ── slot priority: the move lane yields boot slots to overdue reconciler records ─────────────────
def slot_priority_path(lr_root: str) -> str:
    return os.path.join(lr_root, "locks", SLOT_PRIORITY)


def write_slot_priority(
    lr_root: str, now: float, last_pass_s: float, why: str
) -> float:
    """``until`` = now + max(180 s, 2 × the last pass): a fixed lease from the WRITE would lapse
    inside one long pass, so the writer also refreshes it from clock.step. lr-move-lib.sh's acquire
    caps the move lane at 1 slot while ``until`` > its own clock. Returns until (0 = not written)."""
    try:
        if os.path.exists(os.path.join(lr_root, "locks", SLOT_YIELD_OFF)):
            return 0.0
        until = float(now) + max(
            SLOT_PRIORITY_MIN_S, 2.0 * max(0.0, float(last_pass_s))
        )
        atomic_write(
            slot_priority_path(lr_root),
            "until=%d\npid=%d\nwhy=%s\n"
            % (int(until), os.getpid(), why.replace("\n", " ")[:120]),
        )
        return until
    except (OSError, TypeError, ValueError):
        return 0.0


def slot_priority_until(lr_root: str) -> Optional[float]:
    """The standing file's until, or None (absent or unreadable)."""
    try:
        with open(slot_priority_path(lr_root), encoding="utf-8") as fh:
            for ln in fh:
                if ln.startswith("until="):
                    return float(ln[len("until=") :].strip())
    except (OSError, ValueError):
        pass
    return None


def clear_slot_priority(lr_root: str) -> bool:
    try:
        os.unlink(slot_priority_path(lr_root))
        return True
    except OSError:
        return False


class Admission:
    """One per ACTIVE period (§C6). ``enter_active`` freezes R and L_open; ``leave_active`` clears all."""

    def __init__(
        self,
        runner: Optional[Runner] = None,
        repo: Optional[str] = None,
        env: Optional[Mapping[str, str]] = None,
        wall: Optional[Callable[[], float]] = None,
    ) -> None:
        self.runner: Runner = runner or default_runner
        self.repo = repo or REPO_ROOT
        # the pace's and the drip's clock, read at decide time; never the pass's ``now``
        self.wall: Callable[[], float] = wall or time.time
        # B7: the pacer reads the wall too; the reconciler's recon/pass-clock kill switch clears it
        self.pacer_on_wall = True
        e = env if env is not None else os.environ
        self.pacer_per_acct = _env_int(e, "LR_PACER_PER_ACCT", 3)
        self.restore_r: Optional[int] = None
        # the per-core load at ACTIVE entry: recorded for the record, no gate reads it
        self.l_open: Optional[float] = None
        self.entered_at: Optional[float] = None
        self.last_admit_at: Optional[float] = None
        self.pace_tokens = float(PACE_BURST)
        self.pace_at: Optional[float] = None  # wall time of the last refill
        self.pacer: Dict[str, Dict[str, float]] = {}  # acct -> {sid: submitted_at}
        self.refusals: Dict[str, int] = {}  # cohort -> consecutive probe refusals
        self.last_drip_at: Dict[str, float] = {}
        self.paged: Set[str] = set()
        self.page_due = False
        # the restore budget's numbers at the last decide, for the status line
        self.last_terms = ""
        self.over_at: Dict[
            str, float
        ] = {}  # cohort -> the pass that last counted a restore-r
        # W11 (B3): the hard stop is read only on an overdue admission; a test or a caller that
        # builds Admission directly gets the default (F-L)
        self.hard = HardStop()
        self.deadline_why = ""  # why the last overdue decide fell through (reset each decide)
        self.drip_pages: List[str] = []  # cohorts whose drip opened, drained by the reporter
        # W11 lever 5: the probe at most once per pass. pass_now is set by begin_pass; a caller that
        # never opens a pass (a direct decide) reads the probe per call, as before
        self.pass_now: Optional[float] = None
        self.probe_memo: Optional[Tuple[bool, str]] = None
        self.probe_counted: Dict[str, float] = {}  # cohort -> the pass that counted a refusal
        self.probe_calls = 0

    # ── gate 1: the frozen restore budget ────────────────────────────────────────────────────
    def enter_active(
        self,
        a_open: int,
        c_open: int,
        ceiling: int,
        load1: float = 0.0,
        load5: float = 0.0,
        ncpu: int = 1,
        now: float = 0.0,
    ) -> int:
        """Freeze R = max(ceiling, A_open + C_open) and L_open once. Idempotent while ACTIVE: a later
        death turns one active session into one corpse, so recomputing could only drift."""
        if self.restore_r is None:
            self.restore_r = max(ceiling, a_open + c_open)
            self.l_open = max(load1, load5) / max(ncpu, 1)
            self.entered_at = now
        return self.restore_r

    def leave_active(self) -> None:
        """DORMANT: every frozen term and counter goes, so the next ACTIVE period starts clean."""
        self.restore_r = None
        self.l_open = None
        self.entered_at = None
        self.last_admit_at = None
        self.pace_tokens = float(PACE_BURST)
        self.pace_at = None
        self.pacer.clear()
        self.refusals.clear()
        self.last_drip_at.clear()
        self.paged.clear()
        self.over_at.clear()
        self.page_due = False
        self.drip_pages = []  # F-L
        self.probe_counted.clear()
        self.probe_memo = None

    def begin_pass(self, now: float) -> None:
        """The dispatcher opens a pass (W11 lever 5). From here a REFUSING probe reading counts once
        per pass toward DRIP_AFTER and is reused for every later candidate of the pass, so the
        fall-through paths no longer make the pass length grow with the cohort (B2 review C3: the
        command is sid-free, so k calls asked one question k times). An admitting reading admits
        one member; the next candidate reads again. Semantics change, stated: the drip opens after
        DRIP_AFTER refusing PASSES, not members."""
        self.pass_now = now
        self.probe_memo = None
        self.deadline_why = ""

    def _probe_pass(self, restore_r: int) -> Tuple[bool, str]:
        if self.pass_now is not None and self.probe_memo is not None:
            return self.probe_memo
        self.probe_calls += 1
        ok, why = self.probe(restore_r)
        if self.pass_now is not None and not ok:
            self.probe_memo = (ok, why)
        return ok, why

    def restore_ok(self, active: int, unredeemed: int) -> bool:
        """``active + unredeemed + 1 <= R``: an admitted-but-unredeemed token is already on its way in."""
        return self.restore_r is not None and active + unredeemed + 1 <= self.restore_r

    # ── gate 2: the wall-clock pace ──────────────────────────────────────────────────────────
    def pace_ok(self, wall: float) -> bool:
        """A token is free: the bucket refills one per PACE_EVERY_S of wall time up to PACE_BURST.
        No load term: under the operator's premise load never falls, so any load term is a wait
        that never ends (REPORT §3.2). The memory terms stay with the probe (gate 4)."""
        if self.pace_at is not None and wall > self.pace_at:
            self.pace_tokens = min(
                float(PACE_BURST),
                self.pace_tokens + (wall - self.pace_at) / PACE_EVERY_S,
            )
        if self.pace_at is None or wall > self.pace_at:
            self.pace_at = wall
        return self.pace_tokens >= 1.0

    def pace_take(self) -> None:
        self.pace_tokens = max(0.0, self.pace_tokens - 1.0)

    # ── gate 3: the per-target-account pacer ─────────────────────────────────────────────────
    def _expire(self, acct: str, now: float) -> Dict[str, float]:
        slots = self.pacer.setdefault(acct, {})
        for sid in [s for s, at in slots.items() if now - at >= PACER_RELEASE_S]:
            del slots[sid]
        return slots

    def pacer_ok(self, acct: str, now: float, sid: str = "") -> bool:
        slots = self._expire(acct, now)
        return sid in slots or len(slots) < self.pacer_per_acct

    def pacer_take(self, sid: str, acct: str, now: float) -> None:
        self._expire(acct, now)[sid] = now

    def pacer_release(self, sid: str) -> None:
        """On ENGAGED or a TARGET-* verdict: the account has answered, so its slot is free."""
        for slots in self.pacer.values():
            slots.pop(sid, None)

    def pace_wake(self, sid: str, acct: str, now: float) -> Tuple[bool, str]:
        """In-place reset wakes share the pacer; the caller adds ``jitter_s(sid)`` to the wake time."""
        t = self._t_dec(now)
        if not self.pacer_ok(acct, t, sid):
            return False, "pacer:%s" % acct
        self.pacer_take(sid, acct, t)
        return True, "admit"

    def _t_dec(self, now: float) -> float:
        """B7 R2/R3: the pacer's decision instant, the wall but never earlier than the census."""
        return max(now, self.wall()) if self.pacer_on_wall else now

    # ── gate 4: the library's memory terms ───────────────────────────────────────────────────
    def _lib(self) -> str:
        return shlex.quote(os.path.join(self.repo, LIB_REL))

    def probe(self, restore_r: int) -> Tuple[bool, str]:
        """rc 0 admit, rc 9 refuse ("capacity"); the runner's bound firing is "probe-timeout"; any
        other code is "probe-error rc=<N>" (RC_SPAWN_ERROR reads rc=-1).

        The load term is OFF, as lr-lib.sh's probe runs it: the CPU brake (gate 2) is this module's
        load gate. With it on, all 89 of the probe's IDL rows refused on load, and rc 9 was
        reported as "memory" (D1.12). rc 9 now means a memory, segment or active-count term."""
        cmd = (
            "source %s; CC_ADMIT_LOAD_TERM=off CC_ADMIT_RESTORE_R=%d "
            "cc_capacity_probe lr-reconciler first-turn"
            % (
                self._lib(),
                int(restore_r),
            )
        )
        rc, _ = self.runner(["bash", "-c", cmd])
        if rc == 0:
            return True, "admit"
        if rc == 9:
            return False, "capacity"
        if rc == RC_TIMEOUT:
            return False, "probe-timeout"
        return False, "probe-error rc=%d" % rc

    def library_probe(self, restore_r: int) -> bool:
        return self.probe(restore_r)[0]

    def mint_token(self, sid: str, owes_prompt: bool = True) -> Optional[str]:
        """One-shot sid-bound admission token via ``cc_capacity_token_mint``; returns its path.

        The KIND is always passed, never inherited: a move that owes no prompt relaunches a session
        that is already counted where it sits, so its token is ``swap`` and stays out of the
        in-flight count (capacity-admit.sh, "WHAT A TOKEN IS AN ADMISSION OF"). Before 2026-10-18
        every reconciler token minted as ``turn`` by default (lr-wake c2 §2.6)."""
        if not _SID_OK.match(sid):
            return None
        kind = "turn" if owes_prompt else "swap"
        cmd = (
            'source %s; CC_ADMIT_TOKEN_KIND="$2" cc_capacity_token_mint "$1"'
            % self._lib()
        )
        rc, out = self.runner(["bash", "-c", cmd, "lr-admit", sid, kind])
        lines = [ln.strip() for ln in out.splitlines() if ln.strip()]
        if rc != 0 or not lines:
            return None
        return lines[-1]

    # ── the decision ─────────────────────────────────────────────────────────────────────────
    def decide(
        self,
        sid: str,
        acct: str,
        now: float,
        active: int,
        unredeemed: int,
        load1: float,
        load5: float,
        ncpu: int,
        cohort: str = "",
        overdue: bool = False,
        lane_room: bool = False,
    ) -> Tuple[bool, str]:
        """Apply R, the pace, the pacer, then the probe. The reason names the first gate that refused
        ("restore-r", "pace", "pacer:<acct>", "capacity", "probe-timeout", "probe-error rc=<N>", "drip");
        "admit" or "admit:drip" otherwise. An admission takes a pace token and a pacer slot and resets
        the cohort's refusal run.

        load1, load5 and ncpu are accepted for the caller's symmetry with ``enter_active``; no gate
        here reads them (REPORT §4 A4: under a load that never falls, a load gate never opens)."""
        del load1, load5, ncpu
        self.deadline_why = ""  # F-L: never sticky across calls
        if overdue:
            # W11: the overdue branch first. Only with lane room and a clear hard stop does it admit;
            # otherwise the call falls through to today's path unchanged (never worse than today).
            if lane_room:
                hard = self.hard.check()
                if not hard:
                    self.pace_ok(self.wall())
                    self.pace_take()  # charged, never required (the bucket floors at 0)
                    t_dec = self._t_dec(now)
                    self.pacer_take(sid, acct, t_dec)  # charged, never refused
                    self.last_admit_at = t_dec
                    self.last_terms = "deadline (memory %s)" % self.hard.state
                    return True, "admit:deadline"  # restore-r, probe and drip untouched
                self.deadline_why = "hard:" + hard
            else:
                self.deadline_why = "deadline-lane"
        self.last_terms = "active %d + in flight %d + 1 vs R %s" % (
            active,
            unredeemed,
            "unset" if self.restore_r is None else self.restore_r,
        )
        if self.restore_r is None:
            return False, "restore-r"
        # THE RESTORE BUDGET IS BOUNDED LIKE THE PROBE THAT CARRIES THE SAME TERM (2026-10-13,
        # 14233392). `active` is every mid-turn session on the machine, so once the rest of the fleet
        # is busier than it was at ACTIVE entry this refuses on every pass: measured active 12,
        # in flight 0, R frozen at the floor of 8, one member refused from 1791856395 until its
        # reset. The probe's active term reads the same R and has always opened the drip after
        # DRIP_AFTER refusals; this check ran in front of it and returned before that bound. It now
        # counts in the same run, and past the run only the pace, the pacer and the drip's own
        # clock decide. The run counts PASSES, not members: inside one pass the budget binds
        # exactly as before, however many members it refuses.
        over = not self.restore_ok(active, unredeemed)
        if over and self.refusals.get(cohort, 0) < DRIP_AFTER:
            if self.over_at.get(cohort) != now:
                self.over_at[cohort] = now
                self.refusals[cohort] = self.refusals.get(cohort, 0) + 1
            return False, "restore-r"
        if not self.pace_ok(self.wall()):
            return False, "pace"
        if not self.pacer_ok(acct, self._t_dec(now), sid):
            return False, "pacer:%s" % acct
        ok, reason = (False, "restore-r") if over else self._probe_pass(self.restore_r)
        if not ok:
            run = self.refusals.get(cohort, 0)
            if run < DRIP_AFTER:
                if self.pass_now is None or self.probe_counted.get(cohort) != self.pass_now:
                    self.probe_counted[cohort] = (
                        self.pass_now if self.pass_now is not None else now
                    )
                    self.refusals[cohort] = run + 1
                return False, reason
            # wall time, read after the probe: a pass is one ``now`` however long it runs, so a
            # pass-scoped drip clock opened at most once per pass (REPORT §3.2, axis 01 F3)
            wall = self.wall()
            last = self.last_drip_at.get(cohort)
            if last is not None and wall - last < DRIP_EVERY_S:
                return False, "drip"
            if cohort not in self.paged:
                self.paged.add(cohort)
                self.page_due = True
                self.drip_pages.append(cohort)  # W11 lever 8: one DRIP page per cohort
            self.last_drip_at[cohort] = wall
            reason = "admit:drip"
        else:
            reason = "admit"
            self.refusals[cohort] = 0
        # B7: re-read after the probe (up to 30 s), so the slot is stamped at the admission itself
        t_dec = self._t_dec(now)
        self.last_admit_at = t_dec
        self.pace_take()
        self.pacer_take(sid, acct, t_dec)
        return True, reason


class BootSlots:
    """TUI boots in flight (relaunch typed -> painted), AIMD (§6): start 6, +2 after a wave where every
    boot painted within 15 s, halve on any boot over 45 s or INDETERMINATE, floor 2, cap LR_BOOT_MAX.
    Boots are the resource that failed at load 40+; actuator subprocesses are bounded separately."""

    START = 6
    FLOOR = 2
    FAST_S = 15.0
    SLOW_S = 45.0

    def __init__(
        self, env: Optional[Mapping[str, str]] = None, store: str = ""
    ) -> None:
        e = env if env is not None else os.environ
        self.cap = _env_int(e, "LR_BOOT_MAX", 12)
        self.workers_cap = _env_int(e, "LR_RECON_WORKERS", 16)
        self.limit = min(self.START, self.cap)
        self.held: Set[str] = set()
        # THE SHARED STORE (design-swap-v3 critic 11, 2026-10-04). `cc-lr move` bounds its own boots
        # with mkdir slots under <lr_root>/locks/swap-slots (lr-move-lib.sh lr_swap_slot_acquire).
        # Two counters that cannot see each other bound nothing together: 6 boots here plus 4 there
        # is 10 at once on a box never measured above 4. With a store, a boot slot is ALSO one of
        # those directories, holding this daemon's (pid, lstart) in the two files the bash side
        # reads, so each dispatcher's width counts the other's boots. Empty store = memory only.
        self.store = store
        self.disk: Dict[str, str] = {}

    @staticmethod
    def _holder(d: str) -> Tuple[Optional[int], str]:
        """(pid, lstart) a slot dir names; pid None when it names none (or is unreadable)."""
        try:
            with open(os.path.join(d, "pid"), "r", encoding="utf-8") as fh:
                pid: Optional[int] = int(fh.read().strip() or "0") or None
        except (OSError, ValueError):
            pid = None
        try:
            with open(os.path.join(d, "lstart"), "r", encoding="utf-8") as fh:
                want = " ".join(fh.read().split())
        except OSError:
            want = ""
        return pid, want

    @staticmethod
    def _slot_live(d: str) -> bool:
        """Is the slot's holder alive? Unknown (our own ps timeout) reads as alive."""
        from lr_recon.store import UNKNOWN, cached_self_lstart, proc_lstart

        pid, want = BootSlots._holder(d)
        if pid is None:
            # no pid yet: a taker between its mkdir and its stamp, unless the slot is old
            try:
                return time.time() - os.stat(d).st_mtime < 60
            except OSError:
                return False
        if pid == os.getpid():
            # W9 (B2 F5, review C6): our own slot runs no ps (acquiring the 6th cost 5 self reads),
            # and an unknown self lstart keeps it live — a "" read wiped our own slot for a 2nd sid
            me = cached_self_lstart()
            return not want or not me or want == me
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        except OSError:
            pass
        cur = proc_lstart(pid, unknown=UNKNOWN)
        return not want or not cur or cur == UNKNOWN or want == cur

    STEAL_LOCK_STALE_S = (
        60.0  # a slot-N.steal this old is a stealer that died holding it
    )

    @staticmethod
    def _stamp(d: str) -> None:
        from lr_recon.store import self_lstart

        with open(os.path.join(d, "pid"), "w", encoding="utf-8") as fh:
            fh.write("%d\n" % os.getpid())
        with open(os.path.join(d, "lstart"), "w", encoding="utf-8") as fh:
            fh.write(self_lstart() + "\n")

    def _steal_locked(self, d: str) -> bool:
        """Take a slot judged dead IN PLACE, under its own lock — lr_swap_slot_acquire's protocol
        (lr-move-lib.sh), so the two dispatchers serialize on one name. The taker that wins
        ``mkdir <slot>.steal`` re-judges the holder there (a fresh read, not the one it acted on)
        and overwrites pid/lstart; every other taker skips the slot this round. Nothing is moved, so
        no live take can be displaced: unlinking in place without a lock let 12 processes believe
        they held 6 slots (G2 C6), and moving the slot aside still let a third taker re-create the
        path before a mistaken move was undone. Returns whether we stamped it."""
        lock = d + ".steal"
        try:
            os.mkdir(lock)
        except FileExistsError:
            try:
                if time.time() - os.stat(lock).st_mtime > self.STEAL_LOCK_STALE_S:
                    os.rmdir(lock)
            except OSError:
                pass
            return False
        except OSError:
            return False
        try:
            if not os.path.isdir(d) or self._slot_live(d):
                return False
            self._stamp(d)
            return True
        except OSError:
            return False
        finally:
            try:
                os.rmdir(lock)
            except OSError:
                pass

    def _disk_take(self, sid: str) -> bool:
        try:
            os.makedirs(self.store, exist_ok=True)
        except OSError:
            return True  # an unwritable store must not stop every boot: memory still bounds them
        locked = os.environ.get("LR_BOOT_SLOT_STEAL", "") != "unlink"
        for i in range(1, self.limit + 1):
            d = os.path.join(self.store, "slot-%d" % i)
            try:
                os.mkdir(d)
                self._stamp(d)
            except FileExistsError:
                if self._slot_live(d):
                    continue
                if locked:
                    if not self._steal_locked(d):
                        continue
                else:  # the pre-W9 unlocked wipe (LR_BOOT_SLOT_STEAL=unlink, the race's control)
                    try:
                        self._stamp(d)
                    except OSError:
                        continue
            except OSError:
                continue
            if locked and self._holder(d)[0] != os.getpid():
                continue  # every stamp is re-read: a racer took it between our judge and stamp
            self.disk[sid] = d
            return True
        return False

    def on_wave(self, durations: Sequence[Optional[float]]) -> int:
        """One finished wave; a ``None`` duration is an INDETERMINATE boot. Returns the new limit."""
        if not durations:
            return self.limit
        if any(d is None or d > self.SLOW_S for d in durations):
            self.limit = max(self.FLOOR, self.limit // 2)
        elif all(d is not None and d <= self.FAST_S for d in durations):
            self.limit = min(self.cap, self.limit + 2)
        return self.limit

    def acquire(self, sid: str) -> bool:
        if sid in self.held:
            return True
        if len(self.held) >= self.limit:
            return False
        if self.store and not self._disk_take(sid):
            return False
        self.held.add(sid)
        return True

    def release(self, sid: str) -> None:
        self.held.discard(sid)
        d = self.disk.pop(sid, "")
        if d:
            for name in ("pid", "lstart"):
                try:
                    os.unlink(os.path.join(d, name))
                except OSError:
                    pass
            try:
                os.rmdir(d)
            except OSError:
                pass
