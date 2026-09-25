#!/usr/bin/env bats
# bin/cc-token-ledger — the standing per-task cost instrument (token-efficiency spec, item T2).
#
# The fixture (tests/fixtures/token-ledger/) is two task trees in two config dirs:
#   session A (.claude-secondary): a main thread whose first message is written as THREE records and
#     only the last carries the final output (400); a 2.5 h gap then a full rewrite; then a cache hit;
#     a subagent with no final record; a workflow agent; a cost-state record with Haiku side usage.
#     The same main transcript is also copied into .claude-tertiary (an account transplant).
#   session B (.claude-tertiary): a different CLAUDE.md content, put on the "slim" arm by the variant
#     log before it started, plus one response from a model with no price row.
# Fixture dirs are named dotclaude* (a global gitignore hides .claude-*/) and copied into a scratch
# HOME under their real names. Prices come from the fixture model-config.yaml, never the repo's.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  L="$REPO_ROOT/bin/cc-token-ledger"
  FX="$REPO_ROOT/tests/fixtures/token-ledger"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  local d
  for d in "$FX"/home/dot*; do
    cp -R "$d" "$HOME/.${d##*/dot}"
  done
  export CC_MODEL_CONFIG="$FX/model-config.yaml" CC_TOKEN_LEDGER_WORKERS=1
  SA=aaaaaaaa-0000-4000-8000-000000000001
}

# Read one value out of a JSON document: _j '<python expr over d>' <<< "$json"
_j() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }
_near() { python3 -c 'import sys; a,b=float(sys.argv[1]),float(sys.argv[2]); sys.exit(0 if abs(a-b)<1e-6 else 1)' "$1" "$2"; }
_sha16() { printf '%s' "$1" | shasum -a 256 | cut -c1-16; }

@test "fixture HOME has the config dirs the ledger scans" {
  [ -f "$HOME/.claude-secondary/projects/proj/$SA.jsonl" ]
  [ -f "$HOME/.claude-tertiary/projects/proj/$SA.jsonl" ]
  [ -f "$HOME/.claude/autonomy/instruction-variants.jsonl" ]
}

@test "a message written as several records is one response carrying its final output" {
  run "$L" --since 2026-09-01 --task "$SA" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j '[c for c in d["contexts"] if c["ctx_type"]=="main"][0]["responses"]')" -eq 3 ]
  # 400 (msg_A1's last record, not the first record's 5) + 100 + 50
  [ "$(printf '%s' "$output" | _j '[c for c in d["contexts"] if c["ctx_type"]=="main"][0]["tokens"]["output"]')" -eq 550 ]
}

@test "transplanted copies of a session are dropped from every total" {
  run "$L" --since 2026-09-01 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["meta"]["responses_xdup_dropped"]')" -eq 3 ]
  [ "$(printf '%s' "$output" | _j 'd["fleet"]["responses"]')" -eq 7 ]
  [ "$(printf '%s' "$output" | _j 'd["per_task"]["n_tasks"]')" -eq 2 ]
  run "$L" --since 2026-09-01 --task "$SA"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'main  in .claude-tertiary: a copy, its 3 responses are counted in the original file'
}

