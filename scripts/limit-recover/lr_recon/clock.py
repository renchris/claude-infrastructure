"""Sleep-aware clock, wake guard, heartbeat thread and caffeinate hold (§C2, §4.3, invariant 29).

A laptop lid close freezes the daemon mid-pass; on wake every wall-clock deadline has silently
expired at once. ``Clock.tick`` measures the pause as Δwall − Δuptime (CLOCK_UPTIME_RAW does not
advance during sleep), so callers can shift deadlines by it and spend the next pass observing
instead of acting on a world that moved while we were frozen. Every external effect (time
sources, sysctl, process spawn, file write) is an injectable seam so tests stay hermetic.

The two clocks of one pass (B7, docs/research/lr-sustained-load-2026-10-20/impl/B7-now-audit.md §1).
``now`` is the CENSUS instant: the census, facts and evidence were read at about that moment, and
the pass then runs for minutes. ``t_dec = max(now, wall())`` is the instant a decision is taken.

  R1  an observation (what a census saw) is stamped with ``now``, and census stamps compare to ``now``
  R2  an action we take (spawn, admission, pacer slot, launch.log row) is stamped with ``t_dec``
  R3  a rate gate ("no more than one per N s") reads ``t_dec`` against the action stamps
  R4  an evidence wait ("act only on a census taken >= N s after X") reads ``now``, never the wall: a
      later wall reading cannot make an older census newer. C's 60 s grace is one (nothing re-reads
      the transcript before C types), and so is may_actuate's next_eligible_at (R_PROOF_S)
  R5  a quiet window ("X absent >= N s") runs from the FIRST census that did not see X (a lower
      bound), never the last that did (an upper bound); each census stamps its sighting before any
      reader in the same pass (settle.note_seen / quiet_for)
  R6  updated_at is rewritten every pass, so it is never an age anchor
  R7  a stamp used as pass identity stays ``now`` (busy_at at _invariant, Admission.over_at)

``max(now, wall())`` is never earlier than the census instant, so a test that drives ``now`` by
hand keeps its semantics. ``recon/pass-clock`` = ``pass`` reverts t_dec and the wall pacer.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import threading
import time
from typing import Any, Callable, Dict, Mapping, Optional, Sequence, Tuple

from lr_recon import types as T

SLEEP_THRESHOLD_S = 5.0
WAKE_GUARD_S = 30
HEARTBEAT_INTERVAL_S = 10
SYSCTL_TIMEOUT_S = 5
CAFFEINATE = "/usr/bin/caffeinate"

_TIMEVAL = re.compile(r"sec\s*=\s*(\d+)\s*,\s*usec\s*=\s*(\d+)")


def _uptime_raw() -> float:
    """CLOCK_UPTIME_RAW stops during sleep, which is what makes Δwall − Δuptime a sleep meter."""
    clk = getattr(time, "CLOCK_UPTIME_RAW", None)
    if clk is not None:
        return time.clock_gettime(clk)
    return time.monotonic()


def _run_sysctl(name: str) -> str:
    """``sysctl -n <name>``, bounded; "" on any failure so callers read it as "no evidence"."""
    try:
        cp = run_bounded(
            ["/usr/sbin/sysctl", "-n", name],
            capture_output=True,
            text=True,
            timeout=SYSCTL_TIMEOUT_S,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return cp.stdout if cp.returncode == 0 else ""


def parse_timeval(text: str) -> Optional[float]:
    """Parse ``{ sec = N, usec = M } <date>`` (with or without the ``kern.x:`` prefix)."""
    m = _TIMEVAL.search(text or "")
    if not m:
        return None
    return int(m.group(1)) + int(m.group(2)) / 1e6


def _env_float(env: Mapping[str, str], name: str, default: float) -> float:
    try:
        return float(env.get(name, "") or default)
    except ValueError:
        return float(default)


def pause_is_sleep(slept: float, threshold: Optional[float] = None) -> bool:
    """Normal scheduler drift is sub-second; anything past the threshold was a real suspend."""
    return slept > (SLEEP_THRESHOLD_S if threshold is None else threshold)


class Clock:
    """Wall + uptime pair with sleep accounting (§C2 "Sleep-aware clock")."""

    def __init__(
        self,
        wall: Callable[[], float] = time.time,
        uptime: Callable[[], float] = _uptime_raw,
        sysctl: Callable[[str], str] = _run_sysctl,
        env: Optional[Mapping[str, str]] = None,
    ) -> None:
        self.wall = wall
        self.uptime = uptime
        self._sysctl = sysctl
        env = os.environ if env is None else env
        self.sleep_threshold_s = _env_float(
            env, "LR_SLEEP_THRESHOLD_S", SLEEP_THRESHOLD_S
        )
        self.wake_guard_s = _env_float(env, "LR_WAKE_GUARD_S", WAKE_GUARD_S)
        self.constructed_wall = wall()
        self.last_wake_wall = (
            self.constructed_wall
        )  # fallback evidence when waketime is unreadable
        self.total_slept = 0.0
        self._last: Optional[Tuple[float, float]] = None
        self._observe_only = False
        self._boottime: Optional[float] = None
        # Rig seam (W5): seconds ADDED to wall time as read by tick() only, from a file the rig
        # writes, so a simulated suspend travels the real detection path (uptime stands still
        # while wall jumps). Unset in production; an unreadable file reads as 0.
        self._skew_file = env.get("LR_RECON_CLOCK_SKEW_FILE", "")

    def _skew(self) -> float:
        if not self._skew_file:
            return 0.0
        try:
            with open(self._skew_file, encoding="utf-8") as fh:
                return float(fh.read().strip() or 0)
        except (OSError, ValueError):
            return 0.0

    def tick(self) -> float:
        """Return seconds slept since the previous tick (0.0 below threshold or on first call)."""
        now = (self.wall() + self._skew(), self.uptime())
        prev, self._last = self._last, now
        if prev is None:
            return 0.0
        slept = (now[0] - prev[0]) - (now[1] - prev[1])
        if not pause_is_sleep(slept, self.sleep_threshold_s):
            return 0.0
        self.total_slept += slept
        self._observe_only = True
        self.last_wake_wall = now[0]
        return slept

    def take_observe_only(self) -> bool:
        """The pass after a sleep only observes: facts gathered before the lid closed are stale."""
        flag, self._observe_only = self._observe_only, False
        return flag

    def waketime(self) -> Optional[float]:
        return parse_timeval(self._sysctl("kern.waketime"))

    def boottime(self) -> Optional[float]:
        if self._boottime is None:
            self._boottime = parse_timeval(self._sysctl("kern.boottime"))
        return self._boottime

    def wake_guard_ok(self, guard_s: Optional[float] = None) -> bool:
        """Invariant 29: no irreversible step within ``guard_s`` of a wake (network, auth and
        panes are still settling). Unreadable waketime falls back to our own evidence — time
        since construction or since the last sleep tick() saw — so we neither block forever
        nor pass on no evidence at startup."""
        guard = self.wake_guard_s if guard_s is None else guard_s
        now = self.wall()
        wt = self.waketime()
        anchor = wt if wt is not None else self.last_wake_wall
        return now - anchor >= guard

    # W8 (G1 F12): load_multiplier, max(1, load1/ncpu/2) uncapped (x20 at 40/core) with no caller,
    # and its getloadavg/cpu_count seam are deleted. A bound that must stretch with load says so in
    # its own function, capped (the G1 lint's capped-bound-stretch class).


def shift_record(rec: T.Record, slept: float) -> None:
    """Move every DEADLINE forward by ``slept``; timeline stamps are history and stay put.
    ``wait.since`` of 0.0 is the unset default and is left alone, like None."""
    if slept <= 0:
        return
    if rec.next_eligible_at is not None:
        rec.next_eligible_at += slept
    if rec.sentinel_until is not None:
        rec.sentinel_until += slept
    if rec.wait is not None:
        if rec.wait.since:
            rec.wait.since += slept
        if rec.wait.eta is not None:
            rec.wait.eta += slept


def atomic_write(path: str, data: str) -> None:
    """tmp in the same dir + fsync + os.replace: a reader never sees a torn heartbeat."""
    d = os.path.dirname(path) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix="." + os.path.basename(path) + ".")
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


class Heartbeat:
    """Dedicated heartbeat thread (§C2). File freshness proves the process is alive; ``progress``
    moves only via ``advance()`` from the main loop, so a wedged loop shows a fresh file with a
    frozen counter — the two failure modes stay distinguishable. Inside a pass the loop advances
    through ``step()`` after each bounded unit, so a long pass made of bounded children reads as
    working while one stuck unit still freezes the counter."""

    def __init__(
        self,
        path: str,
        pid: int,
        lstart: str,
        clock: Clock,
        interval_s: float = HEARTBEAT_INTERVAL_S,
        write: Callable[[str, str], None] = atomic_write,
    ) -> None:
        self.path = path
        self.pid = pid
        self.lstart = lstart
        self.clock = clock
        self.interval_s = interval_s
        self._write = write
        self._lock = threading.Lock()
        self.progress = 0
        self.progress_wall = clock.wall()
        self._progress_up = clock.uptime()
        self.step_due = 0.0
        self.child_bound_s = 0.0
        self.max_step_gap_s = 0.0
        self.max_step_gap_bound_s = 0.0
        self.max_step_gap_at = 0.0
        self.phase = ""
        self.phase_at = 0.0
        self.pass_seq = 0
        self.pass_at = 0.0
        self.write_errors = 0
        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def snapshot(self) -> T.Heartbeat:
        with self._lock:
            return T.Heartbeat(
                pid=self.pid,
                lstart=self.lstart,
                progress=self.progress,
                wall=self.clock.wall(),
                uptime_raw=self.clock.uptime(),
                progress_wall=self.progress_wall,
                step_due=self.step_due,
                child_bound_s=self.child_bound_s,
                max_step_gap_s=self.max_step_gap_s,
                max_step_gap_bound_s=self.max_step_gap_bound_s,
                max_step_gap_at=self.max_step_gap_at,
                phase=self.phase,
                phase_at=self.phase_at,
                pass_seq=self.pass_seq,
                pass_at=self.pass_at,
            )

    def set_phase(self, name: str, seq: int) -> None:
        """B6: the pass's current phase, for a reader of a pass that has not ended. ``begin``
        also stamps ``pass_at``, so a killed pass still leaves how long it had run."""
        with self._lock:
            now = self.clock.wall()
            self.phase, self.phase_at, self.pass_seq = name[:24], now, int(seq)
            if name == "begin":
                self.pass_at = now

    def render(self) -> str:
        # Compact separators: bash readers sed `"key":value` out of it.
        return json.dumps(T.to_dict(self.snapshot()), separators=(",", ":")) + "\n"

    def declare_child(self, bound_s: float) -> None:
        """A bounded child is about to start: the next advance is due by now + ``bound_s``."""
        with self._lock:
            self.step_due = max(self.step_due, self.clock.wall() + bound_s)
            self.child_bound_s = max(self.child_bound_s, bound_s)

    def advance(self) -> None:
        with self._lock:
            up = self.clock.uptime()
            gap = (
                up - self._progress_up
            )  # uptime: a lid-close is not a gap the loop made
            if gap > self.max_step_gap_s:
                self.max_step_gap_s = gap
                self.max_step_gap_bound_s = self.child_bound_s
                self.max_step_gap_at = self.clock.wall()
            self._progress_up = up
            self.progress += 1
            self.progress_wall = self.clock.wall()
            self.step_due = 0.0
            self.child_bound_s = 0.0

    def write_now(self) -> bool:
        try:
            self._write(self.path, self.render())
        except OSError:
            self.write_errors += (
                1  # a full disk must not kill the thread; staleness reports it
            )
            return False
        return True

    def _run(self) -> None:
        self.write_now()
        while not self._stop.wait(self.interval_s):
            self.write_now()

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(
            target=self._run, name="lr-heartbeat", daemon=True
        )
        self._thread.start()

    def stop(self, timeout: Optional[float] = None) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout)
            self._thread = None


_LOOP: Optional[Tuple[Heartbeat, int]] = (
    None  # (heartbeat, ident of the thread that may step it)
)


def bind_steps(hb: Optional[Heartbeat]) -> None:
    """Make the calling thread the loop whose ``step()`` calls advance ``hb``; None unbinds."""
    global _LOOP
    _LOOP = None if hb is None else (hb, threading.get_ident())


def step() -> None:
    """One bounded unit of a pass finished (a stage, a record, a lane, a kitty socket): advance.

    Progress used to move only once per whole pass, and at load 200-500 a pass of 12 records with
    120 s --place probes, 30 s admission probes and kitty reads ran past the watchdog's 900 s
    ceiling while blocked on LIVE children, whose CPU `ps -S` does not count — so the watchdog
    killed a working reconciler three times in an hour on 2026-10-18, each restart mid-pass
    (lr-recon-watchdog.sh condition 4). A step per stage was still not enough: one unit chains
    several bounded children (admission probes, a 120 s --place, ps reads that take 30-40 s under
    load), and on 2026-10-19 the watchdog killed a holder running that fix 186 s into such a unit
    while 58 other samples froze 600-1193 s. So every child the loop thread waits on now goes
    through ``run_bounded``, which declares its bound before the spawn and steps after it: the gap
    between two steps is one child plus the loop's own CPU work, and the watchdog waits out the
    declared bound (heartbeat ``step_due``) before it reads a quiet CPU as a wedge. A wedged unit
    never returns to call step(), so the counter freezes exactly as before. Only the bound thread
    advances: a step from any other thread, or with nothing bound (``--once``, tests), is a no-op."""
    loop = _LOOP
    if loop is not None and loop[1] == threading.get_ident():
        loop[0].advance()


def declare_child(bound_s: float) -> None:
    """The bound loop thread is about to wait up to ``bound_s`` on a child (no-op elsewhere)."""
    loop = _LOOP
    if loop is not None and loop[1] == threading.get_ident():
        loop[0].declare_child(bound_s)


def run_bounded(*args: Any, **kw: Any) -> "subprocess.CompletedProcess[Any]":
    """``subprocess.run`` for a child the loop waits on: the timeout is REQUIRED (an unbounded
    child is the one wait no watchdog margin can cover), declared to the heartbeat before the
    spawn, and the loop steps once the call returns or raises. The default ``run`` of every
    reconciler call site, so a new site inherits the step by default instead of by hand edit."""
    timeout = kw.get("timeout")
    if timeout is None:
        raise TypeError("run_bounded needs timeout=")
    declare_child(float(timeout))
    t0, late = time.monotonic(), False
    try:
        return subprocess.run(*args, **kw)
    except subprocess.TimeoutExpired:
        late = True
        raise
    finally:
        step()
        _note_child(args[0] if args else kw.get("args"), time.monotonic() - t0, late)


def set_phase(name: str, seq: int = 0) -> None:
    """B6: stamp the pass phase on the bound loop's heartbeat (no-op elsewhere). Called by
    __main__ directly, outside the B6 writer's guard, so the phase stays true while that writer is off."""
    loop = _LOOP
    if loop is not None and loop[1] == threading.get_ident():
        loop[0].set_phase(name, seq)


