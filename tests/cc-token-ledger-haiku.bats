#!/usr/bin/env bats
# cc-token-ledger --haiku — the telemetry behind the Haiku 5.5 revert triggers
# (docs/research/haiku55-upgrade-2026-10-07/README.md § Revert triggers).
#
# The fixture is built in a scratch HOME by setup(), one config dir (.claude-next):
#   S1 main (Opus) + cost-state (Opus out 1000, Haiku 5.5 out 350), two Explore spawns:
#      a1 requested haiku @medium, served claude-haiku-5-5 at transcript effort medium, out 30+20
#      a2 requested haiku, no effort, served claude-haiku-4-5-20251001 at effort high (a served-model
#         mismatch and an off-pin effort), plus a "Prompt is too long" API error (an overflow)
#      o1 an Opus Explore with no model in its meta: NOT a Haiku run
#   S2 main (Opus) + cost-state (Opus out 500, Haiku 5.5 out 200), one general-purpose spawn b1
#      requested haiku @medium (meta only, no effort on its records) that ends in a refusal, out 10
#   S3 a main thread served by Haiku 5.5 (a `claude -p --model haiku` run): a Haiku run, no cost-state
#   S4 main (Opus) + cost-state (Opus out 1000, Haiku 5.5 out 100), no Haiku workers
# so helper output is 350-50 + 200-10 + 100 = 590, and 100 of 1100 in the no-Haiku-worker sessions.
# The budget flag cache and the extraction validation log are fixture files too.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  L="$REPO_ROOT/bin/cc-token-ledger"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export CC_TOKEN_LEDGER_WORKERS=1 CC_MODEL_CONFIG="$BATS_TEST_TMPDIR/model-config.yaml"
  export CC_EXTRACTION_LOG="$BATS_TEST_TMPDIR/extraction-validate.jsonl"
  cat > "$CC_MODEL_CONFIG" <<'EOF'
versions:
  haiku_latest: claude-haiku-5-5            # comment
pricing_per_mtok:
  claude-opus-5-5: [4, 20]
  claude-haiku-5-5: [0.10, 0.50]
  claude-haiku-4-5: [1, 5]
EOF
  python3 - "$HOME" <<'PY'
