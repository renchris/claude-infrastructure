import os, sys, json, time, glob, collections
root = os.path.expanduser(sys.argv[1]); cutoff = time.time() - 86400
tok = collections.Counter(); req = collections.Counter(); seen = set(); nfiles = 0
for p in glob.glob(os.path.join(root, 'projects', '*', '**', '*.jsonl'), recursive=True):
    try:
        if os.path.getmtime(p) < cutoff: continue
    except OSError: continue
    nfiles += 1
    with open(p, 'rb') as f:
        for line in f:
            if b'"usage"' not in line or b'"assistant"' not in line: continue
            try: d = json.loads(line)
            except Exception: continue
            m = d.get('message') or {}
            mid = m.get('id'); u = m.get('usage') or {}
            if not mid or mid in seen: continue
            seen.add(mid)
            mod = m.get('model', '?'); req[mod] += 1
            tok[mod] += u.get('cache_read_input_tokens', 0) or 0
print('files', nfiles, 'deduped responses', len(seen))
tot = sum(tok.values()) or 1
for mod, n in req.most_common(8): print(f'{mod:30s} responses={n:6d} cache_read={tok[mod]:>13,d} share_of_cache_read={tok[mod]/tot:.1%}')
