#!/usr/bin/env python3
"""Feed every broad candidate (subagent fg Bash, timeout > 270000) to the LIVE count-only hook with its
log redirected to /tmp, so the narrow verdict is the hook's own (bash 3.2 regex), not a re-implementation.
Usage: python3 -I replay.py <bash.jsonl> <log_out> <workers>"""

import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

SRC, LOG, NW = sys.argv[1], sys.argv[2], int(sys.argv[3])
HOOK = os.path.expanduser("~/.claude/hooks/subagent-long-bash-shadow.sh")
U = {}
for l in open(SRC):
    r = json.loads(l)
    if r["bg"] or not isinstance(r["to"], (int, float)) or r["to"] <= 270000:
        continue
    U.setdefault(r["id"], r)
env = dict(os.environ, CC_SUBAGENT_LONG_BASH_LOG=LOG, CC_SUBAGENT_LONG_BASH="shadow")


def run(r):
    payload = dict(
        agent_id=r["aid"],
        agent_type="replay",
        session_id=r["sid"],
        tool_use_id=r["id"],
        transcript_path=r["tp"],
        hook_event_name="PreToolUse",
        tool_name="Bash",
        tool_input=dict(command=r["cmd"], timeout=r["to"], description="replay"),
    )
    subprocess.run(
        ["/bin/bash", HOOK],
        input=json.dumps(payload).encode(),
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=60,
    )
    return 1


n = 0
with ThreadPoolExecutor(NW) as ex:
    for _ in ex.map(run, U.values()):
        n += 1
        if n % 1000 == 0:
            sys.stderr.write("replayed %d/%d\n" % (n, len(U)))
            sys.stderr.flush()
sys.stderr.write("DONE replayed=%d\n" % n)
