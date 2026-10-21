#!/usr/bin/env bats
# restore-note.bats — scripts/lib/restore-note.sh (W3 P4): the inbox note every restored session
# gets, the launch-argument prompt only a session with open work and quota gets, and the read-back
# that decides whether a prompt arrived.
#
# HERMETIC: $HOME is fixtured, cc-wake and the paste are stubs, and nothing here launches a session
# or reaches a kitty. The real bin/cc-notify, hooks/mailbox-drain.sh and bin/cc-resume-classify.py
# run against the fixture, because the contract between them is what is under test.
# The library runs under /bin/bash 3.2: launchd runs boot-resume.sh with it.
#
# ERREXIT DISCIPLINE: a non-final `[[ ]]`, `!` or `A && B` is errexit-exempt, so each carries `|| false`.

bats_require_minimum_version 1.5.0

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_MAILBOX_DIR="$HOME/.claude/mailbox" CC_REGISTRY_DIR="$HOME/.claude/cc-registry"
  mkdir -p "$CC_MAILBOX_DIR" "$CC_REGISTRY_DIR"
  # No test here runs ship-land (the string is a fixture's lost background command), but the land
  # gate asks every suite that names it to pin the converge kick off.
  export SHIP_LAND_CONVERGE=off DEPLOY_REPO="$BATS_TEST_TMPDIR/deploy-repo"
  unset KITTY_PID KITTY_LISTEN_ON KITTY_WINDOW_ID ITERM_SESSION_ID CC_PANE_ID CC_RESTORE_NUDGE CC_RESTORE_PASTE_CMD
  # The classifier's reason stores default under the fixture HOME; an exported override must not
  # point it at the real backlog, intent records or reboot prep.
  unset CC_BACKLOG_FILE CC_BACKLOG_BIN CC_SELF_CLOSE_INTENT_DIR CC_REBOOT_PREP_DIR CC_RESTORE_PROJECT_ROOTS
  export CC_RESTORE_TX_CACHE="$BATS_TEST_TMPDIR/tx-cache"
  # The library resolves handoff-fire.sh for the verified paste, so pin what a fire would read off the
  # machine: its load gate and the account tooling (absent paths: those sensors fail open on one).
  export CC_FIRE_CAPACITY_GATE=off CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-claude-accounts" \
    HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json" \
    CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/claude-accounts-heal-"
  export CC_NOTIFY_BIN="$REPO/bin/cc-notify" CC_NOTIFY_WAKE=0 CC_WAKE=off
  export CC_WAKE_BIN="$BATS_TEST_TMPDIR/stub-wake"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$0.log"\nexit 1\n' > "$CC_WAKE_BIN"; chmod +x "$CC_WAKE_BIN"
  LIB="$REPO/scripts/lib/restore-note.sh"
  SID_A="aaaaaaaa-1111-4222-8333-444444444444"
  SID_B="bbbbbbbb-1111-4222-8333-444444444444"
  CUT=1791170000
  LOST="$BATS_TEST_TMPDIR/lost.json"
}

teardown() {
  [ -z "${KPID:-}" ] || kill "$KPID" 2>/dev/null || true
  chmod -R u+rwx "$BATS_TEST_TMPDIR" 2>/dev/null || true   # the R6 test takes a root's read bit
}

rn() { /bin/bash -c '. "$1"; shift; "$@"' _ "$LIB" "$@"; }   # one library function, under bash 3.2

