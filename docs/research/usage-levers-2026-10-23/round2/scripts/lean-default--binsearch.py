#!/usr/bin/env python3
# mmap search of the Claude Code binary for a pattern; print a context window around each hit (deduped).
import mmap, sys, re

path, pat = sys.argv[1], sys.argv[2].encode()
before = int(sys.argv[3]) if len(sys.argv) > 3 else 300
after = int(sys.argv[4]) if len(sys.argv) > 4 else 300
maxhits = int(sys.argv[5]) if len(sys.argv) > 5 else 20
seen = set()
hits = 0
with open(path, "rb") as f:
    mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    i = 0
    while hits < maxhits:
        j = mm.find(pat, i)
        if j < 0:
            break
        ctx = mm[max(0, j - before) : j + after]
        key = ctx[before - 60 : before + 60]
        if key not in seen:
            seen.add(key)
            hits += 1
            print("=== @", j)
            print(re.sub(rb"[^\x20-\x7e\n]", b".", ctx).decode("ascii"))
        i = j + len(pat)
print("hits shown", hits)
