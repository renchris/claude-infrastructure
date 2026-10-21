#!/usr/bin/python3
"""kitty-fd-headroom.py — a no_ui kitten that raises (set) or reads (get) the RUNNING kitty's
open-file soft limit, in place, with no restart, signal, window or config reload (operator step O2b
of docs/research/lr-sustained-load-2026-10-20/impl/B8-kitty-hygiene.md, review E-5/E-6).

WHY. kitty 0.48.2 and 0.49.x keep one fd per remote-control peer until the main thread answers it
(prune_peers). A napped or starved main thread therefore piles up abandoned peers, and at the 256
soft limit accept() hits EMFILE and the talk thread dies for good: only a restart, or kitty 0.50.0
(#10632), recovers. A `no_ui` kitten's handle_result runs INSIDE kitty's process
(boss.run_kitten_with_metadata), so `setrlimit` there moves kitty's own limit.

    kitten @ --to unix:/tmp/b8probe/ctl.sock kitten ~/.claude/scripts/lib/kitty-fd-headroom.py set   # the throwaway probe FIRST
    kitten @ --to unix:/tmp/b8probe/ctl.sock kitten ~/.claude/scripts/lib/kitty-fd-headroom.py get   # read it back
    # then the same two against the main kitty: --to unix:/tmp/kitty-<main pid>

set: soft = min(8192, hard); the hard limit is never touched. get: reads only. Either prints one
line, `fd_headroom=<mode> pid=<pid> soft=<before>-><after> hard=<hard>`, and never raises inside
kitty (an error is reported as `fd_headroom=error …`). Run as a plain script (`python3 <this> get`)
it does the same for its own process, which is how tests read a fixture limit with no kitty.
Exit (script form): 0 ok · 1 error · 2 usage.
"""

import os
import resource
import sys

TARGET = 8192

try:  # inside kitty
    from kittens.tui.handler import result_handler
except ImportError:  # a plain python3 (tests, a dry read): the decorator is a no-op

    def result_handler(**_kw):
        def deco(f):
            return f

        return deco


def _lim(v):
    return "unlimited" if v == resource.RLIM_INFINITY else str(v)


def apply(mode):
    """One status line; never raises."""
    try:
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        if mode == "get":
            return "fd_headroom=get pid=%d soft=%s hard=%s" % (
                os.getpid(),
                _lim(soft),
                _lim(hard),
            )
        if mode != "set":
            return "fd_headroom=error unknown mode %r (use set or get)" % mode
        new = TARGET if hard == resource.RLIM_INFINITY else min(TARGET, hard)
        if soft != resource.RLIM_INFINITY and soft >= new:
            return (
                "fd_headroom=set pid=%d soft=%s->%s hard=%s (already at or above %d)"
                % (os.getpid(), _lim(soft), _lim(soft), _lim(hard), new)
            )
        resource.setrlimit(resource.RLIMIT_NOFILE, (new, hard))
        after, _ = resource.getrlimit(resource.RLIMIT_NOFILE)
        return "fd_headroom=set pid=%d soft=%s->%s hard=%s" % (
            os.getpid(),
            _lim(soft),
            _lim(after),
            _lim(hard),
        )
    except Exception as e:  # noqa: BLE001 — inside kitty an exception must never escape
        return "fd_headroom=error %s: %s" % (type(e).__name__, e)


def main(args):
    """kitty calls this first; a no_ui kitten has nothing to show."""
    return None


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    return apply(args[1] if len(args) > 1 else "get")


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("set", "get"):
        print("usage: kitty-fd-headroom.py set|get", file=sys.stderr)
        sys.exit(2)
    line = apply(sys.argv[1])
    print(line)
    sys.exit(1 if line.startswith("fd_headroom=error") else 0)
