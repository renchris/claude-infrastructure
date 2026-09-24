#!/usr/bin/env python3
"""of_binctx.py — print deduplicated source context around identifiers in the CC native binary.

usage: of_binctx.py <term> [radius=300] [max=6]
The 2.1.280 claude.exe embeds the JS bundle (twice in places); identical windows are printed once.
"""

import mmap, sys, re

BIN = (
    "/Users/chrisren/.claude-280/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
)
term = sys.argv[1].encode()
rad = int(sys.argv[2]) if len(sys.argv) > 2 else 300
mx = int(sys.argv[3]) if len(sys.argv) > 3 else 6
with open(BIN, "rb") as f:
    mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    seen = set()
    i = 0
    shown = 0
    while shown < mx:
        j = mm.find(term, i)
        if j < 0:
            break
        w = mm[max(0, j - rad) : j + len(term) + rad]
        s = re.sub(rb"[^\x20-\x7e\n]", b".", w).decode()
        if s not in seen:
            seen.add(s)
            print("=== @%d\n%s\n" % (j, s))
            shown += 1
        i = j + 1
