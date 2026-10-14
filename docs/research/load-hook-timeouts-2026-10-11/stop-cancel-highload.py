"""Stop-hook cancel rate in the minutes when 1-min load was >= THRESH, from history.

Usage: python3 -I stop-cancel-highload.py <since-iso> [thresh=300]
Load per minute: ~/.claude/logs/capacity-alarm.jsonl (load_1m). Hook records: every transcript
(main + subagents) under ~/.claude*/projects modified since <since>. A Stop hook RUN is any
attachment with hookEvent == "Stop"; a CANCEL is one whose type is hook_cancelled.
"""

import collections
import datetime as dt
import glob
import json
import os
import sys

since = sys.argv[1]
thresh = float(sys.argv[2]) if len(sys.argv) > 2 else 300.0
P = lambda s: dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
t_since = P(since)

hi_min = set()
lo_min = set()
for line in open(os.path.expanduser("~/.claude/logs/capacity-alarm.jsonl")):
    try:
        r = json.loads(line)
    except ValueError:
        continue
    ts, v = r.get("ts"), r.get("load_1m")
    if not ts or not isinstance(v, (int, float)):
        continue
    t = P(ts)
    if t < t_since:
        continue
    key = t.replace(second=0, microsecond=0)
    (hi_min if v >= thresh else lo_min).add(key)
lo_min -= hi_min

runs = {"hi": collections.Counter(), "lo": collections.Counter()}
canc = {"hi": collections.Counter(), "lo": collections.Counter()}
mtime_cut = t_since.timestamp() - 60
for root in glob.glob(os.path.expanduser("~") + "/.claude*/projects"):
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
            with fh:
                for line in fh:
                    if '"Stop"' not in line:
                        continue
                    try:
                        r = json.loads(line)
                    except ValueError:
                        continue
                    a = r.get("attachment") or {}
                    if a.get("hookEvent") != "Stop" or not r.get("timestamp"):
                        continue
                    t = P(r["timestamp"])
                    if t < t_since:
                        continue
                    m = t.replace(second=0, microsecond=0)
                    band = "hi" if m in hi_min else ("lo" if m in lo_min else None)
                    if not band:
                        continue
                    cmd = os.path.basename(
                        (a.get("command") or a.get("hookName") or "?").split()[0]
                    )
                    runs[band][cmd] += 1
                    if a.get("type") == "hook_cancelled":
                        canc[band][cmd] += 1

print(
    f"since={since} thresh={thresh} minutes_hi={len(hi_min)} minutes_lo={len(lo_min)}"
)
for band in ("hi", "lo"):
    tr, tc = sum(runs[band].values()), sum(canc[band].values())
    print(
        f"\n[{band}] Stop hook records={tr} cancels={tc} rate={100 * tc / max(tr, 1):.2f}%"
    )
    for cmd in (
        "operator-readout.sh",
        "session-continue.sh",
        "boundary-handoff.sh",
        "completion-assert.sh",
    ):
        print(f"   {cmd:24s} records={runs[band][cmd]:6d} cancels={canc[band][cmd]:4d}")