# A transcript for <sid> in the fixture's claude-next store: records given as jq-ready JSON lines,
# each stamped <seconds before the cut>.
tx() { # <sid> <"secs json">...
  local sid="$1" d; d="$HOME/.claude-next/projects/-x"; mkdir -p "$d"; shift
  : > "$d/$sid.jsonl"
  local pair
  for pair in "$@"; do
    jq -c --argjson t "$((CUT - ${pair%% *}))" '. + {timestamp: ($t | todate)}' <<<"${pair#* }" >> "$d/$sid.jsonl"
  done
}
A_TEXT='{"type":"assistant","message":{"content":[{"type":"text","text":"done."}]}}'
use() { jq -cn --arg id "$1" --arg n "$2" --argjson i "$3" '{type:"assistant",message:{content:[{type:"tool_use",id:$id,name:$n,input:$i}]}}'; }
res() { jq -cn --arg id "$1" --arg t "$2" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:$id,content:$t}]}}'; }
classify() { # <sid>... → writes $LOST from the real classifier over the fixture ($CL_ARGS: more flags)
  local s; for s in "$@"; do printf 'next\t%s\t/x\tbr\n' "$s"; done \
    | python3 "$REPO/bin/cc-resume-classify.py" --boot-epoch "$CUT" --wake-lost --lost-json "$LOST" --hb-dir "$BATS_TEST_TMPDIR/hb" \
        ${CL_ARGS:-} 2> "$BATS_TEST_TMPDIR/classify.err"
}
verdicts() { printf '%s\n' "$1" | awk -F'\t' '{ print $NF }' | tr '\n' ' '; }

@test "the library parses and defines its functions under /bin/bash 3.2" {
  run /bin/bash -c '. "$1" && command -v rn_note_text rn_send_note rn_nudge_wanted rn_prompt_text rn_write_prompt rn_confirm rn_fallback' _ "$LIB"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 7 ]
}

@test "one note per sid, in that session's own box, sent --mailbox-only --no-wake" {
  rn rn_send_note "$SID_A" "$(rn rn_note_text restart "$CUT" /nonexistent "$SID_A")"
  rn rn_send_note "$SID_B" "$(rn rn_note_text crash "$CUT" /nonexistent "$SID_B")"
  [ "$(grep -c . "$CC_MAILBOX_DIR/$SID_A.md")" -eq 1 ]
  [ "$(grep -c . "$CC_MAILBOX_DIR/$SID_B.md")" -eq 1 ]
  grep -q ' \[boot-resume\] \[restore\] Kitty was restarted at [0-9][0-9]:[0-9][0-9]\. This session was resumed in full\. Nothing it had running is recorded as lost' "$CC_MAILBOX_DIR/$SID_A.md"
  grep -q 'Kitty was lost in a crash at' "$CC_MAILBOX_DIR/$SID_B.md"
  # The flags, on a stub: --no-wake is what keeps a note from costing a turn.
  export CC_NOTIFY_BIN="$BATS_TEST_TMPDIR/stub-notify"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$0.log"\n' > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"
  rn rn_send_note "$SID_A" "x y"
  [ "$(cat "$CC_NOTIFY_BIN.log")" = "--mailbox-only --no-wake --from boot-resume $SID_A x y" ]
}

@test "under bats an unset cc-notify seam sends nothing rather than reaching the real tool" {
  unset CC_NOTIFY_BIN
  run -127 rn rn_send_note "$SID_A" "x"
  [ ! -e "$CC_MAILBOX_DIR/$SID_A.md" ]
}

# ── the drain, under the kitty-epoch seal (9cf121e54) ─────────────────────────────────────────────
# A note is written BEFORE its session's launch, and on a reboot before the new kitty even exists,
# so it always predates "this kitty". The seal drops mail that predates this kitty from a reused
# pane box. The note lives in the SESSION's box, which the seal never touches. The pane-box line
# beside it is the control: it must be sealed, or the seal was not running and the test proved nothing.
drain_as() { # <sid> <pane> → the SessionStart hook's additionalContext
  printf '{"session_id":"%s","hook_event_name":"SessionStart","source":"resume"}' "$1" \
    | CC_PANE_ID="$2" KITTY_PID="$KPID" bash "$REPO/hooks/mailbox-drain.sh" session-start \
    | jq -r '.hookSpecificOutput.additionalContext // empty'
}
seal_fixture() {
  rn rn_send_note "$SID_A" "$(rn rn_note_text reboot "$CUT" /nonexistent "$SID_A")"
  printf '%s [peer] mail for whoever held window 41 in the earlier kitty\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >> "$CC_MAILBOX_DIR/41.md"
  sleep 2                                    # ps lstart has one-second resolution
  sleep 300 & KPID=$!                        # stands in for the kitty the restore opens afterwards
}

