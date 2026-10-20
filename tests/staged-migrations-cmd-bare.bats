#!/usr/bin/env bats
# The twelve still-staged settings migrations survive migration 0070's explicit-interpreter rewrite.
# 0070 turns `~/.claude/hooks/x.sh` into `/bin/bash ~/.claude/hooks/x.sh` (the script's own shebang,
# verbatim) in live settings.json; a migration that matched its hook by exact string would then
# re-add a duplicate, refuse, or report not-live forever. Each case: drive the migration to applied in
# a sandbox HOME, apply the real 0070 rewrite (scripts/hook-interp.py, hermetic against this repo's
# hooks), then require (a) its own verify still clears and (b) a re-run leaves settings.json
# byte-identical. docs/research/panic-2026-10-18-zone-map-shebang-leak.md.
#
# RED-proof: against the pre-fix copies (git show 171263d18:migrations/<m>) all 12 per-migration
# cases fail (1..13, 12 not ok), each at its own verify reading not-live after the rewrite.
#
# Hermetic: $HOME is a fixture; 0047/0068/0069 run the real bin/cc-settings-parity over fixture
# account dirs through CC_PARITY_DIRS (as tests/migration-0068-0069-timeouts.bats does); 0067 uses
# the stubs of tests/migration-0067-ms365-shared.bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CC_CLAUDE_DIR CC_SETTINGS_PARITY_BIN CC_PARITY_CANONICAL CC_PARITY_ACCOUNTS_JSON CC_MIGRATION_STATE
  mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/bin" "$HOME/.claude/scripts/limit-recover"
  S="$HOME/.claude/settings.json"
}

mig() { echo "$REPO/migrations/$1"; }
stub_hook() { local h; for h; do printf '#!/bin/bash\nexit 0\n' > "$HOME/.claude/hooks/$h"; chmod +x "$HOME/.claude/hooks/$h"; done; }
real_hook() { cp "$REPO/hooks/$1" "$HOME/.claude/hooks/$1"; chmod +x "$HOME/.claude/hooks/$1"; }

# The four account dirs symlink the primary settings.json; the real parity checker reads them.
linked_fleet() {
  CC_PARITY_DIRS=""
  ln -s "$REPO/bin/cc-settings-parity" "$HOME/.claude/bin/cc-settings-parity"
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"
    ln -s "$S" "$HOME/.claude-$a/settings.json"
    CC_PARITY_DIRS="${CC_PARITY_DIRS:+$CC_PARITY_DIRS:}$HOME/.claude-$a"
  done
  export CC_PARITY_DIRS
}

# Migration 0070's rewrite over every real settings.json in the fixture; then prove it bit: the
# subject hook carries an interpreter and no bare spelling of it is left.
rewrite_0070() {
  local f
  for f in "$HOME"/.claude*/settings.json; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    python3 "$REPO/scripts/hook-interp.py" rewrite "$f" --root "$REPO" --hermetic > "$f.raw" 2>/dev/null
    jq . "$f.raw" > "$f.tmp" && mv "$f.tmp" "$f" && rm -f "$f.raw"
  done
  grep -qE "\"(/bin/bash|/usr/bin/env bash) ~/\.claude/hooks/$1" "$S" || { echo "0070 rewrite did not prefix $1"; cat "$S"; false; }
  [ "$(grep -c "\"~/\.claude/hooks/$1" "$S")" -eq 0 ] || { echo "a bare $1 survived the rewrite"; false; }
}

verify_header() {
  local v
  v="$(sed -n 's/^# *migration-verify: *//p' "$(mig "$1")" | head -1)"
  [ -n "$v" ]
  run bash -c "$v"
  [ "$status" -eq 0 ] || { echo "$1's declared verify reads not-live after 0070"; false; }
}

rerun_is_noop() {
  local before
  before="$(cat "$S")"
  run "$@"
  [ "$status" -eq 0 ] || { echo "re-run after 0070 failed: $output"; false; }
  [ "$(cat "$S")" = "$before" ] || { echo "re-run after 0070 changed settings.json:"; cat "$S"; false; }
}

