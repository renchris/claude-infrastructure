import json, collections, sys
from concurrent.futures import ProcessPoolExecutor
calls=[json.loads(l) for l in open('/tmp/lean-idle/workflow-lean/review-mechanism/wfcalls.jsonl')]
files=sorted({c['p'] for c in calls})
def scan(p):
    msgs=collections.defaultdict(list)
    for line in open(p,'rb'):
        if b'"tool_use"' not in line or b'"assistant"' not in line: continue
        try: d=json.loads(line)
        except Exception: continue
        if d.get('type')!='assistant' or (d.get('timestamp') or '')<'2026-09-24': continue
        m=d.get('message') or {}
        for c in m.get('content') or []:
            if isinstance(c,dict) and c.get('type')=='tool_use':
                inp=c.get('input') or {}
                tag=c['name']
                if tag=='Bash' and inp.get('run_in_background'): tag='Bash(bg)'
                msgs[m.get('id')].append(tag)
    out=[]
    for mid,names in msgs.items():
        if 'Workflow' in names: out.append([n for n in names if n!='Workflow'])
    return out
def main():
  res=[]
  with ProcessPoolExecutor(8) as ex:
    for r in ex.map(scan, files, chunksize=4): res.extend(r)
  print('assistant messages with a Workflow call', len(res), 'with a sibling tool call', sum(1 for r in res if r))
  print(collections.Counter(n for r in res for n in r).most_common(10))

if __name__ == '__main__':
  main()
