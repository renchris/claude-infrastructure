import json,sys
rows=[]; bad=0
for line in open('/Users/chrisren/.reso/curl-audit.jsonl'):
    try: r=json.loads(line)
    except Exception: bad+=1; continue
    ts=r.get('ts','')
    if '2026-09-25T02:22:56' <= ts < '2026-09-29T00:00:00': rows.append(r)
json.dump(rows,open('window.json','w'))
print('bad_lines',bad,'window_rows',len(rows))
