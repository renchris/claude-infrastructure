"""lr_recon shared types: the ONE interface every module builds against (FLEET_V2 W3, frozen).

Everything the reconciler passes between modules or stores on disk is a dataclass declared here.
Modules own behaviour; this file owns shape. A field is added here first, in its own commit, and
never renamed in place: records written by an older daemon must still load (``from_dict`` ignores
unknown keys and defaults missing ones).

Python 3.9 compatible on purpose (``/usr/bin/python3`` is 3.9.6 and launchd may resolve it), so
annotations use ``typing.Optional/List/Dict``, never ``X | Y``, and never ``match``.

Architecture references are to docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md.
"""

from __future__ import annotations

import dataclasses
import os
import typing
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

SCHEMA_VERSION = 1

# ── enumerations (plain string constants: they round-trip through JSON unchanged) ───────────────

MODES = (
    "observe",
    "plan",
    "act",
)  # recon/mode; absent or unreadable ⇒ "observe" (safe side)

KINDS = ("limited", "idle")
ORIGINS = ("hook", "census", "fanout", "cc-lr")  # ascending rank; cc-lr is sticky (C2)
SURFACES = ("kitty", "iterm")
ROOT_SHAPES = ("shell", "launcher", "headless", "unknown")
PANE_STATES = ("claude", "shell", "gone", "unknown")  # fixture `pane_state`
SCOPES_ACCOUNT_WIDE = ("5h", "7d", "auth")  # plus "model:<name>" and "fable" (C4)

# §4.2 phases, in table order. PRE-MOVE carries a substate from PRE_MOVE_SUBSTATES.
PHASES = (
    "SPLIT-BRAIN",
    "TARGET-LIMITED",
    "TARGET-AUTH",
    "TARGET-TRANSIENT",
    "ENGAGED",
    "MOVED",
    "RELAUNCHED",
    "EXITING",
    "HUSK-RETIRED",
    "EXITED",
    "PANE-GONE",
    "TRANSPLANTED",
    "PRE-MOVE",
)
RELAUNCH_SUBSTATES = ("UNPROMPTED", "DRAFTED", "SUBMITTED")
PRE_MOVE_SUBSTATES = (
    "DETECTED",
    "PLANNED",
    "WAIT_SLOT",
    "WAIT_RESET",
    "WAIT_DATA",
    "WAIT_CAPACITY",
    "HOLD-DRAFT",
    "HOLD-BGWORK",
    "HOLD-SUBAGENTS",
    "HOLD-MENU",
    "HOLD:iterm",
    "HOLD:repo-bare",
    "HELD:team",
    "PARKED-REBOOT",
    "BACKOFF",
    # Operator decision 7 is unruled: a focused limited pane is HELD until LR_MOVE_FOCUSED=on.
    "HOLD-FOCUS",
)
# Terminal outcomes (§4.2 Outcomes). ESCALATED is NOT terminal.
OUTCOMES = ("CLOSED", "NOT_NEEDED", "REPLACED", "REPLACED-NEW-WINDOW", "IMPOSSIBLE")

ERROR_CLASSES = ("TRANSIENT", "WAIT", "HOLD", "DETERMINISTIC", "IMPOSSIBLE")  # §7.2

PROC_ROLES = (
    "actuator",
    "watcher",
    "launcher",
    "fire_resume",
    "claude",
)  # §4.1 procs[]
ACTUATORS = (
    "A",
    "A-husk",
    "B",
    "C",
    "C-retry",
    "UNCONFIRM",
    "FOLD",
    "ABORT",
    "R",
    "SPLIT",
    "HEAL",
)

TARGET_LAST = (
    "ok",
    "limit",
    "authentication_failed",
    "server_529",
    "server_error",
    "network",
    "notification",
    "none",
)
READINESS = ("READY", "READY-QUIET", "composer-empty-x2", "parked-menu", "none")

