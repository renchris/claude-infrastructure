# For sessions in loop_asks.json: find genuine operator prompts that follow an assistant
# "complete"-type claim, and test each against the protocol's widened completeness regex (SYNTHESIS §7.1).
import json,re,glob,os,collections
Q = re.compile(r'100\.00\s*/\s*100\.00|100\s*/\s*100|are we (100%? )?(complete|done)|100% complete|absolute perfection|100th|perfect|exhaust|take[- ]?back|nothing left|good to close', re.I)
CLAIM = re.compile(r'Good to close:\s*yes|✅ Complete|safe to close|exhaustively done|100\.00\s*/\s*100\.00 complete|Complete & live', re.I)
asks=json.load(open('/tmp/rescomp/loop_asks.json'))
sids=sorted(set(a['sid'] for a in asks))
def best(sid):
    fs=glob.glob(os.path.expanduser(f'~/.claude*/projects/*/{sid}.jsonl'))
    fs=[f for f in fs if os.path.getsize(f)>100000] or fs
    return max(fs,key=os.path.getsize) if fs else None
rows=[]
for sid in sids:
    f=best(sid)
    if not f: continue
    last_claim=None
    for l in open(f,'rb'):
        try: r=json.loads(l)
        except: continue
        if r.get('type')=='assistant':
            for b in (r.get('message') or {}).get('content') or []:
                if isinstance(b,dict) and b.get('type')=='text' and CLAIM.search(b.get('text','')):
                    last_claim=r.get('timestamp','')
        elif r.get('type')=='user' and not r.get('isMeta'):
            c=(r.get('message') or {}).get('content')
            if not isinstance(c,str) or c.lstrip().startswith('<') or c.startswith('[') or 'Workflow harness' in c or len(c)>3000: continue
            if last_claim:
                rows.append({'sid':sid[:8],'ts':r.get('timestamp',''),'claim_ts':last_claim,'match':bool(Q.search(c)),'text':c.replace('\n',' ')[:260]})
                last_claim=None
print('prompts immediately following a done-claim:',len(rows))
print(collections.Counter(r['match'] for r in rows))
json.dump(rows,open('/tmp/rescomp/adv_opscope_bypass.json','w'),indent=1,ensure_ascii=False)
for r in rows:
    if not r['match']: print(r['sid'],r['ts'],'|',r['text'][:230])
