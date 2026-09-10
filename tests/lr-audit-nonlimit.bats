#!/usr/bin/env bats
# lr-audit NON-LIMIT interruption awareness — D1 (lead process state) + D2 (the
# notification ledger and the retry fold). W2-A of docs/plans/NONLIMIT_RESUME_LADDER.md.
#
# WHAT THIS SUITE EXISTS TO PIN. Before D1, lr-audit.py read no pid at all
# (`grep -E 'kill -0|os.kill|psutil|lstart' lr-audit.py` -> 0 hits), so every
# verdict was computed as though the lead process were dead. A quota kill ends the
# session; a NETWORK drop usually does not. Measured 2026-09-09: the whole fleet
# produced nothing from 14:40Z to 17:20Z while every process stayed alive, and the
# first api-error record landed 107 minutes after the silence began. Under the
# all-DEAD assumption a slot that was STILL RUNNING in a live process was reported
# `PARTIAL -> RE-RUN` one minute after its last record (`wf_f3e13296-400` /
# `agent-aefd2e2...`), and executing that plan doubles a running slot.
#
# FIXTURE PROVENANCE, stated because it is a deviation. The plan's W2-A row asks
# for byte ranges copied out of the operator's real transcripts. This suite was
# written off-box on a cloud VM where those paths do not exist, so every record
# shape below is copied from a VERBATIM QUOTE already in this repo rather than
# invented:
#   · the network-death envelope  — NONLIMIT_RESUME_LADDER.md § Finding 2
#   · the <task-notification>     — docs/research/pane-theft-composer-guard.md:33
#   · system/turn_duration        — docs/SAFEGUARD_BLOCKED_VISIBILITY.md and the
#                                   fixtures already in tests/lr-team-audit.bats
# No api-error record here is synthesized: `model:"<synthetic>"` +
# `isApiErrorMessage:true` is the measured structural pair, and it is what makes a
# text-widened read safe (a session merely DISCUSSING an error in prose is not a
# synthetic api-error record and cannot match).

setup() {
  # Fixture $HOME (hermeticity rule 1) — this suite must never read the live layer.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AUDIT="$REPO/scripts/limit-recover/lr-audit.py"
  SID="9a9a0000-1111-2222-3333-444444444444"
  FIX="$BATS_TEST_TMPDIR/fix"
  export CC_REGISTRY_DIR="$FIX/registry"
  mkdir -p "$CC_REGISTRY_DIR"
  unset LR_AUDIT_LEAD_STATE
}

teardown() {
  if [ -n "${LIVE_PID:-}" ]; then kill "$LIVE_PID" 2>/dev/null || true; fi
}

# A pid that is genuinely alive for the duration of one test.
start_live_pid() {
  sleep 120 &
  LIVE_PID=$!
}

# A pid that is genuinely dead — reaped, so `kill -0` cannot succeed. Guessing a
# high number would be a pid that merely PROBABLY does not exist.
dead_pid() {
  sleep 0.1 &
  local p=$!
  kill "$p" 2>/dev/null || true
  wait "$p" 2>/dev/null || true
  printf '%s' "$p"
}

register_pid() { # $1=pid — write the registry row lr_registry_live_rows reads
  printf '{"session_id":"%s","pid":%s,"paneUUID":"pane-1","account":"claude","cwd":"%s"}\n' \
    "$SID" "$1" "$FIX/repo" > "$CC_REGISTRY_DIR/pane-1.json"
}

