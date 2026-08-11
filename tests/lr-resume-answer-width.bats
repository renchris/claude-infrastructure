#!/usr/bin/env bats
# lr-fire-resume.sh — the resume answer must not depend on the terminal width, and must select
# "Resume full session as-is".
#
# THE DEFECT (c4b016c2d2a6). The arms matched LITERAL phrases — `Resume from summary
# \(recommended\)`, `Quick safety check`, `new fullscreen renderer`. A literal is a property of the
# prompt AT ONE WIDTH. Three transplants parked 20+ minutes at the menu in panes of 8 and ~18
# columns on 2026-08-10 and all three needed hand-answering. The polarity is the worst kind: panes
# get narrower as more sessions are split in, so it fails hardest exactly when a recovery matters,
# and it is green in any wide dev pane.
#
# THE SECOND DEFECT (d1490376b963). The old arm pressed Enter on the HIGHLIGHTED DEFAULT, option 1,
# `Resume from summary (recommended)` — which runs /compact, spends usage, loses fidelity and drops
# the session's /goal. Option 2 is `Resume full session as-is`, and a moved session must come back
# as-is. So the script answered the opposite of the requirement, silently.
#
# WHAT THE FIXTURES ARE. `tests/fixtures/lr-resume/real-select-{8,20,40,80}.raw` are REAL captures
# of Claude Code 2.1.220 rendering its select component at those widths, taken through a pty sized
# before the first frame. The resume-return menu itself cannot be captured headlessly (it is gated
# on a server-side flag that is off for an unauthenticated process), but it renders through the SAME
# component — `jr` in the bundle, which is also what the theme picker uses — so the captures pin the
# component's real wrapping, its real ordinals, and its real interleaved colour escapes. The modelled
# renderer is used for the resume menu's own labels ONLY after it is pinned against those captures.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  FIX="$REPO/tests/fixtures/lr-resume"
  # The subject reads $HOME (account map, capacity-admit library, the model SSOT) and the wiring
  # tests EXECUTE it, so an unfixtured HOME would run this suite against the operator's live
  # install — and the resume path writes. Every state root the subject touches is redirected:
  # HOME here, LR_STATE_DIR per drive().
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"

  eval "$(sed -n '/^lr_wrap_re() {/,/^}/p' "$FIRE")"
  command -v lr_wrap_re >/dev/null || { echo "extraction of lr_wrap_re from $FIRE failed" >&2; return 1; }

  # An expect(1) matcher, driven from a FILE. `expect -c` mangles a regex carrying raw ESC bytes,
  # and — measured while building this suite — `exit N` inside a pattern body after a `spawn`
  # returns 0 regardless, so an exit-code harness reports MATCH for everything including a pattern
  # that is definitely absent. The verdict is therefore a parsed TOKEN, never a status.
  cat > "$BATS_TEST_TMPDIR/match.exp" <<'EXP'
set timeout 10
match_max 400000
log_user 0
set vf [open $env(LR_V) w]
spawn -noecho cat $env(LR_FILE)
expect {
  -re $env(LR_RE) { puts $vf "MATCH" }
  eof             { puts $vf "NOMATCH" }
  timeout         { puts $vf "TIMEOUT" }
}
close $vf
EXP
}

# → MATCH | NOMATCH | TIMEOUT
match_in() { # regex file
  LR_RE="$1" LR_FILE="$2" LR_V="$BATS_TEST_TMPDIR/v" expect -f "$BATS_TEST_TMPDIR/match.exp" >/dev/null 2>&1
  cat "$BATS_TEST_TMPDIR/v"
}

# ── the matcher, against REAL rendered bytes ─────────────────────────────────────────────────────

@test "the harness can say NO — an absent pattern is NOMATCH at every width" {
  # Without this every assertion below could be passing vacuously on a matcher that never refuses.
  for w in 8 20 40 80; do
    [ "$(match_in 'ZZZ_DEFINITELY_ABSENT_ZZZ' "$FIX/real-select-$w.raw")" = NOMATCH ] \
      || { echo "width $w: the matcher matched a pattern that is not there"; false; }
  done
}

@test "THE BUG: a literal phrase match fails on the real render — at EVERY width, not just narrow" {
  # The anchoring control, and it corrects the framing of the bug report. The literal
  # `Dark mode (colorblind-friendly)` is absent even at 80 columns, because a colour escape sits
  # between "mode " and "(colorblind". Narrow panes made it visible; the literal was never sound.
  for w in 8 20 40 80; do
    [ "$(match_in 'Dark mode \(colorblind-friendly\)' "$FIX/real-select-$w.raw")" = NOMATCH ] \
      || { echo "width $w: literal matched — fixture no longer reproduces the defect"; false; }
  done
}

