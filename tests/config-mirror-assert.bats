#!/usr/bin/env bats
# config-mirror-assert.sh — the SessionStart backstop that re-runs the knowledge-layer mirror for a
# non-primary account and reports what safe mode cannot fix.
#
# What is pinned here (docs/research/token-efficiency-2026-09-23/measure/hooks.md §4 "Mirror", §5 rows
# 5 and 11): a FORKED report is a count, a backup count, at most five names (non-backups first) and the
# list/converge commands — never the whole list, which ran to a median 216 names and was persisted by
# Claude Code as an 18 KB file; and a run with nothing to report emits nothing at all.
#
# Hermetic: $HOME is a scratch dir, and the mirror library is a stub whose _cc_sync_account prints one
# FORKED line to stderr per name in $STUB_FORKS, exactly in the real library's format
# (lib/config-mirror.zsh:178).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/config-mirror-assert.sh"
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/lib" "$HOME/.claude-secondary"
  export CLAUDE_CONFIG_DIR="$HOME/.claude-secondary"
  cat > "$HOME/.claude/lib/config-mirror.zsh" <<'ZSH'
_cc_sync_account() {
  local n
  for n in ${=STUB_FORKS}; do
    print -u2 "config-mirror: FORKED real '$n' in ${1:t} — shadows ~/.claude/$n; safe mode cannot fix it, run with --convert (all that account's panes closed)"
  done
}
ZSH
  export STUB_FORKS=""
}

ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext'; }
# A bare `! cmd` mid-test cannot fail a bats test (errexit ignores it); a function returning the
# negation can.
lacks() { ! printf '%s' "$1" | grep -qF -- "$2"; }

@test "FORKED: 473 entries ⇒ count, backup count, 5 names, +468 more, list and converge commands" {
  local i names="settings.json .mcp-probe-cache .last-update-result.json commands keybindings.json"
  names="$names a1 a2 a3 a4"
  for i in $(seq 1 464); do names="$names settings.json.bak-$i"; done
  STUB_FORKS="$names"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local c; c="$(ctx "$output")"
  printf '%s' "$c" | grep -qF '473 FORKED real entry(ies)'
  printf '%s' "$c" | grep -qF '(464 of them *.bak* backups)'
  printf '%s' "$c" | grep -qF ': settings.json .mcp-probe-cache .last-update-result.json commands keybindings.json (+468 more)'
  printf '%s' "$c" | grep -qF "_cc_sync_account --convert $HOME/.claude-secondary'"
  printf '%s' "$c" | grep -qF "_cc_sync_account $HOME/.claude-secondary' 2>&1 | grep FORKED"
  # the backups themselves are never listed while a non-backup name is available
  lacks "$c" 'settings.json.bak-'
  # the whole message stays well under Claude Code's 10,000-char persistence cap
  [ "${#c}" -lt 1000 ]
}

@test "FORKED: non-backups are named before backups even when the library lists backups first" {
  # The real library reports in glob order, which is alphabetical, so settings.json.bak-* comes
  # before skills and todos; the fixture above lists non-backups first and cannot see the ordering.
  STUB_FORKS="agents settings.json.bak-1 settings.json.bak-2 settings.json.bak-3 settings.json.bak-4 skills todos"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local c; c="$(ctx "$output")"
  printf '%s' "$c" | grep -qF '(4 of them *.bak* backups): agents skills todos settings.json.bak-1 settings.json.bak-2 (+2 more)'
}

@test "FORKED: only backups forked ⇒ backups fill the five names" {
  STUB_FORKS="settings.json.bak-1 settings.json.bak-2 settings.json.bak-3 settings.json.bak-4 settings.json.bak-5 settings.json.bak-6"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local c; c="$(ctx "$output")"
  printf '%s' "$c" | grep -qF '6 FORKED real entry(ies)'
  printf '%s' "$c" | grep -qF '(6 of them *.bak* backups)'
  printf '%s' "$c" | grep -qF 'settings.json.bak-5 (+1 more)'
  lacks "$c" 'settings.json.bak-6'
}

@test "FORKED: three entries ⇒ all three named, no '+N more'" {
  STUB_FORKS="settings.json commands agents"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local c; c="$(ctx "$output")"
  printf '%s' "$c" | grep -qF '3 FORKED real entry(ies) shadow ~/.claude in .claude-secondary (0 of them *.bak* backups): settings.json commands agents —'
  lacks "$c" 'more)'
}

@test "silent: nothing forked and no registration drift ⇒ no output at all" {
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "drift-only: a vanished 0019 registration is still reported with no fork list" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  jq -n '{hooks:{StopFailure:[{hooks:[{type:"command",command:"~/.claude/hooks/stop-failure-marker.sh"}]}]}}' \
    > "$CLAUDE_CONFIG_DIR/settings.json"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local c; c="$(ctx "$output")"
  printf '%s' "$c" | grep -qF 'knowledge-layer mirror (.claude-secondary): ⚠ hook-surface registration DRIFT'
  printf '%s' "$c" | grep -qF 'InstructionsLoaded PostToolBatch'
  lacks "$c" 'FORKED'
}

@test "primary account (CLAUDE_CONFIG_DIR unset) ⇒ no-op" {
  unset CLAUDE_CONFIG_DIR
  STUB_FORKS="settings.json"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
