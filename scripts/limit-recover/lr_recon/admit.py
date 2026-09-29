"""admit.py: first-turn admission for one ACTIVE period (§C6, §6).

Four gates guard a limited session's FIRST TURN (the continue prompt), in this order:
  1. the frozen restore budget R (growth past the pre-limit population is refused),
  2. the CPU brake at the pre-limit operating point, with a floor of one admission per 20 s,
  3. the per-target-account pacer (at most 3 submitted-not-ENGAGED per account),
  4. the library's memory terms via ``cc_capacity_probe`` (a PROBE: it charges nothing).

A relaunch with no prompt needs none of them. A LIMITED session whose first turn is refused is still
relaunched unprompted (RELAUNCHED-UNPROMPTED is a named wait that frees the source seat), so a refusal
here never blocks the relaunch: the CALLER decides, this module only answers.

The bounded gate: probe refusals never spend the library's own refusal budget, so the reconciler owns
the counter. After 3 consecutive probe refusals in a cohort the probe is overridden at most once per
30 s ("drip") and ``page_due`` is raised once for that cohort. Only the probe is overridden: R, the
brake (which has its own floor) and the pacer stay binding.

State is plain attributes and every external effect (the bash library, the environment) is injected.
"""

import hashlib
import os
import re
import shlex
import subprocess
from typing import Callable, Dict, List, Mapping, Optional, Sequence, Set, Tuple

# argv -> (rc, stdout). rc < 0 means the runner itself failed (spawn error, timeout).
Runner = Callable[[List[str]], Tuple[int, str]]

REPO_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)
LIB_REL = "scripts/lib/capacity-admit.sh"

CPU_FLOOR_RATIO = 2.5  # per core; §C6 gate 2
CPU_FLOOR_S = 20.0  # at least one admission per 20 s, whatever the load
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
    """Run argv with no stdin and a hard bound; a spawn failure or timeout is rc -1, never a raise."""
    try:
        cp = subprocess.run(
            argv, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30
        )
    except (OSError, subprocess.TimeoutExpired):
        return -1, ""
    return cp.returncode, cp.stdout


def jitter_s(sid: str) -> float:
    """Deterministic 0-60 s offset for in-place reset wakes (WAIT_RESET, HELD:team leads).

    A hash of the sid, so a restarted daemon picks the same offset and a cohort that resets at one
    instant spreads over a minute instead of hitting one account at once (§C6 gate 3)."""
    digest = hashlib.sha256(sid.encode("utf-8")).hexdigest()
    return float(int(digest[:8], 16) % (JITTER_MAX_S + 1))


