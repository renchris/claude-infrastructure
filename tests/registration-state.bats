#!/usr/bin/env bats
# registration-state.bats — pins the FOUR-state classifier in scripts/registration-state.sh.
#
# The suite fixtures $HOME itself, not merely the store env-vars: every declared verifier reads
# ${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json, so a suite that redirected only CC_MIGRATION_DIR
# would silently answer from the operator's real fleet config and pass or fail for reasons that have
# nothing to do with the subject (MEMORY.md hermetic-in-stubs-not-in-interpreter).
#
# Each state gets its own fixture, and the last test is a MUTATION CONTROL: it breaks the verifier
# and asserts the verdict actually flips. Without it, every green here is consistent with a script
# that prints "registered" unconditionally (MEMORY.md control-must-replay-the-real-artifact).

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SUT="$REPO/scripts/registration-state.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  export CC_CLAUDE_DIR="$HOME/.claude"
  export CC_MIGRATION_DIR="$BATS_TEST_TMPDIR/migrations"
  export CC_MIGRATION_STATE="$BATS_TEST_TMPDIR/state"
  mkdir -p "$CC_MIGRATION_DIR" "$CC_MIGRATION_STATE"/{applied,staged,failed,superseded}
}

# write a migration fixture: <nnnn-name> <class> <subject> <verify> [conflict]
mk_mig() {
  local name="$1" class="$2" subject="$3" verify="$4" conflict="${5:-}"
  {
    printf '#!/bin/bash\n'
    printf '# migration-class: %s\n' "$class"
    printf '# migration-step: fixture\n'
    [ -n "$subject" ] && printf '# migration-subject: %s\n' "$subject"
    [ -n "$verify" ]  && printf '# migration-verify: %s\n' "$verify"
    [ -n "$conflict" ] && printf '# migration-conflict: %s\n' "$conflict"
    printf 'exit 0\n'
  } > "$CC_MIGRATION_DIR/$name.sh"
}

ledger() { : > "$CC_MIGRATION_STATE/$2/$1.json"; }

# A settings.json carrying exactly the hooks named in $@ (as SessionStart commands).
settings_with() {
  local cmds="" c
  for c in "$@"; do cmds="$cmds{\"type\":\"command\",\"command\":\"$c\"},"; done
  printf '{"hooks":{"SessionStart":[{"hooks":[%s]}]}}' "${cmds%,}" > "$HOME/.claude/settings.json"
}

@test "registered: the effect is live in the enforcing store" {
  # shellcheck disable=SC2088  # literal ~ on purpose: settings.json stores the tilde UNEXPANDED and CC expands it at hook-run time, so the fixture must match that spelling exactly.
  settings_with "~/.claude/hooks/armed.sh"
  touch "$HOME/.claude/armed.sh"
  mk_mig 0010-armed c10 "$HOME/.claude/armed.sh" \
    'jq -e '"'"'[.hooks.SessionStart[].hooks[]?.command] | any(. == "~/.claude/hooks/armed.sh")'"'"' "$CC_CLAUDE_DIR/settings.json" >/dev/null'
  ledger 0010-armed staged
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=registered migration=0010-armed"* ]]
}

@test "staged-pending: c10 with the arm present and the effect absent is a PASS, not a failure" {
  # shellcheck disable=SC2088  # literal ~ on purpose: settings.json stores the tilde UNEXPANDED and CC expands it at hook-run time, so the fixture must match that spelling exactly.
  settings_with "~/.claude/hooks/other.sh"
  touch "$HOME/.claude/armed.sh"
  mk_mig 0011-waiting c10 "$HOME/.claude/armed.sh" 'false'
  ledger 0011-waiting staged
  run bash "$SUT"
  [ "$status" -eq 0 ]                      # a correctly-staged c10 must NOT redden the check
  [[ "$output" == *"verdict=staged-pending migration=0011-waiting"* ]] || false
  [[ "$output" == *"FAILING=0"* ]]
}

