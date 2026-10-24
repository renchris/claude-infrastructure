import json, sys, collections, os
from concurrent.futures import ProcessPoolExecutor
CUT = "2026-09-24"
def scan(p):
    out = []
    try:
        fh = open(p, 'rb')
    except OSError:
        return out
    with fh:
        for line in fh:
            if b'"name":"Workflow"' not in line or b'"tool_use"' not in line:
                continue
            try: d = json.loads(line)
            except Exception: continue
            if d.get('type') != 'assistant': continue
            ts = d.get('timestamp') or ''
            if ts < CUT: continue
            for c in (d.get('message') or {}).get('content') or []:
                if isinstance(c, dict) and c.get('type') == 'tool_use' and c.get('name') == 'Workflow':
                    inp = c.get('input') or {}
                    out.append(dict(p=p, ts=ts, sid=d.get('sessionId'), keys=sorted(inp.keys()),
                        script_len=len(inp.get('script') or '') if isinstance(inp.get('script'), str) else None,
                        name=inp.get('name'), scriptPath=inp.get('scriptPath'), id=c.get('id'),
                        entry=d.get('entrypoint'), side=d.get('isSidechain'), team=d.get('teamName'), agentName=d.get('agentName'),
                        ver=d.get('version')))
    return out
if __name__ == '__main__':
    files = [l.strip() for l in open('/tmp/lean-idle/workflow-lean/review-mechanism/wfcall_files.txt')]
    rows = []
    with ProcessPoolExecutor(8) as ex:
        for r in ex.map(scan, files, chunksize=20):
            rows.extend(r)
    with open('/tmp/lean-idle/workflow-lean/review-mechanism/wfcalls.jsonl', 'w') as fh:
        for r in rows: fh.write(json.dumps(r) + '\n')
    print('calls', len(rows))
    print('keys', collections.Counter(tuple(r['keys']) for r in rows).most_common(10))
    print('entry', collections.Counter(r['entry'] for r in rows).most_common())
    print('team', collections.Counter(bool(r['team']) for r in rows), 'agentName', collections.Counter(bool(r['agentName']) for r in rows))
    print('script_len None', sum(r['script_len'] is None for r in rows))
    print('DONE')