@test "a note written before the new kitty started is drained at SessionStart, while the seal drops the reused pane's old mail" {
  seal_fixture
  run drain_as "$SID_A" 41
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"[restore] The Mac rebooted at"* ]] || { echo "the note did not reach the session: $output"; false; }
  [[ "$output" == *"This session was resumed in full"* ]] || false
  [[ "$output" != *"whoever held window 41"* ]] || { echo "the seal was not active: $output"; false; }
  [ -s "$CC_MAILBOX_DIR/41.sealed" ]
}

@test "CONTROL: with the seal off the pane's old mail IS delivered, so the test above can fail" {
  seal_fixture
  CC_MBX_KITTY_EPOCH=0 run drain_as "$SID_A" 41
  [ "$status" -eq 0 ]
  [[ "$output" == *"whoever held window 41"* ]] || { echo "$output"; false; }
  [[ "$output" == *"[restore] The Mac rebooted at"* ]] || false
}

@test "the note is delivered once: a second SessionStart drains nothing" {
  seal_fixture
  run drain_as "$SID_A" 41
  [[ "$output" == *"[restore]"* ]] || false
  run drain_as "$SID_A" 41
  [[ "$output" != *"[restore]"* ]] || { echo "delivered twice: $output"; false; }
}

# ── what the note says: the real classifier's lost items, rendered ───────────────────────────────
@test "the note names what died: shells, a ship-land, a watcher, a Workflow run id with its resume call, a Monitor, ports, a browser session and URL, teammates" {
  mkdir -p "$BATS_TEST_TMPDIR/hb" "$HOME/.claude-next/teams/t1"
  printf '%s\t100\tlisten\t102\t*:3000\n%s\t100\twatching\t103\t%s\n\037\t\037\tagent-browser\t104\tfb2\n' "$SID_A" "$SID_A" "$SID_A" > "$BATS_TEST_TMPDIR/hb/hb.bg.tsv"
  jq -n --arg s "$SID_A" '{name:"t1",leadSessionId:$s,leadAgentId:"team-lead@t1",members:[{name:"team-lead",agentId:"team-lead@t1",agentType:"team-lead"},{name:"builder-a",agentId:"builder-a@t1",agentType:"general-purpose"}]}' > "$HOME/.claude-next/teams/t1/config.json"
  tx "$SID_A" \
    "900 $(use b0 Bash '{"command":"agent-browser --session fb2 open https://example.test/app"}')" "899 $(res b0 ok)" \
    "800 $(use b1 Bash '{"command":"bats tests/x.bats","run_in_background":true}')" "799 $(res b1 'Command running in background with ID: bzrbwj020')" \
    "700 $(use b2 Bash '{"command":"bash scripts/ship-land.sh","run_in_background":true}')" "699 $(res b2 'Command running in background with ID: bship1')" \
    "600 $(use b3 Bash '{"command":"cc-await-ping --timeout 3300","run_in_background":true}')" "599 $(res b3 'Command running in background with ID: bwatch1')" \
    "500 $(use w1 Workflow '{"script":"x"}')" "499 $(res w1 'Workflow launched in background. Task ID: wtcaytsys Transcript dir: /p/subagents/workflows/wf_d4508a0a-f86')" \
    "450 $(use m1 Monitor '{"command":"x","description":"watch CI","timeout_ms":1800000}')" "449 $(res m1 'Monitor started (task bv3wgaxut, expires in 30m)')" \
    "400 $A_TEXT"
  tx "$SID_B" "400 $A_TEXT"
  run classify "$SID_A" "$SID_B"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | awk -F'\t' '{ print $NF }' | tr '\n' ' ')" = "WAKE-LOST AT-REST " ]
  note="$(rn rn_note_text crash "$CUT" "$LOST" "$SID_A")"
  for want in \
    'These died with the old process: 2 background shells (bzrbwj020: bats tests/x.bats; bship1: bash scripts/ship-land.sh)' \
    'an inbox watcher this session armed (cc-await-ping)' \
    'a Workflow run (wf_d4508a0a-f86: resume it with Workflow({resumeFromRunId: "wf_d4508a0a-f86"}))' \
    'a Monitor (task bv3wgaxut: watch CI)' \
    'a ship-land that was running' \
    'an Agent Teams member (builder-a)' \
    'an agent-browser session (fb2 at https://example.test/app)' \
    'listening ports :3000 (dev servers under this session)' \
    'If any of them still matters, re-run it from disk state; otherwise carry on.' \
    'A ship-land was in flight: check git ls-tree origin/main before landing again.' \
    'Re-arm cc-await-ping unless a /goal is live.' \
    '/limit-recover covers the Teams respawn.'; do
    [[ "$note" == *"$want"* ]] || { echo "missing: $want"; echo "note: $note"; false; }
  done
  [ "$(printf '%s' "$note" | grep -c '')" -eq 1 ]            # one line: an inbox counts messages by line
  # The session that lost nothing is told so, with none of the advice.
  quiet="$(rn rn_note_text crash "$CUT" "$LOST" "$SID_B")"
  [[ "$quiet" == *"Nothing it had running is recorded as lost; carry on." ]] || { echo "$quiet"; false; }
  [[ "$quiet" != *"cc-await-ping"* ]] || false
}

