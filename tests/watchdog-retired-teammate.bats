#!/usr/bin/env bats
# lead-crash-watchdog.sh — a RETIRED teammate is retired, and every reader is honest
# (docs/research/husk-panes-2026-09-30.md, root causes 6 and 7, fix F-c).
#
# WHAT FAILED. Five Agent-Teams members (panes 33, 57-60) exited after their lead's shutdown_request
# and were painted "Resume it here" — the watchdog had no teammate arm, and members launch without
# cc-close-attrib, so nothing said otherwise. Three more defects rode along:
#   · pane_last_close grepped the WHOLE jsonl, so a session that never wrote a close read `no` off
#     the CLAUDE.md instructions attachment;
#   · find_close_record took the newest `<pid>-*.json`, so a REUSED pid joined a stranger's record;
#   · the death page went to `cc-notify --role desk`, and no desk role file exists — rc 3 every time.
# Every source is fixtured through the file's seams; nothing here touches a live tty, pane or store.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/lead-crash-watchdog.sh"
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/watchdog" "$HOME/.claude/logs" "$T/dev" "$T/roles" "$T/acct/projects/proj" "$T/jetsam" "$T/teardown" "$T/registry" "$T/close"
  export CC_ACCOUNT_BASES="$T/acct" CC_JETSAM_DIRS="$T/jetsam" CC_TEARDOWN_DIR="$T/teardown" CC_REGISTRY_DIR="$T/registry"
  export CC_ROLES_DIR="$T/roles" CC_SESSIONS_LOG="$T/sessions.log" CC_HANDOFF_LOG="$T/handoffs.jsonl"
  export CC_CLOSE_RECORDS_DIR="$T/close"
  # the pane: a fixture "tty" file and a procs file standing in for `ps -t <tty> -o stat=,command=`
  export CC_PANE_VERDICT_DEV="$T/dev" CC_PANE_VERDICT_TTY=ttys099 CC_PANE_VERDICT_TTY_PROCS="$T/procs"
  export CC_PANE_VERDICT_SETTLE_S=0 CC_PANE_VERDICT_PANE=33 CC_PANE_VERDICT_CFG="/x/.claude-tertiary" CC_PANE_VERDICT_CWD="$T/nocwd"
  # a "holds nothing" verdict hands the pane to the closer: a recorder here, never the real one
  export CC_PANE_CLOSE_BIN="$T/stub-pane-close" CC_PANE_VERDICT_CLOSE_GRACE_S=0
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$T/closed.txt" > "$CC_PANE_CLOSE_BIN"; chmod +x "$CC_PANE_CLOSE_BIN"
  : > "$T/dev/ttys099"; printf 'Ss+ /bin/zsh -l\n' > "$T/procs"
  # the death page and the OS notification, stubbed as argv collectors
  PAGED="$T/paged.txt"; OSA="$T/osa.txt"
  export CC_DEATH_PAGER="$T/stub-pager" CC_DEATH_OSA_BIN="$T/stub-osa"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$PAGED" > "$CC_DEATH_PAGER"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$OSA" > "$CC_DEATH_OSA_BIN"
  chmod +x "$CC_DEATH_PAGER" "$CC_DEATH_OSA_BIN"
  SID="74148f20-0d15-47ce-aa0b-c2f50d946016"
  TX="$T/acct/projects/proj/$SID.jsonl"
}

# A member's transcript: every record carries teamName + agentName (the shape a real member writes);
# its instructions attachment mentions shutdown_request in PROSE, which must never count as one.
mk_member_tx() { # $1=agentName
  printf '{"teamName":"session-4726bdf3","agentName":"%s","type":"user","message":{"role":"user","content":"<teammate-message teammate_id=\\"team-lead\\">\\nYou are a teammate. Then wait for a shutdown_request.\\n</teammate-message>"}}\n' "$1" > "$TX"
  # shellcheck disable=SC2016  # literal backticks, as the real instructions attachment carries them
  printf '{"teamName":"session-4726bdf3","agentName":"%s","type":"attachment","attachment":{"type":"instructions","content":"If you receive a JSON message with `type: \\"shutdown_request\\"`, respond."}}\n' "$1" >> "$TX"
  printf '{"teamName":"session-4726bdf3","agentName":"%s","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Report sent to the lead."}]}}\n' "$1" >> "$TX"
}
add_shutdown() { # $1=the member the request is addressed to
  printf '{"teamName":"session-4726bdf3","agentName":"lt-wrap","type":"user","message":{"role":"user","content":"<teammate-message teammate_id=\\"team-lead\\">\\n{\\"type\\":\\"shutdown_request\\",\\"requestId\\":\\"shutdown-1790819739861@%s\\",\\"from\\":\\"team-lead\\"}\\n</teammate-message>"}}\n' "$1" >> "$TX"
}
verdict() { # $1=class $2=cause $3=exit $4=sig
  bash "$HOOK" --pane-verdict "$SID" 63977 "$1" "$2" "$3" "$4" "$TX" </dev/null
}
painted() { cat "$T/dev/ttys099"; }