@test "0012: mailbox-wake-arm on Stop survives the 0070 rewrite" {
  real_hook mailbox-wake-arm.sh
  jq -n '{hooks:{SessionStart:[{hooks:[{type:"command",command:"~/.claude/hooks/mailbox-drain.sh session-start",timeout:10}]}],
                 Stop:[{hooks:[{type:"command",command:"~/.claude/hooks/session-continue.sh",timeout:10}]}]}}' > "$S"
  # 3319250f6 moved 0012 to the 0068 contract: --confirm settings.json, refused on a forked fleet.
  linked_fleet
  run /bin/bash "$(mig 0012-mailbox-wake-arm-stop-rearm.sh)" --confirm settings.json; [ "$status" -eq 0 ]
  rewrite_0070 mailbox-wake-arm.sh
  verify_header 0012-mailbox-wake-arm-stop-rearm.sh
  run /bin/bash "$(mig 0012-mailbox-wake-arm-stop-rearm.sh)" --verify
  [ "$status" -eq 0 ] || { echo "0012 --verify reads not-live after 0070: $output"; false; }
  rerun_is_noop /bin/bash "$(mig 0012-mailbox-wake-arm-stop-rearm.sh)" --confirm settings.json
}

@test "0014: subagent-stop on SubagentStop survives the 0070 rewrite" {
  stub_hook subagent-stop.sh
  jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"~/.claude/hooks/session-continue.sh",timeout:10}]}]}}' > "$S"
  run /bin/bash "$(mig 0014-subagent-stop-registration.sh)"; [ "$status" -eq 0 ]
  rewrite_0070 subagent-stop.sh
  verify_header 0014-subagent-stop-registration.sh
  rerun_is_noop /bin/bash "$(mig 0014-subagent-stop-registration.sh)"
}

@test "0018: the memory-index-drain timeout raise survives the 0070 rewrite" {
  real_hook memory-index-drain.sh
  jq -n '{hooks:{PostToolUse:[{matcher:"Bash|Write|Edit|MultiEdit",hooks:[{type:"command",command:"~/.claude/hooks/memory-index-drain.sh",timeout:10}]}]}}' > "$S"
  run /bin/bash "$(mig 0018-memory-index-drain-rotor-budget.sh)"; [ "$status" -eq 0 ]
  rewrite_0070 memory-index-drain.sh
  verify_header 0018-memory-index-drain-rotor-budget.sh
  rerun_is_noop /bin/bash "$(mig 0018-memory-index-drain-rotor-budget.sh)"
}

@test "0023: TaskCreated + StopFailure registrations survive the 0070 rewrite" {
  stub_hook task-created-attrib.sh session-beat.sh
  jq -n '{env:{MCP_TIMEOUT:"30000"},
          hooks:{Stop:[{hooks:[{type:"command",command:"~/.claude/hooks/session-beat.sh stop",timeout:5}]}],
                 PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"~/.claude/hooks/validate-bash.sh"}]}],
                 StopFailure:[{hooks:[{type:"command",command:"~/.claude/hooks/stop-failure-marker.sh"}]}]}}' > "$S"
  run /bin/bash "$(mig 0023-todo-tools-and-task-hooks.sh)"; [ "$status" -eq 0 ]
  rewrite_0070 task-created-attrib.sh
  run env CC_CLAUDE_DIR="$HOME/.claude" /bin/bash "$(mig 0023-todo-tools-and-task-hooks.sh)" --verify
  [ "$status" -eq 0 ] || { echo "0023 --verify reads not-live after 0070: $output"; false; }
  rerun_is_noop /bin/bash "$(mig 0023-todo-tools-and-task-hooks.sh)"
}

@test "0024: unit-gate stays FIRST and single through the 0070 rewrite" {
  stub_hook unit-gate.sh
  printf '#!/bin/bash\nexit 0\n' > "$HOME/.claude/bin/cc-halt"; chmod +x "$HOME/.claude/bin/cc-halt"
  jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"~/.claude/hooks/validate-bash.sh"}]}],
                 Stop:[{hooks:[{type:"command",command:"~/.claude/hooks/session-continue.sh",timeout:10}]}]}}' > "$S"
  run /bin/bash "$(mig 0024-unit-gate-registration.sh)"; [ "$status" -eq 0 ]
  rewrite_0070 unit-gate.sh
  run env CC_CLAUDE_DIR="$HOME/.claude" /bin/bash "$(mig 0024-unit-gate-registration.sh)" --verify
  [ "$status" -eq 0 ] || { echo "0024 --verify reads not-live after 0070: $output"; false; }
  run env CC_CLAUDE_DIR="$HOME/.claude" /bin/bash "$(mig 0024-unit-gate-registration.sh)" --conflict
  [ "$status" -ne 0 ] || { echo "0024 --conflict reads its own prefixed entry as a foreign squatter"; false; }
  rerun_is_noop /bin/bash "$(mig 0024-unit-gate-registration.sh)"
}

