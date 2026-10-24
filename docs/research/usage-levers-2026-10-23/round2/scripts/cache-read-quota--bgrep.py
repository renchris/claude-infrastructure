import mmap, sys
path = sys.argv[1]; win = int(sys.argv[2]); maxhits = int(sys.argv[3]); pats = sys.argv[4:]
with open(path, 'rb') as f:
    m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    for p in pats:
        pb = p.encode(); pos = 0; n = 0
        while n < maxhits:
            i = m.find(pb, pos)
            if i < 0: break
            s = m[max(0, i - win): i + len(pb) + win].decode('utf-8', 'replace').replace('\n', '\\n')
            print(f'### {p!r} @ {i}\n{s}\n')
            pos = i + len(pb); n += 1
        # count total
        tot = 0; pos = 0
        while True:
            i = m.find(pb, pos)
            if i < 0: break
            tot += 1; pos = i + len(pb)
        print(f'=== {p!r} total occurrences: {tot}\n')
