#!/usr/bin/env bats
# boot-resume.sh must not resume a session that RETIRED ITSELF ON PURPOSE.
#
# Incident 2026-10-01: d86e6bd4 ran `handoff-fire.sh self-close --terminal` at 18:43:34Z; a kitty
# restart then resumed it from a roster taken before that, through this script. The evidence is the
# teardown marker self-close writes just before /exit (<teardown>/<sid>.json, mode terminal |
# successor), and it counts only when it is newer than the transcript's newest user/assistant record.
#
# Hermetic: temp $HOME, every binary stubbed, and the cases run under PATH=<stubdir>:/usr/bin:/bin.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO/scripts/boot-resume.sh"
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"; mkdir -p "$HOME"
  STUBS="$T/stubs"; mkdir -p "$STUBS"
  export PATH="$STUBS:/usr/bin:/bin"
  export CC_REGISTRY_DIR="$T/cc-registry" CC_ROLES_DIR="$T/roles" CC_IDL="$T/idl.jsonl"
  export CC_BOOT_RESUME_STATE_DIR="$T/state" CC_BOOTTIME_OVERRIDE=1784800000
  export CC_BOOT_RESUME_ROSTER_DIR="$T/autonomy" CC_SHUTDOWN_TOMB_DIR="$T/tombs"
  export CC_TEARDOWN_DIR="$T/teardown"
  mkdir -p "$CC_REGISTRY_DIR" "$CC_ROLES_DIR" "$CC_BOOT_RESUME_ROSTER_DIR" "$CC_SHUTDOWN_TOMB_DIR" "$CC_TEARDOWN_DIR"
  echo desk-pane > "$CC_ROLES_DIR/desk"

  stub() { printf '#!/bin/bash\n%s\n' "$2" > "$STUBS/$1"; chmod +x "$STUBS/$1"; }
  stub notify    'printf "%s\n" "$*" >> "$0.log"'
  stub backlog   'echo beef1234cafe'
  stub launch    '[ "$1" = --check-only ] && exit 0; printf "%s\n" "$*" >> "$0.log"'
  stub open      ':'
  stub ksock     'echo unix:/tmp/kitty-test'
  stub keepalive ':'
  stub launchctl ':'
  stub select    'exit 0'
  stub classify  'while IFS= read -r r; do [ -n "$r" ] && printf "%s\tAT-REST\n" "$r"; done'
  export CC_NOTIFY_BIN="$STUBS/notify" CC_BACKLOG_BIN="$STUBS/backlog" CC_RESUME_LAUNCH_BIN="$STUBS/launch"
  export CC_OPEN_BIN="$STUBS/open" CC_KITTY_SOCKET_BIN="$STUBS/ksock" CC_KEEPALIVE_BIN="$STUBS/keepalive"
  export CC_LAUNCHCTL_BIN="$STUBS/launchctl" CC_RESUME_SELECT_BIN="$STUBS/select"
  export CC_RESUME_CLASSIFY_BIN="$STUBS/classify" CC_RESUME_LAYOUT_BIN="$T/no-layout"
  export CC_BOOT_RESUME_KITTY_POLL=0 CC_BOOT_RESUME_MODE=resume

  # The roster a pre-restart snapshot took: two sessions, both on .claude-tertiary (→ claude3).
  printf '%s\n' 1784799000 > "$CC_BOOT_RESUME_ROSTER_DIR/reboot-t.start"
  jq -n '[{account:"claude-tertiary",cwd:"/x/wt-gone",session_id:"sid-gone",name:"gone-pane",branch:"b1"},
          {account:"claude-tertiary",cwd:"/x/wt-live",session_id:"sid-live",name:"live-pane",branch:"b2"}]' \
    > "$CC_BOOT_RESUME_ROSTER_DIR/reboot-t.roster.json"
  transcript sid-gone "2026-10-01T18:43:24.288Z"
  transcript sid-live "2026-10-01T18:50:00.000Z"
}

