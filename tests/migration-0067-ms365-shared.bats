#!/usr/bin/env bats
# shellcheck disable=SC2016  # stub bodies carry literal $ on purpose
# Migration 0067 — one shared ms365 server (docs/research/load-root-cause-2026-10-17/DESIGN.md X4).
#
# Pinned: a bare run is a dry run that changes nothing; --confirm must name its target; a live layer
# without the guard or launcher refuses; a FAILING gate stops before launchctl, settings.json and the
# marker, so every session stays on stdio; a passing gate ends with the job loaded, the guard
# registered once, the marker written and the configs re-rendered and checked; a re-run is idempotent.
#
# Hermetic: scratch HOME, LaunchAgents and a FIXTURE repo (CC_MIGRATION_REPO) whose gate and renderer
# are stubs, so nothing here spawns a server, runs npm, or renders a real account config. launchctl
# and cc-settings-parity are stubs that record every call; npm is a stub that fails loudly if reached
# (the fixture already carries mcp-proxy at the pinned version).

setup() {
  REAL="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REAL/migrations/0067-ms365-shared.sh"
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home" CC_MIGRATION_REPO="$T/repo" CC_MIGRATION_LA_DIR="$T/LaunchAgents"
  export CC_0067_LAUNCHCTL="$T/launchctl" CC_SETTINGS_PARITY_BIN="$T/parity" LC_DIR="$T/lc" CALLS="$T/calls"
  mkdir -p "$LC_DIR" "$CC_MIGRATION_LA_DIR" "$HOME/.claude/hooks" "$HOME/.claude/scripts" \
           "$CC_MIGRATION_REPO/launchd/staged" "$CC_MIGRATION_REPO/scripts" "$T/bin"
  cp "$REAL/launchd/staged/com.claude.mcp-ms365.plist" "$CC_MIGRATION_REPO/launchd/staged/"
  cp "$REAL/mcp-servers.json" "$CC_MIGRATION_REPO/"
  PVER="$(jq -r .shared.ms365.proxy_version "$REAL/mcp-servers.json")"
  NM="$HOME/Library/Application Support/fnm/aliases/default/lib/node_modules/mcp-proxy"
  mkdir -p "$NM" "$HOME/Library/Application Support/fnm/aliases/default/bin"
  printf '{"version":"%s"}\n' "$PVER" > "$NM/package.json"
  # the live layer the migration requires before it acts
  printf '#!/bin/sh\nexit 0\n' > "$HOME/.claude/hooks/ms365-shared-guard.sh"
  printf '#!/bin/sh\nexit 0\n' > "$HOME/.claude/scripts/mcp-ms365-proxy.sh"
  chmod +x "$HOME/.claude/hooks/ms365-shared-guard.sh" "$HOME/.claude/scripts/mcp-ms365-proxy.sh"
  printf '{"model":"x","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"a"}]}]}}\n' \
    > "$HOME/.claude/settings.json"
  cp "$HOME/.claude/settings.json" "$T/settings.before"
  # gate stub: GATE_RC decides; renderer stub records each call
  printf '#!/bin/bash\necho "gate $*" >> "%s"\nexit "${GATE_RC:-0}"\n' "$CALLS" > "$CC_MIGRATION_REPO/scripts/mcp-ms365-proxy.sh"
  printf '#!/bin/bash\necho "wire $*" >> "%s"\nexit 0\n' "$CALLS" > "$CC_MIGRATION_REPO/scripts/mcp-ssot-wire.sh"
  printf '#!/bin/bash\necho "parity $*" >> "%s"\nexit 0\n' "$CALLS" > "$CC_SETTINGS_PARITY_BIN"
  printf '#!/bin/bash\necho "npm $*" >> "%s"\nexit 1\n' "$CALLS" > "$T/bin/npm"
  cat > "$CC_0067_LAUNCHCTL" <<'STUB'
#!/bin/bash
verb="$1"; shift
echo "launchctl $verb $*" >> "$CALLS"
case "$verb" in
  print) [ -f "$LC_DIR/loaded" ] || exit 113; echo "	state = running"; exit 0 ;;
  bootout) rm -f "$LC_DIR/loaded"; exit 0 ;;
  bootstrap) cp "$2" "$LC_DIR/loaded"; exit 0 ;;
