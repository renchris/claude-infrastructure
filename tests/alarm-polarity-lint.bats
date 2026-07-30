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

@test "POSITIVE CONTROL: catches the REAL pre-fix cc-blockers predicate recovered from git" {
  # The exact artifact, not a reconstruction: the newest commit of bin/cc-blockers whose alarm still
  # tested `[ "$red" -eq "$seen" ]` AND carried no suppression marker. If no such commit is reachable
  # the control cannot run, and a control that cannot run must SKIP loudly, never pass.
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
  sha="$(cd "$REPO" && git log --format=%H -- bin/cc-blockers | while read -r c; do
           b="$(git show "$c:bin/cc-blockers" 2>/dev/null)" || continue
           if printf '%s' "$b" | grep -q '"\$red" -eq "\$seen"' \
              && ! printf '%s' "$b" | grep -q 'alarm-polarity-ok' \
              && ! printf '%s' "$b" | grep -q 'notgreen'; then echo "$c"; break; fi
         done)"
  [ -n "$sha" ] || skip "no pre-fix baseline reachable in history"
  (cd "$REPO" && git show "$sha:bin/cc-blockers") > "$D/prefix"
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
