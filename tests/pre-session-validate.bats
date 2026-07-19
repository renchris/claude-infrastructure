#!/usr/bin/env bats
# pre-session-validate.sh — SessionStart hook. Two jobs: (1) the SETTINGS MODEL
# PORTABILITY GUARD strips a window-bound frontier model (fable / claude-fable-5)
# left saved as the default in the LAUNCHING account's settings.json; (2) auto-rollback
# of a broken ~/.claude-versions/current binary. These tests exercise job (1) — the
# T-P10-3 fix: the guard MUST read the launching account's settings via
# CLAUDE_CONFIG_DIR, not a hardcoded ~/.claude/settings.json (which would only ever heal
# the DEFAULT account and leave every non-default account bricked). Each test points
# HOME at a throwaway dir with no ~/.claude-versions/current, so the script runs the
# guard and then exits 0 at the "no current symlink" gate — job (2) never fires.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/pre-session-validate.sh"
}

# saved "model" value of a settings.json ('' when the key is absent)
model_of() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('model',''))" "$1" 2>/dev/null; }

@test "guard strips fable from the LAUNCHING account (CLAUDE_CONFIG_DIR), leaving the default account untouched" {
  h="$BATS_TEST_TMPDIR/home"; cfg="$BATS_TEST_TMPDIR/cfg"
  mkdir -p "$h/.claude" "$cfg"
  printf '%s\n' '{"model": "fable", "keepKey": "keepVal"}' > "$cfg/settings.json"
  printf '%s\n' '{"model": "fable"}'                       > "$h/.claude/settings.json"  # default-account control
  run env HOME="$h" CLAUDE_CONFIG_DIR="$cfg" bash "$HOOK" </dev/null
  [ "$status" -eq 0 ]
  # launching account: model stripped, sibling keys preserved
  [ -z "$(model_of "$cfg/settings.json")" ]
  run python3 -c "import json;print(json.load(open('$cfg/settings.json'))['keepKey'])"
  [ "$output" = "keepVal" ]
  # default account: UNTOUCHED — the pre-fix hardcoded path would have stripped THIS instead
  [ "$(model_of "$h/.claude/settings.json")" = "fable" ]
  # a backup of the mutated account's settings was written next to it
  ls "$cfg"/settings.json.bak-model-guard-* >/dev/null 2>&1
}

@test "a non-default launch never mutates the default account's settings (no cross-account write)" {
  h="$BATS_TEST_TMPDIR/home"; cfg="$BATS_TEST_TMPDIR/cfg"
  mkdir -p "$h/.claude" "$cfg"
  printf '%s\n' '{"model": "sonnet"}' > "$cfg/settings.json"        # launching account: clean (no fable)
  printf '%s\n' '{"model": "fable"}'  > "$h/.claude/settings.json"  # default account: has a fable default
  run env HOME="$h" CLAUDE_CONFIG_DIR="$cfg" bash "$HOOK" </dev/null
  [ "$status" -eq 0 ]
  # default account's fable is NOT stripped — the pre-fix bug read $HOME/.claude and would have stripped it here
  [ "$(model_of "$h/.claude/settings.json")" = "fable" ]
  # launching account untouched; no stray backup written into the default account's dir
  [ "$(model_of "$cfg/settings.json")" = "sonnet" ]
  ! ls "$h/.claude"/settings.json.bak-model-guard-* >/dev/null 2>&1
}

@test "guard still heals the default account when CLAUDE_CONFIG_DIR is unset (backward compat)" {
  h="$BATS_TEST_TMPDIR/home"
  mkdir -p "$h/.claude"
  printf '%s\n' '{"model": "claude-fable-5", "x": 1}' > "$h/.claude/settings.json"
  run env -u CLAUDE_CONFIG_DIR HOME="$h" bash "$HOOK" </dev/null
  [ "$status" -eq 0 ]
  [ -z "$(model_of "$h/.claude/settings.json")" ]
  run python3 -c "import json;print(json.load(open('$h/.claude/settings.json'))['x'])"
  [ "$output" = "1" ]
}

@test "guard leaves a non-frontier saved model untouched" {
  h="$BATS_TEST_TMPDIR/home"; cfg="$BATS_TEST_TMPDIR/cfg"
  mkdir -p "$h/.claude" "$cfg"
  printf '%s\n' '{"model": "opus"}' > "$cfg/settings.json"
  run env HOME="$h" CLAUDE_CONFIG_DIR="$cfg" bash "$HOOK" </dev/null
  [ "$status" -eq 0 ]
  [ "$(model_of "$cfg/settings.json")" = "opus" ]
}

@test "kill switch (PRE_SESSION_VALIDATE_DISABLED=1) skips the guard entirely" {
  h="$BATS_TEST_TMPDIR/home"; cfg="$BATS_TEST_TMPDIR/cfg"
  mkdir -p "$h/.claude" "$cfg"
  printf '%s\n' '{"model": "fable"}' > "$cfg/settings.json"
  run env HOME="$h" CLAUDE_CONFIG_DIR="$cfg" PRE_SESSION_VALIDATE_DISABLED=1 bash "$HOOK" </dev/null
  [ "$status" -eq 0 ]
  [ "$(model_of "$cfg/settings.json")" = "fable" ]   # untouched: disabled means no guard
}
