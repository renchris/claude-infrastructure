#!/usr/bin/env bats
# alarm-polarity-lint — the recurrence guard for row 10's signature bug class
# (OPERATOR_SURFACE_V2 §4 F10). For a VERDICT ask "is it red?"; for an ALARM ask "is it green?".
#
# THE PROOF THAT MATTERS is the positive control: the lint must catch the REAL pre-fix predicate
# recovered from git, not a hand-written approximation of it (memory
# control-must-replay-the-real-artifact — a RED-proof against an approximation passes vacuously).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  L="$REPO/scripts/alarm-polarity-lint.sh"
  D="$BATS_TEST_TMPDIR"
}

# THE BASELINE IS VENDORED, so this control can no longer be SKIPPED (2026-08-11, grok-wiki tests
# shard candidate 3, backlog 9ea31151dd94). It used to be recovered from history on every run, and
# `[ -n "$sha" ] || skip` was the only thing standing between "no baseline reachable" and a green
# suite. Measured, not argued: `git clone --depth 1` of this repo leaves ONE commit touching
# bin/cc-blockers, the three-condition selector returns empty, and the strongest control in this
# file silently does not run while `bats tests/alarm-polarity-lint.bats` reports ok. A positive
# control that can decline to run is exactly the vacuous pass this repo keeps re-learning.
#
# WHY GZIPPED and not a plain checked-in script: it is an 881-line shell file from 2026-07-29 with a
# deliberate defect in it. Dropped into the tree as a *.sh it re-enters is_shell_file() and with it
# every one of the land gate's shell ratchets — shellcheck, bash -n, unguarded-kill, afunix,
# pipefail-sigpipe, git-identity — as NEW findings owned by whoever lands it. A gzip stream matches
# no shebang and no extension, so the artifact is preserved byte-for-byte without conscripting a
# historical file into today's rules. The `-n` on gzip drops the timestamp, so the blob is
# reproducible from the same input.
#
# It cannot be doctored: the sha256 below pins the plaintext, and the separate cross-check test
# asserts the fixture is byte-identical to what git holds whenever history CAN answer.
PREFIX_SHA=39ebcd072289d02678f4efc79abc1f111970e98b
PREFIX_SHA256=98181e53bf76153bfaa8f053a3c979563848ee446e8af38991f7df688d84a0eb

prefix_baseline() {   # → $D/prefix, from the vendored artifact; never consults history
  gunzip -c "$REPO/tests/fixtures/cc-blockers-prefix-39ebcd07.gz" > "$D/prefix"
  [ "$(shasum -a 256 "$D/prefix" | cut -d' ' -f1)" = "$PREFIX_SHA256" ] || false
}

@test "POSITIVE CONTROL: catches the REAL pre-fix cc-blockers predicate (vendored — never skipped)" {
  # The exact artifact, not a reconstruction: bin/cc-blockers at 39ebcd07, the newest commit whose
  # alarm still tested `[ "$red" -eq "$seen" ]` AND carried no suppression marker. That commit was
  # selected by the three-condition walk preserved verbatim in the cross-check below — the selector's
  # reasoning is still live, it just no longer holds the power to silence this control.
  #
  # THE SECOND CONDITION IS LOAD-BEARING and was missing on the first cut, which broke this control on
  # the VERY NEXT commit to bin/cc-blockers. The predicate string SURVIVES in the fixed file — the
  # state-naming line `[ "$red" -eq "$seen" ]` is legitimate there and carries
  # `# alarm-polarity-ok:` — so a selector keyed on the string alone walks back exactly ONE commit,
  # finds the CURRENT justified version, and the lint correctly returns 0. The control then reports
  # "the lint does not catch the bug" while actually having tested the wrong file. A too-loose
  # baseline selector converts a positive control into a no-op the moment the guarded code evolves
  # (memory control-must-replay-the-real-artifact). Require the UNFIXED shape explicitly.
  # THREE conditions, and the third matters as much as the second: no `notgreen` counter either, or
  # the selector settles on the POST-M1 commit — which still carries an unsuppressed state-naming
  # `[ "$red" -eq "$seen" ]`, so the lint fires and the test passes while having tested a file where
  # the alarm was ALREADY FIXED. That proves "the lint recognises the shape", not "the lint would have
  # caught the original bug", which is what this control claims. Measured: without it the selector
  # picked f1451bcf, whose cc-blockers contains `notgreen` six times.
  prefix_baseline
  # HARNESS SELF-CHECK, the same discipline statusline-identity.bats uses: prove the baseline really
  # is the unfixed implementation before believing anything the lint says about it. A bad extraction
  # must not be able to make this control pass.
  grep -q '"\$red" -eq "\$seen"' "$D/prefix" || false
  ! grep -q 'notgreen' "$D/prefix" || false
  ! grep -q 'alarm-polarity-ok' "$D/prefix" || false
  run bash "$L" "$D/prefix"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'POLARITY' || false
  echo "$output" | grep -q '`red` is incremented ONLY on a named failure' || false
}

