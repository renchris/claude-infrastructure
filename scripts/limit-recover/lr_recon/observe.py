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

from lr_recon import clock as _clock
from lr_recon import store
from lr_recon import types as T
from lr_recon.clock import run_bounded, step
from lr_recon.observe_rows import (
    SHELLS,
    GlobFn,
    acct_cfg_map,
    acct_of_cfg,
    ancestors,
    argv0,
    bind as bind,  # re-exported: bind is part of observe's surface (§C3.2)
    bg_host_pid,
    bg_work_for,
    children_map,
    holders_for,
    is_claude,
    is_iterm,
    live,
    live_as,
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


# W7a: at load 87-116 the census read "0 claude procs · degraded: ps" — ps failed under a flat 20 s
# bound with no second try. The bound now grows with load per cpu (vm.loadavg, the fleet's load
# source) and each call gets one retry, all inside one budget that leaves most of the watchdog's
# 180 s stall window to the rest of the pass. A read that fails past its retry still degrades "ps",
# and the pass then decides nothing (``untrusted`` below, __main__.run_pass).
PS_BOUND_S = 20.0  # per call on a quiet box: the flat pre-W7a bound
PS_BOUND_MAX_S = 40.0  # per call at 10+ runnable threads per cpu
PS_ATTEMPTS = 2  # the first try and one retry
PS_BUDGET_S = 90.0  # every ps call of one pass together, retries included
PS_MIN_CALL_S = 5.0  # a try with less budget left than this is not started


def ps_bound(
    load_fn: Callable[[], Tuple[float, ...]] = os.getloadavg,
    ncpu: Optional[int] = None,
) -> float:
    """PS_BOUND_S × (1 + load-per-cpu / 10), capped at PS_BOUND_MAX_S; an unreadable load keeps
    the flat bound."""
    try:
        per_cpu = float(load_fn()[0]) / max(1, ncpu or os.cpu_count() or 1)
    except (OSError, ValueError, TypeError, IndexError):
        return PS_BOUND_S
    return min(PS_BOUND_MAX_S, PS_BOUND_S * (1.0 + max(0.0, per_cpu) / 10.0))


def _parse_procs(out: str) -> Dict[int, T.ProcRow]:
    procs: Dict[int, T.ProcRow] = {}
    for line in out.splitlines():
        t = line.split(None, 8)
        if len(t) < 8 or not t[0].isdigit() or not t[1].isdigit():
            continue
        args = t[8].strip() if len(t) > 8 else ""
        procs[int(t[0])] = T.ProcRow(int(t[0]), int(t[1]), t[2], " ".join(t[3:8]), args)
    return procs


def _parse_ttys(out: str) -> Dict[int, str]:
    ttys: Dict[int, str] = {}
    for line in out.splitlines():
        t = line.split()
        if len(t) == 2 and t[0].isdigit() and t[1] not in ("??", "-"):
            ttys[int(t[0])] = t[1]
    return ttys


def _ps_read(
    run: RunFn,
    argv: List[str],
    env: Dict[str, str],
    bound: float,
    deadline: float,
    clock: Callable[[], float],
    accept: Callable[[str], Optional[Any]],
    attempts: int = PS_ATTEMPTS,
) -> Tuple[Any, int]:
    """(parsed, tries) for one ps call. A timeout, a non-zero exit or output ``accept`` rejects
    (None) is retried once; each try is bounded by min(bound, the budget left). Raises naming every
    try's failure, so the abstain event says whether ps hung, failed or returned nothing."""
    why: List[str] = []
    for attempt in range(1, attempts + 1):
        left = deadline - clock()
        if left < PS_MIN_CALL_S:
            why.append("ps budget spent")
            break
        t = min(bound, left)
        try:
            got = accept(_run_ok(run, argv, t, env))
        except subprocess.TimeoutExpired:
            why.append("timed out at %.0fs" % t)
            continue
        except Exception as e:  # noqa: BLE001 — every failure is one more try
            why.append(str(e)[:80] or type(e).__name__)
            continue
        if got is not None:
            return got, attempt
        why.append("no rows")
    raise RuntimeError("%s %s: %s" % (argv[0], argv[-1], "; ".join(why)))


def read_ps(
    run: RunFn = run_bounded,
    bound: Optional[float] = None,
    budget: float = PS_BUDGET_S,
    clock: Callable[[], float] = time.monotonic,
    stats: Optional[Dict[str, int]] = None,
) -> Tuple[Dict[int, T.ProcRow], Dict[int, str]]:
    """The two ps reads. macOS ps has no `lstat` keyword, so the state column is `stat`; lstart's
    padded day (`Sep  9`) is collapsed to single spaces, the rendering `tr -s ' '` gives the shell
    side, so holders compare equal across the package. Raises on failure (observe degrades "ps").
    ``stats["attempts"]`` gets the most tries either call took."""
    env = _ps_env()
    b = ps_bound() if bound is None else bound
    deadline = clock() + budget
    # W9 (B2 efficacy 6): with the kill-wait bounded, a kernel stall now parks each timed-out ps as
    # an orphan, and a second try forks another reader into the same stuck path. While
    # ORPHAN_RETRY_SKIP_AT of them are still alive, one try per call — never zero: a census that
    # never runs recovers nothing.
    tries = 1 if _clock.orphans_of("ps") >= _clock.ORPHAN_RETRY_SKIP_AT else PS_ATTEMPTS
    procs, n1 = _ps_read(
        run,
        ["/bin/ps", "-axww", "-o", "pid=,ppid=,stat=,lstart=,args="],
        env,
        b,
        deadline,
        clock,
        lambda out: _parse_procs(out) or None,
        tries,
    )
    ttys, n2 = _ps_read(
        run,
        ["/bin/ps", "-axo", "pid=,tty="],
        env,
        b,
        deadline,
        clock,
        lambda out: _parse_ttys(out) if out.strip() else None,
        tries,
    )
    if stats is not None:
        stats["attempts"] = max(n1, n2)
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
    run: RunFn = run_bounded,
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
_CHROME = frozenset(
    "\u276f"
)  # ❯; the U+00A0 after it is not printable, so isprintable() drops it
GLYPH = "\u276f"


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


def _slash_command(row: str) -> str:
    """The "/cmd" of a "❯ /cmd …" row (leading spaces, then spaces or U+00A0 after the glyph), else ""."""
    t = row.lstrip(" ")
    if not t.startswith(GLYPH):
        return ""
    t = t[len(GLYPH) :].lstrip(" \u00a0")
    if not t.startswith("/"):
        return ""
    return re.split(r"[ \t\r]", t, maxsplit=1)[0]


def _dialog_over_box(plain: List[str], top: int, bottom: int) -> bool:
    """True when a dialog owns the keys although a composer box is still drawn.

    Claude Code 2.1.260 draws its background-work dialog ABOVE a composer that stays visible; read
    as "the rows between the last two borders" that screen is an empty box, and the idle fan-out
    would then type at a dialog whose `1` is "Exit and stop tasks" (slot-reader-sweep.md, two real
    captures). The rule is handoff-fire.sh composer_content's, and tests/composer-parser-parity.bats
    runs both over one corpus:
      * a ❯ under the bottom border: a dialog draws its selector with it, a footer never does;
      * a top border that does not start at column 0: a box printed in output, a teammate panel;
      * a ❯ at indent 1-4 above the box: a dialog option row. The slash-command menu is exempt
        only when its highlighted row names the command the box itself holds, because with the
        menu open a CR submits the highlight, not the box.
    """
    if any(GLYPH in ln for ln in plain[bottom + 1 :]):
        return True
    if not plain[top].startswith("─"):
        return True
    first = plain[top + 1]
    held = _slash_command(first) if first.startswith(GLYPH) else ""
    for ln in plain[:top]:
        body = ln.lstrip(" ")
        if 1 <= len(ln) - len(body) <= 4 and body.startswith(GLYPH):
            if not (held and _slash_command(ln) == held):
                return True
    return False


def composer_from_screen(screen: str) -> str:
    """ "empty" | "draft" | "unknown" from a --ansi screen: the rows strictly between the last two
    border rows, faint runs dropped; a whole-row `Try "…"` is the placeholder. A box with a dialog
    drawn over it is "unknown" (_dialog_over_box).

    Only the known chrome is stripped — the prompt glyph ❯, and the U+00A0 after it, which is not
    printable — and every other printable non-space character is content (D6.8). Keeping printable ASCII only read a
    draft written wholly in non-ASCII as EMPTY, and /exit could then merge into it."""
    lines = screen.splitlines()
    plain = [_ESC.sub("", ln) for ln in lines]
    borders = [i for i, ln in enumerate(plain) if BORDER in ln]
    if len(borders) < 2 or borders[-1] - borders[-2] < 2:
        return "unknown"
    top, bottom = borders[-2], borders[-1]
    if _dialog_over_box(plain, top, bottom):
        return "unknown"
    rows = []
    for ln in lines[top + 1 : bottom]:
        txt = "".join(
            ch for ch in _unfaint(ln) if ch not in _CHROME and ch.isprintable()
        )
        if not _PLACEHOLDER.match(txt):
            rows.append(txt)
    return "draft" if "".join("".join(rows).split()) else "empty"


def composer_state(
    sock: str,
    window_id: int,
    run: RunFn = run_bounded,
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


# ── W14 (B5-R): kitty-free pane binding ──────────────────────────────────────────────────────────
# A record born while its kitty's `kitten @ ls` fails had no pane: no window roots ⇒ bind() None ⇒
# PRE-MOVE/None with nothing dispatched, for the whole outage (C2 efficacy E1). The kernel already
# knows the pane: kitty puts KITTY_WINDOW_ID and KITTY_PID in every window's env, and the ppid chain
# reaches that kitty. These are W12's kernel pane identity rules (handoff-fire.sh hf_kid_probe), read
# from the pass's one ps table plus ONE `ps -E` call for the claude pids. Only a kitty whose ls failed
# is bound this way, only in mode on, and only above the background band (W12's hf_kitty_band): a
# background-banded or unreadable kitty main thread holds as today, retried the next pass.

PANE_BIND_ENV_MODE = (
    "pane-bind-env.mode"  # under LR_RECON_ROOT; `printf off >` is the kill switch
)
PANE_BIND_ENV_LOG = "pane-bind-env.jsonl"  # under recon/shadow
PANE_BIND_ENV_LOG_MAX = 4 << 20
PANE_BIND_ENV_PIDS_MAX = 256
# With every kitty answering, the shadow comparison against ls runs at most this often: the rows are
# the on-flip's evidence (≥ 30 rows, 0 agree=no), not something a pass needs.
PANE_BIND_ENV_HEALTHY_EVERY_S = 120.0
PS_ENV_BOUND_S = 20.0
KITTY_BAND_SAMPLES = 3
KITTY_BAND_BG_MAX = 4  # PRI ≤ 4: Darwin's background band (App Nap, screen lock)
_ENV_KEYS = ("KITTY_WINDOW_ID", "KITTY_PID", "KITTY_LISTEN_ON")
_SOCK_RE = re.compile(r"^unix:/[A-Za-z0-9_./-]+$")
_HEALTHY_AT = [float("-inf")]  # monotonic time of the last healthy-kitty shadow sample


def pane_bind_env_mode(paths: Optional[T.Paths]) -> str:
    """recon/pane-bind-env.mode, re-read every pass: off | shadow | on. Absent or unrecognised ⇒ the
    code default ``shadow`` (log, bind nothing); no paths (a tool or test census) ⇒ off."""
    if paths is None:
        return "off"
    try:
        with open(paths.p(PANE_BIND_ENV_MODE), "rb") as fh:
            raw = fh.read(16)
    except OSError:
        return "shadow"
    v = "".join(c for c in raw.decode("ascii", "replace") if "a" <= c <= "z")
    return v if v in T.PANE_BIND_ENV_MODES else "shadow"


def parse_ps_env(out: str) -> Dict[int, Dict[str, str]]:
    """pid → its LAST KITTY_* tokens, from `ps -E -o pid=,command=`. The owed prompt rides claude's
    argv, before the env block, so the last match is the env's (lr-lib.sh lr_pid_env). A line with no
    HOME=/PATH= token has no readable env block and is left out: unknown, never "no kitty"."""
    res: Dict[int, Dict[str, str]] = {}
    for line in out.splitlines():
        toks = line.split()
        if len(toks) < 2 or not toks[0].isdigit():
            continue
        if not any(t.startswith(("HOME=", "PATH=")) for t in toks[1:]):
            continue
        env: Dict[str, str] = {}
        for t in toks[1:]:
            k, sep, v = t.partition("=")
            if sep and k in _ENV_KEYS:
                env[k] = v
        res[int(toks[0])] = env
    return res


def read_ps_env(
    run: RunFn, pids: List[int], bound: float = PS_ENV_BOUND_S
) -> Dict[int, Dict[str, str]]:
    """One bounded `ps -E` for ``pids``. ps exits 1 when one of them died since the table was read and
    still prints the rest, so any output counts; none raises (the binding then decides nothing)."""
    argv = ["/bin/ps", "-E", "-ww", "-o", "pid=,command=", "-p"]
    res = run(
        argv + [",".join(str(p) for p in pids)],
        capture_output=True,
        text=True,
        timeout=bound,
        env=_ps_env(),
    )
    out = str(res.stdout or "")
    if not out.strip():
        raise RuntimeError("ps -E exited %s with no rows" % res.returncode)
    return parse_ps_env(out)


def kitty_of(pid: int, procs: Dict[int, T.ProcRow]) -> int:
    """The nearest live kitty ancestor of ``pid``, or 0."""
    for a in ancestors(pid, procs):
        row = live(a, procs)
        if row is not None and argv0(row.args) == "kitty":
            return a
    return 0


def env_pane(
    pid: int,
    env: Dict[str, str],
    procs: Dict[int, T.ProcRow],
    ttys: Dict[int, str],
) -> Tuple[Optional[Tuple[int, int]], int, str]:
    """(pane, window root pid, why-not) by W12's rules, each a refusal when it fails:
    (1) the pid is alive and not a zombie; (2) its env names KITTY_WINDOW_ID=W and KITTY_PID=K;
    (3) K is on its ppid chain, and the process directly under K — the window root — is alive, not a
    zombie, with a controlling tty; (4) K is alive, not a zombie, and its argv0 is kitty."""
    if live(pid, procs) is None:
        return None, 0, "pid gone or zombie"
    wid, kp = env.get("KITTY_WINDOW_ID", ""), env.get("KITTY_PID", "")
    if not wid.isdigit() or not kp.isdigit():
        return None, 0, "no KITTY_WINDOW_ID/KITTY_PID in env"
    k = int(kp)
    krow = live(k, procs)
    if krow is None or argv0(krow.args) != "kitty":
        return None, 0, "env KITTY_PID %d is not a live kitty" % k
    chain = [pid] + list(ancestors(pid, procs))
    if k not in chain[1:]:
        return None, 0, "env KITTY_PID %d is not an ancestor" % k
    root = chain[chain.index(k) - 1]
    rrow = procs.get(root)
    if rrow is None or rrow.zombie:
        return None, 0, "window root %d gone or zombie" % root
    if not ttys.get(root):
        return None, 0, "window root %d has no tty" % root
    return (k, int(wid)), root, ""


def kitty_band(
    kpid: int, run: RunFn = run_bounded, samples: int = KITTY_BAND_SAMPLES
) -> Tuple[int, str]:
    """W12's hf_kitty_band: ``samples`` bounded `ps -M` reads of kitty's main thread, majority
    decides. (0 above the band | 1 background-banded | 2 unreadable, no proof; the samples read)."""
    low = high = 0
    read: List[str] = []
    for _ in range(samples):
        step()
        p = ""
        try:
            out = _run_ok(run, ["/bin/ps", "-M", "-p", str(kpid)], 5.0, _ps_env())
            lines = out.splitlines()
            f = lines[1].split() if len(lines) > 1 else []
            p = re.match(r"\d*", f[5]).group(0) if len(f) > 5 else ""  # type: ignore[union-attr]
        except Exception:  # noqa: BLE001 — an unread sample is a "?", never a band
            p = ""
        read.append(p or "?")
        if p:
            if int(p) <= KITTY_BAND_BG_MAX:
                low += 1
            else:
                high += 1
    if low + high < 2:
        return 2, " ".join(read)
    return (0 if low < high else 1), " ".join(read)


def _capped(under: Dict[int, int], failed: Dict[int, str]) -> List[int]:
    """At most PANE_BIND_ENV_PIDS_MAX pids; the cap drops healthy-kitty comparisons first, since a
    deaf kitty's claudes are what the binding is for."""
    return sorted(under, key=lambda p: (under[p] not in failed, p))[
        :PANE_BIND_ENV_PIDS_MAX
    ]


def env_rows(
    snap: T.Snapshot,
    ttys: Dict[int, str],
    roots: Dict[int, Tuple[int, int]],
    failed: Dict[int, str],
    mode: str,
    run: RunFn = run_bounded,
    clock: Callable[[], float] = time.monotonic,
) -> Dict[int, Tuple[int, int]]:
    """Judge every claude under a kitty whose ls failed (``failed``: kitty pid → its socket), plus, at
    most every PANE_BIND_ENV_HEALTHY_EVERY_S, every claude under a kitty that answered (the shadow
    comparison against ls). Appends one row per claude to ``snap.pane_bind_env`` and returns the
    env roots ``bind`` may use: empty unless mode is on. In mode on it also adds a PaneObs
    (pane_src "env", state "unknown": nothing read its foreground) for each pane it binds."""
    if mode not in ("shadow", "on"):
        return {}
    snap.pane_bind_env_mode = mode
    procs = snap.procs
    healthy = clock() - _HEALTHY_AT[0] >= PANE_BIND_ENV_HEALTHY_EVERY_S
    under: Dict[int, int] = {}
    for r in procs.values():
        if r.zombie or not is_claude(r.args):
            continue
        k = kitty_of(r.pid, procs)
        if k and (k in failed or healthy):
            under[r.pid] = k
    if not under:
        return {}
    if healthy and any(k not in failed for k in under.values()):
        _HEALTHY_AT[0] = clock()
    pids = _capped(under, failed)
    step()
    try:
        envs = read_ps_env(run, pids)
    except Exception as e:  # noqa: BLE001 — no env read: nothing is bound, and the pass says why
        snap.degraded_why["pane-bind-env"] = str(e)[:200] or type(e).__name__
        return {}
    out: Dict[int, Tuple[int, int]] = {}
    bands: Dict[int, Tuple[int, str]] = {}
    for pid in pids:
        k = under[pid]
        row = procs[pid]
        key, root, why = (
            env_pane(pid, envs[pid], procs, ttys)
            if pid in envs
            else (None, 0, "env block unreadable")
        )
        ls_key = bind(pid, procs, roots)
        agree, band, held, bound = "-", "", "", False
        if k not in failed:
            if key is not None:
                agree = "yes" if key == ls_key else "no"
            elif ls_key is not None:
                agree = "miss"
        elif key is not None and key[0] in failed:
            if key[0] not in bands:
                bands[key[0]] = kitty_band(key[0], run)
            brc, band = bands[key[0]]
            if brc == 1:
                held = "banded"
                why = "kitty background-banded: its main thread would not drain output (B8)"
            elif brc == 2:
                held = "band-unreadable"
                why = "kitty main-thread band unreadable, so the binding has no proof"
            elif mode == "on":
                out[pid] = key
                bound = True
                _env_pane_obs(snap, key, root, ttys, failed[key[0]], envs[pid])
        elif key is not None:
            why = "env kitty %d answered ls; the nearest kitty %d did not" % (key[0], k)
        snap.pane_bind_env.append(
            {
                "t": snap.wall,
                "mode": mode,
                "pid": pid,
                "lstart": row.lstart,
                "kitty_pid": k,
                "ls_ok": k not in failed,
                "env": "%d:%d" % key if key else "-",
                "ls": "%d:%d" % ls_key if ls_key else "-",
                "root": root,
                "agree": agree,
                "band": band,
                "held": held,
                "bound": bound,
                "why": why,
            }
        )
    return out


def _env_pane_obs(
    snap: T.Snapshot,
    key: Tuple[int, int],
    root: int,
    ttys: Dict[int, str],
    sock: str,
    env: Dict[str, str],
) -> None:
    sk = "%d:%d" % key
    if sk in snap.panes:
        return
    procs = snap.procs
    if not sock:
        lo = env.get("KITTY_LISTEN_ON", "")
        sock = lo if _SOCK_RE.match(lo) else "unix:/tmp/kitty-%d" % key[0]
    rrow = procs[root]
    snap.panes[sk] = T.PaneObs(
        kitty_pid=key[0],
        window_id=key[1],
        sock=sock,
        kitty_lstart=procs[key[0]].lstart,
        tty=ttys.get(root, ""),
        root_pid=root,
        root_lstart=rrow.lstart,
        root_shape="shell" if argv0(rrow.args) in SHELLS else "launcher",
        state="unknown",
        pane_src="env",
    )


def env_counts(snap: T.Snapshot) -> str:
    """The kitty-degraded event's counts: of the claudes under a deaf kitty, how many the kernel
    bound (or would, in shadow), how many it refused, and how many a low kitty band held."""
    if not snap.pane_bind_env_mode:
        return "pane-bind-env off"
    deaf = [r for r in snap.pane_bind_env if not r.get("ls_ok")]
    proven = sum(1 for r in deaf if r.get("env") != "-")
    held = sum(1 for r in deaf if r.get("held"))
    bound = sum(1 for r in deaf if r.get("bound"))
    return (
        "pane-bind-env %s: %d of %d claude(s) under a deaf kitty bound by env (%d kernel-proven, %d held by the kitty band)"
        % (
            snap.pane_bind_env_mode,
            bound,
            len(deaf),
            proven,
            held,
        )
    )


def _log_env_rows(paths: Optional[T.Paths], snap: T.Snapshot) -> None:
    if paths is None or not snap.pane_bind_env:
        return
    try:
        os.makedirs(paths.shadow, exist_ok=True)
        path = os.path.join(paths.shadow, PANE_BIND_ENV_LOG)
        for r in snap.pane_bind_env:
            store.append_bounded(path, store.dumps(r), PANE_BIND_ENV_LOG_MAX)
    except OSError:
        pass  # a log we could not write changes no decision


# ── C3.4-5, 7: sessions ──────────────────────────────────────────────────────────────────────────


def _uptime_raw() -> float:
    clk = getattr(time, "CLOCK_MONOTONIC_RAW", None)
    return time.clock_gettime(clk) if clk is not None else time.monotonic()


def observe(
    paths: Optional[T.Paths],
    home: str,
    run: RunFn = run_bounded,
    glob_fn: GlobFn = glob.glob,
    transcript_fn: Optional[TranscriptFn] = None,
    now: Optional[float] = None,
    lstat_fn: Callable[[str], os.stat_result] = os.lstat,
    kitten: Optional[str] = None,
    registry_dir: Optional[str] = None,
    rig: Optional[bool] = None,
    rig_keep: FrozenSet[str] = frozenset(),
    pane_bind_env: Optional[str] = None,
) -> T.Snapshot:
    """One census pass. Never raises: every instrument is fenced and degrades by name.
    ``pane_bind_env`` overrides recon/pane-bind-env.mode (W14; tests and one-shot reads)."""
    snap = T.Snapshot(
        wall=time.time() if now is None else now, uptime_raw=_uptime_raw()
    )
    stats: Dict[str, int] = {}
    try:
        snap.procs, ttys = read_ps(run, stats=stats)
        snap.ttys = sorted(set(ttys.values()))
        snap.ps_attempts = stats.get("attempts", 0)
    except Exception as e:  # noqa: BLE001
        snap.degraded.append("ps")
        snap.degraded_why["ps"] = str(e)[:200] or type(e).__name__
        return snap
    step()  # each unit below is bounded (ps: PS_BUDGET_S; kitty: 5 s per socket)
    procs = snap.procs
    try:
        snap.sockets = kitty_sockets(procs, glob_fn, lstat_fn)
    except Exception:  # noqa: BLE001
        snap.degraded.append("kitty-sockets")
    roots: Dict[int, Tuple[int, int]] = {}
    failed: Dict[int, str] = {}  # kitty pid → the socket whose ls failed (W14)
    for sock in snap.sockets:
        step()
        kpid = int(sock.rsplit("-", 1)[-1])
        data = kitty_ls(sock, run, kitten=kitten, degraded=snap.degraded)
        if data is None:
            failed[kpid] = sock
            continue
        try:
            for p in panes_from_ls(sock, kpid, data, procs, ttys):
                snap.panes["%d:%d" % p.key] = p
                if p.root_pid:
                    roots[p.root_pid] = p.key
        except Exception:  # noqa: BLE001
            snap.degraded.append("kitty:" + sock)
            failed[kpid] = sock
    env_roots: Dict[int, Tuple[int, int]] = {}
    try:
        env_roots = env_rows(
            snap,
            ttys,
            roots,
            failed,
            pane_bind_env_mode(paths) if pane_bind_env is None else pane_bind_env,
            run,
        )
    except Exception as e:  # noqa: BLE001 — the kernel binding is advisory: it never costs a pass
        snap.degraded_why["pane-bind-env"] = str(e)[:200] or type(e).__name__
    _log_env_rows(paths, snap)
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
            env_roots,
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
    env_roots: Optional[Dict[int, Tuple[int, int]]] = None,
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
        step()
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
        # a registry row outlives its session by CC_REG_RETAIN_H, so its pid alone is not identity:
        # one whose lstart names another instant is a reused pid and holds nothing (live_as)
        live_reg = [
            r
            for r in rrows
            if live_as(r.get("pid"), r.get("lstart"), procs) is not None
        ]
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
                r["pid"],
                "",
            )
            for r in live_reg
        ]
        sources += [("resume-argv", "", p, "") for p in leaves.get(sid, [])]
        holders = holders_for(sources, procs, roots, env_roots)
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