@test "a busy session's note names at most 4 of a kind and counts the rest" {
  jq -n --arg s "$SID_A" '{sessions:{($s):{items:[range(0;7) | {kind:"shell",task_id:"b\(.)",detail:"cmd \(.)"}]}}}' > "$LOST"
  note="$(rn rn_note_text restart "$CUT" "$LOST" "$SID_A")"
  [[ "$note" == *"7 background shells (b0: cmd 0; b1: cmd 1; b2: cmd 2; b3: cmd 3; +3 more)"* ]] || { echo "$note"; false; }
}

# ── who gets a prompt ─────────────────────────────────────────────────────────────────────────────
@test "no prompt for an at-rest row, an unreadable one, or an exhausted account; CC_RESTORE_NUDGE=off turns every prompt off" {
  run rn rn_nudge_wanted INTERRUPTED "$SID_A" "";                  [ "$status" -eq 0 ]
  run rn rn_nudge_wanted WAKE-LOST   "$SID_A" "$SID_B";            [ "$status" -eq 0 ]
  run rn rn_nudge_wanted AT-REST     "$SID_A" "";                  [ "$status" -eq 1 ]
  run rn rn_nudge_wanted UNKNOWN     "$SID_A" "";                  [ "$status" -eq 1 ]
  run rn rn_nudge_wanted RETIRED     "$SID_A" "";                  [ "$status" -eq 1 ]
  run rn rn_nudge_wanted INTERRUPTED "$SID_A" "$SID_B $SID_A";     [ "$status" -eq 1 ]
  run rn rn_nudge_wanted WAKE-LOST   "$SID_A" "$SID_A";            [ "$status" -eq 1 ]
  CC_RESTORE_NUDGE=off run rn rn_nudge_wanted INTERRUPTED "$SID_A" ""
  [ "$status" -eq 1 ]
}

