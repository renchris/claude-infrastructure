#!/usr/bin/env bats
# pane-close-queue — F-b of docs/research/husk-panes-2026-09-30.md: a failed teammate pane close is a
# durable row (scripts/lib/pane-close-queue.sh) that scripts/pane-close-retry.sh retries once kitty
# remote control answers, re-reading the world first because rc 124 on a mutating verb may still
# execute late (root causes 3, 4, 10).
#
# HERMETIC: kitty, it2, the pager and the process table are stubs or fixtures under
# $BATS_TEST_TMPDIR, PATH is <stubdir>:/usr/bin:/bin, HOME is a temp dir. Nothing here can reach a
# live pane. Assertion style: `[ ]` — a non-final `[[ ]]` is errexit-exempt under bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/pane-close-queue.sh"
  DRAIN="$REPO/scripts/pane-close-retry.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude/logs" "$D/bin"
  # Pinned, never ambient: this box lives above handoff-fire's capacity ceiling (test-hermeticity-lint).
  export CC_FIRE_CAPACITY_GATE=off
  export PATH="$D/bin:/usr/bin:/bin"
  export CC_PANE_CLOSE_QUEUE_DIR="$D/q"
  export CC_PCQ_LOG="$D/pcq.log"
  export CC_PCQ_KITTY_BIN="$D/bin/kitty" CC_PCQ_IT2_BIN="$D/bin/it2" CC_PCQ_PAGE_BIN="$D/bin/page"
  export CC_PCQ_PS_FILE="$D/ps.txt" CC_PCQ_KITTY_SOCKET_BIN="$D/bin/nosock"
  # The kitty-independent closer is a stub that REFUSES unless a test says otherwise: the real one
  # would read this machine's watchdog log and signal real shells.
  export CC_PCQ_PANE_CLOSE_BIN="$D/bin/cc-pane-close"
  printf '#!/bin/bash\necho "pane ${2:-?}: REFUSED — stub"\nexit 1\n' > "$CC_PCQ_PANE_CLOSE_BIN"; chmod +x "$CC_PCQ_PANE_CLOSE_BIN"
  export KITTY_LISTEN_ON="unix:$D/kitty-610"
  # The session running this suite may itself sit in a kitty or iTerm2 pane; none of that may leak.
  unset KITTY_PID KITTY_WINDOW_ID CC_PANE_ID ITERM_SESSION_ID CC_TERM CC_TERM_KITTY_TO
  printf '%s\n' "  1 /sbin/launchd" > "$D/ps.txt"

  # kitty: `@ --to <sock> ls` prints $D/ls.json, or exits with $D/kitty.rc when that exists.
  # shellcheck disable=SC2016   # stub source written literally; its $ must expand in the stub, not here
  printf '#!/bin/bash\necho "kitty $*" >> "%s/kitty-calls.log"\n[ -f "%s/kitty.rc" ] && exit "$(cat "%s/kitty.rc")"\ncat "%s/ls.json"\n' \
    "$D" "$D" "$D" "$D" > "$D/bin/kitty"
  # it2: records the call, exits $D/it2.rc (default 0); a successful close swaps in ls-after.json.
  # shellcheck disable=SC2016
  printf '#!/bin/bash\necho "it2 $*" >> "%s/it2-calls.log"\nrc=$(cat "%s/it2.rc" 2>/dev/null || echo 0)\n[ "$rc" = 0 ] && [ -f "%s/ls-after.json" ] && mv "%s/ls-after.json" "%s/ls.json"\nexit "$rc"\n' \
    "$D" "$D" "$D" "$D" "$D" > "$D/bin/it2"
  printf '#!/bin/bash\necho "page $*" >> "%s/page-calls.log"\n' "$D" > "$D/bin/page"
  printf '#!/bin/bash\necho "notify $*" >> "%s/pcqnotify-calls.log"\n' "$D" > "$D/bin/pcqnotify"
  export CC_PCQ_NOTIFY_BIN="$D/bin/pcqnotify"
  printf '#!/bin/bash\nexit 4\n' > "$D/bin/nosock"
  chmod +x "$D/bin/kitty" "$D/bin/it2" "$D/bin/page" "$D/bin/pcqnotify" "$D/bin/nosock"
}

