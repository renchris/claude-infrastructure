#!/usr/bin/env bats
# bin/cc-pane-close run from OUTSIDE kitty — the launchd drainer, the setsid'd crash-watchdog daemons,
# the detached SessionEnd drain (docs/research/husk-panes-2026-10-22/round2-2026-10-23/, RC1/RC2/RC7).
#
# None of those callers carries a KITTY_* variable or has kitty among its ancestors, so the it2 shim
# routes an UNPINNED call to the iTerm2 CLI, which exits 2 ("Not running inside iTerm2"). The close at
# :461 was already pinned (CC_TERM=kitty + the socket); the listing and the remote-control probe were
# not, so every background run read "remote control is down" and refused panes 144-147 and 165 8-44
# times while an in-kitty run of the same closer said would-close. Every stub here behaves like the
# real shim: it answers only a call pinned with CC_TERM=kitty. The waves before this were tested only
# from inside kitty, where the defect cannot show (RC7), so every test unsets KITTY_*/CC_TERM.
#
# RC2: hooks/lead-crash-watchdog.sh appends ` teammate=<id>` to a teammate's registration line
# (b6bf10c0c); readers anchored on `pane=N` at end of line never saw a teammate's registration.
# shellcheck disable=SC2030,SC2031,SC2016  # per-test env exports are deliberate; stub bodies are literal

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CLOSE="${CC_PANE_CLOSE_UNDER_TEST:-$REPO/bin/cc-pane-close}"
  F="$BATS_TEST_TMPDIR/fix"; S="$BATS_TEST_TMPDIR/stub"; mkdir -p "$F" "$S"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset KITTY_WINDOW_ID KITTY_PID KITTY_LISTEN_ON CC_TERM CC_TERM_KITTY_TO CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
  export CC_PANE_CLOSE_KITTY_PID=610 CC_PANE_CLOSE_REMOTE=on CC_PANE_CLOSE_SETTLE_S=1 CC_PANE_CLOSE_REAP_S=1
  export CC_PANE_CLOSE_WATCHDOG_LOG="$F/watchdog.log" CC_PANE_CLOSE_LOG="$F/close.jsonl"
  export CC_PANE_CLOSE_STORES="$F/store" CC_CUSTODY_DIR="$F/custody" FIX="$F"
  export CC_PANE_CLOSE_PS_BIN="$S/ps" CC_PANE_CLOSE_KILL_BIN="$S/kill" CC_PANE_CLOSE_IT2="$S/it2"
  export CC_PANE_CLOSE_EXIT_DIR="$F/pane-exit" CC_PANE_CLOSE_FIND_BIN="$S/cc-find"
  export CC_PANE_CLOSE_HANDOFFS_LOG="$F/handoffs.jsonl" CC_KITTY_FS_GUARD="$S/fs-guard"
  cc_stub "$S" ps '#!/bin/bash
for a; do prev="$a"; done
case "$2" in lstart=) cat "$FIX/lstart.$prev" 2>/dev/null ;; stat=) if [ -f "$FIX/lstart.$prev" ]; then echo Ss; fi ;; tty=) cat "$FIX/ttyof.$prev" 2>/dev/null ;; *) cat "$FIX/tty.$prev" 2>/dev/null ;; esac
exit 0'
  cc_stub "$S" kill '#!/bin/bash
echo "$*" >> "$FIX/kill.log"
rm -f "$FIX/lstart.$ROOT"'
  cc_stub "$S" cc-find '#!/bin/bash
exit 0'
  # it2, as the real shim behaves for a caller outside kitty: an UNPINNED call goes to the iTerm2 CLI
  # and fails; a pinned one reaches kitty. KITTY_DEAF=1 makes kitty itself not answer.
  cc_stub "$S" it2 '#!/bin/bash
echo "it2 CC_TERM=${CC_TERM:-} TO=${CC_TERM_KITTY_TO:-} $*" >> "$FIX/it2.log"
if [ "${CC_TERM:-}" != kitty ]; then echo "Not running inside iTerm2 or Python API not enabled" >&2; exit 2; fi
if [ "${KITTY_DEAF:-0}" = 1 ]; then echo "Error: Failed to connect to unix:/tmp/kitty-610: connection refused" >&2; exit 1; fi
case "$1 $2" in "session list") cat "$FIX/klist.json"; exit 0 ;; "session close") rm -f "$FIX/lstart.$ROOT"; exit 0 ;; esac
exit 1'
  # the fullscreen guard: argv to guard.log; GUARD_MSG on stderr; rc GUARD_RC (the --any-fs arm: ANYFS_RC)
  cc_stub "$S" fs-guard '#!/bin/bash
