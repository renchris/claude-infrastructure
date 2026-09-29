"""Snapshot + record → ``T.Evidence``: the one bridge from what the census saw to ``derive_phase``.

``derive_phase`` is pure (§4.2); everything impure it needs is gathered here, once per record per
pass: the holder set classified against the record's source/target config dirs, the tombstone and
stub files, live watcher / launcher processes by argv, the pane's presence and identity, and the
target copy's submit-token and turn reads (``tokens``). Cross-pass history (two absent scans for
PANE-GONE, two holder samples ≥15 s apart for MOVED) lives on the record and is advanced by
``advance_history`` AFTER the evidence is taken, so one pass never counts twice.

Fail-closed choices, each named where it is made: an unrecorded identity never matches (no B
relaunch on a guess); a pane whose kitty instance was DEGRADED is "unknown", never "gone" (no R
over a pane we simply could not read).
"""

from __future__ import annotations

import glob
import os
from typing import Callable, Dict, List, Optional

from lr_recon import tokens
from lr_recon import types as T
from lr_recon.transcript import slug

MOVED_SAMPLE_GAP_S = 15.0

ReadinessFn = Callable[[T.Record], str]
DebtFn = Callable[[str], bool]


def _real(p: str) -> str:
    try:
        return os.path.realpath(os.path.expanduser(p)) if p else ""
    except OSError:
        return p


def _same_cfg(a: str, b: str) -> bool:
    """``.claude`` and ``.claude-next`` are ONE account (invariant 24): compare resolved projects/."""
    if not a or not b:
        return False
    ra, rb = _real(os.path.join(a, "projects")), _real(os.path.join(b, "projects"))
    return ra == rb or _real(a) == _real(b)


def transcript_path(cfg: str, cwd: str, sid: str) -> str:
    """Slug-direct path, then a glob fallback that also finds a tombstoned copy."""
    if not cfg:
        return ""
    direct = os.path.join(cfg, "projects", slug(cwd), sid + ".jsonl")
    if os.path.exists(direct) or os.path.exists(direct + ".handed-off"):
        return direct
    for pat in (sid + ".jsonl", sid + ".jsonl.handed-off"):
        hits = sorted(glob.glob(os.path.join(cfg, "projects", "*", pat)))
        if hits:
            return (
                hits[0][: -len(".handed-off")]
                if hits[0].endswith(".handed-off")
                else hits[0]
            )
    return direct


def _holders(rec: T.Record, s: Optional[T.SessionObs]) -> List[T.EvHolder]:
    out: List[T.EvHolder] = []
    for h in s.holders if s else []:
        if h.pid == rec.source_pid and h.lstart == rec.source_lstart:
            cfg = "source"
        elif _same_cfg(h.cfg, rec.target_cfg):
            cfg = "target"
        elif _same_cfg(h.cfg, rec.source_cfg):
            cfg = "source"
        else:
            cfg = "other"
        out.append(
            T.EvHolder(
                cfg=cfg,
                pane_bound=bool(rec.pane) and h.pane == rec.pane,
                bg=h.bg,
                role="bg-row" if h.bg else "claude",
            )
        )
    return out


def _argv_live(snap: T.Snapshot, sid: str, *needles: str) -> bool:
    for row in snap.procs.values():
        if row.zombie or sid not in row.args:
            continue
        if all(n in row.args for n in needles):
            return True
    return False


def _role_live(rec: T.Record, snap: T.Snapshot, *roles: str) -> bool:
    return any(p.role in roles and snap.alive(p.pid, p.lstart) for p in rec.procs)


def _pane(rec: T.Record, snap: T.Snapshot) -> Optional[T.PaneObs]:
    if not rec.pane:
        return None
    return snap.panes.get("%d:%d" % (rec.pane[0], rec.pane[1]))


