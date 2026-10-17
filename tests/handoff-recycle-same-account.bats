#!/usr/bin/env bats
# handoff-fire.sh --recycle --same-account — the SECOND evidence class of the remote in-place form
# (cc-lr upgrade, 2026-09-22), plus the resume-mode prompt-trailer defect (defect 6 of that brief).
#
# THE NEED. Moving 14 idle sessions onto a new binary+model in place (same pane, same uuid, same
# account) took ~5 h and 6 operator scripts on 2026-09-22, because the only remote recycle this file
# admitted was the TRANSPLANT class: a pane that is not the caller's may be recycled only when its
# session MOVED and a tombstone proves it. An upgrade moves nothing, so there is no tombstone, and
# faking one would forge the very evidence that class stands on. The same-account class replaces it
# with facts that are true of an upgrade and false of every unsafe case: the row binds pane→session,
# the row's process is alive on the pane's tty, the relaunch account IS the row's account (one live
# copy, never two), no tombstone, not a teammate, and the transcript AT REST (a /exit into a turn in
# flight kills that turn).
#
# Technique mirrors tests/handoff-recycle-remote-resume.bats: PATH shims, --dry-run so every gate
# runs and nothing is typed, the whole script invoked. The at-rest oracle is also extracted and
# driven directly, because its fixtures are transcript shapes, not control flow.
#
# RED-PROOFS. Cases marked [RED] fail against the pre-change subject (git stash the script and
# re-run): the admission case because --same-account was an unknown flag, the trailer case because
# the resume-mode recycle died on "prompt file not found". The REFUSED cases are the negatives that
# make the admission meaningful — each names the one fact its fixture falsifies.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off              # hermeticity: the launcher path reaches capacity-admit.sh
  export CC_FIRE_HEADROOM_GATE=off
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  export CC_TERM=iterm2
  unset ITERM_SESSION_ID CLAUDE_CODE_SESSION_ID

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep-stamp.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  cat > "$SHIM/osascript" <<'SH'
#!/usr/bin/env bash
uuid=""
while [ $# -gt 0 ]; do
  case "$1" in
    -e) shift 2 2>/dev/null || shift ;;
    -)  shift ;;
    *)  uuid="$1"; shift ;;
  esac
done
[ -n "$uuid" ] && printf '%s' "TTY-$uuid"
exit 0
SH
  cat > "$SHIM/git" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  # ps: `-o tty=` answers PS_TTY_OUT, `-o args=` answers PS_ARGS_OUT (the row pid's argv — the
  # teammate check reads it); `-o ppid=` answers nothing so the ancestry walk stops after one hop.
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
want=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) case "${2:-}" in tty=) want=tty ;; args=) want=args ;; comm=) want=comm ;; esac; shift 2 ;;
    *) shift ;;
  esac
done
[ "$want" = tty ] && [ -n "${PS_TTY_OUT:-}" ] && printf '%s\n' "$PS_TTY_OUT"
[ "$want" = args ] && [ -n "${PS_ARGS_OUT:-}" ] && printf '%s\n' "$PS_ARGS_OUT"
exit 0
SH
  chmod +x "$SHIM/osascript" "$SHIM/git" "$SHIM/ps"
  export PATH="$SHIM:$PATH"

  SRC_PANE="11110000-2222-3333-4444-555566667777"
  SESS="7b3f9c10-0000-4000-8000-abcdefabcdef"
  SRC_CFG="$BATS_TEST_TMPDIR/.claude-source"          # a real account dir is ~/.<account>
  OTHER_CFG="$BATS_TEST_TMPDIR/.claude-other"
  SLUG="-Users-x-Development-thing"
  mkdir -p "$SRC_CFG/projects/$SLUG" "$OTHER_CFG/projects/$SLUG"
  export CC_PROJECTS_DIRS="$SRC_CFG/projects $OTHER_CFG/projects"
  TX="$SRC_CFG/projects/$SLUG/$SESS.jsonl"
  LAUNCHER="$BATS_TEST_TMPDIR/upgrade/launch.sh"; mkdir -p "$(dirname "$LAUNCHER")"
  printf '#!/bin/bash\nexec /bin/echo resume\n' > "$LAUNCHER"; chmod +x "$LAUNCHER"
  CWD_DIR="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD_DIR"
  export PS_TTY_OUT="TTY-$SRC_PANE"
  export PS_ARGS_OUT="/x/.claude-260/node_modules/.bin/claude --permission-mode auto --model claude-opus-5 --effort high"
}

