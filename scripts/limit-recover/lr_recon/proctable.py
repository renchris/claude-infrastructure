"""The ps-free census: the process table without forking /bin/ps (REPORT §4.6, notes/S07 §6).

``/bin/ps`` is setuid root and walks every task's memory map and threads (about 2,200 processes and
6,600 threads here), so at load 650-770 every call timed out at 42 s and the census went blind for
15 passes (2026-10-24 22:43-22:56 CDT); multi-pid ``ps -o pid=,lstart= -p <list>`` reads wedged for
37-77 min on 2026-10-25 (57730d18c, 19c297766). This module reads the same six fields in process:

- pid, ppid, the zombie bit, lstart and the tty device from ONE ``sysctl KERN_PROC_ALL`` (3.3 ms for
  2,167 rows at load 624). It takes no task port, reads no target memory and has no same-uid check,
  so the root-owned ``login`` pane roots that ``proc_pidinfo`` refuses keep their lstart and tty.
- the tty name from a ``/dev`` ``st_rdev`` map (0.7 ms), rescanned when an unknown device appears.
- args from ``KERN_PROCARGS2``, the one call that copies from the target's VM and so shares ps's
  stall path: it runs on a bounded worker thread (``ArgsReader``), claude-family rows first, with a
  per-call deadline and a per-pass budget. A worker stuck in the kernel cannot be killed, so it is
  abandoned; at STUCK_MAX live stuck workers no new one starts.

Rendering follows ps (``getproclline``): argv joined by spaces, leading spaces stripped, then libc
``strvis(VIS_TAB|VIS_NL|VIS_NOSLASH)`` in the C locale, so a newline inside an owed prompt stays glued
to its token exactly as ``args.split()`` sees it under ps. A zombie renders ``<defunct>`` and an
unreadable row ``(comm)``, as ps does.

Fail-closed rule: an unread argv on a claude-family row, a kitty, a shell under kitty or a child of
claude is never trusted as ``(comm)``; ``read_table`` names those pids in ``info["critical_unread"]``
and the caller degrades. Env blocks can carry credentials: only the keys asked for are extracted and
nothing of argv or env is ever logged — the shadow log holds counts, pids and token-list hashes.

Modes (``mode``): ``recon/ps-free.off`` present ⇒ off (read every pass, no restart); else env
``LR_RECON_PSFREE`` in off|shadow|on; unset or unknown ⇒ off (today's ps path). Shadow keeps ps as
the decider and logs per-pass parity to ``recon/shadow/ps-free.jsonl``.
"""

from __future__ import annotations

import ctypes
import hashlib
import json
import os
import queue
import struct
import sys
import threading
import time
from typing import (
    Any,
    Callable,
    Dict,
    Iterable,
    List,
    Mapping,
    NamedTuple,
    Optional,
    Tuple,
)

from lr_recon import store
from lr_recon import types as T

MODES = ("off", "shadow", "on")
MODE_ENV = "LR_RECON_PSFREE"
OFF_FILE = "ps-free.off"  # under recon/
MODE_FILE = "ps-free.mode"  # under recon/: off | shadow | on, below the env value
SHADOW_LOG = "ps-free.jsonl"  # under recon/shadow/
SHADOW_LOG_MAX_BYTES = 8 * 1024 * 1024  # then rotated once to .1

# sysctl MIBs and struct kinfo_proc offsets (Darwin 24.6.0, clang offsetof; S07 §2).
CTL_KERN, KERN_PROC, KERN_PROC_ALL, KERN_PROC_PID, KERN_PROCARGS2 = 1, 14, 0, 1, 49
KINFO_SIZE = 648
_OFF_SEC, _OFF_STAT, _OFF_PID, _OFF_COMM = 0, 36, 40, 243
_OFF_UID, _OFF_PPID, _OFF_TDEV = 420, 560, 572
_COMM_LEN = 17  # MAXCOMLEN + 1
SZOMB, SSTOP = 5, 4
NODEV = -1
ARGMAX_DEFAULT = 1024 * 1024
ENOMEM = 12

ARGS_CALL_S = (
    0.5  # per KERN_PROCARGS2 call: measured max 127.8 ms at load 621, ×4 headroom
)
ARGS_BUDGET_S = 3.0  # per pass: all same-uid rows measured 0.40-0.63 s
STUCK_MAX = 2  # live abandoned workers at which no new reader starts (ORPHAN_RETRY_SKIP_AT's rule)
SLOW_CALL_S = 0.1  # a call this slow is named (pid, comm, ms) in the shadow row
PID_LIST_MAX = 20  # pids named per mismatch field in one shadow row

CLAUDE_COMMS = ("claude", "claude.exe")
SHELL_COMMS = ("zsh", "bash", "fish", "sh", "-zsh", "-bash", "-fish", "-sh")
HOST_COMMS = ("bash", "python3", "Python", "expect", "kitty")


class KRow(NamedTuple):
    """One ``kinfo_proc`` row, the fields the census reads."""

    pid: int
    ppid: int
    p_stat: int
    sec: int
    usec: int
    tdev: int
    uid: int
    comm: str