@test "the width-invariant matcher finds the phrase at 8, 20, 40 and 80 columns" {
  re="$(lr_wrap_re 'Choose the text style that looks best with your terminal')"
  for w in 8 20 40 80; do
    [ "$(match_in "$re" "$FIX/real-select-$w.raw")" = MATCH ] \
      || { echo "width $w: width-invariant matcher missed the phrase"; false; }
  done
}

@test "the selector readback is ordinal-anchored and discriminates at 8 columns" {
  # The readback is what makes selecting option 2 safe. In these captures the pointer sits on
  # option 2, so `❯2.` must match and `❯1.` must not — at every width, including 8, where the
  # option LABEL is truncated by the component and only the ordinal survives.
  on2="$(lr_wrap_re '❯2. Dark mode')"
  on1="$(lr_wrap_re '❯1. Auto')"
  for w in 8 20 40 80; do
    [ "$(match_in "$on2" "$FIX/real-select-$w.raw")" = MATCH ] \
      || { echo "width $w: readback failed to confirm the selector it IS on"; false; }
    [ "$(match_in "$on1" "$FIX/real-select-$w.raw")" = NOMATCH ] \
      || { echo "width $w: readback confirmed an option the selector is NOT on"; false; }
  done
}

@test "FIDELITY PIN: the modelled renderer reproduces the real captures' matcher verdicts" {
  # The resume menu cannot be captured headlessly, so its frames are modelled. A model that has
  # never been replayed against the real artifact can pass vacuously — so before the model is used
  # for the resume labels, it must answer every matcher question exactly as the real bytes do.
  labels=('Auto (match terminal)' 'Dark mode' 'Light mode' 'Dark mode (colorblind-friendly)')
  python3 "$FIX/render_select.py" 8 1 "${labels[@]}" > "$BATS_TEST_TMPDIR/model-8.raw"
  for w in 8 20 40 80; do
    python3 "$FIX/render_select.py" "$w" 1 "${labels[@]}" > "$BATS_TEST_TMPDIR/model-$w.raw"
    [ "$(match_in "$(lr_wrap_re '❯2. Dark mode')" "$BATS_TEST_TMPDIR/model-$w.raw")" = MATCH ] \
      || { echo "width $w: model disagrees with the real capture on the readback"; false; }
    [ "$(match_in "$(lr_wrap_re '❯1. Auto')" "$BATS_TEST_TMPDIR/model-$w.raw")" = NOMATCH ] \
      || { echo "width $w: model disagrees with the real capture on the negative readback"; false; }
    [ "$(match_in 'Dark mode \(colorblind-friendly\)' "$BATS_TEST_TMPDIR/model-$w.raw")" = NOMATCH ] \
      || { echo "width $w: model does not reproduce the literal-match failure"; false; }
  done
}

# ── the WIRING — the real expect program, answered by a real select on the other end ─────────────
# Every assertion above tests the matcher. All of them stay green if the arm is deleted, or if it
# fires and then presses the wrong key. These drive lr-fire-resume.sh itself against a stand-in
# binary that renders the menu, MOVES its selector on Down, and records what it received.

MENU_LABELS=$'Resume from summary (recommended)\x1fResume full session as-is\x1fDon\'t ask me again'

drive() { # width [extra lr-fire-resume args...] → keylog on stdout
  local w="$1"; shift
  local cfg="$BATS_TEST_TMPDIR/cfg" wt="$BATS_TEST_TMPDIR/wt-$w-$RANDOM"
  mkdir -p "$cfg" "$wt"
  : > "$BATS_TEST_TMPDIR/keylog"
  cat > "$BATS_TEST_TMPDIR/fakebin" <<EOF
#!/bin/bash
exec python3 "$FIX/fake-claude.py"
EOF
  chmod +x "$BATS_TEST_TMPDIR/fakebin"
  CC_CLAUDE_BIN="$BATS_TEST_TMPDIR/fakebin" \
  CC_ADMIT_GATE=off \
  LR_STATE_DIR="$BATS_TEST_TMPDIR/state" \
  LR_TEST_WIDTH="$w" \
  LR_TEST_KEYLOG="$BATS_TEST_TMPDIR/keylog" \
  LR_TEST_LABELS="$MENU_LABELS" \
  LR_TEST_REPAINT_AFTER_SUBMIT="${LR_TEST_REPAINT_AFTER_SUBMIT:-}" \
    timeout 90 bash "$FIRE" "$cfg" "$wt" "sid-under-test" \
      --model claude-opus-5 --effort high "$@" >/dev/null 2>&1 || true
  cat "$BATS_TEST_TMPDIR/keylog"
}

