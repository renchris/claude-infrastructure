#!/usr/bin/env bats
# cc-permission-audit — ranks the Bash commands most likely to be raising permission prompts,
# by matching the transcript corpus against the live settings.json allow/deny/ask rules.
#
# It reports an UPPER BOUND, not the true prompt set: auto mode's classifier approves much of what
# matches no literal rule, and the beacon rm -f's each pending record once answered, so no history
# of ACTUAL prompts exists. These tests pin the arithmetic and the honesty of that framing.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/projects/proj"
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  AUDIT="$REPO/bin/cc-permission-audit"
  [ -x "$AUDIT" ] || skip "cc-permission-audit not executable"
  cat > "$HOME/.claude/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(git status:*)","Bash(ls:*)"],
 "deny":["Bash(dd:*)"],"ask":["Bash(git push:*)"],"defaultMode":"auto"}}
JSON
}

mk() { # $1=command -> one transcript line carrying a Bash tool_use
  python3 -c "
import json,sys
print(json.dumps({'type':'assistant','message':{'content':[
 {'type':'tool_use','name':'Bash','input':{'command':sys.argv[1]}}]}}))" "$1" \
    >> "$HOME/.claude/projects/proj/t.jsonl"
}

@test "counts an allow-matching command as matched, not as a prompt candidate" {
  mk "git status --short"; mk "ls -la /tmp"
  run python3 "$AUDIT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 Bash invocations"* ]]
  [[ "$output" == *"matched an allow rule :      2"* ]]
}

@test "an unmatched command is ranked as a prompt candidate" {
  mk "sed -n '1,5p' file.txt"
  run python3 "$AUDIT"
  [[ "$output" == *"matched NOTHING       :      1"* ]]
  [[ "$output" == *"sed -n"* ]]
}

@test "ASK and DENY are counted separately — they are NOT prompt candidates to allow-list" {
  mk "git push origin main"; mk "dd if=/dev/zero of=/tmp/x"
  run python3 "$AUDIT"
  [[ "$output" == *"hit an ASK rule       :      1"* ]]
  [[ "$output" == *"hit a DENY rule       :      1"* ]]
  # Neither may appear in the allow-list recommendations — recommending a DENY'd or gated
  # command would be the one way this tool could do real harm.
  # Write the slice to a FILE rather than holding it in a var consumed inside `bash -c`:
  # ShellCheck cannot see through the quoted string and flags the var unused (SC2034), and
  # suppressing that would blind the gate to a genuine typo on this exact assertion.
  # (Capitalised deliberately — a comment word-starting with the lowercase tool name parses as a
  # malformed DIRECTIVE and aborts analysis of the whole file: SC1073/SC1072.)
  # Slice must STOP before the "ASK rules actually exercised" section, which legitimately lists
  # `git push` — a greedy /,$p/ swept it in and made this assertion fail against correct output.
  echo "$output" | sed -n '/TOP 25 PROMPT CANDIDATES/,/ASK rules actually exercised/p' \
    > "$BATS_TEST_TMPDIR/cands.txt"
  run grep -q 'dd if' "$BATS_TEST_TMPDIR/cands.txt"
  [ "$status" -ne 0 ]
  run grep -q 'git push' "$BATS_TEST_TMPDIR/cands.txt"
  [ "$status" -ne 0 ]
}

@test "leading env assignments are stripped before matching — they are not the decided verb" {
  mk "FOO=1 BAR=2 git status"
  run python3 "$AUDIT"
  [[ "$output" == *"matched an allow rule :      1"* ]]
}

@test "the report states its own upper-bound limitation" {
  mk "ls -l"
  run python3 "$AUDIT"
  [[ "$output" == *"upper bound"* ]]
}

@test "an empty corpus reports no data rather than dividing by zero" {
  run python3 "$AUDIT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no data"* ]]
}
