#!/usr/bin/env bats
# pane-id-lint.sh — the truncated-pane-UUID detector, and the ONE blind spot it must never grow.
#
# WHY THIS FILE EXISTS (audit 08 §7, 2026-07-25): the lint's in-code precision claim ("across the
# whole corpus this matches exactly two distinct tokens and zero dates/counts") rotted — the corpus
# grew to 7 distinct pane tokens and 4 pure-decimal non-tokens. The obvious precision fix is to
# require ≥1 hex LETTER in the token. That fix is FORBIDDEN: `99261468` is a REAL pane-uuid prefix
# (it is the exact truncation that caused the cc-notify exit-3 hard-fail this lint was built for) and
# it is all digits. The first test below is the do-not-reintroduce pin for that false negative.
#
# HERMETIC: every case builds its own corpus in BATS_TEST_TMPDIR and passes it as $1 (SCAN).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO_ROOT/scripts/pane-id-lint.sh"
  CORPUS="$BATS_TEST_TMPDIR/docs"
  mkdir -p "$CORPUS"
}

@test "BLIND SPOT PIN: the all-digit REAL pane prefix 99261468 still trips the lint" {
  printf 'the successor announced from orchestrator pane 99261468 and cc-notify exit 3ed\n' \
    > "$CORPUS/real-all-digit.md"
  run "$LINT" "$CORPUS"
  [ "$status" -eq 1 ]
  [[ "$output" == *99261468* ]]
}

@test "a hex-lettered truncated pane id trips the lint" {
  printf 'cc-roles/desk = `1EB2C679` (absent from live cc-sessions)\n' > "$CORPUS/hex.md"
  run "$LINT" "$CORPUS"
  [ "$status" -eq 1 ]
  [[ "$output" == *1EB2C679* ]]
}

@test "benign shape (a): a 20xxxxxx rotation date is not a pane id" {
  printf -- '- rotated gz backlog (`*.20260719...gz`, KEEP=8) is bounded\n' > "$CORPUS/date.md"
  run "$LINT" "$CORPUS"
  [ "$status" -eq 0 ]
}

@test "benign shape (b): a size-unit-suffixed byte count is not a pane id" {
  printf -- '- ls showed idl.jsonl 72085650 bytes on disk\n' > "$CORPUS/size.md"
  run "$LINT" "$CORPUS"
  [ "$status" -eq 0 ]
}

@test "benign shape (c): a support.claude.com article id is not a pane id" {
  printf -- 'learn more: https://support.claude.com/en/articles/15363606\n' > "$CORPUS/url.md"
  run "$LINT" "$CORPUS"
  [ "$status" -eq 0 ]
}

@test "the benign filter is TOKEN-level: a line carrying both a byte count and a real pane id still trips" {
  printf -- '- desk D08B4FC0 idl.jsonl 72085650 bytes unacked\n' > "$CORPUS/mixed.md"
  run "$LINT" "$CORPUS"
  [ "$status" -eq 1 ]
  [[ "$output" == *D08B4FC0* ]]
}

@test "a FULL uuid is the sanctioned historical form and is not flagged" {
  printf -- 'historical: pane 1EB2C679-1234-5678-9ABC-DEF012345678 (dead 2026-07-18)\n' > "$CORPUS/full.md"
  run "$LINT" "$CORPUS"
  [ "$status" -eq 0 ]
}

@test "an explicit pane-id-lint:allow marker opts a historical line out" {
  printf -- '- the former desk `1EB2C679` held 631 lines <!-- pane-id-lint:allow -->\n' > "$CORPUS/allow.md"
  run "$LINT" "$CORPUS"
  [ "$status" -eq 0 ]
}

@test "the live docs corpus is clean" {
  run "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == *clean* ]]
}
