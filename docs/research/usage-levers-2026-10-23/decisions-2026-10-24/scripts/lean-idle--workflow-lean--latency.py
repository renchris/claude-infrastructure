#!/usr/bin/env python3
"""End-to-end latency of the registered hook command over every unique saved Workflow script.
Runs `/usr/bin/env python3 /Users/chrisren/.claude/hooks/workflow-lean-shadow.py` (the live file)
with HOME pointed at a scratch dir so its log row lands in /tmp/lean-idle/workflow-lean/fakehome,
never in the real ~/.claude/logs. Also replays the hook's verdict per unique script.
Usage: latency.py <concurrency> <reps>"""

import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

W = "/tmp/lean-idle/workflow-lean"
HOOK = "/Users/chrisren/.claude/hooks/workflow-lean-shadow.py"
conc = int(sys.argv[1]) if len(sys.argv) > 1 else 1
reps = int(sys.argv[2]) if len(sys.argv) > 2 else 1
tag = f"c{conc}r{reps}"
FAKE = os.path.join(W, "fakehome-" + tag)
os.makedirs(FAKE, exist_ok=True)

srcs = {}


def add(src, origin):
    if not src:
        return
    h = hashlib.sha1(src.encode()).hexdigest()[:12]
    srcs.setdefault(h, (src, origin))


for p in (l.strip() for l in open(os.path.join(W, "wfjson_index.txt"))):
    try:
        d = json.load(open(p))
    except Exception:
        continue
    if (d.get("startTime") or 0) >= int(
        time.mktime(time.strptime("2026-09-24", "%Y-%m-%d")) * 1000
    ):
        add(d.get("script"), p)
for p in (l.strip() for l in open(os.path.join(W, "scripts30.txt"))):
    add(open(p, encoding="utf-8", errors="replace").read(), p)
extra = glob.glob(os.path.expanduser("~/.claude/workflows/*.*js")) + [
    p
    for p in glob.glob(
        os.path.expanduser("~/.cache/agentsync-bring-back/b13/*/*workflow*.js")
    )
    if os.stat(p).st_mtime >= time.time() - 30 * 86400
]
for p in extra:
    add(open(p, encoding="utf-8", errors="replace").read(), p)
items = sorted(srcs.items())
print(f"unique scripts {len(items)} (extra files {len(extra)})", file=sys.stderr)

env = dict(os.environ, HOME=FAKE)
env.pop("CC_WORKFLOW_SHADOW", None)


def one(arg):
    h, (src, origin), rep = arg
    payload = json.dumps(
        {
            "session_id": f"replay-{h}",
            "tool_use_id": f"r{rep}",
            "cwd": "/tmp",
            "tool_name": "Workflow",
            "hook_event_name": "PreToolUse",
            "tool_input": {"script": src},
        }
    )
    t = time.perf_counter()
    p = subprocess.run(
        ["/usr/bin/env", "python3", HOOK],
        input=payload.encode(),
        capture_output=True,
        env=env,
        timeout=30,
    )
    wall = (time.perf_counter() - t) * 1000
    return dict(
        sha=h,
        origin=origin,
        rep=rep,
        chars=len(src),
        wall_ms=round(wall, 2),
        rc=p.returncode,
        stdout=len(p.stdout),
        stderr=p.stderr[:200].decode(errors="replace"),
    )


args = [(h, v, r) for r in range(reps) for h, v in items]
t0 = time.time()
with ThreadPoolExecutor(conc) as ex:
    res = list(ex.map(one, args))
with open(os.path.join(W, f"latency-{tag}.jsonl"), "w") as f:
    for r in res:
        f.write(json.dumps(r) + "\n")
w = sorted(r["wall_ms"] for r in res)


def q(p):
    return w[min(len(w) - 1, int(p * len(w)))]


print(
    json.dumps(
        dict(
            tag=tag,
            n=len(w),
            p50=q(0.5),
            p90=q(0.9),
            p99=q(0.99),
            max=w[-1],
            over_1s=sum(x > 1000 for x in w),
            over_5s=sum(x > 5000 for x in w),
            nonzero_rc=sum(r["rc"] != 0 for r in res),
            stdout_bytes=sum(r["stdout"] for r in res),
            secs=round(time.time() - t0, 1),
        )
    )
)
