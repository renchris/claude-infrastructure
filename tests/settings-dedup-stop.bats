#!/usr/bin/env bats
# settings-dedup-stop.sh — the WRITE-side complement to settings-drift-assert.sh: collapse a
# strictly-redundant duplicate hook object (the G-P6-5b boundary-handoff double-registration class,
# cc-backlog f15ca1237fd2). The tool's --selftest RED-proves the rule end-to-end; these bats pin the
# CLI contract (dry-run vs --apply, backup, exit codes, matcher-awareness, scope, idempotence).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/settings-dedup-stop.sh"
  D="$BATS_TEST_TMPDIR"
}

# the live bug: an obj-0 chain ending in the portable boundary-handoff + a standalone machine-absolute
# boundary object (identical hook, different path spelling → same hook by basename normalization).
mklive() {
  jq -n '{hooks:{Stop:[
      {hooks:[
        {type:"command",command:"~/.claude/hooks/anti-deference-nudge.sh"},
        {type:"command",command:"~/.claude/hooks/boundary-handoff.sh"}]},
      {hooks:[{type:"command",command:"/Users/x/Development/claude-infrastructure/hooks/boundary-handoff.sh"}]}
    ]}}' > "$1"
}

@test "selftest passes and runs all 10 checks (a zero-check suite must not 'pass')" {
  run "$S" --selftest
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  ok   ')" -eq 10 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "unknown arg → exit 2" {
  run "$S" --bogus
  [ "$status" -eq 2 ]
}

@test "no file path → exit 2" {
  run "$S" --apply
  [ "$status" -eq 2 ]
}

@test "missing file → exit 3" {
  run "$S" "$D/does-not-exist.json"
  [ "$status" -eq 3 ]
}

@test "dry-run reports the machine-absolute obj#1 and does NOT mutate" {
  mklive "$D/s.json"
  run "$S" "$D/s.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qE 'DROP +Stop obj#1'
  [ "$(jq '.hooks.Stop | length' "$D/s.json")" -eq 2 ]   # untouched
  [ ! -f "$D/s.json.dedup.bak" ]                          # no backup on dry-run
}

@test "--apply collapses 2→1, keeps boundary-handoff exactly once, writes .dedup.bak" {
  mklive "$D/s.json"
  run "$S" --apply "$D/s.json"
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.Stop | length' "$D/s.json")" -eq 1 ]
  [ "$(jq -r '[.hooks.Stop[].hooks[].command | select(test("boundary-handoff"))] | length' "$D/s.json")" -eq 1 ]
  # the surviving registration is the portable one from obj-0 (anti-deference chain preserved)
  jq -e '.hooks.Stop[0].hooks | map(.command) | index("~/.claude/hooks/anti-deference-nudge.sh")' "$D/s.json"
  [ -f "$D/s.json.dedup.bak" ]
}

@test "--apply is idempotent — second run is a clean no-op" {
  mklive "$D/s.json"
  "$S" --apply "$D/s.json"
  run "$S" --apply "$D/s.json"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'clean'
  [ "$(jq '.hooks.Stop | length' "$D/s.json")" -eq 1 ]
}

@test "different matchers are never collapsed (matcher-awareness)" {
  jq -n '{hooks:{PreToolUse:[
      {matcher:"Bash",hooks:[{type:"command",command:"~/.claude/hooks/g.sh"}]},
      {matcher:"Edit",hooks:[{type:"command",command:"~/.claude/hooks/g.sh"}]}]}}' > "$D/m.json"
  run "$S" --all-events --apply "$D/m.json"
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.PreToolUse | length' "$D/m.json")" -eq 2 ]
}

@test "a distinct (non-subset) second object is preserved" {
  jq -n '{hooks:{Stop:[
      {hooks:[{type:"command",command:"~/.claude/hooks/a.sh"}]},
      {hooks:[{type:"command",command:"~/.claude/hooks/b.sh"}]}]}}' > "$D/d.json"
  run "$S" --apply "$D/d.json"
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.Stop | length' "$D/d.json")" -eq 2 ]
}

@test "default scope is Stop-only; --event targets another event" {
  jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"~/.claude/hooks/s.sh"}]}],
                 SessionStart:[
                   {hooks:[{type:"command",command:"~/.claude/hooks/w.sh"}]},
                   {hooks:[{type:"command",command:"/abs/w.sh"}]}]}}' > "$D/e.json"
  "$S" --apply "$D/e.json"
  [ "$(jq '.hooks.SessionStart | length' "$D/e.json")" -eq 2 ]   # untouched by default
  run "$S" --event SessionStart --apply "$D/e.json"
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.SessionStart | length' "$D/e.json")" -eq 1 ]
}