rec() { printf '%s\n' "$1" >> "$TX"; }
at_rest_tx() {
  : > "$TX"
  rec '{"type":"user","message":{"role":"user","content":"do the thing"},"timestamp":"2026-09-22T10:00:00Z"}'
  rec '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use"}]},"timestamp":"2026-09-22T10:00:01Z"}'
  rec '{"type":"user","message":{"role":"user","content":[{"type":"tool_result"}]},"timestamp":"2026-09-22T10:00:02Z"}'
  rec '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"done"}]},"timestamp":"2026-09-22T10:00:03Z"}'
}
row() { # $1 = account the row records (default: the source account)
  printf '{"paneUUID":"%s","name":"x-%s","cwd":"%s","account":"%s","pid":%d,"session_id":"%s","surface":"pane"}\n' \
    "$SRC_PANE" "$SRC_PANE" "$CWD_DIR" "${1:-claude-source}" "$$" "$SESS" > "$CC_REGISTRY_DIR/$SRC_PANE.json"
}
recycle_sa() {
  run bash "$HF" --recycle --dry-run --same-account --source-pane "$SRC_PANE" --source-session "$SESS" \
      --resume-launcher "$LAUNCHER" --resume-cfg "$SRC_CFG" "$@"
}
load_rest() {
  FN="$BATS_TEST_TMPDIR/rest.sh"
  awk '/^hf_transcript_at_rest\(\) \{/,/^\}/' "$HF" > "$FN"
  [ -s "$FN" ] || { echo "hf_transcript_at_rest not found in $HF"; false; }
  # shellcheck disable=SC1090
  . "$FN"
}

# ── ADMISSION ─────────────────────────────────────────────────────────────────────────────────────

@test "[RED] all same-account facts hold: the remote relaunch is ADMITTED on the row's own account" {
  at_rest_tx; row
  recycle_sa
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"remote in-place SAME-ACCOUNT relaunch: pane $SRC_PANE is PROVEN to hold session ${SESS:0:8}"* ]] || { echo "$output"; false; }
  [[ "$output" == *"SAME ACCOUNT .claude-source; no tombstone"* ]] || { echo "dry run hides the class: $output"; false; }
  [[ "$output" == *"bash $LAUNCHER"* ]] || { echo "the relaunch is not the launcher: $output"; false; }
}

# ── REFUSALS — each falsifies exactly one fact ───────────────────────────────────────────────────

@test "REFUSED: the relaunch account is not the row's account (a second live copy)" {
  at_rest_tx; row
  run bash "$HF" --recycle --dry-run --same-account --source-pane "$SRC_PANE" --source-session "$SESS" \
      --resume-launcher "$LAUNCHER" --resume-cfg "$OTHER_CFG"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"SECOND live copy"* ]] || { echo "$output"; false; }
}

@test "REFUSED: a turn is in flight (last main-thread record is a tool_use)" {
  at_rest_tx; row
  rec '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use"}]},"timestamp":"2026-09-22T10:00:09Z"}'
  recycle_sa
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"is not at rest (rc 1"* ]] || { echo "$output"; false; }
}

@test "REFUSED: a user prompt the model has not answered yet is a turn in flight" {
  at_rest_tx; row
  rec '{"type":"user","message":{"role":"user","content":"next thing"},"timestamp":"2026-09-22T10:00:09Z"}'
  recycle_sa
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"is not at rest (rc 1"* ]] || { echo "$output"; false; }
}

