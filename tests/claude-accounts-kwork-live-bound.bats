#!/usr/bin/env bats
# claude-accounts — the working census is capped at the live processes (bound_kwork).
#
# working_concurrency counts transcripts written in the last KWORK_WINDOW_MIN minutes, which is
# THROUGHPUT: a headless `claude -p` job that exited nine minutes ago still counts. Measured
# 2026-09-25: an eval harness running short headless jobs back to back made every account read
# 18-21 top-level "working" transcripts against 2-4 live processes, so all three healthy accounts
# were refused kmax-concurrency (KMAX 8) and the router abstained. These cases pin the physical
# ceiling (top-level term <= live processes incl. headless), the subagent carve-out, the
# plain-dict no-op that keeps every older stub valid, and the kill switch. The first case is the
# control: it fails on the pre-fix tree, where bound_kwork does not exist.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export CA_BIN="$REPO/bin/claude-accounts"
}

_pre() {
  cat <<'PY'
import importlib.machinery, importlib.util, os
_ld = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", _ld))
_ld.exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "ca.log")
PY
}

@test "bound_kwork: finished headless jobs no longer count as working sessions" {
  run python3 -c "$(_pre)"'
counts = ca._Census({"a": 2}, headless={"a": 1})     # 2 interactive + 1 headless live
wc = ca._Census({"a": 21}, top={"a": 21})            # 21 top-level transcripts in the window
row = {"k_work": 21}
ca.bound_kwork(row, "a", counts, wc)
assert row["k_work"] == 3, row
assert row["k_work_raw"] == 21, row
R = {"KMAX": 8, "KMAX_RESIDENT": 40}
assert ca.k_eff(row) < ca.k_cap(dict(row, k=2), R), "still refused kmax-concurrency"
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "bound_kwork: subagent transcripts stay uncapped (they share their parent process)" {
  run python3 -c "$(_pre)"'
counts = ca._Census({"a": 4}, headless={"a": 0})
wc = ca._Census({"a": 28}, top={"a": 18})            # 18 top-level + 10 subagent
row = {"k_work": 28}
ca.bound_kwork(row, "a", counts, wc)
assert row["k_work"] == 4 + 10, row
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "bound_kwork: never raises the count, and a live count above the walk changes nothing" {
  run python3 -c "$(_pre)"'
counts = ca._Census({"a": 9}, headless={"a": 3})
wc = ca._Census({"a": 5}, top={"a": 5})
row = {"k_work": 5}
ca.bound_kwork(row, "a", counts, wc)
assert row == {"k_work": 5}, row
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "bound_kwork: plain dicts (older callers and test stubs) and unmeasured inputs are a no-op" {
  run python3 -c "$(_pre)"'
for counts, wc, kw in [({"a": 1}, {"a": 21}, 21),                       # no split carried
                       (None, ca._Census({"a": 21}, top={"a": 21}), 21), # ps unmeasured
                       (ca._Census({"a": 1}, headless={"a": 0}), None, None)]:  # walk over budget
    row = {"k_work": kw}
    ca.bound_kwork(row, "a", counts, wc)
    assert row == {"k_work": kw}, (row, counts, wc)
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "bound_kwork: CC_ROUTE_KWORK_LIVE_BOUND=off restores the raw census" {
  CC_ROUTE_KWORK_LIVE_BOUND=off run python3 -c "$(_pre)"'
row = {"k_work": 21}
ca.bound_kwork(row, "a", ca._Census({"a": 2}, headless={"a": 1}), ca._Census({"a": 21}, top={"a": 21}))
assert row == {"k_work": 21}, row
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "concurrency: a headless claude -p is tallied as headless, never as interactive" {
  run python3 -c "$(_pre)"'
import types
cfg = {"accounts": [{"name": "a", "config_dir": "/tmp/cfg-a"}]}
ps_out = ("/opt/bin/claude --model x CLAUDE_CONFIG_DIR=/tmp/cfg-a\n"
          "/opt/bin/claude -p hello CLAUDE_CONFIG_DIR=/tmp/cfg-a\n"
          "/opt/bin/claude --print hi CLAUDE_CONFIG_DIR=/tmp/cfg-a\n"
          "/opt/bin/claude --version CLAUDE_CONFIG_DIR=/tmp/cfg-a\n")
ca.subprocess.run = lambda *a, **k: types.SimpleNamespace(stdout=ps_out)
c = ca.concurrency(cfg)
assert dict(c) == {"a": 1}, dict(c)
assert c.headless == {"a": 2}, c.headless
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ---- WHAT "WORKING" MEANS (FLEET_V2 W6 D1.8) ---------------------------------------------------
# 2026-09-29 06:16:09Z logged k_work next=14 / next4=11 against KMAX 8 while ~3-5 / ~2 sessions
# were in flight: the mtime census counted every subagent file a FINISHED agent had written in the
# last 10 min, and bound_kwork caps only the top-level term. Replayed on the same transcripts the
# new rule reads 3 and 7 (docs/research/lr-fleet-v2-decisions-2026-09-30/kmax-rebase.md). Each case
# below FAILS on the pre-fix tree, where every fresh file counts.

_kw() {
  # the leading blank line survives $( ) and separates this from _pre's last line
  cat <<'PY'

import json, os, time
from datetime import datetime, timezone
NOW = time.time()
def iso(t): return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
BASE = os.path.join(os.environ["BATS_TEST_TMPDIR"], "cfg")
SLUG = os.path.join(BASE, "projects", "slug")
os.makedirs(SLUG, exist_ok=True)
CFG = {"accounts": [{"name": "a", "config_dir": BASE}]}
def user(ago, text="go"):
    return {"type": "user", "timestamp": iso(NOW - ago), "message": {"role": "user", "content": text}}
def said(ago, text="done"):
    return {"type": "assistant", "timestamp": iso(NOW - ago),
            "message": {"role": "assistant", "content": [{"type": "text", "text": text}]}}
def tool(ago):
    return {"type": "assistant", "timestamp": iso(NOW - ago),
            "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t", "name": "Bash", "input": {}}]}}
def attach(ago):
    return {"type": "attachment", "timestamp": iso(NOW - ago), "attachment": {"k": 1}}
def write(path, recs, mtime_ago=0):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for r in recs: f.write(json.dumps(r, separators=(",", ":")) + "\n")
    os.utime(path, (NOW - mtime_ago, NOW - mtime_ago))
def sub(sid, aid, recs, wf=None, **kw):
    d = os.path.join(SLUG, sid, "subagents") if wf is None else os.path.join(SLUG, sid, "subagents", "workflows", wf)
    write(os.path.join(d, f"agent-{aid}.jsonl"), recs, **kw)
def census(**kw):
    c = ca.working_concurrency(CFG, window_min=10, budget_s=30.0, **kw)
    return c["a"], c.top["a"]
PY
}

@test "D1.8: a subagent that has written its final answer no longer counts; one mid-work does" {
  run python3 -c "$(_pre)$(_kw)"'
write(os.path.join(SLUG, "s1.jsonl"), [user(60), tool(30)])            # parent, waiting on Agent
sub("s1", "done1", [user(300), tool(200), user(190), said(120)])      # finished 2 min ago
sub("s1", "busy1", [user(300), tool(100), user(90)])                  # the model owes a reply
sub("s1", "tool1", [user(300), tool(20)])                             # waiting on its own tool
sub("s1", "big1", [user(300), said(100, "x" * 100000)])               # final answer > the 64 KiB first read
assert census() == (3, 1), census()
os.environ["CC_ROUTE_KWORK_TURNS"] = "off"                            # the old mtime census
assert census() == (5, 1), census()
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "D1.8: a workflow agent ending on its tool call is settled only by its run journal" {
  run python3 -c "$(_pre)$(_kw)"'
write(os.path.join(SLUG, "s2.jsonl"), [user(60), said(50)])
sub("s2", "wfa", [user(300), tool(40)], wf="wf_1")
sub("s2", "wfb", [user(300), tool(40)], wf="wf_1")
jr = os.path.join(SLUG, "s2", "subagents", "workflows", "wf_1", "journal.jsonl")
with open(jr, "w") as f:
    f.write(json.dumps({"type": "started", "agentId": "wfa", "timestamp": iso(NOW - 300)}, separators=(",", ":")) + "\n")
    f.write(json.dumps({"type": "result", "agentId": "wfa", "timestamp": iso(NOW - 35),
                        "result": "{\"agentId\":\"wfb\",\"type\":\"result\"}"}, separators=(",", ":")) + "\n")
# wfa has a bare result row; wfb appears only INSIDE an escaped payload, which must not settle it.
assert census() == (2, 1), census()
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "D1.8: a parent task-notification settles its agent, unless the agent wrote after it" {
  run python3 -c "$(_pre)$(_kw)"'
note = lambda aid, ago: {"type": "queue-operation", "timestamp": iso(NOW - ago),
                         "content": "<task-notification>\n<task-id>" + aid + "</task-id>\n<status>killed</status>"}
write(os.path.join(SLUG, "s3.jsonl"), [user(200), said(190), note("killed1", 60), note("resumed1", 60)])
sub("s3", "killed1", [user(300), tool(70)])                            # killed mid-tool, notified after
sub("s3", "resumed1", [user(300), tool(70), user(30)])                 # wrote AFTER the notification
assert census() == (2, 1), census()
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "D1.8: top level is judged by its last turn record, and a tool wait counts up to the horizon" {
  run python3 -c "$(_pre)$(_kw)"'
write(os.path.join(SLUG, "idle.jsonl"), [user(1900), said(1800), attach(5)])      # hook touched it
write(os.path.join(SLUG, "wait20.jsonl"), [user(1300), tool(1200)], mtime_ago=1200)  # 20-min tool
write(os.path.join(SLUG, "wait40.jsonl"), [user(2500), tool(2400)], mtime_ago=100)   # past horizon
write(os.path.join(SLUG, "empty.jsonl"), [])                                         # nothing to judge
assert census() == (2, 2), census()        # wait20 + empty (old mtime rule)
os.environ["CC_ROUTE_KWORK_TOOLWAIT_MIN"] = "15"
assert census() == (1, 1), census()
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "D1.8: the census replays at a past instant — records after now= are ignored" {
  run python3 -c "$(_pre)$(_kw)"'
write(os.path.join(SLUG, "s5.jsonl"), [user(3000), tool(900)])         # parent mid-tool at NOW-850
sub("s5", "later", [user(900), said(800), user(100), tool(60)])
# at NOW-850 the agent was mid-turn (its answer came at NOW-800); at NOW it is waiting on a tool
assert census(now=NOW - 850) == (2, 1), census(now=NOW - 850)
C = lambda r: json.dumps(r, separators=(",", ":")).encode()      # the serializer compact form
assert ca._turn_state([C(said(800)), C(user(900))], NOW - 850)[2] is False
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
