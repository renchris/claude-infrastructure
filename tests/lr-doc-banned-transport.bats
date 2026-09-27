#!/usr/bin/env bats
# commands/limit-recover.md § "Banned on this path, by name" — the transports a recovering agent
# reaches for and must not. The table is what an agent reads mid-recovery, so a measured defect that
# is missing from it gets re-measured on a live pane.
#
# `kitty @ send-text … $'\r'` (measured 2026-09-27, window 814): the text lands in the composer and
# the CR does NOT submit, because Claude Code pushes the kitty keyboard protocol and a raw CR arrives
# as text, not as the Enter key. The sanctioned path is cc_tui_submit (scripts/lib/cc-tui.sh), which
# proves the submit on disk.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Reads only a repo file; $HOME is fixtured so no future case can grow a dependency on the live one.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  DOC="$REPO/commands/limit-recover.md"
  # The banned table only: from its header line to the first blank line after it.
  TABLE="$(awk '/^\*\*Banned on this path, by name\.\*\*/{on=1} on&&/^\|/{print; seen=1; next} on&&seen&&!/^\|/{exit}' "$DOC")"
}

@test "the banned table exists and still carries kitty @ send-key" {
  [ -n "$TABLE" ]
  printf '%s\n' "$TABLE" | grep -q 'kitty @ send-key'
}

@test "kitty @ send-text with a CR is banned, naming cc_tui_submit as the sanctioned path" {
  row="$(printf '%s\n' "$TABLE" | grep 'kitty @ send-text')"
  [ -n "$row" ]
  printf '%s\n' "$row" | grep -q "\\\\r"
  printf '%s\n' "$row" | grep -q 'cc_tui_submit'
  printf '%s\n' "$row" | grep -qi 'does not submit\|does NOT submit'
}

@test "the send-text row sits next to the send-key row" {
  n_key="$(printf '%s\n' "$TABLE" | grep -n 'kitty @ send-key' | cut -d: -f1)"
  n_txt="$(printf '%s\n' "$TABLE" | grep -n 'kitty @ send-text' | cut -d: -f1)"
  [ -n "$n_key" ] && [ -n "$n_txt" ] || false
  d=$(( n_txt - n_key )); [ "${d#-}" -eq 1 ]
}