# a kitty ls with ONE window <id> whose foreground is <cmd> (written to $2, default ls.json)
lsjson() {
  printf '[{"id":1,"tabs":[{"id":1,"windows":[{"id":%s,"foreground_processes":[{"pid":9,"cmdline":["%s"]}]}]}]}]\n' \
    "$1" "$3" > "$D/${2:-ls.json}"
}
q() { bash -c '. "$0"; pcq_add "$@"' "$LIB" "$@"; }                       # pcq_add in a fresh shell
qget() { bash -c '. "$0"; pcq_get "$1" "$2"' "$LIB" "$1" "$2"; }
ROW33() { printf '%s' "$D/q/teammate-33.json"; }
husk_row() { q teammate 33 agent_id=m1@session-t team=session-t kitty_pid="${1:-610}" reason=close-failed rc=124; }

# ══ the lib ═════════════════════════════════════════════════════════════════════════════════════

@test "pcq_add writes one row; re-adding the same kind+pane updates it, never duplicates" {
  q teammate 33 reason=close-failed rc=124 attempts=2
  [ "$(find "$D/q" -name "*.json" | wc -l | tr -d ' ')" -eq 1 ]
  first="$(qget "$(ROW33)" first_ts)"
  q teammate 33 reason=deferred-tool-in-flight
  [ "$(find "$D/q" -name "*.json" | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(qget "$(ROW33)" reason)" = deferred-tool-in-flight ]
  [ "$(qget "$(ROW33)" attempts)" = 2 ]                 # attempts survive a re-add
  [ "$(qget "$(ROW33)" first_ts)" = "$first" ]
  [ "$(qget "$(ROW33)" kind)" = teammate ]
  [ "$(bash -c '. "$0"; pcq_list' "$LIB")" = "$(ROW33)" ]
}

@test "pcq_add JSON-escapes a value carrying a quote and a backslash" {
  q self-close 'w0t0p0:AB-12' reason='said "no" \ twice' argv='a b'
  row="$D/q/self-close-w0t0p0_AB-12.json"
  jq -e . "$row" >/dev/null
  [ "$(qget "$row" reason)" = 'said "no" \ twice' ]
  [ "$(qget "$row" attempts)" = 0 ]
}

@test "pcq_add refuses an unknown kind; pcq_remove refuses a path outside the queue" {
  run q bogus 33
  [ "$status" -eq 1 ]
  [ ! -e "$D/q/bogus-33.json" ]
  : > "$D/outside.json"
  run bash -c '. "$0"; pcq_remove "$1"' "$LIB" "$D/outside.json"
  [ "$status" -eq 1 ]
  [ -e "$D/outside.json" ]
}

# ══ the drainer ═════════════════════════════════════════════════════════════════════════════════

@test "kitty remote control times out (rc 124): no close is attempted and the row is kept" {
  husk_row; echo 124 > "$D/kitty.rc"
  run "$DRAIN"
  [ "$status" -eq 0 ]
  [ ! -e "$D/it2-calls.log" ]
  [ -e "$(ROW33)" ]
  grep -q "kitty unresponsive — 1 row(s) held" "$D/pcq.log"
}

@test "kitty unresponsive: a teammate row is handed to cc-pane-close, and its close removes the row" {
  husk_row; echo 124 > "$D/kitty.rc"
  printf '#!/bin/bash\necho "$*" >> %q\necho "pane 33: CLOSED — stub"\nexit 0\n' "$D/pc-calls.log" > "$CC_PCQ_PANE_CLOSE_BIN"
  run "$DRAIN"
  [ "$status" -eq 0 ]
  [ "$(cat "$D/pc-calls.log")" = "--pane 33" ]
  [ ! -e "$(ROW33)" ]
  grep -q "teammate pane=33 ✓ closed without remote control" "$D/pcq.log"
  [ ! -e "$D/it2-calls.log" ]
}

