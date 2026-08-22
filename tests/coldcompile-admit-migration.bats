#!/usr/bin/env bats
# migrations/0006-coldcompile-admit-registration.sh — the c10 registration half of Wave C.
#
# WHY THIS FILE EXISTS SEPARATELY FROM THE STAGING TEST. `tests/deploy-migrations.bats` asserts that
# every migration DECLARES a class, which is what stops an undeclared one reaching a converge. It
# says nothing about whether the body works. A c10 migration is staged and never run by the
# converger, so its body's FIRST execution is the operator pasting the command — the one moment
# nobody is watching it. A prescription that has never been run in the context that executes it is
# the shape MEMORY.md records as prescribed-remedy-worse-than-the-bug, so it is run here, twice,
# against a real settings.json copy in a fixtured $HOME.
#
# Hermetic: $HOME is a throwaway tree. The fixture settings.json is a REAL structural copy of the
# live one's PreToolUse Bash group, because a hand-simplified approximation would pass vacuously
# (MEMORY.md control-must-replay-the-real-artifact).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REPO/migrations/0006-coldcompile-admit-registration.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"
  mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/bin" "$HOME/.claude/config"

  # The live layer, as install.sh builds it: per-file symlinks into the checkout. The migration's
  # precondition walks these, so they must be links and not copies.
  ln -s "$REPO/hooks/coldcompile-admit.sh" "$HOME/.claude/hooks/coldcompile-admit.sh"

  SETTINGS="$HOME/.claude/settings.json"
  jq -n '{
    hooks: {
      PreToolUse: [
        { matcher: "Write|Edit", hooks: [ {type:"command", command:"~/.claude/hooks/backup-before-write.sh"} ] },
        { matcher: "Bash", hooks: [
            {type:"command", command:"~/.claude/hooks/validate-bash.sh", timeout:10},
            {type:"command", command:"$HOME/.claude/hooks/qos-rewrite.sh", timeout:10}
        ] }
      ]
    }
  }' > "$SETTINGS"
  # shellcheck disable=SC2088  # the tilde is DELIBERATELY literal — this is the exact string
  # stored INTO settings.json, where CC expands it at hook-run time. Expanding it here would make
  # the assertion pass against a value the migration never writes.
  HOOK_CMD='~/.claude/hooks/coldcompile-admit.sh'
}

registered() { jq -e --arg c "$HOOK_CMD" '[.hooks.PreToolUse[]?.hooks[]?.command] | any(. == $c)' "$SETTINGS" >/dev/null 2>&1; }
bash_group_len() { jq -r '[.hooks.PreToolUse[] | select(.matcher=="Bash")][0].hooks | length' "$SETTINGS"; }

@test "1 registers into the Bash group and nowhere else" {
  run bash "$MIG"
  [ "$status" -eq 0 ]
  registered
  [ "$(bash_group_len)" = "3" ]
  # the Write|Edit group is untouched — a migration that appends to the wrong group reads GREEN
  [ "$(jq -r '[.hooks.PreToolUse[] | select(.matcher=="Write|Edit")][0].hooks | length' "$SETTINGS")" = "1" ]
  [ "$(jq -r --arg c "$HOOK_CMD" '[.hooks.PreToolUse[] | select(.matcher=="Bash")][0].hooks | map(select(.command==$c))[0].timeout' "$SETTINGS")" = "10" ]
}

@test "2 a second run is a no-op, not a duplicate entry" {
  bash "$MIG" >/dev/null
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already registered"* ]] || false
  [ "$(jq -r --arg c "$HOOK_CMD" '[.hooks.PreToolUse[]?.hooks[]?.command] | map(select(. == $c)) | length' "$SETTINGS")" = "1" ]
}

@test "3 --undo removes exactly the one entry and leaves the siblings" {
  bash "$MIG" >/dev/null
  run bash "$MIG" --undo
  [ "$status" -eq 0 ]
  ! registered || false
  [ "$(bash_group_len)" = "2" ]
  jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | any(test("qos-rewrite"))' "$SETTINGS" >/dev/null
  jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | any(test("validate-bash"))' "$SETTINGS" >/dev/null
}

