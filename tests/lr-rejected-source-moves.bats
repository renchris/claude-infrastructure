#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016,SC2034,SC2086  # each @test is its own subshell; per-test exports are the intent
# A session on a SERVER-REJECTED account moves, whatever it is "busy" with.
#
# OPERATOR RULING 2026-10-13: "we need to fix and improve our limit recover skill to recover all
# panes." A session on a rejected account cannot take a turn until the reset, so nothing a
# background job produces can be used there; staying put protects nothing. Holds for a healthy
# source are unchanged, and so are the holds for an Agent Team lead or member and for a ship-land.
#
# THE INCIDENT, rotating next3 (weekly limit rejected on the wire) to next2, 2026-10-13:
#   A  pane 16 (4fe9935f, claude pid 80475): hold:background-job / wait:background-job. The job is
#      a `zprint -d` that never ends, so --until-idle never released it.
#      pane 12 (c56c729c, claude pid 78979): the plan said move, /exit raised the background-work
#      dialog, the watcher answered Stay: `HELD:bg-work`. Its two jobs (a mailbox watcher and an
#      `until grep …; do sleep 120` loop) run in Bash-tool shells whose argv has no
#      `shell-snapshots`, so every job reader called them "none": the plan could not see them and
#      stop-if-watcher saw no watcher (recycle log: "its background jobs are not watcher-only
#      (none shipland=no pids=-)").
#   (The same day's `--phase unconfirm --source-lstart` refusal is tests/lr-transplant-live-lstart.bats,
#   and the restore budget that never admitted pane 113 is lr_recon/tests/test_restore_budget_bound.py.)
#
# EVERY FIXTURE IS THE REAL ARTIFACT: tests/fixtures/lr-rejected-source-moves/pane{12,16}.ps.txt are
# the two panes' process rows as `TZ=UTC LC_ALL=C ps -axww -o pid=,ppid=,lstart=,args=` printed them
# (home path neutralised); the dialog is the view-off menu pane 12's watcher met ("the menu offers
# no keep-work option"), in the capture tests/handoff-recycle-bgwork-dialog.bats uses; the account
# fact is the one the ledger held for next3 (tests/fixtures/lr-dead-source-holds/).
#
# Hermetic: the registry, every store, `ps` and the terminal are fixtures; a holder is a real child
# process; nothing here can reach a live pane.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export CC_ADMIT_GATE=off HANDOFF_ACCOUNT_SWEEP=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FX="$REPO/tests/fixtures/lr-rejected-source-moves"
  FACT="$REPO/tests/fixtures/lr-dead-source-holds/next3.7d.fact.json"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  LRT="$REPO/scripts/limit-recover/lr-transplant.sh"
  HF="$REPO/scripts/handoff-fire.sh"
  CCLR="$REPO/bin/cc-lr"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/penv"; mkdir -p "$LR_MOVE_ENV_DIR"
  export LRU_STATE="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE/recon/facts" "$LRU_STATE/locks"
  export LR_STATE_DIR="$LRU_STATE"
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$LRU_REG_DIR"
  export CC_REGISTRY_DIR="$LRU_REG_DIR"
  export LRU_CFG_ROOT="$HOME"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export HF_PS_SNAPSHOT="$LRU_PS_SNAPSHOT"
  export LRU_COMPOSER=off LRU_SELF_SID=""
  export LRU_LR_LIB="$BATS_TEST_TMPDIR/absent-lr-lib.sh"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export LRU_NOTIFY_BIN="$STUBS/cc-notify"
  export CC_NOTIFY_BIN="$STUBS/cc-notify"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/notify.log"\nexit 0\n' "$BATS_TEST_TMPDIR" > "$STUBS/cc-notify"; chmod +x "$STUBS/cc-notify"
  export LRU_SA_PROBE="$STUBS/sa-probe"
  printf '#!/bin/bash\necho "live_subagents: 0"\n' > "$LRU_SA_PROBE"; chmod +x "$LRU_SA_PROBE"
  printf '#!/bin/bash\nexit 0\n' > "$STUBS/launchctl"; chmod +x "$STUBS/launchctl"
  printf '#!/bin/bash\nexit 0\n' > "$STUBS/osascript"; chmod +x "$STUBS/osascript"
  export CC_ACCOUNTS_BIN="$STUBS/claude-accounts"
  printf '#!/bin/bash\nprintf "next2 0.9\\nnext3 0.4\\n"\n' > "$CC_ACCOUNTS_BIN"; chmod +x "$CC_ACCOUNTS_BIN"
  export PATH="$STUBS:$PATH"
  export CC_LR_UPGRADE_BIN="$LRU" CC_PANE_ID=999 CC_LR_MOVE_POLL_S=0
  export CC_ACCOUNT_MAP="$REPO/lib/account-map.generated.sh"
  export CC_GOAL_SCAN_DIR="$BATS_TEST_TMPDIR/goal-scan"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/claude-accounts-heal-"
  export CC_HANDOFF_ALARM_DIR="$HOME/.claude/handoff-alarms"
  export CC_PANE_MODAL_LIB="$REPO/hooks/lib/pane-modal.sh"
  export HF_DIR="$REPO/scripts"
  unset CLAUDE_CODE_SESSION_ID ITERM_SESSION_ID KITTY_WINDOW_ID LR_DEAD_SOURCE_RELEASE LR_RECON_ROOT
  BIN="/opt/cc/.claude-293/node_modules/.bin/claude"
  S12=c56c729c-0952-4ff7-9638-cf9aae3f6db4; L12="Sun Oct 11 19:11:30 2026"
  S16=4fe9935f-ca5f-4a48-803c-5e569b08f1b7; L16="Sun Oct 11 12:09:25 2026"
  STORE="$HOME/.claude-tertiary/projects/-x"; mkdir -p "$STORE"
  HOLDER_PIDS=""
}

