#!/usr/bin/env bats
# W4-wf (docs/plans/LIMIT_RECOVER_FLEET_V2.md § Status log): a moved session never re-spends
# finished Workflow slots. lr-audit.py PREDICTS how many completed slots a plain
# Workflow({scriptPath, resumeFromRunId}) would re-run, and when that is > 0 the run's gap row
# prescribes a salvage-seeded continuation instead of a resume.
#
# The mechanism under test is W0's measurement (docs/research/lr-recon-w0-2026-09-29 § 8,
# fixtures tests/fixtures/lr-recon/workflow-prefix-7c395da7*.json): a resume replays only the
# longest unchanged PREFIX of agent() calls, and a stage issued in upstream COMPLETION order
# (pipeline) is re-issued in upstream INDEX order, so its call indices shift and every completed
# slot from there on re-runs — even when every dangling slot is last.
#
# LR_AUDIT_UNDER_TEST points the suite at another copy (the red check runs it against the
# pre-change lr-audit.py).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AUDIT="${LR_AUDIT_UNDER_TEST:-$REPO/scripts/limit-recover/lr-audit.py}"
  SID="9b9b0000-1111-2222-3333-444444444444"
  FIX="$BATS_TEST_TMPDIR/fix"
  export CC_REGISTRY_DIR="$FIX/registry"
  mkdir -p "$CC_REGISTRY_DIR"
  unset LR_AUDIT_LEAD_STATE LR_AUDIT_RESUME_PREDICT
  # A reaped pid, registered as the session's holder: the lead is provably DEAD, so the
  # dangling slots are gaps (NULL), not waits.
  sleep 0.1 & local p=$!; kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true
  printf '{"session_id":"%s","pid":%s,"paneUUID":"pane-1","account":"claude","cwd":"%s"}\n' \
    "$SID" "$p" "$FIX/repo" > "$CC_REGISTRY_DIR/pane-1.json"
}