@test "4 the settings.json is left VALID json and a backup survives" {
  bash "$MIG" >/dev/null
  jq -e . "$SETTINGS" >/dev/null
  [ "$(find "$HOME/.claude" -name 'settings.json.bak-0006-*' | wc -l | tr -d ' ')" = "1" ]
}

@test "5 an un-deployed hook REFUSES to register — a registration naming a dead path reads green" {
  rm "$HOME/.claude/hooks/coldcompile-admit.sh"
  run bash "$MIG"
  [ "$status" -ne 0 ]
  ! registered || false
  [[ "$output" == *"missing or not executable"* ]]
}

@test "6 a live layer whose checkout lacks the gate REFUSES — registering it there would be inert" {
  # MUTATION-SHAPED CONTROL for case 5's sibling precondition: the hook IS deployed and executable,
  # but the tree it links into carries no bin/cc-ignition-gate, so every emission would name a
  # binary that does not exist and the hook would decline forever while reading as registered.
  local fake="$D/fake-checkout"
  mkdir -p "$fake/hooks" "$fake/config"
  cp "$REPO/hooks/coldcompile-admit.sh" "$fake/hooks/coldcompile-admit.sh"
  cp "$REPO/config/coldcompile.patterns" "$fake/config/coldcompile.patterns"
  rm "$HOME/.claude/hooks/coldcompile-admit.sh"
  ln -s "$fake/hooks/coldcompile-admit.sh" "$HOME/.claude/hooks/coldcompile-admit.sh"
  run bash "$MIG"
  [ "$status" -ne 0 ]
  ! registered || false
  [[ "$output" == *"would be inert"* ]]
}

@test "7 a settings.json with no Bash group is skipped, never invented" {
  jq 'del(.hooks.PreToolUse[1])' "$SETTINGS" > "$SETTINGS.new" && mv "$SETTINGS.new" "$SETTINGS"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  ! registered || false
  [[ "$output" == *"not a fleet config"* ]]
}

# ── the ENUMERATION axis ──────────────────────────────────────────────────────────────────────────
# Tests 1-7 all run against the setup() fixture, which builds exactly ONE config dir. That is a
# population of one, so a loop that names four of the fleet's five dirs passes every one of them —
# the axis is not weakly covered here, it is structurally unreachable. `.claude-next` was the missing
# member, and it is the DEFAULT dir of the bare `claude` launcher, so the gap was in the busiest
# account. The fixture below is the first in this file with a fleet in it.
peer() { # <dirname> — a second fleet config dir carrying the same real Bash group shape
  mkdir -p "$HOME/$1"
  cp -p "$SETTINGS" "$HOME/$1/settings.json"
}
reg_in() { jq -e --arg c "$HOOK_CMD" '[.hooks.PreToolUse[]?.hooks[]?.command] | any(. == $c)' "$HOME/$1/settings.json" >/dev/null 2>&1; }

@test "8 registers into ALL FIVE fleet config dirs, and into no dir outside the fleet" {
  for d in .claude-next .claude-secondary .claude-tertiary .claude-quaternary .claude-experimental; do peer "$d"; done

  run bash "$MIG"
  [ "$status" -eq 0 ]

  # every fleet member, named individually so a failure says WHICH dir was missed
  registered
  reg_in .claude-next
  reg_in .claude-secondary
  reg_in .claude-tertiary
  reg_in .claude-quaternary

  # DISCRIMINATING CONTROL: the loop is an enumeration of the fleet, not a glob over $HOME/.claude*.
  # Without this, a "fix" that globbed every config-shaped dir would read identically green while
  # registering a PreToolUse hook into a dir nobody declared part of the fleet.
  ! reg_in .claude-experimental || false
}

@test "9 the five-dir run stays idempotent — no dir gains a duplicate entry" {
  for d in .claude-next .claude-secondary .claude-tertiary .claude-quaternary; do peer "$d"; done
  bash "$MIG" >/dev/null
  run bash "$MIG"
  [ "$status" -eq 0 ]
  for d in .claude .claude-next .claude-secondary .claude-tertiary .claude-quaternary; do
    n="$(jq -r --arg c "$HOOK_CMD" '[.hooks.PreToolUse[]?.hooks[]? | select(.command==$c)] | length' "$HOME/$d/settings.json")"
    [ "$n" = "1" ] || { echo "dir $d has $n entries, expected exactly 1"; false; }
  done
}
