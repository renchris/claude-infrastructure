#!/usr/bin/env bats
# pane-spawn-log.sh — one row per pane-spawn, naming the CALLER (item 1467ea1dad4f).
#
# WHAT THESE PIN, and why each is a defect this repo has already paid for elsewhere:
#   · the row carries pid AND ppid — the item's literal ask, and the join key for a forensic
#   · `chain` is pushed at SOURCE time, not at write time, so handoff-fire appears in the row that
#     bin/it2-kitty writes for the split it delegated. Pushing at write time is the shape that would
#     leave the fleet's most common spawn attributed to the leaf alone
#   · unmeasured fields read ABSENT (null), never a fabricated value (R9 — firing_rss_kb logged a
#     false 0 in 141 of 141 fires by breaking exactly this)
#   · every path returns 0, so a spawn cannot die on its bookkeeping, INCLUDING under `set -e`
#   · a jq-less box still leaves a row, and that row says `degraded:true` — silence there would
#     manufacture the "no row ⇒ not from this tree" false conviction the log exists to prevent
#
# HERMETIC: every case writes to its own $CC_SPAWN_LOG_FILE under BATS_TEST_TMPDIR; $HOME is
# fixtured so the subject's default path can never reach the operator's real log.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO_ROOT/scripts/lib/pane-spawn-log.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_SPAWN_LOG_FILE="$BATS_TEST_TMPDIR/spawns.jsonl"
  unset CC_SPAWN_CHAIN CC_SPAWN_CHAIN_SELF CC_SPAWN_CALLER FIRE_MARKER CC_SPAWN_ITEM || true
}

row() { tail -1 "$CC_SPAWN_LOG_FILE"; }

@test "a row carries the caller's pid and ppid as NUMBERS" {
  run bash -c ". '$LIB'; cc_log_pane_spawn split kitty 7 /tmp 'd'"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.pid|type' < <(row))" = number ]
  [ "$(jq -r '.ppid|type' < <(row))" = number ]
  # …and they are THIS process's, not an invented pair.
  [ "$(jq -r '.pid' < <(row))" -gt 0 ]
}

@test "the row records surface, backend, pane and cwd verbatim" {
  bash -c ". '$LIB'; cc_log_pane_spawn os-window kitty 42 /var/tmp 'the detail'"
  [ "$(jq -r '[.surface,.backend,.pane,.cwd,.detail]|join("|")' < <(row))" = "os-window|kitty|42|/var/tmp|the detail" ]
}

@test "R9: an unknown pane reads ABSENT (null), never an empty string or a fabricated id" {
  bash -c ". '$LIB'; cc_log_pane_spawn window iterm2 '' /tmp 'no id at issue time'"
  [ "$(jq -r '.pane' < <(row))" = null ]
  [ "$(jq -r 'has("pane")' < <(row))" = true ]
}

@test "unset marker and item read null, not the string 'null' and not absent keys" {
  bash -c ". '$LIB'; cc_log_pane_spawn split kitty 1 /tmp d"
  [ "$(jq -r '.marker' < <(row))" = null ]
  [ "$(jq -r '.item' < <(row))" = null ]
  [ "$(jq -r '[has("marker"),has("item")]|join(",")' < <(row))" = "true,true" ]
}

@test "FIRE_MARKER ties a row to the composed prompt that fired it" {
  FIRE_MARKER=HANDOFF-ENGAGE-27022-1-2 bash -c ". '$LIB'; cc_log_pane_spawn split kitty 3 /tmp d"
  [ "$(jq -r '.marker' < <(row))" = "HANDOFF-ENGAGE-27022-1-2" ]
}

@test "CHAIN: sourcing pushes the script's own name even when it never writes a row" {
  run bash -c ". '$LIB'; printf '%s' \"\$CC_SPAWN_CHAIN\""
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "CHAIN RELAY: a nested spawner's row names the script that invoked it" {
  # This is the case the whole design turns on — handoff-fire's DEFAULT surface delegates to
  # bin/it2-kitty, so without the relay the busiest spawn on the box would be attributed to the leaf.
  cat > "$BATS_TEST_TMPDIR/outer.sh" <<EOF
#!/bin/bash
. "$LIB"
exec "$BATS_TEST_TMPDIR/inner.sh"
EOF
  cat > "$BATS_TEST_TMPDIR/inner.sh" <<EOF
#!/bin/bash
. "$LIB"
cc_log_pane_spawn split kitty 9 /tmp nested
EOF
  chmod +x "$BATS_TEST_TMPDIR/outer.sh" "$BATS_TEST_TMPDIR/inner.sh"
  run "$BATS_TEST_TMPDIR/outer.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.chain' < <(row))" = "outer.sh>inner.sh" ]
  [ "$(jq -r '.caller' < <(row))" = "inner.sh" ]
}

@test "CHAIN is idempotent: sourcing the library twice does not double-append" {
  run bash -c ". '$LIB'; . '$LIB'; printf '%s' \"\$CC_SPAWN_CHAIN\""
  [ "$status" -eq 0 ]
  [[ "$output" != *">"* ]]
}

@test "ancestry names the process chain by comm, and reaches beyond the immediate parent" {
  bash -c ". '$LIB'; cc_log_pane_spawn split kitty 1 /tmp d"
  local anc; anc="$(jq -r '.ancestry' < <(row))"
  [ "$anc" != null ]
  # ≥2 nodes: a single node would be indistinguishable from a walk that could not start.
  [[ "$anc" == *">"* ]] || false
  # pid:comm shape, not a bare pid list.
  [[ "$anc" =~ ^[0-9]+:[^\>]+ ]]
}

