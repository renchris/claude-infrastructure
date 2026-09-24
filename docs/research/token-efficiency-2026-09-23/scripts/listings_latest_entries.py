#!/usr/bin/env python3
"""Per-entry (name, rendered length, described?) of the most recent INITIAL skill_listing in a
main session of a given project slug. Stores lengths only, no description text.
Usage: python3 listings_latest_entries.py <extract.sqlite> <project_slug_substring> <out.json>"""
import json, re, sqlite3, sys
DB, SLUG, OUT = sys.argv[1:4]
con = sqlite3.connect(DB)
rows = con.execute("""select c.file, max(c.last_ts) from ctx c join item i on i.file=c.file
  where c.ctx_type='main' and c.project_slug like ? and i.subkind='skill_listing' and i.xdup=0
    and i.detail like '%initial=True%' group by c.file order by 2 desc limit 5""", (f'%{SLUG}%',)).fetchall()
for f, _ in rows:
    best = None
    for line in open(f, 'rb'):
        if b'"skill_listing"' not in line:
            continue
        r = json.loads(line)
        a = r.get('attachment') or {}
        if a.get('type') == 'skill_listing' and a.get('isInitial'):
            best = (r, a)
    if not best:
        continue
    r, a = best
    txt = ''.join((x or {}).get('content', '') for x in (r.get('rendered') or []))
    ents = []
    for l in txt.split('\n'):
        m = re.match(r'^- (\S+?)(?:: (.*))?$', l)
        if m:
            ents.append(dict(name=m.group(1), chars=len(l), described=m.group(2) is not None))
    json.dump(dict(file=f, ts=r.get('timestamp'), version=r.get('version'), total_chars=len(txt),
                   entries=ents), open(OUT, 'w'), indent=1)
    print(f, r.get('timestamp'), r.get('version'), len(txt), len(ents), sum(e['described'] for e in ents))
    break
