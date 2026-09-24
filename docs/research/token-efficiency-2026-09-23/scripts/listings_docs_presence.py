#!/usr/bin/env python3
"""Share of contexts, per start day, whose mcp_instructions_delta names the claude.ai Claude Docs
connector (xdup=0 files). Counts only. Usage: python3 listings_docs_presence.py <extract.sqlite>"""
import json, sqlite3, sys, collections
con = sqlite3.connect(sys.argv[1])
files = con.execute("""select distinct c.file, substr(c.first_ts,1,10) from ctx c join item i on i.file=c.file
  where i.kind='attachment' and i.subkind='mcp_instructions_delta' and i.xdup=0""").fetchall()
tot, hit = collections.Counter(), collections.Counter()
for f, day in files:
    tot[day] += 1
    for line in open(f, 'rb'):
        if b'mcp_instructions_delta' in line:
            r = json.loads(line)
            if (r.get('attachment') or {}).get('type') == 'mcp_instructions_delta':
                txt = ''.join((x or {}).get('content', '') for x in (r.get('rendered') or []))
                if 'Claude Docs' in txt:
                    hit[day] += 1
                break
for d in sorted(tot):
    print(d, tot[d], hit[d], round(hit[d] / tot[d], 2))
