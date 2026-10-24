import json, sys, re
n = sys.argv[1]
raw = open(f'c-{n}.json').read().strip()
dec = json.JSONDecoder(); i = 0; cs = []
while i < len(raw):
    o, j = dec.raw_decode(raw, i); cs += o; i = j
    while i < len(raw) and raw[i].isspace(): i += 1
staff = [c for c in cs if c.get('author_association') in ('MEMBER', 'OWNER', 'COLLABORATOR')]
print(n, 'comments', len(cs), 'staff', len(staff))
for c in staff:
    b = c['body'] or ''
    flag = bool(re.search(r'cach|context|token', b, re.I))
    print('---', c['user']['login'], c['created_at'][:10], c['html_url'], 'MENTIONS_CACHE/CTX' if flag else '')
    if flag: print(b[:2500])
