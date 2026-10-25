#!/usr/bin/env bats
# pane-census — scripts/pane-census.sh, the standing pane census (husk-history-2026-10-24
# FIX-DESIGN §4 W3, D15): one JSONL row per drainer tick classifying every fleet pane kitty still
# lists, and a page once per (kitty pid, pane) for an unexplained bare shell or an over-age hold.
#
# HERMETIC: kitty, its socket and the pager are stubs; the watchdog log, exit records and fired
# stamps are fixtures; HOME is a temp dir; PATH is <stubdir>:/usr/bin:/bin. Nothing here can reach a
# live pane. Every run is under /bin/bash (3.2 on macOS), the interpreter launchd gives the drainer.

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CENSUS="$REPO/scripts/pane-census.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude/logs" "$D/bin" "$D/exit" "$D/fired"
  export PATH="$D/bin:/usr/bin:/bin"
  unset KITTY_LISTEN_ON KITTY_PID KITTY_WINDOW_ID CC_TERM CC_TERM_KITTY_TO CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
  KST=$(( $(date +%s) - 86400 )); NOW=$(date +%s)
  export CC_PANE_CENSUS_KITTY_START_EPOCH="$KST" CC_PANE_CENSUS_NOW="$NOW" CC_PANE_CENSUS_MIN_INTERVAL_S=0
  export CC_PANE_CENSUS_LOG="$D/census.jsonl" CC_PANE_CENSUS_STATE_DIR="$D/state"
  export CC_PANE_CENSUS_WATCHDOG_LOG="$D/wd.log" CC_PANE_CENSUS_EXIT_DIR="$D/exit" CC_PANE_CENSUS_FIRED_DIR="$D/fired"
  cc_stub "$D/bin" sock "$(printf '#!/bin/bash\necho unix:/tmp/kitty-610\n')"
  # kitty: `@ --to <sock> ls` prints $D/ls.json, or exits with $D/kitty.rc when that exists; logs argv.
  # shellcheck disable=SC2016   # stub source written literally; its $ must expand in the stub, not here
  cc_stub "$D/bin" kitty "$(printf '#!/bin/bash\necho "$*" >> %q\n[ -f %q ] && exit "$(cat %q)"\ncat %q\n' \
    "$D/kitty-calls.log" "$D/kitty.rc" "$D/kitty.rc" "$D/ls.json")"
  cc_stub "$D/bin" page "$(printf '#!/bin/bash\necho "$*" >> %q\n' "$D/page-calls.log")"
  export CC_PANE_CENSUS_SOCKET_BIN="$D/bin/sock" CC_PANE_CENSUS_KITTY_BIN="$D/bin/kitty" CC_PANE_CENSUS_PAGE_BIN="$D/bin/page"
  WINS=""
}

# win <id> <cmdline json array> [<cmdline json array>…] — one kitty window with those foreground processes
win() { local id="$1" fp=""; shift; for c in "$@"; do fp="$fp${fp:+,}{\"pid\":9,\"cmdline\":$c}"; done
        WINS="$WINS${WINS:+,}{\"id\":$id,\"foreground_processes\":[$fp]}"; }
ls_write() { printf '[{"id":1,"tabs":[{"id":1,"windows":[%s]}]}]\n' "$WINS" > "$D/ls.json"; }
reg() { printf '[%s] registered session=%s pid=7 tty=%s pane=%s%s\n' "$(date -r "${3:-$((KST + 60))}" '+%Y-%m-%d %H:%M:%S')" \
          "00000000-0000-0000-0000-0000000000$(printf %02d "$1")" "${2:-ttys001}" "$1" "${4:-}" >> "$D/wd.log"; }