@test "1h cache writes are priced at 2x input and 5m writes at 1.25x" {
  run "$L" --since 2026-09-01 --json
  [ "$status" -eq 0 ]
  # claude-opus-5-5 at \$4/MTok: 300,000 5m tokens -> \$1.50; 10,000 1h tokens -> \$0.08
  m55='d["by_model"]["claude-opus-5-5"]'
  [ "$(printf '%s' "$output" | _j "${m55}[\"tokens\"][\"cache_write_5m\"]")" -eq 300000 ]
  _near "$(printf '%s' "$output" | _j "${m55}[\"usd\"][\"cache_write_5m\"]")" 1.5
  [ "$(printf '%s' "$output" | _j "${m55}[\"tokens\"][\"cache_write_1h\"]")" -eq 10000 ]
  _near "$(printf '%s' "$output" | _j "${m55}[\"usd\"][\"cache_write_1h\"]")" 0.08
  # claude-opus-5 at \$5: 2,000,150 1h tokens -> \$20.0015; cache read 1,000,060 at 0.1x -> \$0.50003
  _near "$(printf '%s' "$output" | _j 'd["by_model"]["claude-opus-5"]["usd"]["cache_write_1h"]')" 20.0015
  _near "$(printf '%s' "$output" | _j 'd["by_model"]["claude-opus-5"]["usd"]["cache_read"]')" 0.50003
}

@test "the re-price uses the target model's rates, cache read 0.05x on Opus 5.5" {
  run "$L" --since 2026-09-01 --json
  [ "$status" -eq 0 ]
  # the claude-opus-5 cache read (1,000,060 tokens) at \$4 x 0.05
  _near "$(printf '%s' "$output" | _j 'd["by_model"]["claude-opus-5"]["usd_reprice"]["cache_read"]')" 0.200012
}

@test "a model with no price row is reported and left out of the dollars, never guessed" {
  run "$L" --since 2026-09-01 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["unpriced_models"]["claude-opus-4-7"]["responses"]')" -eq 1 ]
  _near "$(printf '%s' "$output" | _j 'd["by_model"]["claude-opus-4-7"]["usd_total"]')" 0
  run "$L" --since 2026-09-01
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'UNPRICED.*claude-opus-4-7 (1 responses)'
}

@test "a task tree groups the main thread, its subagent and its workflow agent" {
  run "$L" --since 2026-09-01 --task "$SA" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j '",".join(c["ctx_type"] for c in d["contexts"] if c["responses"])')" = "main,subagent,workflow_agent" ]
  [ "$(printf '%s' "$output" | _j 'd["tree"]["responses"]')" -eq 5 ]
  run "$L" --since 2026-09-01 --json
  [ "$(printf '%s' "$output" | _j 'd["per_task"]["tasks_with_workers"]')" -eq 1 ]
  # worker \$ = subagent 1.00016 + workflow 0.50062 over the whole fleet
  [ "$(printf '%s' "$output" | _j 'round(d["by_ctx_type"]["subagent"]["usd_total"]+d["by_ctx_type"]["workflow_agent"]["usd_total"],5)')" = "1.50078" ]
}

@test "a task prefix resolves; an unknown task exits 1" {
  run "$L" --since 2026-09-01 --task aaaaaaaa --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["session_id"]')" = "$SA" ]
  run "$L" --since 2026-09-01 --task ffffffff
  [ "$status" -eq 1 ]
}

@test "write classes: START, a REWRITE after a gap over 1h, then INCREMENTAL" {
  run "$L" --since 2026-09-01 --task "$SA" --json
  [ "$status" -eq 0 ]
  wc='[c for c in d["contexts"] if c["ctx_type"]=="main"][0]["write_classes"]'
  [ "$(printf '%s' "$output" | _j "sorted($wc)")" = "['INCREMENTAL', 'REWRITE gap>60m', 'START']" ]
  [ "$(printf '%s' "$output" | _j "${wc}[\"REWRITE gap>60m\"][\"write_tokens\"]")" -eq 1000050 ]
  [ "$(printf '%s' "$output" | _j '[c for c in d["contexts"] if c["ctx_type"]=="main"][0]["first_request_prefix_tokens"]')" -eq 1000010 ]
  run "$L" --since 2026-09-01 --task "$SA"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'REWRITE gap>60m'
}

@test "arms are labelled by CLAUDE.md content and the variant log" {
  run "$L" --since 2026-09-01 --by-arm --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["variant_log"]')" = "present" ]
  [ "$(printf '%s' "$output" | _j 'len(d["arms"])')" -eq 2 ]
  [ "$(printf '%s' "$output" | _j '[a["sha"] for a in d["arms"] if a["arm"]=="shared"][0]')" = "$(_sha16 'shared instructions v1')" ]
  [ "$(printf '%s' "$output" | _j '[a["sha"] for a in d["arms"] if a["arm"]=="slim"][0]')" = "$(_sha16 'slim instructions')" ]
  # guardrail columns: session A had 2 tool results, 1 an error; session B had 1, no error
  _near "$(printf '%s' "$output" | _j '[a["tool_error_rate"] for a in d["arms"] if a["arm"]=="shared"][0]')" 0.5
  _near "$(printf '%s' "$output" | _j '[a["tool_error_rate"] for a in d["arms"] if a["arm"]=="slim"][0]')" 0
  [ "$(printf '%s' "$output" | _j '[a["responses_per_task"]["mean"] for a in d["arms"] if a["arm"]=="shared"][0]')" = "5.0" ]
  [ "$(printf '%s' "$output" | _j '[a["accounts"] for a in d["arms"] if a["arm"]=="slim"][0]')" = "['.claude-tertiary']" ]
}

@test "one CLAUDE.md content on two accounts is one arm row" {
  f="$HOME/.claude-tertiary/projects/proj/bbbbbbbb-0000-4000-8000-000000000002.jsonl"
  sed 's/slim instructions/shared instructions v1/' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  rm "$HOME/.claude/autonomy/instruction-variants.jsonl"
  run "$L" --since 2026-09-01 --by-arm --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'len(d["arms"])')" -eq 1 ]
  [ "$(printf '%s' "$output" | _j 'd["arms"][0]["tasks"]')" -eq 2 ]
  [ "$(printf '%s' "$output" | _j 'd["arms"][0]["accounts"]')" = "['.claude-secondary', '.claude-tertiary']" ]
}

@test "without a variant log the arm column reads '-', the content label remains" {
  rm "$HOME/.claude/autonomy/instruction-variants.jsonl"
  run "$L" --since 2026-09-01 --by-arm --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["variant_log"]')" = "absent" ]
  [ "$(printf '%s' "$output" | _j 'sorted(a["arm"] for a in d["arms"])')" = "['-', '-']" ]
}

@test "side requests: cost-state usage the transcripts never recorded" {
  run "$L" --since 2026-09-01 --side-requests --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["sessions_compared"]')" -eq 1 ]
  [ "$(printf '%s' "$output" | _j 'd["by_model"]["claude-haiku-4-5"]["delta_tokens"]["input"]')" -eq 2000000 ]
  [ "$(printf '%s' "$output" | _j 'd["by_model"]["claude-opus-5"]["delta_tokens"]["input"]')" -eq 1000 ]
  # Haiku 2,000,000 x \$1 + Opus 5 1,000 x \$5
  _near "$(printf '%s' "$output" | _j 'd["usd_side_estimate_total"]')" 2.005
}

@test "--check exits 0 when no settings.json sets ENABLE_PROMPT_CACHING_1H" {
  printf '{"env":{"OTHER":"1"}}\n' > "$HOME/.claude-secondary/settings.json"
  run "$L" --check
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^ok:'
}

@test "--check exits 1 and names the file when ENABLE_PROMPT_CACHING_1H is set" {
  printf '{"env":{"ENABLE_PROMPT_CACHING_1H":"1"}}\n' > "$HOME/.claude-tertiary/settings.json"
  run "$L" --check
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'claude-tertiary/settings.json'
  run "$L" --check --json
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | _j 'd["ok"]')" = "False" ]
}