esac
exit 0
STUB
  chmod +x "$CC_MIGRATION_REPO/scripts/"*.sh "$CC_SETTINGS_PARITY_BIN" "$T/bin/npm" "$CC_0067_LAUNCHCTL"
  export PATH="$T/bin:$PATH"
  MARKER="$HOME/.claude/state/ms365-shared.active"
  KEY="$HOME/.claude/state/ms365-proxy.key"
}

guard_entries() {
  jq '[.hooks.PreToolUse[] | select(.matcher == "mcp__ms365__.*") | .hooks[].command
       | select(. == "~/.claude/hooks/ms365-shared-guard.sh")] | length' "$HOME/.claude/settings.json"
}

@test "a bare run is a dry run: it names the plan and writes nothing" {
  run /bin/bash "$MIG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry run — nothing changed"* ]] || false
  [ ! -e "$MARKER" ] && [ ! -e "$KEY" ] && [ ! -e "$CALLS" ] || false
  cmp -s "$HOME/.claude/settings.json" "$T/settings.before"
}

@test "--confirm must name its target; a wrong one refuses and writes nothing" {
  run /bin/bash "$MIG" --confirm launchd
  [ "$status" -eq 2 ]
  [[ "$output" == *"--confirm must name its target"* ]] || false
  [ ! -e "$MARKER" ] && [ ! -e "$KEY" ] && [ ! -e "$CALLS" ]
}

@test "a live layer without the guard refuses (exit 4) before touching anything" {
  rm "$HOME/.claude/hooks/ms365-shared-guard.sh"
  run /bin/bash "$MIG" --confirm ms365-shared
  [ "$status" -eq 4 ]
  [[ "$output" == *"converge first"* ]] || false
  [ ! -e "$MARKER" ] && [ ! -e "$CALLS" ]
}

@test "a FAILING gate stops before launchctl, settings.json and the marker" {
  GATE_RC=1 run /bin/bash "$MIG" --confirm ms365-shared
  [ "$status" -eq 1 ]
  [[ "$output" == *"gate FAILED — nothing session-facing changed"* ]] || false
  grep -q '^gate gate$' "$CALLS"
  ! grep -q '^launchctl' "$CALLS" || false
  ! grep -q '^wire' "$CALLS" || false
  ! grep -q '^npm' "$CALLS" || false
  [ ! -e "$MARKER" ]
  cmp -s "$HOME/.claude/settings.json" "$T/settings.before"
}

@test "a passing gate loads the job, registers the guard once, writes the marker, re-renders and checks" {
  run /bin/bash "$MIG" --confirm ms365-shared
  [ "$status" -eq 0 ]
  [[ "$output" == *"done — NEW sessions connect to the shared server"* ]] || false
  grep -q '^launchctl bootstrap gui/' "$CALLS"
  cmp -s "$CC_MIGRATION_LA_DIR/com.claude.mcp-ms365.plist" "$CC_MIGRATION_REPO/launchd/staged/com.claude.mcp-ms365.plist"
  [ "$(guard_entries)" = 1 ]
  # everything else in settings.json is unchanged, the earlier hook included
  [ "$(jq -S 'del(.hooks.PreToolUse)' "$HOME/.claude/settings.json")" = "$(jq -S 'del(.hooks.PreToolUse)' "$T/settings.before")" ]
  [ "$(jq -c '.hooks.PreToolUse[0]' "$HOME/.claude/settings.json")" = "$(jq -c '.hooks.PreToolUse[0]' "$T/settings.before")" ]
  [ -e "$MARKER" ]
  [ "$(stat -f %Lp "$KEY")" = 600 ] && [ -s "$KEY" ] || false
  # the marker comes after the gate and the load, and the re-render is followed by --check
  [ "$(grep -n '^gate' "$CALLS" | cut -d: -f1)" -lt "$(grep -n '^launchctl bootstrap' "$CALLS" | cut -d: -f1)" ]
  grep -qx 'wire ' "$CALLS" && grep -qx 'wire --check' "$CALLS" || false
  ! grep -q '^npm' "$CALLS" || false
}

@test "a re-run is idempotent: one guard entry, the same key, no second bootstrap" {
  run /bin/bash "$MIG" --confirm ms365-shared
  [ "$status" -eq 0 ]
  k1="$(cat "$KEY")"; : > "$CALLS"
  run /bin/bash "$MIG" --confirm ms365-shared
  [ "$status" -eq 0 ]
  [ "$(guard_entries)" = 1 ]
  [ "$(cat "$KEY")" = "$k1" ]
  ! grep -q '^launchctl bootstrap' "$CALLS" || false
}