@test "not-staged: the arm was never written" {
  mk_mig 0012-missing c10 "$HOME/.claude/never-written.sh" 'false'
  ledger 0012-missing staged
  run bash "$SUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=not-staged migration=0012-missing"* ]]
}

@test "not-delivered: ledger says applied but nothing registered it" {
  touch "$HOME/.claude/armed.sh"
  mk_mig 0013-inert c10 "$HOME/.claude/armed.sh" 'false'
  ledger 0013-inert applied
  run bash "$SUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=not-delivered migration=0013-inert"* ]]
}

@test "overridden: a different value is set at the same key, and it outranks not-delivered" {
  touch "$HOME/.claude/armed.sh"
  mk_mig 0014-clobbered c10 "$HOME/.claude/armed.sh" 'false' 'true'
  ledger 0014-clobbered staged
  run bash "$SUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=overridden migration=0014-clobbered"* ]] || false
  # the conflict oracle must win over the staged-pending branch it would otherwise reach
  [[ "$output" != *"verdict=staged-pending migration=0014-clobbered"* ]]
}

@test "unverifiable is counted separately and never folded into the pass tally" {
  mk_mig 0015-silent c10 "$HOME/.claude/armed.sh" ''
  ledger 0015-silent staged
  run bash "$SUT"
  [[ "$output" == *"verdict=unverifiable migration=0015-silent"* ]] || false
  [[ "$output" == *"unverifiable=1"* ]] || false
  [[ "$output" == *"registered=0"* ]]
}

@test "MUTATION CONTROL: breaking the verifier flips registered -> a failing state" {
  # shellcheck disable=SC2088  # literal ~ on purpose: settings.json stores the tilde UNEXPANDED and CC expands it at hook-run time, so the fixture must match that spelling exactly.
  settings_with "~/.claude/hooks/armed.sh"
  touch "$HOME/.claude/armed.sh"
  # identical to the 'registered' fixture except the command the verifier looks for
  mk_mig 0016-mutant c10 "$HOME/.claude/armed.sh" \
    'jq -e '"'"'[.hooks.SessionStart[].hooks[]?.command] | any(. == "~/.claude/hooks/NOT-THE-ONE.sh")'"'"' "$CC_CLAUDE_DIR/settings.json" >/dev/null'
  ledger 0016-mutant applied
  run bash "$SUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=not-delivered migration=0016-mutant"* ]] || false
  [[ "$output" != *"verdict=registered migration=0016-mutant"* ]]
}

@test "hermetic: the check does not read the operator's real settings.json" {
  # If $HOME were not fixtured, this migration's verifier would find the real mailbox-drain entry.
  mk_mig 0017-real c10 "$HOME/.claude/armed.sh" \
    'jq -e '"'"'[.hooks.SessionStart[].hooks[]?.command] | any(test("mailbox-drain"))'"'"' "$CC_CLAUDE_DIR/settings.json" >/dev/null'
  ledger 0017-real staged
  touch "$HOME/.claude/armed.sh"
  # shellcheck disable=SC2088  # literal ~ on purpose: settings.json stores the tilde UNEXPANDED and CC expands it at hook-run time, so the fixture must match that spelling exactly.
  settings_with "~/.claude/hooks/armed.sh"
  run bash "$SUT"
  [[ "$output" != *"verdict=registered migration=0017-real"* ]]
}

# ── MULTI-CONFIG COVERAGE ────────────────────────────────────────────────────────────────────────
# The declared verifiers read ONE settings.json, while the registration migrations deliberately
# write four or five separate REAL files that were measured already divergent. A registration
# present in ~/.claude and absent from ~/.claude-tertiary therefore satisfied the verifier and read
# `registered`, while every session launched against tertiary was unarmed — the same silent
# half-coverage the migration exists to abolish, reproduced in the check itself.

# settings.json for an arbitrary config dir suffix, carrying the named commands
settings_in() {
  local suffix="$1"; shift
  local cmds="" c
  for c in "$@"; do cmds="$cmds{\"type\":\"command\",\"command\":\"$c\"},"; done
  mkdir -p "$HOME/.claude$suffix"
  printf '{"hooks":{"SessionStart":[{"hooks":[%s]}]}}' "${cmds%,}" > "$HOME/.claude$suffix/settings.json"
}

