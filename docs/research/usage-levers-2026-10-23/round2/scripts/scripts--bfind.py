import mmap, sys, re
path = sys.argv[1]; win = int(sys.argv[2]); pats = sys.argv[3:]
with open(path, 'rb') as f:
    m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    for p in pats:
        rx = re.compile(p.encode())
        hits = [h.start() for h in rx.finditer(m)]
        print(f'=== {p!r}: {len(hits)} hits at {hits[:10]}')
        for i in hits[:3]:
            s = m[max(0, i - win): i + win].decode('utf-8', 'replace').replace('\n', '\\n')
            print(f'--- @{i}\n{s}\n')