# B6 child ledger: the daemon binds the B6 writer's ``child(label, dur, late)`` here. run_bounded is
# already the one choke point for every child the loop waits on, so a new call site inherits it.
_CHILD_HOOK: Optional[Callable[[str, float, bool], None]] = None
_INTERP = ("bash", "sh", "zsh", "dash", "python3", "python")


def bind_child_hook(fn: Optional[Callable[[str, float, bool], None]]) -> None:
    global _CHILD_HOOK
    _CHILD_HOOK = fn


def child_label(argv: Any) -> str:
    """The ledger label: ``ps:all`` vs ``ps:pid`` (a 1.5 MB census vs a 5 s per-pid read),
    ``probe``/``mint`` for the capacity ``bash -c`` probes, an interpreter's script basename,
    ``claude-accounts --place``, else argv0's basename plus a leading ``--flag``. ≤ 40 chars."""
    a = (
        [str(x) for x in argv]
        if isinstance(argv, (list, tuple))
        else str(argv or "").split()
    )
    if not a:
        return "?"
    b0 = os.path.basename(a[0])
    if b0 == "ps":
        lab = "ps:pid" if "-p" in a else "ps:all"
    elif b0 in _INTERP and len(a) > 1 and a[1] == "-c":
        text = a[2] if len(a) > 2 else ""
        # matched on the suffix: the full function name reads as a bare capacity call to G1's lint
        lab = (
            "probe"
            if "_capacity_probe" in text
            else "mint"
            if "_capacity_token_mint" in text
            else b0 + " -c"
        )
    elif b0 in _INTERP:
        script = next((x for x in a[1:] if not x.startswith("-")), "")
        lab = os.path.basename(script) or b0
    elif b0 == "claude-accounts" and "--place" in a:
        lab = "claude-accounts --place"
    else:
        lab = b0 + (" " + a[1] if len(a) > 1 and a[1].startswith("--") else "")
    return lab[:40]