# ── the fixture builder ──────────────────────────────────────────────────────
# Args are passed as a JSON blob so each test states only what it varies. Every
# knob defaults to the shape of the measured 2026-09-09 network death.
build() { # $1 = JSON options
  python3 - "$FIX" "$SID" "$1" <<'PY'
import json, os, re, sys
from datetime import datetime, timedelta, timezone

fix, sid, opts_raw = sys.argv[1], sys.argv[2], sys.argv[3]
o = json.loads(opts_raw)
cfg, cwd = os.path.join(fix, "cfg"), os.path.join(fix, "repo")
slug = re.sub(r"[^A-Za-z0-9]", "-", cwd)
proj = os.path.join(cfg, "projects", slug)
for d in (proj, cwd):
    os.makedirs(d, exist_ok=True)

now = datetime.now(timezone.utc)
def ts(minutes_ago):
    return (now - timedelta(minutes=minutes_ago)).isoformat().replace("+00:00", "Z")

recs = []

def prompt(text, mins):
    recs.append({"type": "user", "cwd": cwd, "timestamp": ts(mins),
                 "message": {"role": "user", "content": text}})

def turn_end(mins):
    recs.append({"type": "system", "subtype": "turn_duration",
                 "durationMs": 5601349, "timestamp": ts(mins)})

def spawn(tool, tid, mins, inp=None):
    recs.append({"type": "assistant", "timestamp": ts(mins),
                 "message": {"role": "assistant", "model": "claude-opus-5",
                             "content": [{"type": "tool_use", "id": tid,
                                          "name": tool, "input": inp or {}}]}})

def tool_result(tid, mins, body="done"):
    recs.append({"type": "user", "timestamp": ts(mins),
                 "message": {"role": "user",
                             "content": [{"type": "tool_result", "tool_use_id": tid,
                                          "content": body}]}})

def api_error(mins, err="server_error",
              text="API Error: Can't reach the API server — check your internet or DNS (ENOTFOUND)"):
    # VERBATIM envelope from NONLIMIT_RESUME_LADDER.md § Finding 2. Identical to a
    # cap's envelope; only `error` and the text differ.
    recs.append({"type": "assistant", "timestamp": ts(mins),
                 "message": {"model": "<synthetic>", "role": "assistant",
                             "content": [{"type": "text", "text": text}]},
                 "error": err, "isApiErrorMessage": True, "version": "2.1.260",
                 "uuid": "err-uuid-0001"})

def notification(tid, status, mins, carrier="user"):
    # VERBATIM shape from docs/research/pane-theft-composer-guard.md:33
    body = ("<task-notification>\n<task-id>bfpgwlzqu</task-id>\n"
            f"<tool-use-id>{tid}</tool-use-id>\n"
            "<output-file>/tmp/x/tasks/bfpgwlzqu.output</output-file>\n"
            f"<status>{status}</status>\n"
            "<summary>Background command \"unit\" settled</summary>\n"
            "</task-notification>")
    if carrier == "queue-operation":
        recs.append({"type": "queue-operation", "operation": "enqueue",
                     "timestamp": ts(mins), "sessionId": sid, "content": body})
    else:
        recs.append({"type": "user", "timestamp": ts(mins),
                     "message": {"role": "user", "content": body}})

prompt("do the work", 120)
spawn("Agent", "toolu_A1", 119, {"description": "unit A"})
for tid, status, carrier in o.get("notifications", []):
    notification(tid, status, 60, carrier)
for tid in o.get("tool_results", []):
    tool_result(tid, 59)
for extra in o.get("extra_prompts", []):
    prompt(extra, 40)
if o.get("api_error", True):
    api_error(30, o.get("api_error_kind", "server_error"))
if o.get("turn_end", True):
    turn_end(29)
if o.get("turn_end_then_prompt"):
    prompt("a prompt AFTER the turn end", 5)

with open(os.path.join(proj, sid + ".jsonl"), "w") as f:
    for r in recs:
        f.write(json.dumps(r) + "\n")

session_dir = os.path.join(proj, sid)

# ── bare subagent, if asked ─────────────────────────────────────────────────
sub = o.get("subagent")
if sub:
    sdir = os.path.join(session_dir, "subagents")
    os.makedirs(sdir, exist_ok=True)
    aid = "a1b2c3d4"
    lines = [{"type": "user", "timestamp": ts(100),
              "message": {"role": "user", "content": "unit A brief"}}]
    for i in range(1, 5):
        lines.append({"type": "assistant", "timestamp": ts(99 - i),
                      "message": {"role": "assistant", "model": "claude-opus-5",
                                  "content": [{"type": "tool_use", "id": f"t{i}",
                                               "name": "Read", "input": {}}]}})
        lines.append({"type": "user", "timestamp": ts(99 - i),
                      "message": {"role": "user",
                                  "content": [{"type": "tool_result",
                                               "tool_use_id": f"t{i}",
                                               "content": "x" * 50}]}})
    if sub == "final":
        lines.append({"type": "assistant", "timestamp": ts(90),
                      "message": {"role": "assistant", "model": "claude-opus-5",
                                  "stop_reason": "end_turn",
                                  "content": [{"type": "text",
                                               "text": "DONE — unit A result."}]}})
    with open(os.path.join(sdir, f"agent-{aid}.jsonl"), "w") as f:
        for r in lines:
            f.write(json.dumps(r) + "\n")
    with open(os.path.join(sdir, f"agent-{aid}.meta.json"), "w") as f:
        json.dump({"agentType": "general-purpose", "description": "unit A",
                   "toolUseId": "toolu_A1"}, f)

# ── workflow run, if asked ─────────────────────────────────────────────────
wf = o.get("workflow")
if wf:
    rid = "wf_acd6923d-9c5"
    run_dir = os.path.join(session_dir, "subagents", "workflows", rid)
    os.makedirs(run_dir, exist_ok=True)
    attempts = wf.get("attempts", 1)
    key = "v2:a990db61"
    journal = []
    # The audit derives an agentId from the FILENAME as basename[6:-6], i.e.
    # `agent-<id>.jsonl` -> `<id>`, so the journal's agentId must be the bare id.
    # Getting this wrong makes every slot read "journal started but agent jsonl
    # missing" — a fixture that holds the axis under test constant.
    agent_ids = [f"a{i:07d}" for i in range(1, attempts + 1)]
    for aid in agent_ids:
        journal.append({"type": "started", "agentId": aid, "key": key})
    if wf.get("result_for_last"):
        journal.append({"type": "result", "agentId": agent_ids[-1], "key": key,
                        "result": {"findings": ["x" * 200]}})
    if wf.get("journal_failed"):
        journal.append({"type": "failed", "key": key,
                        "error": wf.get("error", "agent stalled")})
    with open(os.path.join(run_dir, "journal.jsonl"), "w") as f:
        for r in journal:
            f.write(json.dumps(r) + "\n")
    # Attempt 1 does real work then dies on its tool timeout; every later attempt
    # is 7 lines with ZERO assistant records, ending in the watchdog's interrupt
    # marker — which is byte-identical to a human Ctrl-C. That identity is the
    # whole reason the run json's `error:` has to be the discriminator.
    for idx, aid in enumerate(agent_ids):
        lines = [{"type": "user", "timestamp": ts(80 - idx * 17),
                  "message": {"role": "user", "content": "slot brief"}}]
        # The attempt that produced a journal RESULT must carry substantive work,
        # or it correctly trips slot_verdict's vacuity floors (lines>=8,
        # tool_uses>=2) and reads VACUOUS_SUSPECT rather than COMPLETE.
        worked = (idx == 0 and wf.get("first_attempt_worked", True)) or (
            wf.get("result_for_last") and idx == len(agent_ids) - 1
        )
        if worked:
            for i in range(1, 6):
                lines.append({"type": "assistant", "timestamp": ts(79 - i),
                              "message": {"role": "assistant",
                                          "model": "claude-opus-5",
                                          "content": [{"type": "tool_use",
                                                       "id": f"w{i}", "name": "Bash",
                                                       "input": {}}]}})
                lines.append({"type": "user", "timestamp": ts(79 - i),
                              "message": {"role": "user",
                                          "content": [{"type": "tool_result",
                                                       "tool_use_id": f"w{i}",
                                                       "content": "y" * 80}]}})
        else:
            for i in range(5):
                lines.append({"type": "user", "timestamp": ts(80 - idx * 17),
                              "message": {"role": "user",
                                          "content": [{"type": "text",
                                                       "text": f"spawn attachment {i}"}]}})
        if wf.get("interrupt_marker", True):
            lines.append({"type": "user", "timestamp": ts(79 - idx * 17),
                          "message": {"role": "user",
                                      "content": [{"type": "text",
                                                   "text": "[Request interrupted by user]"}]}})
        with open(os.path.join(run_dir, f"agent-{aid}.jsonl"), "w") as f:
            for r in lines:
                f.write(json.dumps(r) + "\n")
    if wf.get("summary", True):
        wdir = os.path.join(session_dir, "workflows")
        os.makedirs(wdir, exist_ok=True)
        summary = {"runId": rid, "workflowName": "stall-repro",
                   "status": wf.get("status", "failed"),
                   "agentCount": attempts, "scriptPath": "/tmp/wf.js",
                   "startTime": ts(85), "durationMs": 42825639}
        if wf.get("error"):
            summary["error"] = wf["error"]
        if wf.get("run_result"):
            summary["result"] = {"ok": True}
        with open(os.path.join(wdir, rid + ".json"), "w") as f:
            json.dump(summary, f)

print(session_dir)
PY
}

