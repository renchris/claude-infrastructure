#!/usr/bin/env python3
"""pty-run.py — run a command attached to a REAL pseudo-terminal, echoing its output.

WHY THIS EXISTS. `jev-batch.sh` branches on `[ -t 1 ]`: launchd gets a plain file descriptor and
the run is written to a file, while a human running it by hand gets the pass streamed to their
terminal (a 133-call pass is 9-27 minutes, and a silent terminal for that long reads as hung).
That branch is unreachable from bats, which pipes stdout — so without a pty the streaming half
ships untested and the suite can only ever exercise the file-only path.

`script -q /dev/null CMD` was tried first and silently ran nothing on this platform: no output, no
log file, exit 0. It looked identical to "the subject printed nothing", which is the failure this
fixture exists to avoid, so it is deliberately not used.

Usage: pty-run.py <cmd> [args...]   — command output goes to THIS process's stdout; exit code is
the child's, so a caller can assert on it.
"""
import os
import pty
import sys

chunks = []


def _read(fd):
    data = os.read(fd, 1024)
    chunks.append(data)
    return data


if len(sys.argv) < 2:
    sys.stderr.write("usage: pty-run.py <cmd> [args...]\n")
    raise SystemExit(2)

status = pty.spawn(sys.argv[1:], _read)
sys.stdout.write(b"".join(chunks).decode(errors="replace"))
sys.stdout.flush()
raise SystemExit(os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") else status >> 8)