# build SPEC_JSON — SPEC: {status, error?, calls:[{index, stage, state: done|error, queuedAt?,
# startedAt, durationMs?, lastProgressAt?, attempts?}]}. Every call gets a journal `started`
# (one per attempt, one key), a `result` when done or a `failed` when not, and an agent jsonl
# (substantive when done, killed-at-spawn when not); the run summary carries workflowProgress.
build() {
  python3 - "$FIX" "$SID" "$1" <<'PY'
import json, os, re, sys
from datetime import datetime, timedelta, timezone
fix, sid, spec = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
cfg, cwd = os.path.join(fix, "cfg"), os.path.join(fix, "repo")
proj = os.path.join(cfg, "projects", re.sub(r"[^A-Za-z0-9]", "-", cwd))
os.makedirs(proj, exist_ok=True); os.makedirs(cwd, exist_ok=True)
now = datetime.now(timezone.utc)
ts = lambda m: (now - timedelta(minutes=m)).isoformat().replace("+00:00", "Z")
rid = "wf_0a0b0c0d-e1f"
recs = [
    {"type": "user", "cwd": cwd, "timestamp": ts(120),
     "message": {"role": "user", "content": "run the workflow"}},
    {"type": "assistant", "timestamp": ts(119),
     "message": {"role": "assistant", "model": "claude-opus-5",
                 "content": [{"type": "tool_use", "id": "toolu_W1", "name": "Workflow",
                              "input": {"scriptPath": "/tmp/wf.js"}}]}},
    {"type": "assistant", "timestamp": ts(30),
     "message": {"model": "<synthetic>", "role": "assistant",
                 "content": [{"type": "text", "text": "You've hit your session limit"}]},
     "error": "rate_limit", "isApiErrorMessage": True, "uuid": "err-1"},
]
with open(os.path.join(proj, sid + ".jsonl"), "w") as f:
    f.writelines(json.dumps(r) + "\n" for r in recs)
sd = os.path.join(proj, sid)
run_dir = os.path.join(sd, "subagents", "workflows", rid)
os.makedirs(run_dir, exist_ok=True); os.makedirs(os.path.join(sd, "workflows"), exist_ok=True)
journal, progress = [], []
for c in spec["calls"]:
    i, key = c["index"], f"v2:k{c['index']:05d}"
    aids = [f"a{i:05d}{n:02d}" for n in range(c.get("attempts", 1))]
    for aid in aids:
        journal.append({"type": "started", "agentId": aid, "key": key,
                        "label": f"{c['stage']}:{i}"})
        done = c["state"] == "done" and aid == aids[-1]
        lines = [{"type": "user", "timestamp": ts(100),
                  "message": {"role": "user", "content": f"brief {i}"}}]
        if done:
            for t in range(5):
                lines.append({"type": "assistant", "timestamp": ts(99),
                              "message": {"role": "assistant", "model": "claude-opus-5",
                                          "content": [{"type": "tool_use", "id": f"u{t}",
                                                       "name": "Read", "input": {}}]}})
                lines.append({"type": "user", "timestamp": ts(99),
                              "message": {"role": "user",
                                          "content": [{"type": "tool_result",
                                                       "tool_use_id": f"u{t}",
                                                       "content": "x" * 40}]}})
        with open(os.path.join(run_dir, f"agent-{aid}.jsonl"), "w") as f:
            f.writelines(json.dumps(r) + "\n" for r in lines)
    if c["state"] == "done":
        journal.append({"type": "result", "agentId": aids[-1], "key": key,
                        "result": {"finding": "y" * 200}})
    else:
        journal.append({"type": "failed", "key": key, "error": spec.get("error") or "limit"})
    e = {"type": "workflow_agent", "index": i, "label": f"{c['stage']}:{i}",
         "agentId": aids[-1], "state": c["state"]}
    for k in ("queuedAt", "startedAt", "durationMs", "lastProgressAt"):
        if c.get(k) is not None:
            e[k] = c[k]
    progress.append(e)
with open(os.path.join(run_dir, "journal.jsonl"), "w") as f:
    f.writelines(json.dumps(r) + "\n" for r in journal)
summary = {"runId": rid, "workflowName": "prefix-repro", "status": spec.get("status", "killed"),
           "agentCount": len(spec["calls"]), "scriptPath": "/tmp/wf.js",
           "workflowProgress": progress}
if spec.get("error"):
    summary["error"] = spec["error"]
with open(os.path.join(sd, "workflows", rid + ".json"), "w") as f:
    json.dump(summary, f)
PY
}

run_audit() {
  run python3 "$AUDIT" --config-dir "$FIX/cfg" --session "$SID" --cwd "$FIX/repo" \
    --json "$BATS_TEST_TMPDIR/audit.json" --md "$BATS_TEST_TMPDIR/audit.md" --quiet
}

# A pipeline: 3 finds issued at once finish in the order 2, 3, 1; each releases a burst of 2
# verifies 5 ms after it ends (so each burst lands while other finds are still in flight); a
# judge issued after everything is quiet dies on the limit.
PIPELINE='{"status":"completed","calls":[
 {"index":1,"stage":"find","state":"done","queuedAt":0,"startedAt":1,"durationMs":3000},
 {"index":2,"stage":"find","state":"done","queuedAt":0,"startedAt":1,"durationMs":1000},
 {"index":3,"stage":"find","state":"done","queuedAt":0,"startedAt":1,"durationMs":2000},
 {"index":4,"stage":"verify","state":"done","queuedAt":1006,"startedAt":1007,"durationMs":5000},
 {"index":5,"stage":"verify","state":"done","queuedAt":1006,"startedAt":1007,"durationMs":5000},
 {"index":6,"stage":"verify","state":"done","queuedAt":2006,"startedAt":2007,"durationMs":5000},
 {"index":7,"stage":"verify","state":"done","queuedAt":2006,"startedAt":2007,"durationMs":5000},
 {"index":8,"stage":"verify","state":"done","queuedAt":3006,"startedAt":3007,"durationMs":5000},
 {"index":9,"stage":"verify","state":"done","queuedAt":3006,"startedAt":3007,"durationMs":5000},
 {"index":10,"stage":"judge","state":"error","queuedAt":9000,"startedAt":9001,"lastProgressAt":9100}]}'

