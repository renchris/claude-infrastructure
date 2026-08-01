#!/usr/bin/env bats
# cc-in-kitty — "am I genuinely inside a kitty pane?", answered by ANCESTRY rather than by an
# environment variable.
#
# THE DEFECT THIS PINS (2026-07-31). KITTY_WINDOW_ID, KITTY_PID and KITTY_LISTEN_ON are ordinary
# exported env vars, so every process launched from a kitty pane inherits them transitively and
# permanently. An iTerm2.app launched from a kitty pane carried all three into EVERY pane under it,
# and bin/it2-wrapper — whose divert tested `[ -n "$KITTY_WINDOW_ID" ]` — therefore diverted Claude
# Code's Agent Teams pane backend into kitty from inside genuine iTerm2 panes. The failure shape was
# worse than an outage: `it2 session list` returned rc 0 (kitty was alive), so Claude Code cached the
# backend as AVAILABLE, and every assignee spawn then died at USE time on `not a kitty window id`
# with no fallback to in-process teammates.
#
# THE REGRESSION ANCHOR is "KITTY_* set but kitty is not an ancestor" below. It is the exact state
# the old predicate called kitty, so a revert to any env-only test turns it red. Every other case
# here would pass under the old predicate too.
#
# Assertions are `[ ]` / `|| false`; `[[ ]]` and `(( ))` are errexit-EXEMPT in bats and would be
# silently dead anywhere but a body's last line (memory: bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  P="$REPO/bin/cc-in-kitty"
  # cc-in-kitty reads no path under $HOME, but the hermeticity ratchet judges the SUITE, not the
  # subject — an un-fixtured $HOME here would run against the operator's live ~/ and, once landed,
  # red the lint for every subsequent lander (scripts/test-hermeticity-lint.sh).
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Inherit nothing from the terminal the suite happens to run in — this file's whole subject is
  # variables that leak across terminals, so a leaked one would decide its own verdict.
  unset KITTY_WINDOW_ID KITTY_PID KITTY_LISTEN_ON CC_TERM
}

# ── the explicit override ────────────────────────────────────────────────────────────────────────

@test "CC_TERM=kitty forces yes, ahead of every inference" {
  run env CC_TERM=kitty "$P"
  [ "$status" -eq 0 ]
}

@test "CC_TERM=anything-else forces no, even with a perfect kitty environment" {
  run env CC_TERM=iterm2 KITTY_WINDOW_ID=11 KITTY_PID=$$ "$P"
  [ "$status" -eq 1 ]
}

# ── the cheap reject ─────────────────────────────────────────────────────────────────────────────

@test "no KITTY_WINDOW_ID is a definitive no" {
  run "$P"
  [ "$status" -eq 1 ]
}

@test "a non-numeric KITTY_WINDOW_ID is a definitive no" {
  # kitty window ids are always integers. A UUID here means someone crossed the terminals.
  run env KITTY_WINDOW_ID="w0t15p4:E5D77446-2AE5-4463-929A-7ACBCD97018E" KITTY_PID=$$ "$P"
  [ "$status" -eq 1 ]
}

# ── unverifiable is its own state, distinct from "no" ────────────────────────────────────────────

@test "KITTY_WINDOW_ID without KITTY_PID is UNVERIFIABLE (rc 2), not a plain no" {
  # Same fail-closed consequence, different fix: rc 1 means "you are in iTerm2", rc 2 means "your
  # kitty did not export what I need". Collapsing them makes a broken deploy read as a terminal.
  run env KITTY_WINDOW_ID=11 "$P"
  [ "$status" -eq 2 ]
}

@test "KITTY_PID=1 is refused — launchd is an ancestor of everything" {
  # Accepting it would make the walk answer YES for every process on the box, i.e. reintroduce the
  # false positive this file exists to remove.
  run env KITTY_WINDOW_ID=11 KITTY_PID=1 "$P"
  [ "$status" -eq 2 ]
}

# ── the ancestry walk: both controls are REAL process trees, not fixtures ────────────────────────

@test "positive control: a genuine ancestor is found" {
  # $$ is the shell running this file, which really is cc-in-kitty's parent. Without this, the
  # negative below could pass simply because the walk never finds anything.
  run env KITTY_WINDOW_ID=11 KITTY_PID=$$ "$P"
  [ "$status" -eq 0 ]
}

@test "REGRESSION ANCHOR: KITTY_* set but kitty is not an ancestor ⇒ NOT kitty" {
  # The 2026-07-31 state exactly: every kitty variable present and a LIVE kitty pid, but this
  # process descends from something else. `sleep` is a sibling — alive, in the ps table, and not in
  # our lineage — so the answer cannot come from the pid merely being dead.
  sleep 30 &
  local sibling=$!
  run env KITTY_WINDOW_ID=11 KITTY_PID="$sibling" KITTY_LISTEN_ON=unix:/tmp/kitty-fake "$P"
  kill "$sibling" 2>/dev/null || true
  [ "$status" -eq 1 ] || { echo "a live non-ancestor pid was accepted as kitty"; false; }
}

# ── diagnosability ───────────────────────────────────────────────────────────────────────────────

@test "--why explains the inherited case in words an operator can act on" {
  sleep 30 &
  local sibling=$!
  run env KITTY_WINDOW_ID=11 KITTY_PID="$sibling" "$P" --why
  kill "$sibling" 2>/dev/null || true
  [ "$status" -eq 1 ]
  # "not kitty" without a reason sends the reader to look at the id, which is the innocent party.
  echo "$output" | grep -qi 'inherited' || { echo "$output"; false; }
}

@test "silent without --why: the hot it2 path must not gain per-call chatter" {
  run env KITTY_WINDOW_ID=11 KITTY_PID=$$ "$P"
  [ -z "$output" ] || { echo "unexpected output: $output"; false; }
}

@test "an unknown argument is refused rather than treated as --why" {
  run env KITTY_WINDOW_ID=11 KITTY_PID=$$ "$P" --wat
  [ "$status" -eq 64 ]
}