@test "0026: recover-inject on UserPromptSubmit survives the 0070 rewrite" {
  stub_hook recover-inject.sh
  printf 'lr_last_api_error() { :; }\n' > "$HOME/.claude/scripts/limit-recover/lr-lib.sh"
  jq -n '{hooks:{UserPromptSubmit:[{hooks:[{type:"command",command:"~/.claude/hooks/dod-persist.sh",timeout:5}]}]}}' > "$S"
  run /bin/bash "$(mig 0026-recover-inject-registration.sh)"; [ "$status" -eq 0 ]
  rewrite_0070 recover-inject.sh
  verify_header 0026-recover-inject-registration.sh
  rerun_is_noop /bin/bash "$(mig 0026-recover-inject-registration.sh)"
}

@test "0029: frontier-spawn-gate on PreToolUse/Bash survives the 0070 rewrite" {
  real_hook frontier-spawn-gate.sh
  jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"~/.claude/hooks/validate-bash.sh"}]},
                             {matcher:"Agent",hooks:[{type:"command",command:"~/.claude/hooks/frontier-spawn-gate.sh",timeout:5}]}]}}' > "$S"
  run /bin/bash "$(mig 0029-frontier-gate-session-path.sh)"; [ "$status" -eq 0 ]
  rewrite_0070 frontier-spawn-gate.sh
  verify_header 0029-frontier-gate-session-path.sh
  rerun_is_noop /bin/bash "$(mig 0029-frontier-gate-session-path.sh)"
}

@test "0030: net-recover-arm on SessionStart + Stop survives the 0070 rewrite" {
  stub_hook net-recover-arm.sh
  printf 'lr_last_api_error() { :; }\n' > "$HOME/.claude/scripts/limit-recover/lr-lib.sh"
  printf '#!/bin/bash\nexit 0\n' > "$HOME/.claude/scripts/limit-recover/lr-probe.sh"
  chmod +x "$HOME/.claude/scripts/limit-recover/lr-probe.sh"
  jq -n '{hooks:{SessionStart:[{hooks:[{type:"command",command:"~/.claude/hooks/dod-persist.sh",timeout:5}]}],
                 Stop:[{hooks:[{type:"command",command:"~/.claude/hooks/session-continue.sh",timeout:10}]}]}}' > "$S"
  run /bin/bash "$(mig 0030-net-recover-arm-registration.sh)"; [ "$status" -eq 0 ]
  rewrite_0070 net-recover-arm.sh
  verify_header 0030-net-recover-arm-registration.sh
  rerun_is_noop /bin/bash "$(mig 0030-net-recover-arm-registration.sh)"
}

@test "0047: read-before-write-parity on PreToolUse survives the 0070 rewrite" {
  stub_hook read-before-write-parity.sh
  jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"~/.claude/hooks/validate-bash.sh"}]}]}}' > "$S"
  linked_fleet
  run /bin/bash "$(mig 0047-read-before-write-parity-registration.sh)" --confirm settings.json; [ "$status" -eq 0 ]
  rewrite_0070 read-before-write-parity.sh
  verify_header 0047-read-before-write-parity-registration.sh
  run /bin/bash "$(mig 0047-read-before-write-parity-registration.sh)" --verify
  [ "$status" -eq 0 ] || { echo "0047 --verify reads not-live after 0070: $output"; false; }
  rerun_is_noop /bin/bash "$(mig 0047-read-before-write-parity-registration.sh)" --confirm settings.json
}