import json, os, sys
from datetime import datetime, timezone
home = sys.argv[1]
P = os.path.join(home, ".claude-next", "projects", "-proj")
def dump(path, recs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        for r in recs:
            fh.write(json.dumps(r, separators=(",", ":")) + "\n")
def asst(mid, model, out, ts, stop="end_turn", effort=None, text="ok"):
    r = {"type": "assistant", "timestamp": ts,
         "message": {"id": mid, "model": model, "stop_reason": stop,
                     "content": [{"type": "text", "text": text}],
                     "usage": {"input_tokens": 10, "output_tokens": out, "cache_read_input_tokens": 0,
                               "cache_creation_input_tokens": 0}}}
    if effort:
        r["effort"] = effort
    return r
def user(ts):
    return {"type": "user", "timestamp": ts, "message": {"role": "user", "content": "go"}}
def err(ts, text):
    return {"type": "assistant", "timestamp": ts, "isApiErrorMessage": True, "error": "invalid_request",
            "message": {"id": "e-" + ts, "model": "<synthetic>", "content": [{"type": "text", "text": text}]}}
def ms(iso):
    return int(datetime.strptime(iso, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp() * 1000)
def cost(start, usage):
    return {"type": "cost-state", "startTime": ms(start), "totalCostUSD": 0,
            "modelUsage": {m: {"inputTokens": 0, "cacheCreationInputTokens": 0, "cacheReadInputTokens": 0,
                               "outputTokens": o} for m, o in usage.items()}}
def meta(path, **kw):
    with open(path[:-len(".jsonl")] + ".meta.json", "w") as fh:
        json.dump(kw, fh)

S1, S2, S3, S4 = ("11111111-0000-4000-8000-00000000000%d" % i for i in (1, 2, 3, 4))
dump(f"{P}/{S1}.jsonl", [user("2026-10-01T10:00:00"), asst("m-s1", "claude-opus-5-5", 1000, "2026-10-01T10:00:05"),
                         cost("2026-10-01T09:59:00", {"claude-opus-5-5": 1000, "claude-haiku-5-5": 350})])
a1 = f"{P}/{S1}/subagents/agent-a1.jsonl"
dump(a1, [user("2026-10-01T10:01:00"),
          asst("m-a1a", "claude-haiku-5-5", 30, "2026-10-01T10:01:04", stop="tool_use", effort="medium"),
          asst("m-a1b", "claude-haiku-5-5", 20, "2026-10-01T10:01:10", effort="medium")])
meta(a1, agentType="Explore", model="haiku", effort="medium")
a2 = f"{P}/{S1}/subagents/agent-a2.jsonl"
dump(a2, [user("2026-10-01T10:02:00"),
          asst("m-a2a", "claude-haiku-4-5-20251001", 40, "2026-10-01T10:02:05", stop="tool_use", effort="high"),
          err("2026-10-01T10:02:30", "Prompt is too long")])
meta(a2, agentType="Explore", model="haiku")
o1 = f"{P}/{S1}/subagents/agent-o1.jsonl"
dump(o1, [user("2026-10-01T10:03:00"), asst("m-o1", "claude-opus-5-5", 90, "2026-10-01T10:03:09", effort="high")])
meta(o1, agentType="Explore")
dump(f"{P}/{S2}.jsonl", [user("2026-10-01T11:00:00"), asst("m-s2", "claude-opus-5-5", 500, "2026-10-01T11:00:05"),
                         cost("2026-10-01T10:59:00", {"claude-opus-5-5": 500, "claude-haiku-5-5": 200})])
b1 = f"{P}/{S2}/subagents/agent-b1.jsonl"
dump(b1, [user("2026-10-01T11:01:00"), asst("m-b1", "claude-haiku-5-5", 10, "2026-10-01T11:01:03", stop="refusal")])
meta(b1, agentType="general-purpose", model="haiku", effort="medium")
dump(f"{P}/{S3}.jsonl", [user("2026-10-01T12:00:00"), asst("m-s3", "claude-haiku-5-5", 70, "2026-10-01T12:00:08", effort="low")])
dump(f"{P}/{S4}.jsonl", [user("2026-10-01T13:00:00"), asst("m-s4", "claude-opus-5-5", 1000, "2026-10-01T13:00:05"),
                         cost("2026-10-01T12:59:00", {"claude-opus-5-5": 1000, "claude-haiku-5-5": 100})])
with open(os.path.join(home, ".claude-next", ".claude.json"), "w") as fh:
    json.dump({"cachedGrowthBookFeatures": {"tengu_rippling_tulip": 250000}}, fh)
PY
  printf '%s\n' \
    '{"ts":"2026-10-01T10:00:00","slot":"x","model":"claude-haiku-5-5","attempt":1,"valid":false}' \
    '{"ts":"2026-10-01T10:00:09","slot":"x","model":"claude-haiku-5-5","attempt":2,"valid":true}' \
    '{"ts":"2026-10-01T10:01:00","slot":"x","model":"claude-haiku-5-5","attempt":1,"valid":true}' \
    '{"ts":"2026-10-01T10:02:00","slot":"x","model":"claude-haiku-5-5","attempt":1,"valid":true}' \
    '{"ts":"2026-09-01T10:00:00","slot":"x","model":"claude-haiku-5-5","attempt":1,"valid":false}' \
    > "$CC_EXTRACTION_LOG"
}

_j() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }
haiku_json() { "$L" --since 2026-09-30 --haiku --json; }

@test "runs: Haiku spawns and a Haiku-served main thread count; an Opus Explore does not" {
  run haiku_json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s' "$output" | _j 'len(d["runs"])')" -eq 4 ]
  [ "$(printf '%s' "$output" | _j 'sorted(r["agent_id"] for r in d["runs"])')" = "['', 'a1', 'a2', 'b1']" ]
  [ "$(printf '%s' "$output" | _j '[r for r in d["runs"] if r["agent_id"]=="a1"][0]["turns"]')" -eq 2 ]
  [ "$(printf '%s' "$output" | _j '[r for r in d["runs"] if r["agent_id"]=="a1"][0]["output_tokens"]')" -eq 50 ]
  [ "$(printf '%s' "$output" | _j '[r for r in d["runs"] if r["agent_id"]=="a1"][0]["wall_s"]')" = "10.0" ]
}