@test "the prompt: it says it is not the operator, carries its nonce, and only an INTERRUPTED row is told to run /limit-recover" {
  jq -n --arg s "$SID_A" '{sessions:{($s):{items:[{kind:"workflow",task_id:"wt1",run_id:"wf_0a1b2c3d-e4f"}]}}}' > "$LOST"
  wake="$(rn rn_prompt_text restart "$CUT" "$LOST" "$SID_A" WAKE-LOST R-0a1b2c3d)"
  cut="$(rn rn_prompt_text restart "$CUT" "$LOST" "$SID_A" INTERRUPTED R-0a1b2c3d)"
  for p in "$wake" "$cut"; do
    [[ "$p" == *"This message comes from the restore tool, not from the operator."* ]] || { echo "$p"; false; }
    [[ "$p" == *"wf_0a1b2c3d-e4f: resume it with Workflow({resumeFromRunId: \"wf_0a1b2c3d-e4f\"})"* ]] || false
    [[ "$p" == *"do not start new work. If nothing was pending, reply with one line saying so. (restore ref R-0a1b2c3d)" ]] || false
  done
  [[ "$wake" != *"/limit-recover now"* ]] || { echo "$wake"; false; }
  [[ "$wake" != *"cut off mid-way"* ]] || false
  [[ "$cut" == *"and your last turn was cut off mid-way. Run /limit-recover now."* ]] || { echo "$cut"; false; }
  f="$(rn rn_write_prompt "$BATS_TEST_TMPDIR/ev/prompts" "$SID_A" "$wake")"
  [ "$f" = "$BATS_TEST_TMPDIR/ev/prompts/$SID_A.txt" ]
  [ "$(cat "$f")" = "$wake" ]
  [[ "$(rn rn_nonce)" =~ ^R-[0-9a-f]{8}$ ]]
}

# ── the read-back ─────────────────────────────────────────────────────────────────────────────────
USER_N='{"type":"user","message":{"content":"[restore] … (restore ref R-feedc0de)"}}'
ASST_OK='{"type":"assistant","message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"nothing pending"}]}}'
@test "confirm: a user record with the nonce AND a real assistant record after it; either alone is not confirmed" {
  run rn rn_confirm "$SID_A" R-feedc0de                       # no transcript at all
  [ "$status" -eq 2 ] || { echo "$status $output"; false; }
  [ "$output" = "user=0 assistant=0" ] || { echo "$status $output"; false; }
  tx "$SID_A" "50 $ASST_OK"                                   # an assistant record BEFORE the prompt is not a reply
  run rn rn_confirm "$SID_A" R-feedc0de
  [ "$status" -eq 2 ] || false
  tx "$SID_A" "50 $ASST_OK" "40 $USER_N"
  run rn rn_confirm "$SID_A" R-feedc0de
  [ "$status" -eq 1 ] || { echo "$status $output"; false; }
  [ "$output" = "user=1 assistant=0" ] || { echo "$status $output"; false; }
  tx "$SID_A" "40 $USER_N" "30 $ASST_OK"
  run rn rn_confirm "$SID_A" R-feedc0de
  [ "$status" -eq 0 ] || { echo "$status $output"; false; }
  [ "$output" = "user=1 assistant=1" ] || { echo "$status $output"; false; }
  run rn rn_confirm "$SID_A" R-00000000                       # another prompt's nonce
  [ "$status" -eq 2 ]
}

@test "confirm: a limit notice or an API error after the prompt is not a turn, and a queued copy of the prompt is not a submit" {
  tx "$SID_A" "40 $USER_N" \
    '30 {"type":"assistant","message":{"model":"<synthetic>","content":[{"type":"text","text":"You have hit your limit"}]}}' \
    '20 {"type":"assistant","isApiErrorMessage":true,"message":{"model":"claude-opus-5-5","content":[]}}'
  run rn rn_confirm "$SID_A" R-feedc0de
  [ "$status" -eq 1 ] || { echo "$status $output"; false; }
  [ "$output" = "user=1 assistant=0" ] || { echo "$status $output"; false; }
  tx "$SID_B" '40 {"type":"queue-operation","operation":"enqueue","content":"(restore ref R-feedc0de)"}' "30 $ASST_OK"
  run rn rn_confirm "$SID_B" R-feedc0de
  [ "$status" -eq 2 ] || { echo "$status $output"; false; }
}

# ── the fallback ──────────────────────────────────────────────────────────────────────────────────
@test "fallback: CC_RESTORE_NUDGE=off or no prompt file sends nothing at all" {
  printf 'p (restore ref R-feedc0de)\n' > "$BATS_TEST_TMPDIR/p.txt"
  CC_RESTORE_NUDGE=off run rn rn_fallback "$SID_A" "$BATS_TEST_TMPDIR/p.txt" R-feedc0de
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"why=CC_RESTORE_NUDGE=off" ]] || { echo "$output"; false; }
  run rn rn_fallback "$SID_A" "$BATS_TEST_TMPDIR/absent.txt" R-feedc0de
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"why=no-prompt-file" ]] || { echo "$output"; false; }
  [ ! -e "$CC_WAKE_BIN.log" ] && [ ! -e "$CC_MAILBOX_DIR/$SID_A.md" ] || false
}

