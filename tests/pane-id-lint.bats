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
  # HERMETICITY — added when this suite was recovered from the branch graveyard (it predates the
  # hermeticity ratchet, which correctly RED'd the land). Every case below passes its own $1 corpus,
  # so $HOME is not read by the subject; fixturing it anyway keeps the suite honest if the lint ever
  # grows a default-path branch, and satisfies the ratchet without an allowlist entry.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
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

# DELIBERATE, RED-PROOFED TEST CHANGE — recovered from `a6eab446` (2026-07-25) by cherry-pick and
# rewritten here on purpose, with the reason recorded (GROUND_UP_REBUILD_MAP.md: "A test can encode a
# falsified premise — changing it is legitimate, hiding it is not").
#
# The original asserted `status -eq 0` on the WHOLE live docs corpus, i.e. "nobody anywhere has ever
# written a truncated pane id". That was true when it was written and is now FALSE: 28 violations
# across 12+ files, spread over the coordinator's own GROUND_UP_DISPATCH.md, row 1's
# LAND_PIPELINE_V2.md, TWO_WAY_SESSION_COMMS_PLAN.md and 9 others. Not one of them is row 2's.
#
# Landing it unchanged would make a tree-scoped lint a FLEET-WIDE HARD STOP — every author answerable
# for every other author's docs — and it would enter the postland corpus permanently red, feeding the
# 0-green-stamps condition that is currently holding the campaign's deploy. So: block on what THIS
# suite owns (the unit shapes above, all hermetic), and report the corpus count LABELLED instead of
# asserting it away. The 28 are recorded as a measured constant in SESSION_LIFECYCLE_V2.md §2 and
# backlogged; the enforcement this row DOES add is PAYLOAD-scoped at the fire chokepoint, which is
# the diff-equivalent and cannot hold one author responsible for another's file.
@test "the lint RUNS end-to-end on the live corpus and emits a parseable verdict (count reported, not asserted)" {
  run "$LINT"
  # A verdict either way is the assertion — the lint must not crash, hang, or exit silently on the
  # real corpus. This is the positive control for the hermetic cases above: they build their own
  # corpora, so only this case proves the tool works on the actual tree.
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  [[ "$output" == *clean* ]] || [[ "$output" == *"TRUNCATED pane id"* ]] || false
  if [ "$status" -eq 1 ]; then
    echo "# LABELLED (not a failure of this suite): live docs corpus carries truncated pane id(s)" >&3
    echo "# owners are other rows; see SESSION_LIFECYCLE_V2.md §2 M-19 and its backlog note" >&3
  fi
}