# Maximum ages, seconds (C11). None ⇒ "at once" (page on entry). WAIT_SLOT's is relative to its
# earliest wake and HELD:team's to the reset: plan/report resolve those two against the record.
MAX_AGE_S: Dict[str, Optional[int]] = {
    "WAIT_DATA": 120,
    "WAIT_SLOT": 600,  # + earliest wake
    "WAIT_CAPACITY": 900,
    "HOLD-DRAFT": 900,
    "HOLD-FOCUS": 900,
    "HOLD-BGWORK": 1200,  # decision 2: 3600 when the job is a ship-land (Wait.detail)
    "HOLD-SUBAGENTS": 1800,
    "HOLD-MENU": None,
    "HOLD:repo-bare": None,
    "HOLD:iterm": None,
    "HELD:team": 600,  # not ENGAGED 10 min after reset
}
HOLD_BGWORK_SHIPLAND_MAX_AGE_S = (
    3600  # decision 2 (SETTLED): page at 60 min for a ship-land job
)

# §4.3 phase deadlines with no live recorded process, seconds.
PHASE_DEADLINE_S: Dict[str, int] = {
    "PLANNED": 45,  # → TRANSPLANTED
    "TRANSPLANTED": 60,  # → EXITED
    "EXITED": 60,  # → RELAUNCHED
    "RELAUNCHED-DRAFTED": 60,  # → SUBMITTED
    "RELAUNCHED-SUBMITTED": 180,  # → ENGAGED
}


# ── generic (de)serialisation ────────────────────────────────────────────────────────────────────


def _hints(cls: type) -> Dict[str, Any]:
    cache = _HINT_CACHE.get(cls)
    if cache is None:
        cache = typing.get_type_hints(cls)
        _HINT_CACHE[cls] = cache
    return cache


_HINT_CACHE: Dict[type, Dict[str, Any]] = {}


def _coerce(tp: Any, value: Any) -> Any:
    if value is None:
        return None
    origin = typing.get_origin(tp)
    args = typing.get_args(tp)
    if origin is typing.Union:  # Optional[X]
        inner = [a for a in args if a is not type(None)]
        return _coerce(inner[0], value) if len(inner) == 1 else value
    if origin in (list, List):
        return [_coerce(args[0], v) for v in value] if args else list(value)
    if origin in (dict, Dict):
        return (
            {k: _coerce(args[1], v) for k, v in value.items()} if args else dict(value)
        )
    if origin in (tuple, Tuple):
        return tuple(value)
    if dataclasses.is_dataclass(tp) and isinstance(value, dict):
        return from_dict(tp, value)
    return value


def from_dict(cls: type, data: Dict[str, Any]) -> Any:
    """Build ``cls`` from a JSON dict. Unknown keys are ignored; missing keys take their default."""
    hints = _hints(cls)
    kwargs = {}
    for f in dataclasses.fields(cls):
        if f.name in data:
            kwargs[f.name] = _coerce(hints[f.name], data[f.name])
    return cls(**kwargs)


def to_dict(obj: Any) -> Dict[str, Any]:
    return dataclasses.asdict(obj)


# ── paths (C7, §11). Every state dir the daemon writes is under LR_RECON_ROOT ───────────────────