class Admission:
    """One per ACTIVE period (§C6). ``enter_active`` freezes R and L_open; ``leave_active`` clears all."""

    def __init__(
        self,
        runner: Optional[Runner] = None,
        repo: Optional[str] = None,
        env: Optional[Mapping[str, str]] = None,
    ) -> None:
        self.runner: Runner = runner or default_runner
        self.repo = repo or REPO_ROOT
        e = env if env is not None else os.environ
        self.pacer_per_acct = _env_int(e, "LR_PACER_PER_ACCT", 3)
        self.restore_r: Optional[int] = None
        self.l_open: Optional[float] = None
        self.entered_at: Optional[float] = None
        self.last_admit_at: Optional[float] = None
        self.pacer: Dict[str, Dict[str, float]] = {}  # acct -> {sid: submitted_at}
        self.refusals: Dict[str, int] = {}  # cohort -> consecutive probe refusals
        self.last_drip_at: Dict[str, float] = {}
        self.paged: Set[str] = set()
        self.page_due = False

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
        self.pacer.clear()
        self.refusals.clear()
        self.last_drip_at.clear()
        self.paged.clear()
        self.page_due = False

    def restore_ok(self, active: int, unredeemed: int) -> bool:
        """``active + unredeemed + 1 <= R``: an admitted-but-unredeemed token is already on its way in."""
        return self.restore_r is not None and active + unredeemed + 1 <= self.restore_r

    # ── gate 2: the CPU brake ────────────────────────────────────────────────────────────────
    def cpu_ok(self, load1: float, ncpu: int, now: float) -> bool:
        """load1/ncpu <= max(2.5, L_open), or 20 s since the last admission (the anti-starvation floor;
        before any admission the reference is ACTIVE entry)."""
        limit = max(CPU_FLOOR_RATIO, self.l_open or 0.0)
        if load1 / max(ncpu, 1) <= limit:
            return True
        ref = self.last_admit_at if self.last_admit_at is not None else self.entered_at
        return ref is not None and now - ref >= CPU_FLOOR_S

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
        if not self.pacer_ok(acct, now, sid):
            return False, "pacer:%s" % acct
        self.pacer_take(sid, acct, now)
        return True, "admit"

    # ── gate 4: the library's memory terms ───────────────────────────────────────────────────
    def _lib(self) -> str:
        return shlex.quote(os.path.join(self.repo, LIB_REL))

    def probe(self, restore_r: int) -> Tuple[bool, str]:
        """rc 0 admit, rc 9 refuse ("memory"); anything else is not an admission ("probe-error")."""
        cmd = (
            "source %s; CC_ADMIT_RESTORE_R=%d cc_capacity_probe lr-reconciler first-turn"
            % (
                self._lib(),
                int(restore_r),
            )
        )
        rc, _ = self.runner(["bash", "-c", cmd])
        if rc == 0:
            return True, "admit"
        return False, "memory" if rc == 9 else "probe-error"

    def library_probe(self, restore_r: int) -> bool:
        return self.probe(restore_r)[0]

    def mint_token(self, sid: str) -> Optional[str]:
        """One-shot sid-bound admission token via ``cc_capacity_token_mint``; returns its path."""
        if not _SID_OK.match(sid):
            return None
        cmd = 'source %s; cc_capacity_token_mint "$1"' % self._lib()
        rc, out = self.runner(["bash", "-c", cmd, "lr-admit", sid])
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
    ) -> Tuple[bool, str]:
        """Apply R, the brake, the pacer, then the probe. The reason names the first gate that refused
        ("restore-r", "cpu", "pacer:<acct>", "memory", "probe-error", "drip"); "admit" or "admit:drip"
        otherwise. An admission takes a pacer slot and resets the cohort's refusal run.

        load5 is accepted for the caller's symmetry with ``enter_active``; the brake reads load1 only,
        because L_open already carries the lagging load5 term (§C6 gate 2)."""
        del load5
        if self.restore_r is None or not self.restore_ok(active, unredeemed):
            return False, "restore-r"
        if not self.cpu_ok(load1, ncpu, now):
            return False, "cpu"
        if not self.pacer_ok(acct, now, sid):
            return False, "pacer:%s" % acct
        ok, reason = self.probe(self.restore_r)
        if not ok:
            run = self.refusals.get(cohort, 0)
            if run < DRIP_AFTER:
                self.refusals[cohort] = run + 1
                return False, reason
            last = self.last_drip_at.get(cohort)
            if last is not None and now - last < DRIP_EVERY_S:
                return False, "drip"
            if cohort not in self.paged:
                self.paged.add(cohort)
                self.page_due = True
            self.last_drip_at[cohort] = now
            reason = "admit:drip"
        else:
            reason = "admit"
            self.refusals[cohort] = 0
        self.last_admit_at = now
        self.pacer_take(sid, acct, now)
        return True, reason


class BootSlots:
    """TUI boots in flight (relaunch typed -> painted), AIMD (§6): start 6, +2 after a wave where every
    boot painted within 15 s, halve on any boot over 45 s or INDETERMINATE, floor 2, cap LR_BOOT_MAX.
    Boots are the resource that failed at load 40+; actuator subprocesses are bounded separately."""

    START = 6
    FLOOR = 2
    FAST_S = 15.0
    SLOW_S = 45.0

    def __init__(self, env: Optional[Mapping[str, str]] = None) -> None:
        e = env if env is not None else os.environ
        self.cap = _env_int(e, "LR_BOOT_MAX", 12)
        self.workers_cap = _env_int(e, "LR_RECON_WORKERS", 16)
        self.limit = min(self.START, self.cap)
        self.held: Set[str] = set()

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
        self.held.add(sid)
        return True

    def release(self, sid: str) -> None:
        self.held.discard(sid)
