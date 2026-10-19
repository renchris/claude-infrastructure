#!/usr/bin/env bats
# scripts/lib/composer-intent.sh — which composer contents are NOT a draft. Every row of the
# "unintended" table is a shape measured on a live limited pane on 2026-09-27; every draft row is a
# shape that must keep the old refusal. The polarity that matters is the second list: a false
# "unintended" destroys operator text, a false "draft" only strands a recovery.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_COMPOSER_DISCARD_LOG="$BATS_TEST_TMPDIR/discarded.log"
  export CC_FIRE_CAPACITY_GATE=off      # hermeticity ratchet: never read live machine load
  # …and capacity-admit's terms pinned, because a K8 case reads lr-fire-resume.sh, which sources it
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0 CC_ADMIT_HEADROOM_OVERRIDE=64 CC_ADMIT_RESERVE_TERM=off
  unset CC_COMPOSER_UNINTENDED CC_COMPOSER_STRAY_MAX
  # shellcheck disable=SC1091
  . "$REPO/scripts/lib/composer-intent.sh"
}

cls() { composer_unintended_class "$1" || printf 'DRAFT'; }

@test "the four measured 2026-09-27 panes each classify as NOT a draft" {
  [ "$(cls 'I')" = stray-keystroke ]                                                            # 815
  [ "$(cls 'Youwereresumedonaccountnext2afteraweeklylimitonnext(waspane780).Continuetheworky')" = rail-prompt ]   # 814
  [ "$(cls '[Pastedtext#1]Z:16ba1a46')" = rail-token ]                                          # 751
  [ "$(cls '_Ga=d,d=I,i=7110,q=225h')" = terminal-reply ]                                       # 810
}

@test "every prompt this rail types is recognised by its prefix" {
  [ "$(cls '[limit-recover]Theusagelimitispastandnext2hasheadroom.Continue')" = rail-prompt ]
  [ "$(cls '/limit-recoveringest/Users/x/bundle')" = rail-prompt ]
  [ "$(cls 'Resumedinplaceonnext—samepane,samesession18e3fd78')" = rail-prompt ]
  [ "$(cls 'OPUS55-UPGRADE(operatorrequest):relaunch')" = rail-prompt ]
  [ "$(cls '[operator-rulingcc-lr-switchreq=abc]RuninBashnow')" = rail-prompt ]
}

@test "handoff-fire's own unsubmitted /goal arm is rail-goal; a hand-typed /goal stays a draft" {
  [ "$(cls '/goaldocs/research/session-durability.mdlandedonorigin/main—provenbygitls-tree;donotchangecodeoutsidedocs/;fullbriefinthepromptabove,DoDatdocs/plans/kitty-deadlock-recovery-2026-10-01.md')" = rail-goal ]   # pane 41
  [ "$(cls '/goalthetestsaregreen')" = DRAFT ]
  [ "$(cls 'pleasereadthefullbriefinthepromptabove')" = DRAFT ]
}

@test "a submit token counts only at the END, alone or behind a paste chip" {
  [ "$(cls 'anything(submittoken:run:18e3fd78:20260927T054318Z:16ba1a46)')" = rail-token ]
  [ "$(cls '[Pastedtext#2+3lines]Z:16ba1a46)')" = rail-token ]
  [ "$(cls '[Pastedtext#1]2bd7')" = rail-token ]             # pane 815: half the nonce after the chip
  [ "$(cls '[Pastedtext#1]ab')" = rail-token ]
  [ "$(cls '[Pastedtext#1]a')" = DRAFT ]                     # one character is not evidence
  [ "$(cls '[Pastedtext#1]fixthis')" = DRAFT ]               # words after a chip are a human's
  [ "$(cls 'see(submittoken:run:18e3fd78:20260927T054318Z:16ba1a46)andfixit')" = DRAFT ]
  [ "$(cls '[Pastedtext#1]')" = DRAFT ]                    # an operator paste looks exactly like this
  [ "$(cls '[Pastedtext#1]andmynotes')" = DRAFT ]
}

@test "terminal replies: kitty graphics, DA1, DECRQM, XTVERSION, OSC colour" {
  [ "$(cls '_Gi=31;OK')" = terminal-reply ]
  [ "$(cls '[?62;52;c')" = terminal-reply ]
  [ "$(cls '[?2026;2$y')" = terminal-reply ]
  [ "$(cls 'P>|kitty(0.48.2)')" = terminal-reply ]
  [ "$(cls ']11;rgb:1e1e/1e1e/2e2e')" = terminal-reply ]
}

@test "drafts stay drafts: real words, a slash command, and three characters" {
  [ "$(cls 'shipthebragfilm')" = DRAFT ]
  [ "$(cls 'IalsothinkVIPDeck1needsmoremargintop')" = DRAFT ]
  [ "$(cls '/c')" = DRAFT ]
  [ "$(cls 'yes')" = DRAFT ]
  [ "$(cls '')" = DRAFT ]
}

@test "CC_COMPOSER_STRAY_MAX bounds the stray class" {
  [ "$(cls 'ok')" = stray-keystroke ]
  export CC_COMPOSER_STRAY_MAX=1
  [ "$(cls 'ok')" = DRAFT ]
  [ "$(cls 'I')" = stray-keystroke ]
}

@test "kill switch: CC_COMPOSER_UNINTENDED=off makes every non-empty composer a draft" {
  export CC_COMPOSER_UNINTENDED=off
  [ "$(cls 'I')" = DRAFT ]
  [ "$(cls '_Ga=d,d=I')" = DRAFT ]
  [ "$(cls '[limit-recover]x')" = DRAFT ]
}

