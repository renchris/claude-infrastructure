"""Actuators (§C8): spawn, adopt, reap, and the gate that decides whether one may run at all.

Every actuator is a setsid child whose argv carries ``--record-id <id> --intent <nonce>`` (an
``lr-recon-act`` bash wrapper puts them there even for tools that take no such flag), so a daemon
restart ADOPTS a live actuator by an argv scan instead of spawning a second one (§4.5). Write
order: the intent nonce is saved on the record BEFORE the spawn, the (pid, lstart) after it — a
crash in between leaves a nonce the argv scan resolves, never an unknown process.

The gate (``may_actuate``) is where the kill switches live, all on the safe side: no actuation
unless ``recon.on`` exists AND the mode is ``act``; PLAN-ONLY records never actuate; nothing
irreversible inside the 30 s wake guard; HEAL is disabled until the operator rules on
``LR_HEAL_CORE_BARE``; every actuation carries ``CC_RECYCLE_BGWORK_ANSWER=cancel`` (decision 2:
hold, never "Exit and stop tasks"). The sibling's core.bare heal (``LR_BARE_REPAIR``) is left as
landed — decision 5 is SETTLED "allow", so nothing here overrides it.
"""

from __future__ import annotations

import os
import subprocess
import time
import uuid
from typing import Any, Callable, Dict, List, Optional, Tuple

from lr_recon import census, store
from lr_recon import types as T

HERE = os.path.dirname(os.path.abspath(__file__))
LR_DIR = os.path.dirname(HERE)  # scripts/limit-recover
SCRIPTS = os.path.dirname(LR_DIR)  # scripts/
IRREVERSIBLE = ("A", "A-husk", "B", "R", "UNCONFIRM", "FOLD", "ABORT", "SPLIT", "HEAL")
BOOTING = ("A", "A-husk", "B", "R")  # hold a TUI boot slot (§6 B)
WRAPPER = 'shift 4; "$@"'  # $0 lr-recon-act $1..$4 = the four tokens
ACTLOG_MAX_AGE_S = 7 * 86400  # stated bound on recon/actlogs (§C12)

PopenFn = Callable[..., Any]
# pid → exit code of our own actuators, filled by reap_children and drained by settle.dead_actuators.
EXIT_CODES: Dict[int, int] = {}
# pid → the actuator's own Popen, held so it is never garbage-collected into subprocess._active:
# every later Popen runs subprocess._cleanup, which reaped those and stole the exit code before
# reap_children's waitpid saw it (W5 rig: 32 of 113 exits read "code unknown").
_CHILDREN: Dict[int, "subprocess.Popen[bytes]"] = {}


def _p(*parts: str) -> str:
    return os.path.join(*parts)


def actuator_env(
    rec: T.Record, paths: T.Paths, pane_sock: str, base: Optional[Dict[str, str]] = None
) -> Dict[str, str]:
    """The §C8 environment, identical for every actuator."""
    env = dict(os.environ if base is None else base)
    env.update(
        {
            "LR_RECORD_ID": rec.record_id,
            "LR_ATTEMPT": str(rec.attempt),
            "HF_RECYCLE_ATTEMPT": "%s:%d" % (rec.record_id, rec.attempt),
            # NOT under sessions/: load_all reads every sessions/*.json as a record and quarantines
            # anything else (the W5 rig quarantined one watcher file per move)
            "HF_WATCHER_RECORD": _p(paths.root, "work", rec.sid + ".watcher.json"),
            "CC_RECYCLE_BGWORK_ANSWER": "cancel",
            "LR_WAKE_GUARD_S": "30",
            "LR_INPLACE_AWAIT": "0",
            "LR_PLACED_BY": "reconciler",
            "LR_ASSIGN_ID": rec.assign_id or rec.record_id,
            # NO LR_PRESEED_DONE: it tells lr-handoff and lr-fire-resume to skip the target
            # account's folder-trust seed, and the batched per-target preseed it vouched for was
            # never built (W5b). Each move seeds its own target (idempotent, lock-guarded).
            "CLAUDE_CODE_DISABLE_AGENT_VIEW": "1",
            # the daemon's own trees, explicitly: the fence an actuator sources logs to and reads
            # owned/ under LR_RECON_ROOT, and a canary daemon's root is not the default one
            "LR_STATE_DIR": paths.lr_root,
            "LR_RECON_ROOT": paths.root,
        }
    )
    if rec.kind == "idle":
        # An idle move relaunches with NO prompt, so no assistant turn is owed. Its watcher must
        # prove the relaunch by a live `--resume <sid>` process (handoff-fire's no-prompt branch,
        # the team procedure); waiting for a turn declared a working in-place rescue dead after
        # 180 s and paged recycle-dead (W5b real canary 3). Canaries 1-2 passed only because
        # their resumed sessions happened to take a turn.
        env["HF_ENGAGE_BY_PROCESS"] = "1"
    if pane_sock:
        env["CC_TERM_KITTY_TO"] = pane_sock
    if rec.admit_token:
        env["LR_ADMIT_TOKEN_PATH"] = rec.admit_token
    if (
        rec.submit_token
    ):  # lr-handoff types THIS token, so row 5 can find this attempt's prompt
        env["LR_RECON_SUBMIT_TOKEN"] = rec.submit_token
    return env


