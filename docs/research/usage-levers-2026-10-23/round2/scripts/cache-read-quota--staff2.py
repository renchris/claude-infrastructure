import json, sys, re
STAFF = {'bcherny','ThariqS','wolffiex','catherinewu','lydiahallie','ashwin-ant','bogini','dicksontsai','km-anthropic','rboyce-ant','sid374','igorkofman','hackyon-anthropic','ant-kurt','chrislloyd','levpopov'}
for n in sys.argv[1:]:
    raw = open(f'c-{n}.json').read().strip()
    dec = json.JSONDecoder(); i = 0; cs = []
    while i < len(raw):
        o, j = dec.raw_decode(raw, i); cs += o; i = j
        while i < len(raw) and raw[i].isspace(): i += 1
    hits = [c for c in cs if c['user']['login'] in STAFF or c.get('author_association') in ('MEMBER','OWNER','COLLABORATOR')]
    print('#', n, 'comments', len(cs), 'candidate-staff', len(hits))
    for c in hits:
        b = c['body'] or ''
        print('---', c['user']['login'], c['author_association'], c['created_at'][:10], c['html_url'])
        if re.search(r'cach', b, re.I): print(b[:3000])
        else: print('[no cache mention]', b[:300].replace('\n',' '))
