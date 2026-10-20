#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: each @test runs in its own subshell, so an `export` inside one is meant to be local
# to it; the linter reads that as a lost modification. File-level, because it is a property of bats.
#
# config-mirror-assert.sh — the SessionStart backstop that re-runs the knowledge-layer mirror for a
# non-primary account and reports what safe mode cannot fix.
#
# What is pinned here (docs/research/token-efficiency-2026-09-23/measure/hooks.md §4 "Mirror", §5 rows
# 5 and 11; channel and backup rule changed 2026-10-04): the report is ONE top-level systemMessage
# for the operator, never additionalContext. A FORKED report counts and names only NON-backup forks
# (at most five, then a "+N more" with the list command) plus the converge command; backups (the
# library's own *bak* rule) are neither counted nor named, so a backup-only fork list emits nothing,
# as does a run with nothing to report. The whole list ran to a median 216 names, ~90% backups.
#
# Hermetic: $HOME is a scratch dir, and the mirror library is a stub whose _cc_sync_config_mirror
# prints one FORKED line to stderr per name in $STUB_FORKS, exactly in the real library's format
# (lib/config-mirror.zsh:178). Its _cc_sync_memory_mirror records each call in $HOME/calls; the full
# walk (no --slug) can be HELD until $STUB_HOLD exists, which is how the split tests below see the
# hook return while the detached sweep is still running.
#
# The memory-walk split (docs/research/startup-hooks-2026-10-18 README §5 unit 5.7): the hook links
# only the session's own slug inline and starts the full walk as a detached, single-flight sweep
# AFTER its report. The report pins above it are unchanged by that, which is the point: the split
# moves time, not output.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/config-mirror-assert.sh"
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_STARTUP_HEALTH_DIR="$BATS_TEST_TMPDIR/startup-health"
  mkdir -p "$HOME/.claude/lib" "$HOME/.claude-secondary"
  export CLAUDE_CONFIG_DIR="$HOME/.claude-secondary"
  cat > "$HOME/.claude/lib/config-mirror.zsh" <<'ZSH'
_cc_sync_config_mirror() {
  local n
  for n in ${=STUB_FORKS}; do
    print -u2 "config-mirror: FORKED real '$n' in ${1:t} — shadows ~/.claude/$n; safe mode cannot fix it, run with --convert (all that account's panes closed)"
  done
}
_cc_memory_mirror_wanted() { return 0; }
_cc_sync_memory_mirror() {
  if [[ "$1" == --slug ]]; then print -r -- "slug $2 ${3:t}" >> "$HOME/calls"; return 0; fi
  print -r -- "sweep-start ${1:t}" >> "$HOME/calls"
  local i
  if [[ -n "${STUB_HOLD:-}" ]]; then
    for i in {1..600}; do [[ -e "$STUB_HOLD" ]] && break; sleep 0.1; done
  fi
  print -r -- "sweep-end ${1:t}" >> "$HOME/calls"
}
ZSH
  export STUB_FORKS=""
  CLAIM="$HOME/.claude/state/config-mirror/.claude-secondary.sweep.claim"
  STAMP="$HOME/.claude/state/config-mirror/.claude-secondary.sweep-stamp"
  SWEEP_LOG="$HOME/.claude/logs/config-mirror-sweep.log"
}

# Never leave a detached sweep running past its test: release any hold, then wait for the claim the
# sweep removes when it finishes.
teardown() {
  [ -n "${STUB_HOLD:-}" ] && : > "$STUB_HOLD"
  local i
  for i in $(seq 1 300); do [ -d "${CLAIM:-/nonexistent}" ] || return 0; sleep 0.1; done
}

