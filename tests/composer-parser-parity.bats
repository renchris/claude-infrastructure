#!/usr/bin/env bats
# shellcheck disable=SC2329
# SC2329: the transport stubs (cc_tui_rpc, cc_tui_screen, hf_bounded, kt) are called by the
# extracted parsers, so the linter reads them as never invoked.
#
# EVERY COMPOSER PARSER READS A DIALOG OVER THE BOX AS UNKNOWN (REPORT fix 9, 2026-10-11).
# Evidence: docs/research/recycle-failures-kitty-2026-10-10/slot-reader-sweep.md (sections 2-4, 6).
#
# There are six readers of the Claude Code input box. handoff-fire.sh's composer_content is the
# reference: it refuses a box with a dialog drawn above it (a ❯ option row at indent 1-4) or below
# it (a ❯ under the bottom border), and it exempts the slash-command menu only when the highlighted
# row names the command the box itself holds (0e882c9ac), because with the menu open a CR submits
# the HIGHLIGHT. The other five are the copies under test:
#   tui      scripts/lib/cc-tui.sh cc_tui_composer            (cc_tui_submit types through it)
#   lcs      scripts/lib/lr-composer-snapshot.sh lcs_draft_rows
#   screen   scripts/limit-recover/lr-fire-resume.sh LR_SCREEN_SH (run by expect via bash -c)
#   observe  scripts/limit-recover/lr_recon/observe.py composer_from_screen
#   it2k     bin/it2-kitty composer_state                     (the close guard)
# Each one is the shipped code, extracted or sourced, with only its screen transport stubbed.
#
# Screens: tests/fixtures/composer-parity (synthetic 2.1.293 states at 38 and 57 columns, see
# gen.py there), the real 2.1.291 slash-menu capture, the two real 2.1.260 background-work-dialog
# captures, and tests/fixtures/lr-recon/screens.
#
# RED-proof: this suite over the five files as they stood at d92eaa620 (git archive into a scratch
# tree, 2026-10-11) prints 1..21 with 9 not ok, each for the reason its name gives:
#   2, 6, 14, 18   tui, lcs, observe, it2k read EMPTY under a dialog above the box (the two real
#                  2.1.260 captures included) and /exit or DRAFT under a dialog below it
#   4, 8, 16, 20   the same four read /exit (or /e) under a menu highlighting another command
#   11             screen reads UNKNOWN under the menu its own /exit opens
# Test 1 (the reference) and every copy's plain-box control pass before and after. The screen
# copy's dialog and foreign-highlight cases (10, 12) also pass before: it refused every ❯ row, so
# what the fix changes there is test 11, and 12 is what keeps that exemption narrow.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FX="$REPO/tests/fixtures/composer-parity"
  LRFX="$REPO/tests/fixtures/lr-recon/screens"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  W="$BATS_TEST_TMPDIR"
  # Nothing here fires, types or reaches a pane: every reader gets its screen from a fixture file.
  # The pins below are the ones any suite naming handoff-fire.sh and bin/it2-kitty must carry, so
  # no reader can pick up this machine's load, accounts, pane identity or kitty socket.
  unset KITTY_WINDOW_ID KITTY_LISTEN_ON CC_TERM_KITTY_TO CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
  export IT2_WRAPPER_NO_KITTY=1 CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue"
  export CC_RECYCLE_RETRY_DIR="$BATS_TEST_TMPDIR/retry"
  export CC_NOTIFY_BIN="$BATS_TEST_TMPDIR/no-such-cc-notify"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export LR_COMPOSER_SNAP_DIR="$BATS_TEST_TMPDIR/snaps"

  # reference: composer_content, extracted by name (handoff-fire.sh is not sourceable)
  sed -n '/^composer_content() {/,/^}/p' "$REPO/scripts/handoff-fire.sh" > "$W/ref.sh"
  grep -q '^composer_content() {' "$W/ref.sh" || { echo "composer_content was not extracted" >&2; return 1; }
  # screen: the LR_SCREEN_SH program, as expect hands it to bash -c
  awk '/<<.LRSCREENSH./ { f = 1; next } /^LRSCREENSH$/ { f = 0 } f' \
    "$REPO/scripts/limit-recover/lr-fire-resume.sh" > "$W/lr-screen.sh"
  [ -s "$W/lr-screen.sh" ] || { echo "LR_SCREEN_SH was not extracted" >&2; return 1; }
  cat > "$W/lr-it2" <<'STUB'
