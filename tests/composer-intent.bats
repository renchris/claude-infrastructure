#!/usr/bin/env bats
# scripts/lib/composer-intent.sh — which composer contents are NOT a draft. Every row of the
# "unintended" table is a shape measured on a live limited pane on 2026-09-27; every draft row is a
# shape that must keep the old refusal. The polarity that matters is the second list: a false
# "unintended" destroys operator text, a false "draft" only strands a recovery.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_COMPOSER_DISCARD_LOG="$BATS_TEST_TMPDIR/discarded.log"
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

@test "a submit token counts only at the END, alone or behind a paste chip" {
  [ "$(cls 'anything(submittoken:run:18e3fd78:20260927T054318Z:16ba1a46)')" = rail-token ]
  [ "$(cls '[Pastedtext#2+3lines]Z:16ba1a46)')" = rail-token ]
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

@test "composer_discard_note keeps what was discarded, one line per discard" {
  composer_discard_note 815 stray-keystroke I
  composer_discard_note 751 rail-token '[Pastedtext#1]Z:16ba1a46'
  [ "$(wc -l < "$CC_COMPOSER_DISCARD_LOG" | tr -d ' ')" = 2 ]
  grep -q $'pane=815\tclass=stray-keystroke\tI$' "$CC_COMPOSER_DISCARD_LOG"
}