@dataclass(frozen=True)
class Paths:
    """Resolved state tree. ``lr_root`` is the shared limit-recover tree (requests, runs, locks);
    ``root`` is the reconciler's own tree and the ONLY place it creates directories."""

    lr_root: str
    root: str

    @classmethod
    def from_env(
        cls, root: Optional[str] = None, env: Optional[Dict[str, str]] = None
    ) -> "Paths":
        env = os.environ if env is None else env
        home = env.get("HOME", os.path.expanduser("~"))
        lr_root = env.get("LR_STATE_DIR") or os.path.join(
            home, ".reso", "limit-recover"
        )
        rroot = root or env.get("LR_RECON_ROOT") or os.path.join(lr_root, "recon")
        return cls(lr_root=lr_root, root=rroot)

    def p(self, *parts: str) -> str:
        return os.path.join(self.root, *parts)

    # reconciler-owned (under root)
    @property
    def sessions(self) -> str:
        return self.p("sessions")

    @property
    def owned(self) -> str:
        return self.p("owned")

    @property
    def facts(self) -> str:
        return self.p("facts")

    @property
    def cohorts(self) -> str:
        return self.p("cohorts")

    @property
    def plans(self) -> str:
        return self.p("plans")

    @property
    def shadow(self) -> str:
        return self.p("shadow")

    @property
    def quarantine(self) -> str:
        return self.p("quarantine")

    @property
    def ctl(self) -> str:
        return self.p("ctl")

    @property
    def events(self) -> str:
        return self.p("events.jsonl")

    @property
    def launch_log(self) -> str:
        return self.p("launch.log")

    @property
    def heartbeat(self) -> str:
        return self.p("heartbeat")

    @property
    def restarts(self) -> str:
        return self.p("restarts.jsonl")

    @property
    def lock(self) -> str:
        return self.p("reconciler.lock")

    @property
    def mode_file(self) -> str:
        return self.p("mode")

    # shared (under lr_root) — read, and written only through the C7 lock pattern
    @property
    def recon_on(self) -> str:
        return os.path.join(self.lr_root, "recon.on")

    @property
    def autorecover_on(self) -> str:
        return os.path.join(self.lr_root, "autorecover.on")

    @property
    def requests(self) -> str:
        return os.path.join(self.lr_root, "requests")

    @property
    def claimed(self) -> str:
        # The landed poller's CLAIMED="$STATE/claimed" (lr-reset-poller.sh:167): one drained-request
        # store for both consumers, never a second one beside it.
        return os.path.join(self.lr_root, "claimed")

    @property
    def runs_by_sid(self) -> str:
        return os.path.join(self.lr_root, "runs", "by-sid")

    @property
    def locks(self) -> str:
        return os.path.join(self.lr_root, "locks")

    def reconciler_dirs(self) -> List[str]:
        return [
            self.sessions,
            self.owned,
            self.facts,
            self.cohorts,
            self.plans,
            self.shadow,
            self.quarantine,
            self.ctl,
        ]


# ── process identity (§10 #12: liveness is exact) ────────────────────────────────────────────────


@dataclass(frozen=True)
class ProcId:
    """A process by (pid, lstart). ``lstart`` is ps's LSTART rendered under TZ=UTC LC_ALL=C."""

    pid: int
    lstart: str


@dataclass
class ProcRow:
    """One row of the single ``ps -axo pid,ppid,lstat,lstart,args`` read (C3.1)."""

    pid: int
    ppid: int
    stat: str
    lstart: str
    args: str

    @property
    def zombie(self) -> bool:
        return self.stat.startswith("Z")

    @property
    def ident(self) -> ProcId:
        return ProcId(self.pid, self.lstart)


@dataclass
class ProcRole:
    """A process the reconciler started or adopted, as recorded in ``owned/`` and the record."""

    role: str  # PROC_ROLES
    pid: int
    lstart: str
    argv_hash: str = ""


# ── locks, claims, fence (C7, C10) ───────────────────────────────────────────────────────────────


@dataclass
class LockHolder:
    """``holder`` file of every mkdir lock (C7 lock pattern)."""

    record_id: str
    attempt: int
    role: str
    pid: int
    lstart: str
    at: float


@dataclass
class RunClaimHolder:
    """``runs/by-sid/<sid>.active/holder``. A legacy holder has only ``pid`` (owner="")."""

    pid: int
    lstart: str = ""
    owner: str = ""
    record_id: str = ""


@dataclass
class FenceFile:
    """``recon/owned/<sid>`` — the only file other tools read (C7/C10)."""

    record_id: str
    attempt: int
    procs: List[ProcRole] = field(default_factory=list)


@dataclass
class Heartbeat:
    """``recon/heartbeat`` (C2). ``progress`` advances only from the main loop.

    ``progress_wall`` is the wall time of the last ``progress`` change, so ONE read answers the
    fence's "advanced within 180 s" (C10). Sleep adjustment for readers: the age of an advance is
    ``now - max(progress_wall, kern.waketime)`` — a wake restarts the clock, which errs to DEFER."""

    pid: int
    lstart: str
    progress: int
    wall: float
    uptime_raw: float
    progress_wall: float = 0.0


# ── account facts (C4) ───────────────────────────────────────────────────────────────────────────


