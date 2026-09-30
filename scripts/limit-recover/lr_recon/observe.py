"""The census: one read per instrument per pass, pure data after that (§C3 items 1-7, 9, 11).

``observe()`` never raises. An instrument that fails appends its name to ``Snapshot.degraded`` and
nothing is inferred for the part it covers, because a missing read that looked like "no pane" or
"no holder" would plan a move over a live session (invariants 12, 13). Every external effect goes
through an injectable seam (``run``, ``glob_fn``, ``lstat_fn``, ``transcript_fn``) so the tests are
hermetic.
"""

from __future__ import annotations

import glob
import json
import os
import re
import shutil
import stat
import subprocess
import time
from typing import Any, Callable, Dict, FrozenSet, List, Mapping, Optional, Tuple

from lr_recon import types as T
from lr_recon.observe_rows import (
    SHELLS,
    GlobFn,
    acct_cfg_map,
    acct_of_cfg,
    argv0,
    bind as bind,  # re-exported: bind is part of observe's surface (§C3.2)
    bg_host_pid,
    bg_work_for,
    children_map,
    holders_for,
    is_claude,
    is_iterm,
    live,
    read_registry,
    read_session_rows,
    registry_cfg,
    resume_leaves,
)

RunFn = Callable[..., Any]
TranscriptFn = Callable[[str, str, str], T.TranscriptObs]
PS_ENV_OVERRIDES = {"TZ": "UTC", "LC_ALL": "C"}
KITTEN_APP = "/Applications/kitty.app/Contents/MacOS/kitten"


def rig_mode(env: Optional[Mapping[str, str]] = None) -> bool:
    """The W5 rig daemon (LR_RECON_RIG=1, the plist's name; LR_RIG=1, the plan's) sees ONLY sessions
    whose registry row carries ``rig: true``. Every other sid — a real session found through its
    ``--resume`` argv, a planted row without the tag — is dropped from the census before any bucket,
    record or actuator can exist for it, and named in ``Snapshot.rig_refused``."""
    e: Mapping[str, str] = os.environ if env is None else env
    return e.get("LR_RECON_RIG") == "1" or e.get("LR_RIG") == "1"


def _ps_env() -> Dict[str, str]:
    env = dict(os.environ)
    env.update(PS_ENV_OVERRIDES)
    return env


def _run_ok(
    run: RunFn, argv: List[str], timeout: float, env: Optional[Dict[str, str]] = None
) -> str:
    """stdout of a bounded call; raises on a non-zero exit so the caller degrades the instrument."""
    res = run(argv, capture_output=True, text=True, timeout=timeout, env=env)
    if res.returncode != 0:
        raise RuntimeError("%s exited %s" % (argv[0], res.returncode))
    return str(res.stdout or "")


# ── C3.1: processes ──────────────────────────────────────────────────────────────────────────────


def read_ps(run: RunFn = subprocess.run) -> Tuple[Dict[int, T.ProcRow], Dict[int, str]]:
    """The two ps reads. macOS ps has no `lstat` keyword, so the state column is `stat`; lstart's
    padded day (`Sep  9`) is collapsed to single spaces, the rendering `tr -s ' '` gives the shell
    side, so holders compare equal across the package. Raises on failure (observe degrades "ps")."""
    env = _ps_env()
    out = _run_ok(
        run, ["/bin/ps", "-axww", "-o", "pid=,ppid=,stat=,lstart=,args="], 20.0, env
    )
    procs: Dict[int, T.ProcRow] = {}
    for line in out.splitlines():
        t = line.split(None, 8)
        if len(t) < 8 or not t[0].isdigit() or not t[1].isdigit():
            continue
        args = t[8].strip() if len(t) > 8 else ""
        procs[int(t[0])] = T.ProcRow(int(t[0]), int(t[1]), t[2], " ".join(t[3:8]), args)
    ttys: Dict[int, str] = {}
    for line in _run_ok(run, ["/bin/ps", "-axo", "pid=,tty="], 20.0, env).splitlines():
        t = line.split()
        if len(t) == 2 and t[0].isdigit() and t[1] not in ("??", "-"):
            ttys[int(t[0])] = t[1]
    if not procs:
        raise RuntimeError("ps returned no rows")
    return procs, ttys