# ── mode ─────────────────────────────────────────────────────────────────────────────────────────


def mode(
    paths: Optional[T.Paths] = None, env: Optional[Mapping[str, str]] = None
) -> str:
    """off | shadow | on, re-read on every call. ``recon/ps-free.off`` wins; then a valid env
    value; then ``recon/ps-free.mode`` (one word, so an operator turns shadow on with one write and
    no plist edit or daemon restart); anything else is off, so the default is today's ps path."""
    e: Mapping[str, str] = os.environ if env is None else env
    p: Optional[T.Paths] = None
    try:
        p = paths if paths is not None else T.Paths.from_env(env=dict(e))
        if os.path.exists(p.p(OFF_FILE)):
            return "off"
    except Exception:  # noqa: BLE001 — an unresolvable tree has no off file to read
        p = None
    v = (e.get(MODE_ENV) or "").strip().lower()
    if v in MODES:
        return v
    if p is not None:
        try:
            with open(p.p(MODE_FILE), "rb") as fh:
                raw = fh.read(16)
        except OSError:
            return "off"
        w = "".join(c for c in raw.decode("ascii", "replace") if "a" <= c <= "z")
        if w in MODES:
            return w
    return "off"


# ── libc seams ───────────────────────────────────────────────────────────────────────────────────

_LIBC: List[Any] = []


def _libc() -> Any:
    if not _LIBC:
        try:
            _LIBC.append(ctypes.CDLL(None, use_errno=True))
        except OSError:
            _LIBC.append(None)
    return _LIBC[0]


def _sysctl(mib: List[int], size: int) -> bytes:
    """One ``sysctl(mib)`` into a ``size``-byte buffer; raises OSError with the errno."""
    lib = _libc()
    if lib is None or sys.platform != "darwin":
        raise OSError(0, "no darwin sysctl here")
    m = (ctypes.c_int * len(mib))(*mib)
    buf = ctypes.create_string_buffer(max(1, size))
    sz = ctypes.c_size_t(size)
    if lib.sysctl(m, len(mib), buf, ctypes.byref(sz), None, ctypes.c_size_t(0)) != 0:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err))
    return buf.raw[: sz.value]


def _sysctl_size(mib: List[int]) -> int:
    lib = _libc()
    if lib is None or sys.platform != "darwin":
        raise OSError(0, "no darwin sysctl here")
    m = (ctypes.c_int * len(mib))(*mib)
    sz = ctypes.c_size_t(0)
    if lib.sysctl(m, len(mib), None, ctypes.byref(sz), None, ctypes.c_size_t(0)) != 0:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err))
    return int(sz.value)


def parse_kinfo(raw: bytes) -> Dict[int, KRow]:
    """Rows from a KERN_PROC_ALL / KERN_PROC_PID buffer; a trailing partial row is ignored."""
    out: Dict[int, KRow] = {}
    for off in range(0, len(raw) - KINFO_SIZE + 1, KINFO_SIZE):
        (pid,) = struct.unpack_from("<i", raw, off + _OFF_PID)
        sec, usec = struct.unpack_from("<qi", raw, off + _OFF_SEC)
        (ppid,) = struct.unpack_from("<i", raw, off + _OFF_PPID)
        (tdev,) = struct.unpack_from("<i", raw, off + _OFF_TDEV)
        (uid,) = struct.unpack_from("<I", raw, off + _OFF_UID)
        comm = raw[off + _OFF_COMM : off + _OFF_COMM + _COMM_LEN].split(b"\0", 1)[0]
        out[pid] = KRow(
            pid, ppid, raw[off + _OFF_STAT], sec, usec, tdev, uid,
            comm.decode("utf-8", "replace"),
        )  # fmt: skip
    return out


def kern_proc_all(tries: int = 3) -> Dict[int, KRow]:
    """The whole table in one sysctl: size probe, ×1.25 + 64 rows of slack, 3 tries on ENOMEM
    (the table grew between probe and read). Raises when every try fails."""
    mib = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
    last: Optional[OSError] = None
    for _ in range(max(1, tries)):
        try:
            size = int(_sysctl_size(mib) * 1.25) + 64 * KINFO_SIZE
            return parse_kinfo(_sysctl(mib, size))
        except OSError as e:
            last = e
            if e.errno != ENOMEM:
                break
    raise OSError(last.errno if last else 0, "KERN_PROC_ALL: %s" % (last or "failed"))


def kern_proc_pid(pid: int) -> Optional[KRow]:
    """One row by pid (no uid check). None = no such process; raises OSError on a failed read."""
    if pid <= 0:
        return None
    rows = parse_kinfo(
        _sysctl([CTL_KERN, KERN_PROC, KERN_PROC_PID, int(pid)], KINFO_SIZE)
    )
    return rows.get(int(pid))


