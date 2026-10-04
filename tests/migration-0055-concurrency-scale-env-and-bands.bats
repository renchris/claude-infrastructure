#!/usr/bin/env bats
# shellcheck disable=SC2016  # jq programs and stub bodies carry literal $ on purpose
# Migration 0055 — the operator-only half of the 2026-10-04 concurrency fixes: two env keys and one
# hook timeout in the ONE shared settings.json, and a reload of four launchd jobs into the bands
# their repo plists declare.
#
# Pinned: a bare run and --dry-run write nothing and reload nothing; --confirm changes exactly the
# two env keys and the one timeout, keeps every account a symlink, reloads only jobs that are loaded
# in an old band, and reads everything back through --verify; a second run is a no-op; an operator's
# own env value and a forked account are refused with nothing written; a job whose tick is running
# is never booted out, and is reloaded by the gap waiter in the gap after its tick (inline in most
# cases here via CC_0055_DETACH=inline; one case runs the real detached waiter with a short bound).
#
# Hermetic: scratch HOME, the repo's own bin/cc-settings-parity, and a launchctl STUB that holds a
# loaded-job table in a scratch dir. The stub derives a job's band from the plist it is handed at
# bootstrap, the way launchd does, so "reloaded into the new band" is read off the real repo plist.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REPO/migrations/0055-concurrency-scale-env-and-bands.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_SETTINGS_PARITY_BIN="$REPO/bin/cc-settings-parity"
  export CC_MIGRATION_REPO="$REPO" CC_MIGRATION_LA_DIR="$BATS_TEST_TMPDIR/LaunchAgents"
  export CC_0055_LAUNCHCTL="$BATS_TEST_TMPDIR/launchctl" CC_0055_WAIT_S=2 CC_0055_POLL_S=1
  export CC_0055_STATE_DIR="$BATS_TEST_TMPDIR/state" CC_0055_DETACH=inline CC_0055_IDLE_WAIT_S=2
  export LC_DIR="$BATS_TEST_TMPDIR/lc"; mkdir -p "$LC_DIR" "$CC_MIGRATION_LA_DIR" "$HOME/.claude"
  printf '{"accounts":[{"name":"next","config_dir":"~/.claude-next"},{"name":"next2","config_dir":"~/.claude-secondary"}]}\n' \
    > "$HOME/.claude/accounts.json"
  jq -n '{
    env: {MCP_TIMEOUT: "30000"},
    hooks: {SessionStart: [
      {hooks: [{type: "command", command: "~/.claude/hooks/mailbox-drain.sh session-start", timeout: 5},
               {type: "command", command: "~/.claude/hooks/net-context-stamp.sh"}]},
      {hooks: [{type: "command", command: "~/.claude/hooks/session-start.sh", timeout: 10}]}]},
    permissions: {allow: ["Bash(git add:*)"], defaultMode: "auto"}
  }' > "$HOME/.claude/settings.json"
  for a in next secondary; do
    mkdir -p "$HOME/.claude-$a"; ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
  done
  F="$HOME/.claude/settings.json"
  JOBS="com.claude.capacity-alarm com.claude.qos-census com.claude.deploy-live com.claude.worktree-gc-infra"
  # every job loaded in its OLD band, with the repo plist already copied into place (install.sh's part)
  for j in $JOBS; do cp "$REPO/launchd/$j.plist" "$CC_MIGRATION_LA_DIR/$j.plist"; done
  printf 'adaptive (6)\n'   > "$LC_DIR/com.claude.capacity-alarm.loaded"
  printf 'background (5)\n' > "$LC_DIR/com.claude.qos-census.loaded"
  printf 'background (5)\n' > "$LC_DIR/com.claude.deploy-live.loaded"
  printf 'background (5)\n' > "$LC_DIR/com.claude.worktree-gc-infra.loaded"
  cat > "$CC_0055_LAUNCHCTL" <<'STUB'