#!/usr/bin/env bash
n=""; i=1
while [ "$i" -le "$#" ]; do [ "${!i}" = -n ] && { j=$((i + 1)); n="${!j}"; }; i=$((i + 1)); done
tail -n "${n:-1000}" "$PARITY_PLAIN"
STUB
  chmod +x "$W/lr-it2"
  # it2k: composer_state, extracted by name; its kitty transport (kt) is stubbed per read
  sed -n '/^composer_state() {/,/^}/p' "$REPO/bin/it2-kitty" > "$W/it2k.sh"
  grep -q '^composer_state() {' "$W/it2k.sh" || { echo "composer_state was not extracted" >&2; return 1; }
  for f in ref.sh lr-screen.sh it2k.sh; do bash -n "$W/$f" || { echo "$f is not valid bash" >&2; return 1; }; done
}

# fx <name> → PARITY_PLAIN / PARITY_ANSI (the --ansi read falls back to plain when none was captured)
fx() {
  case "$1" in
    real-menu-own)     PARITY_PLAIN="$REPO/tests/fixtures/recycle-exit-residue/slash-menu-exit-2.1.291.txt"
                       PARITY_ANSI="$REPO/tests/fixtures/recycle-exit-residue/slash-menu-exit-2.1.291.ansi.txt" ;;
    real-bgdialog-1)   PARITY_PLAIN="$REPO/tests/fixtures/teammate-probe/captures/p1-run2-exitmodal/pane-before.txt"; PARITY_ANSI="$PARITY_PLAIN" ;;
    real-bgdialog-2)   PARITY_PLAIN="$REPO/tests/fixtures/teammate-probe/captures/p1-run2/lead-pane.after-exit.txt"; PARITY_ANSI="$PARITY_PLAIN" ;;
    lr-*)              PARITY_PLAIN="$LRFX/${1#lr-}.txt"; PARITY_ANSI="$PARITY_PLAIN" ;;
    *)                 PARITY_PLAIN="$FX/$1.txt"; PARITY_ANSI="$FX/$1.ansi" ;;
  esac
  [ -s "$PARITY_PLAIN" ] && [ -s "$PARITY_ANSI" ] || { echo "fixture $1 is missing" >&2; return 1; }
  export PARITY_PLAIN PARITY_ANSI
}

# read_as <copy> <fixture> [want] → UNKNOWN | EMPTY | the box content, whitespace-stripped.
# The three copies that report a state rather than text say DRAFT; `want` (screen only) is the
# text LR_SCREEN_SH must find in the box to answer DRAFT-MINE, which is how it proves what it read.
read_as() {
  local copy="$1" out rc=0
  fx "$2" || return 1
  case "$copy" in
    ref)
      # shellcheck disable=SC1090,SC1091
      out="$(. "$W/ref.sh"
             hf_bounded() { local n="" f="$PARITY_PLAIN" i j; for ((i = 1; i <= $#; i++)); do
                 [ "${!i}" = -n ] && { j=$((i + 1)); n="${!j}"; }; [ "${!i}" = --ansi ] && f="$PARITY_ANSI"; done
               tail -n "${n:-1000}" "$f"; }
             composer_content it2 1)" || rc=$?
      [ "$rc" = 0 ] || { echo UNKNOWN; return 0; }; echo "${out:-EMPTY}" ;;
    tui)
      # shellcheck disable=SC1090,SC1091
      out="$(unset CC_TUI_LIB_LOADED; . "$REPO/scripts/lib/cc-tui.sh"
             cc_tui_rpc() { case " $* " in *" --ansi "*) cat "$PARITY_ANSI" ;; *) cat "$PARITY_PLAIN" ;; esac; }
             cc_tui_composer 1)" || rc=$?
      [ "$rc" = 0 ] || { echo UNKNOWN; return 0; }; echo "${out:-EMPTY}" ;;
    lcs)
      # shellcheck disable=SC1090,SC1091
      out="$(unset CC_TUI_LIB_LOADED; . "$REPO/scripts/lib/lr-composer-snapshot.sh"; lcs_draft_rows "$PARITY_ANSI")" || rc=$?
      [ "$rc" = 0 ] || { echo UNKNOWN; return 0; }
      out="$(printf '%s' "$out" | LC_ALL=C tr -d '[:space:]')"; echo "${out:-EMPTY}" ;;
    screen)
      out="$(LR_IT2="$W/lr-it2" LR_PANE=1 LR_SCREEN_WANT="${3:-}" LR_SCREEN_NONCE="" LR_SCREEN_TAIL="" bash "$W/lr-screen.sh")"
      case "$out" in MENU|UNKNOWN|"") echo UNKNOWN ;; *) echo "$out" ;; esac ;;
    observe)
      out="$(PYTHONPATH="$REPO/scripts/limit-recover" python3 -c '