@test "kitty unresponsive and cc-pane-close refuses: the row is kept and the refusal is logged" {
  husk_row; echo 124 > "$D/kitty.rc"
  run "$DRAIN"
  [ "$status" -eq 0 ]
  [ -e "$(ROW33)" ]
  grep -q "held — kitty unresponsive and cc-pane-close did not close it: pane 33: REFUSED" "$D/pcq.log"
}

@test "pane absent from kitty ls: the row is removed and close is never called" {
  husk_row; lsjson 99 ls.json /bin/zsh
  run "$DRAIN"
  [ "$status" -eq 0 ]
  [ ! -e "$(ROW33)" ]
  [ ! -e "$D/it2-calls.log" ]
  grep -q "pane=33 ✓ pane gone" "$D/pcq.log"
}

@test "the member's claude still running: row kept, close never called" {
  husk_row; lsjson 33 ls.json /bin/zsh
  printf '%s\n' "4321 /x/node_modules/.bin/claude.exe --agent-id m1@session-t --agent-name m1 --team-name session-t" > "$D/ps.txt"
  run "$DRAIN"
  [ -e "$(ROW33)" ]
  [ ! -e "$D/it2-calls.log" ]
  grep -q "still running" "$D/pcq.log"
}

@test "an id that only appears inside a NON-claude process's quoted brief does not count as running" {
  husk_row; lsjson 33 ls.json -zsh; lsjson 77 ls-after.json /bin/zsh
  printf '%s\n' '4321 /bin/zsh -c "brief: check claude --agent-id m1@session-t --agent-name m1"' > "$D/ps.txt"
  run "$DRAIN"
  [ "$(grep -c 'session close' "$D/it2-calls.log")" -eq 1 ]
  [ ! -e "$(ROW33)" ]
}

@test "shell-only pane, member gone: closes once, re-lists, and removes the row" {
  husk_row; lsjson 33 ls.json /bin/zsh; lsjson 77 ls-after.json /bin/zsh
  run "$DRAIN"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'session close' "$D/it2-calls.log")" -eq 1 ]
  grep -q "it2 session close -f -s 33 --expect-generation 610" "$D/it2-calls.log"
  [ ! -e "$(ROW33)" ]
  grep -q "pane=33 ✓ closed and verified gone" "$D/pcq.log"
}

@test "a pane whose foreground is not a shell is not a husk: held, never closed" {
  husk_row; lsjson 33 ls.json /usr/bin/vim
  run "$DRAIN"
  [ -e "$(ROW33)" ]
  [ ! -e "$D/it2-calls.log" ]
}

@test "close returns 124: the row is kept with attempts=1" {
  husk_row; lsjson 33 ls.json /bin/zsh; echo 124 > "$D/it2.rc"
  run "$DRAIN"
  [ "$status" -eq 0 ]
  [ -e "$(ROW33)" ]
  [ "$(qget "$(ROW33)" attempts)" = 1 ]
  [ ! -e "$D/page-calls.log" ]
}

@test "attempts reaching CC_PCQ_MAX_ATTEMPTS page once and keep the row" {
  husk_row; lsjson 33 ls.json /bin/zsh; echo 1 > "$D/it2.rc"
  CC_PCQ_MAX_ATTEMPTS=2 run "$DRAIN"
  [ ! -e "$D/page-calls.log" ]
  CC_PCQ_MAX_ATTEMPTS=2 run "$DRAIN"
  CC_PCQ_MAX_ATTEMPTS=2 run "$DRAIN"
  [ "$(grep -c 'page ' "$D/page-calls.log")" -eq 1 ]
  [ -e "$(ROW33)" ]
}