@test "the vendored baseline IS the git artifact — byte-identical to the commit the selector picks" {
  # The rot guard on the fixture, and the only place history is still consulted. THIS may skip: on a
  # shallow clone git genuinely cannot answer, and a cross-check that cannot run is not a control
  # that silently passed — the control above already ran, unconditionally, on the pinned bytes.
  #
  # The selector is preserved verbatim from the original control because its reasoning is still what
  # justifies the pin: it must land on 39ebcd07 and on nothing else. If a future commit to
  # bin/cc-blockers re-introduces the unfixed shape, this test goes RED rather than quietly
  # re-baselining, which is the failure mode a history-derived baseline had by construction.
  sha="$(cd "$REPO" && git log --format=%H -- bin/cc-blockers | while read -r c; do
           b="$(git show "$c:bin/cc-blockers" 2>/dev/null)" || continue
           if printf '%s' "$b" | grep -q '"\$red" -eq "\$seen"' \
              && ! printf '%s' "$b" | grep -q 'alarm-polarity-ok' \
              && ! printf '%s' "$b" | grep -q 'notgreen'; then echo "$c"; break; fi
         done)"
  [ -n "$sha" ] || skip "shallow/pruned history — the fixture stands on its pinned sha256 instead"
  [ "$sha" = "$PREFIX_SHA" ] || false
  prefix_baseline
  (cd "$REPO" && git show "$sha:bin/cc-blockers") > "$D/fromgit"
  cmp "$D/prefix" "$D/fromgit" || false
}

@test "the CURRENT declared alarm set is clean (the fix holds, and the suppression is explained)" {
  run bash "$L"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '0 inverted alarm predicates' || false
  echo "$output" | grep -q '1 explained suppression' || false
}

@test "NEGATIVE CONTROL: a not-green counter is NOT flagged (the fixed shape must pass)" {
  cat > "$D/ok.sh" <<'EOS'
#!/bin/bash
while read -r v; do
  [ "$v" != "green" ] && notgreen=$((notgreen + 1))
  seen=$((seen + 1))
done
[ "$notgreen" -eq "$seen" ] && echo ALARM
EOS
  run bash "$L" "$D/ok.sh"
  [ "$status" -eq 0 ]
}

@test "a BARE suppression marker is reported — typing the magic word is not evidence" {
  cat > "$D/bare.sh" <<'EOS'
#!/bin/bash
[ "$v" = "red" ] && red=$((red + 1))
# alarm-polarity-ok
[ "$red" -eq "$seen" ] && echo ALARM
EOS
  run bash "$L" "$D/bare.sh"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'BARE-SUPPRESSION' || false
}

@test "an EXPLAINED suppression on the adjacent line silences it" {
  cat > "$D/ok2.sh" <<'EOS'
#!/bin/bash
[ "$v" = "red" ] && red=$((red + 1))
# alarm-polarity-ok: this names a state, it does not gate an alarm
[ "$red" -eq "$seen" ] && echo LABEL
EOS
  run bash "$L" "$D/ok2.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '1 explained suppression' || false
}

@test "kill switch CC_ALARM_POLARITY_LINT=off ABSTAINS LOUDLY — never a silent pass" {
  cat > "$D/bad.sh" <<'EOS'
#!/bin/bash
[ "$v" = "hung" ] && hung=$((hung + 1))
[ "$hung" -eq "$seen" ] && echo ALARM
EOS
  run env CC_ALARM_POLARITY_LINT=off bash "$L" "$D/bad.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'ABSTAIN' || false
  echo "$output" | grep -q 'this is not a pass' || false
}

@test "scope: with no args it lints the DECLARED set, never the whole tree" {
  # A blocking lint scoped to the tree makes every author answerable for every other's.
  run bash "$L"
  echo "$output" | grep -qE '[0-9]+ file\(s\) scanned' || false
  n="$(echo "$output" | sed -n 's/.*clean — \([0-9]*\) file.*/\1/p')"
  [ "$n" -le 8 ]
}