@test "REFUSED: the session carries a transplant tombstone (a husk takes the other class)" {
  at_rest_tx; row
  printf '{"handed_off_to":"%s"}\n' "$OTHER_CFG" > "$SRC_CFG/projects/$SLUG/$SESS.HANDOFF.json"
  recycle_sa
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"carries a transplant tombstone"* ]] || { echo "$output"; false; }
}

@test "REFUSED: the row's process is a TEAMMATE" {
  at_rest_tx; row
  export PS_ARGS_OUT="/x/claude.exe --agent-id w@session-abc --agent-name w --parent-session-id $SESS"
  recycle_sa
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"is a TEAMMATE"* ]] || { echo "$output"; false; }
}

# ── THE TEAM PROCEDURE (2026-09-23): a teammate is relaunched only as ITSELF ────────────────────
TM_ID="w@session-7b3f9c10"
teammate_argv() { export PS_ARGS_OUT="/x/claude.exe --agent-id $TM_ID --agent-name w --team-name session-7b3f9c10 --parent-session-id $SESS --model claude-opus-5"; }

@test "[RED] a TEAMMATE is ADMITTED when --team-member-id is its own id and the launcher carries it" {
  at_rest_tx; row; teammate_argv
  printf '#!/bin/bash\nexec /bin/echo resume --extra-args --agent-id\\ %s\\ --agent-name\\ w\n' "$TM_ID" > "$LAUNCHER"
  recycle_sa --team-member-id "$TM_ID"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"TEAMMATE $TM_ID admitted by the team procedure"* ]] || { echo "$output"; false; }
}

@test "REFUSED: --team-member-id names a DIFFERENT member than the pid carries" {
  at_rest_tx; row; teammate_argv
  printf '#!/bin/bash\nexec /bin/echo resume --agent-id\\ other@session-7b3f9c10\n' > "$LAUNCHER"
  recycle_sa --team-member-id "other@session-7b3f9c10"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"re-join as a DIFFERENT member"* ]] || { echo "$output"; false; }
}

@test "REFUSED: the teammate's launcher does not carry its --agent-id (it would come back outside the team)" {
  at_rest_tx; row; teammate_argv
  recycle_sa --team-member-id "$TM_ID"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"does not carry that --agent-id"* ]] || { echo "$output"; false; }
}

# ── MEMBERSHIP AS THE CLOSER SAW IT (teammate resurrection 2026-10-16, REPORT.md § 4.2 step 9) ──
# The resume debt opened before the /exit records whether the closed process was a team member, read
# off its argv, so the relaunch that settles the debt never guesses from a transcript head. --dry-run
# stops before the debt, and a full recycle needs a real tty holding a real claude, so the evidence
# function and the debt-open stanza of recycle_fire_commit are extracted from the subject and run in
# order, in one shell, as the recycle runs them.
load_sa_debt() {
  FN="$BATS_TEST_TMPDIR/sa-debt.sh"
  {
    awk '/^hf_transcript_at_rest\(\) \{/,/^\}/' "$HF"
    awk '/^hf_same_account_evidence\(\) \{/,/^\}/' "$HF"
    echo 'sa_debt_open() {'
    awk '/^  rcy_debt_sid="\$rcy_old_sid"$/ { on = 1 } on { print } on && /^  fi$/ { exit }' "$HF"
    echo '}'
  } > "$FN"
  grep -q '_hf_resume_debt open' "$FN" || { echo "the debt open was not extracted from $HF"; false; }
  bash -n "$FN"
  # shellcheck disable=SC1090
  . "$FN"
  DEBT_CALLS="$BATS_TEST_TMPDIR/debt.calls"; : > "$DEBT_CALLS"
  _hf_resume_debt() { printf '%s\n' "$*" >> "$DEBT_CALLS"; }
  # shellcheck disable=SC2034  # globals read by the extracted handoff-fire code
  REG_DIR="$CC_REGISTRY_DIR" RESUME_LAUNCHER="$LAUNCHER" RESUME_CFG="$SRC_CFG" RCY_SOURCE_SESSION="$SESS" \
    LAUNCH_DIR="$CWD_DIR" SID="$SRC_PANE" rcy_old_sid="$SESS" HF_SA_MEMBER="" HF_TEAM_MEMBER_ID=""
}