@test "fallback: cc-wake is tried first with the prompt already in the inbox; with no single registry pane the verdict is unconfirmed, never a raw send" {
  # handoff-fire.sh has had the paste-verified entry point since W3 P5, so the paste is now refused
  # one step later: this session has no registry row, so there is no pane to paste into.
  printf 'p (restore ref R-feedc0de)\n' > "$BATS_TEST_TMPDIR/p.txt"
  run rn rn_fallback "$SID_A" "$BATS_TEST_TMPDIR/p.txt" R-feedc0de
  [ "$status" -eq 1 ]
  [ "$output" = "verdict=unconfirmed via=none why=cc-wake-rc-1,no-single-registry-pane" ] || { echo "$output"; false; }
  [ "$(cat "$CC_WAKE_BIN.log")" = "$SID_A --wait 60 --from boot-resume" ]
  grep -q '(restore ref R-feedc0de)' "$CC_MAILBOX_DIR/$SID_A.md"
}

# ── 2026-10-21 restart (docs/plans/REBOOT_RESUME_PERFECTION_2026-10-21.md, wave T1) ───────────────
# 15 of 26 restored sessions got only a note, and two of them held work: the reboot's own lead had
# promised the post-restart checks, and the sevenrooms lead had unread "W2 landed" mail. One session
# that was closing itself was relaunched. These pin who is woken, what the prompt quotes, and who is not.
SID_C="cccccccc-1111-4222-8333-444444444444"
SID_D="dddddddd-1111-4222-8333-444444444444"
say() { jq -cn --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}'; }
PROMISE="This session closes too. After you log in, it reopens with the others, and I'll confirm the Mac is on 15.8.1 and run the leak test."

@test "the classifier's own selftest passes in full" {
  run python3 "$REPO/bin/cc-resume-classify.py" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ cc-resume-classify\ --selftest:\ ([0-9]+)/([0-9]+)\ passed ]] || { echo "$output"; false; }
  [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ] && [ "${BASH_REMATCH[2]}" -ge 72 ] || { echo "$output"; false; }
}

@test "the owner and a promise spoken after the prep are woken and quoted; a promise from before the prep is not; a pending self-close is RETIRED and never prompted" {
  mkdir -p "$HOME/.claude/autonomy"
  printf '%s\n' "$((CUT - 1800))" > "$HOME/.claude/autonomy/reboot-2026-10-21.start"
  tx "$SID_A" "300 $(say "$PROMISE")"
  tx "$SID_B" "400 $A_TEXT"
  tx "$SID_C" "300 $A_TEXT" "240 $(use s1 Bash '{"command":"$HOME/.claude/scripts/handoff-fire.sh self-close --terminal"}')"
  tx "$SID_D" "2400 $(say "$PROMISE")"
  CL_ARGS="--owner $SID_B" run classify "$SID_A" "$SID_B" "$SID_C" "$SID_D"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$BATS_TEST_TMPDIR/classify.err"; false; }
  [ "$(verdicts "$output")" = "WAKE-LOST WAKE-LOST RETIRED AT-REST " ] || { echo "$output"; cat "$BATS_TEST_TMPDIR/classify.err"; false; }
  run rn rn_nudge_wanted WAKE-LOST "$SID_A" "";  [ "$status" -eq 0 ]
  run rn rn_nudge_wanted WAKE-LOST "$SID_B" "";  [ "$status" -eq 0 ]
  run rn rn_nudge_wanted RETIRED "$SID_C" "";    [ "$status" -eq 1 ]
  run rn rn_nudge_wanted AT-REST "$SID_D" "";    [ "$status" -eq 1 ]
  p="$(rn rn_prompt_text reboot "$CUT" "$LOST" "$SID_A" WAKE-LOST R-0a1b2c3d)"
  [[ "$p" == *"Before the restart you said: \"After you log in, it reopens with the others, and I'll confirm the Mac is on 15.8.1 and run the leak test.\" Do that now."* ]] || { echo "$p"; false; }
  [[ "$p" != *"died with it: nothing recorded"* ]] || { echo "$p"; false; }
  [[ "$p" == *"(restore ref R-0a1b2c3d)" ]] || false
  o="$(rn rn_prompt_text reboot "$CUT" "$LOST" "$SID_B" WAKE-LOST R-0a1b2c3d)"
  [[ "$o" == *"You ran the reboot prep for this restart, so its follow-up is yours."* ]] || { echo "$o"; false; }
  # The tier-1 note is about what died, so a reason alone leaves it saying nothing was lost.
  [[ "$(rn rn_note_text reboot "$CUT" "$LOST" "$SID_A")" == *"Nothing it had running is recorded as lost"* ]] || false
}