@test "--since outside the fixture window reports nothing; a bad --since is a usage error" {
  run "$L" --since 2026-09-22 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["fleet"]["responses"]')" -eq 0 ]
  run "$L" --since yesterday
  [ "$status" -eq 2 ]
}

@test "relative --since is measured from CC_NOW" {
  CC_NOW=1758450000 run "$L" --since 1d --json   # 2025-09-21T10:20Z: the fixture is a year later
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["meta"]["since"]')" = "2025-09-20T10:20:00" ]
}

@test "the worker pool gives the same totals as the single-process path" {
  one="$("$L" --since 2026-09-01 --json | _j 'round(d["fleet"]["usd_total"],6)')"
  four="$(CC_TOKEN_LEDGER_WORKERS=4 "$L" --since 2026-09-01 --json | _j 'round(d["fleet"]["usd_total"],6)')"
  [ -n "$one" ]
  [ "$one" = "$four" ]
}

# Session C: a subagent tree with 25 FINAL responses shaped like session A's subagent message, so the
# imputation strata reach n >= 20 and session A's unfinished subagent response gets output_est = 1000.
_add_session_c() {
  python3 - "$HOME/.claude-secondary/projects/proj/cccccccc-0000-4000-8000-000000000003/subagents/agent-c1.jsonl" <<'PY'
import json, os, sys
p = sys.argv[1]
os.makedirs(os.path.dirname(p), exist_ok=True)
sid = "cccccccc-0000-4000-8000-000000000003"
with open(p, "w") as fh:
    for i in range(25):
        fh.write(json.dumps({"type": "assistant", "timestamp": "2026-09-20T11:%02d:00.000Z" % i, "sessionId": sid,
            "message": {"model": "claude-opus-5-5", "id": "msg_C%d" % i, "role": "assistant",
                        "content": [{"type": "tool_use", "id": "tu_C%d" % i, "name": "Read", "input": {"file_path": "/y"}}],
                        "stop_reason": "tool_use",
                        "usage": {"input_tokens": 5, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 1000,
                                  "output_tokens": 1000}}}, separators=(",", ":")) + "\n")
PY
}