# ── command builders, per the frozen W1/W2 contract (plan Phase 0) ──────────────────────────────


def _pane_id(rec: T.Record) -> str:
    return str(rec.pane[1]) if rec.pane else ""


def cmd_move(
    rec: T.Record, evidence_file: str = "", voluntary: bool = False
) -> List[str]:
    argv = [
        "/bin/bash",
        _p(LR_DIR, "lr-handoff.sh"),
        "--sid",
        rec.sid,
        "--config-dir",
        rec.source_cfg,
        "--cwd",
        rec.cwd,
        "--target",
        rec.target_acct,
        "--launch",
        "--in-place",
        "--source-pane",
        _pane_id(rec),
        "--record-id",
        rec.record_id,
        "--attempt",
        str(rec.attempt),
    ]
    if rec.kind == "idle":
        argv += ["--voluntary", "--account-evidence", evidence_file, "--no-prompt"]
    elif (
        voluntary
    ):  # a TARGET-AUTH hop: moved on the auth fact, and the prompt still goes
        argv += ["--voluntary", "--account-evidence", evidence_file]
    return argv


def cmd_husk(rec: T.Record) -> List[str]:
    if not rec.bundle:  # `--resume-launcher ""` can only fail: no argv, no spawn
        return []
    return [
        "/bin/bash",
        _p(SCRIPTS, "handoff-fire.sh"),
        "--recycle",
        "--transplanted-source",
        "--husk",
        "--resume-launcher",
        rec.bundle,
        "--resume-cfg",
        rec.target_cfg,
        "--source-pane",
        _pane_id(rec),
        "--source-session",
        rec.sid,
        "--record-id",
        rec.record_id,
    ]


def cmd_relaunch_at_shell(rec: T.Record, identity_file: str) -> List[str]:
    if not rec.bundle:
        return []
    return [
        "/bin/bash",
        _p(SCRIPTS, "handoff-fire.sh"),
        "--relaunch-at-shell",
        "--source-pane",
        _pane_id(rec),
        "--source-session",
        rec.sid,
        "--resume-launcher",
        rec.bundle,
        "--resume-cfg",
        rec.target_cfg,
        "--resume-cwd",
        rec.cwd,
        "--expect-identity",
        identity_file,
        "--record-id",
        rec.record_id,
    ]


def cmd_transplant(rec: T.Record, phase: str) -> List[str]:
    """UNCONFIRM / FOLD / ABORT through lr-transplant's new phases."""
    argv = [
        "/bin/bash",
        _p(LR_DIR, "lr-transplant.sh"),
        "--phase",
        phase,
        "--sid",
        rec.sid,
        "--from",
        rec.source_cfg,
        "--to",
        rec.target_cfg,
        "--record-id",
        rec.record_id,
    ]
    if phase == "unconfirm":
        argv += [
            "--source-pid",
            str(rec.source_pid),
            "--source-lstart",
            rec.source_lstart,
        ]
    return argv


def cmd_engage(rec: T.Record, payload_file: str) -> List[str]:
    """C / C-retry: the continue prompt through the pane's own socket (cc_tui_submit)."""
    script = 'source "%s"; cc_tui_submit "$1" "$2"' % _p(SCRIPTS, "lib", "cc-tui.sh")
    return ["/bin/bash", "-c", script, "lr-recon-engage", _pane_id(rec), payload_file]


# The in-place reset wake (D1.11, D4.9, resolution 2): a plain continue, never /limit-recover, which
# runs the skill and can choose a move. A held team lead is also told how its members resume.
WAKE_TEXT = "continue"
WAKE_TEXT_TEAM = (
    "continue — the usage limit has reset. Any teammate whose last turn hit the limit resumes "
    "when you message it."
)
# The wake's own exits beside cc_tui_submit's table: 6 = lr_focus_gate held it (nothing typed,
# retry), 8 = no lr_focus_gate to ask (nothing typed; every typing path must ask it, resolution 1).
WAKE_HELD_RC = 6
WAKE_NO_GATE_RC = 8