echo "$*" >> "$FIX/guard.log"
case "$1" in --any-fs) exit "${ANYFS_RC:-3}" ;; esac
[ -z "${GUARD_MSG:-}" ] || echo "$GUARD_MSG" >&2
exit "${GUARD_RC:-0}"'
  NOW=$(date +%s); K=$((NOW - 36000)); REG=$((NOW - 7200))
  lst 610 "$K"
  SID="aaaaaaaa-1111-2222-3333-444444444444"
  CWD="$BATS_TEST_TMPDIR/work"; mkdir -p "$CWD"; git -C "$CWD" init -q
  mkdir -p "$F/store/projects/p" "$F/pane-exit"
  printf '[]\n' > "$F/klist.json"
}

lst() { date -u -r "$2" '+%a %b %d %T %Y' > "$FIX/lstart.$1"; }
wts() { date -r "$1" '+%Y-%m-%d %H:%M:%S'; }
window() { # $1=pane $2=window pid $3=tty $4=window start epoch — kitty lists it, ps shows login+zsh
  printf '[{"id":"%s","pid":%s,"cwd":"/x","title":"zsh"}]\n' "$1" "$2" > "$FIX/klist.json"
  printf '%s\n' "$3" > "$FIX/ttyof.$2"
  printf '%s 610 /usr/bin/login\n%s %s /bin/zsh\n' "$2" "$(($2 + 1))" "$2" > "$FIX/tty.$3"
  lst "$2" "$4"; lst "$(($2 + 1))" "$4"
  export ROOT="$2"
}
exit_rec() { printf '{"rc":%s,"claude_started":%s,"launch_sha":"abc123def4567890","ts":%s}\n' "$2" "$3" "$4" > "$FIX/pane-exit/$1.json"; }
teammate_tx() { printf '{"type":"user","teamName":"session-x","cwd":"%s","message":{"role":"user","content":"hi"}}\n' "$CWD" > "$FIX/store/projects/p/$SID.jsonl"; }

# ── C1: the listing and the remote-control probe are pinned to kitty ───────────────────────────────
# RED on 67b74ef87: the unpinned listing reads the iTerm2 failure as an empty list, and the
# never-launched arm refuses "kitty remote control does not name this pane's window".
@test "C1: a never-launched pane is closed from outside kitty — the listing is pinned to this kitty's socket" {
  window 145 6000 ttys070 $((NOW - 600)); exit_rec 145 124 false $((NOW - 300))
  run "$CLOSE" --pane 145
  [ "$status" -eq 0 ] || { echo "$output"; cat "$FIX/it2.log"; false; }
  [[ "$output" == *"pane 145: CLOSED"*"via kitty remote control"* ]] || { echo "$output"; false; }
  grep -q '^it2 CC_TERM=kitty TO=unix:/tmp/kitty-610 session list --json' "$FIX/it2.log" || { cat "$FIX/it2.log"; false; }
  ! grep -q '^it2 CC_TERM= ' "$FIX/it2.log" || { cat "$FIX/it2.log"; false; }
}

@test "C1: a registered teammate's pane closes by remote control from outside kitty, not by the blind-HUP fallback" {
  window 69 5000 ttys057 $((REG - 4)); teammate_tx
  printf '[%s] registered session=%s pid=7000 tty=ttys057 pane=69\n' "$(wts "$REG")" "$SID" > "$FIX/watchdog.log"
  run "$CLOSE" --pane 69
  [ "$status" -eq 0 ] || { echo "$output"; cat "$FIX/it2.log"; false; }
  [[ "$output" == *"pane 69: CLOSED"*"via kitty remote control"* ]] || { echo "$output"; false; }
  [ ! -e "$FIX/kill.log" ]
  ! grep -q -- '--any-fs' "$FIX/guard.log" || { cat "$FIX/guard.log"; false; }
}

@test "C1: listing read and the pane absent ⇒ ALREADY CLOSED (kitty never reuses a window id), nothing asked or sent" {
  printf '[{"id":"12","pid":4000,"cwd":"/x","title":"zsh"}]\n' > "$FIX/klist.json"
  exit_rec 146 124 false $((NOW - 300))
  run "$CLOSE" --pane 146
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"pane 146: ALREADY CLOSED"*"does not hold this pane"* ]] || { echo "$output"; false; }
  [ ! -e "$FIX/guard.log" ]; [ ! -e "$FIX/kill.log" ]
  ! grep -q 'session close' "$FIX/it2.log" || false
}

@test "C1: a listing that did not answer is said as such, with the it2 error, never as 'does not name this pane'" {
  window 147 6000 ttys070 $((NOW - 600)); exit_rec 147 124 false $((NOW - 300))
  KITTY_DEAF=1 run "$CLOSE" --pane 147
  [ "$status" -eq 1 ]
  [[ "$output" == *"pane 147: REFUSED"*"kitty's window list did not answer"*"connection refused"* ]] || { echo "$output"; false; }
  [[ "$output" != *"does not name this pane"* ]] || false
  [ ! -e "$FIX/kill.log" ]
}