# ── 1. the RETIRED class ──────────────────────────────────────────────────────────────────────────

@test "a teammate shut down by its lead classifies RECYCLE/retired-teammate, and the death page is NOT sent" {
  mk_member_tx lt-wrap; add_shutdown lt-wrap
  run bash "$HOOK" --classify "$SID" ""
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | cut -f1)" = RECYCLE ]
  [ "$(printf '%s' "$output" | cut -f2)" = retired-teammate ]
  bash "$HOOK" --surface-death "$SID" 63977 RECYCLE retired-teammate "" "" "$TX" >/dev/null
  [ ! -s "$PAGED" ] || { echo "a retired teammate was paged: $(cat "$PAGED")"; false; }
}

@test "a retired teammate overrides a close record's exit code too (signal is not a crash)" {
  mk_member_tx lt-wrap; add_shutdown lt-wrap
  printf '{"pid":7001,"exit_code":137,"signal":"9","version":"2.1.284"}\n' > "$T/close/7001-100.json"
  run bash "$HOOK" --classify "$SID" 7001
  [ "$(printf '%s' "$output" | cut -f1-2)" = "$(printf 'RECYCLE\tretired-teammate')" ]
}

@test "the retired banner says RETIRED and close this pane, and offers no resume at all" {
  mk_member_tx lt-wrap; add_shutdown lt-wrap
  run verdict RECYCLE retired-teammate "" ""
  [ "$status" -eq 0 ]
  painted | grep -q 'RETIRED — teammate lt-wrap (session 74148f20) was shut down by its lead'
  painted | grep -q 'close this pane'
  ! painted | grep -q 'Resume' || false
  ! painted | grep -q -- '--resume' || false
}

@test "a shutdown_request addressed to ANOTHER member, or only mentioned in prose, is not a retirement" {
  mk_member_tx lt-wrap; add_shutdown someone-else
  run bash "$HOOK" --classify "$SID" ""
  [ "$(printf '%s' "$output" | cut -f2)" != retired-teammate ]
  mk_member_tx lt-wrap
  run bash "$HOOK" --classify "$SID" ""
  [ "$(printf '%s' "$output" | cut -f2)" != retired-teammate ]
}

@test "the registration-time agent id identifies the member when its records carry no teamName" {
  printf '{"type":"user","message":{"role":"user","content":"<teammate-message teammate_id=\\"team-lead\\">\\n{\\"type\\":\\"shutdown_request\\",\\"requestId\\":\\"shutdown-9@acct-routing\\"}\\n</teammate-message>"}}\n' > "$TX"
  CC_PANE_VERDICT_AGENT_ID="acct-routing@session-6a000e4a" run bash "$HOOK" --classify "$SID" ""
  [ "$(printf '%s' "$output" | cut -f2)" = retired-teammate ]
  run bash "$HOOK" --classify "$SID" ""
  [ "$(printf '%s' "$output" | cut -f2)" != retired-teammate ]
}

@test "a teammate death WITHOUT a shutdown_request keeps its class, and its banner names the lead instead of --resume" {
  mk_member_tx lt-wrap
  run bash "$HOOK" --classify "$SID" ""
  [ "$(printf '%s' "$output" | cut -f1)" = CRASH ]
  run verdict CRASH external-sigterm 143 15
  painted | grep -q 'NOT A CLEAN EXIT'
  painted | grep -q 'tell its lead (session 4726bdf3)'
  ! painted | grep -q -- '--resume' || false
  : > "$T/dev/ttys099"
  run verdict RECYCLE clean-exit 0 ""
  painted | grep -q 'tell its lead (session 4726bdf3)'
  ! painted | grep -q -- '--resume' || false
}

