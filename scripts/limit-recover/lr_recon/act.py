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

Restart safety (A6, docs/research/lr-sustained-load-2026-10-20/impl/A6-restart-safety.md §2.2):
1. Identity. An actuator is (pid, lstart) for liveness, read from the pass's one ps census, and its
   spawn nonce for its verdict.
2. Inherited. A ProcRole loaded from the record file is tracked without a respawn; when it dies its
   verdict comes from its exit file ``recon/exits/<nonce>.rc``, which the wrapper writes.
3. Found by argv scan. A ``/bin/bash -c … lr-recon-act --record-id <rid> --intent <nonce>`` row is
   the WRAPPER: adopted under ``rec.intent.actuator`` when the nonce is the intent's, else as
   "adopted" (liveness only). A row whose nonce a recorded proc already carries REPAIRS that proc's
   (pid, lstart) instead of appending a second entry (one spawn is one exit). Every other
   ``--record-id`` match is a descendant: "adopted", no nonce.
4. Only the wrapper's exit is a verdict. A descendant never carries a code, and an in-memory code is
   accepted only for a pid this process spawned under the same nonce (a reused pid never speaks).
5. Claim. The run claim names the daemon, or a live named actuator an EARLIER daemon started: only
   that one is an ancestor of the handoff-fire that checks it (claim_holder_for).
6. Unknown is not a verdict: no code from any source is settle_exit's existing None path.
7. Replay. A settle's effects and the pruning of its proc land in one atomic record write, so a
   killed pass replays the exit from its file exactly once. Events may show it twice.