# ── K8 (lr-wake 2026-10-18): rail-exit, multi-chip rail-token, rail-residue ─────────────────────────
cls_at() { composer_unintended_class "$1" "$2" || printf 'DRAFT'; }

@test "K8 rail-exit: an exact /exit is the rail's own; anything else after the slash stays a draft" {
  [ "$(cls '/exit')" = rail-exit ]            # pane 384's leftover, carried into its successor
  [ "$(cls '/exitnow')" = DRAFT ]
  [ "$(cls '/exit-plan')" = DRAFT ]
  [ "$(cls '/ex')" = DRAFT ]
}

@test "K8 rail-token: two chips plus a token are what a paste leaves; words after them are not" {
  [ "$(cls '[Pastedtext#1][Pastedtext#2]Z:16ba1a46)')" = rail-token ]
  [ "$(cls '[Pastedtext#1][Pastedtext#2+3lines]2bd7')" = rail-token ]
  [ "$(cls '[Pastedtext#1][Pastedtext#2][Pastedtext#3]9f3a)')" = rail-token ]
  [ "$(cls '[Pastedtext#1][Pastedtext#2]fixthis')" = DRAFT ]
  [ "$(cls 'note[Pastedtext#1][Pastedtext#2]2bd7')" = DRAFT ]
  [ "$(cls '[Pastedtext#1][Pastedtext#2]')" = DRAFT ]
}

@test "K8 rail-residue: the 430 box is cleared only when this pane recorded exactly that box" {
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue"; mkdir -p "$CC_COMPOSER_RESIDUE_DIR"
  local box='[Pastedtext#1][Pastedtext#2]re)-->'
  [ "$(cls_at "$box" 430)" = DRAFT ]                                         # no record: an operator's
  printf '2026-10-18T10:07:12Z\t[Pasted text #1][Pasted text #2]re) -->\n' > "$CC_COMPOSER_RESIDUE_DIR/430"
  [ "$(cls_at "$box" 430)" = rail-residue ]                                  # recorded raw, compared stripped
  [ "$(cls_at "${box}x" 430)" = DRAFT ]                                      # one byte more is not it
  [ "$(cls_at "$box" 431)" = DRAFT ]                                         # another pane's record
  [ "$(cls "$box")" = DRAFT ]                                                # no pane id: nothing to match
  export CC_COMPOSER_UNINTENDED=off
  [ "$(cls_at "$box" 430)" = DRAFT ]                                         # the kill switch still wins
}

@test "K8 the dim suggestion reads EMPTY through LR_SCREEN_SH; the same row typed for real is a draft" {
  # Claude Code paints its prompt suggestion faint (ESC[22;2m) inside the box; the plain read cannot
  # see that, so pane 23's `/goal clear` read as a draft (RC5, h defect 4). --ansi is what tells them apart.
  local prog b='────────────────────────────────' d=$'\e[22;2m' n=$'\e[22m'
  prog="$(sed -n "/<<'LRSCREENSH'/,/^LRSCREENSH\$/p" "$REPO/scripts/limit-recover/lr-fire-resume.sh" | sed '1d;$d')"
  [ -n "$prog" ] || { echo "LR_SCREEN_SH extraction failed"; false; }
  local it2="$BATS_TEST_TMPDIR/it2"
  # shellcheck disable=SC2016  # the stub's own $vars
  printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = --ansi ] && { cat "$SCR_ANSI"; exit 0; }; done\ncat "$SCR_PLAIN"\n' > "$it2"
  chmod +x "$it2"
  export SCR_ANSI="$BATS_TEST_TMPDIR/ansi" SCR_PLAIN="$BATS_TEST_TMPDIR/plain"
  printf '%s\n' "  chrome" "${d}${b}${n}" " ❯ ${d}/goal clear${n}" "${d}${b}${n}" " ? for shortcuts" > "$SCR_ANSI"
  printf '%s\n' "  chrome" "$b" " ❯ /goal clear" "$b" " ? for shortcuts" > "$SCR_PLAIN"
  run env LR_IT2="$it2" LR_PANE=23 LR_SCREEN_WANT="" bash -c "$prog"
  [ "$output" = EMPTY ] || { echo "a faint suggestion read '$output', not EMPTY"; false; }
  # the same text NOT faint is someone's draft
  printf '%s\n' "  chrome" "$b" " ❯ "$'\e[39m'"/goal clear"$'\e[39m' "$b" " ? for shortcuts" > "$SCR_ANSI"
  run env LR_IT2="$it2" LR_PANE=23 LR_SCREEN_WANT="" bash -c "$prog"
  [ "$output" = DRAFT ] || { echo "a typed row read '$output', not DRAFT"; false; }
  # a reader that refuses --ansi falls back to the plain read, which cannot tell: DRAFT, as before
  printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = --ansi ] && exit 2; done\ncat "$SCR_PLAIN"\n' > "$it2"
  run env LR_IT2="$it2" LR_PANE=23 LR_SCREEN_WANT="" bash -c "$prog"
  [ "$output" = DRAFT ] || { echo "the plain fallback read '$output'"; false; }
}

@test "composer_discard_note keeps what was discarded, one line per discard" {
  composer_discard_note 815 stray-keystroke I
  composer_discard_note 751 rail-token '[Pastedtext#1]Z:16ba1a46'
  [ "$(wc -l < "$CC_COMPOSER_DISCARD_LOG" | tr -d ' ')" = 2 ]
  grep -q $'pane=815\tclass=stray-keystroke\tI$' "$CC_COMPOSER_DISCARD_LOG"
}