def _pane_state(rec: T.Record, snap: T.Snapshot) -> str:
    pane = _pane(rec, snap)
    if pane is not None:
        return pane.state
    if not rec.pane:
        return "unknown"
    # A kitty instance we could not read proves nothing about its windows (fail closed).
    if any(d.startswith("kitty:") or d == "ps" for d in snap.degraded):
        return "unknown"
    return "gone"


def _tty_present(rec: T.Record, snap: T.Snapshot) -> bool:
    ident = rec.identity
    if ident.root_pid and ident.root_lstart:
        return snap.alive(ident.root_pid, ident.root_lstart)
    if not ident.tty:
        return False
    if snap.ttys:
        return os.path.basename(ident.tty) in snap.ttys
    return os.path.exists(ident.tty if ident.tty.startswith("/") else "/dev/" + ident.tty)


def _identity_match(rec: T.Record, pane: Optional[T.PaneObs]) -> bool:
    ident = rec.identity
    if pane is None or not ident.root_pid:
        return False  # unrecorded identity never matches: no relaunch typed on a guess
    return (
        pane.kitty_pid == ident.kitty_pid
        and pane.window_id == ident.window_id
        and pane.root_pid == ident.root_pid
        and pane.root_lstart == ident.root_lstart
    )


def _lock_names_target(paths: T.Paths, rec: T.Record) -> bool:
    lock = os.path.join(paths.locks, rec.sid + ".lock")
    try:
        with open(lock, encoding="utf-8", errors="replace") as fh:
            body = fh.read(4096)
    except OSError:
        return False
    return bool(rec.target_cfg) and any(
        ('"to":"%s"' % c) in body for c in {rec.target_cfg, _real(rec.target_cfg)} if c
    )


def _debt_open(sid: str) -> bool:
    """An open resume debt (bin/cc-resume-debt, states open|retrying|escalated) names the sid."""
    d = os.environ.get("CC_RESUME_DEBT_DIR") or os.path.expanduser(
        "~/.claude/autonomy/resume-debt"
    )
    meta = os.path.join(d, "meta", sid + ".json")
    try:
        with open(meta, encoding="utf-8", errors="replace") as fh:
            body = fh.read(8192)
    except OSError:
        return False
    return any(
        '"state":"%s"' % s in body.replace(" ", "")
        for s in ("open", "retrying", "escalated")
    )


def _no_readiness(rec: T.Record) -> str:
    return "none"


def build(
    paths: T.Paths,
    rec: T.Record,
    snap: T.Snapshot,
    readiness: ReadinessFn = _no_readiness,
    debt_open: DebtFn = _debt_open,
) -> T.Evidence:
    """Gather §4.2's inputs for one record. Never raises on a missing file: absent = false."""
    s = snap.sessions.get(rec.sid)
    src_tx = transcript_path(rec.source_cfg, rec.cwd, rec.sid)
    handed = bool(src_tx) and os.path.exists(src_tx + ".handed-off")
    stub = handed and os.path.exists(src_tx)
    source_alive = bool(rec.source_pid) and snap.alive(
        rec.source_pid, rec.source_lstart
    )
    pane = _pane(rec, snap)
    state = _pane_state(rec, snap)

    ev = T.Evidence(
        kind=rec.kind,
        attempt=rec.attempt,
        holders=_holders(rec, s),
        source_alive=source_alive,
        source_at_composer=source_alive and state == "claude",
        handed_off=handed,
        stub_present=stub,
        live_watcher=_argv_live(snap, rec.sid, "handoff-fire", "__recycle")
        or _role_live(rec, snap, "watcher"),
        live_launcher=_argv_live(snap, rec.sid, "lr-fire-resume")
        or _role_live(rec, snap, "launcher", "fire_resume"),
        pane_state=state,
        pane_absent_observations=rec.pane_absent_obs + (state == "gone"),
        # The pane's tty is "present" while the pane's recorded ROOT process (pid + lstart) lives.
        # A device-node test never goes false on macOS (the /dev/ttysNNN node outlives its window),
        # and "held by any process" went true again within seconds when another session's expect
        # pty took the freed number (both seen in the W5 rig). pid + lstart cannot be reused. With
        # no recorded root, fall back to the tty being held by a live process, then to the node.
        tty_present=_tty_present(rec, snap),
        identity_match=_identity_match(rec, pane),
        exit_typed_by_me=rec.timeline.exit_typed_by_me is not None,
        resume_debt_open=debt_open(rec.sid),
        lock_names_target=_lock_names_target(paths, rec),
        source_retired=handed,
        submitted=rec.timeline.submitted is not None,
        confirm_len=rec.confirm_len,
        readiness=readiness(rec),
        relaunch_substate="DRAFTED" if rec.substate == "DRAFTED" else None,
        last_error_class=rec.last_error.cls if rec.last_error else "",
        pre_move=(rec.substate or "") if rec.phase == "PRE-MOVE" else "",
    )
    _target_reads(rec, ev)
    ev.holder_stable_two_samples = _stable(rec, s, snap.wall)
    return ev


