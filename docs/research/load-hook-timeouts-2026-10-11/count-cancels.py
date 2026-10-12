"""Count UserPromptSubmit hook_cancelled records per hook command in the last N minutes.

Usage: python3 -I count-cancels.py <minutes> [since_iso]
Scans transcripts (main + subagents) under every ~/.claude*/projects modified within the window.
"""

import datetime
import glob
import json
import os
import sys
import time
from collections import Counter

mins = float(sys.argv[1])
now = datetime.datetime.now(datetime.timezone.utc)
cut = now - datetime.timedelta(minutes=mins)
if len(sys.argv) > 2:
    cut = max(cut, datetime.datetime.fromisoformat(sys.argv[2].replace("Z", "+00:00")))
home = os.path.expanduser("~")
mtime_cut = time.time() - mins * 60 - 60
by_cmd, prompts, files = Counter(), 0, 0
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
                    if '"UserPromptSubmit"' not in ln:
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
                    if (
                        a.get("type") == "hook_cancelled"
                        and a.get("hookEvent") == "UserPromptSubmit"
                    ):
                        by_cmd[os.path.basename(a.get("command", "?").split()[0])] += 1
print(
    f"window_start={cut.isoformat()} files_scanned={files} total_ups_cancels={sum(by_cmd.values())}"
)
for cmd, n in by_cmd.most_common():
    print(f"{n:6d}  {cmd}")
