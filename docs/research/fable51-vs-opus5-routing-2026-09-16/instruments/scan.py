import json,os,sys,collections,subprocess
root=os.path.expanduser('~/.claude-tertiary/projects')
files=subprocess.run(['find',root,'-name','*.jsonl','-newermt','2026-09-01 00:00'],capture_output=True,text=True).stdout.split('\n')
files=[f for f in files if f]
agg=collections.defaultdict(lambda: collections.Counter())
nfile=0
for f in files:
    nfile+=1
    try:
        fh=open(f,'r',errors='replace')
    except Exception: continue
    with fh:
        for line in fh:
            if '"usage"' not in line: continue
            if '2026-09-' not in line: continue
            try: d=json.loads(line)
            except Exception: continue
            if d.get('type')!='assistant': continue
            m=d.get('message') or {}
            u=m.get('usage') or {}
            if not u: continue
            ts=d.get('timestamp') or ''
            if not ts.startswith('2026-09-'): continue
            model=m.get('model') or 'unknown'
            hour=ts[:16]
            c=agg[(hour,model)]
            c['in']+=u.get('input_tokens',0) or 0
            c['out']+=u.get('output_tokens',0) or 0
            c['cc']+=u.get('cache_creation_input_tokens',0) or 0
            c['cr']+=u.get('cache_read_input_tokens',0) or 0
            c['n']+=1
print("files scanned",nfile, file=sys.stderr)
out=[]
for (hour,model),c in sorted(agg.items()):
    out.append({'hour':hour,'model':model,**dict(c)})
json.dump(out,open('next3-minute-tokens.json','w'))
print("rows",len(out))
models=collections.Counter()
for r in out: models[r['model']]+=r['n']
print(models.most_common())
