#!/usr/bin/env bats
# migration 0035 — lever 4 of docs/research/opus55-feature-adoption-2026-09-22/README.md.
#
# 0035 stages CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS=12 into every config dir's settings `env`
# (c10: staged for the operator, never self-run). Without it 2.1.280's gate is
# min(16, max(2, availableParallelism-2)) = 8 on this 10-core box, so a default 10-agent research
# wave queues 2 agents behind the first finisher.
#
# Pins: the class is c10; the verify oracle DISCRIMINATES (fails before, passes after); the edit
# keeps every sibling key and every other env key; a second run is a no-op with no second backup;
# the conflict arm names a different value; and the value stays inside the parser's 1..256 and at
# or above the research wave's default N.
#
# Hermetic: $HOME is a fixture under BATS_TEST_TMPDIR; nothing reads the operator's config.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  M="$REPO_ROOT/migrations/0035-workflow-concurrency.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude" "$HOME/.claude-next"
  jq -n '{env:{MCP_TIMEOUT:"30000"}, effortLevel:"high", hooks:{Stop:[]}}' > "$HOME/.claude/settings.json"
  jq -n '{hooks:{Stop:[]}}' > "$HOME/.claude-next/settings.json"   # no env block at all
}

header() { sed -n "s/^# *migration-$1: *//p" "$M" | head -1; }

@test "1: 0035 is c10 and names its operator step" {
  [ "$(header class)" = "c10" ]
  [ -n "$(header step)" ]
}

@test "2: the verify oracle fails before the migration and passes after it, in every dir" {
  verify="$(header verify)"
  for d in .claude .claude-next; do
    run env CC_CLAUDE_DIR="$HOME/$d" bash -c "$verify"
    [ "$status" -ne 0 ] || { echo "$d: oracle passed BEFORE the migration ran"; false; }
  done
  run bash "$M"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  for d in .claude .claude-next; do
    run env CC_CLAUDE_DIR="$HOME/$d" bash -c "$verify"
    [ "$status" -eq 0 ] || { echo "$d: oracle failed AFTER the migration ran"; false; }
  done
}

@test "3: the edit keeps sibling keys and other env keys, and creates env when absent" {
  bash "$M" >/dev/null
  jq -e '.env.MCP_TIMEOUT == "30000" and .effortLevel == "high" and (.hooks.Stop | type == "array")' \
    "$HOME/.claude/settings.json" >/dev/null || { cat "$HOME/.claude/settings.json"; false; }
  jq -e '.env.CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS == "12" and (.hooks.Stop | type == "array")' \
    "$HOME/.claude-next/settings.json" >/dev/null || { cat "$HOME/.claude-next/settings.json"; false; }
}

@test "4: a second run is a no-op and takes no second backup" {
  bash "$M" >/dev/null
  n1="$(find "$HOME" -name 'settings.json.bak-0035-*' | wc -l | tr -d ' ')"
  run bash "$M"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already"* ]]
  n2="$(find "$HOME" -name 'settings.json.bak-0035-*' | wc -l | tr -d ' ')"
  [ "$n1" = "$n2" ] || { echo "backups $n1 -> $n2"; false; }
}

@test "5: the conflict arm fires on a different value and is silent on the intended one" {
  conflict="$(header conflict)"
  jq '.env.CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS = "4"' "$HOME/.claude/settings.json" > "$HOME/t" && mv "$HOME/t" "$HOME/.claude/settings.json"
  run env CC_CLAUDE_DIR="$HOME/.claude" bash -c "$conflict"
  [ "$status" -eq 0 ] || { echo "conflict arm missed a different value"; false; }
  bash "$M" >/dev/null
  run env CC_CLAUDE_DIR="$HOME/.claude" bash -c "$conflict"
  [ "$status" -ne 0 ] || { echo "conflict arm fired on the intended value"; false; }
}

@test "6: the staged value is inside the parser's range and covers the default research wave" {
  val="$(sed -n 's/^VAL="\([0-9]*\)"$/\1/p' "$M")"
  [ -n "$val" ] && [ "$val" -ge 1 ] && [ "$val" -le 256 ] || { echo "VAL='$val' outside 1..256"; false; }
  # The research-subagents skill's default N; the whole point is that a default wave is one round.
  [ "$val" -ge 10 ] || { echo "VAL=$val is below the default wave N=10"; false; }
}