@test "(a) a completion-ordered stage predicts the re-spend and prescribes a salvage-seeded continuation naming the count" {
  build "$PIPELINE"
  run_audit
  [ "$status" -eq 1 ]
  python3 - "$BATS_TEST_TMPDIR/audit.json" "$BATS_TEST_TMPDIR/audit.md" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); md = open(sys.argv[2]).read()
r = d["workflows"][0]
p = r["resume_prediction"]
assert p["available"] and p["cause"] == "completion-order", p
assert p["cache_hits"] == 3 and p["prefix_ends_at_index"] == 4, p
assert p["predicted_respend"] == 6 and p["respend_by_stage"] == {"verify": 6}, p
run_rows = [g for g in d["gap_units"] if g["unit"].startswith("workflow wf_0a0b0c0d")]
assert len(run_rows) == 1, run_rows
act = run_rows[0]["action"]
assert act.startswith("SALVAGE-SEEDED CONTINUATION"), act
assert "RE-SPEND 6 of 9 completed slot(s)" in act, act
assert "COMPLETION order" in act and "conservative" in act, act
assert "only the first 3 call(s) would hit the cache" in act, act
# the unfinished slot's own row points at the continuation, never at a bare resume
slot_rows = [g for g in d["gap_units"] if g["unit"].startswith("wf_0a0b0c0d")]
assert slot_rows and all("SALVAGE-SEEDED CONTINUATION" in g["action"] for g in slot_rows), slot_rows
# the channel to the successor: audit.md's gap ledger carries the action verbatim
assert act in md, "run action missing from audit.md"
assert "would re-run **6** of 9 completed slot(s)" in md, md
PY
}

@test "(b) index-stable call order — a sequential chain then a queued parallel map — still offers a plain resume" {
  build '{"status":"killed","calls":[
   {"index":1,"stage":"plan","state":"done","queuedAt":0,"startedAt":1,"durationMs":1000},
   {"index":2,"stage":"plan","state":"done","queuedAt":1010,"startedAt":1011,"durationMs":1000},
   {"index":3,"stage":"scan","state":"done","queuedAt":2020,"startedAt":2021,"durationMs":1000},
   {"index":4,"stage":"scan","state":"done","queuedAt":2020,"startedAt":3025,"durationMs":1000},
   {"index":5,"stage":"scan","state":"done","queuedAt":2020,"startedAt":3030,"durationMs":1000},
   {"index":6,"stage":"scan","state":"done","queuedAt":2021,"startedAt":4040,"durationMs":1000},
   {"index":7,"stage":"judge","state":"error","queuedAt":6000,"startedAt":6001,"lastProgressAt":6100}]}'
  run_audit
  [ "$status" -eq 1 ]
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = d["workflows"][0]["resume_prediction"]
assert p["available"] and p["predicted_respend"] == 0, p
assert p["cache_hits"] == 6 and p["cause"] == "dangling", p
act = [g for g in d["gap_units"] if g["unit"].startswith("workflow ")][0]["action"]
assert act == "resume via Workflow({scriptPath, resumeFromRunId}); re-audit after", act
PY
}

@test "(b2) the plain prefix rule still counts: an EARLY unfinished slot re-spends every completed slot after it" {
  build '{"status":"killed","calls":[
   {"index":1,"stage":"a","state":"done","queuedAt":0,"startedAt":1,"durationMs":1000},
   {"index":2,"stage":"b","state":"error","queuedAt":1010,"startedAt":1011,"lastProgressAt":1500},
   {"index":3,"stage":"c","state":"done","queuedAt":1600,"startedAt":1601,"durationMs":1000},
   {"index":4,"stage":"c","state":"done","queuedAt":2700,"startedAt":2701,"durationMs":1000}]}'
  run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = d["workflows"][0]["resume_prediction"]
assert p["cause"] == "dangling" and p["predicted_respend"] == 2 and p["cache_hits"] == 1, p
act = [g for g in d["gap_units"] if g["unit"].startswith("workflow ")][0]["action"]
assert act.startswith("SALVAGE-SEEDED CONTINUATION") and "first unfinished call is #2" in act, act
PY
}

