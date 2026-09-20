#!/usr/bin/env python3
"""One stop-failure marker row, derived from a fixture transcript (tests/lr-fleet.bats mark()).

A fixture that states the death twice — once in the transcript the slow scan reads, once in the
marker the census reads — can hand the two producers different facts, and the both-paths diff
would then be measuring the fixture rather than the implementations. Derived, so it cannot.
"""
import json
import sys

tx, sid, cfg, cwd, pane = sys.argv[1:6]
ts = txt = err = None
for line in open(tx):
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("type") == "assistant" and d.get("isApiErrorMessage"):
        m = d.get("message") or {}
        c = m.get("content")
        txt = c if isinstance(c, str) else " ".join(
            x.get("text", "") for x in (c or []) if isinstance(x, dict))
        ts, err = d.get("timestamp"), d.get("error") or "rate_limit"
if ts:
    print(json.dumps({"session_id": sid, "ts": ts, "config_dir": cfg, "pane": pane,
                      "cwd": cwd, "transcript_path": tx, "error": err,
                      "last_assistant_message": txt}))