run_audit() {
  run python3 "$AUDIT" --config-dir "$FIX/cfg" --session "$SID" --cwd "$FIX/repo" \
    --json "$BATS_TEST_TMPDIR/audit.json" --quiet
}

# The agent-*.jsonl files the builder writes are named `agent-a0000001.jsonl`, so
# the audit's basename slice yields `a0000001`. Kept as a helper so a rename of the
# convention fails in one place.
jq_verdicts() {
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for r in d["workflows"]:
    for s in r["slots"]:
        print("slot", s.get("agentId"), s["verdict"], s.get("attempts"))
for s in d["subagents"]:
    print("subagent", s["agentId"], s["verdict"])
print("lead_state", d["lead_state"]["state"])
PY
}

# ════════════════════════════════════════════════════════════════════════════
# D1 — the three lead states
# ════════════════════════════════════════════════════════════════════════════

@test "D1-a: a NETWORK death with NO live process is DEAD — and limit_events being empty must not read as 'nothing was interrupted'" {
  build '{"subagent":"partial"}'
  register_pid "$(dead_pid)"
  run_audit
  [ "$status" -eq 1 ]
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["lead_state"]["state"] == "DEAD", d["lead_state"]
# The quota subset is EMPTY on a network death. That is correct and it is the trap.
assert d["limit_events"] == [], d["limit_events"]
# The general death record must be present, with its own `error` value preserved.
ae = d["last_api_error"]
assert ae and ae["error"] == "server_error", ae
assert ae["kind"] == "other_api_error", ae
assert "ENOTFOUND" in ae["text"], ae
# A DEAD lead leaves the mechanical verdict alone: re-run is safe and correct.
v = {s["agentId"]: s["verdict"] for s in d["subagents"]}
assert v == {"a1b2c3d4": "PARTIAL"}, v
PY
}