import sys
from lr_recon.observe import composer_from_screen
print(composer_from_screen(open(sys.argv[1], encoding="utf-8", errors="replace").read()))' "$PARITY_ANSI")" || out=unknown
      case "$out" in empty) echo EMPTY ;; draft) echo DRAFT ;; *) echo UNKNOWN ;; esac ;;
    it2k)
      PARITY_COLS="$(perl -CSD -ne 'if (/\x{2500}{6}/) { chomp; print length; exit }' "$PARITY_PLAIN")"; export PARITY_COLS
      # shellcheck disable=SC1090,SC1091
      out="$(. "$W/it2k.sh"
             kt() { case " $* " in
                 *" ls "*) printf '[{"id":1,"tabs":[{"id":1,"windows":[{"id":300,"columns":%s,"in_alternate_screen":true,"foreground_processes":[]}]}]}]\n' "${PARITY_COLS:-80}" ;;
                 *" get-text "*) cat "$PARITY_ANSI" ;; esac; }
             composer_state 300)"
      case "$out" in EMPTY) echo EMPTY ;; NON-EMPTY) echo DRAFT ;; *) echo UNKNOWN ;; esac ;;
    *) echo "unknown copy $copy" >&2; return 1 ;;
  esac
}

# A dialog owns the keys, drawn above the box or below it. Real 2.1.260 captures first.
DIALOG_OVER_BOX="real-bgdialog-1 real-bgdialog-2 bgdialog-above-empty-38c bgdialog-above-empty-57c
  bgdialog-below-38c bgdialog-below-57c pathdialog-above-empty-38c pathdialog-above-empty-57c
  lr-bgwork-dialog-2.1.284 lr-bgwork-dialog-2.1.284-agent-view-off"
OWN_MENU="real-menu-own exit-menu-own-38c exit-menu-own-57c midturn-exit-menu-own-38c midturn-exit-menu-own-57c"
# The highlight is not the command the box holds: /exit under ❯ /export, and the prefix /e under ❯ /exit.
FOREIGN_MENU="exit-menu-foreign-38c exit-menu-foreign-57c e-prefix-menu-38c e-prefix-menu-57c"

unknown_on() { # <copy> <fixtures…>: every one reads UNKNOWN
  local copy="$1" f got bad=0; shift
  for f in "$@"; do
    got="$(read_as "$copy" "$f")"
    [ "$got" = UNKNOWN ] || { echo "$copy read '$got' on $f, expected UNKNOWN"; bad=1; }
  done
  [ "$bad" -eq 0 ]
}

reads() { # <copy> <expected> <fixtures…>
  local copy="$1" want="$2" f got bad=0; shift 2
  for f in "$@"; do
    got="$(read_as "$copy" "$f")"
    [ "$got" = "$want" ] || { echo "$copy read '$got' on $f, expected '$want'"; bad=1; }
  done
  [ "$bad" -eq 0 ]
}

# ── the reference: the corpus means what this suite says it means ────────────────────────────────

@test "reference composer_content: UNKNOWN under a dialog, /exit under its own menu, UNKNOWN under a foreign highlight" {
  # shellcheck disable=SC2086
  unknown_on ref $DIALOG_OVER_BOX
  # shellcheck disable=SC2086
  reads ref /exit $OWN_MENU exit-nomenu-38c exit-nomenu-57c
  # shellcheck disable=SC2086
  unknown_on ref $FOREIGN_MENU
  reads ref EMPTY empty-38c empty-57c
  reads ref fixthebuildthenpingme draft-38c draft-57c
}

# ── cc-tui.sh cc_tui_composer ────────────────────────────────────────────────────────────────────

@test "tui: a dialog over the box reads UNKNOWN" {
  # shellcheck disable=SC2086
  unknown_on tui $DIALOG_OVER_BOX
}

