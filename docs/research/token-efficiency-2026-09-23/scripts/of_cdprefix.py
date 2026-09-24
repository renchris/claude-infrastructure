#!/usr/bin/env python3
"""of_cdprefix.py — input-side companion of the cwd-reset finding: how many Bash commands open with
`cd <absolute path> &&|;|newline`, and how many characters those prefixes cost, by ctx_type.
Uses tr.cmd (first 300 chars of each command, from of_scan.py); xdup=0. Characters are what the
model WROTE (output tokens) and then carries in context (tool_use_input persists like a result)."""
import os, re, sqlite3
D = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")
db = sqlite3.connect(os.path.join(D, "output_formats.sqlite")); db.execute("ATTACH ? AS x", (os.path.join(D, "extract.sqlite"),))
CD = re.compile(r"^\s*cd\s+(\"[^\"]*\"|'[^']*'|\S+)\s*(&&|;|\n)\s*")
agg = {}
for ct, cmd, reset in db.execute("""SELECT c.ctx_type, t.cmd, t.cwd_reset FROM tr t JOIN x.item i ON i.file=t.file AND i.tool_use_id=t.tool_use_id AND i.kind='tool_result'
                                    JOIN x.ctx c ON c.file=t.file WHERE t.tool='Bash' AND i.xdup=0"""):
    a = agg.setdefault(ct, [0, 0, 0, 0])
    a[0] += 1
    m = CD.match(cmd or "")
    if m and m.group(1).strip("\"'").startswith(("/", "~", "$HOME")):
        a[1] += 1; a[2] += len(m.group(0))
    if reset: a[3] += 1
for ct, (n, ncd, ch, nr) in agg.items():
    print("%-15s bash=%7d  cd-abs-prefixed=%7d (%.0f%%)  prefix_chars=%9d  cwd_reset_notes=%6d" % (ct, n, ncd, 100 * ncd / n, ch, nr))
