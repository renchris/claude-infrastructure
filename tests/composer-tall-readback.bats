#!/usr/bin/env bats
# shellcheck disable=SC2329
# SC2329: bats invokes setup and each stub (hf_bounded, composer_owned, read_post) through its runner
# or through the extracted units, so the linter reads them as never called.
# A TALL COMPOSER READS BACK AS ITSELF; A MODAL STILL DOES NOT (goal-arm-readback, 2026-10-10).
# Evidence + design: docs/research/goal-arm-readback-2026-10-10/REPORT.md; plan GOAL_ARM_READBACK.md.
#
# THE INCIDENT. handoff-fire.sh pasted a ~470-char `/goal …` into a fired pane 32 columns wide. It
# wrapped to 22 composer rows; with the footer under the bottom border the TOP border sat 26 rows
# up, and composer_content read only the last 24. Every read-back said UNKNOWN, the arm reported
# "saw '<unreadable>'", withheld the CR, and left the goal typed but unsubmitted over a healthy
# composer (panes 70, 175, 176, 202, 203). The fixture below is pane 203's own screen, captured live
# mid-turn (spinner up), with only the home path rewritten.
#
# WHY THE STUB HONOURS `-n`. Every older composer stub `cat`s its whole fixture whatever window the
# caller asks for, so the window size had never been exercised — which is how a 24-row window
# shipped. This stub serves `tail -n N`, like bin/it2-kitty, and the `.ansi` twin when --ansi is
# asked for, like the live read.
#
# THE FAIL-CLOSED HALF. The bigger window is read only when the small one shows a bottom border and
# no top, and its box is accepted only when shaped like a composer. Every real modal fixture in the
# repo (trust, settings error, background-work dialog at 29/40/80 columns, resume pickers), alone
# and under a transcript built to fool the widened read, must never read EMPTY and must never match
# a payload — so no paste lands in it and no CR follows one.

bats_require_minimum_version 1.5.0  # `run !` (SC2314): a bare `! cmd` mid-test never fails

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  FX="$REPO/tests/fixtures/composer-tall"
  MODALS="$REPO/tests/fixtures/lr-recon/screens"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  {
    grep '^_iso_now() {' "$HF" || true
    sed -n '/^composer_content() {/,/^}/p'            "$HF"
    sed -n '/^_paste_newlines() {/,/^}/p'             "$HF"
    sed -n '/^paste_readback_expect() {/,/^}/p'       "$HF"
    sed -n '/^paste_readback_ok() {/,/^}/p'           "$HF"
    sed -n '/^composer_scrub_verified() {/,/^}/p'     "$HF"
    sed -n '/^composer_residue_dir() {/,/^}/p'        "$HF"
    sed -n '/^composer_residue_record() {/,/^}/p'     "$HF"
    sed -n '/^composer_residue_forget() {/,/^}/p'     "$HF"
    sed -n '/^composer_residue_is_ours() {/,/^}/p'    "$HF"
    sed -n '/^it2_paste_submit_verified() {/,/^}/p'   "$HF"
  } > "$BATS_TEST_TMPDIR/units.sh"
  bash -n "$BATS_TEST_TMPDIR/units.sh" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  # shellcheck disable=SC1091
  . "$BATS_TEST_TMPDIR/units.sh"
  composer_owned() { return 0; }
  export BP_START=$'\x1b[200~' BP_END=$'\x1b[201~'
  export FIRE_TYPE_SETTLE=0.01 FIRE_PASTE_PREWAIT=0 FIRE_PASTE_PREIVL=0.01 CC_COMPOSER_SCRUB=off
  SENT_LOG="$BATS_TEST_TMPDIR/sent.log"; : > "$SENT_LOG"
  READS_FILE="$BATS_TEST_TMPDIR/reads"; : > "$READS_FILE"
  PRE_FILE="$BATS_TEST_TMPDIR/pre.txt"; POST_FILE="$BATS_TEST_TMPDIR/post.txt"
  B="$(printf '─%.0s' $(seq 1 32))"
  GOAL='/goal a long wrapped /goal pasted into a narrow or busy pane reads back as matching and is submitted, while a real modal still reads as unreadable and gets no Enter, and the fix is landed and live — proven by printing the touched bats summary (1..N, 0 failures) including both replays and git ls-tree origin/main on the changed paths; do not touch scripts/limit-recover/lr_recon, settings.json, completion-assert.sh, close-shape.sh, operator-readout.sh or lead-crash-watchdog.sh; full brief in the prompt above, DoD at docs/plans/GOAL_ARM_READBACK.md'
  { echo "  some reply"; echo "$B"; echo "❯ "; echo "$B"; echo "  (4) #203 status"; } > "$PRE_FILE"
}

