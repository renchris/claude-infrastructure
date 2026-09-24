#!/usr/bin/env python3
"""Schema survey: sample transcript files of each ctx type and report which fields exist.
Prints aggregates only (key presence counts), never content."""
import json, glob, os, random, collections, sys
random.seed(7)
CFG = ['~/.claude','~/.claude-secondary','~/.claude-tertiary','~/.claude-quaternary']
files = {'main':[], 'subagent':[], 'workflow_agent':[]}
for c in CFG:
    root = os.path.expanduser(c) + '/projects'
    for p in glob.glob(root + '/*/*.jsonl'): files['main'].append(p)
    for p in glob.glob(root + '/*/*/subagents/agent-*.jsonl'): files['subagent'].append(p)
    for p in glob.glob(root + '/*/*/subagents/workflows/**/agent-*.jsonl', recursive=True): files['workflow_agent'].append(p)
N = int(sys.argv[1]) if len(sys.argv) > 1 else 8
for kind, fl in files.items():
    fl = [f for f in fl if os.path.getmtime(f) > 1757376000]  # 2025-09-09 guard, loose
    fl = sorted(fl, key=os.path.getmtime)[-400:]
    sample = random.sample(fl, min(N, len(fl)))
    top = collections.Counter(); keys = collections.defaultdict(collections.Counter)
    blocks = collections.Counter(); att = collections.Counter(); usage_keys = collections.Counter(); msgkeys = collections.Counter()
    ucontent = collections.Counter(); tr_content = collections.Counter(); origin = collections.Counter()
    for f in sample:
        for line in open(f, errors='replace'):
            try: r = json.loads(line)
            except Exception: top['<badjson>'] += 1; continue
            t = r.get('type'); top[t] += 1
            for k in r: keys[t][k] += 1
            m = r.get('message') if isinstance(r.get('message'), dict) else None
            if m:
                for k in m: msgkeys[(t, k)] += 1
                c = m.get('content')
                if isinstance(c, list):
                    for b in c:
                        if isinstance(b, dict):
                            blocks[(t, b.get('type'))] += 1
                            if b.get('type') == 'tool_result':
                                cc = b.get('content'); tr_content[type(cc).__name__ if not isinstance(cc, list) else 'list:' + ','.join(sorted({x.get('type','?') for x in cc if isinstance(x, dict)}))] += 1
                elif isinstance(c, str): ucontent[(t, 'str')] += 1
                u = m.get('usage')
                if isinstance(u, dict):
                    for k in u: usage_keys[k] += 1
            if t == 'attachment':
                a = r.get('attachment') or {}
                att[a.get('type')] += 1
            if 'origin' in r: origin[json.dumps(r['origin'])[:60]] += 1
    print(f'===== {kind}: {len(fl)} recent files, sampled {len(sample)}')
    print('types', dict(top.most_common()))
    for t, kc in keys.items(): print(' keys', t, dict(kc.most_common()))
    print('msgkeys', dict(msgkeys.most_common()))
    print('blocks', dict(blocks.most_common()))
    print('str content', dict(ucontent))
    print('tool_result.content', dict(tr_content.most_common()))
    print('usage keys', dict(usage_keys.most_common()))
    print('attachment types', dict(att.most_common()))
    print('origin', dict(origin.most_common(8)))
