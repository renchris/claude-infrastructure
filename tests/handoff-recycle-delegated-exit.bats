#!/usr/bin/env bats
# handoff-fire.sh __recycle — the self-recycle latency fix (docs/research/selfrecycle-latency-2026-10-26/).
#
# D1  the foreground of a self-recycle writes `exit-delegated` and types nothing; the WATCHER waits for
#     the recycle's own tool call to end and types the first /exit itself, so no "Background work is
#     running" dialog is raised over that call (34 of 47 self-recycles paid 24-52 s for it).
# D2  a dialog that still appears is read every second for the first 30 s, not first at 15 s.
# D3  a dialog listing only session scheduled tasks (CronCreate) is answered "Exit and stop tasks",
#     and the crons are appended to the successor's prompt first; anything else listed keeps keep-work.
# D5  a terminal failure row also lands in its incident record (fire suppressed under bats).
#
# WHAT IS DRIVEN: the detached `__recycle` watcher, directly, against a stateful stub `it2` that draws
# a composer box (read back through the real composer_content), turns into the dialog when a CR submits
# /exit, and records every key. The tty does not exist, so the watcher never reaches a shell and ends at
# its 6 s bound; each test asserts what was TYPED and the ledger rows, not how the run ended.
# The dialog screens are the PTY captures of 2.1.293 (/tmp/probe-cron, 2026-10-26), item rows verbatim.
#
# RED-proof (pre-fix watcher, 1a0ee3658): D1 — exit-delegated is ignored, so no /exit is typed inside
# the 6 s bound; D2 — the first dialog check is at 15 s, past the bound, so nothing is answered; D3 —
# kind `none` fails stop-if-watcher and the keep-work index '2' is sent; D5 — no incident record.

load helpers/cc-stub

setup() {
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"
  export H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude/bin" "$H/.claude/cc-registry"; export HOME="$H"
  export CC_HANDOFF_ALARM_DIR="$H/.claude/handoff-alarms"
  export CC_PANE_MODAL_LIB="$REPO_SRC/hooks/lib/pane-modal.sh"
  export CC_PROJECTS_DIRS="$H/.claude/projects"
  export CC_RECYCLE_RETRY_DIR="$H/retry" CC_RECYCLE_INCIDENT_DIR="$H/incidents"
  export HF_TEAM_HOLD=off CC_RECYCLE_DEAD_SOURCE_STOP=off CC_RECYCLE_BGWORK_GOAL_CLEAR=off
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  cc_stub "$SHIM" osascript $'#!/usr/bin/env bash\nexit 0\n'
  export PATH="$SHIM:$PATH"
  export CC_NOTIFY_BIN="$H/.claude/bin/cc-notify"
  cc_stub "$H/.claude/bin" cc-notify $'#!/usr/bin/env bash\nexit 0\n'
  export STUB_PANE="SELF-PANE"
  : > "$H/composer"
  cc_stub "$H/.claude/bin" it2 - <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "$STUB_PANE"; else printf '%s\n' "$STUB_PANE"; fi
    exit 0 ;;
  "session read")
    if [ -f "$HOME/dialog" ]; then cat "$HOME/dialog"; exit 0; fi
    printf '  earlier output\n──────────────────────────────────────\n❯ %s\n──────────────────────────────────────\n' "$(cat "$HOME/composer")"
    exit 0 ;;
  "session send")
    k="${5:-}"
    case "$k" in
      /exit) printf 'caller_alive=%s\n' "$(kill -0 "${CALLER:-0}" 2>/dev/null && echo 1 || echo 0)" >> "$HOME/exit-typed.log"
             printf '%s/exit' "$(cat "$HOME/draft" 2>/dev/null)" > "$HOME/composer" ;;
      $'\r') if [ "$(cat "$HOME/composer")" = /exit ]; then : > "$HOME/composer"; [ ! -f "$HOME/dialog-on-exit" ] || cp "$HOME/dialog-on-exit" "$HOME/dialog"; fi ;;
      $'\e') rm -f "$HOME/dialog"; printf 'esc\n' >> "$HOME/keys.log" ;;
      $'\x7f\x7f\x7f\x7f\x7f') printf 'dels\n' >> "$HOME/keys.log" ;;
      [1-9]) rm -f "$HOME/dialog"; printf '%s\n' "$k" >> "$HOME/keys.log" ;;
    esac
    exit 0 ;;