@dataclass
class Fact:
    """``recon/facts/<acct>.<scope>.json``. File name uses the scope with ':' kept verbatim."""

    acct: str
    scope: str  # "5h" | "7d" | "auth" | "fable" | "model:<name>"
    status: str = "rejected"
    window: str = ""  # "five_hour" | "seven_day" | "" (model/fable/auth)
    resets_at: Optional[float] = None  # epoch seconds
    first_sid: str = ""
    observed_at: float = 0.0
    src: str = ""  # "hook" | "census" | "wire"
    contradicted: bool = False
    untested: bool = False  # fable scope: no instance seen (C1)

    @property
    def key(self) -> str:
        return "%s.%s" % (self.acct, self.scope)

    @property
    def account_wide(self) -> bool:
        return self.scope in SCOPES_ACCOUNT_WIDE


# ── observation (C3). Built once per pass by observe.py; pure data after that ───────────────────


@dataclass
class PaneObs:
    kitty_pid: int
    window_id: int
    sock: str  # "unix:/tmp/kitty-<pid>" — the instance socket for CC_TERM_KITTY_TO
    surface: str = "kitty"
    kitty_lstart: str = ""
    tty: str = ""
    root_pid: int = 0
    root_lstart: str = ""
    is_focused: bool = False
    title: str = ""
    cwd: str = ""
    root_shape: str = "unknown"  # ROOT_SHAPES
    state: str = "unknown"  # PANE_STATES

    @property
    def key(self) -> Tuple[int, int]:
        return (self.kitty_pid, self.window_id)


@dataclass
class Identity:
    """The identity tuple recorded at precheck (C3.10)."""

    kitty_pid: int = 0
    kitty_lstart: str = ""
    window_id: int = 0
    tty: str = ""
    root_pid: int = 0
    root_lstart: str = ""


@dataclass
class HolderObs:
    """One member of H(sid) (C3.5)."""

    pid: int
    lstart: str
    cfg: str  # config dir path the holder runs under
    src: str  # "registry" | "resume-argv" | "session-row"
    kind: str = ""  # session-row kind ("", "bg", …)
    bg: bool = False
    pane: Optional[Tuple[int, int]] = (
        None  # (kitty_pid, window_id) when pane-bound by ppid walk
    )


@dataclass
class BgWork:
    """One background-work item for a session (C3.7)."""

    kind: str  # "bg-row" | "shell"
    pid: int
    lstart: str = ""
    argv: str = ""
    watcher_only: bool = False  # shell whose only child is cc-await-ping (W0 §3)
    ship_land: bool = False  # decision 2: 60-min page


@dataclass
class TranscriptObs:
    path: str = ""
    size: int = 0
    mtime: float = 0.0
    last: Dict[str, Any] = field(
        default_factory=dict
    )  # lr_predicate.classify_tail verdict
    last_assistant_ok_at: Optional[float] = None  # ts of last non-error assistant turn
    at_rest: bool = False
    teammate: bool = False  # lr_predicate.is_teammate_head
    live_subagents: int = 0  # includes workflow slots


@dataclass
class SessionObs:
    sid: str
    cfg: str = ""  # config dir of the live claude (or where the transcript lives)
    acct: str = ""  # folded account name (".claude" and ".claude-next" are one)
    model: str = ""
    pid: int = 0
    lstart: str = ""
    cwd: str = ""
    pane: Optional[Tuple[int, int]] = None
    holders: List[HolderObs] = field(default_factory=list)
    bg_work: List[BgWork] = field(default_factory=list)
    transcript: TranscriptObs = field(default_factory=TranscriptObs)
    registry_name: str = ""
    live_members: int = 0  # lead with live pane teammates ⇒ HELD:team
    composer: str = ""  # "empty" | "draft" | "unknown" | "" (not read)


@dataclass
class Snapshot:
    """One census. ``degraded`` names instruments that failed; nothing is planned for those parts."""

    wall: float
    uptime_raw: float
    procs: Dict[int, ProcRow] = field(default_factory=dict)
    panes: Dict[str, PaneObs] = field(
        default_factory=dict
    )  # key "<kitty_pid>:<window_id>"
    sessions: Dict[str, SessionObs] = field(default_factory=dict)
    sockets: List[str] = field(default_factory=list)
    degraded: List[str] = field(
        default_factory=list
    )  # e.g. "kitty:<sock>", "ps", "registry"
    rig_refused: List[str] = field(
        default_factory=list
    )  # rig mode only: sids dropped because no registry row carries rig:true
    ttys: List[str] = field(
        default_factory=list
    )  # controlling ttys held by any live process ("ttys022"), from the same ps read

    def alive(self, pid: int, lstart: str) -> bool:
        row = self.procs.get(pid)
        return bool(row) and row.lstart == lstart and not row.zombie


