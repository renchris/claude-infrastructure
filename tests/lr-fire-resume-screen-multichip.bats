#!/usr/bin/env bats
# lr-fire-resume.sh LR_SCREEN_SH — a box of SEVERAL paste chips plus a tail of OUR prompt is ours.
#
# THE INCIDENT (lr-wake 2026-10-18, pane 430, e §2). A 2,050-byte rescue brief was typed as raw keys
# and Claude Code collapsed it into `[Pasted text #1][Pasted text #2]re) -->`, the last 7 characters
# landing as text. The reader stripped only the FIRST chip (`${body#*]}`), so the "tail" it compared
# was `[Pastedtext#2]re)-->`, which is in no prompt: DRAFT, no second Enter, and an unsubmitted box
# that every verified rail then held on for 8 h. This is the fourth time a chip shape beat the reader
# (751, 815, 4fe9935f); the delivery fix is in lr-fire-resume-inject-atomic.bats, this pins the reader.
#
# The tail needle is DERIVED by the subject's own lines (_lrf_ink + LR_SCREEN_TAIL), not restated.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off      # hermeticity ratchet: never read live machine load
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0 CC_ADMIT_HEADROOM_OVERRIDE=64 CC_ADMIT_RESERVE_TERM=off
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue"
  PROG="$(sed -n "/<<'LRSCREENSH'/,/^LRSCREENSH\$/p" "$FIRE" | sed '1d;$d')"
  [ -n "$PROG" ] || { echo "LR_SCREEN_SH extraction failed" >&2; return 1; }
  INK="$(grep -E '^_lrf_ink\(\) \{' "$FIRE")"
  TAILDEF="$(grep -E '^LR_SCREEN_TAIL=' "$FIRE")"
  [ -n "$INK" ] && [ -n "$TAILDEF" ] || { echo "the tail derivation moved — its anchors are stale" >&2; return 1; }
  # pane 430's payload, flattened as :807 flattens it: the rescue line, the self-retire block, and the
  # engagement marker it ends on. Only the tail matters to this reader; the body length is realistic.
  BRIEF="[limit-recover rescue] This session was moved next4 -> next2 and its relaunch never verified. $(printf 'ON COMPLETION — SELF-RETIRE (do NOT idle) %.0s' $(seq 1 40))<!-- handoff-fire engagement marker: HANDOFF-ENGAGE-98707-1792317953-3219 (ignore) -->"
  LR_SCREEN_TAIL="$(PROMPT="$BRIEF" bash -c "$INK"'
'"$TAILDEF"'
printf "%s" "$LR_SCREEN_TAIL"')"
  [ -n "$LR_SCREEN_TAIL" ] || { echo "the subject derived no tail" >&2; return 1; }
  export LR_SCREEN_TAIL
  IT2="$BATS_TEST_TMPDIR/it2"
  # shellcheck disable=SC2016  # the stub's own $vars
  printf '#!/bin/bash\ncat "$SCR"\n' > "$IT2"; chmod +x "$IT2"
  export SCR="$BATS_TEST_TMPDIR/screen"
}

box() { # $1 = the composer row → the LR_SCREEN_SH verdict for a real-shaped box holding it
  local b='────────────────────────────────'
  printf '%s\n' "✻ Churned for 41s · done 1:02 AM" "$b" "❯ $1" "$b" "  ? for shortcuts" > "$SCR"
  LR_IT2="$IT2" LR_PANE=430 LR_SCREEN_WANT="[limit-recoverrescue]Thissessionwasmoved" \
    LR_SCREEN_NONCE="" LR_SCREEN_NL="" bash -c "$PROG"
}

@test "RED-PROOF the pane-430 box, two chips and our 7-character tail, reads DRAFT-MINE" {
  [ "$(box '[Pasted text #1][Pasted text #2]re) -->')" = DRAFT-MINE ]
}

@test "one chip and a tail fragment still reads DRAFT-MINE (pane 815, unchanged)" {
  [ "$(box '[Pasted text #1]re) -->')" = DRAFT-MINE ]
  [ "$(box '[Pasted text #1 +3 lines][Pasted text #2](ignore) -->')" = DRAFT-MINE ]
}

@test "controls: text before the chips, a stranger's tail, or one character stay DRAFT" {
  [ "$(box 'foo[Pasted text #1]re) -->')" = DRAFT ]
  [ "$(box '[Pasted text #1][Pasted text #2]please fix the build')" = DRAFT ]
  [ "$(box '[Pasted text #1][Pasted text #2]>')" = DRAFT ]
  [ "$(box '[Pasted text #1][Pasted text #2]')" = DRAFT ]
}

@test "at an unsubmitted verdict the box is filed as residue, and composer-intent then clears it" {
  # LR_SCREEN_RECORD=1 is what the expect program sets at NOT SUBMITTED / UNSUBMITTED; without it a
  # read writes nothing, so an ordinary look never files a residue.
  [ "$(box '[Pasted text #1][Pasted text #2]re) -->')" = DRAFT-MINE ]
  [ ! -e "$CC_COMPOSER_RESIDUE_DIR/430" ] || { echo "a plain look filed a residue"; false; }
  export LR_SCREEN_RECORD=1
  box '[Pasted text #1][Pasted text #2]re) -->' >/dev/null
  [ -f "$CC_COMPOSER_RESIDUE_DIR/430" ] || { echo "no residue was filed"; false; }
  run bash -c '. "$1"; composer_unintended_class "[Pastedtext#1][Pastedtext#2]re)-->" 430' _ "$REPO/scripts/lib/composer-intent.sh"
  [ "$status" -eq 0 ] || { echo "class: $output (rc $status)"; false; }
  [ "$output" = rail-residue ] || { echo "class: $output (rc $status)"; false; }
  # a stranger's box is never filed, because only DRAFT-MINE files
  rm -f "$CC_COMPOSER_RESIDUE_DIR/430"
  box 'git status --porcelain' >/dev/null
  [ ! -e "$CC_COMPOSER_RESIDUE_DIR/430" ] || { echo "a draft was filed as residue"; false; }
}