# The hook reads the SessionStart payload on stdin; $PAYLOAD names a file holding one.
hook() { bash "$HOOK" < "${PAYLOAD:-/dev/null}"; }
payload_for() { printf '{"session_id":"s1","transcript_path":"%s/s1.jsonl"}' "$1" > "$BATS_TEST_TMPDIR/payload"; PAYLOAD="$BATS_TEST_TMPDIR/payload"; }
# Wait up to ~30 s for $2 lines matching $1 in $3 (default $HOME/calls).
wait_n() {
  local i n
  for i in $(seq 1 300); do
    n="$(grep -c -- "$1" "${3:-$HOME/calls}" 2>/dev/null || true)"
    [ "${n:-0}" -ge "$2" ] && return 0
    sleep 0.1
  done
  echo "timed out waiting for $2 × '$1' in ${3:-$HOME/calls}"; cat "${3:-$HOME/calls}" 2>/dev/null; return 1
}
count() { grep -c -- "$1" "${2:-$HOME/calls}" 2>/dev/null || true; }

ctx() { printf '%s' "$1" | jq -r '.systemMessage'; }
# A bare `! cmd` mid-test cannot fail a bats test (errexit ignores it); a function returning the
# negation can.
lacks() { ! printf '%s' "$1" | grep -qF -- "$2"; }

@test "channel: the report is ONE top-level systemMessage, never additionalContext" {
  STUB_FORKS="settings.json"
  run hook
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '(.systemMessage | test("FORKED")) and (has("hookSpecificOutput") | not)' >/dev/null
}

@test "FORKED: 473 entries, 9 of them real ⇒ counts the 9, names 5, +4 more, converge command" {
  local i names="settings.json .mcp-probe-cache .last-update-result.json commands keybindings.json"
  names="$names a1 a2 a3 a4"
  for i in $(seq 1 464); do names="$names settings.json.bak-$i"; done
  STUB_FORKS="$names"
  run hook
  [ "$status" -eq 0 ]
  local c; c="$(ctx "$output")"
  printf '%s' "$c" | grep -qF '9 FORKED real entry(ies) shadow ~/.claude in .claude-secondary: settings.json .mcp-probe-cache .last-update-result.json commands keybindings.json (+4 more: '
  printf '%s' "$c" | grep -qF "_cc_sync_account --convert $HOME/.claude-secondary'"
  printf '%s' "$c" | grep -qF "_cc_sync_account $HOME/.claude-secondary' 2>&1 | grep FORKED | grep -v bak"
  # the 464 backups are neither counted nor named
  lacks "$c" '473'
  lacks "$c" 'settings.json.bak-'
  [ "${#c}" -lt 1000 ]
}

@test "FORKED: backups listed first by the library are still skipped, real forks named in order" {
  # The real library reports in glob order, which is alphabetical, so settings.json.bak-* comes
  # before skills and todos.
  STUB_FORKS="agents settings.json.bak-1 settings.json.bak-2 settings.json.bak-3 settings.json.bak-4 skills todos"
  run hook
  [ "$status" -eq 0 ]
  local c; c="$(ctx "$output")"
  printf '%s' "$c" | grep -qF '3 FORKED real entry(ies) shadow ~/.claude in .claude-secondary: agents skills todos —'
  lacks "$c" 'more'
}

@test "FORKED: only backups forked ⇒ NO output at all" {
  STUB_FORKS="settings.json.bak-1 settings.json.bak-2 settings.json.bak-3 settings.json.bak-4 settings.json.bak-5 settings.json.bak-6"
  run hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # non-vacuity: one real fork among the same backups speaks, and names only itself
  STUB_FORKS="$STUB_FORKS commands"
  run hook
  local c; c="$(ctx "$output")"
  printf '%s' "$c" | grep -qF '1 FORKED real entry(ies) shadow ~/.claude in .claude-secondary: commands —'
}

