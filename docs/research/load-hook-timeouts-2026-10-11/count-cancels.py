"""Count hook_cancelled records per hook command in the last N minutes.

Usage: python3 -I count-cancels.py <minutes> [since_iso] [--event NAME|all]
The event defaults to UserPromptSubmit (the Wave 1 measurement); `--event Stop` counts Stop-hook
cancels and `--event all` prints every event, one block each.
Scans transcripts (main + subagents) under every ~/.claude*/projects modified within the window.
"""

import datetime
import glob
import json
import os
import sys
import time
from collections import Counter

args = sys.argv[1:]
event = "UserPromptSubmit"
if "--event" in args:
    i = args.index("--event")
    event = args[i + 1]
    del args[i : i + 2]
mins = float(args[0])
now = datetime.datetime.now(datetime.timezone.utc)
cut = now - datetime.timedelta(minutes=mins)
if len(args) > 1:
    cut = max(cut, datetime.datetime.fromisoformat(args[1].replace("Z", "+00:00")))
home = os.path.expanduser("~")
mtime_cut = time.time() - mins * 60 - 60
by_ev, files = {}, 0
for root in glob.glob(home + "/.claude*/projects"):
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if not fn.endswith(".jsonl"):
                continue
            p = os.path.join(dp, fn)
            try:
                if os.path.getmtime(p) < mtime_cut:
                    continue
                fh = open(p, errors="replace")
            except OSError:
                continue
            files += 1
            with fh:
                for ln in fh:
                    if '"hook_cancelled"' not in ln:
                        continue
                    try:
                        r = json.loads(ln)
                    except ValueError:
                        continue
                    ts = r.get("timestamp")
                    if not ts:
                        continue
                    t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
                    if t < cut:
                        continue
                    a = r.get("attachment") or {}
                    ev = a.get("hookEvent") or "?"
                    if a.get("type") == "hook_cancelled" and event in ("all", ev):
                        cmd = os.path.basename((a.get("command") or "?").split()[0])
                        by_ev.setdefault(ev, Counter())[cmd] += 1
total = sum(sum(c.values()) for c in by_ev.values())
label = "total_ups_cancels" if event == "UserPromptSubmit" else f"total_{event}_cancels"
print(f"window_start={cut.isoformat()} files_scanned={files} {label}={total}")
for ev in sorted(by_ev):
    if event == "all":
        print(f"{ev}: {sum(by_ev[ev].values())}")
    for cmd, n in by_ev[ev].most_common():
        print(f"{n:6d}  {cmd}")