# The window-honouring transport. Read 1 serves $PRE_FILE, every later read $POST_FILE (a FILE
# counter: composer_content calls this inside $(…), where a shell counter would not survive).
windowed_hf_bounded() { # <bin> session <read|send> -s <sid> [-n N] [--ansi] | send payload in $6
  local verb="$3" n="" ansi=0 f a i
  if [ "$verb" = read ]; then
    for ((i = 1; i <= $#; i++)); do
      a="${!i}"; [ "$a" = --ansi ] && ansi=1
      if [ "$a" = -n ]; then i=$((i + 1)); n="${!i}"; fi
    done
    echo r >> "$READS_FILE"
    if [ "$(wc -l < "$READS_FILE")" -le 1 ]; then f="$PRE_FILE"; else f="$POST_FILE"; fi
    [ "$ansi" = 1 ] && [ -f "$f.ansi" ] && f="$f.ansi"
    if [ -n "$n" ]; then tail -n "$n" "$f"; else cat "$f"; fi
    return 0
  fi
  if [ "$verb" = send ]; then printf '%s\n' "SEND:$6" >> "$SENT_LOG"; return 0; fi
  return 1
}

# One screen read as composer_content sees it (every read serves $POST_FILE).
read_post() { echo r >> "$READS_FILE"; hf_bounded() { windowed_hf_bounded "$@"; }; composer_content it2 sid; }

# A tall composer of $1 rows under a narrow footer, built the way Claude Code paints it.
mk_tall() { # $1=rows → $POST_FILE, and the payload it holds in $TALL_TEXT
  local rows="$1" r
  TALL_TEXT="/goal row1"
  { for r in $(seq 1 30); do echo "  transcript line $r"; done
    echo "✳ Elucidating… (1m 19s)"; echo ""; echo "$B"; echo "❯ /goal row1"
    for r in $(seq 2 "$rows"); do echo "  row$r"; done
    echo "$B"; echo "  (4) #203 bd0889f1 11% · goa…"; echo "  ⏵⏵ auto mode on (shift+tab"; } > "$POST_FILE"
  for r in $(seq 2 "$rows"); do TALL_TEXT="$TALL_TEXT row$r"; done
}

# ── 1. the incident screen ───────────────────────────────────────────────────────────────────

@test "[RED] pane 203's tall wrapped /goal reads back as exactly the payload (mid-turn, 32 cols)" {
  cp "$FX/pane203-tall-goal.txt" "$POST_FILE"; cp "$FX/pane203-tall-goal.ansi.txt" "$POST_FILE.ansi"
  run read_post
  [ "$status" -eq 0 ]
  paste_readback_ok "$GOAL" "$output"
}

@test "[RED] the arm sends its CR: paste + read-back + Enter on the pane-203 screen (rc 0)" {
  cp "$FX/pane203-tall-goal.txt" "$POST_FILE"; cp "$FX/pane203-tall-goal.ansi.txt" "$POST_FILE.ansi"
  hf_bounded() { windowed_hf_bounded "$@"; }
  run it2_paste_submit_verified it2 sid "$GOAL"
  [ "$status" -eq 0 ]
  grep -c 'SEND:' "$SENT_LOG" | grep -qx 2
  tail -1 "$SENT_LOG" | grep -q $'SEND:\r'
}

@test "[RED] composers of 20 to 50 rows all parse, and the small window alone could not" {
  local rows
  for rows in 20 23 30 40 50; do
    mk_tall "$rows"; : > "$READS_FILE"
    run read_post
    [ "$status" -eq 0 ] || { echo "rows=$rows rc=$status" >&2; return 1; }
    [ "$output" = "$(printf '%s' "$TALL_TEXT" | tr -d '[:space:]')" ]
    [ "$rows" -ge 23 ] || continue                             # shorter boxes fit 24 rows anyway
    : > "$READS_FILE"
    FIRE_COMPOSER_READLINES_MAX=24 run read_post               # the pre-fix behaviour, by its seam
    [ "$status" -eq 1 ]
  done
}

@test "a short composer is untouched: ONE read, no second window" {
  : > "$READS_FILE"; cp "$PRE_FILE" "$POST_FILE"
  run read_post
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(wc -l < "$READS_FILE")" -eq 2 ]                          # read_post's marker + one read
}

# ── 2. the fail-closed half ──────────────────────────────────────────────────────────────────

# A transcript built to fool a widened read: a column-0 rule, an echoed prompt shaped exactly like
# a composer (❯ row, two-space continuations) holding the payload, then the modal underneath.
mk_hostile() { # $1=modal fixture → $POST_FILE
  { for r in $(seq 1 30); do echo "  transcript line $r"; done
    echo "$B"; echo "❯ /goal row1"; echo "  row2"; cat "$1"; } > "$POST_FILE"
}

@test "every real modal fixture, alone and under a hostile transcript, never reads EMPTY or as the payload" {
  local m n=0
  for m in "$MODALS"/trust-dialog-* "$MODALS"/settings-error-dialog-* "$MODALS"/bgwork-dialog-* \
           "$MODALS"/resume-picker-* "$MODALS"/resume-return-menu-* "$FX/win527-teammate-panel.txt"; do
    n=$((n + 1))
    cp "$m" "$POST_FILE"; : > "$READS_FILE"
    run read_post
    if [ "$status" -eq 0 ]; then
      [ -n "$output" ] || { echo "EMPTY: $m" >&2; return 1; }
      ! paste_readback_ok "/goal row1 row2" "$output" || { echo "MATCH: $m" >&2; return 1; }
    fi
    mk_hostile "$m"; : > "$READS_FILE"
    run read_post
    if [ "$status" -eq 0 ]; then
      [ -n "$output" ] || { echo "EMPTY (hostile): $m" >&2; return 1; }
      ! paste_readback_ok "/goal row1 row2" "$output" || { echo "MATCH (hostile): $m" >&2; return 1; }
    fi
  done
  [ "$n" -ge 8 ]                                                # the fixtures were really there
}

@test "the win527 teammate panel (╭──╮ above, wrapped rule) stays UNKNOWN through the bigger window" {
  cp "$FX/win527-teammate-panel.txt" "$POST_FILE"
  run read_post
  [ "$status" -eq 3 ]                # UNKNOWN, static shape (tall-rejected)
}

@test "a paste that lands in a modal under a hostile transcript gets NO CR (rc 4)" {
  mk_hostile "$MODALS/trust-dialog-2.1.284.txt"
  hf_bounded() { windowed_hf_bounded "$@"; }
  run it2_paste_submit_verified it2 sid "/goal row1 row2"
  [ "$status" -eq 4 ]
  run ! grep -q $'SEND:\r' "$SENT_LOG"
}

@test "a modal on screen before the paste: nothing is typed at all (rc 2)" {
  cp "$MODALS/trust-dialog-2.1.284.txt" "$PRE_FILE"
  cp "$MODALS/trust-dialog-2.1.284.txt" "$POST_FILE"
  hf_bounded() { windowed_hf_bounded "$@"; }
  run it2_paste_submit_verified it2 sid "/goal x"
  [ "$status" -eq 2 ]
  [ ! -s "$SENT_LOG" ]
}

# Each shape check is load-bearing: break the box one way at a time and it must stay UNKNOWN —
# rc 3, the static shape a turn ending would not change (recycle-failures-kitty REPORT.md fix 3).
@test "each shape check refuses on its own: indented rule, no ❯ first row, odd continuation, selector below" {
  mk_tall 30; sed -i.bak "33s/^/ /" "$POST_FILE"                 # (ii) top rule not at column 0
  run read_post; [ "$status" -eq 3 ]
  mk_tall 30; sed -i.bak "34s/^❯/>/" "$POST_FILE"                # (iii) first row not the glyph
  : > "$READS_FILE"; run read_post; [ "$status" -eq 3 ]
  mk_tall 30; sed -i.bak "40s/^  /⏺ /" "$POST_FILE"              # (iv) a transcript row inside
  : > "$READS_FILE"; run read_post; [ "$status" -eq 3 ]
  mk_tall 30; echo "❯ 1. Yes" >> "$POST_FILE"                    # (v) a selector glyph under the border
  : > "$READS_FILE"; run read_post; [ "$status" -eq 3 ]
  mk_tall 30                                                     # and the unbroken box parses
  : > "$READS_FILE"; run read_post; [ "$status" -eq 0 ]
}

# ── 3. the same rule in lr-fire-resume.sh's screen program (LR_SCREEN_SH) ─────────────────────
# A second copy of the parse, run by expect through `bash -c`; it read the same 24-row window and
# lost the same screen (UNKNOWN for pane 203, so the DRAFT-MINE re-Enter rescue never fired).

lr_screen() { # → the LR_SCREEN_SH verdict for $POST_FILE through a window-honouring it2
  local prog
  prog="$(sed -n "/<<'LRSCREENSH'/,/^LRSCREENSH\$/p" "$REPO/scripts/limit-recover/lr-fire-resume.sh" | sed '1d;$d')"
  [ -n "$prog" ] || { echo "LR_SCREEN_SH extraction failed" >&2; return 1; }
  # shellcheck disable=SC2016  # the stub's own $vars, expanded when the stub runs
  printf '#!/bin/bash\nn=; for ((i=1;i<=$#;i++)); do [ "${!i}" = -n ] && { j=$((i+1)); n="${!j}"; }; done\nif [ -n "$n" ]; then tail -n "$n" "%s"; else cat "%s"; fi\n' "$POST_FILE" "$POST_FILE" > "$BATS_TEST_TMPDIR/lr-it2"
  chmod +x "$BATS_TEST_TMPDIR/lr-it2"
  LR_IT2="$BATS_TEST_TMPDIR/lr-it2" LR_PANE=x bash -c "$prog"
}

@test "[RED] LR_SCREEN_SH: pane 203's tall composer reads DRAFT-MINE, not UNKNOWN" {
  cp "$FX/pane203-tall-goal.txt" "$POST_FILE"
  LR_SCREEN_WANT="/goalalongwrapped/goalpastedintoanarrow" run lr_screen
  [ "$output" = DRAFT-MINE ]
  LR_SCREEN_WANT="/goalalongwrapped/goalpastedintoanarrow" LR_SCREEN_LINES_MAX=24 run lr_screen
  [ "$output" = UNKNOWN ]                                        # the pre-fix behaviour, by its seam
}

@test "LR_SCREEN_SH: every modal fixture, alone and under a hostile transcript, is never EMPTY or DRAFT-MINE" {
  local m n=0
  for m in "$MODALS"/trust-dialog-* "$MODALS"/settings-error-dialog-* "$MODALS"/bgwork-dialog-* \
           "$MODALS"/resume-picker-* "$MODALS"/resume-return-menu-* "$FX/win527-teammate-panel.txt"; do
    n=$((n + 1))
    cp "$m" "$POST_FILE"
    LR_SCREEN_WANT="row1row2" run lr_screen
    case "$output" in EMPTY|DRAFT-MINE) echo "$output: $m" >&2; return 1 ;; esac
    mk_hostile "$m"
    LR_SCREEN_WANT="row1row2" run lr_screen
    case "$output" in EMPTY|DRAFT-MINE) echo "$output (hostile): $m" >&2; return 1 ;; esac
  done
  [ "$n" -ge 8 ]
}

