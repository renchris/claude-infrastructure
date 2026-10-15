#!/usr/bin/env python3
"""close-order.py — for each kitty GLFWWindow that closed, did its fullscreen teardown run BEFORE or
AFTER the window itself closed?

    log show --style compact --predicate 'processID == <pid> AND category == "Window"' | close-order.py

The incident's unified log (unilog-0127.txt :465-524) has the order that precedes the crash: the
GLFWWindow logs `finishing close` FIRST (.466) and only then is its NSToolbarFullScreenWindow removed
from the window's group and closed (.506) — the fullscreen machinery was still being torn down for a
window that no longer existed. A window that left fullscreen before it closed shows the opposite
order, and a window that was never fullscreen has no toolbar window at all.

One row per closed GLFWWindow:  main_close  windowNumber  verdict  toolbar_close-main_close(ms)
verdict = CLOSED-IN-FULLSCREEN | LEFT-FULLSCREEN-FIRST | WINDOWED
"""

import re
import sys

TS = r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)"
group = re.compile(
    TS
    + r".*parent <GLFWWindow: \S+> windowNumber=(\w+) (?:add|remove) <NSToolbarFullScreenWindow: \S+> windowNumber=(\w+)"
)
fin = re.compile(TS + r".*window <(\w+): \S+> windowNumber=(\w+) finishing close")


def secs(t: str) -> float:
    h, m, s = t.split()[1].split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


toolbar_of: dict[str, str] = {}
closed: dict[str, float] = {}
order: list[tuple[float, str, str]] = []
for line in sys.stdin:
    g = group.search(line)
    if g:
        toolbar_of[g.group(2)] = g.group(3)
        continue
    f = fin.search(line)
    if f:
        t, cls, num = secs(f.group(1)), f.group(2), f.group(3)
        closed[num] = t
        if cls == "GLFWWindow":
            order.append((t, num, f.group(1).split()[1]))

for t, num, stamp in order:
    tb = toolbar_of.get(num)
    if tb is None or tb not in closed:
        print(f"{stamp}\t{num}\tWINDOWED\t-")
        continue
    d = (closed[tb] - t) * 1000
    print(
        f"{stamp}\t{num}\t{'CLOSED-IN-FULLSCREEN' if d > 0 else 'LEFT-FULLSCREEN-FIRST'}\t{d:+.0f}"
    )