@test "(c) the STALLED gate still wins over a completion-ordered run: gate first, continuation only after it" {
  spec="$(python3 -c '
import json, sys
s = json.loads(sys.argv[1])
s["status"] = "failed"
s["error"] = "agent stalled on all 3 attempts (no progress for 180000ms each)"
s["calls"][-1]["attempts"] = 3
print(json.dumps(s))' "$PIPELINE")"
  build "$spec"
  run_audit
  [ "$status" -eq 1 ]
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
r = d["workflows"][0]
assert r["slot_counts"].get("STALLED") == 1, r["slot_counts"]
act = [g for g in d["gap_units"] if g["unit"].startswith("workflow ")][0]["action"]
assert act.startswith("GATED CONTINUATION — this run holds 1 STALLED slot(s)."), act
gate, cont = act.index("AT MOST ONE re-fire"), act.index("Only then: SALVAGE-SEEDED CONTINUATION")
assert gate < cont, act
assert "RE-SPEND 6 of 9" in act, act
PY
}

@test "(d) the 7c395da7 fixture: the verify stage is predicted re-spent (>=595 of 608) behind exactly the 8 index-stable hits" {
  W0="$REPO/tests/fixtures/lr-recon/workflow-prefix-7c395da7.json"
  CALLS="$REPO/tests/fixtures/lr-recon/workflow-prefix-7c395da7-calls.json"
  spec="$(python3 - "$W0" "$CALLS" <<'PY'
import json, sys
w0, calls = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
assert w0["run_id"] == calls["run_id"] and len(w0["slots"]) == len(calls["calls"]) == 646
# The two fixtures describe ONE run: slot i is call index i+1, with the same terminal state.
for s, c in zip(w0["slots"], calls["calls"]):
    assert c["index"] == s["i"] + 1, (s, c)
    assert (c["state"] == "done") == (s["status"] == "COMPLETE"), (s, c)
print(json.dumps({"status": "completed", "calls": calls["calls"]}))
PY
)"
  build "$spec"
  run_audit
  [ "$status" -eq 1 ]
  python3 - "$BATS_TEST_TMPDIR/audit.json" "$W0" > "$BATS_TEST_TMPDIR/d.out" <<'PY'
import json, sys
d, w0 = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
r = d["workflows"][0]
p = r["resume_prediction"]
assert p["available"] and p["cause"] == "completion-order", p
assert p["respend_by_stage"].get("verify", 0) >= 595, p
# measured: exactly the 8 slots whose call index did not change hit the cache
hits = [s["i"] for s in w0["slots"] if s["re_run_after_resume"] is False]
assert p["cache_hits"] == w0["resumed_run"]["cache_hits"] == len(hits) == 8, (p, hits)
assert hits == list(range(8)), hits
# every slot the measured resume actually re-spawned is inside the predicted re-spend
respawned = [s["i"] for s in w0["slots"] if s["re_run_after_resume"] is True]
assert respawned and min(respawned) >= p["cache_hits"], respawned
act = [g for g in d["gap_units"] if g["unit"].startswith("workflow ")][0]["action"]
assert act.startswith("SALVAGE-SEEDED CONTINUATION"), act
assert f"RE-SPEND {p['predicted_respend']} of 633 completed slot(s)" in act, act
print(f"7c395da7 predicted re-spend: {p['predicted_respend']} of {p['completed']} completed "
      f"slots ({', '.join(f'{k} {v}' for k, v in sorted(p['respend_by_stage'].items()))}); "
      f"cache hits {p['cache_hits']}")
PY
  cat "$BATS_TEST_TMPDIR/d.out" >&3
  grep -q '^7c395da7 predicted re-spend: 625 of 633' "$BATS_TEST_TMPDIR/d.out"
}

@test "kill switch: LR_AUDIT_RESUME_PREDICT=off restores the plain resume action on the pipeline" {
  build "$PIPELINE"
  LR_AUDIT_RESUME_PREDICT=off run_audit
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = d["workflows"][0]["resume_prediction"]
assert p == {"available": False, "reason": "LR_AUDIT_RESUME_PREDICT=off"}, p
act = [g for g in d["gap_units"] if g["unit"].startswith("workflow ")][0]["action"]
assert act.startswith("run 'completed' over gap slots"), act
PY
}
