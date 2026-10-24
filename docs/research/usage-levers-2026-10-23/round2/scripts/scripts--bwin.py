import mmap, sys, re
path = sys.argv[1]; lo = int(sys.argv[2]); hi = int(sys.argv[3]); pats = sys.argv[4:]
with open(path, 'rb') as f:
    m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    seg = m[lo:hi]
    for p in pats:
        rx = re.compile(p.encode())
        hits = [h.start() for h in rx.finditer(seg)]
        print(f'=== {p!r}: {len(hits)} hits (abs offsets {[lo+h for h in hits[:12]]})')
        for i in hits[:6]:
            s = seg[max(0, i - 260): i + 260].decode('utf-8', 'replace').replace('\n', '\\n')
            print(f'--- @{lo+i}\n{s}\n')