@test "a blocked row whose until probe passes wakes the session that filed it and is quoted; a failing probe, another session's row and a row without until do not" {
  tx "$SID_A" "400 $A_TEXT"
  tx "$SID_B" "400 $A_TEXT"
  jq -n --arg a "$SID_A" --arg b "$SID_B" '[
    {id:"d4a65e8decc0",status:"blocked",session:$a,title:"leak test after 15.8.1",until:"test -d /"},
    {id:"aaaa00000001",status:"blocked",session:$b,title:"not yet",until:"false"},
    {id:"aaaa00000002",status:"blocked",session:"someone-else",title:"theirs",until:"true"},
    {id:"aaaa00000003",status:"blocked",session:$b,title:"no until"}]' > "$BATS_TEST_TMPDIR/blocked.json"
  CL_ARGS="--backlog-json $BATS_TEST_TMPDIR/blocked.json" run classify "$SID_A" "$SID_B"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$BATS_TEST_TMPDIR/classify.err"; false; }
  [ "$(verdicts "$output")" = "WAKE-LOST AT-REST " ] || { echo "$output"; false; }
  [ "$(jq -r --arg b "$SID_B" '.sessions[$b].items | length' "$LOST")" -eq 0 ]
  p="$(rn rn_prompt_text reboot "$CUT" "$LOST" "$SID_A" WAKE-LOST R-0a1b2c3d)"
  [[ "$p" == *'Backlog row d4a65e8decc0 (leak test after 15.8.1) was blocked until `test -d /` passed, and it passes now: the row is unblocked and yours to finish.'* ]] || { echo "$p"; false; }
}

@test "mail carried from the old pane box by mailbox_migrate wakes the session and is quoted; WAKE-PATH and restore lines, forwarded or not, stay AT-REST" {
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf '%s [cc-await-ping] WAKE-PATH-DOWN: the watcher armed for [31] was TERMINATED\n%s [macapp-extract-55] [@v1;pane=55;sid=e80b61f4;title=x] HANDOFF-PING fire-x: DONE — W2 landed on origin/main at fa03894\n' \
    "$ts" "$ts" > "$CC_MAILBOX_DIR/31.md"
  printf '%s [cc-await-ping] WAKE-PATH-CLASS: verdict=B-BENIGN\n%s [boot-resume] [restore] The Mac rebooted at 13:59.\n' "$ts" "$ts" > "$CC_MAILBOX_DIR/32.md"
  run /bin/bash -c '. "$1"; mailbox_migrate 31 "$2" && mailbox_migrate 32 "$3"' _ "$REPO/hooks/lib/mailbox-pending.sh" "$SID_A" "$SID_B"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The carried lines keep their sender behind the provenance prefix, which is what the classifier strips.
  grep -q '\[forwarded:31\] .* \[cc-await-ping\] WAKE-PATH-DOWN' "$CC_MAILBOX_DIR/$SID_A.md"
  grep -q '\[forwarded:32\] .* \[cc-await-ping\] WAKE-PATH-CLASS' "$CC_MAILBOX_DIR/$SID_B.md"
  tx "$SID_A" "400 $A_TEXT"
  tx "$SID_B" "400 $A_TEXT"
  run classify "$SID_A" "$SID_B"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$BATS_TEST_TMPDIR/classify.err"; false; }
  [ "$(verdicts "$output")" = "WAKE-LOST AT-REST " ] || { echo "$output"; false; }
  [ "$(jq -r --arg a "$SID_A" '.sessions[$a].items[] | select(.kind == "mail") | .count' "$LOST")" = 1 ]
  p="$(rn rn_prompt_text reboot "$CUT" "$LOST" "$SID_A" WAKE-LOST R-0a1b2c3d)"
  [[ "$p" == *'An unread inbox message is waiting for you (newest from macapp-extract-55: "HANDOFF-PING fire-x: DONE — W2 landed on origin/main at fa03894"); read it and act on it.'* ]] || { echo "$p"; false; }
}

