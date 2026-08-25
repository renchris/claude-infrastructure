#!/usr/bin/env bats
# THE FIELD-ORDER CONTRACT between lr-select.py and its two newest consumers.
#
# WHY THIS SUITE EXISTS (2026-08-25). lr-select.py:434 emits  acct <TAB> sid <TAB> cwd <TAB> branch
# and boot-resume.sh:293 reads its winners back in exactly that order. But cc-resume-classify.py
# and cc-resume-layout.sh both shipped reading field 3 as the session id — i.e. the WORKTREE PATH —
# so the one-liner the resume-sessions skill prescribes,
#
#     lr-select.py --scan --allow-missing-cwd | cc-resume-layout.sh
#
# could never launch anything, and the classifier returned UNKNOWN for every row it was ever given.
#
# WHAT MADE IT INVISIBLE, and why the assertion below is on BEHAVIOUR rather than on the literal
# `cut -f` index: the classifier's failure is FAIL-SAFE. UNKNOWN means "treat as AT-REST", so a
# 100%-broken run nudges nobody — which is indistinguishable from a healthy recovery after a
# planned restart, where nudging nobody is the CORRECT outcome. Measured on the 2026-08-25 reboot:
# 164 rows in, 164 UNKNOWN out, zero nudges, exit 0, no error on any channel. The existing
# --selftest passed 5/5 throughout, because its cases are synthetic in-memory transcripts that
# never traverse the stdin field-parsing path at all. A green selftest is therefore NOT evidence
# about this bug, which is precisely why the coverage had to be added here instead.
#
# Hermetic: HOME is a fixture tree, so the transcript lookup never reads the operator's real stores.

bats_require_minimum_version 1.5.0

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CLASSIFY="$REPO/bin/cc-resume-classify.py"
  LAYOUT="$REPO/bin/cc-resume-layout.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  SID="aaaaaaaa-1111-2222-3333-444444444444"
  WT="$BATS_TEST_TMPDIR/worktrees/wt-example"
  mkdir -p "$WT"
  BOOT=1787642174                       # 2026-08-25T07:16:14Z, the reboot this suite was written on

  # A transcript that is unambiguously AT-REST: the last record is the assistant's own text, and
  # it is old enough to sit outside any plausible alive-window. The verdict is not what is under
  # test — only that the row RESOLVES to a transcript at all, rather than missing the lookup.
  local proj
  proj="$HOME/.claude-next/projects/$(printf '%s' "$WT" | sed 's/[^a-zA-Z0-9]/-/g')"
  mkdir -p "$proj"
  printf '{"type":"assistant","timestamp":"2026-08-24T00:00:00Z","message":{"content":[{"type":"text","text":"done"}]}}\n' \
    > "$proj/$SID.jsonl"

  # lr-select.py's REAL output shape, and the same row with fields 2/3 transposed.
  GOOD="$BATS_TEST_TMPDIR/good.tsv"
  BAD="$BATS_TEST_TMPDIR/bad.tsv"
  printf '%s\t%s\t%s\t%s\n' "next" "$SID" "$WT" "main" > "$GOOD"
  printf '%s\t%s\t%s\t%s\n' "next" "$WT" "$SID" "main" > "$BAD"
}

@test "classify: a row in lr-select's real order RESOLVES its transcript (not UNKNOWN)" {
  run --separate-stderr python3 "$CLASSIFY" --boot-epoch "$BOOT" < "$GOOD"
  [ "$status" -eq 0 ]
  # The 5th column is the verdict. Pre-fix this read UNKNOWN, because the lookup was handed "$WT".
  [ "$(printf '%s' "$output" | cut -f5)" = "AT-REST" ]
  [[ "$stderr" != *"transcript not found"* ]]
}

@test "classify: a TOTAL lookup miss is LOUD and nonzero, never a quiet zero-nudge run" {
  run --separate-stderr python3 "$CLASSIFY" --boot-epoch "$BOOT" < "$BAD"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"INSTRUMENT FAILURE"* ]] || false
  [[ "$stderr" == *"FIELD 2"* ]] || false
  # Fail-safe polarity is preserved even while alarming: the row still classifies as UNKNOWN,
  # which every caller treats as AT-REST. The alarm adds a signal; it never adds a nudge.
  [ "$(printf '%s' "$output" | cut -f5)" = "UNKNOWN" ]
}

@test "classify: a partial miss stays quiet — the alarm indicts the instrument, not one bad row" {
  local mixed="$BATS_TEST_TMPDIR/mixed.tsv"
  cat "$GOOD" > "$mixed"
  printf '%s\t%s\t%s\t%s\n' "next" "bbbbbbbb-0000-0000-0000-000000000000" "$WT" "main" >> "$mixed"
  run --separate-stderr python3 "$CLASSIFY" --boot-epoch "$BOOT" < "$mixed"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"INSTRUMENT FAILURE"* ]]
}

@test "layout: hands reso-resume-one <acct> <worktree> <sid>, not <acct> <sid> <worktree>" {
  run bash "$LAYOUT" --dry-run --file "$GOOD"
  [ "$status" -eq 0 ]
  local line
  line="$(printf '%s\n' "$output" | grep -m1 'reso-resume-one')"
  [ -n "$line" ]
  # reso-resume-one's signature is <account> <worktree-path> <session-id> [branch]. Assert the
  # positions, not merely that both tokens appear somewhere: the pre-fix bug emitted BOTH values,
  # just swapped, so a substring check would have passed against the defect.
  [ "$(printf '%s' "$line" | awk '{print $(NF-2)}')" = "$WT" ]
  [ "$(printf '%s' "$line" | awk '{print $(NF-1)}')" = "$SID" ]
}