#!/bin/bash
# launchctl stub: print | bootout | bootstrap over $LC_DIR/<label>.loaded (band) / .args / .running
verb="$1"; shift
case "$verb" in
  print) l="${1##*/}"; [ -f "$LC_DIR/$l.loaded" ] || exit 113
         # .running empty ⇒ running forever; holding N ⇒ running for N more prints, then the tick exits
         r="$LC_DIR/$l.running"
         if [ -s "$r" ]; then n="$(cat "$r")"; if [ "$n" -le 0 ]; then rm -f "$r"; else echo $((n - 1)) > "$r"; fi; fi
         if [ -f "$r" ]; then echo "	state = running"; else echo "	state = not running"; fi
         echo "	spawn type = $(cat "$LC_DIR/$l.loaded")"
         [ -f "$LC_DIR/$l.args" ] && cat "$LC_DIR/$l.args"; exit 0 ;;
  bootout) l="${1##*/}"; echo "bootout $l" >> "$LC_DIR/calls"
         [ -f "$LC_DIR/$l.running" ] && echo "KILLED-A-RUNNING-TICK $l" >> "$LC_DIR/calls"; rm -f "$LC_DIR/$l.loaded" "$LC_DIR/$l.args"; exit 0 ;;
  bootstrap) p="$2"; l="$(basename "$p" .plist)"; echo "bootstrap $l" >> "$LC_DIR/calls"
         if grep -q '<string>Background</string>' "$p"; then b='background (5)'
         elif grep -q '<string>Adaptive</string>' "$p"; then b='adaptive (6)'; else b='daemon (3)'; fi
         echo "$b" > "$LC_DIR/$l.loaded"; grep 'exec ' "$p" | grep '<string>' > "$LC_DIR/$l.args" || true; exit 0 ;;
esac
exit 64
STUB
  chmod +x "$CC_0055_LAUNCHCTL"
}

mig() { bash "$MIG" "$@"; }
calls() { if [ -f "$LC_DIR/calls" ]; then wc -l < "$LC_DIR/calls" | tr -d ' '; else echo 0; fi; }
all_linked() { for a in next secondary; do [ -L "$HOME/.claude-$a/settings.json" ] || return 1; done; }

@test "0055: a bare run and --dry-run write nothing and reload nothing; --verify reads NOT live" {
  local before; before="$(shasum "$F")"
  for m in "" --dry-run; do
    # shellcheck disable=SC2086  # the empty mode must vanish, not become an empty argument
    run mig $m
    [ "$status" -eq 0 ] || { echo "mode '$m': $output"; false; }
  done
  [ "$(shasum "$F")" = "$before" ]
  [ "$(calls)" -eq 0 ]
  run mig --verify
  [ "$status" -eq 1 ]
}

@test "0055: --confirm sets exactly two env keys and one timeout, reloads the four jobs, and reads back live" {
  cp "$F" "$BATS_TEST_TMPDIR/before.json"
  run mig --confirm settings.json+launchd
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.env' "$F")" = '{"MCP_TIMEOUT":"30000","CLAUDE_CODE_CERT_STORE":"bundled","AGENT_BROWSER_IDLE_TIMEOUT_MS":"1800000"}' ]
  [ "$(jq -c '.hooks.SessionStart[0].hooks[1]' "$F")" = '{"type":"command","command":"~/.claude/hooks/net-context-stamp.sh","timeout":5}' ]
  # nothing else moved: the other hooks, their timeouts and the permissions are byte-for-byte the same
  [ "$(jq -c 'del(.env, .hooks.SessionStart[0].hooks[1])' "$F")" = "$(jq -c 'del(.env, .hooks.SessionStart[0].hooks[1])' "$BATS_TEST_TMPDIR/before.json")" ]
  all_linked
  [ "$(grep -c '^bootout ' "$LC_DIR/calls")" -eq 4 ]
  [ "$(grep -c '^bootstrap ' "$LC_DIR/calls")" -eq 4 ]
  [ "$(cat "$LC_DIR/com.claude.capacity-alarm.loaded")" = "daemon (3)" ]
  grep -q 'taskpolicy -c utility' "$LC_DIR/com.claude.deploy-live.args"
  run mig --verify
  [ "$status" -eq 0 ]
}

@test "0055: a second --confirm is a no-op" {
  mig --confirm settings.json+launchd >/dev/null
  local sum n; sum="$(shasum "$F")"; n="$(calls)"
  run mig --confirm settings.json+launchd
  [ "$status" -eq 0 ]
  [ "$(shasum "$F")" = "$sum" ]
  [ "$(calls)" -eq "$n" ]
}

@test "0055: an env value the operator already set differently is refused with nothing written or reloaded" {
  jq '.env.CLAUDE_CODE_CERT_STORE = "system"' "$F" > "$F.n" && mv "$F.n" "$F"
  local before; before="$(shasum "$F")"
  run mig --confirm settings.json+launchd
  [ "$status" -eq 1 ]
  [[ "$output" == *"an operator value, left unchanged"* ]] || false
  [ "$(shasum "$F")" = "$before" ]
  [ "$(calls)" -eq 0 ]
}

@test "0055: a forked account is refused rc 3 with nothing written or reloaded" {
  rm "$HOME/.claude-next/settings.json"; cp "$F" "$HOME/.claude-next/settings.json"
  local before; before="$(shasum "$F")"
  run mig --confirm settings.json+launchd
  [ "$status" -eq 3 ]
  [ "$(shasum "$F")" = "$before" ]
  [ "$(calls)" -eq 0 ]
}

