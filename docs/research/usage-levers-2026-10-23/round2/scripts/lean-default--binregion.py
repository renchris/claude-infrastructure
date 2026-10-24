#!/usr/bin/env python3
# Find every occurrence of a pattern inside a byte region of the binary and print short context.
import mmap, sys, re

path, pat, lo, hi = (
    sys.argv[1],
    sys.argv[2].encode(),
    int(sys.argv[3]),
    int(sys.argv[4]),
)
w = int(sys.argv[5]) if len(sys.argv) > 5 else 200
with open(path, "rb") as f:
    mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    i = lo
    n = 0
    while True:
        j = mm.find(pat, i, hi)
        if j < 0:
            break
        n += 1
        print("=== @", j)
        print(
            re.sub(rb"[^\x20-\x7e\n]", b".", mm[max(0, j - w) : j + w]).decode("ascii")
        )
        i = j + len(pat)
    print("count", n)