# ── 2. pane_last_close reads ASSISTANT text only ─────────────────────────────────────────────────

@test "the last close verdict comes from assistant text, never from an instructions attachment" {
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done.\\nGood to close: yes — nothing of mine is open"}]}}\n' > "$TX"
  # shellcheck disable=SC2016  # literal backticks, as the real instructions attachment carries them
  printf '{"type":"attachment","attachment":{"type":"instructions","content":"An honest `Good to close: no — <what remains>` also satisfies."}}\n' >> "$TX"
  printf '{"type":"user","message":{"role":"user","content":"is it Good to close: no?"}}\n' >> "$TX"
  run verdict RECYCLE clean-exit 0 ""
  painted | grep -q 'its last close verdict: yes'
}

@test "a session whose only close phrase is in its instructions reads '-', not 'no'" {
  # shellcheck disable=SC2016  # literal backticks, as the real instructions attachment carries them
  printf '{"type":"attachment","attachment":{"type":"instructions","content":"An honest `Good to close: no — <what remains>` also satisfies."}}\n' > "$TX"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}\n' >> "$TX"
  run verdict RECYCLE clean-exit 0 ""
  painted | grep -q 'its last close verdict: -'
}

# ── 3. the close-record join is keyed on pid + start time ───────────────────────────────────────

@test "two records for one pid: the join takes the one whose started_at matches the lead's start" {
  printf '{"pid":4242,"started_at":"2026-10-01T01:00:00Z","exit_code":0,"version":"2.1.284"}\n' > "$T/close/4242-1790816400.json"
  printf '{"pid":4242,"started_at":"2026-10-01T02:00:00Z","exit_code":143,"version":"2.1.284"}\n' > "$T/close/4242-1790820000.json"
  touch -t 202601010000 "$T/close/4242-1790816400.json"     # the match is the OLDER file by mtime
  run env CC_LEAD_START_EPOCH=1790816402 bash "$HOOK" --close-fields 4242
  [ "$(printf '%s' "$output" | cut -f3)" = "$T/close/4242-1790816400.json" ]
  [ "$(printf '%s' "$output" | cut -f1)" = 0 ]
}

@test "no record within tolerance of the lead's start ⇒ no join (the ladder's no-record path)" {
  printf '{"pid":4243,"started_at":"2026-10-01T02:00:00Z","exit_code":137,"version":"2.1.284"}\n' > "$T/close/4243-1790820000.json"
  run env CC_LEAD_START_EPOCH=1790816400 bash "$HOOK" --close-fields 4243
  [ "$status" -eq 0 ]
  [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ]
  # and the classifier no longer reads the stranger's 137 as this lead's SIGKILL
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"x"}]}}\n' > "$TX"
  run env CC_LEAD_START_EPOCH=1790816400 bash "$HOOK" --classify "$SID" 4243
  [ "$(printf '%s' "$output" | cut -f2)" != killed-oom-or-force ]
}

# ── 4. the death page has a destination that exists ────────────────────────────────────────────

@test "the default pager is cc-desk-page, called with --source and the line, and it exists in the tree" {
  [ -x "$REPO/bin/cc-desk-page" ]
  unset CC_DEATH_PAGER
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$PAGED" > "$HOME/.claude/bin/cc-desk-page"
  chmod +x "$HOME/.claude/bin/cc-desk-page"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"x"}]}}\n' > "$TX"
  bash "$HOOK" --surface-death "$SID" 63977 CRASH external-sigterm 143 15 "$TX" >/dev/null
  [ -s "$PAGED" ]
  grep -q '^--source lead-crash-watchdog SESSION DEATH' "$PAGED"
  ! grep -q -- '--role' "$PAGED" || false
}

@test "an explicit pager override named cc-notify keeps the --role call shape" {
  mkdir -p "$T/ov"
  export CC_DEATH_PAGER="$T/ov/cc-notify"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$PAGED" > "$CC_DEATH_PAGER"; chmod +x "$CC_DEATH_PAGER"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"x"}]}}\n' > "$TX"
  bash "$HOOK" --surface-death "$SID" 63977 CRASH external-sigterm 143 15 "$TX" >/dev/null
  grep -q '^--role desk SESSION DEATH' "$PAGED"
}