def stat_letter(p_stat: int) -> str:
    """The one ``stat`` letter the census reads: Z for a zombie (all ``ProcRow.zombie`` checks);
    T for stopped; else S. ps's other letters come from Mach thread states nothing consumes."""
    return "Z" if p_stat == SZOMB else "T" if p_stat == SSTOP else "S"


def proc_lstart(pid: int) -> Optional[str]:
    """ps LSTART (UTC, C names, spaces collapsed) for one pid via KERN_PROC_PID, root rows included.
    "" = no such process; None = not readable (no sysctl here, or the call failed): ask ps."""
    try:
        row = kern_proc_pid(pid)
    except OSError:
        return None
    if row is None:
        return ""
    return store.lstart_text(row.sec) if row.sec > 0 else None


def proc_stat(pid: int) -> Optional[str]:
    """The stat letter for one pid. "" = no such process; None = not readable."""
    try:
        row = kern_proc_pid(pid)
    except OSError:
        return None
    return "" if row is None else stat_letter(row.p_stat)


# ── tty names ────────────────────────────────────────────────────────────────────────────────────

_TTY_CACHE: Dict[int, str] = {}


def _scan_dev(scandir: Callable[[str], Iterable[Any]] = os.scandir) -> Dict[int, str]:
    out: Dict[int, str] = {}
    for ent in scandir("/dev"):
        name = ent.name
        if not (name.startswith("tty") or name == "console"):
            continue
        try:
            st = ent.stat(follow_symlinks=False)
        except OSError:
            continue
        out[st.st_rdev & 0xFFFFFFFF] = name
    return out


def tty_map(
    tdevs: Iterable[int], scandir: Callable[[str], Iterable[Any]] = os.scandir
) -> Dict[int, str]:
    """tdev → tty name for every tdev asked for. The /dev scan is cached and redone once when a
    device is unknown (a new pty); NODEV and a device still unknown map to nothing (ps's ``??``)."""
    want = {t & 0xFFFFFFFF for t in tdevs if t != NODEV}
    if not _TTY_CACHE or any(t not in _TTY_CACHE for t in want):
        _TTY_CACHE.clear()
        _TTY_CACHE.update(_scan_dev(scandir))
    return {t: _TTY_CACHE[t] for t in want if t in _TTY_CACHE}


# ── args ─────────────────────────────────────────────────────────────────────────────────────────

Parsed = Tuple[List[bytes], Dict[str, str]]  # argv, and ONLY the env keys asked for
Reader = Callable[[int, Tuple[str, ...]], Optional[Parsed]]


def parse_procargs2(raw: bytes, keys: Tuple[str, ...] = ()) -> Optional[Parsed]:
    """``KERN_PROCARGS2``: int argc, the exec path, NUL padding, argc strings, then the env block.
    Only env entries whose key is in ``keys`` are kept; the rest is dropped unread."""
    if len(raw) < 4:
        return None
    (argc,) = struct.unpack_from("<i", raw, 0)
    i = raw.find(b"\0", 4)
    if i < 0 or argc < 0:
        return None
    n = len(raw)
    while i < n and raw[i] == 0:
        i += 1
    argv: List[bytes] = []
    while len(argv) < argc and i < n:
        j = raw.find(b"\0", i)
        j = n if j < 0 else j
        argv.append(raw[i:j])
        i = j + 1
    env: Dict[str, str] = {}
    if keys:
        while i < n:
            j = raw.find(b"\0", i)
            j = n if j < 0 else j
            if j == i:
                break
            k, sep, v = raw[i:j].partition(b"=")
            ks = k.decode("utf-8", "replace")
            if sep and ks in keys:
                env[ks] = v.decode("utf-8", "replace")
            i = j + 1
    return argv, env


_ARGMAX: List[int] = []


def procargs2(pid: int, keys: Tuple[str, ...] = ()) -> Optional[Parsed]:
    """argv (and the asked-for env keys) of ``pid``; None when unreadable (other uid ⇒ EINVAL,
    gone, a kernel refusal). This call copies from the target's VM: run it off the loop thread."""
    if not _ARGMAX:
        try:
            _ARGMAX.append(
                struct.unpack("<i", _sysctl([CTL_KERN, 8], 4))[0]
            )  # KERN_ARGMAX
        except (OSError, struct.error):
            _ARGMAX.append(ARGMAX_DEFAULT)
    try:
        raw = _sysctl([CTL_KERN, KERN_PROCARGS2, int(pid)], _ARGMAX[0])
    except OSError:
        return None
    return parse_procargs2(raw, keys)


VIS_TAB, VIS_NL, VIS_NOSLASH = 0x08, 0x10, 0x40
_VIS_FLAGS = VIS_TAB | VIS_NL | VIS_NOSLASH
_C_LOCALE: List[Any] = []  # [locale_t of "C" or None], made once