@test "FORKED: a backup is whatever the library calls one (*bak*), infix spellings included" {
  # Live 2026-10-04: settings.json.pane-autonomy-bak-<stamp> was named as a real fork because the
  # hook matched '.bak' while lib/config-mirror.zsh folds '*bak*'.
  STUB_FORKS="settings.json.pane-autonomy-bak-20261001T155952 settings.json.permharvest-bak-20261001T162531Z .claude.json.bak-ms365-restore commands.premirror-bak"
  run hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent: nothing forked and no registration drift ⇒ no output at all" {
  run hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "drift-only: a vanished 0019 registration is still reported with no fork list" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  jq -n '{hooks:{StopFailure:[{hooks:[{type:"command",command:"~/.claude/hooks/stop-failure-marker.sh"}]}]}}' \
    > "$CLAUDE_CONFIG_DIR/settings.json"
  run hook
  [ "$status" -eq 0 ]
  local c; c="$(ctx "$output")"
  printf '%s' "$c" | grep -qF 'knowledge-layer mirror (.claude-secondary): ⚠ hook-surface registration DRIFT'
  printf '%s' "$c" | grep -qF 'InstructionsLoaded PostToolBatch'
  lacks "$c" 'FORKED'
}

@test "primary account (CLAUDE_CONFIG_DIR unset) ⇒ no-op" {
  unset CLAUDE_CONFIG_DIR
  STUB_FORKS="settings.json"
  run hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Decision D6 (migration 0060): a per-agent budget flag cached ON in this account while
# CLAUDE_CODE_RIPPLING_TULIP=0 is absent is named in the report; with the switch set, or with the flag
# cached OFF, the hook stays silent. Uses the repo's own bin/cc-agent-budget-flags at the deployed path.
@test "D6: a budget flag ON with the switch absent is reported; switch set or flag off is silent" {
  mkdir -p "$HOME/.claude/bin"
  cp "$REPO/bin/cc-agent-budget-flags" "$HOME/.claude/bin/"
  printf '{"cachedGrowthBookFeatures":{"tengu_rippling_tulip":250000}}\n' > "$CLAUDE_CONFIG_DIR/.claude.json"
  printf '{"env":{}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
  run hook
  [ "$status" -eq 0 ]
  m="$(ctx "$output")"
  [[ "$m" == *"per-agent token budget ON"* ]] || { echo "$output"; false; }
  [[ "$m" == *"tengu_rippling_tulip=250000"* ]] || { echo "$m"; false; }
  [[ "$m" == *"0060-agent-budget-off.sh --confirm settings.json"* ]] || { echo "$m"; false; }

  printf '{"env":{"CLAUDE_CODE_RIPPLING_TULIP":"0"}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
  run hook
  [ "$status" -eq 0 ]; [ -z "$output" ] || { echo "$output"; false; }

  printf '{"env":{}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
  printf '{"cachedStatsigGates":{"tengu_streamed_bumblebee":false}}\n' > "$CLAUDE_CONFIG_DIR/.claude.json"
  run hook
  [ "$status" -eq 0 ]; [ -z "$output" ] || { echo "$output"; false; }
}

# ── unit 5.7: the memory walk is split off the foreground ───────────────────────────────────────

@test "split: own slug linked inline, the full walk is detached and the hook returns before it ends" {
  export STUB_HOLD="$BATS_TEST_TMPDIR/release"
  payload_for "$CLAUDE_CONFIG_DIR/projects/-Users-me-own"
  run hook
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }      # healthy start: still silent
  # The own slug was visited synchronously: it is recorded the moment the hook has returned.
  [ "$(count 'slug -Users-me-own .claude-secondary')" -eq 1 ]
  # The full walk started, and is still running after the hook returned.
  wait_n 'sweep-start .claude-secondary' 1
  [ "$(count 'sweep-end')" -eq 0 ]
  [ -d "$CLAIM" ]
  : > "$STUB_HOLD"
  wait_n 'sweep-end .claude-secondary' 1
  wait_n 'verdict=ok rc=0' 1 "$SWEEP_LOG"
  [ ! -d "$CLAIM" ]                                    # the sweep releases its own claim
}

@test "split: a report is written even though the sweep is held, and a payload outside this account links nothing" {
  export STUB_HOLD="$BATS_TEST_TMPDIR/release"
  STUB_FORKS="commands"
  payload_for "$HOME/.claude/projects/-Users-me-own"   # the SHARED store, not this account's
  run hook
  [ "$status" -eq 0 ]
  c="$(ctx "$output")"
  printf '%s' "$c" | grep -qF '1 FORKED real entry(ies) shadow ~/.claude in .claude-secondary: commands —'
  [ "$(count 'slug ')" -eq 0 ]
  wait_n 'sweep-start' 1
}