esac
exit 0
SH
  CMDFILE="$BATS_TEST_TMPDIR/relaunch.cmd"; printf 'claude --permission-mode auto\n' > "$CMDFILE"
  export CMDFILE
  export HF_RECYCLE_SHELL_WAIT_S=6
  # A ps snapshot with nothing under the session's claude pid: hf_bg_work_kind reads `none`.
  printf '  1     0 Mon Oct 26 08:00:00 2026 /sbin/launchd\n' > "$BATS_TEST_TMPDIR/ps.txt"
  export HF_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"
}

teardown() { [ -z "${CALLER:-}" ] || kill "$CALLER" 2>/dev/null || true; }

# $1=old sid (may be empty) $2=caller pid (may be empty)
drive() {
  bash "$HF" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR" \
    "${1:-}" "" "" "" "" "" "" "" "" "" "${2:-}"
}
rows() { jq -r '.class' "$H/.claude/logs/handoffs.jsonl" 2>/dev/null; }
dialog_with() { # $@=item rows → the measured 2.1.293 dialog, with these items
  { printf '✻ Worked for 5s · done 2:58 AM\n▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔\n'
    printf '   Background work is running\n   The following will stop when you exit:\n\n'
    for r in "$@"; do printf '   %s\n' "$r"; done
    printf '\n   ❯ 1. Exit and stop tasks\n     2. Move to background and exit\n     3. Stay\n\n─  Enter to confirm · Esc to cancel\n'; }
}
cron_transcript() { # $1=sid → a transcript holding one live CronCreate job
  mkdir -p "$H/.claude/projects/p"
  { jq -nc '{type:"assistant",timestamp:(now|todate),message:{content:[{type:"tool_use",id:"toolu_1",name:"CronCreate",input:{cron:"13 3 * * *",prompt:"probe ping",recurring:true}}]}}'
    jq -nc '{type:"user",timestamp:(now|todate),message:{content:[{tool_use_id:"toolu_1",type:"tool_result",content:"Scheduled recurring job a0913553 (13 3 * * *). Session-only."}]},toolUseResult:{id:"a0913553",humanSchedule:"13 3 * * *",recurring:true,durable:false}}'
  } > "$H/.claude/projects/p/$1.jsonl"
}

@test "D1: the watcher types the delegated /exit only after the recycle's own call has returned, and never sends Esc" {
  /bin/sleep 2 & CALLER=$!; export CALLER
  : > "$CMDFILE.exit-delegated"
  run drive "" "$CALLER"
  [ "$(cat "$H/exit-typed.log")" = "caller_alive=0" ] || { cat "$H/exit-typed.log"; false; }
! grep -qx 'esc' "$H/keys.log" 2>/dev/null || { echo "an Esc was sent"; false; }
  grep -c $'session send -s SELF-PANE \r' "$H/it2-calls.log" | grep -qx 1
  rows | grep -qx recycle-exit-delegated
  [[ "$output" == *"/exit typed by the watcher, read back, CR sent (delegated)"* ]]
}

@test "D1: a call that outlives CC_RECYCLE_SELFCALL_WAIT_S holds with nothing typed, a retry ticket and an incident record" {
  /bin/sleep 30 & CALLER=$!; export CALLER
  : > "$CMDFILE.exit-delegated"
  CC_RECYCLE_SELFCALL_WAIT_S=2 run drive OLDSID-held "$CALLER"
  [ "$status" -eq 1 ]
  [ ! -s "$H/exit-typed.log" ]
  rows | grep -qx recycle-held-delegated
  [ "$(jq -r '.why' "$H/retry/OLDSID-held.json")" = "the recycle's own tool call did not return within 2s, so its /exit was never typed" ]
  [ "$(jq -r '.count' "$H/incidents/recycle-held-delegated.json")" = 1 ]
  [ "$(jq -r '.last_verdict' "$H/incidents/recycle-held-delegated.json")" = suppressed-under-test ]
}

@test "D1: a delegated /exit that reads back fused to an operator draft holds, undoes our five characters, sends no CR" {
  printf 'half a thought' > "$H/draft"
  : > "$CMDFILE.exit-delegated"
  run drive "" ""
  [ "$status" -eq 1 ]
  grep -qx dels "$H/keys.log"
! grep -q $'session send -s SELF-PANE \r' "$H/it2-calls.log" || { echo "a CR was sent over a draft"; false; }
  rows | grep -qx recycle-held-exit-readback
}