def _c_locale() -> Any:
    """A ``newlocale(LC_ALL_MASK, "C")`` handle, or None where libc has none."""
    if not _C_LOCALE:
        loc = None
        lib = _libc()
        try:
            if lib is not None and sys.platform == "darwin":
                lib.newlocale.restype = ctypes.c_void_p
                lib.newlocale.argtypes = [
                    ctypes.c_int,
                    ctypes.c_char_p,
                    ctypes.c_void_p,
                ]
                lib.uselocale.restype = ctypes.c_void_p
                lib.uselocale.argtypes = [ctypes.c_void_p]
                loc = lib.newlocale(63, b"C", None) or None  # LC_ALL_MASK
        except (AttributeError, OSError):
            loc = None
        _C_LOCALE.append(loc)
    return _C_LOCALE[0]


def _strvis_py(b: bytes) -> str:
    """Fallback when libc strvis is unusable: every non-graphic byte except space as ``\\ooo``."""
    return "".join(chr(c) if 0x20 <= c < 0x7F else "\\%03o" % c for c in b)


def strvis(b: bytes) -> str:
    """libc ``strvis(VIS_TAB|VIS_NL|VIS_NOSLASH)`` in the C locale (ps print.c's encoding, under
    observe._ps_env's LC_ALL=C). The C locale is set with ``uselocale`` for this call only and the
    thread's previous locale restored after it: leaving the caller (the daemon's main thread) in C
    would turn its codeset to ASCII and break every text read and write that follows."""
    lib, loc = _libc(), _c_locale()
    if lib is None or loc is None:
        return _strvis_py(b)
    dst = ctypes.create_string_buffer(4 * len(b) + 1)
    old = lib.uselocale(loc)
    try:
        lib.strvis(dst, b, ctypes.c_int(_VIS_FLAGS))
    except (AttributeError, OSError):
        return _strvis_py(b)
    finally:
        lib.uselocale(old)
    return dst.value.decode("ascii", "replace")


def render_args(argv: Optional[List[bytes]], comm: str, zombie: bool) -> str:
    """The ``args`` column as ps prints it: ``<defunct>`` for a zombie, ``(comm)`` when argv is
    unreadable, else argv joined by spaces, leading spaces stripped, strvis-encoded."""
    if zombie:
        return "<defunct>"
    if not argv:
        return "(%s)" % comm
    # observe._parse_procs strips the ps column (``t[8].strip()``): the census compares that form
    return strvis(b" ".join(argv).lstrip(b" ")).strip()


class _Slot:
    __slots__ = ("pid", "done", "result", "ms")

    def __init__(self, pid: int) -> None:
        self.pid = pid
        self.done = threading.Event()
        self.result: Optional[Parsed] = None
        self.ms = 0.0


class _Worker(threading.Thread):
    """One daemon thread serving KERN_PROCARGS2 reads from a queue. Abandoned once a call outlives
    its deadline; it exits when (if) that call returns."""

    def __init__(self, reader: Reader, keys: Tuple[str, ...]) -> None:
        super().__init__(name="lr-proctable-args", daemon=True)
        self.q: "queue.Queue[Optional[_Slot]]" = queue.Queue()
        self.reader, self.keys = reader, keys
        self.abandoned = False

    def run(self) -> None:
        while True:
            slot = self.q.get()
            if slot is None:
                return
            t0 = time.monotonic()
            try:
                slot.result = self.reader(slot.pid, self.keys)
            except Exception:  # noqa: BLE001 — an unread row, never a dead reader
                slot.result = None
            slot.ms = (time.monotonic() - t0) * 1000.0
            slot.done.set()
            if self.abandoned:
                return


_STUCK: List[_Worker] = []  # abandoned workers still inside a call, across passes


def stuck_count() -> int:
    _STUCK[:] = [w for w in _STUCK if w.is_alive()]
    return len(_STUCK)


class ArgsReader:
    """Bounded KERN_PROCARGS2 reads for one pass. ``read`` returns (results, unread, stats):
    ``results[pid]`` is the parsed argv or None (refused); ``unread`` are the pids never answered
    (deadline, budget, or STUCK_MAX reached)."""

    def __init__(
        self,
        reader: Reader = procargs2,
        call_s: float = ARGS_CALL_S,
        budget_s: float = ARGS_BUDGET_S,
        stuck_max: int = STUCK_MAX,
        mono: Callable[[], float] = time.monotonic,
    ) -> None:
        self.reader, self.call_s, self.budget_s = reader, call_s, budget_s
        self.stuck_max, self.mono = stuck_max, mono

    def read(
        self, pids: List[int], keys: Tuple[str, ...] = ()
    ) -> Tuple[Dict[int, Optional[Parsed]], List[int], Dict[str, Any]]:
        results: Dict[int, Optional[Parsed]] = {}
        unread: List[int] = []
        slow: List[Tuple[int, float]] = []
        stats: Dict[str, Any] = {"calls": 0, "deadline": 0, "skipped": 0, "max_ms": 0.0}
        end = self.mono() + self.budget_s
        w: Optional[_Worker] = None
        try:
            for i, pid in enumerate(pids):
                left = end - self.mono()
                if left <= 0 or (w is None and stuck_count() >= self.stuck_max):
                    stats["skipped"] = len(pids) - i
                    unread.extend(pids[i:])
                    break
                if w is None:
                    w = _Worker(self.reader, keys)
                    w.start()
                slot = _Slot(pid)
                w.q.put(slot)
                stats["calls"] += 1
                if slot.done.wait(min(self.call_s, left)):
                    results[pid] = slot.result
                    stats["max_ms"] = max(stats["max_ms"], slot.ms)
                    if slot.ms >= SLOW_CALL_S * 1000.0:
                        slow.append((pid, slot.ms))
                    continue
                w.abandoned = (
                    True  # an in-kernel ctypes call cannot be interrupted: leave it
                )
                _STUCK.append(w)
                w = None
                stats["deadline"] += 1
                unread.append(pid)
        finally:
            if w is not None:
                w.q.put(None)
        stats["stuck"] = stuck_count()
        stats["slow"] = sorted(slow, key=lambda s: -s[1])[:PID_LIST_MAX]
        return results, unread, stats