# ── phase derivation (§4.2) ──────────────────────────────────────────────────────────────────────


@dataclass
class EvHolder:
    cfg: str  # "source" | "target" | "other"
    pane_bound: bool = False
    bg: bool = False
    role: str = "claude"  # "claude" | "bg-row"


@dataclass
class Evidence:
    """``derive_phase`` input. Field for field the fixture ``evidence`` schema
    (tests/fixtures/lr-recon/README.md); every field is optional (absent = unknown/false)."""

    kind: str = "limited"
    attempt: int = 1
    holders: List[EvHolder] = field(default_factory=list)
    source_alive: bool = False
    source_at_composer: bool = False
    handed_off: bool = False
    stub_present: bool = False
    live_watcher: bool = False
    live_launcher: bool = False
    pane_state: str = "unknown"
    pane_absent_observations: int = 0
    tty_present: bool = False
    identity_match: bool = False
    exit_typed_by_me: bool = False
    resume_debt_open: bool = False
    lock_names_target: bool = False
    source_retired: bool = False
    submitted: bool = False
    target_last_assistant: str = "none"
    token_record_offset: Optional[int] = None
    token_is_this_attempt: bool = False
    confirm_len: Optional[int] = None
    nonerror_assistant_after_token: bool = False
    holder_stable_two_samples: bool = False
    readiness: str = "none"
    relaunch_substate: Optional[str] = None
    last_error_class: str = ""  # record.last_error.cls, for row 9's HOLD/TOCTOU branch
    pre_move: str = ""  # the record's cached PRE-MOVE substate, returned for row 13


@dataclass
class PhaseResult:
    phase: str  # PHASES
    substate: Optional[str] = None
    action: str = ""  # ACTUATORS member, "wait", "none", "page", "sentinel"
    reason: str = ""  # which table row / branch fired, for the event log


# ── the durable record (§4.1) ────────────────────────────────────────────────────────────────────


@dataclass
class Intent:
    nonce: str
    at: float
    actuator: str = ""


@dataclass
class Timeline:
    detected: Optional[float] = None
    planned: Optional[float] = None
    confirmed: Optional[float] = None
    exit_typed_by_me: Optional[float] = None
    exited: Optional[float] = None
    relaunched: Optional[float] = None
    submitted: Optional[float] = None
    engaged: Optional[float] = None


@dataclass
class LastError:
    cls: str  # ERROR_CLASSES
    fingerprint: str = ""
    detail: str = ""
    at: float = 0.0


@dataclass
class Wait:
    reason: str  # a PRE_MOVE_SUBSTATES member (WAIT_*/HOLD*/HELD:team)
    since: float = 0.0
    wakes: List[str] = field(default_factory=list)  # named wake conditions
    max_age_s: Optional[int] = None
    eta: Optional[float] = None
    detail: str = ""


@dataclass
class Terminal:
    outcome: str  # OUTCOMES
    proof: str = ""
    at: float = 0.0