@test "ancestry does NOT carry argv — an agent brief must never land in this log" {
  # memory pgrep-f-matches-agent-briefs: a table-wide `args=` read is both enormous and the exact
  # instrument that has already lied here. `comm` only.
  run bash -c "export MARKERWORD=SENTINEL_BRIEF_TEXT; . '$LIB'; cc_log_pane_spawn split kitty 1 /tmp d"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.ancestry' < <(row))" != *SENTINEL_BRIEF_TEXT* ]]
}

@test "ALWAYS 0: an unwritable log directory does not fail the spawn, even under set -e" {
  mkdir -p "$BATS_TEST_TMPDIR/ro"; chmod 500 "$BATS_TEST_TMPDIR/ro"
  run bash -c "set -e; export CC_SPAWN_LOG_FILE='$BATS_TEST_TMPDIR/ro/x/s.jsonl'; . '$LIB'; cc_log_pane_spawn split kitty 1 /tmp d; echo REACHED"
  chmod 700 "$BATS_TEST_TMPDIR/ro"
  [ "$status" -eq 0 ]
  [[ "$output" == *REACHED* ]]
}

@test "ALWAYS 0: called with no arguments at all" {
  run bash -c "set -e; . '$LIB'; cc_log_pane_spawn; echo REACHED"
  [ "$status" -eq 0 ]
  [[ "$output" == *REACHED* ]] || false
  [ "$(jq -r '.surface' < <(row))" = unknown ]
}

@test "SEAM: CC_SPAWN_LOG=0 writes nothing at all" {
  bash -c "CC_SPAWN_LOG=0; export CC_SPAWN_LOG; . '$LIB'; cc_log_pane_spawn split kitty 1 /tmp d"
  [ ! -e "$CC_SPAWN_LOG_FILE" ]
}

@test "SEAM: CC_SPAWN_LOG_FILE set to EMPTY turns the writer off at the source" {
  # `${VAR:-}` cannot tell unset from set-empty; a seam that cannot turn a thing off is not a seam.
  run bash -c "export CC_SPAWN_LOG_FILE=''; . '$LIB'; cc_log_pane_spawn split kitty 1 /tmp d; echo REACHED"
  [ "$status" -eq 0 ]
  [[ "$output" == *REACHED* ]]
}

@test "DEGRADED: with jq genuinely ABSENT a row is still written, and it says degraded" {
  # POSITIVE CONTROL for the fallback: silence here would fake "not from this tree".
  mkdir -p "$BATS_TEST_TMPDIR/nojq"
  for c in bash sed cut tr date ps awk basename dirname mkdir printf grep; do
    p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$BATS_TEST_TMPDIR/nojq/$c" || true
  done
  run env PATH="$BATS_TEST_TMPDIR/nojq" CC_SPAWN_LOG_FILE="$CC_SPAWN_LOG_FILE" HOME="$HOME" \
      "$(command -v bash)" -c ". '$LIB'; cc_log_pane_spawn split kitty 5 /tmp 'no jq here'"
  [ "$status" -eq 0 ]
  [ -s "$CC_SPAWN_LOG_FILE" ]
  # Parseable by a consumer that DOES have jq — a degraded row must not corrupt the file.
  [ "$(jq -r '.degraded' < <(row))" = true ]
  [ "$(jq -r '.pane' < <(row))" = 5 ]
}

@test "DEGRADED rows stay parseable when a field contains quotes and backslashes" {
  mkdir -p "$BATS_TEST_TMPDIR/nojq2"
  for c in bash sed cut tr date ps awk basename dirname mkdir printf grep; do
    p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$BATS_TEST_TMPDIR/nojq2/$c" || true
  done
  run env PATH="$BATS_TEST_TMPDIR/nojq2" CC_SPAWN_LOG_FILE="$CC_SPAWN_LOG_FILE" HOME="$HOME" \
      "$(command -v bash)" -c ". '$LIB'; cc_log_pane_spawn split kitty 5 /tmp 'a \"quoted\" \\ thing'"
  [ "$status" -eq 0 ]
  run jq -e . < <(row)
  [ "$status" -eq 0 ]
}

@test "CLI MODE: an executed library logs, and CC_SPAWN_CALLER attributes the row to the caller" {
  # bin/kitty-pane-menu is python3 and reaches the log this way; without the override every row it
  # writes would be attributed to the logger instead of to the spawner.
  run env CC_SPAWN_CALLER=kitty-pane-menu "$LIB" log os-window kitty 3 /tmp 'detach-window'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.caller' < <(row))" = kitty-pane-menu ]
  [ "$(jq -r '.chain' < <(row))" = kitty-pane-menu ]
}

@test "CLI MODE: an unknown verb is LOUD (exit 64), never a silent success" {
  run "$LIB" frobnicate
  [ "$status" -eq 64 ]
  run "$LIB"
  [ "$status" -eq 64 ]
}

@test "sourcing the library does NOT fall into the CLI dispatch" {
  # BASH_SOURCE[0] != $0 is the guard; a broken guard would make every `source` exit 64 and take the
  # sourcing script's whole spawn path with it.
  run bash -c ". '$LIB'; echo SOURCED_FINE"
  [ "$status" -eq 0 ]
  [[ "$output" == *SOURCED_FINE* ]]
}

@test "one call writes exactly ONE line" {
  bash -c ". '$LIB'; cc_log_pane_spawn split kitty 1 /tmp d"
  [ "$(wc -l < "$CC_SPAWN_LOG_FILE" | tr -d ' ')" = 1 ]
}
