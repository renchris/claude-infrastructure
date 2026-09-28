#!/usr/bin/env bats
# hooks/lib/rules-loaded.sh — `rules_file_loads <abs-path>` → loads|excluded|unknown.
#
# The property that matters is the FAILURE DIRECTION: every state in which the answer cannot be
# read must come out `unknown`, never `loads`, because a false `loads` is exactly what told the
# model to delete the only resident pointer to a rule (docs/research/truememory-2026-09-27.md §3.1).
# Each unknown arm is its own test so a regression names which door opened.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/rules-loaded.sh"
  T="$BATS_TEST_TMPDIR"
  S="$T/settings.json"
  export RULES_LOADED_SETTINGS="$S"
  SIT="/x/proj/.claude/rules/agent-operating-lessons-situational.md"
  RES="/x/proj/.claude/rules/agent-operating-lessons.md"
  # shellcheck source=../hooks/lib/rules-loaded.sh
  . "$LIB"
}

# The glob migration 0036 writes, verbatim.
excl() { printf '{"claudeMdExcludes":["**/.claude/rules/agent-operating-lessons-situational.md"]}\n' >"$S"; }

@test "excluded: the 0036 glob matches the situational file at any depth" {
  excl
  run rules_file_loads "$SIT"
  [ "$status" -eq 0 ]
  [ "$output" = excluded ]
}

@test "loads: the resident file beside it is not matched by that glob" {
  excl
  run rules_file_loads "$RES"
  [ "$status" -eq 0 ]
  [ "$output" = loads ]
}

@test "loads: settings with no claudeMdExcludes key at all" {
  printf '{"model":"opus"}\n' >"$S"
  run rules_file_loads "$SIT"
  [ "$output" = loads ]
}

@test "unknown: the settings file does not exist" {
  run rules_file_loads "$SIT"
  [ "$status" -eq 0 ]
  [ "$output" = unknown ]
}

@test "unknown: the settings file is not valid JSON" {
  printf '{"claudeMdExcludes": [\n' >"$S"
  run rules_file_loads "$SIT"
  [ "$status" -eq 0 ]
  [ "$output" = unknown ]
}

@test "unknown: claudeMdExcludes is present but not an array" {
  printf '{"claudeMdExcludes":"**/*.md"}\n' >"$S"
  run rules_file_loads "$SIT"
  [ "$output" = unknown ]
}

@test "unknown: no jq on PATH" {
  excl
  mkdir -p "$T/empty"
  PATH="$T/empty" run rules_file_loads "$SIT"
  [ "$status" -eq 0 ]
  [ "$output" = unknown ]
}

@test "unknown: an empty path is never answered loads" {
  printf '{}\n' >"$S"
  run rules_file_loads ""
  [ "$output" = unknown ]
}

@test "X1: sourced THROUGH A SYMLINK in another dir, the lib still resolves and answers" {
  excl
  mkdir -p "$T/linkdir"
  ln -s "$LIB" "$T/linkdir/rules-loaded.sh"
  run bash -c 'unset -f rules_file_loads; . "$1"; rules_file_loads "$2"; rules_file_loads "$3"' _ \
    "$T/linkdir/rules-loaded.sh" "$SIT" "$RES"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'excluded\nloads')" ]
}

@test "bash 3.2: the lib parses and answers under /bin/bash" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  excl
  run /bin/bash -c '. "$1"; rules_file_loads "$2"' _ "$LIB" "$SIT"
  [ "$status" -eq 0 ]
  [ "$output" = excluded ]
}