@test "[RED] the debt open carries --member yes for a teammate admitted with --team-member-id" {
  at_rest_tx; row; teammate_argv
  printf '#!/bin/bash\nexec /bin/echo resume --extra-args --agent-id\\ %s\\ --agent-name\\ w\n' "$TM_ID" > "$LAUNCHER"
  load_sa_debt
  # shellcheck disable=SC2034  # read by the extracted hf_same_account_evidence
  HF_TEAM_MEMBER_ID="$TM_ID"
  hf_same_account_evidence "$SRC_PANE" "$SESS" "$SRC_CFG" "$$" --recycle
  [ "$HF_SA_MEMBER" = yes ] || { echo "HF_SA_MEMBER='$HF_SA_MEMBER'"; false; }
  sa_debt_open
  grep -q -- "^open --sid $SESS .* --member yes " "$DEBT_CALLS" || { cat "$DEBT_CALLS"; false; }
}

@test "[RED] the debt open carries --member no for a plain remote pid, and nothing for a self-recycle" {
  at_rest_tx; row
  load_sa_debt
  hf_same_account_evidence "$SRC_PANE" "$SESS" "$SRC_CFG" "$$" --recycle
  [ "$HF_SA_MEMBER" = no ] || { echo "HF_SA_MEMBER='$HF_SA_MEMBER'"; false; }
  sa_debt_open
  grep -q -- "^open --sid $SESS .* --member no " "$DEBT_CALLS" || { cat "$DEBT_CALLS"; false; }
  # A self-recycle never runs the evidence function, so it states no membership at all.
  : > "$DEBT_CALLS"; HF_SA_MEMBER=""
  sa_debt_open
  grep -q '^open ' "$DEBT_CALLS" || { echo "no debt opened"; false; }
  ! grep -q -- '--member' "$DEBT_CALLS" || { cat "$DEBT_CALLS"; false; }
}

@test "REFUSED: no transcript on the account (nothing to resume)" {
  row
  recycle_sa
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"has no transcript under"* ]] || { echo "$output"; false; }
}

@test "REFUSED: the row names a different session (binding still decides first)" {
  at_rest_tx
  printf '{"paneUUID":"%s","cwd":"%s","account":"claude-source","pid":%d,"session_id":"%s"}\n' \
    "$SRC_PANE" "$CWD_DIR" "$$" "00000000-0000-4000-8000-000000000000" > "$CC_REGISTRY_DIR/$SRC_PANE.json"
  recycle_sa
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"does NOT hold session ${SESS:0:8}"* ]] || { echo "$output"; false; }
}

@test "REFUSED: --same-account and --transplanted-source together (exclusive classes)" {
  at_rest_tx; row
  recycle_sa --transplanted-source
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"are exclusive"* ]] || { echo "$output"; false; }
}

@test "REFUSED: --same-account without --source-pane is not the remote form" {
  at_rest_tx; row
  run bash "$HF" --recycle --dry-run --same-account --resume-launcher "$LAUNCHER" --resume-cfg "$SRC_CFG"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"is the REMOTE form"* ]] || { echo "$output"; false; }
}

@test "FENCE: with neither class flag the remote form still refuses (the old gate is intact)" {
  at_rest_tx; row
  run bash "$HF" --recycle --dry-run --source-pane "$SRC_PANE" --source-session "$SESS" \
      --resume-launcher "$LAUNCHER" --resume-cfg "$SRC_CFG"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"admissible ONLY with --transplanted-source"* ]] || { echo "$output"; false; }
}

# ── THE AT-REST ORACLE, driven directly ───────────────────────────────────────────────────────────