# ── C3.2-3: kitty instances and panes ────────────────────────────────────────────────────────────


def kitty_sockets(
    procs: Dict[int, T.ProcRow],
    glob_fn: GlobFn = glob.glob,
    lstat_fn: Callable[[str], os.stat_result] = os.lstat,
) -> List[str]:
    """`unix:/tmp/kitty-<pid>` for each real socket (not a symlink, not a log) owned by a live kitty.
    Mirrors handoff-fire.sh kitty_sockets; `[ -S ]` there is a reject, the `ls` call is the verdict."""
    out: List[str] = []
    for path in sorted(glob_fn("/tmp/kitty-*")):
        suffix = path.rsplit("kitty-", 1)[-1]
        if not suffix.isdigit():
            continue
        try:
            if not stat.S_ISSOCK(lstat_fn(path).st_mode):
                continue
        except OSError:
            continue
        row = live(int(suffix), procs)
        if row is not None and argv0(row.args) == "kitty":
            addr = "unix:" + path
            if addr not in out:
                out.append(addr)
    return out


def kitten_bin(
    env: Optional[Dict[str, str]] = None,
    exists: Callable[[str], bool] = os.path.exists,
    which: Callable[[str], Optional[str]] = shutil.which,
) -> str:
    """LR_KITTEN_BIN, else the app bundle's kitten, else PATH (launchd's PATH lacks it — W0 §4)."""
    e: Mapping[str, str] = os.environ if env is None else env
    if e.get("LR_KITTEN_BIN"):
        return e["LR_KITTEN_BIN"]
    if exists(KITTEN_APP):
        return KITTEN_APP
    return which("kitten") or "kitten"


def kitty_ls(
    sock: str,
    run: RunFn = subprocess.run,
    timeout: float = 5.0,
    kitten: Optional[str] = None,
    degraded: Optional[List[str]] = None,
) -> Optional[List[Any]]:
    """One bounded `kitten @ ls`; any failure ⇒ None and ``kitty:<sock>`` degraded (§C3.2)."""
    try:
        data = json.loads(
            _run_ok(run, [kitten or kitten_bin(), "@", "--to", sock, "ls"], timeout)
        )
        if isinstance(data, list):
            return data
    except Exception:  # noqa: BLE001 — timeout, missing binary, torn JSON: all one verdict
        pass
    if degraded is not None:
        degraded.append("kitty:" + sock)
    return None


def _pane_state(root_pid: int, fg: List[Dict[str, Any]]) -> str:
    cmds = [
        (p.get("pid"), " ".join(str(a) for a in (p.get("cmdline") or [])))
        for p in fg
        if isinstance(p, dict)
    ]
    if any(is_claude(c) for _, c in cmds):
        return "claude"
    if cmds and all(pid == root_pid and argv0(c) in SHELLS for pid, c in cmds):
        return "shell"
    return "unknown"


