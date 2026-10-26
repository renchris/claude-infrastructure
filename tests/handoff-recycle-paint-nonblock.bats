#!/usr/bin/env bats
# The __recycle watcher's failure banner never block-opens the pane's tty by path (lockup incident
# 2026-10-25, RCA rank 1: an opener that sleeps in ptsopen's carrier wait is the precondition of the
# /dev wedge; lane F's sweep flagged rcy_pane_paint's `printf … > "$TTY_PATH"`).
#
# The painter now opens O_WRONLY|O_NONBLOCK|O_NOCTTY in a python3 -I child the watcher polls for at
# most 10 s and then abandons. A FIFO with no reader is the stand-in for a tty that will never answer:
# a blocking open of it for writing sleeps forever, exactly like the carrier wait, while a
# non-blocking one fails at once with ENXIO. The pre-fix painter is replayed from trunk's bytes
# (git show of the immutable pre-fix sha abda1d5a1), so the RED half is the real artifact, not a paraphrase of it.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # the subject file names these machine seams; pin them though the painter never reads them
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/claude-accounts-heal-"
  unset CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE CC_PANE_CMD
  CMDFILE="$BATS_TEST_TMPDIR/cmd.txt"; printf 'claude --resume x\n' > "$CMDFILE"
  export CMDFILE
  PRE_FIX=abda1d5a1   # trunk just before the non-blocking painter; immutable, unlike origin/main
}

painter() { # $1=file holding handoff-fire.sh → prints rcy_pane_paint's definition
  awk '/^  rcy_pane_paint\(\) \{/ { p = 1 } p { print } p && /^  }$/ { exit }' "$1"
}

paint() { # $1=painter source $2=TTY_PATH → runs one paint under a hard 30 s bound
  TTY_PATH="$2" /usr/bin/perl -e 'alarm 30; exec @ARGV' -- /bin/bash -c 'eval "$1"; rcy_pane_paint boot-failed "the successor did not start"' _ "$1"
}

@test "01 the painter returns within its bound on a tty that never answers (FIFO, no reader)" {
  local src fifo t0 rc=0
  src="$(painter "$REPO/scripts/handoff-fire.sh")"
  [ -n "$src" ] || { echo "rcy_pane_paint moved — this case asserts over nothing"; false; }
  ! printf '%s\n' "$src" | grep -v '^[[:space:]]*#' | grep -E '> "\$TTY_PATH"' >/dev/null || { echo "a by-path redirect into the tty is back"; false; }
  fifo="$BATS_TEST_TMPDIR/tty.fifo"; mkfifo "$fifo"
  t0="$(date +%s)"
  paint "$src" "$fifo" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { echo "painter rc=$rc after $(( $(date +%s) - t0 ))s (142 = it blocked until the alarm)"; false; }
  [ $(( $(date +%s) - t0 )) -lt 25 ] || false
}

@test "02 RED CONTROL: the pre-fix painter (abda1d5a1) blocks on the same FIFO until the alarm" {
  local old fifo rc=0
  old="$BATS_TEST_TMPDIR/handoff-fire.main.sh"
  git -C "$REPO" show "$PRE_FIX:scripts/handoff-fire.sh" > "$old" 2>/dev/null || skip "pre-fix sha $PRE_FIX unreadable"
  grep -E '> "\$TTY_PATH"' <(painter "$old") >/dev/null || { echo "the pinned pre-fix painter has no by-path redirect — wrong sha"; false; }
  fifo="$BATS_TEST_TMPDIR/tty.fifo"; mkfifo "$fifo"
  TTY_PATH="$fifo" /usr/bin/perl -e 'alarm 5; exec @ARGV' -- /bin/bash -c 'eval "$1"; rcy_pane_paint boot-failed x' _ "$(painter "$old")" \
    >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 142 ] || { echo "the pre-fix painter returned rc=$rc instead of blocking — the FIFO stand-in proves nothing"; false; }
}

@test "03 control: a writable target still gets the whole banner" {
  local src out="$BATS_TEST_TMPDIR/tty.txt"
  src="$(painter "$REPO/scripts/handoff-fire.sh")"
  : > "$out"
  paint "$src" "$out" >/dev/null 2>&1
  grep -q 'HANDOFF RECYCLE FAILED (boot-failed)' "$out" || { cat "$out"; false; }
  grep -q 'claude --resume x' "$out" || false
}
