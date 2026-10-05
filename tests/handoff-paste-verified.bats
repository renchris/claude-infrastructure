#!/usr/bin/env bats
# handoff-fire.sh paste-verified <pane> <prompt-file> (W3 P5) — the entry point that lets
# scripts/lib/restore-note.sh reach it2_paste_submit_verified for a recovery prompt that never
# reached its session. The paste function has its own suite (tests/handoff-composer-gate.bats);
# these cases pin the door: its arguments, its exit status, and that it types nothing it should not.
# No case reaches a terminal: the driver is a stub that only records its argv.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin" "$HOME/.claude/logs"
  unset KITTY_WINDOW_ID KITTY_LISTEN_ON KITTY_PID ITERM_SESSION_ID CC_PANE_ID
  export IT2_WRAPPER_NO_KITTY=1
  # One export per line: the pin-guard (handoff-fire-capacity-gate.bats case 25) reads them that way.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-such-sweep-stamp.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue"
  export IT2LOG="$BATS_TEST_TMPDIR/it2.log"; : > "$IT2LOG"
  export IT2_BIN="$BATS_TEST_TMPDIR/it2"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$IT2LOG"\nexit 0\n' > "$IT2_BIN"; chmod +x "$IT2_BIN"
  PF="$BATS_TEST_TMPDIR/prompt.txt"; printf 'continue the work (restore ref R-abc123)\n' > "$PF"
  # The entry point alone, with the paste function replaced by a recorder.
  { printf '%s\n' 'it2_paste_submit_verified() { printf "%s|%s|%s\n" "$1" "$2" "$3" >> "$PVLOG"; FIRE_PASTE_LAST_READBACK="${PV_RB:-}"; return "${PV_STUB_RC:-0}"; }'
    sed -n '/^if \[ "\${1:-}" = "paste-verified" \]; then/,/^fi/p' "$HF"
  } > "$BATS_TEST_TMPDIR/door.sh"
  export PVLOG="$BATS_TEST_TMPDIR/pv.log"; : > "$PVLOG"
}

door() { bash "$BATS_TEST_TMPDIR/door.sh" "$@"; }

@test "the entry point exists under the spelling restore-note.sh greps for" {
  [ "$(grep -c '^if \[ "\${1:-}" = "paste-verified" \]' "$HF")" -eq 1 ]
  . "$REPO/scripts/lib/restore-note.sh"
  unset CC_RESTORE_PASTE_CMD
  [ "$(_rn_paste_cmd)" = "$REPO/scripts/lib/../handoff-fire.sh paste-verified" ]
}

@test "usage: no pane, a missing file or an empty file exits 64 and pastes nothing" {
  run door paste-verified;                 [ "$status" -eq 64 ]
  run door paste-verified 77 "$PF.absent"; [ "$status" -eq 64 ]
  : > "$PF.empty"
  run door paste-verified 77 "$PF.empty";  [ "$status" -eq 64 ]
  [ ! -s "$PVLOG" ]
}

@test "the pane and the file's text reach the verified paste, once, through the it2 seam" {
  run door paste-verified 77 "$PF"
  [ "$status" -eq 0 ]
  [ "$(cat "$PVLOG")" = "$IT2_BIN|77|continue the work (restore ref R-abc123)" ]
  [[ "$output" == *"paste-verified pane=77 rc=0"* ]] || false
}

@test "the exit status is the paste function's own: held (3) and mangled (4) are not flattened to 1" {
  PV_STUB_RC=3 run door paste-verified 77 "$PF"; [ "$status" -eq 3 ]
  PV_STUB_RC=4 PV_RB='half a draft' run door paste-verified 77 "$PF"
  [ "$status" -eq 4 ]
  [[ "$output" == *"rc=4 readback=half a draft"* ]] || false
  [ "$(grep -c . "$PVLOG")" -eq 2 ]          # one call each: the door never retries
}

@test "END TO END: a pane with no proven Claude session is abstained on (2) and nothing is typed" {
  run bash "$HF" paste-verified 77 "$PF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ABSTAINED"* ]] || false
  ! grep -q 'session send' "$IT2LOG"
}