"""

from __future__ import annotations

import os
import re
import subprocess
import time
import uuid
from typing import Any, Callable, Dict, List, Optional, Tuple

from lr_recon import census, clock, store
from lr_recon import types as T
from lr_recon.clock import run_bounded

HERE = os.path.dirname(os.path.abspath(__file__))
LR_DIR = os.path.dirname(HERE)  # scripts/limit-recover
SCRIPTS = os.path.dirname(LR_DIR)  # scripts/
IRREVERSIBLE = ("A", "A-husk", "B", "R", "UNCONFIRM", "FOLD", "ABORT", "SPLIT", "HEAL")
BOOTING = ("A", "A-husk", "B", "R")  # hold a TUI boot slot (§6 B)
# $0 lr-recon-act $1..$4 = the four tokens. The actuator runs as the wrapper's CHILD (bash 3.2 does
# not exec a command that is followed by more of the list); its code goes to
# $LR_RECON_ROOT/exits/<nonce>.rc, which the NEXT daemon reads: a restart reparents this setsid'd
# wrapper to launchd, which reaps it, so no waitpid of ours sees the code (2026-10-20: 6 of 7
# actuators that crossed a restart read "code unknown"). Builtins only, no fork. A signal-killed
# child is 128+N, what Popen.poll() of the wrapper reads. A non-hex nonce or a missing exits/ dir
# (a test or tool run without LR_RECON_ROOT) writes nothing.
WRAPPER = (
    'n="$4"; shift 4; "$@"; rc=$?; '
    'case "$n" in ""|*[!0-9a-f]*) ;; *) [ -d "${LR_RECON_ROOT:-/nonexistent}/exits" ] && '
    'printf "%d\\n" "$rc" 2>/dev/null >"$LR_RECON_ROOT/exits/$n.rc";; esac; exit "$rc"'
)
ACTLOG_MAX_AGE_S = (
    7 * 86400
)  # stated bound on recon/actlogs (§C12); exit files share it
# Kill switches, files under the reconciler root read every pass (no reload). exit-files.off: the
# reader ignores exit files. claim-keeper.off: the run claim's holder is ALWAYS this daemon — the
# keeper still hands a claim back to it, and never hands one to an actuator (A6 S-7).
EXITS_OFF = "exit-files.off"
KEEPER_OFF = "claim-keeper.off"
LOAD_TERM_ON = (
    "actuator-load-term.on"  # W8: restores the library's load term for actuators
)
# W13 (A7 Part D): removing recon/autorecover.on means "no new moves", never "strand the move half
# done". plan-only-finish.off restores the old gate (every plan-only record refused, none handed
# over); __main__ re-reads it every pass into PLAN_ONLY_FINISH. The hard stop stays recon.on/mode.
PLAN_ONLY_FINISH_OFF = "plan-only-finish.off"
PLAN_ONLY_FINISH = True
# The (phase, actuator) pairs that FINISH a move this reconciler spawned (A7 review F-D2): an
# explicit allowlist, because "past PRE-MOVE" also admits TARGET-LIMITED's A, which is a new move
# (a hop from the target), and the live-watcher case that leaves A in ctx.actions.
OWN_MOVE_FINISH = frozenset(
    {
        ("TRANSPLANTED", "A"),  # row 12's re-drive to the same target
        ("TRANSPLANTED", "R"),
        ("EXITED", "B"),
        ("HUSK-RETIRED", "A-husk"),
        ("HUSK-RETIRED", "UNCONFIRM"),
        ("RELAUNCHED", "C"),
        ("TARGET-TRANSIENT", "C-retry"),
        ("PANE-GONE", "R"),
        ("PRE-MOVE", "R"),  # IN-FLIGHT only (own_move_in_flight)
    }
)
_HEX = re.compile(r"[0-9a-f]{6,32}")
# The wrapper's own ps row, anchored on its interpreter so a grep or pgrep row that merely quotes
# the token is never adopted under an actuator name (A6 S-11).
_WRAPPER_TOK = re.compile(
    r"^/bin/bash -c .*?\blr-recon-act --record-id (\S+) --intent ([0-9a-f]{6,32})(?:\s|$)"
)

PopenFn = Callable[..., Any]
# pid → exit code of our own actuators, filled by reap_children and drained by settle.dead_actuators.
EXIT_CODES: Dict[int, int] = {}
# pid → (the actuator's own Popen, its nonce), held so the Popen is never garbage-collected into
# subprocess._active: every later Popen runs subprocess._cleanup, which reaped those and stole the
# exit code before reap_children's waitpid saw it (W5 rig: 32 of 113 exits read "code unknown").
_CHILDREN: Dict[int, Tuple["subprocess.Popen[bytes]", str]] = {}
# pid → nonce of every actuator THIS process spawned: the only pids an EXIT_CODES entry may speak
# for, and only under the same nonce (a reused pid never hands an actuator a stranger's code, A6 S-4).
# Popped when the code is consumed.
_SPAWNED: Dict[int, str] = {}


def _p(*parts: str) -> str:
    return os.path.join(*parts)


def actuator_env(
    rec: T.Record, paths: T.Paths, pane_sock: str, base: Optional[Dict[str, str]] = None
) -> Dict[str, str]:
    """The §C8 environment, identical for every actuator."""
    src = os.environ if base is None else base
    env = dict(src)
    env.update(
        {
            # G1 Rule 3 (W8): no actuator inherits the capacity library's load term. R's
            # cmd_replace runs boot-resume-launch.sh, whose bare cc_capacity_admit has the term ON
            # by default at a 2.0/core ceiling, which permanent 15-40/core load never opens.
            "CC_ADMIT_LOAD_TERM": "off",
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
    if os.path.exists(_p(paths.root, LOAD_TERM_ON)):
        # kill switch: the actuators get the environment's own value back, as before W8
        if "CC_ADMIT_LOAD_TERM" in src:
            env["CC_ADMIT_LOAD_TERM"] = src["CC_ADMIT_LOAD_TERM"]
        else:
            env.pop("CC_ADMIT_LOAD_TERM", None)
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
    # B7 R2: the spawn's own instant, never the pass start (p50 >= 173 s backdated before A1).
    # time.time read here, not as a default argument, so a test that patches it is honoured.
    t = max(now, time.time())
    rec.intent = T.Intent(nonce=nonce, at=t, actuator=actuator)
    store.save_record(paths, rec, t)
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
        _CHILDREN[pid] = (proc, nonce)
    _SPAWNED[pid] = nonce
    rec.procs.append(
        T.ProcRole(
            role="actuator",
            pid=pid,
            lstart=lstart_of(pid),
            argv_hash=actuator,
            nonce=nonce,
        )
    )
    store.save_record(paths, rec, t)
    fence = store.read_fence(paths, rec.sid)
    if fence is not None and fence.record_id == rec.record_id:
        fence.procs = list(rec.procs)
        store.update_fence(paths, rec.sid, fence)
    store.append_event(
        paths,
        T.Event(
            t=t,
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
    """Find live actuators for this record by their argv token and record them (§C2 step 4; A6
    rule 3 in the module docstring: the wrapper by its nonce, a known nonce repaired in place)."""
    tok = "--record-id %s" % rec.record_id
    known = {(p.pid, p.lstart) for p in rec.procs}
    found = []
    for row in snap.procs.values():
        if row.zombie or tok not in row.args or (row.pid, row.lstart) in known:
            continue
        role = "watcher" if "__recycle" in row.args else "actuator"
        name, nonce = "adopted", ""
        m = _WRAPPER_TOK.match(row.args) if role == "actuator" else None
        if m and m.group(1) == rec.record_id:
            nonce = m.group(2)  # the wrapper itself: its exit file is readable
            same = [p for p in rec.procs if p.nonce == nonce]
            if same:
                # spawn's lstart read timed out ("" lstart), or the pid was recorded wrong: one
                # spawn is one entry, or its exit is scored twice (A6 F10/S-3)
                same[0].pid, same[0].lstart = row.pid, row.lstart
                known.add((row.pid, row.lstart))
                found.append(same[0])
                continue
            # killed between Popen and the procs save (§4.5): the intent names the actuator
            it = rec.intent
            if it is not None and it.nonce == nonce and it.actuator:
                name = it.actuator
        pr = T.ProcRole(
            role=role, pid=row.pid, lstart=row.lstart, argv_hash=name, nonce=nonce
        )
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
    """Reap REGISTERED children only, every pass, so our exited actuators never linger as zombies.

    W9 (B2 F2) deleted the ``waitpid(-1)`` loop that followed: it reaped ANY child, so it stole the
    exit status another owner was about to read — CPython maps the ECHILD its own poll() then gets
    to returncode 0, and a capacity refusal (rc 9) read as an admit (/tmp/b2meas/steal.py). Every
    child is now in a registry (act._CHILDREN, clock's in-flight, orphan and detached lists) and is
    polled through its own Popen. ``recon/bounded-pass.off`` restores the old loop."""
    n = 0
    # our own actuators first: poll() owns their waitpid and keeps returncode on the object, so
    # no other reaper can race it (negative = signal, as below)
    for pid, (proc, _nonce) in list(_CHILDREN.items()):
        rc = proc.poll()
        if rc is not None:
            EXIT_CODES[pid] = rc
            del _CHILDREN[pid]
            n += 1
    n += clock.reap_orphans()
    if clock.BOUNDED_PASS:
        return n
    # the pre-W9 reaper, behind the kill switch: a child we did not spawn as an actuator is reaped
    # and its code DROPPED (pids wrap in ~86 s here; A6 §1.4)
    while True:
        try:
            pid, _status = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return n
        if pid == 0:
            return n
        if pid in _SPAWNED:
            EXIT_CODES[pid] = (
                os.WEXITSTATUS(_status)
                if os.WIFEXITED(_status)
                else -os.WTERMSIG(_status)
            )
        n += 1


def any_exited() -> bool:
    """An actuator of ours has exited: the daemon's wait wakes on it, so the exit is settled and
    its retry scheduled within ~1 s instead of 3-20 s later. poll() reaps it and keeps the code on
    the Popen, where the next reap_children reads it."""
    return any(p.poll() is not None for p, _nonce in list(_CHILDREN.values()))


def read_exit(paths: T.Paths, pr: T.ProcRole) -> Optional[int]:
    """The wrapper's durable exit code, or None (no nonce, a non-hex one, no file, unreadable, or
    exit-files.off). The nonce comes from a record file, so it is checked before it names a path."""
    if not _HEX.fullmatch(pr.nonce or "") or os.path.exists(paths.p(EXITS_OFF)):
        return None
    try:
        with open(_p(paths.exits, pr.nonce + ".rc"), encoding="ascii") as fh:
            raw = fh.read(16).strip()
    except (OSError, ValueError):
        return None
    return int(raw) if re.fullmatch(r"-?[0-9]{1,3}", raw) else None


def intent_only_exit(paths: T.Paths, rec: T.Record) -> Optional[T.ProcRole]:
    """A6 S-9: the daemon was killed between Popen and the procs save, and the wrapper exited before
    any census saw it. Nothing carries the intent's nonce, so prune_dead would clear the intent and
    the exit file would never be read. Returns a proc to settle once under ``intent.actuator`` (the
    caller then clears the intent), or None. Call it after adopt, before prune_dead."""
    it = rec.intent
    if it is None or not it.actuator or any(p.nonce == it.nonce for p in rec.procs):
        return None
    pr = T.ProcRole(
        role="actuator", pid=0, lstart="", argv_hash=it.actuator, nonce=it.nonce
    )
    return pr if read_exit(paths, pr) is not None else None


def reap_exits(paths: T.Paths, now: float) -> int:
    """Exit files older than ACTLOG_MAX_AGE_S go, at startup only. Never at consumption: a file
    must outlive the record write that consumed it (rule 7)."""
    return _reap_older(paths.exits, now)


def reap_actlogs(paths: T.Paths, now: float) -> int:
    return _reap_older(paths.p("actlogs"), now)


def _reap_older(d: str, now: float) -> int:
    n = 0
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


def own_move_in_flight(rec: T.Record, actuator: Optional[str] = None) -> bool:
    """A7 Part D: a move THIS reconciler spawned for this very attempt (close.move_attempt, stamped
    at __main__._dispatch before the spawn, == rec.attempt) and has not finished: past PRE-MOVE in an
    OWN_MOVE_FINISH phase, or PRE-MOVE/IN-FLIGHT in its relaunch gap. With ``actuator``, the (phase,
    actuator) pair must be on the allowlist too. A plan-only IN-FLIGHT record moved by another lane
    has no move_attempt, and a failed attempt bumped past it, so both stay refused."""
    if not PLAN_ONLY_FINISH or rec.terminal is not None:
        return False
    ma = rec.close.get("move_attempt")
    if ma is None or ma != rec.attempt:
        return False
    if rec.phase == "PRE-MOVE" and rec.substate != "IN-FLIGHT":
        return False
    phases = {p for p, _a in OWN_MOVE_FINISH}
    if actuator is None:
        return rec.phase in phases
    return (rec.phase, actuator) in OWN_MOVE_FINISH


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
    if rec.plan_only and not own_move_in_flight(rec, actuator):
        return False, "plan-only"
    if not rec.open:
        return False, "terminal"
    if rec.substate == "PARKED-REBOOT":
        return False, "parked-reboot"  # boot-resume owns a pre-boot plan's relaunch
    if actuator == "HEAL" and env.get("LR_HEAL_CORE_BARE", "off") != "on":
        return False, "heal-disabled"
    if live_procs(rec, snap):
        return False, "process-live"
    moves_lead = actuator == "A" or actuator == "R" and replaces(rec)
    if moves_lead and census.live_members(rec.sid, snap) > 0:
        return False, "team-live"  # D4.4: never move a lead out from under its members
    if actuator == "R" and duplicate_risk(rec, snap):
        return False, "duplicate-risk"  # invariant 27
    if rec.next_eligible_at and now < rec.next_eligible_at:
        return False, "backoff"
    if rec.escalated:
        return False, "escalated"
    if actuator in IRREVERSIBLE and not wake_ok:
        return False, "wake-guard"
    if running >= workers:
        return False, "workers-cap"
    return True, "ok"


CLAIMED_ACTUATORS = (
    "A",
    "A-husk",
    "B",
    "R",
    "C",
    "C-retry",
)  # the ones that drive the session
_SELF_LSTART: Tuple[int, str] = (0, "")  # (pid, lstart) of this daemon, read once


def self_ident(snap: Optional[T.Snapshot] = None) -> Tuple[int, str]:
    """(pid, lstart) of this process: the pass census's own row when it has one (no second ps on
    the keeper's path, whatever the load), else one bounded ps per process, cached. An lstart of ""
    means unknown: the keeper writes nothing on it."""
    global _SELF_LSTART
    pid = os.getpid()
    row = snap.procs.get(pid) if snap is not None else None
    if row is not None and row.lstart and not row.zombie:
        _SELF_LSTART = (pid, row.lstart)
        return pid, row.lstart
    if _SELF_LSTART[0] != pid or not _SELF_LSTART[1]:
        _SELF_LSTART = (pid, store.proc_lstart(pid))  # one ps per process
    return _SELF_LSTART


def keeper_on(paths: T.Paths) -> bool:
    return not os.path.exists(paths.p(KEEPER_OFF))


def claim_holder_for(
    rec: T.Record, snap: T.Snapshot, me: Tuple[int, str], keeper: bool = True
) -> Optional[Tuple[int, str]]:
    """A6 (c): who the run claim must name — a LIVE ancestor of every process driving the record.
    hf_recycle_claim_foreign (handoff-fire.sh) refuses a live holder that is not the caller or an
    ancestor, and an actuator an earlier daemon started is no descendant of this one (e80b61f4 and
    7aae55e1, 2026-10-20). Only a NAMED wrapper (recorded at spawn, or adopted by its nonce) can be
    that ancestor; an adopted descendant never is (A6 F-A). With the keeper off the holder is always
    this daemon (S-7). None: our own lstart is unknown this pass — write nothing, retry next pass."""
    if keeper:
        live = [
            p
            for p in rec.procs
            if p.role == "actuator"
            and p.argv_hash != "adopted"
            and snap.alive(p.pid, p.lstart)
        ]
        if live:
            w = live[
                -1
            ]  # the newest spawn: may_actuate allows one live actuator per record
            if snap.procs[w.pid].ppid != me[0]:  # started by an earlier daemon
                return (w.pid, w.lstart)
    return me if me[1] else None


def keep_claim(
    paths: T.Paths, rec: T.Record, snap: T.Snapshot, me: Tuple[int, str]
) -> Tuple[str, str]:
    """Re-stamp the record's OWN run claim to claim_holder_for, on change only. Never raises: an
    OSError (a steal renamed the claim dir mid-write) is unknown, retried next pass (S-6). Returns
    (event, detail): ("", "") wrote nothing · ("claim-restamp", …) · ("claim-race", …) the re-read
    after the write named someone else."""
    if not rec.open or not rec.record_id:
        return "", ""
    try:
        cur = store.read_claim(paths, rec.sid)
        if cur is None or cur.record_id != rec.record_id:
            return "", ""  # absent, or another record's or lane's: never ours to write
        want = claim_holder_for(rec, snap, me, keeper_on(paths))
        if want is None or (cur.pid, cur.lstart) == want:
            return "", ""
        if not store.claim_restamp(paths, rec.sid, rec.record_id, want[0], want[1]):
            return "", ""
        back = store.read_claim(paths, rec.sid)
    except OSError:
        return "", ""
    if back is None or (back.pid, back.lstart) != want:
        return "claim-race", "wrote %d, read back %s" % (
            want[0],
            "nothing" if back is None else "%d by %s" % (back.pid, back.owner),
        )
    return "claim-restamp", "run claim %d → %d (%s)" % (
        cur.pid,
        want[0],
        "this daemon" if want[0] == me[0] else "the actuator an earlier daemon started",
    )


def hold_claim(
    paths: T.Paths,
    rec: T.Record,
    alive: Callable[[int, str], bool],
    now: Optional[float] = None,
) -> Tuple[bool, str]:
    """ONE DRIVER PER SESSION (lr-wake 2026-10-18, Wave G): before any admission token is minted for
    an actuator that drives the session, this record must hold ``runs/by-sid/<sid>.active``.
    3e929a81 was driven at once by a drain batch (``cc-lr move``, which takes that claim), a poller
    REQUEST and this reconciler's cohort, because the reconciler's own claim (``_own_and_charge``)
    logged ``held`` and dispatched anyway. Returns (ok, the claim verdict). ``held`` and
    ``lost-race`` refuse: another live driver has the session, and nothing is minted or spawned.
    A legacy holder (pid only) counts as alive while its argv is a recovery driver naming the sid,
    the same rule the bash taker uses."""
    cur = store.read_claim(paths, rec.sid)
    if cur is not None and cur.record_id and cur.record_id == rec.record_id:
        return True, "ours"
    pid, lstart = self_ident()
    me = T.RunClaimHolder(
        pid=pid,
        lstart=lstart,
        owner="lr-reconciler",
        record_id=rec.record_id,
    )
    verdict = store.claim_take(paths, rec.sid, me, alive, _argv_of, now)
    return verdict not in ("held", "lost-race"), verdict


# W9: the legacy-holder argv reads one pass may start (each ≤ 5 s + the reap grace). Past it a
# claim reads store.UNKNOWN, which claim_take holds: retried next pass, never stolen. Without the
# cap a cohort of n records with legacy holders put n × 7 s on the serial path. None = uncapped
# (recon/pass-caps.off); __main__ resets it at every pass start.
ARGV_READS_PER_PASS = 6
_ARGV_LEFT: List[Optional[int]] = [None]


def begin_pass(capped: bool) -> None:
    _ARGV_LEFT[0] = ARGV_READS_PER_PASS if capped else None


def _argv_of(pid: int) -> str:
    """A holder's argv, "" when it has none (dead), store.UNKNOWN when it could not be read this
    pass (our own timeout, or the per-pass cap): unknown is never a verdict that steals."""
    left = _ARGV_LEFT[0]
    if left is not None:
        if left <= 0:
            return store.UNKNOWN
        _ARGV_LEFT[0] = left - 1
    try:
        cp = run_bounded(
            ["ps", "-o", "command=", "-p", str(pid)],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        return store.UNKNOWN
    except OSError:
        return ""
    return str(cp.stdout or "") if cp.returncode == 0 else ""


def workers_cap() -> int:
    try:
        return max(1, int(os.environ.get("LR_RECON_WORKERS", "16")))
    except ValueError:
        return 16


def replaces(rec: T.Record) -> bool:
    """A limited session in a launcher-rooted pane: its /exit closes the window, so its move is R,
    the existing REPLACE (lr-handoff's successor-beside-then-retire), never A (§C8 R row, §7.2
    IMPOSSIBLE-IN-PLACE). PANE-GONE's R is the other kind: a new-window resume of a dead source."""
    return (
        rec.kind == "limited"
        and rec.root_shape == "launcher"
        and rec.phase != "PANE-GONE"
    )


