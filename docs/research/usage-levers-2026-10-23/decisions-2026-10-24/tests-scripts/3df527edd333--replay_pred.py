#!/usr/bin/env python3
"""Run the d9ffc3964 shadow predicate (reviewer's byte-identical copy) on the 20 original calls and
the 20 simulated re-issues, as a subagent foreground payload. Log redirected under this dir.
Usage: python3 -I replay_pred.py <sample.json> <sims.jsonl> <shadow.sh> <log>"""

import json, os, subprocess, sys

S = json.load(open(sys.argv[1]))
sims = [json.loads(l) for l in open(sys.argv[2])]
sh, log = sys.argv[3], sys.argv[4]
if os.path.exists(log):
    os.rename(log, log + ".prev")
env = dict(os.environ, CC_SUBAGENT_LONG_BASH_LOG=log, CC_SUBAGENT_LONG_BASH="shadow")


def run(tag, cmd, to):
    p = {
        "agent_id": "replay-" + tag,
        "agent_type": "conv-test",
        "session_id": "conv-test",
        "tool_use_id": tag,
        "transcript_path": "-",
        "tool_input": {"command": cmd, "timeout": to},
    }
    subprocess.run(
        ["/bin/bash", sh], input=json.dumps(p), text=True, env=env, capture_output=True
    )


for n, r in enumerate(S, 1):
    run("orig%02d" % n, r["cmd"], r["to"])
for s in sims:
    run("sim%02d" % s["n"], s["call"]["command"], s["call"]["timeout"])
rows = [json.loads(l) for l in open(log)] if os.path.exists(log) else []
o = [x for x in rows if x["tool_use_id"].startswith("orig")]
si = [x for x in rows if x["tool_use_id"].startswith("sim")]
print(
    "originals logged: %d/20, narrow poll-loop: %d"
    % (len(o), sum(1 for x in o if x.get("why") == "poll-loop"))
)
print("re-issues logged (would be judged again): %d/20" % len(si))
