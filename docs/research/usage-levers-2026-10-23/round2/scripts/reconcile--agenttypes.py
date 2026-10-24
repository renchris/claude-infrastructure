import re, sys, collections
p = sys.argv[1]
pat = re.compile(rb'agentType:"([A-Za-z0-9_-]{2,40})"')
seen = collections.Counter()
with open(p, 'rb') as f:
    tail = b''
    while True:
        chunk = f.read(1 << 24)
        if not chunk:
            break
        buf = tail + chunk
        for m in pat.finditer(buf):
            seen[m.group(1).decode()] += 1
        tail = buf[-64:]
for k, v in sorted(seen.items()):
    print(k, v)
