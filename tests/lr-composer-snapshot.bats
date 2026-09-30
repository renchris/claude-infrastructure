#!/usr/bin/env bats
# scripts/lib/lr-composer-snapshot.sh — the raw-screen capture at a draft hold (LIMIT_RECOVER_FLEET_V2
# W6b, D6.7). It types nothing; it keeps the --ansi screen, quotes the de-fainted draft row with its
# spaces and non-ASCII intact, and indexes each capture for decision 6's revisit counter.
# Hermetic: a kitty stub answers get-text from a fixture and records every argv it is given.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LCS="$REPO/scripts/lib/lr-composer-snapshot.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_COMPOSER_SNAP_DIR="$BATS_TEST_TMPDIR/snaps"
  export KITTY_ARGV="$BATS_TEST_TMPDIR/kitty.argv"; : > "$KITTY_ARGV"
  export SCREEN_FILE="$BATS_TEST_TMPDIR/screen.ansi"
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/kitty"
  cat > "$CC_TERM_KITTY" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${KITTY_ARGV:?}"
case " $* " in *" get-text "*) cat "${SCREEN_FILE:?}" ;; esac
exit 0
STUB
  chmod +x "$CC_TERM_KITTY"
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/no-such-kitty"
  B="$(printf '─%.0s' $(seq 1 40))"
}

box() { # $@ = composer rows (may carry escapes via printf %b)
  { printf 'scrollback line\n%s\n' "$B"; for r in "$@"; do printf '%b\n' "$r"; done; printf '%s\n  status\n' "$B"; } > "$SCREEN_FILE"
}

@test "row: the real 2.1.284 draft fixture reads back as the operator's one line" {
  run bash "$LCS" row "$REPO/tests/fixtures/lr-recon/screens/composer-draft-2.1.284.txt"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ] || { printf '%s\n' "${lines[@]}"; false; }
  [[ "$output" == "Use the Bash tool with run_in_background set to true"* ]] || { echo "$output"; false; }
}

@test "row: CC's faint suggestion is not a draft — nothing is quoted" {
  box '❯ \e[2mTry "refactor the parser"\e[22m'
  run bash "$LCS" row "$SCREEN_FILE"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "quoted a hint: $output"; false; }
}

@test "row: a draft written only in non-ASCII is KEPT, byte for byte" {
  box '❯ こんにちは　世界 ✓'
  run bash "$LCS" row "$SCREEN_FILE"
  [ "$output" = "こんにちは　世界 ✓" ] || { echo "got: $output"; false; }
}

@test "row: inner spaces survive, U+00A0 is chrome, trailing blanks go" {
  box "❯ ship  it\xc2\xa0now   "
  run bash "$LCS" row "$SCREEN_FILE"
  [ "$output" = "ship  it now" ] || { echo "got: [$output]"; false; }
}

@test "row: a screen with no input box is rc 1, never an empty draft" {
  printf 'just a shell prompt\n$ \n' > "$SCREEN_FILE"
  run bash "$LCS" row "$SCREEN_FILE"
  [ "$status" -eq 1 ]
}

@test "snap: keeps the ANSI screen under the store, indexes it, and types NOTHING" {
  box '❯ \e[1mhalf-written\e[22m reply'
  run bash "$LCS" snap 513 3c73a9d9-0000-4000-8000-000000000000 HELD:draft --focused 0 --limited 1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$output" ] || { echo "no file at $output"; false; }
  [[ "$output" == "$LR_COMPOSER_SNAP_DIR/"*"-win513-3c73a9d9-HELD_draft.ansi" ]] || { echo "$output"; false; }
  grep -q $'\e\\[1m' "$output" || { echo "the ANSI rendering was not kept"; false; }
  run jq -r '[.pane, .reason, (.rows|tostring), .focused, .limited, .first_row] | join("|")' "$LR_COMPOSER_SNAP_DIR/index.jsonl"
  [ "$output" = "513|HELD_draft|1|0|1|half-written reply" ] || { echo "$output"; false; }
  ! grep -q 'send-text\|send-key' "$KITTY_ARGV" || { cat "$KITTY_ARGV"; false; }
  grep -q -- "get-text --match id:513 --extent screen --ansi" "$KITTY_ARGV" || { cat "$KITTY_ARGV"; false; }
}

@test "snap: a pane that is not a window id captures nothing and asks kitty nothing" {
  box '❯ x'
  run bash "$LCS" snap "" sid HELD:draft
  [ "$status" -eq 1 ]
  [ ! -s "$KITTY_ARGV" ]
  [ ! -e "$LR_COMPOSER_SNAP_DIR/index.jsonl" ]
}

@test "snap: an empty read writes no file and no index row" {
  : > "$SCREEN_FILE"
  run bash "$LCS" snap 44 sid HELD:draft
  [ "$status" -eq 1 ]
  [ -z "$(ls "$LR_COMPOSER_SNAP_DIR" 2>/dev/null)" ] || { ls "$LR_COMPOSER_SNAP_DIR"; false; }
}

@test "count: only one-line drafts in unfocused limited panes count — not focused, multi-line, stray or unknown" {
  mkdir -p "$LR_COMPOSER_SNAP_DIR"
  {
    echo '{"rows":1,"focused":"0","limited":"1","reason":"HELD_draft"}'
    echo '{"rows":1,"focused":"0","limited":"1","reason":"HOLD-DRAFT"}'
    echo '{"rows":1,"focused":"1","limited":"1","reason":"HELD_draft"}'
    echo '{"rows":2,"focused":"0","limited":"1","reason":"HELD_draft"}'
    echo '{"rows":1,"focused":"0","limited":"1","reason":"stray-keystroke"}'
    echo '{"rows":1,"focused":"","limited":"1","reason":"HELD_draft"}'
    echo '{"rows":0,"focused":"0","limited":"1","reason":"HELD_draft"}'
  } > "$LR_COMPOSER_SNAP_DIR/index.jsonl"
  run bash "$LCS" count
  [ "$output" = 2 ] || { echo "count=$output"; false; }
}