# transcript <sid> <last-activity-ts> — a real transcript's tail shape: the conversation, then
# the untimestamped records Claude Code appends at exit (which make the FILE newer than any marker).
transcript() {
  local d="$HOME/.claude-tertiary/projects/-x-wt"; mkdir -p "$d"
  {
    printf '{"type":"user","timestamp":"2026-10-01T18:40:00.000Z","message":{"content":"go"}}\n'
    printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"tool_use","name":"Bash"}]}}\n' "$2"
    printf '{"type":"attachment","timestamp":"2026-10-01T18:59:00.000Z"}\n'
    printf '{"type":"last-prompt"}\n{"type":"mode"}\n{"type":"ai-title"}\n'
  } > "$d/$1.jsonl"
}
marker() { # <sid> <mode> <ts>
  printf '{"key_kind":"sid","pane":"25","sid":"%s","mode":"%s","ts":"%s"}\n' "$1" "$2" "$3" > "$CC_TEARDOWN_DIR/$1.json"
}
launched() { cat "$STUBS/launch.log" 2>/dev/null; }

@test "terminal self-close newer than the last activity ⇒ NOT resumed; the other session is" {
  marker sid-gone terminal 2026-10-01T18:43:34Z
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! launched | grep -q sid-gone || false
  launched | grep -q sid-live
  grep -q '"retired_skipped":1' "$CC_IDL"
}

@test "the skip is logged with the marker and its time, and the page names it with a resume line" {
  marker sid-gone terminal 2026-10-01T18:43:34Z
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped retired session gone-pane (sid-gone): terminal self-close marker $CC_TEARDOWN_DIR/sid-gone.json at 2026-10-01T18:43:34Z"* ]] || false
  grep -q "cd '/x/wt-gone' && claude3 --resume sid-gone" "$CC_BOOT_RESUME_STATE_DIR/last-retired.txt"
  grep -q 'closed themselves on purpose' "$STUBS/notify.log"
  grep -q 'claude3 --resume sid-gone' "$STUBS/notify.log"
}

@test "a successor self-close is a retirement too" {
  marker sid-gone successor 2026-10-01T18:43:34Z
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! launched | grep -q sid-gone || false
}

@test "an /exit command record after the marker is not activity" {
  marker sid-gone terminal 2026-10-01T18:43:34Z
  printf '{"type":"user","timestamp":"2026-10-01T18:43:36.000Z","message":{"content":"<command-name>/exit</command-name>"}}\n' \
    >> "$HOME/.claude-tertiary/projects/-x-wt/sid-gone.jsonl"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! launched | grep -q sid-gone || false
}

@test "page mode: a retired session is not listed as live; it is named as skipped" {
  export CC_BOOT_RESUME_MODE=page
  marker sid-gone terminal 2026-10-01T18:43:34Z
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '1 session(s) were live' "$STUBS/notify.log"
  grep -q 'gone-pane (sid-gone): terminal self-close marker' "$STUBS/notify.log"
}

@test "every session retired ⇒ nothing launched, abstain all-retired, marker advanced" {
  marker sid-gone terminal 2026-10-01T18:43:34Z
  marker sid-live terminal 2026-10-01T18:51:00Z
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(launched)" ]
  grep -q '"reason":"all-retired"' "$CC_IDL"
  [ "$(cat "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch")" = 1784800000 ]
}

# ── the guards: what must STILL come back ────────────────────────────────────────────────────
@test "activity AFTER the marker (the self-close aborted) ⇒ resumed" {
  marker sid-gone terminal 2026-10-01T18:43:20Z
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  launched | grep -q sid-gone
  grep -q '"retired_skipped":0' "$CC_IDL"
}

@test "a recycle marker is not a retirement ⇒ resumed" {
  marker sid-gone recycle 2026-10-01T18:43:34Z
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  launched | grep -q sid-gone
}

@test "no transcript to compare against ⇒ resumed (missing evidence never skips)" {
  marker sid-gone terminal 2026-10-01T18:43:34Z
  rm "$HOME/.claude-tertiary/projects/-x-wt/sid-gone.jsonl"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  launched | grep -q sid-gone
}

@test "kill switch CC_BOOT_RESUME_SKIP_RETIRED=off ⇒ resumed" {
  marker sid-gone terminal 2026-10-01T18:43:34Z
  CC_BOOT_RESUME_SKIP_RETIRED=off run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  launched | grep -q sid-gone
}