@test "single-flight: two runs inside the throttle start one sweep; a live claim blocks even past it" {
  export STUB_HOLD="$BATS_TEST_TMPDIR/release"
  run hook; [ "$status" -eq 0 ]
  run hook; [ "$status" -eq 0 ]                        # inside the 600 s stamp
  wait_n 'sweep-start' 1
  touch -t 202001010000 "$STAMP"                       # stamp expired, but the first sweep still holds the claim
  run hook; [ "$status" -eq 0 ]
  : > "$STUB_HOLD"
  wait_n 'sweep-end' 1
  wait_n 'verdict=' 1 "$SWEEP_LOG"
  [ "$(count 'start pid=' "$SWEEP_LOG")" -eq 1 ]
  # Non-vacuity: with the claim released and the stamp expired, the next start does sweep.
  local i; for i in $(seq 1 100); do [ -d "$CLAIM" ] || break; sleep 0.1; done
  touch -t 202001010000 "$STAMP"
  run hook; [ "$status" -eq 0 ]
  wait_n 'verdict=' 2 "$SWEEP_LOG"
  [ "$(count 'start pid=' "$SWEEP_LOG")" -eq 2 ]
}

@test "stale claim: a claim older than the stale bound is broken and a sweep starts" {
  mkdir -p "$CLAIM"
  touch -t 202001010000 "$CLAIM"
  run hook; [ "$status" -eq 0 ]
  wait_n 'verdict=ok' 1 "$SWEEP_LOG"
}

@test "CC_MIRROR_SWEEP=off: no sweep, no claim, no stamp; the own slug is still linked" {
  payload_for "$CLAUDE_CONFIG_DIR/projects/-Users-me-own"
  CC_MIRROR_SWEEP=off run hook
  [ "$status" -eq 0 ]
  [ "$(count 'slug -Users-me-own')" -eq 1 ]
  [ ! -e "$STAMP" ] && [ ! -d "$CLAIM" ] && [ ! -e "$SWEEP_LOG" ]
}

# A3 T19 against the REAL library: many slugs, and the foreground links exactly one of them.
@test "T19 no foreground full walk (real library): 200 slugs, only the own slug linked inline; the sweep links the rest" {
  ln -sf "$REPO/lib/config-mirror.zsh" "$HOME/.claude/lib/config-mirror.zsh"
  local i
  for i in $(seq 1 200); do
    mkdir -p "$HOME/.claude/projects/-Users-me-p$i/memory"
    printf 'x\n' > "$HOME/.claude/projects/-Users-me-p$i/memory/MEMORY.md"
  done
  mkdir -p "$HOME/.claude/projects/-Users-me-own/memory" "$CLAUDE_CONFIG_DIR/projects/-Users-me-own"
  printf 'own\n' > "$HOME/.claude/projects/-Users-me-own/memory/MEMORY.md"
  payload_for "$CLAUDE_CONFIG_DIR/projects/-Users-me-own"
  links() { find "$CLAUDE_CONFIG_DIR/projects" -mindepth 2 -maxdepth 2 -name memory -type l | wc -l | tr -d ' '; }

  CC_MIRROR_SWEEP=off run hook
  [ "$status" -eq 0 ]
  [ "$(readlink "$CLAUDE_CONFIG_DIR/projects/-Users-me-own/memory")" = "$HOME/.claude/projects/-Users-me-own/memory" ]
  [ "$(links)" -eq 1 ] || { echo "links=$(links)"; false; }    # not one of the 200 in the foreground

  run hook
  [ "$status" -eq 0 ]
  wait_n 'verdict=ok rc=0' 1 "$SWEEP_LOG"
  [ "$(links)" -eq 201 ] || { echo "links=$(links)"; cat "$SWEEP_LOG"; false; }
}
