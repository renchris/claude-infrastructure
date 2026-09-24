#!/usr/bin/env python3
"""Within-context repeat rate of per-event hook injections (UserPromptSubmit / PostToolUse /
PreToolUse additionalContext elements): the share of injections whose digit-normalized content
already appeared earlier in the SAME context. A repeat re-teaches nothing new, so it bounds what a
once-per-context (or on-change-only) gate would save. MEASURED; xdup=0, visible=1.
Output: measure/hooks_repeat_rate.json + printed table.
"""

import collections
import hashlib
import importlib.util
import json
import re
import sqlite3

BASE = "/Users/chrisren/Development/.worktrees/wt-feat-token-efficiency-2026-09-23/docs/research/token-efficiency-2026-09-23"
spec = importlib.util.spec_from_file_location("hc", f"{BASE}/scripts/hooks_cost.py")
hc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hc)
x = sqlite3.connect(f"file:{BASE}/data/extract.sqlite?mode=ro", uri=True)
rows = x.execute("""SELECT file, uid FROM item WHERE xdup=0 AND visible=1 AND subkind LIKE 'hook_additional_context:%'
                    AND subkind NOT LIKE '%SessionStart%'""").fetchall()
want = collections.defaultdict(set)
for f, u in rows:
    want[f].add(u)
stat = collections.defaultdict(lambda: [0, 0, 0, 0])  # n, repeats, chars, repeat_chars
for f, uids in want.items():
    seen = collections.defaultdict(set)
    for line in open(f):
        if '"hook_additional_context"' not in line:
            continue
        r = json.loads(line)
        if r.get("type") != "attachment" or (r.get("uuid", "") + "#0") not in uids:
            continue
        for e in r["attachment"].get("content") or []:
            if not isinstance(e, str):
                continue
            sc, _ = hc.classify(e[:160])
            if sc == "unattributed":
                continue
            key = hashlib.md5(re.sub(r"\d+", "#", e).encode()).hexdigest()
            s = stat[sc]
            s[0] += 1
            s[2] += len(e)
            if key in seen[sc]:
                s[1] += 1
                s[3] += len(e)
            seen[sc].add(key)
out = {
    k: dict(
        n=v[0],
        repeats=v[1],
        repeat_share=round(v[1] / v[0], 3),
        chars=v[2],
        repeat_chars_share=round(v[3] / max(v[2], 1), 3),
    )
    for k, v in sorted(stat.items(), key=lambda kv: -kv[1][2])
}
json.dump(out, open(f"{BASE}/measure/hooks_repeat_rate.json", "w"), indent=1)
for k, v in out.items():
    print(
        f"{k[:44]:44s} n={v['n']:5d} repeat={v['repeat_share']:.2f} repeat_chars={v['repeat_chars_share']:.2f}"
    )