def _target_reads(rec: T.Record, ev: T.Evidence) -> None:
    """Rows 2-5 read the TARGET copy: this attempt's token past confirm_len, then the turn after."""
    tgt = transcript_path(rec.target_cfg, rec.cwd, rec.sid)
    if not tgt or not os.path.exists(tgt):
        return
    offset = rec.confirm_len or 0
    if rec.submit_token:
        found = tokens.find_token(tgt, rec.submit_token, 0)
        if found is not None:
            ev.token_record_offset = found
            ev.token_is_this_attempt = (
                True  # tokens are minted per attempt (§7.3 Engage prompt)
            )
            offset = found
    ev.target_last_assistant = tokens.last_assistant_after(tgt, offset)
    if ev.token_record_offset is not None:
        ev.nonerror_assistant_after_token = tokens.nonerror_after(
            tgt, ev.token_record_offset
        )


def _target_holder(rec: T.Record, s: Optional[T.SessionObs]) -> Optional[T.HolderObs]:
    for h in s.holders if s else []:
        if (
            _same_cfg(h.cfg, rec.target_cfg)
            and rec.pane
            and h.pane == rec.pane
            and not h.bg
        ):
            return h
    return None


def _stable(rec: T.Record, s: Optional[T.SessionObs], now: float) -> bool:
    h, prev = _target_holder(rec, s), rec.target_sample
    if h is None or not prev:
        return False
    return (
        prev.get("pid") == h.pid
        and prev.get("lstart") == h.lstart
        and now - float(prev.get("at", now)) >= MOVED_SAMPLE_GAP_S
    )


def advance_history(rec: T.Record, ev: T.Evidence, snap: T.Snapshot) -> None:
    """Carry this pass's observations into the record, after ``derive_phase`` has read them."""
    rec.pane_absent_obs = ev.pane_absent_observations if ev.pane_state == "gone" else 0
    s = snap.sessions.get(rec.sid)
    h = _target_holder(rec, s)
    if h is None:
        rec.target_sample = None
    elif not rec.target_sample or (
        rec.target_sample.get("pid"),
        rec.target_sample.get("lstart"),
    ) != (h.pid, h.lstart):
        rec.target_sample = {"pid": h.pid, "lstart": h.lstart, "at": snap.wall}


def derive(
    paths: T.Paths,
    rec: T.Record,
    snap: T.Snapshot,
    readiness: ReadinessFn = _no_readiness,
    debt_open: DebtFn = _debt_open,
) -> Dict[str, object]:
    """Convenience for main/observe: evidence + phase in one call (phase imported lazily)."""
    from lr_recon.phase import derive_phase

    ev = build(paths, rec, snap, readiness, debt_open)
    res = derive_phase(ev)
    advance_history(rec, ev, snap)
    return {"evidence": ev, "result": res}