def panes_from_ls(
    sock: str,
    kitty_pid: int,
    data: List[Any],
    procs: Dict[int, T.ProcRow],
    tty_by_pid: Dict[int, str],
) -> List[T.PaneObs]:
    """PaneObs per window; focused only when window, tab AND OS window are all focused (§C3.3)."""
    kl = procs[kitty_pid].lstart if kitty_pid in procs else ""
    out: List[T.PaneObs] = []
    for osw in data if isinstance(data, list) else []:
        if not isinstance(osw, dict):
            continue
        for tab in osw.get("tabs") or []:
            if not isinstance(tab, dict):
                continue
            for w in tab.get("windows") or []:
                if not isinstance(w, dict) or not isinstance(w.get("id"), int):
                    continue
                pv = w.get("pid")
                rp = pv if isinstance(pv, int) else 0
                row = procs.get(rp)
                root_args = (
                    row.args
                    if row
                    else " ".join(str(a) for a in w.get("cmdline") or [])
                )
                out.append(
                    T.PaneObs(
                        kitty_pid=kitty_pid,
                        window_id=w["id"],
                        sock=sock,
                        kitty_lstart=kl,
                        tty=tty_by_pid.get(rp, ""),
                        root_pid=rp,
                        root_lstart=row.lstart if row else "",
                        is_focused=bool(
                            osw.get("is_focused")
                            and tab.get("is_focused")
                            and w.get("is_focused")
                        ),
                        title=str(w.get("title") or ""),
                        cwd=str(w.get("cwd") or ""),
                        root_shape="shell"
                        if argv0(root_args) in SHELLS
                        else "launcher",
                        state=_pane_state(rp, w.get("foreground_processes") or []),
                    )
                )
    return out


# ── the composer (idle fan-out only): the same box read as handoff-fire's composer_content ──────

_ESC = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b.")
_SGR = re.compile(r"\x1b\[([0-9;:]*)m")
_PLACEHOLDER = re.compile(r'^\s*Try "[^"]*("|\.\.\.)\s*$')
BORDER = "─" * 12
_CHROME = frozenset("\u276f")  # ❯; the U+00A0 after it is not printable, so isprintable() drops it


def _unfaint(line: str) -> str:
    """Drop escapes and every FAINT (SGR 2) run: CC's prompt suggestion is faint, input never is."""
    out, faint, i = [], False, 0
    for m in re.finditer(
        r"\x1b\[([0-9;:]*)m|\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b.",
        line,
    ):
        if not faint:
            out.append(line[i : m.start()])
        if m.group(1) is not None:
            params = m.group(1).split(";") if m.group(1) else [""]
            k = 0
            while k < len(params):
                c = params[k].split(":")[0]
                if c in ("", "0", "22"):
                    faint = False
                elif c == "2":
                    faint = True
                elif c in ("38", "48", "58") and ":" not in params[k]:
                    nxt = params[k + 1] if k + 1 < len(params) else ""
                    k += 2 if nxt == "5" else 4 if nxt == "2" else 0
                k += 1
        i = m.end()
    if not faint:
        out.append(line[i:])
    return "".join(out)


def composer_from_screen(screen: str) -> str:
    """ "empty" | "draft" | "unknown" from a --ansi screen: the rows strictly between the last two
    border rows, faint runs dropped; a whole-row `Try "…"` is the placeholder.

    Only the known chrome is stripped — the prompt glyph ❯, and the U+00A0 after it, which is not
    printable — and every other printable non-space character is content (D6.8). Keeping printable ASCII only read a
    draft written wholly in non-ASCII as EMPTY, and /exit could then merge into it."""
    lines = screen.splitlines()
    plain = [_ESC.sub("", ln) for ln in lines]
    borders = [i for i, ln in enumerate(plain) if BORDER in ln]
    if len(borders) < 2 or borders[-1] - borders[-2] < 2:
        return "unknown"
    rows = []
    for ln in lines[borders[-2] + 1 : borders[-1]]:
        txt = "".join(
            ch for ch in _unfaint(ln) if ch not in _CHROME and ch.isprintable()
        )
        if not _PLACEHOLDER.match(txt):
            rows.append(txt)
    return "draft" if "".join("".join(rows).split()) else "empty"


def composer_state(
    sock: str,
    window_id: int,
    run: RunFn = subprocess.run,
    kitten: Optional[str] = None,
    timeout: float = 5.0,
) -> str:
    try:
        scr = _run_ok(
            run,
            [
                kitten or kitten_bin(),
                "@",
                "--to",
                sock,
                "get-text",
                "--match",
                "id:%d" % window_id,
                "--extent",
                "screen",
                "--ansi",
            ],
            timeout,
        )
    except Exception:  # noqa: BLE001 — a read we could not make is unknown, never empty
        return "unknown"
    return composer_from_screen(scr)


