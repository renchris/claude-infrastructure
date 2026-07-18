#!/usr/bin/env bats
# install.sh --wire-hooks — event merge + WITHIN-EVENT union (append-only, matcher-aware, idempotent).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CFG="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CFG"
  # target: populated Stop obj-1 WITHOUT boundary/completion; SessionStart without dod-persist;
  # PreToolUse Bash object without keychain; PreCompact auto object without dod-persist.
  cat > "$CFG/settings.json" <<'JSON'
{ "hooks": {
    "Stop": [ { "hooks": [
      { "type":"command","command":"~/.claude/hooks/notify.sh complete","timeout":5 },
      { "type":"command","command":"~/.claude/hooks/session-continue.sh","timeout":5 },
      { "type":"command","command":"~/.claude/hooks/anti-deference-nudge.sh","timeout":5 } ] } ],
    "SessionStart": [ { "hooks": [ { "type":"command","command":"~/.claude/hooks/session-start.sh","timeout":5 } ] } ],
    "PreToolUse": [ { "matcher":"Bash","hooks":[ { "type":"command","command":"~/.claude/hooks/validate-bash.sh","timeout":10 } ] } ],
    "PreCompact": [ { "matcher":"auto","hooks":[ { "type":"command","command":"echo x","timeout":5 } ] } ]
  }, "permissions": { "deny": [], "ask": [] } }
JSON
}

run_wire() { run bash "$REPO/install.sh" --wire-hooks --config-dir "$CFG"; }

@test "within-event union: boundary + completion-assert land at Stop obj-1 tail, order preserved" {
  run_wire; [ "$status" -eq 0 ]
  run jq -r '[.hooks.Stop[0].hooks[].command] | join("|")' "$CFG/settings.json"
  [[ "$output" == *"notify.sh complete|"*"session-continue.sh|"*"anti-deference-nudge.sh"* ]]
  [[ "$output" == *"completion-assert.sh"* ]]
  [[ "$output" == *"boundary-handoff.sh"* ]]
  # pre-existing order intact (notify before continue before anti-def)
  [[ "$output" =~ notify.*session-continue.*anti-deference ]]
}

@test "matcher-aware: keychain-guard joins the EXISTING Bash object; dod-persist joins the auto PreCompact object" {
  run_wire; [ "$status" -eq 0 ]
  run jq '[.hooks.PreToolUse[] | select(.matcher=="Bash")] | length' "$CFG/settings.json"
  [ "$output" -eq 1 ]   # no duplicate Bash object created
  run jq -r '[.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[].command] | join("|")' "$CFG/settings.json"
  [[ "$output" == *"validate-bash.sh"* && "$output" == *"keychain-guard.sh"* ]]
  run jq -r '[.hooks.PreCompact[] | select(.matcher=="auto") | .hooks[].command] | join("|")' "$CFG/settings.json"
  [[ "$output" == *"echo x"* && "$output" == *"dod-persist.sh"* ]]
}

@test "SessionStart gains dod-persist without touching the existing object" {
  run_wire; [ "$status" -eq 0 ]
  run jq -r '[.hooks.SessionStart[].hooks[].command] | join("|")' "$CFG/settings.json"
  [[ "$output" == *"session-start.sh"* && "$output" == *"dod-persist.sh"* ]]
}

@test "idempotent: second run is byte-identical" {
  run_wire; [ "$status" -eq 0 ]
  cp "$CFG/settings.json" "$CFG/first.json"
  run_wire; [ "$status" -eq 0 ]
  run diff "$CFG/settings.json" "$CFG/first.json"
  [ "$status" -eq 0 ]
}

@test "RED-guard: a target that already has every command gains nothing and loses nothing" {
  run_wire; [ "$status" -eq 0 ]
  before=$(jq -S . "$CFG/settings.json")
  run_wire; [ "$status" -eq 0 ]
  after=$(jq -S . "$CFG/settings.json")
  [ "$before" = "$after" ]
}