@test "kitty generation changed: the row is removed and the stranger window is never closed" {
  husk_row 500; lsjson 33 ls.json /bin/zsh
  run "$DRAIN"
  [ ! -e "$(ROW33)" ]
  [ ! -e "$D/it2-calls.log" ]
  grep -q "generation changed (500 → 610)" "$D/pcq.log"
}

@test "self-close row with a dead retrier pages once; a second run does not page again" {
  q self-close 61 sid=abc reason=unreachable retrier_pid=99999998 retrier_lstart='Wed Sep 30 01:00:00 2026'
  echo 124 > "$D/kitty.rc"                    # never touches kitty, so a deaf kitty must not hold it
  run "$DRAIN"
  [ "$(grep -c 'page ' "$D/page-calls.log")" -eq 1 ]
  grep -q -- "--source pane-close-retry" "$D/page-calls.log"
  run "$DRAIN"
  [ "$(grep -c 'page ' "$D/page-calls.log")" -eq 1 ]
  [ -e "$D/q/self-close-61.json" ]
  [ ! -e "$D/it2-calls.log" ]
  [ ! -e "$D/pcqnotify-calls.log" ]           # the terminal is still deaf: no "re-run it" note yet
}

@test "self-close row, dead retrier, kitty answers: the session is told once to re-run its self-close" {
  q self-close 61 sid=abc reason=unreachable retrier_pid=99999998 retrier_lstart='Wed Sep 30 01:00:00 2026' \
    argv='--sid abc --pane 61'
  echo '[]' > "$D/ls.json"
  run "$DRAIN"
  [ "$(grep -c '^notify ' "$D/pcqnotify-calls.log")" -eq 1 ]
  grep -q "^notify 61 SELF-CLOSE RETRY: your self-close of pane 61 aborted at .* because the terminal did not answer; it answers now — re-run: handoff-fire.sh self-close --sid abc --pane 61" "$D/pcqnotify-calls.log"
  [ "$(grep -c 'page ' "$D/page-calls.log")" -eq 1 ]   # the desk page is kept
  run "$DRAIN"
  [ "$(grep -c '^notify ' "$D/pcqnotify-calls.log")" -eq 1 ]
  [ "$(grep -c 'page ' "$D/page-calls.log")" -eq 1 ]
  [ "$(qget "$D/q/self-close-61.json" notified)" = 1 ]
}

@test "self-close row with a LIVE retrier: no page, no note" {
  q self-close 61 sid=abc retrier_pid="$$" retrier_lstart="$(ps -p $$ -o lstart=)"
  echo '[]' > "$D/ls.json"
  run "$DRAIN"
  [ ! -e "$D/page-calls.log" ]
  [ ! -e "$D/pcqnotify-calls.log" ]
}

@test "an empty queue never asks kitty anything" {
  run "$DRAIN"
  [ "$status" -eq 0 ]
  [ ! -e "$D/kitty-calls.log" ]
}

# ══ the wiring ══════════════════════════════════════════════════════════════════════════════════

@test "teammate-reap-alarm runs the drainer, and a failing drainer leaves its exit code unchanged" {
  local lc="$D/lifecycle.log" i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "[$(date +%Y-%m-%d) 09:00:00] defer m$i (1/3): dirty tree" >> "$lc"; done
  printf '#!/bin/bash\ntouch "%s/drain-ran"\nexit 7\n' "$D" > "$D/bin/drain"; chmod +x "$D/bin/drain"
  export TEAMMATE_LIFECYCLE_LOG="$lc" CC_RESIDENCY_SH="$D/none" CC_PCQ_DRAIN_BIN="$D/bin/drain"
  CC_PCQ_DRAIN=off run "$REPO/scripts/teammate-reap-alarm.sh"
  want="$status"
  [ ! -e "$D/drain-ran" ]
  run "$REPO/scripts/teammate-reap-alarm.sh"
  [ -e "$D/drain-ran" ]
  [ "$status" -eq "$want" ]
}