rec() { printf '{"rc":0,"claude_started":true,"launch_sha":"","ts":%s%s}\n' "${3:-$((NOW - 100))}" "${2:+,\"tail\":\"$2\"}" > "$D/exit/$1.json"; }
fired() { printf '{"paneUUID":"%s","firedAt":"%s"}\n' "$1" "$(TZ=UTC date -r "${2:-$((KST + 60))}" +%Y-%m-%dT%H:%M:%SZ)" > "$D/fired/$1.json"; }
census() { run /bin/bash "$CENSUS" "$@"; }
row() { tail -1 "$D/census.jsonl"; }
RUNNER='["/bin/bash","/Users/x/.claude/bin/cc-pane-runner"]'

@test "every class: running, held, deciding, kept[r], unexplained and operator, from foreground and tail" {
  reg 10; win 10 '["claude","--resume","x"]'
  reg 11; win 11 "$RUNNER" '["/bin/sleep","10"]'; rec 11 hold:fs
  reg 12; win 12 "$RUNNER"; rec 12
  reg 13; win 13 '["-zsh"]'; rec 13 keep:crash
  reg 14; win 14 '["/bin/zsh","-i"]'; rec 14 closed
  fired 15; win 15 '["-zsh"]'
  reg 16; win 16 '["-zsh"]'
  reg 18; win 18 '["bash","some-script"]'
  ls_write
  census
  [ "$status" -eq 0 ]
  r="$(row)"
  [ "$(jq -c .counts <<<"$r")" = '{"running":2,"held":1,"deciding":1,"kept":1,"unexplained":2,"operator":1}' ]
  [ "$(jq -c .kept <<<"$r")" = '{"crash":1}' ]
  [ "$(jq -c '.held[0]' <<<"$r")" = '{"pane":11,"age_s":100,"tail":"hold:fs"}' ]
  [ "$(jq -c '[.unexplained[].pane]' <<<"$r")" = '[14,15]' ]
  [ "$(jq -r '.unexplained[1].why' <<<"$r")" = "no exit record" ]
  [ "$(jq -r '.metric, .population, .windows, .kitty_pid, .readable' <<<"$r" | tr '\n' ' ')" = "2 8 8 610 true " ]
  [ "$(cat "$D/kitty-calls.log")" = "@ --to unix:/tmp/kitty-610 ls" ]   # read-only: one ls, nothing else
}

# mutant: count every bare shell — the operator's own window and an older kitty's records would count.
@test "outside the population: an operator window, an older kitty's registration, a headless tty=none run" {
  win 17 '["-zsh"]'
  reg 20 ttys001 $((KST - 600)); win 20 '["-zsh"]'; rec 20 closed
  reg 21 none; win 21 '["-zsh"]'
  ls_write
  census
  r="$(row)"
  [ "$(jq -r '.population, .windows, .metric' <<<"$r" | tr '\n' ' ')" = "0 3 0 " ]
}

@test "a record from an older kitty under the same id is not this pane's: a registered bare shell is operator" {
  reg 19; win 19 '["-zsh"]'; rec 19 keep:crash $((KST - 600))
  reg 22 ttys002 $((KST + 60)) " teammate=m1@team"; win 22 '["-zsh"]'; rec 22 keep:fallback
  ls_write
  census
  r="$(row)"
  [ "$(jq -r '.counts.operator, .counts.kept, .counts.unexplained' <<<"$r" | tr '\n' ' ')" = "1 0 1 " ]
  [ "$(jq -r '.unexplained[0] | "\(.pane) \(.why)"' <<<"$r")" = "22 keep:fallback" ]
}

@test "a runner whose record predates its own launch is still running its command, not deciding" {
  rec 23 closed; sleep 1; : > "$D/exit/23.launch"
  win 23 "$RUNNER" '["claude-wrapper"]'
  ls_write
  census
  [ "$(jq -r '.counts.running, .counts.deciding, .population' <<<"$(row)" | tr '\n' ' ')" = "1 0 1 " ]
}