@test "0067: the ms365 shared guard registration survives the 0070 rewrite" {
  T="$BATS_TEST_TMPDIR"
  export CC_MIGRATION_REPO="$T/repo" CC_MIGRATION_LA_DIR="$T/LaunchAgents"
  export CC_0067_LAUNCHCTL="$T/launchctl" CC_SETTINGS_PARITY_BIN="$T/parity" LC_DIR="$T/lc" CALLS="$T/calls"
  mkdir -p "$LC_DIR" "$CC_MIGRATION_LA_DIR" "$CC_MIGRATION_REPO/launchd/staged" "$CC_MIGRATION_REPO/scripts" "$T/bin"
  cp "$REPO/launchd/staged/com.claude.mcp-ms365.plist" "$CC_MIGRATION_REPO/launchd/staged/"
  cp "$REPO/mcp-servers.json" "$CC_MIGRATION_REPO/"
  NM="$HOME/Library/Application Support/fnm/aliases/default/lib/node_modules/mcp-proxy"
  mkdir -p "$NM" "$HOME/Library/Application Support/fnm/aliases/default/bin"
  printf '{"version":"%s"}\n' "$(jq -r .shared.ms365.proxy_version "$REPO/mcp-servers.json")" > "$NM/package.json"
  stub_hook ms365-shared-guard.sh
  printf '#!/bin/sh\nexit 0\n' > "$HOME/.claude/scripts/mcp-ms365-proxy.sh"; chmod +x "$HOME/.claude/scripts/mcp-ms365-proxy.sh"
  jq -n '{model:"x",hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"~/.claude/hooks/validate-bash.sh"}]}]}}' > "$S"
  printf '#!/bin/bash\nexit 0\n' > "$CC_MIGRATION_REPO/scripts/mcp-ms365-proxy.sh"
  printf '#!/bin/bash\nexit 0\n' > "$CC_MIGRATION_REPO/scripts/mcp-ssot-wire.sh"
  printf '#!/bin/bash\nexit 0\n' > "$CC_SETTINGS_PARITY_BIN"
  printf '#!/bin/bash\nexit 1\n' > "$T/bin/npm"
  # shellcheck disable=SC2016  # the stub's own script text, expanded when the stub runs
  printf '%s\n' '#!/bin/bash' 'verb="$1"; shift' 'case "$verb" in' \
    '  print) [ -f "$LC_DIR/loaded" ] || exit 113; echo "state = running"; exit 0 ;;' \
    '  bootout) rm -f "$LC_DIR/loaded"; exit 0 ;;' \
    '  bootstrap) cp "$2" "$LC_DIR/loaded"; exit 0 ;;' 'esac' 'exit 0' > "$CC_0067_LAUNCHCTL"
  chmod +x "$CC_MIGRATION_REPO/scripts/"*.sh "$CC_SETTINGS_PARITY_BIN" "$T/bin/npm" "$CC_0067_LAUNCHCTL"
  export PATH="$T/bin:$PATH"
  run /bin/bash "$(mig 0067-ms365-shared.sh)" --confirm ms365-shared; [ "$status" -eq 0 ]
  rewrite_0070 ms365-shared-guard.sh
  run /bin/bash "$(mig 0067-ms365-shared.sh)" --verify
  [ "$status" -eq 0 ] || { echo "0067 --verify reads not-live after 0070: $output"; false; }
  rerun_is_noop /bin/bash "$(mig 0067-ms365-shared.sh)" --confirm ms365-shared
}

@test "0068: the SessionStart dispatcher timeout raise survives the 0070 rewrite" {
  jq -n '{env:{A:"1"}, hooks:{SessionStart:[{hooks:[{type:"command",command:"~/.claude/hooks/dod-persist.sh",timeout:5},
                                                    {type:"command",command:"~/.claude/hooks/session-start-dispatch.sh",timeout:12}]}]}}' > "$S"
  linked_fleet
  run /bin/bash "$(mig 0068-ssd-timeout-20.sh)" --confirm settings.json; [ "$status" -eq 0 ]
  rewrite_0070 session-start-dispatch.sh
  run /bin/bash "$(mig 0068-ssd-timeout-20.sh)" --verify
  [ "$status" -eq 0 ] || { echo "0068 --verify reads not-live after 0070: $output"; false; }
  rerun_is_noop /bin/bash "$(mig 0068-ssd-timeout-20.sh)" --confirm settings.json
}

@test "0069: the TeammateIdle timeout raise survives the 0070 rewrite" {
  jq -n '{env:{A:"1"}, hooks:{TeammateIdle:[{hooks:[{type:"command",command:"~/.claude/hooks/teammate-auto-shutdown.sh",timeout:5}]}]}}' > "$S"
  linked_fleet
  run /bin/bash "$(mig 0069-teammate-idle-timeout-20.sh)" --confirm settings.json; [ "$status" -eq 0 ]
  rewrite_0070 teammate-auto-shutdown.sh
  run /bin/bash "$(mig 0069-teammate-idle-timeout-20.sh)" --verify
  [ "$status" -eq 0 ] || { echo "0069 --verify reads not-live after 0070: $output"; false; }
  rerun_is_noop /bin/bash "$(mig 0069-teammate-idle-timeout-20.sh)" --confirm settings.json
}

@test "every inlined def cmd_bare is byte-identical to scripts/lib/hook-cmd-bare.jq" {
  canon="$(grep '^def cmd_bare:' "$REPO/scripts/lib/hook-cmd-bare.jq")"
  [ -n "$canon" ]
  copies="$(grep -rhoE 'def cmd_bare:[^;]*;[^;]*;' "$REPO/migrations" "$REPO/scripts" "$REPO/install.sh")"
  [ "$(printf '%s\n' "$copies" | sort -u)" = "$canon" ] || { printf 'divergent copies:\n%s\n' "$copies" | sort -u; false; }
  [ "$(grep -rlE 'def cmd_bare:' "$REPO/migrations" | wc -l)" -ge 12 ]
}