teardown() {
  local p
  for p in $HOLDER_PIDS; do kill "$p" 2>/dev/null || true; done
}

# pane <12|16> [extra claude argv] → the registry row, the claude row, the pane's REAL job rows and
# a transcript at rest
pane() {
  local n="$1" pid sid l
  case "$n" in 12) pid=78979 sid="$S12" l="$L12" ;; *) pid=80475 sid="$S16" l="$L16" ;; esac
  printf '{"paneUUID":"%s","pid":%s,"session_id":"%s","account":"claude-tertiary","cwd":"%s","lstart":"%s"}\n' \
    "$n" "$pid" "$sid" "$BATS_TEST_TMPDIR" "$l" > "$LRU_REG_DIR/$n.json"
  printf '%s 1 %s %s --model claude-opus-5-5 --effort high --resume %s%s\n' "$pid" "$l" "$BIN" "$sid" "${2:+ $2}" >> "$LRU_PS_SNAPSHOT"
  cat "$FX/pane$n.ps.txt" >> "$LRU_PS_SNAPSHOT"
  printf '%s\n' '{"type":"user","isSidechain":false,"message":{"role":"user","content":"x"}}' \
    '{"type":"assistant","isSidechain":false,"message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"done"}]}}' \
    > "$STORE/$sid.jsonl"
}
# rejected <acct> → the REAL next3.7d fact, re-based: observed 10 minutes ago, resets in 10 hours
rejected() {
  jq -c --arg a "$1" --argjson now "$(date +%s)" '.acct = $a | .observed_at = ($now - 600) | .resets_at = ($now + 36000)' \
    "$FACT" > "$LRU_STATE/recon/facts/$1.7d.json"
}
disp() { printf '%s\n' "$output" | awk -v s="${1:0:8}" '$2 == s { print $3 }'; }
load_fns() {
  local src="$1" f out="$BATS_TEST_TMPDIR/fns.$RANDOM.sh"; shift
  for f in "$@"; do
    awk -v f="$f" '$0 ~ "^" f "\\(\\) \\{" { on = 1 } on { print } on && /^}/ { exit }' "$src" >> "$out"
  done
  # shellcheck disable=SC1090
  . "$out"
}