# ── teammate-auto-shutdown: minimal close fixture (mirrors tests/teammate-auto-shutdown.bats) ──
# $1 = what `it2 session list` prints, $2 = rc of `it2 session close`, $3 = "tool" for a transcript
# whose last assistant record is an unanswered tool_use (the tool-in-flight defer). Writes the hook
# input to $D/in.json; _hook_close runs the hook on it.
_hook_setup() {
  local NOW=1000000000 sid=sidT team=teamT member=wkrTerm wt="$D/wtT" content='{"type":"text","text":"hi"}'
  [ "${3:-}" = tool ] && content='{"type":"tool_use","id":"tu-live","name":"Bash","input":{}}'
  export CLAUDE_CONFIG_DIR="$HOME/.claude" CC_CLASSIFY_PROJECT_ROOTS="$D/proj" CC_CLASSIFY_NOW="$NOW"
  export CC_CLASSIFY_INTERACTIVE_HOLD_S=21600 CC_CLASSIFY_FIRE_PROMPT_SLACK_S=300
  export CC_INTERACTIVE_LIB="$D/cc-interactive-stub.sh" CC_NOTIFY_BIN="$D/bin/cc-notify"
  export TEAMMATE_CHECKPOINT_DISABLED=1 TEAMMATE_CLOSE_GRACE_S=0 CC_IN_KITTY_BIN="$D/bin/cik"
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  printf '%s\n' "  4243     1 /bin/zsh -l" > "$D/pstable.txt"; export CC_WF_PSTABLE_FILE="$D/pstable.txt"
  printf '#!/usr/bin/env bash\n. "%s"\n' "$REPO/hooks/lib/cc-interactive.sh" > "$D/cc-interactive-stub.sh"
  printf '#!/bin/bash\nexit 0\n' > "$D/bin/cik"
  printf '#!/bin/bash\necho "cc-notify $*" >> "%s/notify-calls.log"\n' "$D" > "$D/bin/cc-notify"
  printf '#!/bin/bash\ncat "%s/sessions.json"\n' "$D" > "$D/bin/cc-sessions"
  # shellcheck disable=SC2016
  printf '#!/bin/bash\nif [ "$1 $2" = "session list" ]; then printf "%%s\\n" "%s"; exit 0; fi\nif [ "$1 $2" = "session close" ]; then echo close >> "%s/hit2.log"; exit %s; fi\nexit 0\n' \
    "$1" "$D" "$2" > "$D/bin/it2"
  chmod +x "$D/bin/cik" "$D/bin/cc-notify" "$D/bin/cc-sessions" "$D/bin/it2"
  mkdir -p "$wt" "$D/proj/slug" "$HOME/.claude/teams/$team" "$HOME/.claude/watchdog"
  printf '%s\t%s\n' "$member" "$wt" > "$HOME/.claude/teams/$team/worktrees.tsv"
  printf '{"members":[{"name":"%s","tmuxPaneId":"PANE-Z"}]}' "$member" > "$HOME/.claude/teams/$team/config.json"
  printf '[{"name":"t","paneUUID":"PANE-T","account":"next","cwd":"%s","pid":%s,"session_id":"%s","startedAt":%s}]\n' \
    "$wt" "$$" "$sid" "$(( (NOW - 3600) * 1000 ))" > "$D/sessions.json"
  printf '{"type":"assistant","timestamp":"%s.000Z","message":{"role":"assistant","content":[%s]}}\n' \
    "$(TZ=UTC date -j -f %s "$((NOW - 9000))" +%Y-%m-%dT%H:%M:%S)" "$content" > "$D/proj/slug/$sid.jsonl"
  printf '{"teammate_name":"%s","team_name":"%s","session_id":"%s","cwd":"%s"}' "$member" "$team" "$sid" "$wt" > "$D/in.json"
}
# fd 9 ends the wait only when the hook AND its detached close child have exited (see the sibling suite).
_hook_close() { _hook_setup "$@"; { "$REPO/hooks/teammate-auto-shutdown.sh" 9>&1 < "$D/in.json"; } | cat; }