@test "--task and the fleet view price one tree the same, imputation included" {
  _add_session_c
  run "$L" --since 2026-09-01 --json
  [ "$status" -eq 0 ]
  fleet_usd="$(printf '%s' "$output" | _j '[t["usd_total"] for t in d["per_task"]["top"] if t["session_id"]=="'"$SA"'"][0]')"
  fleet_out="$(printf '%s' "$output" | _j '[t["output"] for t in d["per_task"]["top"] if t["session_id"]=="'"$SA"'"][0]')"
  [ -n "$fleet_usd" ]
  run "$L" --since 2026-09-01 --task "$SA" --json
  [ "$status" -eq 0 ]
  _near "$(printf '%s' "$output" | _j 'd["tree"]["usd_total"]')" "$fleet_usd"
  [ "$(printf '%s' "$output" | _j 'd["tree"]["tokens"]["output"]')" -eq "$fleet_out" ]
  # the subagent's unfinished response (7 recorded) was imputed from session C's stratum
  [ "$(printf '%s' "$output" | _j '[c for c in d["contexts"] if c["ctx_type"]=="subagent"][0]["tokens"]["output"]')" -eq 1000 ]
}

@test "--task --quick scans only the tree and reports recorded output" {
  _add_session_c
  run "$L" --since 2026-09-01 --task "$SA" --quick --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["meta"]["quick"]')" = "True" ]
  [ "$(printf '%s' "$output" | _j '[c for c in d["contexts"] if c["ctx_type"]=="subagent"][0]["tokens"]["output"]')" -eq 7 ]
  [ "$(printf '%s' "$output" | _j 'd["tree"]["tokens"]["output"]==d["tree"]["output_recorded"]')" = "True" ]
  run "$L" --since 2026-09-01 --task "$SA" --quick
  printf '%s\n' "$output" | grep -q 'output as recorded (no imputation)'
  run "$L" --since 2026-09-01 --quick
  [ "$status" -eq 2 ]
}

@test "side requests: a model under two cost-state keys is summed before subtracting" {
  for f in "$HOME"/.claude-*/projects/proj/"$SA".jsonl; do
    python3 - "$f" <<'PY'
import json, sys
p = sys.argv[1]
lines = open(p).read().splitlines()
for i, line in enumerate(lines):
    r = json.loads(line)
    if r.get("type") == "cost-state":
        u = r["modelUsage"].pop("claude-opus-5")
        half = {k: v // 2 for k, v in u.items()}
        r["modelUsage"]["claude-opus-5"] = half
        r["modelUsage"]["claude-opus-5[1m]"] = {k: v - half[k] for k, v in u.items()}
        lines[i] = json.dumps(r)
open(p, "w").write("\n".join(lines) + "\n")
PY
  done
  run "$L" --since 2026-09-01 --side-requests --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["by_model"]["claude-opus-5"]["delta_tokens"]')" = "{'input': 1000, 'cache_write': 0, 'cache_read': 0, 'output': 0}" ]
  _near "$(printf '%s' "$output" | _j 'd["usd_side_estimate_total"]')" 2.005
  _near "$(printf '%s' "$output" | _j 'd["sessions"][0]["usd_side_estimate"]')" 2.005
}

@test "side requests: non-Haiku cache-write and output deltas are shown, not priced" {
  for f in "$HOME"/.claude-*/projects/proj/"$SA".jsonl; do
    sed 's/"outputTokens":550,"cacheReadInputTokens":1000060,"cacheCreationInputTokens":2000150/"outputTokens":1550,"cacheReadInputTokens":1000060,"cacheCreationInputTokens":3000150/' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done
  run "$L" --since 2026-09-01 --side-requests --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["by_model"]["claude-opus-5"]["delta_tokens"]["cache_write"]')" -eq 1000000 ]
  [ "$(printf '%s' "$output" | _j 'd["by_model"]["claude-opus-5"]["delta_tokens"]["output"]')" -eq 1000 ]
  _near "$(printf '%s' "$output" | _j 'd["usd_side_estimate_total"]')" 2.005
}

@test "side requests: a session still writing at --until is skipped" {
  run "$L" --since 2026-09-01 --until 2026-09-20T11:00 --side-requests --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["sessions_compared"]')" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["sessions_skipped_past_until"]')" -eq 1 ]
  run "$L" --since 2026-09-01 --until 2026-09-22 --side-requests --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["sessions_compared"]')" -eq 1 ]
}

@test "--check treats a falsy ENABLE_PROMPT_CACHING_1H as not set" {
  printf '{"env":{"ENABLE_PROMPT_CACHING_1H":"0"}}\n' > "$HOME/.claude-secondary/settings.json"
  printf '{"env":{"ENABLE_PROMPT_CACHING_1H":"false"}}\n' > "$HOME/.claude-tertiary/settings.json"
  run "$L" --check
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^ok: ENABLE_PROMPT_CACHING_1H is not set in 2 settings file'
}

