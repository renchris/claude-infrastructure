#!/usr/bin/env python3
"""A recording kitty stub with a MUTABLE `kitty @ ls`, for tests/pane-placement.bats.

argv is `@ [--to <sock>] <cmd> <args…>`. Every call is appended to $KLOG. The tree lives in
$KSTATE (kitty's `ls` JSON); `launch` mutates it exactly as kitty would for the shapes placement
uses, so a sequence of fires sees its own earlier panes:
  --type=window   the new window joins the tab of the OS window holding --match window_id:<n>
  --type=os-window  a new OS window with one tab and one window
  --type=tab      a new tab in the OS window holding --match (recorded, so a test can catch it)
Knobs: KLS_BROKEN=1 (ls prints garbage) · KFAIL_SPLIT=1 (every --type=window launch exits 1 and
creates nothing) · KSLOW_SPLIT=<s> (the FIRST --type=window launch creates its window, then sleeps
<s> before answering, so a caller's timeout kills it after the window exists).
"""

import json
import os
import sys
import time

args = sys.argv[1:]
with open(os.environ["KLOG"], "a") as f:
    f.write(" ".join(args) + "\n")
if args and args[0] == "@":
    args = args[1:]
if args[:1] == ["--to"]:
    args = args[2:]
cmd, rest = (args[0], args[1:]) if args else ("", [])
state_path = os.environ["KSTATE"]

if cmd == "ls":
    if os.environ.get("KLS_BROKEN") == "1":
        print("Error: timed out")
        sys.exit(0)
    sys.stdout.write(open(state_path).read())
    sys.exit(0)
if cmd != "launch":
    sys.exit(0)

d = json.load(open(state_path))
typ, match, uvars = "window", None, {}
i = 0
while i < len(rest):
    a = rest[i]
    if a == "--":
        break
    if a.startswith("--type="):
        typ = a.split("=", 1)[1]
    elif a == "--match":
        match = rest[i + 1]
        i += 1
    elif a == "--var":
        k, _, v = rest[i + 1].partition("=")
        uvars[k] = v
        i += 1
    i += 1

if typ == "window" and os.environ.get("KFAIL_SPLIT") == "1":
    sys.exit(1)

ids = [w["id"] for o in d for t in o["tabs"] for w in t["windows"]]
new = max(ids + [899]) + 1
win = {"id": new, "columns": 80, "user_vars": uvars}


def holder(m):
    want = int(m.split(":", 1)[1])
    for o in d:
        for t in o["tabs"]:
            if any(w["id"] == want for w in t["windows"]):
                return o, t
    return None, None


if typ == "os-window":
    oid = max([o["id"] for o in d] + [0]) + 1
    d.append(
        {"id": oid, "tabs": [{"id": oid * 100, "layout": "splits", "windows": [win]}]}
    )
elif typ == "tab":
    o, _ = holder(match)
    if o is None:
        sys.exit(1)
    o["tabs"].append(
        {
            "id": max(t["id"] for t in o["tabs"]) + 1,
            "layout": "splits",
            "windows": [win],
        }
    )
else:
    o, t = holder(match)
    if t is None:
        sys.exit(1)
    t["windows"].append(win)
json.dump(d, open(state_path, "w"))

slow = os.environ.get("KSLOW_SPLIT")
if typ == "window" and slow and not os.path.exists(state_path + ".slowed"):
    open(state_path + ".slowed", "w").close()
    time.sleep(float(slow))
print(new)
