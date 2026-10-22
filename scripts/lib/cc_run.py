"""cc_run — the Python twin of scripts/lib/cc-run.sh: run a script through its own #! interpreter.

macOS 15.8.1 keeps ~1.1 KiB of kernel memory for every #! file the kernel execs by path, until reboot
(docs/plans/KALLOC_TRIGGER_ELIMINATION_2026-10-22.md W4). ``subprocess.run([path, ...])`` is such an
exec; ``subprocess.run(cc_argv(path) + [...])`` runs the same program with the same argv the kernel
would build, through a Mach-O interpreter. Same rules as the bash runner: the #! line is split on
space/tab like xnu's exec_extract_strings, and anything the kernel would refuse or treat specially
(not +x, no interpreter, an interpreter that is itself a #! file, a bare name) is returned unchanged.

Callers that cannot import from scripts/lib copy nothing: they resolve this file next to their own
checkout (``<repo>/scripts/lib``) and fall back to ``[path]`` when it is absent.
"""

from __future__ import annotations

import os
import subprocess
from collections.abc import Sequence
from typing import Any

_HEAD = (
    512  # xnu IMG_SHSIZE: the kernel reads the #! line from the first 512 bytes only
)


def _head(path: str, n: int) -> bytes:
    try:
        with open(path, "rb") as f:
            return f.read(n)
    except OSError:
        return b""


def cc_argv(path: str) -> list[str]:
    """The argv the kernel would build for ``path``: ``[interp, *interp_args, path]`` or ``[path]``."""
    if (
        "/" not in path
        or not os.path.isfile(path)
        or not os.access(path, os.X_OK | os.R_OK)
    ):
        return [path]
    head = _head(path, _HEAD)
    if not head.startswith(b"#!"):
        return [path]
    eol = head.find(b"\n")
    if eol < 0:
        return [path]  # no newline in 512 bytes: ENOEXEC, let the kernel say so
    words = head[2:eol].replace(b"\t", b" ").split(b" ")
    toks = [w.decode("utf-8", "surrogateescape") for w in words if w]
    if not toks:
        return [path]
    interp = toks[0]
    if not os.path.isfile(interp) or not os.access(interp, os.X_OK):
        return [path]
    if _head(interp, 2) == b"#!":
        return [path]  # the kernel refuses a #! interpreter; keep its answer
    return [*toks, path]


def cc_run(args: Sequence[str], **kwargs: Any) -> subprocess.CompletedProcess[Any]:
    """``subprocess.run`` with ``args[0]`` mapped through :func:`cc_argv`."""
    argv = list(args)
    return subprocess.run(cc_argv(argv[0]) + argv[1:], **kwargs)  # noqa: S603 — argv list, no shell
