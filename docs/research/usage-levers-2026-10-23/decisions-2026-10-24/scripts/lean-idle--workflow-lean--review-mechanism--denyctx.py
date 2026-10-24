import json, sys
# For each file, find tool_result containing PreToolUse:Workflow, print the deny text and what the model did next (next 3 assistant tool_uses/text)
for p in sys.argv[1:]:
    rows = []
    with open(p, 'rb') as fh:
        for line in fh:
            try: rows.append(json.loads(line))
            except Exception: pass
    for i, d in enumerate(rows):
        if d.get('type') != 'user': continue
        c = (d.get('message') or {}).get('content')
        if not isinstance(c, list): continue
        for x in c:
            if isinstance(x, dict) and x.get('type') == 'tool_result':
                t = x.get('content')
                t = t if isinstance(t, str) else json.dumps(t)
                if 'PreToolUse:Workflow' in t:
                    print('=====', p.split('/')[-2][-40:], d.get('timestamp'))
                    print('DENY:', t[:400].replace('\n',' '))
                    n = 0
                    for e in rows[i+1:]:
                        if e.get('type') == 'assistant':
                            for y in (e.get('message') or {}).get('content') or []:
                                if y.get('type') == 'tool_use':
                                    inp = y.get('input') or {}
                                    print('  NEXT tool_use', y.get('name'), e.get('timestamp'), json.dumps(inp)[:200])
                                    n += 1
                                elif y.get('type') == 'text':
                                    print('  NEXT text', e.get('timestamp'), y.get('text','')[:300].replace('\n',' '))
                                    n += 1
                        if n >= 4: break
