#!/usr/bin/env python3
"""exp_attach_diff.py SID... — for each experiment session transcript, list attachment/record types and char sizes (no content)."""
import json,sys,glob,os
for sid in sys.argv[1:]:
    fs=glob.glob(os.path.expanduser(f'~/.claude-secondary/projects/*/{sid}.jsonl'))
    print('==',sid,fs[:1])
    for f in fs[:1]:
        for line in open(f):
            r=json.loads(line); t=r.get('type')
            if t=='attachment':
                a=r['attachment']; at=a.get('type')
                s=len(json.dumps(a))
                extra=''
                if at=='deferred_tools_delta': extra=f" n_added={len(a.get('addedNames',a.get('added',[])) or [])}"
                if at=='instructions': extra=' files='+','.join(os.path.basename(x.get('path','')) for x in a.get('files',[]))
                print(f'  attachment {at} chars={s}{extra}')
            elif t in('user','assistant','system'):
                m=r.get('message',{}); c=m.get('content')
                print(f'  {t} chars={len(json.dumps(c))} usage={m.get("usage",{}).get("cache_read_input_tokens")}/{m.get("usage",{}).get("cache_creation_input_tokens")}' if t=='assistant' else f'  {t} chars={len(json.dumps(c))}')