@test "LR_SCREEN_SH: each shape check refuses alone, and the unbroken tall box is ours" {
  mk_tall 30; sed -i.bak "33s/^/ /" "$POST_FILE"
  LR_SCREEN_WANT="/goalrow1row2" run lr_screen; [ "$output" = UNKNOWN ]
  mk_tall 30; sed -i.bak "34s/^❯/>/" "$POST_FILE"
  LR_SCREEN_WANT="/goalrow1row2" run lr_screen; [ "$output" = UNKNOWN ]
  mk_tall 30; sed -i.bak "40s/^  /⏺ /" "$POST_FILE"
  LR_SCREEN_WANT="/goalrow1row2" run lr_screen; [ "$output" = UNKNOWN ]
  mk_tall 30; echo "❯ 1. Yes" >> "$POST_FILE"
  LR_SCREEN_WANT="/goalrow1row2" run lr_screen; [ "$output" = MENU ]
  mk_tall 30
  LR_SCREEN_WANT="/goalrow1row2" run lr_screen; [ "$output" = DRAFT-MINE ]
}

# ── 4. the residue receipt holds content, never the `<unreadable>` sentinel ───────────────────
# 7 of 8 receipts on disk held the literal `<unreadable>`; composer_residue_is_ours compares byte
# for byte, so none could ever authorise the scrub its own note promised.

