# Tally model-armed cc-await-ping invocations (Bash tool_use) in the 300 most recent next transcripts:
# --idle-scoped share, --timeout values, run_in_background.
import json, re, collections, os
root='/Users/chrisren/.claude-next/projects/'
c=collections.Counter(); to=collections.Counter(); n=0
for rel in open('/tmp/lean-idle/idle-keepalive-wake/recent300.txt'):
    p=os.path.join(root,rel.strip()[2:])
    try: fh=open(p,'rb')
    except OSError: continue
    for line in fh:
        if b'cc-await-ping' not in line or b'"tool_use"' not in line: continue
        try: r=json.loads(line)
        except Exception: continue
        for b in (r.get('message') or {}).get('content') or []:
            if isinstance(b,dict) and b.get('type')=='tool_use' and b.get('name')=='Bash':
                cmd=(b.get('input') or {}).get('command','')
                if 'cc-await-ping' not in cmd or '--stand-down' in cmd: continue
                n+=1
                bg=bool((b.get('input') or {}).get('run_in_background'))
                c[('bg' if bg else 'fg', 'idle-scoped' if '--idle-scoped' in cmd else 'default')]+=1
                m=re.search(r'--timeout[ =](\d+)',cmd); to[m.group(1) if m else 'none']+=1
print('cc-await-ping arms',n); print(dict(c)); print(to.most_common(8))