@test "the transcript is found by its direct path without a glob, each store root once, and a relaunch on another account by the cached slug" {
  mkdir -p "$HOME/.claude/projects/-Users-x-wt" "$HOME/.claude-secondary/projects" "$HOME/.claude-next"
  ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"
  run rn _rn_roots
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ] || { echo "the symlinked store was listed twice: $output"; false; }
  printf '%s\n%s\n' "$USER_N" "$ASST_OK" | jq -c '. + {timestamp: "2026-01-01T00:00:00Z"}' > "$HOME/.claude/projects/-Users-x-wt/$SID_A.jsonl"
  chmod 311 "$HOME/.claude/projects"            # no listing: a glob over it finds nothing, a direct path still opens
  run rn rn_confirm "$SID_A" R-feedc0de /Users/x/wt
  [ "$status" -eq 0 ] || { echo "$status $output"; false; }
  run rn rn_confirm "$SID_A" R-feedc0de         # no cwd and nothing cached: only the glob is left, and it cannot list
  [ "$status" -eq 2 ] || { echo "$status $output"; false; }
  chmod 755 "$HOME/.claude/projects"
  run rn rn_confirm "$SID_A" R-feedc0de         # the fallback glob finds it and caches the slug
  [ "$status" -eq 0 ] || { echo "$status $output"; false; }
  [ "$(cat "$CC_RESTORE_TX_CACHE/$SID_A")" = "-Users-x-wt" ]
  chmod 311 "$HOME/.claude/projects"
  run rn rn_confirm "$SID_A" R-feedc0de         # the cached slug is a direct path again
  [ "$status" -eq 0 ] || { echo "$status $output"; false; }
  # Relaunched on another account: the same slug under another root, newer, holding the new prompt.
  mkdir -p "$HOME/.claude-secondary/projects/-Users-x-wt"
  printf '%s\n' "$USER_N" | sed 's/R-feedc0de/R-0badc0de/' | jq -c '. + {timestamp: "2026-01-01T01:00:00Z"}' \
    > "$HOME/.claude-secondary/projects/-Users-x-wt/$SID_A.jsonl"
  touch -t 203001010000 "$HOME/.claude-secondary/projects/-Users-x-wt/$SID_A.jsonl"
  run rn rn_confirm "$SID_A" R-0badc0de
  [ "$status" -eq 1 ] || { echo "$status $output"; false; }
  [ "$output" = "user=1 assistant=0" ] || false
}

@test "an unreadable transcript among good rows is one UNKNOWN row: every row comes back and the run exits 0" {
  tx "$SID_A" "400 $A_TEXT"
  tx "$SID_B" "400 $A_TEXT"
  mkdir -p "$HOME/.claude-next/projects/-x/$SID_C.jsonl"     # a directory where the transcript should be
  run classify "$SID_A" "$SID_C" "$SID_B"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$BATS_TEST_TMPDIR/classify.err"; false; }
  [ "$(verdicts "$output")" = "AT-REST UNKNOWN AT-REST " ] || { echo "$output"; false; }
  [[ "$(jq -r --arg c "$SID_C" '.sessions[$c].why' "$LOST")" == unreadable:* ]] || false
}