# ── C3.4-5, 7: sessions ──────────────────────────────────────────────────────────────────────────


def _uptime_raw() -> float:
    clk = getattr(time, "CLOCK_MONOTONIC_RAW", None)
    return time.clock_gettime(clk) if clk is not None else time.monotonic()


def observe(
    paths: Optional[T.Paths],
    home: str,
    run: RunFn = subprocess.run,
    glob_fn: GlobFn = glob.glob,
    transcript_fn: Optional[TranscriptFn] = None,
    now: Optional[float] = None,
    lstat_fn: Callable[[str], os.stat_result] = os.lstat,
    kitten: Optional[str] = None,
    registry_dir: Optional[str] = None,
    rig: Optional[bool] = None,
    rig_keep: FrozenSet[str] = frozenset(),
) -> T.Snapshot:
    """One census pass. Never raises: every instrument is fenced and degrades by name."""
    snap = T.Snapshot(
        wall=time.time() if now is None else now, uptime_raw=_uptime_raw()
    )
    try:
        snap.procs, ttys = read_ps(run)
        snap.ttys = sorted(set(ttys.values()))
    except Exception:  # noqa: BLE001
        snap.degraded.append("ps")
        return snap
    procs = snap.procs
    try:
        snap.sockets = kitty_sockets(procs, glob_fn, lstat_fn)
    except Exception:  # noqa: BLE001
        snap.degraded.append("kitty-sockets")
    roots: Dict[int, Tuple[int, int]] = {}
    for sock in snap.sockets:
        kpid = int(sock.rsplit("-", 1)[-1])
        data = kitty_ls(sock, run, kitten=kitten, degraded=snap.degraded)
        if data is None:
            continue
        try:
            for p in panes_from_ls(sock, kpid, data, procs, ttys):
                snap.panes["%d:%d" % p.key] = p
                if p.root_pid:
                    roots[p.root_pid] = p.key
        except Exception:  # noqa: BLE001
            snap.degraded.append("kitty:" + sock)
    try:
        _sessions(
            snap,
            home,
            glob_fn,
            roots,
            registry_dir,
            transcript_fn,
            rig_mode() if rig is None else rig,
            rig_keep,
            paths.canary if paths is not None else frozenset(),
        )
    except Exception:  # noqa: BLE001
        snap.degraded.append("sessions")
    return snap