@test "C1: the guard's refused-fs verdict is named in the refusal; an unreadable guard read is said as kitty not answering" {
  window 165 6000 ttys070 $((NOW - 600)); exit_rec 165 124 false $((NOW - 300))
  GUARD_RC=3 GUARD_MSG="kitty-fullscreen-guard: refused (refused-fs) kitty window 165: panes 1, FS" run "$CLOSE" --pane 165
  [ "$status" -eq 1 ]
  [[ "$output" == *"pane 165: REFUSED — the fullscreen guard refused (--scope pane --mode refuse): refused-fs — this is the last pane of a fullscreen OS window"* ]] || { echo "$output"; false; }
  GUARD_RC=3 GUARD_MSG="kitty-fullscreen-guard: refused (kitten-failed) kitty window 165: kitty @ kitten rc=1" run "$CLOSE" --pane 165
  [ "$status" -eq 1 ]
  [[ "$output" == *"pane 165: REFUSED — the fullscreen guard refused (--scope pane --mode refuse): kitten-failed — it could not read this pane's window (kitty did not answer it)"* ]] || { echo "$output"; false; }
  ! grep -q 'session close' "$FIX/it2.log" || false
}

# ── C2: a teammate's registration carries a trailing ` teammate=<id>` ──────────────────────────────
# RED on 67b74ef87: `*" pane=$pane")` never matched the suffixed line, so the pane had no identity.
@test "C2: a registration line ending in ' teammate=<id>' is this pane's identity" {
  window 144 5000 ttys057 $((REG - 4)); teammate_tx
  printf '[%s] registered session=%s pid=7000 tty=ttys057 pane=144 teammate=tm2-H11@session-x\n' "$(wts "$REG")" "$SID" > "$FIX/watchdog.log"
  run "$CLOSE" --pane 144
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"pane 144: CLOSED — session aaaaaaaa, team member aaaaaaaa left a clean cwd"* ]] || { echo "$output"; false; }
}

@test "C2 CONTROL: pane=14 is not pane=144's registration, suffix or not" {
  window 144 5000 ttys057 $((REG - 4)); teammate_tx
  printf '[%s] registered session=%s pid=7000 tty=ttys057 pane=14 teammate=tm2-H11@session-x\n' "$(wts "$REG")" "$SID" > "$FIX/watchdog.log"
  run "$CLOSE" --pane 144
  [ "$status" -eq 1 ]
  [[ "$output" == *"no session registration"* ]] || { echo "$output"; false; }
}

# Gate 3 accepts ANY transcript carrying teamName — retired or crashed — so gate 4 (no uncommitted
# change in its cwd) is the only thing standing between a crashed teammate's work and the close
# (skeptics.md FX2). Pinned so the suffix fix can never be read as "teammates close unconditionally".
@test "C2: a teammate pane over uncommitted work is refused — gate 4 protects a crashed teammate" {
  window 144 5000 ttys057 $((REG - 4)); teammate_tx
  printf '[%s] registered session=%s pid=7000 tty=ttys057 pane=144 teammate=tm2-H11@session-x\n' "$(wts "$REG")" "$SID" > "$FIX/watchdog.log"
  echo wip > "$CWD/half-done.txt"
  run "$CLOSE" --pane 144
  [ "$status" -eq 1 ]
  [[ "$output" == *"pane 144: REFUSED"*"1 uncommitted change"* ]] || { echo "$output"; false; }
  ! grep -q 'session close' "$FIX/it2.log" || false
}

# moved_live's reader (the sed over later registrations) had the same end-of-line anchor. RED on
# 67b74ef87: the teammate-suffixed re-registration is unseen and the refusal reads "nothing says".
@test "C2: a later re-registration in another pane as a teammate is seen — refused as moved (STRANDED), not 'nothing says'" {
  window 69 5000 ttys057 $((REG - 4))
  printf '{"type":"user","cwd":"%s","message":{"role":"user","content":"x"}}\n' "$CWD" > "$FIX/store/projects/p/$SID.jsonl"
  { printf '[%s] registered session=%s pid=7000 tty=ttys057 pane=69\n' "$(wts "$REG")" "$SID"
    printf '[%s] registered session=%s pid=7100 tty=ttys060 pane=442 teammate=tm2-H11@session-x\n' "$(wts $((REG + 600)))" "$SID"; } > "$FIX/watchdog.log"
  run "$CLOSE" --pane 69
  [ "$status" -eq 1 ]
  [[ "$output" == *"re-registered in pane 442"*"STRANDED"* ]] || { echo "$output"; false; }
}