@test "D1-b: a live pid MID-TURN is IN-FLIGHT, and its unsettled unit is UNSETTLED-INFLIGHT — never PARTIAL, never re-run" {
  # No turn end after the last prompt => the turn is still running. This is the
  # 107-minute window in which disk is silent and every process is alive.
  build '{"subagent":"partial","turn_end":false}'
  start_live_pid
  register_pid "$LIVE_PID"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["lead_state"]["state"] == "IN-FLIGHT", d["lead_state"]
assert d["lead"]["turn_open"] is True, d["lead"]
v = {s["agentId"]: s["verdict"] for s in d["subagents"]}
assert v == {"a1b2c3d4": "UNSETTLED-INFLIGHT"}, v
# The ACTION must be NONE. A re-run here doubles a live unit.
act = {g["unit"]: g["action"] for g in d["gap_units"]}
mine = [a for u, a in act.items() if "a1b2c3d4" in u][0]
assert mine.startswith("NONE"), mine
# It must FORBID a re-run, not merely omit one. (An earlier draft asserted the
# substring "RE-RUN" was absent and went red on the words "do not re-run" —
# the assertion was wrong, not the action.)
assert "do not re-run" in mine.lower(), mine
# Not a gap, and not COMPLETE either — its own stratum.
assert d["counts"]["gaps"] == 0, d["counts"]
assert d["counts"]["waiting"] == 1, d["counts"]
PY
  # Exit 0: nothing is owed by us. But the report must not read as "all complete".
  [ "$status" -eq 0 ]
}

@test "D1-c: a live pid whose turn has ENDED is IDLE, and its unsettled unit is PENDING -> WAIT-FOR-NOTIFICATION" {
  build '{"subagent":"partial"}'
  start_live_pid
  register_pid "$LIVE_PID"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["lead_state"]["state"] == "IDLE", d["lead_state"]
assert d["lead"]["turn_open"] is False, d["lead"]
v = {s["agentId"]: s["verdict"] for s in d["subagents"]}
assert v == {"a1b2c3d4": "PENDING"}, v
act = [g["action"] for g in d["gap_units"] if "a1b2c3d4" in g["unit"]][0]
assert "WAIT-FOR-NOTIFICATION" in act, act
assert "Never re-run" in act, act
PY
  [ "$status" -eq 0 ]
}

@test "D1-d: THE CAVEAT — several prompts may share ONE turn end; turn_open is 'no end AFTER the last prompt', never a 1:1 count" {
  # 52e35019 carries 27 distinct promptIds against 24 turn_duration records. A
  # count-based test would have called this session mid-turn and frozen recovery.
  build '{"extra_prompts":["queued 1","queued 2"],"subagent":"partial"}'
  start_live_pid
  register_pid "$LIVE_PID"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["lead"]["prompt_count"] == 3, d["lead"]
assert d["lead"]["turn_end_count"] == 1, d["lead"]
# Three prompts, one turn end, and the end comes last => the turn is CLOSED.
assert d["lead"]["turn_open"] is False, d["lead"]
assert d["lead_state"]["state"] == "IDLE", d["lead_state"]
PY
}

@test "D1-d MUTANT: move the turn end BEFORE the last prompt and the same fixture must flip to IN-FLIGHT" {
  # Without this arm the previous test passes under a predicate that ignores order
  # entirely (e.g. 'any turn_duration anywhere'), which is exactly the bug.
  build '{"subagent":"partial","turn_end_then_prompt":true}'
  start_live_pid
  register_pid "$LIVE_PID"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["lead"]["turn_end_count"] == 1, d["lead"]
assert d["lead"]["turn_open"] is True, d["lead"]
assert d["lead_state"]["state"] == "IN-FLIGHT", d["lead_state"]
PY
}

@test "D1-e: when the liveness INSTRUMENT cannot run, the state is UNKNOWN and nothing is cleared for re-run" {
  # jq is what lr_registry_live_rows refuses on. A refusal and a clean 'no' are the
  # same rc, and reading the refusal as 'no live process' is what silently restores
  # the all-DEAD assumption. UNKNOWN must NOT be folded into DEAD: DEAD authorises
  # a re-run, so a fail-safe default that mimicked it would be unfalsifiable.
  build '{"subagent":"partial"}'
  register_pid "$(dead_pid)"
  mkdir -p "$FIX/nojq"
  for b in python3 bash ps awk sed grep cat printf kill sleep env dirname basename; do
    src="$(command -v "$b" 2>/dev/null)" || continue
    ln -sf "$src" "$FIX/nojq/$b" 2>/dev/null || true
  done
  run env PATH="$FIX/nojq" python3 "$AUDIT" --config-dir "$FIX/cfg" --session "$SID" \
    --cwd "$FIX/repo" --json "$BATS_TEST_TMPDIR/audit.json" --quiet
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ls = d["lead_state"]
assert ls["state"] == "UNKNOWN", ls
assert ls["arms"]["reg_ok"] is False, ls
assert "REFUSED" in ls["evidence"], ls
assert "authorises a re-run" in ls["evidence"], ls
v = {s["agentId"]: s["verdict"] for s in d["subagents"]}
assert v == {"a1b2c3d4": "UNVERIFIABLE"}, v
act = [g["action"] for g in d["gap_units"] if "a1b2c3d4" in g["unit"]][0]
assert "SURFACE" in act, act
assert "RE-RUN" not in act.upper(), act
PY
}

