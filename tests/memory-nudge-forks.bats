#!/usr/bin/env bats
# memory-nudge-forks.bats — the process budget of hooks/memory-nudge.sh on a NON-DUE prompt.
#
# The defect this pins (docs/research/load-hook-timeouts-2026-10-11/DESIGN.md item 5): memory-nudge
# caused 28 of 162 UserPromptSubmit cancels at load ~420. Eleven prompts in twelve are not due, yet
# each one measured the index (`_mn_stats` jq, `wc`, seven `cut`s), re-resolved the index path
# (`git`, `tr`, `dirname`), pruned a directory of ~1,000 counter files and forked jq/date/wc/tr for
# each of its two IDL rows: about 40-75 process creations to print nothing, measured 1.39 s.
#
# Every external command the hook runs is counted through PATH stubs: each name on the real PATH
# gets a wrapper that logs its name and then execs the real tool, so behavior is unchanged and an
# unstubbed call cannot slip past the count. The hook is reached through a symlink, as the live
# layer reaches it, so the self-deref is counted too. Hermetic: HOME, config, state and IDL live
# in the test tmpdir.
#
# Assertions are simple commands only (bash exempts `[[ ]]` from errexit in a bats body).

setup_file() {
  STUB="$BATS_FILE_TMPDIR/stub"; mkdir -p "$STUB"
  local d f name
  local IFS=:
  # First occurrence wins, exactly as PATH lookup resolves it.
  for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      name="${f##*/}"
      [ -x "$f" ] && [ ! -d "$f" ] || continue
      case "$name" in *\'*|'') continue ;; esac
      [ -e "$STUB/$name" ] && continue
      printf '#!/bin/bash\nprintf %%s\\\\n %s >> "$MN_FORK_LOG"\nexec %s "$@"\n' \
        "'$name'" "'$f'" > "$STUB/$name"
    done
  done
  chmod +x "$STUB"/*
  export STUB
}

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  # Physical spelling: the nudge names the index by its resolved path (memory-nudge.sh WANT).
  CLAUDE_CONFIG_DIR="$(cd "$BATS_TEST_TMPDIR" && pwd -P)/cfg"
  export CLAUDE_CONFIG_DIR
  export MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export MN_FORK_LOG="$BATS_TEST_TMPDIR/forks.log"
  unset MEMORY_INDEX_PATH MEMORY_NUDGE_INTERVAL CLAUDE_PROJECT_DIR CC_RULING_SHADOW CC_EPISODIC_CUE
  unset MEMORY_ROTATE_AT MEMORY_INDEX_LIMIT MEMORY_INDEX_LINE_LIMIT MEMORY_ROTATE_BIN
  mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
  # A real git repo as the cwd, so the index is resolved the way a session resolves it.
  PROJ="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJ"
  git -C "$PROJ" init -q
  local phys slug
  phys="$(cd "$PROJ" && pwd -P)"
  slug="$(printf '%s' "$phys" | tr '/.' '--')"
  IDX="$CLAUDE_CONFIG_DIR/projects/$slug/memory/MEMORY.md"
  mkdir -p "${IDX%/*}"
  printf -- '- [A](a.md) — one\n- [B](b.md) — two\n- [C](c.md) — three\n' > "$IDX"
  # The live layer reaches the hook through a symlink; so does this suite.
  mkdir -p "$BATS_TEST_TMPDIR/live/hooks"
  ln -s "$REPO/hooks/memory-nudge.sh" "$BATS_TEST_TMPDIR/live/hooks/memory-nudge.sh"
  HOOK="$BATS_TEST_TMPDIR/live/hooks/memory-nudge.sh"
}

# prompt <sid> <text> — one prompt through the stubbed PATH; stdout in $OUT, call log in $CALLS,
# the number of external calls in $NCALLS.
prompt() {
  local in="$BATS_TEST_TMPDIR/in.json"
  jq -cn --arg s "$1" --arg c "$PROJ" --arg p "$2" \
    '{session_id:$s,cwd:$c,prompt:$p,hook_event_name:"UserPromptSubmit"}' > "$in"
  : > "$MN_FORK_LOG"
  OUT="$(PATH="$STUB" /bin/bash "$HOOK" < "$in")"
  CALLS="$(tr '\n' ' ' < "$MN_FORK_LOG")"
  NCALLS="$(grep -c . "$MN_FORK_LOG" || true)"
}
calls_of() { grep -cx -- "$1" "$MN_FORK_LOG" || true; }

@test "a warm non-due prompt makes at most 15 external calls, and still logs its two IDL rows" {
  prompt s-warm 'fix the failing test'          # prompt 1: fills the caches
  prompt s-warm 'fix the failing test again'    # prompt 2: the steady state measured here
  echo "# warm non-due prompt: $NCALLS external calls: $CALLS" >&3
  [ -z "$OUT" ]
  [ "$NCALLS" -le 15 ] || { echo "too many: $NCALLS: $CALLS"; false; }
  # Telemetry is unchanged: one ruling row and one episodic row per counted prompt.
  [ "$(jq -s '[.[] | select(.hook == "memory-nudge:ruling")] | length' "$CC_IDL")" -eq 2 ]
  [ "$(jq -s '[.[] | select(.hook == "memory-nudge:episodic")] | length' "$CC_IDL")" -eq 2 ]
  [ "$(jq -s '[.[] | select(.hook == "memory-nudge")] | length' "$CC_IDL")" -eq 0 ]
}

@test "a cold non-due prompt (fresh state, first prompt of a session) also stays within 15" {
  prompt s-cold 'fix the failing test'
  echo "# cold non-due prompt: $NCALLS external calls: $CALLS" >&3
  [ -z "$OUT" ]
  [ "$NCALLS" -le 15 ] || { echo "too many: $NCALLS: $CALLS"; false; }
}

@test "a non-due prompt on a healthy index never measures it: one jq, no wc, no cut" {
  prompt s-meas 'fix the failing test'
  prompt s-meas 'fix the failing test again'
  # The only jq is the one stdin parse; the measure (_mn_stats) is a second jq.
  [ "$(calls_of jq)" -eq 1 ] || { echo "jq ran $(calls_of jq)x: $CALLS"; false; }
  [ "$(calls_of wc)" -eq 0 ] || { echo "wc ran: $CALLS"; false; }
  [ "$(calls_of cut)" -eq 0 ] || { echo "cut ran: $CALLS"; false; }
  [ "$(calls_of find)" -eq 0 ] || { echo "the daily prune re-ran: $CALLS"; false; }
  [ "$(calls_of git)" -eq 0 ] || { echo "the index path was re-resolved: $CALLS"; false; }
}

@test "the due prompt still measures and reports the budget after warm non-due prompts" {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11; do prompt s-due "fix it $i"; done
  [ -z "$OUT" ]
  prompt s-due 'fix it 12'
  run jq -r '.hookSpecificOutput.additionalContext' <<< "$OUT"
  [[ "$output" == "MEMORY INDEX BUDGET (live): "*"across 3 entries"*"MEMORY CHECK (periodic)"* ]] || false
  [[ "$output" == *"the index is $IDX"* ]] || false
}

# Positive control for the cache: in the rotor's pressure band the cost gate cannot skip the
# measurement (MEMORY_ROTATE_AT is below the index), so only the cache keeps jq at one call.
@test "in the rotor's pressure band a warm non-due prompt reads the cached figures, not a second jq" {
  export MEMORY_ROTATE_AT=10 MEMORY_ROTATE_BIN="$BATS_TEST_TMPDIR/no-such-rotor"
  touch -t 202001010000 "$IDX"
  prompt s-band 'fix the failing test'          # measures (nothing cached yet) and caches
  [ "$(calls_of jq)" -eq 2 ] || { echo "the first prompt did not measure: $CALLS"; false; }
  prompt s-band 'fix the failing test again'
  echo "# pressure-band warm non-due prompt: $NCALLS external calls: $CALLS" >&3
  [ -z "$OUT" ]
  [ "$(calls_of jq)" -eq 1 ] || { echo "jq ran $(calls_of jq)x: $CALLS"; false; }
  [ "$NCALLS" -le 15 ] || { echo "too many: $NCALLS: $CALLS"; false; }
}

# The index is backdated so the measurement cache is really written (a cache is only trusted for
# an index last written in an earlier second than the measurement started).
@test "an index edited after its measurement was cached is re-measured, not served stale" {
  local i
  touch -t 202001010000 "$IDX"
  MEMORY_NUDGE_INTERVAL=1 prompt s-edit 'one'      # due: measures the index and caches it
  run jq -r '.hookSpecificOutput.additionalContext' <<< "$OUT"
  [[ "$output" == "MEMORY INDEX BUDGET (live): "*"across 3 entries"* ]] || false
  for i in $(seq 1 210); do printf -- '- [T%s](t%s.md) — n\n' "$i" "$i" >> "$IDX"; done
  # A new session's FIRST prompt: due only because the index is now over its line cap.
  prompt s-fresh 'a new session'
  run jq -r '.hookSpecificOutput.additionalContext' <<< "$OUT"
  [[ "$output" == "🚨 MEMORY INDEX OVER ITS LINE LIMIT"* ]] || false
}

@test "an index created after the cwd's path was cached is found on the next prompt" {
  local i
  rm -f "$IDX"
  prompt s-none 'fix the failing test'              # caches this cwd's candidate paths
  [ -z "$OUT" ]
  for i in $(seq 1 210); do printf -- '- [T%s](t%s.md) — n\n' "$i" "$i" >> "$IDX"; done
  prompt s-new 'a new session'
  run jq -r '.hookSpecificOutput.additionalContext' <<< "$OUT"
  [[ "$output" == "🚨 MEMORY INDEX OVER ITS LINE LIMIT"* ]] || false
  [[ "$output" == *"the index is $IDX"* ]] || false
}