# ── A1. THE JOB READERS SEE BOTH ARGV SHAPES OF A BASH-TOOL SHELL ──────────────────────────────────

@test "A1 [RED] pane 12's no-snapshot shells are jobs for both job readers (they read 'none')" {
  pane 12
  load_fns "$HF" hf_bg_work_kind
  run hf_bg_work_kind 78979
  [[ "$output" == "work shipland=no pids="* ]] || { echo "hf_bg_work_kind: $output"; false; }
  [[ "$output" == *54057* && "$output" == *95607* ]] || { echo "hf_bg_work_kind: $output"; false; }
  LRU_PROC_LINE="$(sed -n "s/^LRU_PROC_LINE='\(.*\)'\$/\1/p" "$LRU")"
  load_fns "$LRU" lru_bg_kind
  run lru_bg_kind "$(cat "$LRU_PS_SNAPSHOT")" 78979
  [ "$output" = work ] || { echo "lru_bg_kind: $output"; false; }
}

@test "A1b pane 16's snapshot-shaped shells read as before, and a hook's plain bash child is still no job" {
  pane 16
  load_fns "$HF" hf_bg_work_kind
  run hf_bg_work_kind 80475
  [[ "$output" == "work shipland=no pids="* && "$output" == *88781* ]] || { echo "$output"; false; }
  printf '90001 80475 %s /bin/bash /x/hooks/stop-hook.sh\n' "$L16" > "$LRU_PS_SNAPSHOT"
  run hf_bg_work_kind 80475
  [ "$output" = "none shipland=no pids=-" ] || { echo "$output"; false; }
}

# ── A2. THE PLAN: A JOB DOES NOT HOLD A SESSION ON A REJECTED ACCOUNT ──────────────────────────────

@test "A2 [RED] panes 12 and 16 are 'move' on a rejected source, and the plan says their jobs are carried" {
  pane 12; pane 16; rejected next3
  run bash "$CCLR" plan --from next3 --to next2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(disp "$S12")" = move ] || { echo "$output"; false; }
  [ "$(disp "$S16")" = move ] || { echo "$output"; false; }
  [[ "$output" == *"its background jobs end with the exit and are named to the successor"* ]] || { echo "$output"; false; }
  run bash "$CCLR" plan --from next3 --to next2 --until-idle 600
  [ "$(disp "$S16")" = move ] || { echo "--until-idle still waits: $output"; false; }
}

@test "A2b [RED] on a healthy source both are held for their jobs: no fact, another account's fact, a contradicted fact, the kill switch" {
  pane 12; pane 16
  run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S12")" = hold:background-job ] || { echo "pane 12, no fact: $output"; false; }
  [ "$(disp "$S16")" = hold:background-job ] || { echo "pane 16, no fact: $output"; false; }
  run bash "$CCLR" plan --from next3 --to next2 --until-idle 600
  [ "$(disp "$S16")" = wait:background-job ] || { echo "$output"; false; }
  rejected next2
  run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S16")" = hold:background-job ] || { echo "another account's fact released it: $output"; false; }
  rm -f "$LRU_STATE/recon/facts/next2.7d.json"
  rejected next3
  jq -c '.contradicted = true' "$LRU_STATE/recon/facts/next3.7d.json" > "$BATS_TEST_TMPDIR/f.json"
  cp "$BATS_TEST_TMPDIR/f.json" "$LRU_STATE/recon/facts/next3.7d.json"
  run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S16")" = hold:background-job ] || { echo "a contradicted fact released it: $output"; false; }
  rejected next3
  LR_DEAD_SOURCE_RELEASE=off run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S16")" = hold:background-job ] || { echo "the kill switch did not hold: $output"; false; }
}

