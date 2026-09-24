#!/usr/bin/env python3
"""exp_subagent_usage.py SID... — per session: main + subagent transcripts, per-API-response usage (deduped on message.id),
plus attachment types (with char sizes) seen in each subagent transcript. No content printed."""
import json,sys,glob,os
for sid in sys.argv[1:]:
    base=glob.glob(os.path.expanduser(f'~/.claude-secondary/projects/*/{sid}.jsonl'))[0]
    files=[base]+sorted(glob.glob(base[:-6]+'/subagents/**/*.jsonl',recursive=True))
    print('==',sid)
    for f in files:
        seen=set(); rows=[]; att=[]
        for line in open(f):
            r=json.loads(line)
            if r.get('type')=='assistant':
                m=r['message']; mid=m.get('id')
                if mid in seen: continue
                seen.add(mid); u=m.get('usage',{})
                cc=u.get('cache_creation',{})
                rows.append((m.get('model'),u.get('input_tokens'),u.get('cache_read_input_tokens'),u.get('cache_creation_input_tokens'),cc.get('ephemeral_5m_input_tokens'),cc.get('ephemeral_1h_input_tokens'),u.get('output_tokens')))
            elif r.get('type')=='attachment':
                a=r['attachment']; at=a.get('type'); extra=''
                if at=='instructions': extra='['+','.join(f"{os.path.basename(x.get('path',''))}:{len(x.get('content',''))}" for x in a.get('files',[]))+']'
                att.append(f"{at}:{len(json.dumps(a))}{extra}")
        print(' ',os.path.relpath(f,os.path.dirname(base)))
        for x in rows: print('    model=%s in=%s read=%s create=%s (5m=%s 1h=%s) out=%s  prefix_total=%s'%(x+(sum(v or 0 for v in x[1:4]),)))
        print('    attachments:',att)
