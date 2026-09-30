"""For each genuine human completeness ask (ca_scan Q), measure the assistant turn that follows:
tool calls issued before the next human prompt (esp. Agent/Task/Workflow spawns = an in-turn re-audit),
and whether a YES-opening reply also introduces a new/remaining item (the '<=3 lines' leak)."""
import json, re, glob, os, collections
Q = re.compile(r'100\.00\s*/\s*100\.00|100\s*/\s*100|are we (100%? )?(complete|done)|100% complete|absolute perfection', re.I)
YES = re.compile(r'^\W*(✅|yes\b|good to close:\s*yes)', re.I)
NO = re.compile(r'^\W*(no\b|not yet|not quite|actually|almost|close,? but|nearly|🔧|⛔|📦|good to close:\s*no)', re.I)
ITEM = re.compile(r"\b(one|two|three|a few|several) (more|remaining|small|other|last) (thing|item|gap|hole|check|step|caveat)s?\b|worth (noting|flagging)|one caveat|\bexcept\b|still open|not yet (run|verified|measured|built|live)|follow-on: (?!none)", re.I)
SPAWN = {'Agent','Task','Workflow'}
stats=collections.Counter(); ex=collections.defaultdict(list)
for f in glob.glob(os.path.expanduser('~/.claude*/projects/*/*.jsonl')):
    try: recs=[json.loads(l) for l in open(f,'rb') if b'"type":"' in l]
    except Exception: continue
    for i,r in enumerate(recs):
        if r.get('type')!='user' or r.get('isMeta'): continue
        c=(r.get('message') or {}).get('content')
        if not isinstance(c,str) or c.lstrip().startswith('<') or 'Workflow harness' in c or len(c)>4000 or not Q.search(c): continue
        tools=[]; text=''
        for r2 in recs[i+1:]:
            if r2.get('type')=='user':
                c2=(r2.get('message') or {}).get('content')
                if isinstance(c2,str) and not r2.get('isMeta') and not c2.lstrip().startswith('<'): break
                continue
            if r2.get('type')!='assistant': continue
            for b in (r2.get('message') or {}).get('content') or []:
                if not isinstance(b,dict): continue
                if b.get('type')=='tool_use': tools.append(b.get('name',''))
                elif b.get('type')=='text' and not text.strip(): text=b.get('text','')
                elif b.get('type')=='text': text=text  # first text only for opening class
        # final text = last text block in turn
        last=''
        for r2 in recs[i+1:]:
            if r2.get('type')=='user':
                c2=(r2.get('message') or {}).get('content')
                if isinstance(c2,str) and not r2.get('isMeta') and not c2.lstrip().startswith('<'): break
                continue
            if r2.get('type')=='assistant':
                for b in (r2.get('message') or {}).get('content') or []:
                    if isinstance(b,dict) and b.get('type')=='text' and b.get('text','').strip(): last=b['text']
        stats['asks']+=1
        if tools: stats['asks_with_tool_calls']+=1
        if any(t in SPAWN for t in tools): stats['asks_with_subagent_or_workflow_spawn']+=1; ex['spawn'].append((r.get('timestamp','')[:19],os.path.basename(f)[:8]))
        if YES.search(last.strip()):
            stats['final_reply_opens_yes']+=1
            if ITEM.search(last): stats['yes_reply_that_also_names_an_item']+=1; ex['yesitem'].append((r.get('timestamp','')[:19],os.path.basename(f)[:8],ITEM.search(last).group(0),last[:140].replace('\n',' ')))
        elif NO.search(last.strip()): stats['final_reply_opens_no']+=1
        stats['tool_calls_total']+=len(tools)
for k,v in stats.items(): print(k,v)
print("spawn examples:",ex['spawn'][:8])
for e in ex['yesitem'][:10]: print("YES+item:",e)