@dataclass
class Record:
    """``recon/sessions/<sid>.json`` (§4.1). One file per sid, one writer (the daemon)."""

    sid: str
    record_id: str
    schema: int = SCHEMA_VERSION
    # identity
    kind: str = "limited"
    lane: str = "general"  # "general" | "fable"
    scope: str = ""
    surface: str = "kitty"
    pane: Optional[Tuple[int, int]] = None
    source_acct: str = ""
    source_cfg: str = ""
    source_pid: int = 0
    source_lstart: str = ""
    root_shape: str = "unknown"
    identity: Identity = field(default_factory=Identity)
    cwd: str = ""
    # plan
    cohort_id: str = ""
    origin: str = "hook"
    target_acct: str = ""
    target_cfg: str = ""
    weight: int = 1
    assign_id: str = ""
    admit_token: str = ""
    submit_token: str = ""  # this attempt's; a fresh one per attempt and per C-retry
    bundle: str = ""
    confirm_len: Optional[int] = None
    plan_only: bool = False  # daemon-origin without autorecover.on (C2 actuation gate)
    # execution
    phase: str = "PRE-MOVE"
    substate: Optional[str] = "DETECTED"
    intent: Optional[Intent] = None
    procs: List[ProcRole] = field(default_factory=list)
    timeline: Timeline = field(default_factory=Timeline)
    attempt: int = 1
    attempts_by_class: Dict[str, int] = field(default_factory=dict)
    last_error: Optional[LastError] = None
    next_eligible_at: Optional[float] = None
    wait: Optional[Wait] = None
    repo_state: Dict[str, Any] = field(default_factory=dict)
    escalated: bool = False
    # cross-pass evidence history (evidence.py): PANE-GONE needs two consecutive absent scans,
    # MOVED needs the same target holder on two samples ≥15 s apart ({pid, lstart, at})
    pane_absent_obs: int = 0
    target_sample: Optional[Dict[str, Any]] = None
    # close evidence for the cohort DoD line (report.dod_line): {via, at, pane, same_window,
    # same_uuid, seen: [every phase/substate this record passed through]}
    close: Dict[str, Any] = field(default_factory=dict)
    # terminal
    goal_snapshot: str = ""
    terminal: Optional[Terminal] = None
    sentinel_until: Optional[float] = None
    updated_at: float = 0.0

    @property
    def open(self) -> bool:
        return self.terminal is None


def make_record_id(cohort_id: str, sid: str, attempt: int) -> str:
    """Also the phantom assignment id (§3 step 6): ``recon:<cid>:<sid8>:<attempt>``."""
    return "recon:%s:%s:%d" % (cohort_id, sid[:8], attempt)


# ── plan / placement (C5, §5) ────────────────────────────────────────────────────────────────────

BUCKETS = (
    "LIMITED",
    "IDLE-ELIGIBLE",
    "WORKING",
    "HOLD-DRAFT",
    "HOLD-BGWORK",
    "HOLD-SUBAGENTS",
    "HOLD-FOCUS",
    "HOLD:iterm",
    "HOLD:repo-bare",
    "TEAMMATE",
    "HELD:team",
    "LAUNCHER-ROOTED",
    "IMPOSSIBLE",
    "SPLIT-BRAIN",
    "STAY",
)  # §3 step 5: every live session in an affected scope lands in exactly one


@dataclass
class Bucket:
    """One census verdict (§3 step 5), handed from the census to placement and the records."""

    sid: str
    name: str  # BUCKETS
    reason: str = ""
    kind: str = "limited"  # "limited" | "idle" (for movers)
    acct: str = ""
    scope: str = ""
    resets_at: Optional[float] = None
    detail: str = ""  # e.g. "ship-land" for HOLD-BGWORK (decision 2 page age)


@dataclass
class Mover:
    """One ``--movers`` JSONL row (W1 contract)."""

    sid: str
    src: str
    kind: str = "limited"
    w: int = 1
    model: Optional[str] = None
    burn_ph: Optional[float] = None
    death_ts: Optional[float] = None


@dataclass
class Placement:
    """One entry of ``claude-accounts --place --json``: ``{sid: {acct|null, reason, eta_s, weight}}``."""

    acct: Optional[str] = None
    reason: str = ""
    eta_s: Optional[float] = None
    weight: int = 1


@dataclass
class Cohort:
    """``recon/cohorts/<cid>.json`` (C11). Key is (account, scope, resets_at)."""

    cid: str
    acct: str
    scope: str
    resets_at: Optional[float] = None
    opened_at: float = 0.0
    members: List[str] = field(default_factory=list)
    open_paged: bool = False
    last_delta_at: Optional[float] = None
    closed_at: Optional[float] = None
    # frozen at ACTIVE entry (C6)
    restore_r: Optional[int] = None
    l_open: Optional[float] = None


@dataclass
class Request:
    """``requests/<sid>.json`` (hook) or ``requests/<sid>.cc-lr.json`` (cc-lr, lr-fleet --enqueue)."""

    sid: str
    origin: str  # "hook" | "cc-lr"
    path: str = ""
    at: float = 0.0
    raw: Dict[str, Any] = field(default_factory=dict)


@dataclass
class Event:
    """One ``recon/events.jsonl`` line (≤1 KB, C7)."""

    t: float
    ev: str
    sid: str = ""
    record_id: str = ""
    detail: str = ""
