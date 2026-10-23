#!/usr/bin/env bats
# bin/cc-pane-verdict — the ONE writer of a dead pane's screen and title (husk-panes-2026-10-22 F5).
# RED-proof: the tool did not exist before this change, so every case fails on origin/main.
# HERMETIC: HOME, the state store and the pane-say log are temp; the "tty" is a regular file; kitty
# is a recording stub. Nothing here reaches a live pane.

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PV="$REPO/bin/cc-pane-verdict"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export CC_PANE_VERDICT_DIR="$BATS_TEST_TMPDIR/store" CC_SAY_LOG="$BATS_TEST_TMPDIR/say.jsonl"
  export CC_PANE_EXIT_DIR="$BATS_TEST_TMPDIR/pane-exit" KITTY_PID=610 KITTY_LISTEN_ON="unix:$BATS_TEST_TMPDIR/kitty-610"
  unset CC_PANE_VERDICT_COLS
  TTYF="$BATS_TEST_TMPDIR/ttys085"; : > "$TTYF"
  cc_stub "$BATS_TEST_TMPDIR/bin" kitty "$(printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\n' "$BATS_TEST_TMPDIR/kitty.log")"
  export CC_PANE_VERDICT_KITTY_BIN="$BATS_TEST_TMPDIR/bin/kitty"
}
screen() { LC_ALL=C sed $'s/\033\\[[0-9;]*[A-Za-z]//g' "$TTYF"; }
SID=570d3917-79ac-4aa4-93d1-896b843b8b9f

@test "a CRASH painted RESUME is repainted DONE when the facts change, and its title changes with it (pane 85)" {
  run "$PV" --pane 85 --sid "$SID" --state RESUME --unsaved 2 --tty "$TTYF"
  [ "$status" -eq 0 ]
  screen | grep -qF '✗ 570d3917 stopped mid-task · 2 unsaved files'
  screen | grep -qF '▶ cc-husk-sweep --resume --yes --pane 85'
  grep -qF -- '--temporary --match id:85 ⛔ resume 570d3917' "$BATS_TEST_TMPDIR/kitty.log"
  run "$PV" --pane 85 --sid "$SID" --state DONE --guard unreadable --tty "$TTYF"
  [ "$status" -eq 0 ]
  screen | grep -qF '✓ 570d3917 finished · nothing to resume'
  screen | grep -qF "kitty didn't answer · closes when it does"
  [ "$(tail -1 "$BATS_TEST_TMPDIR/kitty.log")" = "@ --to unix:$BATS_TEST_TMPDIR/kitty-610 set-window-title --temporary --match id:85 ✓ done 570d3917" ]
}

@test "rows are fitted to the pane's width: no painted row is wider than 40 cells" {
  CC_PANE_VERDICT_COLS=40 run "$PV" --pane 85 --sid "$SID" --state OWNED --owner 16 --tty "$TTYF"
  [ "$status" -eq 0 ]
  # shellcheck source=/dev/null
  . "$REPO/lib/cc-say.sh"
  local line n=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    cc_say_cells "$line"; [ "$CC_SAY_CELLS" -le 40 ] || { echo "row is $CC_SAY_CELLS cells: $line"; false; }
    n=$((n + 1))
  done < <(screen)
  [ "$n" -eq 2 ]
}

@test "idempotent: the same facts twice write nothing the second time" {
  "$PV" --pane 85 --sid "$SID" --state CANTTELL --tty "$TTYF"
  : > "$TTYF"; local before; before="$(wc -l < "$BATS_TEST_TMPDIR/kitty.log")"
  run "$PV" --pane 85 --sid "$SID" --state CANTTELL --tty "$TTYF"
  [[ "$output" == *"unchanged"* ]] || { echo "$output"; false; }
  [ ! -s "$TTYF" ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/kitty.log")" = "$before" ]
  [ "$(grep -c '"kind":"painted"' "$CC_SAY_LOG")" -eq 1 ]
}

@test "no state paints a banned string (exit codes, causes, internal terms, closed in a title)" {
  local st out
  for st in "DONE --guard safe" "DONE --guard fullscreen" "DONE --moved-to 12" "RESUME --unsaved 3" "RESUME --stranded" \
            "OWNED --owner 16" "NOTHING" "CANTTELL"; do
    # shellcheck disable=SC2086  # $st is the option list on purpose
    out="$("$PV" --pane 85 --sid "$SID" --state $st --dry-run)"
    ! grep -qiE '143|SIGTERM|external-sigterm|suspected-oom|(^|[^-])husk|custody|fleet|collected|kitten|reason unknown|state=UNKNOWN|shell kept for resume' <<<"$out" \
      || { echo "$st: $out"; false; }
    ! grep -E '^title=' <<<"$out" | grep -qE 'closed|✅' || { echo "$st: $out"; false; }
  done
}

@test "--recompute maps the closer's line and the exit record to the contract's states" {
  [ "$("$PV" --pane 42 --recompute --closer-out 'pane 42: REFUSED — kitty remote control is down and …' --dry-run | sed -n 1p)" = state=DONE ]
  "$PV" --pane 42 --recompute --closer-out 'pane 42: REFUSED — kitty remote control is down' --dry-run | grep -qF "kitty didn't answer"
  [ "$("$PV" --pane 42 --recompute --reason crash --closer-out 'pane 42: REFUSED — nothing says session 570d3917 meant to end' --dry-run | sed -n 1p)" = state=RESUME ]
  [ "$("$PV" --pane 42 --recompute --reason ended --closer-out 'pane 42: REFUSED — nothing says session 570d3917 meant to end' --dry-run | sed -n 1p)" = state=CANTTELL ]
  "$PV" --pane 42 --recompute --closer-out 'pane 42: REFUSED — /x holds 4 uncommitted change(s)' --dry-run | grep -qF '4 unsaved files'
  mkdir -p "$CC_PANE_EXIT_DIR"; printf '{"rc":124,"claude_started":false,"launch_sha":"","ts":1}\n' > "$CC_PANE_EXIT_DIR/101.json"
  [ "$("$PV" --pane 101 --recompute --closer-out 'pane 101: REFUSED — anything' --dry-run | sed -n 1p)" = state=NOTHING ]
}

@test "kitty unreachable: the title falls back to OSC-2 on the tty" {
  CC_PANE_VERDICT_KITTY_BIN="$BATS_TEST_TMPDIR/no-kitty" run "$PV" --pane 85 --sid "$SID" --state CANTTELL --tty "$TTYF"
  [ "$status" -eq 0 ]
  grep -qF $'\033]2;◆ check 570d3917\007' "$TTYF"
}