def cmd_wake(rec: T.Record, payload_file: str) -> List[str]:
    """Type one continue into the session's OWN pane: lr_focus_gate first (resolution 1: one focus
    rule for every typing path), then cc_tui_submit, which refuses an occupied composer (rc 3)."""
    script = (
        'source "%s" 2>/dev/null; '
        "if ! command -v lr_focus_gate >/dev/null 2>&1; then "
        'echo "lr-recon-wake: no lr_focus_gate; nothing typed" >&2; exit %d; fi; '
        'lr_focus_gate "$1"; g=$?; '
        'if [ "$g" != 0 ]; then echo "lr-recon-wake: verdict: ${LR_FOCUS_HOLD:-HELD:focused}"; '
        "exit %d; fi; "
        'source "%s"; cc_tui_submit "$1" "$2"'
        % (
            _p(LR_DIR, "lr-lib.sh"),
            WAKE_NO_GATE_RC,
            WAKE_HELD_RC,
            _p(SCRIPTS, "lib", "cc-tui.sh"),
        )
    )
    return ["/bin/bash", "-c", script, "lr-recon-wake", _pane_id(rec), payload_file]


def cmd_replace(rec: T.Record) -> List[str]:
    return [
        "/bin/bash",
        _p(SCRIPTS, "boot-resume-launch.sh"),
        rec.target_acct or rec.source_acct,
        rec.cwd,
        rec.sid,
    ]


def cmd_split(rec: T.Record, job_id: str) -> List[str]:
    return [
        "/usr/bin/env",
        "CLAUDE_CONFIG_DIR=" + rec.source_cfg,
        "claude",
        "stop",
        job_id,
    ]


def continue_prompt(rec: T.Record, window: str, resets: str) -> str:
    """§C8 resume prompt (rc 0 form). A fresh token per attempt and per C-retry (§7.3)."""
    return (
        "[limit-recover] Moved from %s to %s after a %s usage limit (resets %s); same "
        "session, full transcript. Continue the task you were on. (submit %s)"
        % (
            rec.source_acct,
            rec.target_acct,
            window or "usage",
            resets or "later",
            rec.submit_token,
        )
    )


def new_token() -> str:
    return "lrr-" + uuid.uuid4().hex[:12]


# ── spawn / adopt / reap ────────────────────────────────────────────────────────────────────────


def wrap(rec: T.Record, nonce: str, argv: List[str]) -> List[str]:
    return [
        "/bin/bash",
        "-c",
        WRAPPER,
        "lr-recon-act",
        "--record-id",
        rec.record_id,
        "--intent",
        nonce,
    ] + argv


def _actlog(paths: T.Paths, rec: T.Record, actuator: str) -> str:
    d = paths.p("actlogs")
    os.makedirs(d, exist_ok=True)
    return _p(d, "%s.%d.%s.log" % (rec.sid[:8], rec.attempt, actuator))