@test "D2: a dialog already up at the commit is answered within 3 s, at the default 15 s cadence" {
  dialog_with 'shell · sleep 600' > "$H/dialog"
  run drive "" ""
  ans="$(printf '%s\n' "$output" | sed -n "s/.*bgwork@\([0-9]*\)s: the \/exit raised the background-work dialog; answered.*/\1/p" | head -1)"
  [ -n "$ans" ] && [ "$ans" -le 3 ] || { printf '%s\n' "$output" | grep bgwork; false; }
}

@test "D2: CC_RECYCLE_BGWORK_FAST_S=0 restores the 15 s cadence (nothing answered inside the 6 s bound)" {
  dialog_with 'shell · sleep 600' > "$H/dialog"
  CC_RECYCLE_BGWORK_FAST_S=0 run drive "" ""
  [ ! -s "$H/keys.log" ]
}

d3_setup() {
  cron_transcript OLDSID-cron
  printf '{"pid":4242,"session_id":"OLDSID-cron"}\n' > "$H/.claude/cc-registry/$STUB_PANE.json"
  export HF_RCY_LAUNCH_PROMPT="$BATS_TEST_TMPDIR/prompt.md"; printf 'the brief\n' > "$HF_RCY_LAUNCH_PROMPT"
  /usr/bin/true & CALLER=$!; wait "$CALLER" || true; export CALLER   # a call that has returned
  : > "$CMDFILE.exit-delegated"
}

@test "D3: a dialog listing only a session cron is answered 'Exit and stop tasks', with the cron carried and no background copy" {
  d3_setup
  dialog_with 'scheduled task · Every day at 3:13 AM · probe ping' > "$H/dialog-on-exit"
  run drive OLDSID-cron "$CALLER"
  [ "$(cat "$H/keys.log")" = 1 ] || { cat "$H/keys.log"; false; }
  rows | grep -qx recycle-bgwork-stopped-cron
! rows | grep -qx recycle-bgcopy-stop || { echo "a background copy was made"; false; }
  grep -qx '<!-- recycle-cron-carry v1 -->' "$HF_RCY_LAUNCH_PROMPT"
  grep -qF '"cron":"13 3 * * *"' "$HF_RCY_LAUNCH_PROMPT"
}

@test "D3: anything else on the list (an agent beside the cron) keeps today's keep-work answer" {
  d3_setup
  dialog_with 'scheduled task · Every day at 3:13 AM · probe ping' 'agent · research the cause' > "$H/dialog-on-exit"
  run drive OLDSID-cron "$CALLER"
  [ "$(cat "$H/keys.log")" = 2 ] || { cat "$H/keys.log"; false; }
! rows | grep -qx recycle-bgwork-stopped-cron || { echo "real work was stopped"; false; }
  true
}

@test "D3: CC_RECYCLE_CRON_CARRY=off restores keep-work and carries nothing" {
  d3_setup
  dialog_with 'scheduled task · Every day at 3:13 AM · probe ping' > "$H/dialog-on-exit"
  CC_RECYCLE_CRON_CARRY=off run drive OLDSID-cron "$CALLER"
  [ "$(cat "$H/keys.log")" = 2 ]
  [ "$(cat "$HF_RCY_LAUNCH_PROMPT")" = "the brief" ]
}

@test "D3: the dialog's item kinds are read through wrapping, and an unread list yields nothing" {
  run bash -c "$(sed -n '/^hf_bgwork_dialog_kinds() {/,/^}/p' "$HF"); printf '  The following will stop when you\n    exit:\n\n  scheduled task · Every day at\n    3:13 AM · probe ping\n  shell · cc-await-ping --timeout 3300\n\n  ❯ 1. Exit and stop tasks\n' | hf_bgwork_dialog_kinds"
  [ "$status" -eq 0 ]
  [ "$output" = $'scheduled task\nshell' ]
  run bash -c "$(sed -n '/^hf_bgwork_dialog_kinds() {/,/^}/p' "$HF"); printf 'no dialog here\n' | hf_bgwork_dialog_kinds"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