@test "D1-e CONTROL: the same tree with jq present resolves to a real state, so the UNKNOWN above is the instrument and not the fixture" {
  build '{"subagent":"partial"}'
  register_pid "$(dead_pid)"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["lead_state"]["state"] == "DEAD", d["lead_state"]
assert d["lead_state"]["arms"]["reg_ok"] is True, d["lead_state"]
PY
}

@test "D1-f: LR_AUDIT_LEAD_STATE is a real kill switch — it restores the all-DEAD reading over a live pid" {
  build '{"subagent":"partial","turn_end":false}'
  start_live_pid
  register_pid "$LIVE_PID"
  LR_AUDIT_LEAD_STATE=DEAD run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["lead_state"]["state"] == "DEAD", d["lead_state"]
assert "forced" in d["lead_state"]["evidence"], d["lead_state"]
v = {s["agentId"]: s["verdict"] for s in d["subagents"]}
assert v == {"a1b2c3d4": "PARTIAL"}, v
PY
  [ "$status" -eq 1 ]
}

@test "D1-g: a run dir with NO summary json is not 'killed mid-run' while a process still holds the session" {
  # `:1335`'s "run dir exists but run-summary json missing (killed mid-run)" was a
  # death ASSERTED, never measured. On the receipt case the run had no summary
  # because it was STILL RUNNING.
  build '{"workflow":{"attempts":1,"summary":false,"interrupt_marker":false,"first_attempt_worked":true}}'
  start_live_pid
  register_pid "$LIVE_PID"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
r = d["workflows"][0]
probs = " ".join(r["problems"])
assert "killed mid-run" not in probs, probs
assert "not evidence of a kill" in probs, probs
assert r["run_verdict"] in ("PENDING", "UNSETTLED-INFLIGHT"), r["run_verdict"]
PY
}

@test "D1-g CONTROL: with the process GONE the same tree keeps the killed-mid-run reading and stays INCOMPLETE" {
  build '{"workflow":{"attempts":1,"summary":false,"interrupt_marker":false,"first_attempt_worked":true}}'
  register_pid "$(dead_pid)"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
r = d["workflows"][0]
probs = " ".join(r["problems"])
assert "killed mid-run" in probs, probs
assert r["run_verdict"] == "INCOMPLETE", r["run_verdict"]
PY
}

# ════════════════════════════════════════════════════════════════════════════
# D2 — the notification ledger
# ════════════════════════════════════════════════════════════════════════════

@test "D2-a: a task-notification SETTLES a background unit — a completed unit is COMPLETE, not COMPLETE_UNDELIVERED" {
  # Before D2 the audit read only tool_result ids, so a unit the harness had
  # already spoken about read as never delivered.
  build '{"subagent":"final","notifications":[["toolu_A1","completed","user"]]}'
  register_pid "$(dead_pid)"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d["subagents"][0]
assert s["verdict"] == "COMPLETE", s
assert s["settled"] is True, s
assert s["notification"]["status"] == "completed", s
assert d["delegations"]["settled"] == 1, d["delegations"]
assert d["delegations"]["open"] == [], d["delegations"]
PY
  [ "$status" -eq 0 ]
}

@test "D2-a CONTROL: the same completed unit with NO notification and no tool_result is COMPLETE_UNDELIVERED" {
  build '{"subagent":"final"}'
  register_pid "$(dead_pid)"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d["subagents"][0]
assert s["verdict"] == "COMPLETE_UNDELIVERED", s
assert s["settled"] is False, s
assert len(d["delegations"]["open"]) == 1, d["delegations"]
PY
}

@test "D2-b: a notification riding a queue-operation ENQUEUE settles the unit too — both carriers are read" {
  build '{"subagent":"final","notifications":[["toolu_A1","completed","queue-operation"]]}'
  register_pid "$(dead_pid)"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d["subagents"][0]
assert s["verdict"] == "COMPLETE", s
assert s["notification"]["carrier"] == "queue-operation", s
PY
}

@test "D2-c: a NON-SUCCESS notification settles the unit and its status is carried into the evidence" {
  # Q3 predicate 3: a delivered notification whose status is not `completed`. It is
  # terminal — the harness has spoken — and the status is what selects the recovery.
  build '{"subagent":"partial","notifications":[["toolu_A1","killed","user"]]}'
  register_pid "$(dead_pid)"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d["subagents"][0]
assert s["settled"] is True, s
assert s["notification"]["status"] == "killed", s
assert any("status=killed" in e for e in s["evidence"]), s["evidence"]
# Settled means the mechanical verdict stands: the harness's terminal word does
# not un-fail the unit, and a live lead must not turn it into PENDING either.
assert s["verdict"] == "PARTIAL", s
PY
}

@test "D2-c2: a settled unit keeps its mechanical verdict even under a LIVE idle lead — PENDING is for units nobody has spoken about" {
  build '{"subagent":"partial","notifications":[["toolu_A1","failed","user"]]}'
  start_live_pid
  register_pid "$LIVE_PID"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["lead_state"]["state"] == "IDLE", d["lead_state"]
s = d["subagents"][0]
assert s["verdict"] == "PARTIAL", s   # NOT PENDING: it is settled
PY
  [ "$status" -eq 1 ]
}

