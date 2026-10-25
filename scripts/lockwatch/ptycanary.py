"""ptycanary.py -- time a fresh-pty shell start (/bin/zsh -fc), the exact path every new terminal takes.

Run as:  $PY -I ptycanary.py --out FILE        (a lockprobe probe; never via #!: DESIGN I1)

Writes FILE twice (atomic rename each time):
  {"phase":"spawned","zsh_pid":N,"tty":"ttysNNN","t0":<epoch>}       right after the spawn
  {"phase":"done","verdict":"OK"|"ERROR","zsh_ms":<ms>,"rc":<rc>,...}  when zsh exits
The parent (lockprobe) owns the deadline: a canary still at "spawned" is slow or stuck, and its age
is the measurement. This process never kills zsh and never gives up on it.

Why each step (DESIGN C1):
  * The pty comes from posix_openpt/grantpt/unlockpt/ptsname: ioctls, no /dev walk.
  * The slave is opened HERE with O_RDWR|O_NOCTTY|O_NONBLOCK and dup2'd onto zsh's fds 0/1/2.
    The shell gets no setsid and no TIOCSCTTY, so it can never be a session leader whose exit
    revokes its terminal (the 68298 trigger). This process was setsid'd by the spawner but opens the slave with
    O_NOCTTY, so it has no ctty either.
  * The master stays open for zsh's WHOLE life: zsh's init_io re-opens its tty by path, and a
    re-open after the master closed is exactly bash 96296's endless carrier wait.
  * The master is closed with O_NONBLOCK set: 3 ms instead of a ~600 ms drain (experiments.md §2b).
"""

import ctypes
import fcntl
import json
import os
import sys
import time

_LIBC = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
_LIBC.ptsname.restype = ctypes.c_char_p
ZSH = os.environ.get("CC_LOCKWATCH_PTYCANARY_ZSH", "/bin/zsh")
ARGV = [ZSH, "-fc", ": lockwatch-canary; exit"]


def _write(out, doc):
    tmp = out + ".tmp.%d" % os.getpid()
    with open(tmp, "w") as fh:
        fh.write(json.dumps(doc, separators=(",", ":")) + "\n")
    os.rename(tmp, out)


def run(out):
    t0 = time.time()
    sys.stdout.write("started %.3f\n" % t0)
    sys.stdout.flush()
    mfd = _LIBC.posix_openpt(os.O_RDWR | os.O_NOCTTY)
    if mfd < 0:
        _write(
            out,
            {
                "phase": "done",
                "verdict": "ERROR",
                "why": "posix_openpt errno %d" % ctypes.get_errno(),
            },
        )
        return 1
    if _LIBC.grantpt(mfd) != 0 or _LIBC.unlockpt(mfd) != 0:
        _write(
            out,
            {
                "phase": "done",
                "verdict": "ERROR",
                "why": "grantpt/unlockpt errno %d" % ctypes.get_errno(),
            },
        )
        return 1
    name = _LIBC.ptsname(mfd)
    if not name:
        _write(out, {"phase": "done", "verdict": "ERROR", "why": "ptsname failed"})
        return 1
    path = name.decode()
    sfd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    t_open = time.time()
    fa = [
        (os.POSIX_SPAWN_DUP2, sfd, 0),
        (os.POSIX_SPAWN_DUP2, sfd, 1),
        (os.POSIX_SPAWN_DUP2, sfd, 2),
        (os.POSIX_SPAWN_CLOSE, mfd),
    ]
    env = {"PATH": "/usr/bin:/bin", "HOME": os.environ.get("HOME", "/tmp")}
    ts = time.time()
    pid = os.posix_spawn(ZSH, ARGV, env, file_actions=fa)
    os.close(sfd)
    _write(
        out,
        {
            "phase": "spawned",
            "zsh_pid": pid,
            "tty": os.path.basename(path),
            "t0": ts,
            "open_ms": round((t_open - t0) * 1000, 2),
        },
    )
    _pid, status = os.waitpid(pid, 0)
    te = time.time()
    flags = fcntl.fcntl(mfd, fcntl.F_GETFL)
    fcntl.fcntl(mfd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
    try:
        os.read(mfd, 65536)
    except OSError:
        pass
    os.close(mfd)
    rc = (
        os.waitstatus_to_exitcode(status)
        if hasattr(os, "waitstatus_to_exitcode")
        else status >> 8
    )
    _write(
        out,
        {
            "phase": "done",
            "verdict": "OK" if rc == 0 else "ERROR",
            "rc": rc,
            "zsh_pid": pid,
            "tty": os.path.basename(path),
            "t0": ts,
            "zsh_ms": round((te - ts) * 1000, 1),
            "close_ms": round((time.time() - te) * 1000, 2),
        },
    )
    return 0


def main(argv):
    if len(argv) != 2 or argv[0] != "--out":
        sys.stderr.write("usage: ptycanary.py --out FILE\n")
        return 2
    return run(argv[1])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
