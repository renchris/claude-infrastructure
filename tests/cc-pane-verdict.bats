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

# The painter RENDERS the closer's [state=…] token (husk-history FIX-DESIGN D11); it never re-derives a
# state from refusal prose, and a line with no token is CANTTELL — never RESUME, whatever --reason says.
@test "--recompute maps the closer's line and the exit record to the contract's states" {
  [ "$("$PV" --pane 42 --recompute --closer-out 'pane 42: REFUSED — kitty remote control is down and … [state=DONE]' --dry-run | sed -n 1p)" = state=DONE ]
  "$PV" --pane 42 --recompute --closer-out 'pane 42: REFUSED — kitty remote control is down [state=DONE]' --dry-run | grep -qF "kitty didn't answer"
  [ "$("$PV" --pane 42 --recompute --closer-out 'pane 42: REFUSED — session 570d3917 crashed before it said Good to close: yes — resume or triage it instead: cc-husk-sweep --pane 42 [state=RESUME]' --dry-run | sed -n 1p)" = state=RESUME ]
  [ "$("$PV" --pane 42 --recompute --closer-out 'pane 42: REFUSED — session 570d3917 crashed; pane 12 holds its custody [state=OWNED:12]' --dry-run | sed -n 1p)" = state=OWNED ]
  [ "$("$PV" --pane 42 --recompute --closer-out 'pane 42: REFUSED — the custody was returned [state=COLLECTED]' --dry-run | sed -n 1p)" = state=DONE ]
  [ "$("$PV" --pane 42 --recompute --reason crash --closer-out 'pane 42: REFUSED — nothing says session 570d3917 meant to end' --dry-run | sed -n 1p)" = state=CANTTELL ]
  [ "$("$PV" --pane 42 --recompute --reason ended --closer-out 'pane 42: REFUSED — nothing says session 570d3917 meant to end' --dry-run | sed -n 1p)" = state=CANTTELL ]
  # pane 289: a shared cwd's sibling dirt in HEAD's whole-cwd refusal is not "unsaved files"
  [ "$("$PV" --pane 42 --recompute --closer-out 'pane 42: REFUSED — /x holds 4 uncommitted change(s)' --dry-run | sed -n 1p)" = state=CANTTELL ]
  run "$PV" --pane 42 --recompute --closer-out 'pane 42: REFUSED — /x holds 4 uncommitted change(s)' --dry-run
  [[ "$output" != *"unsaved"* && "$output" != *"stopped mid-task"* ]] || false
  mkdir -p "$CC_PANE_EXIT_DIR"; printf '{"rc":124,"claude_started":false,"launch_sha":"","ts":1}\n' > "$CC_PANE_EXIT_DIR/101.json"
  [ "$("$PV" --pane 101 --recompute --closer-out 'pane 101: REFUSED — anything' --dry-run | sed -n 1p)" = state=NOTHING ]
}

# ── C3: the closer's refusal class picks row 2 — only a transient refusal promises "closes when" ───
FS_LINE='pane 165: REFUSED — the fullscreen guard refused (--scope pane --mode refuse): refused-fs — this is the last pane of a fullscreen OS window; only the operator can close it (⌘W) [state=DONE]'
STUCK_LINE='pane 9: REFUSED — kitty remote control refused the close (fullscreen guard, composer guard or identity pin); not falling back to SIGHUP [state=DONE]'

@test "C3: a refused-fs line on a DONE pane names ⌘W and the fullscreen window, never 'closes when it does' (pane 165)" {
  run "$PV" --pane 165 --recompute --closer-out "$FS_LINE" --dry-run
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = state=DONE ]
  [ "${lines[3]}" = '⌘W closes it · last pane of a fullscreen window' ] || { echo "$output"; false; }
  [[ "$output" != *"closes when it does"* ]]
}

@test "C3: any other REFUSED line that lands in DONE is stuck: ⌘W, won't close by itself" {
  run "$PV" --pane 9 --recompute --closer-out "$STUCK_LINE" --dry-run
  [ "${lines[0]}" = state=DONE ]
  [ "${lines[3]}" = "⌘W closes it · won't close by itself" ] || { echo "$output"; false; }
  [[ "$output" != *"closes when"* ]] || false
  run "$PV" --pane 9 --state DONE --guard stuck --dry-run
  [ "$status" -eq 0 ]
  [ "${lines[3]}" = "⌘W closes it · won't close by itself" ] || { echo "$output"; false; }
}

@test "C3: only a closer line where kitty did not answer promises 'closes when it does'" {
  run "$PV" --pane 7 --recompute --closer-out "pane 7: REFUSED — the fullscreen guard refused (--scope pane --mode refuse): rc 124 — it could not read this pane's window (kitty did not answer it) [state=DONE]" --dry-run
  [ "${lines[0]}" = state=DONE ]
  [ "${lines[3]}" = "kitty didn't answer · closes when it does" ] || { echo "$output"; false; }
}

@test "C3: a NOTHING pane takes row 2 from the closer's answer now, not the stale kept --reason" {
  mkdir -p "$CC_PANE_EXIT_DIR"; printf '{"rc":124,"claude_started":false,"launch_sha":"","ts":1}\n' > "$CC_PANE_EXIT_DIR/165.json"
  run "$PV" --pane 165 --recompute --reason guard-unreadable --closer-out "$FS_LINE" --dry-run
  [ "${lines[0]}" = state=NOTHING ]
  [ "${lines[3]}" = '⌘W closes it · last pane of a fullscreen window' ] || { echo "$output"; false; }
  run "$PV" --pane 165 --recompute --reason guard-unreadable --closer-out 'pane 165: WOULD CLOSE — fine' --dry-run
  [ "${lines[3]}" = 'closing now · Ctrl-D closes it' ] || { echo "$output"; false; }
}

@test "C3: --recompute with an empty closer answer repaints nothing and says so" {
  run "$PV" --pane 42 --recompute --reason guard-unreadable --closer-out '' --tty "$TTYF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pane 42 no closer answer — not repainted"* ]] || { echo "$output"; false; }
  [ ! -s "$TTYF" ]
  [ ! -e "$CC_PANE_VERDICT_DIR/610-42.json" ]
}

@test "C3: no fullscreen or stuck row 2 tells the operator Ctrl-D" {
  local a out
  for a in "--state DONE --guard fullscreen" "--state DONE --guard stuck" "--state NOTHING --guard fullscreen" \
           "--state NOTHING --guard stuck" "--recompute --closer-out FS" "--recompute --closer-out STUCK"; do
    # shellcheck disable=SC2086  # $a is the option list on purpose
    case "$a" in
      *FS) out="$("$PV" --pane 85 --recompute --closer-out "$FS_LINE" --dry-run)" ;;
      *STUCK) out="$("$PV" --pane 85 --recompute --closer-out "$STUCK_LINE" --dry-run)" ;;
      *) out="$("$PV" --pane 85 $a --dry-run)" ;;
    esac
    [[ "$(sed -n 4p <<<"$out")" != *Ctrl-D* ]] || { echo "$a: $out"; false; }
    [[ "$(sed -n 4p <<<"$out")" == *"⌘W"* ]] || { echo "$a: $out"; false; }
  done
}

@test "kitty unreachable: the title falls back to OSC-2 on the tty" {
  CC_PANE_VERDICT_KITTY_BIN="$BATS_TEST_TMPDIR/no-kitty" run "$PV" --pane 85 --sid "$SID" --state CANTTELL --tty "$TTYF"
  [ "$status" -eq 0 ]
  grep -qF $'\033]2;◆ check 570d3917\007' "$TTYF"
}