@test "D2-d: a 'running' notification is NOT terminal — it must not settle the unit" {
  build '{"subagent":"partial","notifications":[["toolu_A1","running","user"]]}'
  register_pid "$(dead_pid)"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d["subagents"][0]
assert s["settled"] is False, s
assert len(d["delegations"]["open"]) == 1, d["delegations"]
PY
}

@test "D2-e: the delegation POPULATION is printed by tool name, so a zero names its strata" {
  # fail-safe mimics healthy: an audit that missed a spawn tool would print
  # "0 open" and read exactly like a clean session.
  build '{"subagent":"final","notifications":[["toolu_A1","completed","user"]]}'
  register_pid "$(dead_pid)"
  run python3 "$AUDIT" --config-dir "$FIX/cfg" --session "$SID" --cwd "$FIX/repo" \
    --json "$BATS_TEST_TMPDIR/audit.json"
  echo "$output" | grep -q 'delegation population by tool: Agent 1 (settled 1, open 0)' || {
    echo "MISSING population line; got:"; echo "$output" | head -20; false
  }
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
pop = d["delegations"]["population_by_tool"]
assert pop == {"Agent": {"total": 1, "settled": 1, "open": 0}}, pop
PY
}

@test "D2-f: the empty-limit_events line no longer reads as 'nothing was interrupted'" {
  build '{"subagent":"partial"}'
  register_pid "$(dead_pid)"
  run python3 "$AUDIT" --config-dir "$FIX/cfg" --session "$SID" --cwd "$FIX/repo"
  # The old wording was "No genuine limit events found in the lead transcript." —
  # true, and read as an all-clear on a network death.
  if echo "$output" | grep -q 'No genuine limit events found in the lead transcript\.$'; then
    echo "the old all-clear wording is back"; false
  fi
  echo "$output" | grep -q 'quota subset only' || { echo "$output" | head -20; false; }
  echo "$output" | grep -q 'says NOTHING about whether work was interrupted' || false
}

# ════════════════════════════════════════════════════════════════════════════
# D2 — the retry fold and STALLED
# ════════════════════════════════════════════════════════════════════════════

@test "D2-g: six attempts under ONE journal key fold to ONE unit with attempts=6 and verdict STALLED" {
  # Measured on wf_acd6923d-9c5: six `started` under one key, one `failed`, run json
  # `status: failed` + `error: agent stalled on all 6 attempts (no progress for
  # 180000ms each)`. Read per-attempt that is six INTERRUPTED units, each actioned
  # RE-RUN and each blamed on "TaskStop / user".
  build '{"workflow":{"attempts":6,"journal_failed":true,"status":"failed","error":"agent stalled on all 6 attempts (no progress for 180000ms each)"}}'
  register_pid "$(dead_pid)"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
r = d["workflows"][0]
assert len(r["slots"]) == 1, [s["agentId"] for s in r["slots"]]
s = r["slots"][0]
assert s["verdict"] == "STALLED", s
assert s["attempts"] == 6, s
assert len(s["attempt_agent_ids"]) == 6, s
assert "6 attempts under ONE journal key" in " ".join(s["evidence"]), s["evidence"]
# The attribution must move OFF the user.
ev = " ".join(s["evidence"])
assert "not a user interrupt" in ev, ev
assert "TaskStop / user" not in ev, ev
# ONE slot-level unit in the ledger, not six. (The RUN row is a separate level
# and is expected — the run genuinely needs resuming; what matters is that it
# does not offer a BARE resume over a stalled slot.)
slot_units = [
    g for g in d["gap_units"]
    if "wf_acd6923d" in g["unit"] and not g["unit"].startswith("workflow ")
]
assert len(slot_units) == 1, slot_units
assert "6 attempts" in slot_units[0]["unit"], slot_units[0]
act = slot_units[0]["action"]
assert "AT MOST ONE re-fire" in act, act
assert "GREEN control" in act, act
run_units = [g for g in d["gap_units"] if g["unit"].startswith("workflow wf_acd6923d")]
assert len(run_units) == 1, run_units
ract = run_units[0]["action"]
assert ract.startswith("GATED RESUME"), ract
assert "AT MOST ONE re-fire" in ract, ract
PY
  [ "$status" -eq 1 ]
}

@test "D2-g MUTANT: STALLED must be STRUCTURAL — an arbitrary error string, naming no watchdog, still folds to STALLED" {
  # If the predicate ever keys on the words "stalled" / "no progress", this arm goes
  # red. Q3's own rule: a denylist enumerates spellings, not the class.
  build '{"workflow":{"attempts":6,"journal_failed":true,"status":"failed","error":"zzz totally unrelated terminal condition qqq"}}'
  register_pid "$(dead_pid)"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d["workflows"][0]["slots"][0]
assert s["verdict"] == "STALLED", s
assert s["attempts"] == 6, s
assert "zzz totally unrelated" in " ".join(s["evidence"]), s["evidence"]
PY
}