# ── A3. THE RECYCLE'S OWN GATE (the probe and the last read before /exit) ──────────────────────────

gate() { # <pane> → hf_bg_work_gate over that pane's pid and its at-rest transcript, as a voluntary move
  local pid sid
  case "$1" in 12) pid=78979 sid="$S12" ;; *) pid=80475 sid="$S16" ;; esac
  load_fns "$HF" hf_transcript_at_rest hf_bg_work_kind hf_lr_script hf_tx_account hf_dead_source_notification
  load_fns "$HF" hf_source_dead_for_tx hf_bg_work_gate
  HF_BG_HOLD=""; GRC=0
  hf_bg_work_gate "$pid" 0 "$STORE/$sid.jsonl" "$STORE/$sid.jsonl" > "$BATS_TEST_TMPDIR/gate.out" || GRC=$?
}

@test "A3 [RED] the gate does not hold pane 16's never-ending job on a rejected account, and says why" {
  pane 16; rejected next3
  gate 16
  [ "$GRC" -eq 0 ] || { echo "rc=$GRC hold=$HF_BG_HOLD"; cat "$BATS_TEST_TMPDIR/gate.out"; false; }
  [ -z "$HF_BG_HOLD" ]
  grep -q 'not held: the source account is rejected (next3.7d ' "$BATS_TEST_TMPDIR/gate.out" || { cat "$BATS_TEST_TMPDIR/gate.out"; false; }
}

@test "A3b [RED] the gate still holds it on a healthy source, and holds a ship-land on a rejected one" {
  pane 16
  gate 16
  [ "$GRC/$HF_BG_HOLD" = "3/HELD:bg-work:other" ] || { echo "no fact: rc=$GRC hold=$HF_BG_HOLD"; false; }
  rejected next3
  gate 16
  [ "$GRC" -eq 0 ] || { echo "control: the rejected account did not release (rc=$GRC)"; false; }
  printf '90002 88781 %s /bin/bash /x/scripts/ship-land.sh\n' "$L16" >> "$LRU_PS_SNAPSHOT"
  gate 16
  [ "$GRC/$HF_BG_HOLD" = "3/HELD:bg-work:ship-land" ] || { echo "a land was released: rc=$GRC hold=$HF_BG_HOLD"; false; }
}

# ── A4. THE DIALOG: EXIT AND STOP TASKS ON A REJECTED SOURCE, THE JOBS RECORDED FIRST ──────────────

