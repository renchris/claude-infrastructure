#!/usr/bin/env python3
"""reso-writer-lock.py — per-repo exclusive advisory writer-lock.

The OS-held flock is the concurrency-detection primitive for the worktree
session-isolation system (discovery §3b/§4). ONE exclusive lock per repo,
keyed by the repo's git-common-dir. macOS has no flock(1) CLI, so this
python3 fcntl.flock helper IS the primitive. The kernel releases the lock on
holder death (normal exit, crash, SIGKILL, terminal-close) — no stale-PID
parsing, no freshness window (the S2 red-team mandate).

Modes (lockfile is <git-common-dir>/reso-writer.lock):

  hold <lockfile> <session_id> [--watch-pid PID]
      Acquire LOCK_EX|LOCK_NB. On success: write holder metadata + print
      "ACQUIRED", then BLOCK holding the FD until ANY of:
        (a) stdin reaches EOF   — Pattern A: the claude()/wrapper write-end
                                  closes when claude exits (discovery §4),
        (b) --watch-pid dies    — daemon mode: the guard ties the hold to the
                                  claude session PID (launch-path-independent),
        (c) SIGTERM/SIGINT.
      Releases on every path (finally:); the OS also releases on SIGKILL.
      Exit 0 = acquired-then-released, 3 = already held by another.

  check <lockfile> <session_id>
      Non-destructive state report (never steals a live lock):
        free        -> stdout "free"        exit 0
        self        -> stdout "self <pid>"  exit 0   (held by this session)
        other       -> stdout "other <pid>" exit 1   (held by another writer)

  acquire <lockfile> <session_id>
      One-shot probe (tests): LOCK_EX|LOCK_NB then release immediately.
      Exit 0 = acquired, 3 = held.
"""

from __future__ import annotations

import fcntl
import json
import os
import select
import signal
import sys
import time


def _read_meta(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.loads(fh.read() or "{}")
    except (OSError, ValueError):
        return {}


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # exists, owned by another user
    return True


def _open(path: str):
    # Create-if-absent, never truncate (metadata of a live holder must survive).
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    return fd


def mode_hold(lockfile: str, session_id: str, watch_pid: int) -> int:
    fd = _open(lockfile)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            sys.stdout.write("HELD\n")
            sys.stdout.flush()
            return 3
        meta = {
            "session": session_id,
            "pid": os.getpid(),
            "watch_pid": watch_pid,
            "cwd": os.getcwd(),
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        os.ftruncate(fd, 0)
        os.lseek(fd, 0, os.SEEK_SET)
        os.write(fd, json.dumps(meta).encode("utf-8"))
        os.fsync(fd)
        sys.stdout.write("ACQUIRED\n")
        sys.stdout.flush()

        released = {"v": False}

        def _release(*_):
            if not released["v"]:
                released["v"] = True
            raise SystemExit(0)

        signal.signal(signal.SIGTERM, _release)
        signal.signal(signal.SIGINT, _release)

        # Block holding the FD until the release condition.
        if watch_pid:
            # Daemon mode (the guard): tie the hold to the claude session PID.
            # stdin is ignored (the guard detaches it as </dev/null), so we
            # poll watch_pid only. Release the instant claude dies.
            while _pid_alive(watch_pid):
                time.sleep(2.0)
            return 0
        # Pattern A (the claude() wrapper): no watch-pid → release when our
        # stdin (the write-end held by claude) reaches EOF, i.e. claude exits.
        while True:
            try:
                ready, _, _ = select.select([sys.stdin], [], [], 2.0)
            except (OSError, ValueError):
                return 0
            if ready:
                chunk = sys.stdin.readline()
                if chunk == "" or chunk.strip() == "RELEASE":  # EOF or explicit
                    return 0
    finally:
        try:
            # Best-effort: clear metadata so a stale file never misleads `check`.
            os.ftruncate(fd, 0)
        except OSError:
            pass
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        except OSError:
            pass
        os.close(fd)


def mode_check(lockfile: str, session_id: str) -> int:
    if not os.path.exists(lockfile):
        sys.stdout.write("free\n")
        return 0
    fd = _open(lockfile)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            # A LIVE process holds the lock (OS releases on holder death, so a
            # failed non-blocking acquire ⇒ a live holder). Read who.
            meta = _read_meta(lockfile)
            holder_pid = int(meta.get("pid", 0) or 0)
            if meta.get("session") == session_id:
                sys.stdout.write(f"self {holder_pid}\n")
                return 0
            sys.stdout.write(f"other {holder_pid}\n")
            return 1
        # Acquired ⇒ no live holder. Release immediately (non-destructive).
        fcntl.flock(fd, fcntl.LOCK_UN)
        sys.stdout.write("free\n")
        return 0
    finally:
        os.close(fd)


def mode_acquire(lockfile: str, session_id: str) -> int:
    fd = _open(lockfile)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            sys.stdout.write("HELD\n")
            return 3
        fcntl.flock(fd, fcntl.LOCK_UN)
        sys.stdout.write("ACQUIRED\n")
        return 0
    finally:
        os.close(fd)


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        sys.stderr.write(
            __doc__ or "usage: reso-writer-lock.py <mode> <lockfile> <session_id>\n"
        )
        return 2
    mode, lockfile, session_id = argv[0], argv[1], argv[2]
    watch_pid = 0
    if "--watch-pid" in argv:
        try:
            watch_pid = int(argv[argv.index("--watch-pid") + 1])
        except (IndexError, ValueError):
            watch_pid = 0
    if mode == "hold":
        return mode_hold(lockfile, session_id, watch_pid)
    if mode == "check":
        return mode_check(lockfile, session_id)
    if mode == "acquire":
        return mode_acquire(lockfile, session_id)
    sys.stderr.write(f"unknown mode: {mode}\n")
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except KeyboardInterrupt:
        sys.exit(0)
