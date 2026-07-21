#!/usr/bin/env bats
# lr-reset-poller.sh — the session-sprawl consolidation seam (incident 2026-07-21).
#
# Scope: ONLY the consolidation behaviour added on 2026-07-21. The poller's detection/parking and
# monthly-spend paths are unchanged and not re-tested here; lr-select's own policy has 21 cases in
# lr-select.bats. What this file pins is the SEAM:
#
#   1. Parked candidates whose reset has passed are routed through lr-select ONCE, before any fire.
#   2. Losers are LISTED and retired for THIS limit event — moved to resumed/, never deleted, and
#      never left parked (leaving them parked re-elects them next tick once the winner is running,
#      which is sprawl at 10-minute cadence rather than 2 seconds).
#   3. MAX_PER_RUN becomes the selector's TOTAL ceiling, so the pre-existing bound is preserved.
#   4. A missing selector FAILS CLOSED — the poller fires nothing rather than falling back to the
#      per-tick cap, because that fallback is the incident itself.
#
# Isolation: HOME is redirected, so the poller's store scan finds nothing and only the pre-seeded
# parked/ dir drives the run. osascript/tmux/pgrep are PATH-stubbed so no test can open a window.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  PARKED="$STATE/parked"; RESUMED="$STATE/resumed"; LOG="$STATE/poller.log"
  mkdir -p "$PARKED" "$RESUMED" "$HOME/bin"

  # PATH stubs: nothing in this suite may open a window, spawn a pane, or read real quota.
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  for b in osascript tmux pgrep; do printf '#!/bin/bash\nexit 1\n' > "$STUBS/$b"; chmod +x "$STUBS/$b"; done
  export PATH="$STUBS:$PATH"

  # stub lr-select: log the invocation; emit the winner TSV written to .winners (empty = none).
  export LR_SELECT_BIN="$BATS_TEST_TMPDIR/stub-select"
  cat > "$LR_SELECT_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$0.log"
[ -f "$0.winners" ] && cat "$0.winners"
exit 0
SH
  chmod +x "$LR_SELECT_BIN"
}

# park <sid> <acct> <cwd> [reset-iso]  — a parked session whose reset has already passed.
park() {
  local sid="$1" acct="$2" cwd="$3" reset="${4:-2020-01-01T00:00:00Z}"
  mkdir -p "$cwd"
  printf '{"sid":"%s","acct":"%s","cfg":"%s/.claude-next","cwd":"%s","kind":"session","reset_at_utc":"%s","parked_at":"%s"}\n' \
    "$sid" "$acct" "$HOME" "$cwd" "$reset" "2026-07-21T00:00:00Z" > "$PARKED/$sid.json"
}

@test "ready candidates are routed through lr-select before any firing" {
  park s1 next "$BATS_TEST_TMPDIR/wt/a"
  park s2 next "$BATS_TEST_TMPDIR/wt/a"
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  grep -q -- '--candidate next:s1:' "$LR_SELECT_BIN.log"
  grep -q -- '--candidate next:s2:' "$LR_SELECT_BIN.log"
  grep -q -- '--max-per-worktree 1' "$LR_SELECT_BIN.log"
  grep -q -- '--max-total 4'        "$LR_SELECT_BIN.log"   # MAX_PER_RUN becomes the TOTAL ceiling
}

@test "a parked session whose reset has NOT passed is not offered as a candidate" {
  park future next "$BATS_TEST_TMPDIR/wt/a" "2099-01-01T00:00:00Z"
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  [ ! -f "$LR_SELECT_BIN.log" ] || ! grep -q 'future' "$LR_SELECT_BIN.log"
  [ -f "$PARKED/future.json" ]                              # still parked, untouched
}

@test "losers are LISTED and retired for this event — moved to resumed/, never deleted" {
  park win  next "$BATS_TEST_TMPDIR/wt/shared"
  park lose next "$BATS_TEST_TMPDIR/wt/shared"
  printf 'next\twin\t%s/wt/shared\t\n' "$BATS_TEST_TMPDIR" > "$LR_SELECT_BIN.winners"
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  grep -q 'LISTED lose' "$LOG"
  [ ! -f "$PARKED/lose.json" ]                              # not left parked (would re-elect next tick)
  [ -f "$RESUMED/lose.json" ]                               # retired for THIS event, not deleted
}

@test "the LISTED log carries lr-select's REAL reason, not an assumed one" {
  # A non-winner may have lost the per-worktree contest OR been filtered outright (no transcript,
  # teammate, cwd gone). Those are different facts; the log must not misattribute one as the other.
  park mate next "$BATS_TEST_TMPDIR/wt/shared"
  cat > "$LR_SELECT_BIN" <<'SH'
#!/bin/bash
while [ $# -gt 0 ]; do case "$1" in --json) J="$2"; shift 2 ;; *) shift ;; esac; done
printf '{"winners":[],"listed":[],"filtered":[{"sid":"mate","reason":"teammate-session (lead-owned recovery)"}]}\n' > "$J"
SH
  chmod +x "$LR_SELECT_BIN"
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  grep -q 'LISTED mate .* teammate-session (lead-owned recovery)' "$LOG"
  ! grep -q 'LISTED mate .* not the per-worktree winner' "$LOG"
}

@test "consolidation is logged with the counts, never silent" {
  park a next "$BATS_TEST_TMPDIR/wt/shared"
  park b next "$BATS_TEST_TMPDIR/wt/shared"
  park c next "$BATS_TEST_TMPDIR/wt/shared"
  printf 'next\ta\t%s/wt/shared\t\n' "$BATS_TEST_TMPDIR" > "$LR_SELECT_BIN.winners"
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  grep -q 'CONSOLIDATED 3 ready → 1 winner' "$LOG"
}

@test "the winner survives consolidation and reaches the fire path" {
  park win next "$BATS_TEST_TMPDIR/wt/shared"
  printf 'next\twin\t%s/wt/shared\t\n' "$BATS_TEST_TMPDIR" > "$LR_SELECT_BIN.winners"
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  ! grep -q 'LISTED win' "$LOG"                             # not consolidated away
  grep -q 'READY win' "$LOG"                                # reached the notify/fire branch
}

@test "a missing selector fails CLOSED — nothing fired, nothing consolidated away" {
  park s1 next "$BATS_TEST_TMPDIR/wt/a"
  park s2 next "$BATS_TEST_TMPDIR/wt/a"
  export LR_SELECT_BIN="$BATS_TEST_TMPDIR/does-not-exist"
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]                                       # daemon never crashes (fail-open process)
  grep -q 'ERROR lr-select missing' "$LOG"
  [ -f "$PARKED/s1.json" ]                                  # still parked — recoverable, not lost
  [ -f "$PARKED/s2.json" ]
  [ ! -f "$RESUMED/s1.json" ]
}

@test "LR_POLLER_MAX_PER_WORKTREE opts out of the 1-per-worktree default explicitly" {
  park s1 next "$BATS_TEST_TMPDIR/wt/a"
  export LR_POLLER_MAX_PER_WORKTREE=3
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  grep -q -- '--max-per-worktree 3' "$LR_SELECT_BIN.log"
}

@test "the kill switch still short-circuits the whole poller" {
  park s1 next "$BATS_TEST_TMPDIR/wt/a"
  export LR_POLLER_DISABLED=1
  run bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  [ ! -f "$LR_SELECT_BIN.log" ]
}