# the verifier every multi-dir case declares — deliberately the SAME spelling the real migrations
# use, so these cases exercise the production oracle rather than a convenience variant
verify_armed() {
  printf '%s' 'jq -e '"'"'[.hooks.SessionStart[].hooks[]?.command] | any(. == "~/.claude/hooks/armed.sh")'"'"' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null'
}

@test "partial: live in one config dir and absent from another is a FAILING state, not registered" {
  unset CC_CLAUDE_DIR
  # shellcheck disable=SC2088  # literal ~ on purpose: settings.json stores the tilde UNEXPANDED.
  settings_in ""      "~/.claude/hooks/armed.sh"
  settings_in "-next"
  touch "$HOME/.claude/armed.sh"
  mk_mig 0010-armed c10 "$HOME/.claude/armed.sh" "$(verify_armed)"
  ledger 0010-armed staged
  run bash "$SUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=partial migration=0010-armed"* ]]
}

@test "partial names WHICH config dir is missing, because that is the whole repair instruction" {
  unset CC_CLAUDE_DIR
  # shellcheck disable=SC2088  # literal ~ on purpose.
  settings_in ""          "~/.claude/hooks/armed.sh"
  settings_in "-tertiary"
  touch "$HOME/.claude/armed.sh"
  mk_mig 0010-armed c10 "$HOME/.claude/armed.sh" "$(verify_armed)"
  ledger 0010-armed staged
  run bash "$SUT"
  [[ "$output" == *"missing: .claude-tertiary"* ]]
}

@test "registered requires EVERY config dir, and says how many it proved" {
  unset CC_CLAUDE_DIR
  # shellcheck disable=SC2088  # literal ~ on purpose.
  settings_in ""      "~/.claude/hooks/armed.sh"
  # shellcheck disable=SC2088  # literal ~ on purpose: a disable covers only the NEXT line, and this
  # is the second config dir, so it needs its own — the first annotation does not reach it.
  settings_in "-next" "~/.claude/hooks/armed.sh"
  touch "$HOME/.claude/armed.sh"
  mk_mig 0010-armed c10 "$HOME/.claude/armed.sh" "$(verify_armed)"
  ledger 0010-armed staged
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"in all 2 config dir(s)"* ]]
}

@test "an EXPLICIT CC_CLAUDE_DIR still scopes the check to exactly that one config" {
  # This is what keeps the rest of this suite hermetic, so it is pinned rather than assumed.
  # shellcheck disable=SC2088  # literal ~ on purpose.
  settings_in ""      "~/.claude/hooks/armed.sh"
  settings_in "-next"
  export CC_CLAUDE_DIR="$HOME/.claude"
  touch "$HOME/.claude/armed.sh"
  mk_mig 0010-armed c10 "$HOME/.claude/armed.sh" "$(verify_armed)"
  ledger 0010-armed staged
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"in all 1 config dir(s)"* ]]
}

@test "MUTATION CONTROL: collapsing the loop back to one dir makes the partial case read registered" {
  # Without this, every green above is consistent with a script that never gained the multi-dir
  # loop at all — the partial fixture would simply pass on ~/.claude and report registered.
  unset CC_CLAUDE_DIR
  # shellcheck disable=SC2088  # literal ~ on purpose.
  settings_in ""      "~/.claude/hooks/armed.sh"
  settings_in "-next"
  touch "$HOME/.claude/armed.sh"
  mk_mig 0010-armed c10 "$HOME/.claude/armed.sh" "$(verify_armed)"
  ledger 0010-armed staged
  mutant="$BATS_TEST_TMPDIR/mutant.sh"
  sed 's/^config_dirs() {/config_dirs() { printf "%s\\n" "$HOME\/.claude"; return;/' "$SUT" > "$mutant"
  bash -n "$mutant"
  run bash "$mutant"
  [[ "$output" == *"verdict=registered migration=0010-armed"* ]]
}
