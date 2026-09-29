"""Sleep-aware clock, wake guard, heartbeat thread and caffeinate hold (§C2, §4.3, invariant 29).

A laptop lid close freezes the daemon mid-pass; on wake every wall-clock deadline has silently
expired at once. ``Clock.tick`` measures the pause as Δwall − Δuptime (CLOCK_UPTIME_RAW does not
advance during sleep), so callers can shift deadlines by it and spend the next pass observing
instead of acting on a world that moved while we were frozen. Every external effect (time
sources, sysctl, load, process spawn, file write) is an injectable seam so tests stay hermetic.
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
        cp = subprocess.run(
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
        getloadavg: Callable[[], Tuple[float, float, float]] = os.getloadavg,
        cpu_count: Callable[[], Optional[int]] = os.cpu_count,
        env: Optional[Mapping[str, str]] = None,
    ) -> None:
        self.wall = wall
        self.uptime = uptime
        self._sysctl = sysctl
        self._getloadavg = getloadavg
        self._cpu_count = cpu_count
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

    def tick(self) -> float:
        """Return seconds slept since the previous tick (0.0 below threshold or on first call)."""
        now = (self.wall(), self.uptime())
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

    def load_multiplier(self) -> float:
        """§4.3: process bounds scale by max(1, load1/ncpu/2) so a loaded box is not convicted
        of a hang it merely queued behind."""
        try:
            load1 = float(self._getloadavg()[0])
        except (OSError, IndexError, TypeError, ValueError):
            return 1.0
        ncpu = self._cpu_count() or 1
        return max(1.0, load1 / ncpu / 2)


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
    frozen counter — the two failure modes stay distinguishable."""

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
            )

    def render(self) -> str:
        # Compact separators: bash readers sed `"key":value` out of it.
        return json.dumps(T.to_dict(self.snapshot()), separators=(",", ":")) + "\n"

    def advance(self) -> None:
        with self._lock:
            self.progress += 1
            self.progress_wall = self.clock.wall()

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