# The view-off menu, as pane 12's watcher met it: no keep-work option.
dialog() {
  export SCREEN="$BATS_TEST_TMPDIR/screen.txt"
  printf '%s\n' \
    "✻ Cooked for 10s · 2 shells still running" \
    "▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔" \
    "   Background work is running" \
    "   The following will stop when you exit:" \
    "" \
    "   shell · cc-await-ping --timeout 14000 --interval 30" \
    "   shell · L=/tmp/lookA4/render_full_r4_driver.log; until grep -qE …" \
    "" \
    "   ❯ 1. Exit and stop tasks" \
    "     2. Stay" \
    "" \
    "   Enter to confirm · Esc to cancel" > "$SCREEN"
  export STUB_PANE=12
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$HOME/it2-calls.log"' 'case "$1 $2" in' \
    '  "session list") if [ "${3:-}" = --json ]; then printf "[{\"id\": \"12\", \"tty\": \"/dev/ttys999\"}]\n"; else printf "12\n"; fi; exit 0 ;;' \
    '  "session read") cat "$SCREEN"; exit 0 ;;' 'esac' 'exit 0' > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"
  CMDFILE="$BATS_TEST_TMPDIR/relaunch.cmd"; printf 'claude --permission-mode auto\n' > "$CMDFILE"
  export CMDFILE
  export HF_RECYCLE_SHELL_WAIT_S=6 CC_RECYCLE_BGWORK_EVERY_S=3 HF_TEAM_HOLD=off
  # the fixture's pids are real pids on the machine they were captured on: no live process is read
  export HF_JOB_CWD=off
}
# drive <answer> → the detached watcher against the dialog, with the lane's own answer in force
drive() { run env CC_RECYCLE_BGWORK_ANSWER="$1" bash "$HF" __recycle 12 "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR" "$S12"; }
keys() { grep 'session send' "$HOME/it2-calls.log" 2>/dev/null || true; }
jobs_file() { find "$LRU_STATE/carried-jobs" -name "$S12.*.jsonl" 2>/dev/null | sed -n '1p'; }

@test "A4 [RED] pane 12 on a rejected source: 'Exit and stop tasks', under the move lane's answer and the reconciler's, with both jobs recorded first" {
  local ans f
  for ans in stop-if-watcher cancel; do
    rm -rf "$LRU_STATE/carried-jobs" "$HOME/it2-calls.log"; : > "$LRU_PS_SNAPSHOT"
    pane 12; rejected next3; dialog
    drive "$ans"
    [[ "$output" == *"answered '1' (Exit and stop tasks) — the source account is rejected (next3.7d "* ]] || { echo "answer=$ans: $output"; false; }
    [[ "$output" != *"recycle HELD"* ]] || { echo "answer=$ans held: $output"; false; }
    keys | grep -q 'session send -s 12 1$' || { echo "answer=$ans: no stop index sent"; keys; false; }
    f="$(jobs_file)"
    [ -n "$f" ] || { echo "answer=$ans: no jobs file"; false; }
    [ "$(grep -c . "$f")" -eq 2 ] || { echo "answer=$ans: jobs file '$f'"; cat "$f" 2>/dev/null; false; }
    # each job's command is the text the harness wrapped, verbatim from the real argv
    [ "$(jq -r 'select(.pid == 54057) | .command' "$f")" = "/Users/op/.claude/bin/cc-await-ping --timeout 14000 --interval 30" ] || { cat "$f"; false; }
    [ "$(jq -r 'select(.pid == 54057) | .watcher' "$f")" = true ]
    [ "$(jq -r 'select(.pid == 95607) | .command' "$f")" = 'L=/tmp/lookA4/render_full_r4_driver.log; until grep -qE "RENDER COMPLETE|INCOMPLETE" "$L" 2>/dev/null; do sleep 120; done; grep -E "RENDER COMPLETE|INCOMPLETE" "$L" | tail -1' ] || { cat "$f"; false; }
    [ "$(jq -r 'select(.pid == 95607) | .watcher' "$f")" = false ]
  done
}

@test "A4b [RED] the answer is still Stay on a healthy source, for a team member, for a ship-land job, and under the kill switch" {
  pane 12; dialog
  drive cancel
  [ "$status" -eq 1 ]
  [[ "$output" == *"recycle HELD"*"sent Esc (Stay)"* ]] || { echo "healthy: $output"; false; }
  ! keys | grep -qE 'session send -s 12 [0-9]$' || { echo "healthy: an index was sent"; keys; false; }
  [ -z "$(jobs_file)" ]
  # a team member on the rejected account: its lead moves it
  rm -f "$HOME/it2-calls.log"; : > "$LRU_PS_SNAPSHOT"
  pane 12 "--agent-id w@session-t --parent-session-id 00000000-0000-4000-8000-000000000001"; rejected next3
  drive cancel
  [[ "$output" == *"recycle HELD"*"sent Esc (Stay)"* ]] || { echo "member: $output"; false; }
  ! keys | grep -qE 'session send -s 12 [0-9]$' || { echo "member: an index was sent"; keys; false; }
  # a land in flight under one of its jobs
  rm -f "$HOME/it2-calls.log"; : > "$LRU_PS_SNAPSHOT"
  pane 12
  printf '90003 95607 %s /bin/bash /x/scripts/ship-land.sh\n' "$L12" >> "$LRU_PS_SNAPSHOT"
  drive cancel
  [[ "$output" == *"a ship-land job is running"* && "$output" == *"sent Esc (Stay)"* ]] || { echo "ship-land: $output"; false; }
  ! keys | grep -qE 'session send -s 12 [0-9]$' || { echo "ship-land: an index was sent"; keys; false; }
  # the kill switch
  rm -f "$HOME/it2-calls.log"; : > "$LRU_PS_SNAPSHOT"
  pane 12
  run env CC_RECYCLE_BGWORK_ANSWER=cancel CC_RECYCLE_DEAD_SOURCE_STOP=off bash "$HF" __recycle 12 "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR" "$S12"
  [[ "$output" == *"recycle HELD"*"sent Esc (Stay)"* ]] || { echo "kill switch: $output"; false; }
}

@test "A5 [RED] the successor is told: one mail naming each job's command and directory, sent once" {
  pane 12; rejected next3
  # the polling loop's shell is a real child here, so its directory is read off a live process
  mkdir -p "$BATS_TEST_TMPDIR/render dir"
  ( cd "$BATS_TEST_TMPDIR/render dir" && exec tail -f /dev/null ) >/dev/null 2>&1 3>&- &
  local child=$! cl
  HOLDER_PIDS="$HOLDER_PIDS $child"
  cl="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$child" | tr -s ' ' | sed -e 's/^ //' -e 's/ $//')"
  # the loop's row takes the child's pid and true start; the watcher's takes a pid no process has,
  # so its directory is unread whatever is running on the machine the suite runs on
  sed -i.bak -e "s/^95607 78979 Mon Oct 12 05:58:32 2026 /$child 78979 $cl /" -e "s/ 95607 / $child /" \
    -e "s/^54057 /4000001 /" -e "s/ 54057 / 4000001 /" "$LRU_PS_SNAPSHOT"
  load_fns "$HF" rcy_jobs_snapshot rcy_jobs_capture rcy_jobs_mail
  hf_bounded() { "$@"; }
  emit_recycle_event() { printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/events.log"; }
  RSID=12 RCY_OLD_SID="$S12"
  rcy_jobs_capture 78979 "next3.7d 1791892800"
  [ "$RCY_JOBS_N" -eq 2 ] || { echo "captured $RCY_JOBS_N"; cat "$RCY_JOBS_FILE"; false; }
  [ "$(jq -r --argjson p "$child" 'select(.pid == $p) | .cwd' "$RCY_JOBS_FILE")" = "$(cd "$BATS_TEST_TMPDIR/render dir" && pwd -P)" ] || { cat "$RCY_JOBS_FILE"; false; }
  [ "$(jq -r 'select(.pid == 4000001) | .cwd' "$RCY_JOBS_FILE")" = "" ] || { cat "$RCY_JOBS_FILE"; false; }
  RCY_JOBS_WHY="next3.7d 1791892800"
  rcy_jobs_mail; rcy_jobs_mail
  [ "$(grep -c . "$BATS_TEST_TMPDIR/notify.log")" -eq 1 ] || { echo "mails: $(cat "$BATS_TEST_TMPDIR/notify.log")"; false; }
  local m; m="$(cat "$BATS_TEST_TMPDIR/notify.log")"
  [[ "$m" == *" 12 JOBS-CARRIED: "* ]] || { echo "$m"; false; }
  [[ "$m" == *"cc-await-ping --timeout 14000 --interval 30"* ]] || { echo "$m"; false; }
  [[ "$m" == *'until grep -qE "RENDER COMPLETE|INCOMPLETE" "$L"'* ]] || { echo "$m"; false; }
  [[ "$m" == *"render dir"* && "$m" == *"an unread directory"* && "$m" == *"Start again whichever of these you still need"* ]] || { echo "$m"; false; }
  grep -q 'recycle-jobs-carried' "$BATS_TEST_TMPDIR/events.log"
}