@test "an unreadable mismatch records the PAYLOAD as the receipt, and that receipt is ours once the box reads" {
  printf 'half-drawn assistant output\nno box on screen yet\n' > "$POST_FILE"
  hf_bounded() { windowed_hf_bounded "$@"; }
  local rc=0
  CC_COMPOSER_SCRUB=on FIRE_PASTE_READBACK_TRIES=2 it2_paste_submit_verified it2 sid-R "/goal reply with DONE" 2>/dev/null || rc=$?
  [ "$rc" -eq 4 ]
  [ "$FIRE_PASTE_LAST_READBACK" = "<unreadable>" ]                # the observation is unchanged
  [ "$FIRE_PASTE_SCRUB" = receipted-unreadable ]
  run ! grep -q '<unreadable>' "$CC_COMPOSER_RESIDUE_DIR/sid-R"
  composer_residue_is_ours sid-R "/goalreplywithDONE"
  run ! grep -q $'SEND:\r' "$SENT_LOG"
}

@test "a readable mismatch with the scrub off records the WHOLE read, not a 120-char cut" {
  local long; long="$(printf 'x%.0s' $(seq 1 200))"
  { echo "$B"; echo "❯ $long"; echo "$B"; echo "  (4) status"; } > "$POST_FILE"
  hf_bounded() { windowed_hf_bounded "$@"; }
  local rc=0
  FIRE_PASTE_READBACK_TRIES=2 it2_paste_submit_verified it2 sid-L "/goal y" 2>/dev/null || rc=$?
  [ "$rc" -eq 4 ]
  composer_residue_is_ours sid-L "$long"
}