# ── the table ────────────────────────────────────────────────────────────────────────────────────


def _is_claude_comm(comm: str) -> bool:
    return comm in CLAUDE_COMMS or comm.startswith("node")


def args_order(krows: Dict[int, KRow], my_uid: int) -> Tuple[List[int], List[int], set]:
    """(always-read pids in priority order, cacheable pids, critical pids). Same-uid live rows only
    (another uid's KERN_PROCARGS2 is EINVAL by design). Tier 1 claude family by comm (never cached:
    claude rewrites its process title); tier 2 kitty, shells and script hosts; tier 3 descendants of
    claude; tier 4 the rest, cacheable. Critical = claude family, kitty, a shell under kitty, every
    descendant of claude (``bg_work_for`` reads their argv for background work): an unread argv
    there is never trusted. Critical rows are read first, claude before the rest."""
    kids: Dict[int, List[int]] = {}
    for r in krows.values():
        kids.setdefault(r.ppid, []).append(r.pid)
    claude = [p for p, r in krows.items() if _is_claude_comm(r.comm)]
    kitty = {p for p, r in krows.items() if r.comm == "kitty"}
    under_claude: set = set()
    todo = list(claude)
    while todo:
        for k in kids.get(todo.pop(), []):
            if k not in under_claude:
                under_claude.add(k)
                todo.append(k)
    shell_under_kitty = set()
    for p, r in krows.items():
        if r.comm.lstrip("-") in ("zsh", "bash", "fish", "sh"):
            q, hops = r.ppid, 0
            while q > 1 and hops < 4:
                if q in kitty:
                    shell_under_kitty.add(p)
                    break
                q = krows[q].ppid if q in krows else 0
                hops += 1
    critical = set(claude) | kitty | shell_under_kitty | under_claude
    tiers: List[List[int]] = [[], [], [], []]
    for p in sorted(krows):
        r = krows[p]
        if r.uid != my_uid or r.p_stat == SZOMB:
            continue
        if _is_claude_comm(r.comm):
            tiers[0].append(p)
        elif p in critical:
            tiers[1].append(p)
        elif r.comm in SHELL_COMMS or r.comm in HOST_COMMS:
            tiers[2].append(p)
        else:
            tiers[3].append(p)
    return tiers[0] + tiers[1] + tiers[2], tiers[3], critical


_ARGS_CACHE: Dict[Tuple[int, int, int, str], str] = {}


def _exited(pid: int, row: KRow, recheck: Callable[[int], Optional[KRow]]) -> bool:
    """True only on proof: the pid is gone, or now names a different start. A failed re-read is
    not proof, so the row stays (and stays untrusted)."""
    try:
        now = recheck(pid)
    except OSError:
        return False
    return now is None or (now.sec, now.usec) != (row.sec, row.usec)


