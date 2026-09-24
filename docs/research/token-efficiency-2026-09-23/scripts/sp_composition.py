#!/usr/bin/env python3
"""Per-context static-prefix composition (sizes + content hashes, never content).
Population: every file in extract.sqlite whose first response (seq=0) is in-window, xdup=0, not <synthetic>.
For each file, reads records up to the first assistant record and writes one JSON line to
data/sp_composition.jsonl with: order-indexed setup blocks (type, chars, sha1[:12]) and, for the
`instructions` attachment, one entry per memory file (path, chars, sha1[:12]).
Run: cd /tmp && nice -n 10 python3 sp_composition.py   (4 workers)"""
import json, os, sqlite3, hashlib, sys
from multiprocessing import Pool
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
DB = os.path.join(BASE, 'data', 'extract.sqlite')
OUT = os.path.join(BASE, 'data', 'sp_composition.jsonl')
h = lambda s: hashlib.sha1(s.encode('utf-8', 'replace')).hexdigest()[:12]

def rendered(rec):
    a = rec.get('attachment') or {}
    r = a.get('rendered', rec.get('rendered'))
    if isinstance(r, list):
        return ''.join(x.get('content', '') for x in r if isinstance(x, dict))
    return None

def raw(a):
    for k in ('content', 'text', 'prompt'):
        v = a.get(k)
        if isinstance(v, str): return v
    return None

def work(path):
    blocks = []; instr = []; first = None
    try:
        with open(path, errors='replace') as fh:
            for ln in fh:
                try: rec = json.loads(ln)
                except Exception: continue
                t = rec.get('type')
                if t == 'assistant':
                    break
                if t == 'attachment':
                    a = rec.get('attachment') or {}
                    at = a.get('type', '?')
                    rt = rendered(rec)
                    ev = a.get('hookEvent') if at.startswith('hook') else None
                    name = at + (':' + ev if ev else '')
                    if at == 'instructions':
                        for f in a.get('files') or []:
                            cont = f.get('content') or ''
                            instr.append({'path': f.get('path'), 'type': f.get('type'), 'chars': len(cont), 'sha': h(cont)})
                    txt = rt if rt is not None else (raw(a) or '')
                    blocks.append({'t': name, 'vis': rt is not None, 'chars': len(txt), 'sha': h(txt)})
                elif t == 'user':
                    m = (rec.get('message') or {}).get('content')
                    if isinstance(m, str): L = len(m)
                    else: L = sum(len(b.get('text', '')) if isinstance(b, dict) and b.get('type') == 'text' else len(json.dumps(b)) for b in (m or []))
                    blocks.append({'t': 'user_meta' if rec.get('isMeta') else 'user_prompt', 'vis': True, 'chars': L, 'sha': ''})
    except OSError as e:
        return {'file': path, 'error': str(e)}
    return {'file': path, 'blocks': blocks, 'instr': instr}

def main():
    c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    files = [r[0] for r in c.execute("select file from resp where seq=0 and xdup=0 and model!='<synthetic>'")]
    print('files', len(files), file=sys.stderr)
    n = 0
    with Pool(4) as p, open(OUT + '.tmp', 'w') as o:
        for rec in p.imap_unordered(work, files, chunksize=8):
            o.write(json.dumps(rec) + '\n'); n += 1
    os.replace(OUT + '.tmp', OUT)
    print('wrote', n, OUT, file=sys.stderr)
if __name__ == '__main__': main()