# A stand-in for the member's own claude.exe: the hook runs as ITS child, exactly as on the
# implicit-team model, so _find_teammate_pid walks $PPID to a process whose argv names the member and
# whose env carries the window id. A real process and the real `ps` — no seam in the hook.
# The stand-in's interpreter must NOT be an Apple platform binary: macOS hides a platform process's
# environment from `ps eww` (measured: /bin/bash shows none, Homebrew bash shows it), while the real
# member, a node-packaged claude.exe, is not one. No such bash on the box ⇒ skip, never a false pass.
_as_member() { # $1 = KITTY_WINDOW_ID for the member's env ("" = none)
  local sh=""
  for sh in /opt/homebrew/bin/bash /usr/local/bin/bash ""; do [ -n "$sh" ] && [ -x "$sh" ] && break; done
  [ -n "$sh" ] || skip "no non-platform bash to stand in for claude.exe"
  printf '#!%s\n"%s" < "%s"\n' "$sh" "$REPO/hooks/teammate-auto-shutdown.sh" "$D/in.json" > "$D/bin/claude.exe"
  chmod +x "$D/bin/claude.exe"
  if [ -n "$1" ]; then export KITTY_WINDOW_ID="$1"; fi
  "$D/bin/claude.exe" --agent-id wkrTerm@session-tt --agent-name wkrTerm --team-name session-tt
}

@test "teammate-auto-shutdown: a FAILED close leaves a durable retry row, and still pages" {
  _hook_close PANE-Z 124
  [ -e "$D/hit2.log" ]
  row="$D/q/teammate-PANE-Z.json"
  [ -e "$row" ]
  [ "$(qget "$row" reason)" = close-failed ]
  [ "$(qget "$row" rc)" = 124 ]
  [ "$(qget "$row" agent_id)" = wkrTerm@teamT ]
  grep -q "↻ queued for retry: $row" "$HOME/.claude/logs/teammate-lifecycle.log"
  grep -q "could NOT be closed" "$D/notify-calls.log"
}

@test "teammate-auto-shutdown: a close that reported rc=0 but left the pane STANDING is queued too" {
  _hook_close PANE-Z 0
  grep -q "STILL PRESENT" "$HOME/.claude/logs/teammate-lifecycle.log"
  [ -e "$D/q/teammate-PANE-Z.json" ]
}

@test "teammate-auto-shutdown: a tool-in-flight defer queues the member's kitty window from its own env" {
  _hook_setup PANE-Z 0 tool
  _as_member 4242
  grep -q "tool in flight" "$HOME/.claude/logs/teammate-lifecycle.log"
  [ ! -e "$D/hit2.log" ]                                # the defer still closes nothing
  row="$D/q/teammate-4242.json"
  [ -e "$row" ]
  [ "$(qget "$row" reason)" = deferred-tool-in-flight ]
  [ "$(qget "$row" agent_id)" = wkrTerm@session-tt ]    # read from the member's argv, not composed
}

@test "teammate-auto-shutdown: a tool-in-flight defer with no resolvable pane says it was NOT queued" {
  _hook_setup PANE-Z 0 tool
  _as_member ""
  grep -q "defer NOT queued for retry" "$HOME/.claude/logs/teammate-lifecycle.log"
  [ "$(find "$D/q" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
}

@test "teammate-auto-shutdown: CONTROL — a verified close writes no row" {
  _hook_close SOME-OTHER-PANE 0
  grep -q "✓ closed pane PANE-Z" "$HOME/.claude/logs/teammate-lifecycle.log"
  [ ! -e "$D/q/teammate-PANE-Z.json" ]
}