@test "price lookup: the repo's model-config.yaml, then ~/.claude, else exit 2; unknown --reprice exits 2" {
  unset CC_MODEL_CONFIG
  run "$L" --since 2026-09-01 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'd["meta"]["model_config"]')" = "$(cd "$REPO_ROOT" && pwd -P)/model-config.yaml" ]
  # a copy outside the repo finds no sibling model-config.yaml
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere/bin"
  cp "$L" "$BATS_TEST_TMPDIR/elsewhere/bin/cc-token-ledger"
  run "$BATS_TEST_TMPDIR/elsewhere/bin/cc-token-ledger" --since 2026-09-01
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -q 'no pricing_per_mtok found'
  cp "$FX/model-config.yaml" "$HOME/.claude/model-config.yaml"
  run "$BATS_TEST_TMPDIR/elsewhere/bin/cc-token-ledger" --since 2026-09-01 --json
  [ "$status" -eq 0 ]
  # the ledger prints HOME as ~
  [ "$(printf '%s' "$output" | _j 'd["meta"]["model_config"]=="~/.claude/model-config.yaml"')" = "True" ]
  run "$BATS_TEST_TMPDIR/elsewhere/bin/cc-token-ledger" --since 2026-09-01 --reprice claude-nope-9
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -q 'reprice claude-nope-9 has no price row'
}

@test "write classes: REWRITE gap<5m, gap5-60m, model_switch and shrink" {
  cp "$FX"/walk/dddddddd-*.jsonl "$HOME/.claude-secondary/projects/proj/"
  run "$L" --since 2026-09-01 --task dddddddd --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j 'sorted(d["contexts"][0]["write_classes"])')" = "['INCREMENTAL', 'REWRITE gap5-60m', 'REWRITE gap<5m', 'REWRITE model_switch', 'REWRITE shrink', 'START']" ]
  [ "$(printf '%s' "$output" | _j 'd["contexts"][0]["write_classes"]["REWRITE shrink"]["write_tokens"]')" -eq 50000 ]
}

@test "a context straddling --since flags its first in-window prefix as START_TRUNC" {
  run "$L" --since 2026-09-20T11:00 --task "$SA" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j '[c for c in d["contexts"] if c["ctx_type"]=="main"][0]["first_request_truncated"]')" = "True" ]
  run "$L" --since 2026-09-20T11:00 --task "$SA"
  printf '%s\n' "$output" | grep -q 'first in-window prefix (seq 1, START_TRUNC)'
  run "$L" --since 2026-09-01 --task "$SA" --json
  [ "$(printf '%s' "$output" | _j '[c for c in d["contexts"] if c["ctx_type"]=="main"][0]["first_request_truncated"]')" = "False" ]
}

@test "the arm is read at the session start, not at the first in-window record" {
  # tertiary switches to "fat" one second after session B started; B's first in-window record is later
  printf '{"ts":"2026-09-21T09:00:01Z","account":".claude-tertiary","variant":"fat","action":"set"}\n' \
    >> "$HOME/.claude/autonomy/instruction-variants.jsonl"
  run "$L" --since 2026-09-21T09:00:03 --by-arm --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _j '[a["arm"] for a in d["arms"] if a["sha"]=="'"$(_sha16 'slim instructions')"'"][0]')" = "slim" ]
}

@test "--by-agent-type groups worker contexts by the agentType in each transcript's .meta.json" {
  run "$L" --since 2026-09-01 --by-agent-type --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # the workflow agent carries agent-w1.meta.json (workflow-lean); the subagent has no meta file
  [ "$(printf '%s' "$output" | _j '",".join("%s/%s/%d" % (a["ctx_type"], a["agent_type"], a["contexts"]) for a in sorted(d["agent_types"], key=lambda a: a["ctx_type"]))')" = "subagent/(no meta)/1,workflow_agent/workflow-lean/1" ]
  # the dollars are the same worker dollars the fleet view reports: subagent 1.00016 + workflow 0.50062
  [ "$(printf '%s' "$output" | _j 'round(sum(a["usd_total"] for a in d["agent_types"]),5)')" = "1.50078" ]
  [ "$(printf '%s' "$output" | _j '[round(a["usd_total"],5) for a in d["agent_types"] if a["agent_type"]=="workflow-lean"][0]')" = "0.50062" ]
  # main threads are never a worker context
  [ "$(printf '%s' "$output" | _j 'sum(a["ctx_type"]=="main" for a in d["agent_types"])')" -eq 0 ]
  run "$L" --since 2026-09-01 --by-agent-type
  [ "$status" -eq 0 ]
  [[ "$output" == *"workflow-lean"* ]] || false
}