@test "0055: a tick that never stops is never booted out; the waiter gives up and a re-run finishes it" {
  : > "$LC_DIR/com.claude.deploy-live.running"
  run mig --confirm settings.json+launchd
  [ "$status" -eq 1 ]
  [[ "$output" == *"com.claude.deploy-live: gap waiter FAILED"* ]] || false
  grep -q 'com.claude.deploy-live: verdict=GAVE-UP' "$CC_0055_STATE_DIR/0055-reband.log"
  run grep -c 'com.claude.deploy-live' "$LC_DIR/calls"
  [ "$output" -eq 0 ]
  [ "$(grep -c '^bootstrap ' "$LC_DIR/calls")" -eq 3 ]   # the other three were not held up
  rm "$LC_DIR/com.claude.deploy-live.running"
  run mig --confirm settings.json+launchd
  [ "$status" -eq 0 ]
  [ "$(grep -c 'com.claude.deploy-live' "$LC_DIR/calls")" -eq 2 ]
  run mig --verify
  [ "$status" -eq 0 ]
}

@test "0055: a tick that outlasts the foreground wait is reloaded by the waiter in the gap after it, never mid-tick" {
  echo 8 > "$LC_DIR/com.claude.deploy-live.running"      # the tick exits after 8 more polls
  run env CC_0055_IDLE_WAIT_S=60 bash "$MIG" --confirm settings.json+launchd
  [ "$status" -eq 0 ]
  [[ "$output" == *"com.claude.deploy-live: reloaded by the gap waiter"* ]] || false
  grep -q 'com.claude.deploy-live: verdict=RELOADED' "$CC_0055_STATE_DIR/0055-reband.log"
  run grep -c 'KILLED-A-RUNNING-TICK' "$LC_DIR/calls"
  [ "$output" -eq 0 ]
  [ "$(grep -c '^bootstrap ' "$LC_DIR/calls")" -eq 4 ]
  run mig --verify
  [ "$status" -eq 0 ]
}

@test "0055: the default waiter is detached — apply exits 0 SCHEDULED, --verify stays NOT live naming it, a re-run does not start a second" {
  : > "$LC_DIR/com.claude.deploy-live.running"
  run env -u CC_0055_DETACH CC_0055_IDLE_WAIT_S=4 bash "$MIG" --confirm settings.json+launchd
  [ "$status" -eq 0 ]
  [[ "$output" == *"com.claude.deploy-live: tick still running after 2s — SCHEDULED: gap waiter pid"* ]] || false
  pid="$(cat "$CC_0055_STATE_DIR/0055-reband-com.claude.deploy-live.pid")"
  run mig --verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"its gap waiter (pid $pid)"* ]] || false
  run mig --confirm settings.json+launchd
  [ "$status" -eq 0 ]
  [[ "$output" == *"gap waiter from an earlier run (pid $pid) is still waiting"* ]] || false
  # the waiter is bounded: it gives up on a tick that never ends, and never boots it out
  i=0; while ps -p "$pid" >/dev/null 2>&1 && [ "$i" -lt 30 ]; do sleep 1; i=$((i + 1)); done
  run ps -p "$pid"
  [ "$status" -ne 0 ]
  grep -q 'com.claude.deploy-live: verdict=GAVE-UP' "$CC_0055_STATE_DIR/0055-reband.log"
  run grep -c 'com.claude.deploy-live' "$LC_DIR/calls"
  [ "$output" -eq 0 ]
}

@test "0055: a job that is not loaded is left alone and does not fail the verifier" {
  rm "$LC_DIR/com.claude.qos-census.loaded"
  run mig --confirm settings.json+launchd
  [ "$status" -eq 0 ]
  run grep -c 'com.claude.qos-census' "$LC_DIR/calls"
  [ "$output" -eq 0 ]
  run mig --verify
  [ "$status" -eq 0 ]
}

@test "0055: a stale installed plist is replaced from the repo copy before the reload, and backed up" {
  printf '<plist><dict><key>ProcessType</key><string>Background</string></dict></plist>\n' \
    > "$CC_MIGRATION_LA_DIR/com.claude.worktree-gc-infra.plist"
  run mig --confirm settings.json+launchd
  [ "$status" -eq 0 ]
  cmp -s "$REPO/launchd/com.claude.worktree-gc-infra.plist" "$CC_MIGRATION_LA_DIR/com.claude.worktree-gc-infra.plist"
  [ "$(find "$HOME/.claude/backups" -name 'com.claude.worktree-gc-infra.plist' | wc -l | tr -d ' ')" -eq 1 ]
}

@test "0055: --confirm must name its target, and an unknown flag is a usage error" {
  run mig --confirm settings.json
  [ "$status" -eq 2 ]
  run mig --apply
  [ "$status" -eq 2 ]
  [ "$(calls)" -eq 0 ]
}