@test "D2-h CONTROL: a SINGLE interrupted attempt on a run with no terminal error stays INTERRUPTED — the fold did not swallow the real interrupt class" {
  build '{"workflow":{"attempts":1,"status":"completed","run_result":true,"first_attempt_worked":false}}'
  register_pid "$(dead_pid)"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d["workflows"][0]["slots"][0]
assert s["verdict"] == "INTERRUPTED", s
assert s["attempts"] == 1, s
assert "interrupted (TaskStop / user)" in " ".join(s["evidence"]), s["evidence"]
PY
}

@test "D2-i: a key that COMPLETED under a later attempt keeps the completed unit and marks the earlier ones SUPERSEDED, never STALLED" {
  build '{"workflow":{"attempts":3,"result_for_last":true,"status":"completed"}}'
  register_pid "$(dead_pid)"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
r = d["workflows"][0]
vs = sorted(s["verdict"] for s in r["slots"])
assert vs == ["COMPLETE", "SUPERSEDED", "SUPERSEDED"], vs
assert "STALLED" not in vs, vs
PY
}

@test "D2-j: a folded stall under a LIVE MID-TURN lead is UNSETTLED-INFLIGHT, not a re-fire instruction" {
  build '{"workflow":{"attempts":6,"journal_failed":true,"status":"failed","error":"agent stalled on all 6 attempts"},"turn_end":false}'
  start_live_pid
  register_pid "$LIVE_PID"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["lead_state"]["state"] == "IN-FLIGHT", d["lead_state"]
s = d["workflows"][0]["slots"][0]
assert s["verdict"] == "UNSETTLED-INFLIGHT", s
assert s["attempts"] == 6, s
PY
}

# ════════════════════════════════════════════════════════════════════════════
# The wait ledger must never read as "all complete"
# ════════════════════════════════════════════════════════════════════════════

@test "D1-h: with only waiting units the report says no action is required WITHOUT claiming all work is COMPLETE" {
  build '{"subagent":"partial"}'
  start_live_pid
  register_pid "$LIVE_PID"
  run python3 "$AUDIT" --config-dir "$FIX/cfg" --session "$SID" --cwd "$FIX/repo"
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q 'all delegated work is COMPLETE and delivered'; then
    echo "a waiting unit was reported as COMPLETE"; false
  fi
  echo "$output" | grep -q 'Wait ledger' || { echo "$output" | tail -20; false; }
  echo "$output" | grep -q 'WAITING: 1' || false
  echo "$output" | grep -q 'lead process: IDLE' || false
}

# ════════════════════════════════════════════════════════════════════════════
# D1 — the TEAMMATE re-key. This is the population W0 believed was already safe.
# ════════════════════════════════════════════════════════════════════════════

MEMBER_SID="bbbb0001-0000-0000-0000-000000000001"

build_team() {
  python3 - "$FIX" "$SID" "$MEMBER_SID" <<'PY'
import json, os, re, sys
from datetime import datetime, timedelta, timezone

fix, lead_sid, member_sid = sys.argv[1], sys.argv[2], sys.argv[3]
cfg, cwd = os.path.join(fix, "cfg"), os.path.join(fix, "repo")
slug = re.sub(r"[^A-Za-z0-9]", "-", cwd)
proj = os.path.join(cfg, "projects", slug)
for d in (proj, cwd):
    os.makedirs(d, exist_ok=True)
now = datetime.now(timezone.utc)
def ts(m):
    return (now - timedelta(minutes=m)).isoformat().replace("+00:00", "Z")
joined_ms = int((now - timedelta(hours=1)).timestamp() * 1000)

# THE MEMBER: substantive work, NO terminal turn, and its last record is 45
# minutes old — far past TEAM_ACTIVE_WINDOW_S (300 s). Under the old stamp rule
# this is PARTIAL, and the ACTION for PARTIAL is respawn over the live member.
# Every outage is longer than five minutes; the measured one was 2h40m.
recs = [{"type": "user", "cwd": cwd, "timestamp": ts(60), "teamName": "t1",
         "agentName": "m-live",
         "message": {"role": "user", "content": "member brief: do the analysis"}}]
for i in range(1, 6):
    recs.append({"type": "assistant", "timestamp": ts(59 - i), "teamName": "t1",
                 "agentName": "m-live",
                 "message": {"role": "assistant", "model": "claude-opus-5",
                             "content": [{"type": "tool_use", "id": f"m{i}",
                                          "name": "Read", "input": {}}]}})
    recs.append({"type": "user", "timestamp": ts(59 - i), "teamName": "t1",
                 "agentName": "m-live",
                 "message": {"role": "user",
                             "content": [{"type": "tool_result",
                                          "tool_use_id": f"m{i}",
                                          "content": "z" * 60}]}})
# No turn_duration and no final text: the member is mid-turn, i.e. IN-FLIGHT.
with open(os.path.join(proj, member_sid + ".jsonl"), "w") as f:
    for r in recs:
        f.write(json.dumps(r) + "\n")

team_dir = os.path.join(cfg, "teams", "t1")
os.makedirs(team_dir, exist_ok=True)
with open(os.path.join(team_dir, "config.json"), "w") as f:
    json.dump({"name": "t1", "createdAt": joined_ms, "leadSessionId": lead_sid,
               "members": [
                   {"agentId": "team-lead@t1", "name": "team-lead",
                    "agentType": "team-lead", "joinedAt": joined_ms,
                    "cwd": cwd, "backendType": "in-process"},
                   {"agentId": "m-live@t1", "name": "m-live",
                    "agentType": "general-purpose", "model": "claude-opus-5",
                    "joinedAt": joined_ms, "cwd": cwd, "isActive": True,
                    "prompt": "member brief: do the analysis"}]}, f)

# a minimal lead transcript with a closed turn
with open(os.path.join(proj, lead_sid + ".jsonl"), "w") as f:
    f.write(json.dumps({"type": "user", "cwd": cwd, "timestamp": ts(70),
                        "message": {"role": "user", "content": "lead work"}}) + "\n")
    f.write(json.dumps({"type": "assistant", "timestamp": ts(69),
                        "message": {"role": "assistant", "model": "claude-opus-5",
                                    "stop_reason": "end_turn",
                                    "content": [{"type": "text", "text": "ok"}]}}) + "\n")
    f.write(json.dumps({"type": "system", "subtype": "turn_duration",
                        "timestamp": ts(69)}) + "\n")
PY
}

