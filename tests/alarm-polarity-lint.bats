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
  # tested `[ "$red" -eq "$seen" ]`. If no such commit is reachable the control cannot run, and a
  # control that cannot run must SKIP loudly, never pass.
  sha="$(cd "$REPO" && git log --format=%H -- bin/cc-blockers | while read -r c; do
           if git show "$c:bin/cc-blockers" 2>/dev/null | grep -q '"\$red" -eq "\$seen"'; then echo "$c"; break; fi
         done)"
  [ -n "$sha" ] || skip "no pre-fix baseline reachable in history"
  (cd "$REPO" && git show "$sha:bin/cc-blockers") > "$D/prefix"
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
