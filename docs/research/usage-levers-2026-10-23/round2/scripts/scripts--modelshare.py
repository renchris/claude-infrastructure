import os, sys, json, time, glob, collections, datetime
root = os.path.expanduser(sys.argv[1]); hours = float(sys.argv[2])
cut = time.time() - hours*3600
cr = collections.Counter(); req = collections.Counter(); seen = set(); nf = 0; skipped_ts = 0
for p in glob.glob(os.path.join(root, 'projects', '**', '*.jsonl'), recursive=True):
    try:
        if os.path.getmtime(p) < cut: continue
    except OSError: continue
    nf += 1
    with open(p, 'rb') as f:
        for line in f:
            if b'cache_read_input_tokens' not in line: continue
            try: d = json.loads(line)
            except Exception: continue
            ts = d.get('timestamp')
            if not ts: skipped_ts += 1; continue
            t = datetime.datetime.fromisoformat(ts.replace('Z', '+00:00')).timestamp()
            if t < cut: continue
            m = d.get('message') or {}
            mid = m.get('id'); u = m.get('usage') or {}
            if not mid or mid in seen: continue
            seen.add(mid)
            mod = m.get('model', '?'); req[mod] += 1
            cr[mod] += u.get('cache_read_input_tokens', 0) or 0
tot = sum(cr.values()) or 1
print(f'root={root} hours={hours} files={nf} deduped_responses={len(seen)} no_ts={skipped_ts} total_cache_read={tot:,}')
for mod, n in req.most_common(8): print(f'  {mod:28s} resp={n:6d} cache_read={cr[mod]:>14,d} share={cr[mod]/tot:.2%}')