@test "at-rest oracle: end_turn is rest; sidechain records after it do not wake it" {
  load_rest; at_rest_tx
  rec '{"type":"assistant","isSidechain":true,"message":{"stop_reason":"tool_use"},"timestamp":"2026-09-22T10:00:05Z"}'
  rec '{"type":"system","subtype":"stop_hook_summary","timestamp":"2026-09-22T10:00:06Z"}'
  run hf_transcript_at_rest "$TX"
  [ "$status" -eq 0 ] || { echo "rc=$status"; false; }
}

@test "at-rest oracle: a trailing API-error record (captured auth cliff, stop_sequence) is REST, in both mirrors" {
  # W5 rig: every voluntary auth hop was HELD:mid-turn, because Claude Code writes the auth cliff as
  # isApiErrorMessage with stop_reason "stop_sequence" — which the oracle read as a turn in flight.
  load_rest
  local fx="$BATS_TEST_DIRNAME/fixtures/lr-recon/jsonl/authentication-failed.jsonl"
  local lru="$BATS_TEST_TMPDIR/lru.sh"
  awk '/^lru_at_rest\(\) \{/,/^\}/' "$BATS_TEST_DIRNAME/../scripts/limit-recover/lr-upgrade.sh" > "$lru"
  [ -s "$lru" ] || { echo "lru_at_rest not found"; false; }
  # shellcheck disable=SC1090
  . "$lru"
  : > "$TX"; tail -n 1 "$fx" >> "$TX"
  run hf_transcript_at_rest "$TX"
  [ "$status" -eq 0 ] || { echo "hf rc=$status"; false; }
  run lru_at_rest "$TX"
  [ "$status" -eq 0 ] || { echo "lru rc=$status"; false; }
  # CONTROL: the same stop_reason WITHOUT the api-error flag stays in flight
  rec '{"type":"assistant","message":{"role":"assistant","stop_reason":"stop_sequence"},"timestamp":"2026-09-22T10:00:06Z"}'
  run hf_transcript_at_rest "$TX"
  [ "$status" -eq 1 ] || { echo "hf control rc=$status"; false; }
  run lru_at_rest "$TX"
  [ "$status" -eq 1 ] || { echo "lru control rc=$status"; false; }
}

@test "at-rest oracle: a tool_result awaiting its next assistant record is in flight (rc 1)" {
  load_rest; at_rest_tx
  rec '{"type":"user","message":{"content":[{"type":"tool_result"}]},"timestamp":"2026-09-22T10:00:05Z"}'
  run hf_transcript_at_rest "$TX"
  [ "$status" -eq 1 ]
}

@test "at-rest oracle: a harness <task-notification> left unanswered past the window is REST" {
  load_rest; at_rest_tx
  rec '{"type":"user","message":{"role":"user","content":"<task-notification>\n<status>stopped</status>\n</task-notification>"},"timestamp":"2026-09-22T10:00:05Z"}'
  run hf_transcript_at_rest "$TX"
  [ "$status" -eq 0 ] || { echo "rc=$status"; false; }
}

@test "at-rest oracle: a FRESH notification, or a stale typed prompt, is still in flight (rc 1)" {
  load_rest; at_rest_tx
  rec "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"<task-notification>x</task-notification>\"},\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
  run hf_transcript_at_rest "$TX"
  [ "$status" -eq 1 ] || { echo "fresh notification read as rest: rc=$status"; false; }
  at_rest_tx
  rec '{"type":"user","message":{"role":"user","content":"please continue"},"timestamp":"2026-09-22T10:00:05Z"}'
  run hf_transcript_at_rest "$TX"
  [ "$status" -eq 1 ] || { echo "a typed prompt read as rest: rc=$status"; false; }
}

@test "at-rest oracle: a missing or empty transcript is UNREADABLE (rc 2), never rest" {
  load_rest
  run hf_transcript_at_rest "$BATS_TEST_TMPDIR/absent.jsonl"
  [ "$status" -eq 2 ]
  : > "$TX"
  run hf_transcript_at_rest "$TX"
  [ "$status" -eq 2 ]
}

