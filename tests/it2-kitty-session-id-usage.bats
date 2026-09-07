#!/usr/bin/env bats
# it2-kitty — a missing `-s` must fail LOUD, not as a bare rc 1 (cc-backlog bd1086f74866).
#
# THE DEFECT THIS PINS (2026-09-07). `session focus` and `session read` were written as
# `[ -n "$SESSION" ] && kt … || exit 1`. This shim takes the pane id as a FLAG — every caller in
# the tree passes `-s` — so a bare-positional invocation left SESSION empty and the arm exited 1
# with an empty stderr. kitty answers a pane that is gone or occluded with exactly that, so the two
# were indistinguishable, and the row that measured `it2 session read <pane>` returning rc 1 for
# six panes concluded the read PATH was broken and that the composer guards failing closed on it
# were the consequence. Measured the same day: `it2 session read -s 330` returns 563 bytes rc 0.
# The path was fine; the usage error had no voice.
#
# CONTROL (test 3) is what makes this suite non-vacuous: with `-s` supplied, the arm must still
# reach kitty and still map a kitty failure to rc 1 — the fix may not turn a genuinely unreadable
# pane into a usage error, which would be the same collision pointing the other way.
#
# Assertions are `[ ]` / `|| false`; `[[ ]]` and `(( ))` are errexit-EXEMPT in bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  D="$BATS_TEST_TMPDIR/bin"; mkdir -p "$D"
  cp "$REPO/bin/it2-kitty" "$D/it2-kitty"; chmod +x "$D/it2-kitty"
  [ -f "$REPO/bin/cc-in-kitty" ] && cp "$REPO/bin/cc-in-kitty" "$D/cc-in-kitty" && chmod +x "$D/cc-in-kitty"
  K="$D/it2-kitty"

  # A stand-in kitty whose get-text/focus-window verdict this suite controls.
  KB="$BATS_TEST_TMPDIR/fake-kitty"
  { printf '#!/bin/bash\n'
    printf 'case "$*" in\n'
    printf '  *get-text*|*focus-window*) [ -n "${FAKE_KITTY_FAIL:-}" ] && exit 3; printf "screen text\\n"; exit 0 ;;\n'
    printf 'esac\n'
    printf 'exit 0\n'; } > "$KB"
  chmod +x "$KB"
  export CC_TERM_KITTY="$KB"
  export KITTY_LISTEN_ON="unix:/tmp/kitty-test"
  export CC_TERM_KITTY_TO="unix:/tmp/kitty-test"
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE FAKE_KITTY_FAIL
}

@test "read without -s exits 64 and SAYS why (pre-fix: bare rc 1, empty stderr)" {
  run "$K" session read 330
  [ "$status" -eq 64 ] || { echo "status=$status out=$output"; false; }
  [ -n "$output" ] || { echo "stderr was EMPTY — indistinguishable from an unreadable pane"; false; }
  case "$output" in *"-s <pane-id>"*) : ;; *) echo "no usage line: $output"; false ;; esac
}

@test "focus without -s exits 64 and SAYS why (same collision, same arm)" {
  run "$K" session focus 330
  [ "$status" -eq 64 ] || { echo "status=$status out=$output"; false; }
  case "$output" in *"-s <pane-id>"*) : ;; *) echo "no usage line: $output"; false ;; esac
}

@test "CONTROL: with -s the read arm still reaches kitty, and a kitty failure is still rc 1" {
  run "$K" session read -s 330
  [ "$status" -eq 0 ] || { echo "supported form broke: status=$status out=$output"; false; }
  case "$output" in *"screen text"*) : ;; *) echo "did not reach kitty: $output"; false ;; esac

  FAKE_KITTY_FAIL=1 run "$K" session read -s 330
  [ "$status" -eq 1 ] || { echo "unreadable pane must stay rc 1, got $status"; false; }
}
