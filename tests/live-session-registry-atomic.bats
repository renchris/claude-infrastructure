#!/usr/bin/env bats
# hooks/live-session-registry.sh — the row must be written ATOMICALLY (a15/D5).
#
# WHY THIS SUITE EXISTS. The register path wrote `printf … > "$REG_DIR/$base"`. `>` is O_TRUNC: the
# file is emptied by one syscall and refilled by a later one. worktree-gc reads that row with
# `cut -f2` to get the session's pid; a read landing in the gap yields an empty pid, `kill -0 ""`
# fails, and a LIVE session's worktree is classified dead and REAPED. The file's own header says it
# exists to eliminate exactly that single-bad-read flakiness — so the non-atomic write re-introduced
# the bug it was written to kill, at one-printf width.
#
# WHAT IS ASSERTED, and why the main assertion is the INODE. A true interleaving race is not
# deterministically reproducible from a shell, so proving "no reader ever sees the gap" by racing is
# probabilistic (test 4 does hammer it, and is honest about being a probabilistic backstop). The
# DETERMINISTIC property is the one that makes the gap structurally impossible: the target must be
# replaced by an atomic RENAME, never modified in place. A rename swaps in a different file, so the
# target's inode CHANGES; a truncate-write keeps the same inode. Inode-change is therefore a direct,
# non-flaky witness of the mechanism — and it goes RED against the pre-fix line (verified by
# reverting the fix and re-running: test 2 fails with identical inodes).
#
# Hermetic: $HOME is fixtured (REG_DIR and the reapable-worktree gate are both $HOME-derived), so no
# real ~/.reso state is read or written.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/live-session-registry.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  WT="$HOME/Development/.worktrees/wt-testbed"
  REG="$HOME/.reso/live-sessions"
  mkdir -p "$WT" "$REG"
}

# fire the hook as SessionStart for the fixtured worktree
fire() { # $1=sid
  printf '{"hook_event_name":"SessionStart","cwd":"%s","session_id":"%s"}' "$WT" "${1:-sid-1}" \
    | bash "$HOOK"
}

inode() { ls -i "$1" 2>/dev/null | awk '{print $1}'; }

@test "1: register writes the row (pid, sid, cwd) — the fix did not break the write" {
  fire "sid-alpha"
  [ -f "$REG/wt-testbed" ] || { echo "no registry row written"; false; }
  run cut -f2 "$REG/wt-testbed"
  [ "$output" = "sid-alpha" ] || { echo "sid field: got '$output'"; false; }
  run cut -f3 "$REG/wt-testbed"
  [ "$output" = "$WT" ] || { echo "cwd field: got '$output'"; false; }
  # field 1 is the claude-ancestor pid; under bats there is no claude ancestor, so it falls back to
  # $PPID — assert only that it is a non-empty integer, which is what `kill -0` consumes.
  run cut -f1 "$REG/wt-testbed"
  [[ "$output" =~ ^[0-9]+$ ]] || { echo "pid field not an integer: '$output'"; false; }
}

@test "2: a re-register REPLACES the row by rename (inode changes) — never truncates in place" {
  fire "sid-first"
  local i1 i2
  i1="$(inode "$REG/wt-testbed")"
  [ -n "$i1" ] || { echo "could not stat the first row"; false; }
  fire "sid-second"
  i2="$(inode "$REG/wt-testbed")"
  [ -n "$i2" ] || { echo "could not stat the second row"; false; }
  # THE DISCRIMINATOR: same inode ⇒ the file was modified in place ⇒ an O_TRUNC gap exists ⇒ the
  # reaper can read an empty pid. Different inode ⇒ atomic rename ⇒ readers see old or new, never
  # partial. RED-proven: with `> "$REG_DIR/$base"` restored, i1 == i2 and this test fails.
  [ "$i1" != "$i2" ] || {
    echo "row was written IN PLACE (inode $i1 unchanged) — O_TRUNC gap present, reader can see an empty pid"
    false
  }
  run cut -f2 "$REG/wt-testbed"
  [ "$output" = "sid-second" ] || { echo "replacement row wrong: '$output'"; false; }
}

@test "3: no .tmp litter is left behind in the registry dir" {
  fire "sid-x"; fire "sid-y"; fire "sid-z"
  # the tmp name is ".<base>.<pid>" — any survivor means a failure path leaked it
  run bash -c "ls -A '$REG' | grep -c '^\\.wt-testbed\\.' || true"
  [ "$output" = "0" ] || { echo "leaked $output tmp file(s): $(ls -A "$REG")"; false; }
}

@test "4: a concurrent reader never observes an empty or partial row (probabilistic backstop)" {
  # Honest label: this is the real-world failure shape but it is NOT the deterministic proof —
  # test 2 is. Kept because it asserts the INVARIANT the reaper depends on (a row always has a
  # non-empty pid field), and it can only ever fail for a real reason.
  fire "sid-seed"
  local bad=0 i
  ( for i in $(seq 1 40); do fire "sid-$i" >/dev/null 2>&1; done ) &
  local writer=$!
  for i in $(seq 1 200); do
    if [ -f "$REG/wt-testbed" ]; then
      p="$(cut -f1 "$REG/wt-testbed" 2>/dev/null)"
      case "$p" in ''|*[!0-9]*) bad=$((bad + 1)) ;; esac
    fi
  done
  wait "$writer" 2>/dev/null || true
  [ "$bad" -eq 0 ] || { echo "reader saw $bad empty/partial pid field(s) — the O_TRUNC gap is observable"; false; }
}