@test "an unexplained pane pages once, and only from its second tick running" {
  reg 14; win 14 '["-zsh"]'; rec 14 closed; ls_write
  census
  [ ! -e "$D/page-calls.log" ]
  census
  [ "$(grep -c . "$D/page-calls.log")" -eq 1 ]
  grep -q -- "--source pane-census pane-census: pane 14 is a bare shell nobody can account for (tail=closed)" "$D/page-calls.log"
  census
  [ "$(grep -c . "$D/page-calls.log")" -eq 1 ]
  [ "$(grep -c . "$D/census.jsonl")" -eq 3 ]
}

@test "a pane unexplained on one tick and gone on the next is never paged" {
  reg 14; win 14 '["-zsh"]'; rec 14 closed; ls_write
  census
  WINS=""; win 14 '["claude"]'; ls_write
  census
  WINS=""; win 14 '["-zsh"]'; ls_write
  census
  run test -e "$D/page-calls.log"; [ "$status" -eq 1 ]
}

@test "a hold older than 6 h pages once and counts in the metric; a younger one does neither" {
  reg 11; win 11 "$RUNNER"; rec 11 hold:fs $((NOW - 30000))
  reg 12; win 12 "$RUNNER"; rec 12 hold:unreadable $((NOW - 3600))
  ls_write
  census; census
  [ "$(jq -r '.holds_over_max, .metric' <<<"$(row)" | tr '\n' ' ')" = "1 1 " ]
  [ "$(grep -c . "$D/page-calls.log")" -eq 1 ]
  grep -q "pane 11 has been held for 8 h" "$D/page-calls.log"
}

@test "a kitty that does not answer is an unreadable row and pages nothing" {
  reg 14; rec 14 closed; echo 124 > "$D/kitty.rc"
  census; census
  [ "$status" -eq 0 ]
  [ "$(jq -c '{readable, why, kitty_pid}' <<<"$(row)")" = '{"readable":false,"why":"kitty @ ls did not answer","kitty_pid":610}' ]
  run test -e "$D/page-calls.log"; [ "$status" -eq 1 ]
}

@test "no live kitty socket is an unreadable row, kitty never asked" {
  cc_stub "$D/bin" sock "$(printf '#!/bin/bash\nexit 4\n')"
  census
  [ "$status" -eq 0 ]
  [ "$(jq -r .why <<<"$(row)")" = "no live kitty socket" ]
  run test -e "$D/kitty-calls.log"; [ "$status" -eq 1 ]
}

@test "--dry-run prints the row and the counts, and writes and pages nothing" {
  reg 14; win 14 '["-zsh"]'; rec 14 closed; ls_write
  census --dry-run; census --dry-run
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "windows=1 population=1 running=0 held=0 deciding=0 kept=0 unexplained=1 operator=0 metric=1" ]
  [ "$(jq -r .metric <<<"${lines[0]}")" = 1 ]
  run test -e "$D/census.jsonl"; [ "$status" -eq 1 ]
  run test -e "$D/state"; [ "$status" -eq 1 ]
}

@test "one row per tick: a second run inside the interval (a SessionEnd drain) writes nothing" {
  reg 14; win 14 '["-zsh"]'; rec 14 closed; ls_write
  CC_PANE_CENSUS_MIN_INTERVAL_S=120 census
  CC_PANE_CENSUS_MIN_INTERVAL_S=120 census
  [ "$(grep -c . "$D/census.jsonl")" -eq 1 ]
}

@test "a page marker from an older kitty is dropped; this kitty's stays" {
  mkdir -p "$D/state"; : > "$D/state/paged-500-14"; : > "$D/state/paged-610-14"; : > "$D/state/paged-hold-500-3"
  win 1 '["claude"]'; ls_write
  census
  run test -e "$D/state/paged-500-14"; [ "$status" -eq 1 ]
  run test -e "$D/state/paged-hold-500-3"; [ "$status" -eq 1 ]
  [ -e "$D/state/paged-610-14" ]
}