# ── 5. a CAPPED box, and a dialog drawn ABOVE the composer ────────────────────────────────────
# Claude Code caps the composer (18 rows on a 46-row pane, measured live on a throwaway pane) and
# scrolls it to the cursor, so a tall box's first visible row is a continuation, not ❯. On a 62-row
# pane the cap is taller than the 24-row window, so that box reaches the bigger read — where it may
# only ever match the TAIL of our own text, never read EMPTY.

mk_capped() { # a 62-row screen: a 24-row capped box showing only the END of $1 words → $POST_FILE
  local words="$1" r
  CAP_TEXT="/goal head"; for r in $(seq 1 "$words"); do CAP_TEXT="$CAP_TEXT w$r"; done
  { for r in $(seq 1 30); do echo "  transcript line $r"; done
    echo "$B"
    for r in $(seq $((words - 23)) "$words"); do echo "  w$r"; done
    echo "$B"; echo "  (4) #203 status"; echo "  ⏵⏵ auto mode on"; } > "$POST_FILE"
}

@test "[RED] a capped, scrolled box taller than 24 rows matches the payload by its tail, and gets its CR" {
  mk_capped 120
  run read_post
  [ "$status" -eq 0 ]
  paste_readback_ok "$CAP_TEXT" "$output"
  hf_bounded() { windowed_hf_bounded "$@"; }
  : > "$READS_FILE"
  run it2_paste_submit_verified it2 sid "$CAP_TEXT"
  [ "$status" -eq 0 ]
  tail -1 "$SENT_LOG" | grep -q $'SEND:\r'
}