register_member_pid() { # $1=pid
  printf '{"session_id":"%s","pid":%s,"paneUUID":"pane-m","account":"claude","cwd":"%s"}\n' \
    "$MEMBER_SID" "$1" "$FIX/repo" > "$CC_REGISTRY_DIR/pane-m.json"
}

@test "D1-i: a teammate silent for 45 min under a LIVE pid is RUNNING — the stamp said PARTIAL, whose action is respawn over a live member" {
  build_team
  start_live_pid
  register_pid "$(dead_pid)"          # the LEAD is gone
  register_member_pid "$LIVE_PID"     # the MEMBER is alive and mid-turn
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = d["teams"]["led"][0]["members"][0]
assert m["name"] == "m-live", m
assert m["member_state"]["state"] == "IN-FLIGHT", m["member_state"]
assert m["verdict"] == "RUNNING", m
ev = " ".join(m["evidence"])
assert "never respawn over a live member" in ev, ev
# The stamp must be reported as context, never as the verdict.
assert "last activity" in ev, ev
act = [g["action"] for g in d["gap_units"] if g["unit"] == "team t1/m-live"][0]
assert act.startswith("NONE"), act
assert "never respawn" in act, act
PY
}

@test "D1-i CONTROL: the same 45-min-silent teammate with a DEAD pid is PARTIAL and respawns from the verbatim brief" {
  # Same bytes, one variable changed. Without this arm the test above passes under
  # a predicate that simply always answers RUNNING.
  build_team
  register_pid "$(dead_pid)"
  register_member_pid "$(dead_pid)"
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = d["teams"]["led"][0]["members"][0]
assert m["member_state"]["state"] == "DEAD", m["member_state"]
assert m["verdict"] == "PARTIAL", m
assert "member process is gone" in " ".join(m["evidence"]), m["evidence"]
act = [g["action"] for g in d["gap_units"] if g["unit"] == "team t1/m-live"][0]
assert "RESPAWN" in act, act
PY
  [ "$status" -eq 1 ]
}

@test "D1-j: isActive=false does NOT demote a member whose process this audit just proved alive" {
  # The harness's own word outranks a stamp, but not a live pid: demoting here is
  # the respawn-over-a-live-member hazard wearing the harness's authority.
  build_team
  start_live_pid
  register_pid "$(dead_pid)"
  register_member_pid "$LIVE_PID"
  python3 - "$FIX/cfg/teams/t1/config.json" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
for m in c["members"]:
    if m.get("name") == "m-live":
        m["isActive"] = False
json.dump(c, open(p, "w"))
PY
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = d["teams"]["led"][0]["members"][0]
assert m["verdict"] == "RUNNING", m
assert "isActive=false" not in " ".join(m["evidence"]), m["evidence"]
PY
}

@test "D1-j CONTROL: isActive=false DOES demote when no live process holds the member" {
  build_team
  register_pid "$(dead_pid)"
  register_member_pid "$(dead_pid)"
  python3 - "$FIX/cfg/teams/t1/config.json" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
for m in c["members"]:
    if m.get("name") == "m-live":
        m["isActive"] = False
json.dump(c, open(p, "w"))
PY
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = d["teams"]["led"][0]["members"][0]
assert m["verdict"] == "PARTIAL", m
PY
}

@test "D1-h CONTROL: a genuinely clean session still says all delegated work is COMPLETE" {
  build '{"subagent":"final","notifications":[["toolu_A1","completed","user"]]}'
  register_pid "$(dead_pid)"
  run python3 "$AUDIT" --config-dir "$FIX/cfg" --session "$SID" --cwd "$FIX/repo"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'all delegated work is COMPLETE and delivered' || {
    echo "$output" | tail -20; false
  }
  if echo "$output" | grep -q 'Wait ledger'; then
    echo "a clean session grew a wait ledger"; false
  fi
}
