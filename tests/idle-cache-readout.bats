#!/usr/bin/env bats
# cc-idle-cache-readout — the read-out over the two W3 shadow logs (docs/plans/USAGE_LEVERS.md § W3).
#
# Owns the CLI contract: per account (named through accounts.json) and day, the would-wake count and
# priced outcome of the main-session keepalive; the subagent rule joined to each call's REAL runtime
# and next-request cache write from the subagent transcript, priced as wrongly denied vs rebuild
# avoided; the per-account acceptance line against the 0.2% bar; exit 2 on bad usage.
# The per-gap pricing itself is owned by tests/idle-keepalive.bats (2); this suite checks the sums.
# RED-proof: new CLI. Mutant checked by hand: inverting the 270 s runtime split fails (2).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RO="$REPO/bin/cc-idle-cache-readout"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export CC_IDLE_KEEPALIVE_LOG="$HOME/.claude/logs/idle-keepalive.jsonl"
  export CC_IDLE_KEEPALIVE_STATE="$BATS_TEST_TMPDIR/state"; mkdir -p "$CC_IDLE_KEEPALIVE_STATE"
  export CC_SUBAGENT_LONG_BASH_LOG="$HOME/.claude/logs/subagent-long-bash.jsonl"
  printf '{"accounts":[{"name":"next3","config_dir":"~/.claude-tertiary"}]}\n' > "$HOME/.claude/accounts.json"
  NOW=$(date +%s); T="$(date -u -r $((NOW - 3600)) +%FT%TZ)"
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

gap() { # <outcome> <wakes> <net_lo> <net_hi>
  jq -nc --arg ts "$T" --arg o "$1" --argjson w "$2" --argjson lo "$3" --argjson hi "$4" \
    '{kind:"gap",v:1,ts:$ts,acct:".claude-tertiary",dur:3900,ctx:200000,wake_s:3300,ttl_s:3600,
      wakes:$w,outcome:$o,obs_cw:200000,net_pp:[$lo,$hi]}' >> "$CC_IDLE_KEEPALIVE_LOG"
}
use_result() { # <agent file> <tool_use_id> <use epoch> <result epoch> <next cache write>
  local f="$1"
  {
  printf '{"type":"assistant","timestamp":"%s","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":99949,"output_tokens":50},"content":[{"type":"tool_use","id":"%s","name":"Bash"}]}}\n' "$(date -u -r "$3" +%FT%TZ)" "$2"
  printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"%s","content":"ok"}]}}\n' "$(date -u -r "$4" +%FT%TZ)" "$2"
  printf '{"type":"assistant","timestamp":"%s","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":%s,"cache_read_input_tokens":0,"output_tokens":50},"content":[]}}\n' "$(date -u -r $(($4 + 2)) +%FT%TZ)" "$5"
  } >> "$f"
}
subrow() { # <tool_use_id> <narrow true|false> <why>
  jq -nc --arg ts "$T" --arg t "$1" --argjson n "$2" --arg w "$3" --arg tp "$BATS_TEST_TMPDIR/proj/s1.jsonl" \
    '{kind:"subagent_bash",v:1,ts:$ts,acct:".claude-tertiary",sid:"s1",agent_id:"a1",tool_use_id:$t,
      timeout_ms:600000,broad:true,narrow:$n,why:(if $w == "" then null else $w end),transcript_path:$tp}' >> "$CC_SUBAGENT_LONG_BASH_LOG"
}

@test "(1) main sessions: per-account-day counts and summed net pp, with the timer and open-gap lines" {
  gap wake_saves 1 0.04 0.05; gap wake_unneeded 1 -0.002 -0.001; gap no_wake 0 0 0
  jq -nc --arg ts "$T" '{kind:"wake",v:1,ts:$ts,acct:".claude-tertiary",n:1,ctx:200000,watcher_armed:true}' >> "$CC_IDLE_KEEPALIVE_LOG"
  printf '{"sid":"x","start":%s,"ctx":1}\n' $((NOW - 7200)) > "$CC_IDLE_KEEPALIVE_STATE/x.json"
  run /usr/bin/env python3 "$RO" --days 1 --json
  [ "$status" -eq 0 ]
  d="$(date -u -r $((NOW - 3600)) +%F)"
  [ "$(jq -c --arg k "next3 $d" '.main.per_day[$k] | [.gaps,.would_wake,.wake_saves,.wake_unneeded,.wake_rows,.watcher_armed,.net_pp]' <<<"$output")" \
    = '[3,2,1,1,1,1,[0.038,0.049]]' ]
  [ "$(jq -c '[.main.timer.wake_rows, .main.timer.gaps_lasting_past_due, .main.open_gaps.past_would_wake]' <<<"$output")" = '[1,3,1]' ]
  run /usr/bin/env python3 "$RO" --days 1 --no-resolve
  [ "$status" -eq 0 ]
  [[ "$output" == *"next3 $d"* ]] || false
  [[ "$output" == *"Timer: 1 would-wake rows against 3 gaps"* ]] || false
}

@test "(2) subagents: runtime from the transcript splits wrongly denied from rebuilds avoided" {
  A="$BATS_TEST_TMPDIR/proj/s1/subagents/workflows/wf1/agent-a1.jsonl"; mkdir -p "${A%/*}"
  b=$((NOW - 3600))
  use_result "$A" t_short $b $((b + 10)) 300                # 10 s: the deny was for nothing
  use_result "$A" t_long $((b + 20)) $((b + 440)) 100100    # 7 min: the cache expired, context re-written
  use_result "$A" t_broad $((b + 500)) $((b + 505)) 200     # not narrowed
  subrow t_short true poll-loop; subrow t_long true poll-loop; subrow t_broad false ""
  run /usr/bin/env python3 "$RO" --days 1 --json
  [ "$status" -eq 0 ]
  d="$(date -u -r $((NOW - 3600)) +%F)"
  [ "$(jq -c --arg k "next3 $d" '[.subagents.variants.narrow[$k] | .n,.resolved,.wrong,.rescued]' <<<"$output")" = '[2,2,1,1]' ]
  [ "$(jq -c --arg k "next3 $d" '[.subagents.variants.broad[$k] | .n,.wrong]' <<<"$output")" = '[3,2]' ]
  [ "$(jq -c --arg k "next3 $d" '.subagents.variants.narrow_first[$k].n' <<<"$output")" = 1 ]
  jq -e --arg k "next3 $d" '.subagents.variants.narrow[$k] | .wrong_pp[1] < 0 and .net_pp[0] > 0' <<<"$output" >/dev/null
  jq -e '.subagents.accept.next3.under_0_2pct == true' <<<"$output" >/dev/null
  run /usr/bin/env python3 "$RO" --days 1
  [[ "$output" == *"ACCEPT next3:"*"under the 0.2% bar"* ]] || false
}

@test "(3) empty logs still print a read-out; a non-positive --days is a usage error" {
  run /usr/bin/env python3 "$RO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no gap rows yet)"* ]] || false
  [[ "$output" == *"not registered until migration 0077"* ]] || false
  run /usr/bin/env python3 "$RO" --days 0
  [ "$status" -eq 2 ]
}