def read_table(
    reader: Optional[ArgsReader] = None,
    kern: Callable[[], Dict[int, KRow]] = kern_proc_all,
    ttys_fn: Callable[[Iterable[int]], Dict[int, str]] = tty_map,
    my_uid: Optional[int] = None,
    mono: Callable[[], float] = time.monotonic,
    recheck: Callable[[int], Optional[KRow]] = kern_proc_pid,
) -> Tuple[Dict[int, T.ProcRow], Dict[int, str], Dict[str, Any]]:
    """Drop-in for ``observe.read_ps``: (procs, ttys by pid, info). Raises when KERN_PROC_ALL fails
    or comes back empty (the caller falls back to ps). ``info`` carries the source, timings, the
    unread counts and ``critical_unread`` (pids whose argv may not be trusted as read). A critical
    row whose argv read was refused is re-read by pid: one that exited (or whose pid now names
    another start) during the pass is dropped, as a ps run a moment later would not list it."""
    t0 = mono()
    krows = kern()
    if not krows:
        raise RuntimeError("KERN_PROC_ALL returned no rows")
    t1 = mono()
    names = ttys_fn(r.tdev for r in krows.values())
    t2 = mono()
    uid = os.getuid() if my_uid is None else my_uid
    always, cacheable, critical = args_order(krows, uid)
    todo = always + [
        p for p in cacheable
        if (p, krows[p].sec, krows[p].usec, krows[p].comm) not in _ARGS_CACHE
    ]  # fmt: skip
    got, unread, astats = (reader or ArgsReader()).read(todo)
    t3 = mono()
    live_keys = set()
    procs: Dict[int, T.ProcRow] = {}
    ttys: Dict[int, str] = {}
    n_refused = n_other = n_cached = n_gone = 0
    crit_unread: List[int] = []
    unread_set = set(unread)
    for p, r in krows.items():
        zombie = r.p_stat == SZOMB
        key = (p, r.sec, r.usec, r.comm)
        if zombie:
            args = render_args(None, r.comm, True)
        elif p in got and got[p] is not None:
            args = render_args(got[p][0], r.comm, False)  # type: ignore[index]
            if p not in always:
                _ARGS_CACHE[key] = args
        elif key in _ARGS_CACHE and p not in unread_set:
            args = _ARGS_CACHE[key]
            n_cached += 1
        else:
            args = render_args(None, r.comm, False)
            if r.uid != uid:
                n_other += 1
            elif p in unread_set:
                if p in critical:
                    crit_unread.append(p)
            else:
                n_refused += 1
                if p in critical:
                    if _exited(p, r, recheck):
                        n_gone += 1
                        continue
                    crit_unread.append(p)
        live_keys.add(key)
        procs[p] = T.ProcRow(
            p, r.ppid, stat_letter(r.p_stat), store.lstart_text(r.sec), args
        )
        name = names.get(r.tdev & 0xFFFFFFFF) if r.tdev != NODEV else None
        if name:
            ttys[p] = name
    for k in [k for k in _ARGS_CACHE if k not in live_keys]:
        del _ARGS_CACHE[k]
    info: Dict[str, Any] = {
        "source": "kern_proc_all",
        "rows": len(procs),
        "ms": {
            "table": round((t1 - t0) * 1000.0, 2),
            "tty": round((t2 - t1) * 1000.0, 2),
            "args": round((t3 - t2) * 1000.0, 2),
        },
        "args_read": sum(1 for v in got.values() if v is not None),
        "args_cached": n_cached,
        "args_refused": n_refused,
        "exited": n_gone,
        "args_unread": len(unread),
        "args_other_uid": n_other,
        "critical_unread": sorted(crit_unread),
        "stuck": astats.get("stuck", 0),
        "deadline": astats.get("deadline", 0),
        "max_call_ms": round(float(astats.get("max_ms", 0.0)), 2),
        "slow": [
            {"pid": p, "comm": krows[p].comm if p in krows else "", "ms": round(ms, 1)}
            for p, ms in astats.get("slow", [])
        ],
        "_krows": krows,  # for the shadow comparison; dropped before anything is logged
    }
    return procs, ttys, info


def read_env(
    pids: List[int], keys: Tuple[str, ...], reader: Optional[ArgsReader] = None
) -> Dict[int, Dict[str, str]]:
    """pid → the asked-for env keys, from the KERN_PROCARGS2 env block (``observe.read_ps_env``'s
    contract: a pid with no readable block is left out — unknown, never "no such key")."""
    got, _, _ = (reader or ArgsReader()).read(list(pids), keys)
    return {p: v[1] for p, v in got.items() if v is not None}


# ── shadow parity ────────────────────────────────────────────────────────────────────────────────


def _tok_hash(args: str) -> str:
    return hashlib.sha1("\0".join(args.split()).encode("utf-8", "replace")).hexdigest()[
        :12
    ]