@test "a scrolled box is never proof of EMPTY: blank continuation rows read UNKNOWN" {
  { for r in $(seq 1 30); do echo "  transcript line $r"; done
    echo "$B"; for r in $(seq 1 26); do echo "  "; done
    echo "$B"; echo "  (4) #203 status"; } > "$POST_FILE"
  run read_post
  [ "$status" -eq 1 ]
}

@test "the real 2.1.293 capped box (46-row pane) reads back by its tail" {
  cp "$FX/capped-scrolled-2.1.293-46row.txt" "$POST_FILE"; cp "$FX/capped-scrolled-2.1.293-46row.ansi.txt" "$POST_FILE.ansi"
  run read_post
  [ "$status" -eq 0 ]
  paste_readback_ok "$(cat "$FX/capped-scrolled-2.1.293-46row.payload.txt")" "$output"
}

@test "the real 2.1.293 trust dialog in an 18-column pane reads UNKNOWN" {
  cp "$FX/trust-dialog-2.1.293-18col.txt" "$POST_FILE"
  run read_post
  [ "$status" -eq 1 ]
}

@test "[RED] a dialog drawn ABOVE a live composer (real 2.1.260 captures) reads UNKNOWN, so nothing is typed" {
  local m
  for m in "$REPO/tests/fixtures/teammate-probe/captures/p1-run2-exitmodal/pane-before.txt" \
           "$REPO/tests/fixtures/teammate-probe/captures/p1-run2/lead-pane.after-exit.txt"; do
    cp "$m" "$POST_FILE"; : > "$READS_FILE"
    run read_post
    [ "$status" -eq 3 ] || { echo "rc=$status [$output]: $m" >&2; return 1; }
  done
  cp "$POST_FILE" "$PRE_FILE"
  hf_bounded() { windowed_hf_bounded "$@"; }
  : > "$READS_FILE"
  run it2_paste_submit_verified it2 sid "/goal x"
  [ "$status" -eq 2 ]
  [ ! -s "$SENT_LOG" ]
}

@test "[RED] the SLASH-COMMAND menu above a narrow box is not a dialog: pane 168's /exit reads back as /exit" {
  # Pane 168, 38 columns, 2026-10-11: typing /exit opened the suggestion menu ABOVE the box, its
  # highlighted row "❯ /exit  Exit the CLI" read as a dialog, and the read-back held the recycle.
  { echo "  Then close this pane."; echo ""; echo "  Original prompt: "; echo ""
    echo "  ❯ /exit          Exit the CLI"; echo "    /context       Visualize current"; echo "                   context usage as…"
    echo "$B"; echo "❯ /exit"; echo "$B"; echo "  (2) #168 186452ed 26% · wt-cc…"; } > "$POST_FILE"
  run read_post
  [ "$status" -eq 0 ] || { echo "rc=$status [$output]"; false; }
  [ "$output" = /exit ] || { echo "[$output]"; false; }
  # CONTROL: the same screen with a real dialog option above the box still reads UNKNOWN.
  sed -i.bak 's/❯ \/exit          Exit the CLI/❯ 1. Exit and stop tasks/' "$POST_FILE"
  run read_post
  [ "$status" -eq 3 ] || { echo "rc=$status [$output]"; false; }
  # KILL SWITCH: HF_COMPOSER_SLASH_MENU=off restores the old rule.
  sed -i.bak 's/❯ 1. Exit and stop tasks/❯ \/exit          Exit the CLI/' "$POST_FILE"
  HF_COMPOSER_SLASH_MENU=off run read_post
  [ "$status" -eq 3 ] || { echo "rc=$status [$output]"; false; }
}

@test "an indented rule pair (an empty composer printed in tool output) is not a box" {
  { echo "  ⎿  $B"; echo "     ❯ "; echo "     $B"; echo "  Do you want to proceed?"; } > "$POST_FILE"
  run read_post
  [ "$status" -eq 1 ]
}