def _sessions(
    snap: T.Snapshot,
    home: str,
    glob_fn: GlobFn,
    roots: Dict[int, Tuple[int, int]],
    registry_dir: Optional[str],
    transcript_fn: Optional[TranscriptFn],
    rig: bool = False,
    rig_keep: FrozenSet[str] = frozenset(),
    canary: FrozenSet[str] = frozenset(),
) -> None:
    procs = snap.procs
    kitty_ok = not any(d.startswith("kitty") for d in snap.degraded)
    amap = acct_cfg_map(home)
    if not amap:
        snap.degraded.append("accounts")
    try:
        reg = read_registry(
            registry_dir or os.path.join(home, ".claude", "cc-registry"), glob_fn
        )
    except Exception:  # noqa: BLE001
        reg = []
        snap.degraded.append("registry")
    try:
        srows = read_session_rows(home, procs, glob_fn)
    except Exception:  # noqa: BLE001
        srows = []
        snap.degraded.append("session-rows")
    leaves = resume_leaves(procs)
    kids = children_map(procs)
    bg_rows = [
        (bg_host_pid(r["pid"], procs), procs[r["pid"]])
        for _, r in srows
        if r.get("kind") == "bg"
    ]

    sids: List[str] = []
    for s in (
        [r["session_id"] for r in reg]
        + [r["sessionId"] for _, r in srows]
        + list(leaves)
    ):
        if s not in sids:
            sids.append(s)
    for sid in sids:
        rrows = [r for r in reg if r["session_id"] == sid]
        # membership is a property of the SID: once the daemon holds a record for it (only rig sids
        # ever get one), a pane-keyed registry file another process overwrote must not hide it
        # mid-move (W5 rig 0c95685d: a stray --version probe's row stranded it IN-FLIGHT)
        if rig and sid not in rig_keep and not any(r.get("rig") is True for r in rrows):
            snap.rig_refused.append(sid)
            continue
        # a canary daemon (W5b) sees only its listed throwaway sids: every real session is dropped
        # here, before a bucket, record or actuator can exist for it
        if canary and sid not in canary:
            snap.rig_refused.append(sid)
            continue
        live_reg = [r for r in rrows if live(r.get("pid"), procs) is not None]
        pick = live_reg or rrows
        rrow: Optional[Dict[str, Any]] = pick[-1] if pick else None
        sources: List[Tuple[str, str, int, str]] = [
            ("session-row", cfg, r["pid"], str(r.get("kind") or ""))
            for cfg, r in srows
            if r["sessionId"] == sid
        ]
        sources += [
            (
                "registry",
                registry_cfg(str(r.get("account") or ""), home, amap),
                r["pid"] if isinstance(r.get("pid"), int) else 0,
                "",
            )
            for r in rrows
        ]
        sources += [("resume-argv", "", p, "") for p in leaves.get(sid, [])]
        holders = holders_for(sources, procs, roots)
        bound = [h for h in holders if h.pane is not None and not h.bg]
        ranked = bound or [h for h in holders if not h.bg] or holders
        lead: Optional[T.HolderObs] = ranked[0] if ranked else None
        iterm = rrow is not None and (
            is_iterm(rrow) or (bool(live_reg) and not bound and kitty_ok)
        )
        cfg = (lead.cfg if lead else "") or next((h.cfg for h in holders if h.cfg), "")
        cwd = str(rrow.get("cwd") or "") if rrow else ""
        if not cwd:
            cwd = next(
                (str(r.get("cwd") or "") for c, r in srows if r["sessionId"] == sid), ""
            )
        name = str(rrow.get("name") or "") if rrow else ""
        cps = {h.pid for h in holders if not h.bg}
        cps |= {
            k for p in list(cps) for k in kids.get(p, []) if is_claude(procs[k].args)
        }
        obs = T.SessionObs(
            sid=sid,
            cfg=cfg,
            acct=acct_of_cfg(cfg, amap),
            pid=lead.pid if lead else 0,
            lstart=lead.lstart if lead else "",
            cwd=cwd,
            pane=None if iterm or lead is None else lead.pane,
            holders=holders,
            bg_work=bg_work_for(cps, procs, kids, bg_rows),
            registry_name=("iterm:" + name) if iterm else name,
        )
        if not obs.cwd and obs.pane is not None:
            obs.cwd = snap.panes["%d:%d" % obs.pane].cwd
        if transcript_fn is not None:
            try:
                obs.transcript = transcript_fn(obs.cfg, obs.cwd, sid)
            except Exception:  # noqa: BLE001
                snap.degraded.append("transcript:" + sid)
        snap.sessions[sid] = obs


def census_line(snapshot: T.Snapshot) -> str:
    """One human line for the `--mode observe --once` proof."""
    nclaude = sum(
        1 for r in snapshot.procs.values() if not r.zombie and is_claude(r.args)
    )
    ss = snapshot.sessions.values()
    nbg = sum(1 for s in ss if s.bg_work)
    nit = sum(1 for s in ss if s.registry_name.startswith("iterm:"))
    return (
        "census: %d claude procs · %d panes on %d kitty sockets · %d sessions (%d bg-work, %d iterm) · degraded: %s"
        % (
            nclaude,
            len(snapshot.panes),
            len(snapshot.sockets),
            len(snapshot.sessions),
            nbg,
            nit,
            ", ".join(snapshot.degraded) or "none",
        )
    )