def _note_child(argv: Any, dur: float, late: bool) -> None:
    """Feed the ledger after step(); never raises, and only the bound loop thread reports."""
    fn = _CHILD_HOOK
    if fn is None:
        return
    try:
        loop = _LOOP
        if loop is None or loop[1] != threading.get_ident():
            return
        fn(child_label(argv), dur, late)
    except Exception:  # noqa: BLE001 — a ledger defect must never replace the child's result
        pass


class Caffeinate:
    """Idle/system-sleep hold while any record is between PLANNED and RELAUNCHED (§C2).
    ``-w <pid>`` ties the child to the daemon so a crashed daemon cannot leak a hold. It cannot
    stop a lid close on battery, which is why ``Clock.tick`` accounting is still required."""

    def __init__(
        self,
        pid: int,
        popen: Callable[..., Any] = subprocess.Popen,
        argv0: str = CAFFEINATE,
    ) -> None:
        self.pid = pid
        self._popen = popen
        self.argv: Sequence[str] = (argv0, "-i", "-s", "-w", str(pid))
        self._child: Optional[Any] = None
        self.spawns = 0

    def _alive(self) -> bool:
        return self._child is not None and self._child.poll() is None

    def set_hold(self, want: bool) -> bool:
        """Idempotent; respawns a child that died while wanted. Returns whether a hold is live."""
        if want:
            if not self._alive():
                kw: Dict[str, Any] = {
                    "stdin": subprocess.DEVNULL,
                    "stdout": subprocess.DEVNULL,
                    "stderr": subprocess.DEVNULL,
                }
                try:
                    self._child = self._popen(list(self.argv), **kw)
                    self.spawns += 1
                except OSError:
                    self._child = None
            return self._alive()
        if self._alive():
            child = self._child
            assert child is not None
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=2)
        self._child = None
        return False

    def close(self) -> None:
        self.set_hold(False)
