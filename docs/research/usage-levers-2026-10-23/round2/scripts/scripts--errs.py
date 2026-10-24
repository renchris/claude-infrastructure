#!/usr/bin/env python3
# For main busts with gap 1-2h: look between the two requests for API-error / usage-limit / permission records.
import json, collections, re
G={(g['rel'],g['ts']):g for g in map(json.loads,open('/tmp/usage-audit/r2/cache-rebuilds/gaps.jsonl'))}
R=[json.loads(l) for l in open('/tmp/usage-audit/r2/cache-rebuilds/mainstate.jsonl')]
sel=[r for r in R if 3600<r['gap']<=7200 and r['bust']]
cnt=collections.Counter(); ex=collections.defaultdict(list)
cache={}
for r in sel:
    g=G[(r['rel'],r['ts'])]; p=g['root']+'/'+g['rel']
    if p not in cache: cache[p]=open(p,errors='replace').read().splitlines()
    L=cache[p]
    b=next(i for i,l in enumerate(L) if g['mid'] in l)
    a=max(i for i,l in enumerate(L[:b]) if g['prev_mid'] in l)
    flags=set()
    for l in L[a+1:b]:
        if '"isApiErrorMessage":true' in l or '"error":' in l and '"type":"assistant"' in l: flags.add('api_error')
        if re.search(r'usage limit|rate.limit|limit reached|resets? at', l, re.I) and '"type":"assistant"' in l: flags.add('limit_msg')
        if '[limit-recover] Moved from' in l: flags.add('limit_recover_move')
        if 'The Mac rebooted' in l: flags.add('reboot_restore')
        if '"type":"attachment"' in l and 'permission' in l.lower(): flags.add('perm:'+(re.search(r'"attachment":\{"type":"([a-z_]+)"',l) or re.search('(x)','x')).group(1))
        if 'away_summary' in l: flags.add('away_summary')
    st='A' if r['fg_pending'] else ('B' if any(x['kind']=='watcher' for x in r['live']) else ('C' if r['live'] else 'D'))
    k=(st,'+'.join(sorted(flags - {'away_summary'})) or '-'); cnt[k]+=1
    if flags & {'api_error','limit_msg'} and len(ex[k])<2: ex[k].append(r['rel'][-50:]+' '+r['ts'])
for k,v in sorted(cnt.items()): print(k,v, ex.get(k,''))