def compare(
    ps_procs: Dict[int, T.ProcRow],
    ps_ttys: Dict[int, str],
    pf_procs: Dict[int, T.ProcRow],
    pf_ttys: Dict[int, str],
    pre: Optional[Dict[int, KRow]] = None,
    young_after: Optional[int] = None,
    is_claude: Optional[Callable[[str], bool]] = None,
) -> Dict[str, Any]:
    """Field parity between a ps census and a ps-free one. ``pre`` is a KERN_PROC_ALL read taken
    BEFORE ps: a ppid/zombie/lstart/tty difference ps shares with ``pre`` is churn inside the ps
    call, not a mismatch. ``young_after`` (epoch s) exempts args of a process started after it
    (claude rewrites its title at startup). Only counts, pids and token hashes come back."""
    if is_claude is None:
        from lr_recon.observe_rows import is_claude as is_claude_fn

        is_claude = is_claude_fn
    common = sorted(set(ps_procs) & set(pf_procs))
    fields = ("ppid", "zombie", "lstart", "tty", "args_claude", "args_other")
    mism: Dict[str, int] = {f: 0 for f in fields}
    pids: Dict[str, List[int]] = {f: [] for f in fields}
    churn = 0
    tokens: List[Dict[str, Any]] = []
    tty_of_pre: Dict[int, str] = {}
    if pre:
        names = tty_map(r.tdev for r in pre.values())
        tty_of_pre = {p: names.get(r.tdev & 0xFFFFFFFF, "") for p, r in pre.items()}

    def note(field: str, pid: int) -> None:
        mism[field] += 1
        if len(pids[field]) < PID_LIST_MAX:
            pids[field].append(pid)

    for p in common:
        a, b = ps_procs[p], pf_procs[p]
        k = pre.get(p) if pre else None
        checks = (
            ("ppid", a.ppid, b.ppid, k.ppid if k else None),
            ("zombie", a.zombie, b.zombie, (k.p_stat == SZOMB) if k else None),
            (
                "lstart",
                " ".join(a.lstart.split()),
                b.lstart,
                store.lstart_text(k.sec) if k else None,
            ),
            (
                "tty",
                ps_ttys.get(p, ""),
                pf_ttys.get(p, ""),
                tty_of_pre.get(p) if k else None,
            ),
        )
        for field, ps_v, pf_v, pre_v in checks:
            if ps_v == pf_v:
                continue
            if pre_v is not None and ps_v == pre_v:
                churn += 1
                continue
            note(field, p)
        if a.zombie or b.zombie or b.args.startswith("(") and b.args.endswith(")"):
            continue  # unreadable or defunct: counted by read_table, not a rendering mismatch
        if a.args == b.args:
            continue
        young = young_after is not None and k is not None and k.sec >= young_after
        if young:
            churn += 1
            continue
        if is_claude(a.args) or is_claude(b.args):
            note("args_claude", p)
            if len(tokens) < PID_LIST_MAX:
                tokens.append(
                    {"pid": p, "ps": _tok_hash(a.args), "pf": _tok_hash(b.args)}
                )
        else:
            note("args_other", p)
    return {
        "rows": {
            "ps": len(ps_procs),
            "pf": len(pf_procs),
            "common": len(common),
            "only_ps": len(set(ps_procs) - set(pf_procs)),
            "only_pf": len(set(pf_procs) - set(ps_procs)),
        },
        "mismatch": mism,
        "pids": {f: v for f, v in pids.items() if v},
        "claude_tokens": tokens,
        "churn": churn,
    }


def gate_fields() -> Tuple[str, ...]:
    """The fields that must read zero for the shadow→on switch (REPORT §11 census row)."""
    return ("ppid", "zombie", "lstart", "tty", "args_claude")


def shadow_log(paths: Optional[T.Paths], row: Dict[str, Any]) -> None:
    """Append one parity row to ``recon/shadow/ps-free.jsonl``; rotate once past the size cap. Never
    raises: the shadow is advisory and must not cost a pass."""
    if paths is None:
        return
    try:
        d = paths.shadow
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, SHADOW_LOG)
        try:
            if os.path.getsize(path) >= SHADOW_LOG_MAX_BYTES:
                os.replace(path, path + ".1")
        except OSError:
            pass
        clean = {k: v for k, v in row.items() if not k.startswith("_")}
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(clean, separators=(",", ":"), sort_keys=True) + "\n")
    except Exception:  # noqa: BLE001
        pass


def shadow_point(kind: str, pid: int, decided: str, pf: Optional[str]) -> None:
    """A single-pid read (store, fence) that ps decided: logged only when the in-process read
    disagrees. A gone process on either side ("") or an unread pf (None) is not a disagreement."""
    if pf is None or not pf or not decided or pf == decided:
        return
    try:
        paths: Optional[T.Paths] = T.Paths.from_env()
    except Exception:  # noqa: BLE001
        paths = None
    shadow_log(
        paths, {"ts": round(time.time(), 3), "point": kind, "pid": pid, "agree": False}
    )


def parity_summary(lines: Iterable[str]) -> Dict[str, Any]:
    """Fold the shadow log: passes compared, passes where ps was blind and ps-free was not, field
    totals, and the trailing run of clean passes (the shadow→on gate counts that run)."""
    passes = blind = clean_run = points = 0
    totals: Dict[str, int] = {
        f: 0 for f in ("ppid", "zombie", "lstart", "tty", "args_claude", "args_other")
    }
    max_table_ms = 0.0
    for line in lines:
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if not isinstance(row, dict):
            continue
        if row.get(
            "point"
        ):  # a single-pid read that disagreed (store, fence): breaks the run
            points += 1
            clean_run = 0
            continue
        if not row.get("ps_ok"):
            blind += 1 if row.get("pf_ok") else 0
            continue
        cmp_ = row.get("cmp")
        if not isinstance(cmp_, dict):
            continue
        passes += 1
        m = cmp_.get("mismatch") or {}
        for f in totals:
            totals[f] += int(m.get(f, 0) or 0)
        dirty = any(int(m.get(f, 0) or 0) for f in gate_fields())
        clean_run = 0 if dirty else clean_run + 1
        try:
            max_table_ms = max(
                max_table_ms,
                float(((row.get("pf") or {}).get("ms") or {}).get("table", 0)),
            )
        except (TypeError, ValueError):
            pass
    return {
        "passes": passes,
        "ps_blind_pf_ok": blind,
        "mismatch_totals": totals,
        "clean_run": clean_run,
        "point_disagree": points,
        "max_table_ms": max_table_ms,
    }


