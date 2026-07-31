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
  [[ "$output" == *"2 Bash invocations"* ]] || false
  [[ "$output" == *"matched an allow rule :      2"* ]]
}

@test "an unmatched command is ranked as a prompt candidate" {
  mk "sed -n '1,5p' file.txt"
  run python3 "$AUDIT"
  [[ "$output" == *"matched NOTHING       :      1"* ]] || false
  [[ "$output" == *"sed -n"* ]]
}

@test "ASK and DENY are counted separately — they are NOT prompt candidates to allow-list" {
  mk "git push origin main"; mk "dd if=/dev/zero of=/tmp/x"
  run python3 "$AUDIT"
  [[ "$output" == *"hit an ASK rule       :      1"* ]] || false
  [[ "$output" == *"hit a DENY rule       :      1"* ]] || false
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

# ── OBSERVED section — the archive turns the upper bound into a measured set ─────────────────────
# cc-permission-beacon.sh appends every resolved prompt to a durable JSONL before removing it.
# Absence must read as THREE states, not two: a MISSING archive means the archiver has never run
# and this report is blind, while an EMPTY one means nothing actually blocked. Collapsing them is
# the failure that once let "no pending approvals" mean "the hook has never fired once".
arow() { # $1=sid $2=cmd $3=resolved_by $4=waited_s
  mkdir -p "$CC_PERMARCHIVE_DIR"
  python3 -c "
import json,sys,time
print(json.dumps({'session_id':sys.argv[1],'ts':int(time.time())-int(sys.argv[4]),
 'resolved_ts':int(time.time()),'waited_s':int(sys.argv[4]),'resolved_by':sys.argv[3],
 'tool_name':'Bash','tool_input':{'command':sys.argv[2]},'cwd':'/w'}))" "$1" "$2" "$3" "$4" \
    >> "$CC_PERMARCHIVE_DIR/2026-07.jsonl"
}

@test "archive ABSENT is reported as blindness, not as an all-clear" {
  export CC_PERMARCHIVE_DIR="$BATS_TEST_TMPDIR/nope"
  mk "ls -l"
  run python3 "$AUDIT"
  [[ "$output" == *"archive ABSENT"* ]]
  [[ "$output" == *"BLIND"* ]]
  [[ "$output" != *"nothing has actually blocked"* ]]
}

@test "archive PRESENT but empty is reported as a trustworthy all-clear (the other state)" {
  export CC_PERMARCHIVE_DIR="$BATS_TEST_TMPDIR/arch"; mkdir -p "$CC_PERMARCHIVE_DIR"
  mk "ls -l"
  run python3 "$AUDIT"
  [[ "$output" == *"EMPTY"* ]]
  [[ "$output" == *"nothing has actually blocked"* ]]
  [[ "$output" != *"BLIND"* ]]
}

@test "observed prompts are counted and split by approved vs denied/abandoned" {
  export CC_PERMARCHIVE_DIR="$BATS_TEST_TMPDIR/arch"
  arow s1 "git push origin main" PostToolUse 12
  arow s2 "git push --force"     Stop        60
  arow s3 "rm -rf /tmp/x"        SessionEnd  5
  mk "ls -l"
  run python3 "$AUDIT"
  [[ "$output" == *"3 resolved prompts across 3 sessions"* ]]
  [[ "$output" == *"approved 1"* ]]
  [[ "$output" == *"denied/abandoned 2"* ]]
  [[ "$output" == *"unclassified 0"* ]]
}

@test "an unrecognised resolved_by is left UNCLASSIFIED, never folded into either bucket" {
  # Silently counting an unknown clearer as an approval would overstate how permissive the
  # classifier is — the exact number this archive exists to inform.
  export CC_PERMARCHIVE_DIR="$BATS_TEST_TMPDIR/arch"
  arow s1 "cmd-a" PostToolUse 1
  arow s2 "cmd-b" unknown     1
  mk "ls -l"
  run python3 "$AUDIT"
  [[ "$output" == *"approved 1"* ]]
  [[ "$output" == *"denied/abandoned 0"* ]]
  [[ "$output" == *"unclassified 1"* ]]
}

@test "commands that ACTUALLY blocked are ranked, and outrank the inferred candidates" {
  export CC_PERMARCHIVE_DIR="$BATS_TEST_TMPDIR/arch"
  for _ in 1 2 3; do arow sx "git push origin main" Stop 30; done
  arow sy "dd if=/dev/zero" Stop 1
  mk "ls -l"
  run python3 "$AUDIT"
  [[ "$output" == *"commands that ACTUALLY blocked"* ]]
  echo "$output" | sed -n '/ACTUALLY blocked/,$p' > "$BATS_TEST_TMPDIR/obs.txt"
  run grep -qE '^\s+3\s+git push' "$BATS_TEST_TMPDIR/obs.txt"
  [ "$status" -eq 0 ]
}

@test "the longest block is surfaced in hours — a 17.7h hang must be one glance away" {
  export CC_PERMARCHIVE_DIR="$BATS_TEST_TMPDIR/arch"
  arow s1 "git push --force" Stop 63720
  mk "ls -l"
  run python3 "$AUDIT"
  [[ "$output" == *"longest 17.7h"* ]]
}

@test "a torn/invalid archive line is dropped, never guessed at or fatal" {
  export CC_PERMARCHIVE_DIR="$BATS_TEST_TMPDIR/arch"
  arow s1 "good-cmd" PostToolUse 1
  printf '{"session_id":"torn","tool_inp\n' >> "$CC_PERMARCHIVE_DIR/2026-07.jsonl"
  mk "ls -l"
  run python3 "$AUDIT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 resolved prompts"* ]]
}

@test "a truncated row still contributes via its summary rather than vanishing" {
  export CC_PERMARCHIVE_DIR="$BATS_TEST_TMPDIR/arch"; mkdir -p "$CC_PERMARCHIVE_DIR"
  printf '%s\n' '{"session_id":"sbig","ts":1,"resolved_ts":2,"waited_s":1,"resolved_by":"Stop","tool_name":"Bash","cwd":"/w","tool_input_truncated":true,"tool_input_summary":"psql -c DROP TABLE"}' \
    >> "$CC_PERMARCHIVE_DIR/2026-07.jsonl"
  mk "ls -l"
  run python3 "$AUDIT"
  [[ "$output" == *"1 resolved prompts"* ]]
  [[ "$output" == *"psql -c"* ]]
}

@test "the DAYS argument filters the archive as well as the corpus" {
  export CC_PERMARCHIVE_DIR="$BATS_TEST_TMPDIR/arch"; mkdir -p "$CC_PERMARCHIVE_DIR"
  arow s-new "recent-cmd" Stop 1
  printf '%s\n' '{"session_id":"s-old","ts":100,"resolved_ts":100,"waited_s":0,"resolved_by":"Stop","tool_name":"Bash","tool_input":{"command":"ancient-cmd"},"cwd":"/w"}' \
    >> "$CC_PERMARCHIVE_DIR/2026-07.jsonl"
  mk "ls -l"
  run python3 "$AUDIT" 1
  [[ "$output" == *"1 resolved prompts"* ]]
  [[ "$output" != *ancient-cmd* ]]
}

@test "the docstring no longer claims no history exists — it is now produced" {
  run grep -c 'so no history exists' "$AUDIT"
  [ "$output" = "0" ]
}