@test "WIRING: with the source suppression FORCED OFF, the menu is answered AS-IS at every width" {
  # The lead's requirement, and the reason this arm is not dead code. The suppression below is
  # version-coupled — it reads an env var through an internal symbol of the 2.1.220 bundle — so a
  # binary upgrade can drop it and the menu comes back. A fallback with no test is a fallback we
  # discover is broken during the next recovery.
  for w in 8 20 40 80; do
    log="$(LR_RESUME_SUPPRESS=off drive "$w")"
    [[ "$log" == *"DOWN"* ]] \
      || { echo "width $w: selector never moved off option 1 — keylog: $log"; false; }
    [[ "$log" == *"SUBMIT:1:Resume full session as-is"* ]] \
      || { echo "width $w: did not commit option 2 — keylog: $log"; false; }
  done
}

@test "WIRING: it moves the selector exactly once and never reaches option 3" {
  log="$(LR_RESUME_SUPPRESS=off drive 8)"
  [[ "$log" != *"SUBMIT:2:"* ]] || { echo "committed option 3 — keylog: $log"; false; }
  downs="$(printf '%s\n' "$log" | grep -c '^DOWN$' || true)"
  [ "$downs" -eq 1 ] || { echo "expected exactly one Down, got $downs — keylog: $log"; false; }
}

@test "WIRING: the arm answers ONCE — a repaint after the answer must not re-fire it" {
  # The answered-once latch. The arm ends in exp_continue, and the dialog repaints on its way out
  # with the selector back on option 1 — so without the latch the arm matches its own trigger a
  # second time and sends another Down and CR. By then the dialog is gone, so those keys land in
  # the COMPOSER of the recovered session: a stray newline submits whatever is sitting in it.
  #
  # This test exists because the first mutant run for this site SURVIVED: the original assertion
  # only counted keystrokes up to the answer, so it could not see anything that happened after it.
  log="$(LR_RESUME_SUPPRESS=off LR_TEST_REPAINT_AFTER_SUBMIT=1 drive 8)"
  submits="$(printf '%s\n' "$log" | grep -c '^SUBMIT:' || true)"
  [ "$submits" -eq 1 ] || { echo "answered $submits times — keylog: $log"; false; }
  [[ "$log" != *"AFTER-SUBMIT:"* ]] \
    || { echo "the arm re-fired into the composer after answering — keylog: $log"; false; }
}

@test "WIRING: --summary is the OPT-IN, and it selects option 1" {
  log="$(drive 8 --summary)"
  [[ "$log" == *"SUBMIT:0:Resume from summary (recommended)"* ]] \
    || { echo "--summary did not select the summary option — keylog: $log"; false; }
  [[ "$log" != *"DOWN"* ]] || { echo "--summary moved the selector — keylog: $log"; false; }
}

@test "WIRING: the DEFAULT suppresses the menu at the source, asserted from the value the child saw" {
  # Positively, not by absence: "no menu appeared" is also what a hang looks like. The stand-in
  # records the threshold it was actually handed, and announces that it came up on the full
  # transcript.
  log="$(LR_TEST_SILENT=1 drive 8)"
  [[ "$log" == *"ENV:CLAUDE_CODE_RESUME_THRESHOLD_MINUTES=999999999"* ]] \
    || { echo "the resume-summary prompt was NOT suppressed for the child — keylog: $log"; false; }
  [[ "$log" == *"RESUMED-AS-IS"* ]] || { echo "session did not come up as-is — keylog: $log"; false; }
}

@test "WIRING: --summary does NOT suppress the prompt — the opt-in must still be able to reach it" {
  log="$(LR_TEST_SILENT=1 drive 8 --summary)"
  [[ "$log" == *"ENV:CLAUDE_CODE_RESUME_THRESHOLD_MINUTES=<unset>"* ]] \
    || { echo "--summary suppressed the very prompt it opts into — keylog: $log"; false; }
}