def duplicate_risk(rec: T.Record, snap: T.Snapshot) -> str:
    """Invariant 27: R starts a session, so any holder of the sid outside the record's own pane (or
    one whose pane is unknown, or a background row) is a live copy R would duplicate. A replace over a
    live source passes only with the source alone in its pane; a PANE-GONE resume only with none."""
    s = snap.sessions.get(rec.sid)
    for h in s.holders if s else []:
        if h.bg or h.pane is None or not rec.pane or tuple(h.pane) != tuple(rec.pane):
            return "pid %d holds %s outside pane %s" % (h.pid, rec.sid[:8], rec.pane)
    return ""


def choose(res: T.PhaseResult, rec: T.Record) -> Optional[str]:
    """PhaseResult.action → the actuator to run, or None for wait/sentinel/page/plan-only."""
    a = res.action
    if res.phase == "PRE-MOVE":
        if a == "wake" and rec.substate in ("WAIT_RESET", "HELD:team"):
            return "C"  # the in-place reset wake (D1.11, D4.9)
        if rec.substate != "PLANNED" or not rec.target_acct:
            return None
        return "R" if replaces(rec) else "A"
    if a == "A" and replaces(rec):
        # row 12 re-drives the move: on a launcher-rooted pane that is R again
        return "R"
    if a in ("A", "A-husk", "B", "R", "UNCONFIRM", "SPLIT", "C-retry"):
        return a
    if a == "C" and res.substate in ("UNPROMPTED", "DRAFTED"):
        return "C"
    return None


def running_count(records: Dict[str, T.Record], snap: T.Snapshot) -> int:
    return sum(1 for r in records.values() if live_procs(r, snap))


def sleep_briefly(s: float = 0.05) -> None:
    time.sleep(s)