@test "tui: /exit under a menu highlighting /exit reads /exit" {
  # shellcheck disable=SC2086
  reads tui /exit $OWN_MENU
}

@test "tui: /exit under a menu highlighting another command reads UNKNOWN" {
  # shellcheck disable=SC2086
  unknown_on tui $FOREIGN_MENU
}

@test "tui: a plain box still reads — empty, a draft, /exit with no menu" {
  reads tui EMPTY empty-38c empty-57c lr-composer-empty-2.1.284
  reads tui fixthebuildthenpingme draft-38c draft-57c
  reads tui /exit exit-nomenu-38c exit-nomenu-57c
}

# ── lr-composer-snapshot.sh lcs_draft_rows ───────────────────────────────────────────────────────

@test "lcs: a dialog over the box reads UNKNOWN" {
  # shellcheck disable=SC2086
  unknown_on lcs $DIALOG_OVER_BOX
}

@test "lcs: /exit under a menu highlighting /exit reads /exit" {
  # shellcheck disable=SC2086
  reads lcs /exit $OWN_MENU
}

@test "lcs: /exit under a menu highlighting another command reads UNKNOWN" {
  # shellcheck disable=SC2086
  unknown_on lcs $FOREIGN_MENU
}

@test "lcs: a plain box still reads — empty, a draft, /exit with no menu" {
  reads lcs EMPTY empty-38c empty-57c
  reads lcs fixthebuildthenpingme draft-38c draft-57c
  reads lcs /exit exit-nomenu-38c exit-nomenu-57c
}

# ── lr-fire-resume.sh LR_SCREEN_SH ───────────────────────────────────────────────────────────────

@test "screen: a dialog over the box reads UNKNOWN" {
  # shellcheck disable=SC2086
  unknown_on screen $DIALOG_OVER_BOX
}

@test "screen: /exit under a menu highlighting /exit reads as the /exit it holds" {
  local f got bad=0
  for f in $OWN_MENU; do
    got="$(read_as screen "$f" /exit)"
    [ "$got" = DRAFT-MINE ] || { echo "screen read '$got' on $f, expected DRAFT-MINE for /exit"; bad=1; }
  done
  [ "$bad" -eq 0 ]
}

@test "screen: /exit under a menu highlighting another command reads UNKNOWN" {
  # shellcheck disable=SC2086
  unknown_on screen $FOREIGN_MENU
}

@test "screen: a plain box still reads — empty, a draft, /exit with no menu" {
  reads screen EMPTY empty-38c empty-57c lr-composer-empty-2.1.284
  reads screen DRAFT draft-38c draft-57c
  [ "$(read_as screen exit-nomenu-57c /exit)" = DRAFT-MINE ]
}

# ── lr_recon observe.py composer_from_screen ─────────────────────────────────────────────────────

@test "observe: a dialog over the box reads unknown" {
  # shellcheck disable=SC2086
  unknown_on observe $DIALOG_OVER_BOX
}

@test "observe: /exit under a menu highlighting /exit reads draft" {
  # shellcheck disable=SC2086
  reads observe DRAFT $OWN_MENU
}

@test "observe: /exit under a menu highlighting another command reads unknown" {
  # shellcheck disable=SC2086
  unknown_on observe $FOREIGN_MENU
}

@test "observe: a plain box still reads — empty, a draft, /exit with no menu" {
  reads observe EMPTY empty-38c empty-57c lr-composer-empty-2.1.284
  reads observe DRAFT draft-38c draft-57c exit-nomenu-38c exit-nomenu-57c
}

# ── bin/it2-kitty composer_state (the close guard) ───────────────────────────────────────────────

@test "it2k: a dialog over the box reads UNKNOWN, so the close is refused" {
  # shellcheck disable=SC2086
  unknown_on it2k $DIALOG_OVER_BOX
}

@test "it2k: /exit under a menu highlighting /exit reads NON-EMPTY" {
  # shellcheck disable=SC2086
  reads it2k DRAFT $OWN_MENU
}

@test "it2k: /exit under a menu highlighting another command reads UNKNOWN" {
  # shellcheck disable=SC2086
  unknown_on it2k $FOREIGN_MENU
}

@test "it2k: a plain box still reads — empty, a draft, /exit with no menu" {
  reads it2k EMPTY empty-38c empty-57c
  reads it2k DRAFT draft-38c draft-57c exit-nomenu-38c exit-nomenu-57c
}
