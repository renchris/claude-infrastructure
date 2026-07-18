#!/usr/bin/env bats
# settings.json drift assertion across the 5 config dirs. The tool's --selftest RED-proves the
# detection mechanics; these bats drive it via CC_DRIFT_DIRS against fixture config dirs — the
# independent CLI-level regression on the exit contract (0 = agree, 1 = drift) and the report lines.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/settings-drift-assert.sh"
  D="$BATS_TEST_TMPDIR"
}
mkcfg() { # <dir> <deny-json-array> <stop-cmd>
  mkdir -p "$1"
  jq -n --argjson deny "$2" --arg cmd "$3" \
    '{permissions:{deny:$deny,ask:["Bash(git push:*)"]},hooks:{Stop:[{hooks:[{type:"command",command:$cmd}]}]}}' \
    > "$1/settings.json"
}

@test "selftest passes and runs all 6 checks (a zero-check suite must not 'pass')" {
  run "$S" --selftest
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  ok ')" -eq 6 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "unknown arg → exit 2" {
  run "$S" --bogus
  [ "$status" -eq 2 ]
}

@test "three agreeing config dirs → exit 0 (GREEN)" {
  mkcfg "$D/a" '["Bash(sudo:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  mkcfg "$D/b" '["Bash(sudo:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  mkcfg "$D/c" '["Bash(sudo:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  CC_DRIFT_DIRS="$D/a $D/b $D/c" run "$S" --assert
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'GREEN'
}

@test "a deny rule missing in one dir → exit 1, drift line names array + dir" {
  mkcfg "$D/a" '["Bash(sudo:*)","Bash(rm -rf /:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  mkcfg "$D/b" '["Bash(sudo:*)","Bash(rm -rf /:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  mkcfg "$D/c" '["Bash(sudo:*)"]'                     "~/.claude/hooks/anti-deference-nudge.sh"
  CC_DRIFT_DIRS="$D/a $D/b $D/c" run "$S" --assert
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -qE 'DRIFT \[deny\].*rm -rf'
  printf '%s' "$output" | grep -qE 'missing in:.* c'
}

@test "a Stop hook missing in one dir → exit 1 (the boundary-handoff-on-1/4-dirs class)" {
  mkcfg "$D/a" '["Bash(sudo:*)"]' "~/.claude/hooks/boundary-handoff.sh"
  mkcfg "$D/b" '["Bash(sudo:*)"]' "~/.claude/hooks/boundary-handoff.sh"
  jq -n '{permissions:{deny:["Bash(sudo:*)"],ask:["Bash(git push:*)"]},hooks:{Stop:[]}}' > "$D/x/settings.json" 2>/dev/null || { mkdir -p "$D/x"; jq -n '{permissions:{deny:["Bash(sudo:*)"],ask:["Bash(git push:*)"]},hooks:{Stop:[]}}' > "$D/x/settings.json"; }
  CC_DRIFT_DIRS="$D/a $D/b $D/x" run "$S" --assert
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -qE 'DRIFT \[hooks\].*boundary-handoff'
}

@test "path-spelling variants of the same hook are NOT drift (normalization)" {
  mkcfg "$D/a" '["Bash(sudo:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  mkcfg "$D/b" '["Bash(sudo:*)"]' "/Users/someone/.claude/hooks/anti-deference-nudge.sh"
  CC_DRIFT_DIRS="$D/a $D/b" run "$S" --assert
  [ "$status" -eq 0 ]
}

@test "fewer than 2 dirs with settings.json → nothing to compare (exit 0)" {
  mkcfg "$D/only" '["Bash(sudo:*)"]' "~/.claude/hooks/anti-deference-nudge.sh"
  CC_DRIFT_DIRS="$D/only $D/nonexistent" run "$S" --assert
  [ "$status" -eq 0 ]
}