@test "effort: the transcript's own value wins, the meta request is the fallback, off-pin share counted" {
  run haiku_json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["summary"]["effort_by_spawn"]')" = "{'medium': 2, 'high': 1}" ]
  [ "$(printf '%s' "$output" | _j '[r["effort_source"] for r in d["runs"] if r["agent_id"]=="b1"][0]')" = meta ]
  [ "$(printf '%s' "$output" | _j '(d["summary"]["effort_off_pin"]["n"], d["summary"]["effort_off_pin"]["of"])')" = "(1, 3)" ]
  [ "$(printf '%s' "$output" | _j '(d["summary"]["effort_off_pin_explore"]["n"], d["summary"]["effort_off_pin_explore"]["of"])')" = "(1, 2)" ]
}

@test "served mismatch: a haiku alias served the previous model is named against versions.haiku_latest" {
  run haiku_json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j '(d["summary"]["served_mismatch"]["n"], d["summary"]["served_mismatch"]["of"])')" = "(1, 3)" ]
  [ "$(printf '%s' "$output" | _j 'd["summary"]["served_mismatch"]["runs"][0]["served"]')" = "['claude-haiku-4-5']" ]
}

@test "refusals, retrieval errors and context overflow are counted from stop reasons and API errors" {
  run haiku_json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j '(d["summary"]["refusals"]["n"], d["summary"]["refusals"]["of"])')" = "(1, 4)" ]
  [ "$(printf '%s' "$output" | _j '(d["summary"]["retrieval_overflow"]["n"], d["summary"]["retrieval_overflow"]["of"])')" = "(1, 2)" ]
  [ "$(printf '%s' "$output" | _j 'd["summary"]["retrieval_errors"]["n"]')" -eq 1 ]
}

@test "helper share: cost-state Haiku minus transcript Haiku; the no-Haiku-worker subset is exact" {
  run haiku_json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["summary"]["helper"]["all"]["helper_out"]')" -eq 590 ]
  [ "$(printf '%s' "$output" | _j 'd["summary"]["helper"]["all"]["sessions"]')" -eq 3 ]
  [ "$(printf '%s' "$output" | _j 'd["summary"]["helper"]["no_haiku_worker"]["helper_out"]')" -eq 100 ]
  [ "$(printf '%s' "$output" | _j 'd["summary"]["helper"]["no_haiku_worker"]["session_out"]')" -eq 1100 ]
}

@test "extraction JSON: the invalid rate comes from the consumer's log, inside the window only" {
  run haiku_json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["summary"]["extraction_json"]["by_model"]["claude-haiku-5-5"]["attempts"]')" -eq 4 ]
  [ "$(printf '%s' "$output" | _j 'd["summary"]["extraction_json"]["by_model"]["claude-haiku-5-5"]["invalid_rate"]')" = "0.25" ]
  rm "$CC_EXTRACTION_LOG"
  run "$L" --since 2026-09-30 --haiku
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^extraction-json   D2  no consumer validation log'
}

@test "text report: one keyed line per revert trigger, the budget-flag alarm, and the #97763 caveat" {
  run "$L" --since 2026-09-30 --haiku
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  for k in effort-pin retrieval-errors served-mismatch refusals judgment-on-haiku helper-share extraction-json budget-flags; do
    printf '%s\n' "$output" | grep -q "^$k " || { echo "missing line: $k"; echo "$output"; false; }
  done
  printf '%s\n' "$output" | grep -q 'budget-flags      D6  cached: .claude-next:tengu_rippling_tulip=250000.*ALARM'
  printf '%s\n' "$output" | grep -q '#97763'
  printf '%s\n' "$output" | grep -q 'served another model: 1 of 3'
}