def claude_count(snap: T.Snapshot) -> int:
    """Live, non-zombie claude processes in the ps read."""
    return sum(1 for r in snap.procs.values() if not r.zombie and is_claude(r.args))


# W7a: a census the pass may not decide on. A drop from at least COLLAPSE_FLOOR claude processes to
# under 1/COLLAPSE_RATIO of that in one pass is implausible; the next pass compares against this
# pass's reading, so a real mass exit costs one abstained pass and a stalled ps is never believed.
COLLAPSE_FLOOR = 8
COLLAPSE_RATIO = 4


def untrusted(snap: T.Snapshot, prev: Optional[int]) -> str:
    """Why this census may decide nothing, or "" when it may. Three cases: ps degraded (the census
    is empty, not the world); ps sees fewer than half as many claude processes as kitty shows panes
    whose foreground is claude (kitty is a second, independent witness: every such pane holds at
    least one); or the count collapsed against ``prev``, the previous pass's ps reading."""
    if "ps" in snap.degraded:
        return "ps degraded: " + snap.degraded_why.get("ps", "no reason recorded")
    n = claude_count(snap)
    panes = sum(1 for p in snap.panes.values() if p.state == "claude")
    if n * 2 < panes:
        return "ps read %d claude procs while kitty shows claude in %d panes" % (
            n,
            panes,
        )
    if prev is not None and prev >= COLLAPSE_FLOOR and n * COLLAPSE_RATIO < prev:
        return "claude procs fell from %d to %d in one pass" % (prev, n)
    return ""


def census_line(snapshot: T.Snapshot) -> str:
    """One human line for the `--mode observe --once` proof."""
    nclaude = claude_count(snapshot)
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
        # W7a: a pass its ps retry saved says so, so the shadow shows how close the census came
        + (
            " · ps took %d tries" % snapshot.ps_attempts
            if snapshot.ps_attempts > 1
            else ""
        )
    )