def spawn(
    paths: T.Paths,
    rec: T.Record,
    actuator: str,
    argv: List[str],
    env: Dict[str, str],
    now: float,
    popen: PopenFn = subprocess.Popen,
    lstart_of: Callable[[int], str] = store.proc_lstart,
) -> int:
    """§4.5 write order: intent nonce saved → spawn → (pid, lstart) into record and fence."""
    nonce = uuid.uuid4().hex[:12]
    rec.intent = T.Intent(nonce=nonce, at=now, actuator=actuator)
    store.save_record(paths, rec, now)
    with open(_actlog(paths, rec, actuator), "ab", 0) as log:
        proc = popen(
            wrap(rec, nonce, argv),
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    pid = int(proc.pid)
    if hasattr(proc, "poll"):  # tests inject fakes with only .pid
        _CHILDREN[pid] = proc
    rec.procs.append(
        T.ProcRole(role="actuator", pid=pid, lstart=lstart_of(pid), argv_hash=actuator)
    )
    store.save_record(paths, rec, now)
    fence = store.read_fence(paths, rec.sid)
    if fence is not None and fence.record_id == rec.record_id:
        fence.procs = list(rec.procs)
        store.update_fence(paths, rec.sid, fence)
    store.append_event(
        paths,
        T.Event(
            t=now,
            ev="spawn",
            sid=rec.sid,
            record_id=rec.record_id,
            detail="%s pid=%d nonce=%s" % (actuator, pid, nonce),
        ),
    )
    return pid


def live_procs(rec: T.Record, snap: T.Snapshot) -> List[T.ProcRole]:
    """Recorded processes still alive by exact (pid, lstart); a zombie is dead (§C3.1)."""
    return [p for p in rec.procs if snap.alive(p.pid, p.lstart)]


def adopt(rec: T.Record, snap: T.Snapshot) -> List[T.ProcRole]:
    """Find live actuators for this record by their argv token and record them (§C2 step 4)."""
    tok = "--record-id %s" % rec.record_id
    known = {(p.pid, p.lstart) for p in rec.procs}
    found = []
    for row in snap.procs.values():
        if row.zombie or tok not in row.args or (row.pid, row.lstart) in known:
            continue
        role = "watcher" if "__recycle" in row.args else "actuator"
        pr = T.ProcRole(role=role, pid=row.pid, lstart=row.lstart, argv_hash="adopted")
        rec.procs.append(pr)
        found.append(pr)
    return found


def settle_intent(rec: T.Record, snap: T.Snapshot) -> str:
    """After a restart: a nonce with a live argv match is adopted; one without is cleared so the
    next idempotent action can run. Returns "adopted" | "cleared" | "none"."""
    if rec.intent is None:
        return "none"
    if adopt(rec, snap) or live_procs(rec, snap):
        return "adopted"
    rec.intent = None
    return "cleared"


def prune_dead(rec: T.Record, snap: T.Snapshot) -> List[T.ProcRole]:
    dead = [p for p in rec.procs if not snap.alive(p.pid, p.lstart)]
    rec.procs = [p for p in rec.procs if snap.alive(p.pid, p.lstart)]
    if not rec.procs:
        rec.intent = None
    return dead


def reap_children() -> int:
    """waitpid(WNOHANG) on every pass so our own exited actuators never linger as zombies."""
    n = 0
    # our own actuators first: poll() owns their waitpid and keeps returncode on the object, so
    # no other reaper can race it (negative = signal, as below)
    for pid, proc in list(_CHILDREN.items()):
        rc = proc.poll()
        if rc is not None:
            EXIT_CODES[pid] = rc
            del _CHILDREN[pid]
            n += 1
    while True:
        try:
            pid, _status = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return n
        if pid == 0:
            return n
        EXIT_CODES[pid] = (
            os.WEXITSTATUS(_status) if os.WIFEXITED(_status) else -os.WTERMSIG(_status)
        )
        n += 1


def reap_actlogs(paths: T.Paths, now: float) -> int:
    d, n = paths.p("actlogs"), 0
    try:
        names = os.listdir(d)
    except OSError:
        return 0
    for name in names:
        f = _p(d, name)
        try:
            if now - os.stat(f).st_mtime > ACTLOG_MAX_AGE_S:
                os.unlink(f)
                n += 1
        except OSError:
            continue
    return n


# ── the gate ────────────────────────────────────────────────────────────────────────────────────


def may_actuate(
    paths: T.Paths,
    mode: str,
    rec: T.Record,
    actuator: str,
    snap: T.Snapshot,
    now: float,
    wake_ok: bool,
    running: int,
    workers: int,
    env: Optional[Dict[str, str]] = None,
) -> Tuple[bool, str]:
    """Every kill switch, on the safe side, in one place (plan Phase 0 § Kill switches)."""
    env = dict(os.environ) if env is None else env
    if not os.path.exists(paths.recon_on):
        return False, "recon-off"
    if mode != "act":
        return False, "mode-%s" % mode
    if rec.plan_only:
        return False, "plan-only"
    if not rec.open:
        return False, "terminal"
    if rec.substate == "PARKED-REBOOT":
        return False, "parked-reboot"  # boot-resume owns a pre-boot plan's relaunch
    if actuator == "HEAL" and env.get("LR_HEAL_CORE_BARE", "off") != "on":
        return False, "heal-disabled"
    if live_procs(rec, snap):
        return False, "process-live"
    if actuator == "A" and census.live_members(rec.sid, snap) > 0:
        return False, "team-live"  # D4.4: never move a lead out from under its members
    if rec.next_eligible_at and now < rec.next_eligible_at:
        return False, "backoff"
    if rec.escalated:
        return False, "escalated"
    if actuator in IRREVERSIBLE and not wake_ok:
        return False, "wake-guard"
    if running >= workers:
        return False, "workers-cap"
    return True, "ok"


def workers_cap() -> int:
    try:
        return max(1, int(os.environ.get("LR_RECON_WORKERS", "16")))
    except ValueError:
        return 16


def choose(res: T.PhaseResult, rec: T.Record) -> Optional[str]:
    """PhaseResult.action → the actuator to run, or None for wait/sentinel/page/plan-only."""
    a = res.action
    if res.phase == "PRE-MOVE":
        if a == "wake" and rec.substate in ("WAIT_RESET", "HELD:team"):
            return "C"  # the in-place reset wake (D1.11, D4.9)
        return "A" if rec.substate == "PLANNED" and rec.target_acct else None
    if a in ("A", "A-husk", "B", "R", "UNCONFIRM", "SPLIT", "C-retry"):
        return a
    if a == "C" and res.substate in ("UNPROMPTED", "DRAFTED"):
        return "C"
    return None


def running_count(records: Dict[str, T.Record], snap: T.Snapshot) -> int:
    return sum(1 for r in records.values() if live_procs(r, snap))


def sleep_briefly(s: float = 0.05) -> None:
    time.sleep(s)