# ── A LOCAL COMMAND IS NOT A TURN (lr-stranded-husk, 2026-10-10, session 186452ed) ───────────────
# Claude Code writes a local command (/exit, /model, /effort, /login) as three main-thread USER
# records: the isMeta <local-command-caveat>, the <command-name> echo and the <local-command-stdout>.
# No turn follows. Read as a trailing user record, the /exit a recycle types counted as a turn in
# flight, so the --husk last read of the stub joined with .handed-off held HELD:busy for good.
# Commands that DO start a turn stay in flight: a custom command writes <command-message> and then
# an isMeta prompt, and /goal writes <command-name>, stdout and an isMeta prompt, with no caveat.
local_cmd() { # $1=command (/exit) $2=stdout text → the caveat-led triple, in the shape 2.1.293 writes
  rec '{"type":"user","isMeta":true,"message":{"role":"user","content":"<local-command-caveat>Caveat: The command below was run directly in Claude Code.</local-command-caveat>"},"timestamp":"2026-09-22T10:00:10Z"}'
  rec "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"<command-name>$1</command-name>\\n            <command-message>${1#/}</command-message>\\n            <command-args></command-args>\"},\"timestamp\":\"2026-09-22T10:00:10Z\"}"
  rec "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"<local-command-stdout>$2</local-command-stdout>\"},\"timestamp\":\"2026-09-22T10:00:10Z\"}"
}
load_both_rest() {
  load_rest
  local lru="$BATS_TEST_TMPDIR/lru.sh"
  awk '/^lru_at_rest\(\) \{/,/^\}/' "$BATS_TEST_DIRNAME/../scripts/limit-recover/lr-upgrade.sh" > "$lru"
  [ -s "$lru" ] || { echo "lru_at_rest not found"; false; }
  # shellcheck disable=SC1090
  . "$lru"
}
both_rc() { # $1=expected rc → both mirrors return it on $TX
  run hf_transcript_at_rest "$TX"
  [ "$status" -eq "$1" ] || { echo "hf rc=$status, want $1"; cat "$TX"; return 1; }
  run lru_at_rest "$TX"
  [ "$status" -eq "$1" ] || { echo "lru rc=$status, want $1"; cat "$TX"; return 1; }
}

@test "[RED] at-rest oracle: a local-command triple (/exit) after end_turn or a limit is REST, in both mirrors" {
  load_both_rest
  at_rest_tx; local_cmd /exit "(no content)"; both_rc 0
  # 186452ed: the limit record, then the /exit the recycle typed
  : > "$TX"; cat "$BATS_TEST_DIRNAME/fixtures/lr-recon/jsonl/death-quota-limits.jsonl" >> "$TX"
  local_cmd /exit "(no content)"; both_rc 0
  # two local commands in a row
  at_rest_tx; local_cmd /model "Set model to Opus"; local_cmd /exit "Bye!"; both_rc 0
}

@test "at-rest oracle: the record before a local-command triple decides, and a command that starts a turn is in flight" {
  load_both_rest
  # a turn in flight before the triple stays in flight
  at_rest_tx
  rec '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use"}]},"timestamp":"2026-09-22T10:00:05Z"}'
  local_cmd /model "Set model to Opus"; both_rc 1
  # a prompt typed after the triple is a turn
  at_rest_tx; local_cmd /model "Set model to Opus"
  rec '{"type":"user","message":{"role":"user","content":"please continue"},"timestamp":"2026-09-22T10:00:12Z"}'
  both_rc 1
  # a stub holding ONLY the triple proves nothing: rc 1, as before
  : > "$TX"; local_cmd /exit "(no content)"; both_rc 1
  # a custom slash command: the <command-message> echo, then the isMeta prompt that starts its turn
  at_rest_tx
  rec '{"type":"user","message":{"role":"user","content":"<command-message>limit-recover</command-message>\n<command-name>/limit-recover</command-name>"},"timestamp":"2026-09-22T10:00:10Z"}'
  both_rc 1
  rec '{"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"# /limit-recover"}]},"timestamp":"2026-09-22T10:00:10Z"}'
  both_rc 1
  # /goal: stdout with NO caveat, then the isMeta prompt; in flight at every step, and after a local command too
  at_rest_tx
  rec '{"type":"user","message":{"role":"user","content":"<command-name>/goal</command-name>\n<command-message>goal</command-message>\n<command-args>x</command-args>"},"timestamp":"2026-09-22T10:00:10Z"}'
  rec '{"type":"user","message":{"role":"user","content":"<local-command-stdout>Goal set: x</local-command-stdout>"},"timestamp":"2026-09-22T10:00:10Z"}'
  both_rc 1
  rec '{"type":"user","isMeta":true,"message":{"role":"user","content":"A session-scoped Stop hook is now active"},"timestamp":"2026-09-22T10:00:10Z"}'
  both_rc 1
  at_rest_tx; local_cmd /effort "Set effort to high"
  rec '{"type":"user","message":{"role":"user","content":"<command-name>/goal</command-name>\n<command-message>goal</command-message>\n<command-args>x</command-args>"},"timestamp":"2026-09-22T10:00:11Z"}'
  rec '{"type":"user","message":{"role":"user","content":"<local-command-stdout>Goal set: x</local-command-stdout>"},"timestamp":"2026-09-22T10:00:11Z"}'
  both_rc 1
  # a caveat-led command with no stdout (/context) is unchanged: rc 1
  at_rest_tx
  rec '{"type":"user","isMeta":true,"message":{"role":"user","content":"<local-command-caveat>Caveat</local-command-caveat>"},"timestamp":"2026-09-22T10:00:10Z"}'
  rec '{"type":"user","message":{"role":"user","content":"<command-name>/context</command-name>"},"timestamp":"2026-09-22T10:00:10Z"}'
  both_rc 1
}

# ── DEFECT 6 — a resume-mode recycle never needs --no-self-retire ─────────────────────────────────

@test "[RED] a fired peer's SELF resume-mode recycle does not die on the prompt trailer" {
  # The fired-peer stamp that made hf_recycle_inherits_peer true: valid, open, at the pane's cwd.
  jq -n --arg p "$SRC_PANE" --arg c "$(cd "$CWD_DIR" && pwd -P)" \
    '{paneUUID:$p, cwd:$c, firedBy:"ORIGIN-77", firedAt:"2026-09-22T00:00:00Z", selfRetire:true,
      schema:2, originClass:"fired-peer", originator:"ORIGIN-77", notifyBack:"ORIGIN-77",
      marker:"HANDOFF-ENGAGE-1-2-3", closedAt:null, succession:null}' > "$CC_FIRED_DIR/$SRC_PANE.json"
  # A transplanted self form, as `cc-lr switch` fires it — the shape that carried the trailer.
  TCFG="$OTHER_CFG"; LOCKDIR="$HOME/.reso/limit-recover/locks"; mkdir -p "$LOCKDIR"
  printf '{"handed_off_to":"%s","lock":"%s"}\n' "$TCFG" "$LOCKDIR/$SESS.lock" > "$SRC_CFG/projects/$SLUG/$SESS.HANDOFF.json"
  printf '{"sid":"%s"}\n' "$SESS" > "$LOCKDIR/$SESS.lock"
  row
  run bash -c 'cd "$1" && shift && exec env ITERM_SESSION_ID="w0t0p0:$1" CLAUDE_CODE_SESSION_ID="$2" CLAUDE_CONFIG_DIR="$3" \
      bash "$4" --recycle --dry-run --transplanted-source --transplant-cause voluntary \
      --resume-launcher "$5" --resume-cfg "$6"' _ "$CWD_DIR" "$SRC_PANE" "$SESS" "$SRC_CFG" "$HF" "$LAUNCHER" "$TCFG"
  [[ "$output" != *"prompt trailer: prompt file not found"* ]] || { echo "defect 6 is back: $output"; false; }
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