# ── CLI (bin/cc-proctable) ───────────────────────────────────────────────────────────────────────

USAGE = """usage: cc-proctable [--summary] [--json]
       cc-proctable --lstart <pid>          ps LSTART of one pid, root rows included ("" = gone)
       cc-proctable --holders <sid>         live claude processes carrying --resume <sid>, plus live
                                            registry rows naming <sid>; prints the count
       cc-proctable --parity [--min N]      fold recon/shadow/ps-free.jsonl; exit 0 when the trailing
                                            clean run is at least N passes (default 500)
       cc-proctable --mode                  the mode the reconciler would read now (off|shadow|on)
Never prints argv or env text."""


def _holders(sid: str, home: str) -> Dict[str, Any]:
    from lr_recon import observe_rows as R

    procs, _, info = read_table()
    leaves = R.resume_leaves(procs).get(sid, [])
    reg = R.read_registry(os.path.join(home, ".claude", "cc-registry"))
    reg_pids = [
        int(r["pid"])
        for r in reg
        if r.get("session_id") == sid
        and R.live_as(r.get("pid"), r.get("lstart"), procs)
    ]
    pids = sorted(set(leaves) | set(reg_pids))
    return {
        "sid": sid,
        "holders": len(pids),
        "pids": pids,
        "argv_pids": sorted(leaves),
        "registry_pids": sorted(reg_pids),
        "critical_unread": info["critical_unread"],
    }


def main(argv: List[str]) -> int:
    args = list(argv)
    as_json = "--json" in args
    args = [a for a in args if a != "--json"]
    if args and args[0] in ("-h", "--help"):
        print(USAGE)
        return 0
    if args[:1] == ["--mode"]:
        print(mode())
        return 0
    if args[:1] == ["--lstart"] and len(args) == 2 and args[1].isdigit():
        got = proc_lstart(int(args[1]))
        if got is None:
            print("cc-proctable: lstart unreadable", file=sys.stderr)
            return 2
        print(got)
        return 0 if got else 1
    if args[:1] == ["--holders"] and len(args) == 2:
        res = _holders(args[1], os.environ.get("HOME", os.path.expanduser("~")))
        print(json.dumps(res, sort_keys=True) if as_json else res["holders"])
        return 3 if res["critical_unread"] else 0
    if args[:1] == ["--parity"]:
        need = 500
        if len(args) == 3 and args[1] == "--min" and args[2].isdigit():
            need = int(args[2])
        elif len(args) != 1:
            print(USAGE, file=sys.stderr)
            return 2
        path = os.path.join(T.Paths.from_env().shadow, SHADOW_LOG)
        lines: List[str] = []
        for p in (path + ".1", path):
            try:
                with open(p, "r", encoding="utf-8", errors="replace") as fh:
                    lines.extend(fh.readlines())
            except OSError:
                pass
        s = parity_summary(lines)
        s["need"], s["ready"] = need, s["clean_run"] >= need
        if as_json:
            print(json.dumps(s, sort_keys=True))
        else:
            print(
                "ps-free parity: %d passes compared, trailing clean run %d of %d needed — %s"
                % (
                    s["passes"],
                    s["clean_run"],
                    need,
                    "READY" if s["ready"] else "not ready",
                )
            )
            print(
                "mismatch totals: "
                + ", ".join("%s %d" % kv for kv in sorted(s["mismatch_totals"].items()))
            )
            print(
                "passes where ps was blind and ps-free read the table: %d"
                % s["ps_blind_pf_ok"]
            )
            print(
                "single-pid reads that disagreed (store, fence): %d"
                % s["point_disagree"]
            )
        return 0 if s["ready"] else 1
    if args and args != ["--summary"]:
        print(USAGE, file=sys.stderr)
        return 2
    procs, ttys, info = read_table()
    info.pop("_krows", None)
    nclaude = sum(1 for r in procs.values() if not r.zombie and _is_claude_args(r.args))
    info["claude"] = nclaude
    info["zombies"] = sum(1 for r in procs.values() if r.zombie)
    info["with_tty"] = len(ttys)
    if as_json:
        print(json.dumps(info, sort_keys=True))
    else:
        print(
            "proctable: %d rows (%d claude, %d zombie, %d with a tty) · table %.1f ms, tty %.1f ms, args %.1f ms"
            % (
                info["rows"],
                nclaude,
                info["zombies"],
                len(ttys),
                info["ms"]["table"],
                info["ms"]["tty"],
                info["ms"]["args"],
            )
        )
        print(
            "args: %d read, %d cached, %d refused, %d unread, %d other-uid · critical unread %d · stuck readers %d"
            % (
                info["args_read"], info["args_cached"], info["args_refused"], info["args_unread"],
                info["args_other_uid"], len(info["critical_unread"]), info["stuck"],
            )
        )  # fmt: skip
    return 3 if info["critical_unread"] else 0


def _is_claude_args(args: str) -> bool:
    from lr_recon.observe_rows import is_claude

    return is_claude(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
