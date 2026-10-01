#!/usr/bin/env bash
# composer-intent.sh — is the text sitting in a Claude Code composer somebody's DRAFT, or junk that
# only blocks a recovery? Source, do not execute. Pure: no side effects at load, bash 3.2 safe
# (launchd runs /bin/bash). Callers: handoff-fire.sh --probe-recycle-preconditions (lr-handoff's
# precheck) and cc-tui.sh cc_tui_submit (the daemon's prompt-mode repair and the fleet's nudge).
#
# WHY THIS EXISTS (operator ruling 2026-09-27: "improve /limit-recover if there is obviously
# unintended content in the prompt box to clear/work around it"). Every composer gate on the rail
# refuses on ANY non-empty composer, because /exit or a paste into a draft merges with it. That
# polarity is right for a draft and wrong for everything else, and on 2026-09-27 every limited pane
# on the box was held by something that was not a draft:
#
#   pane   composer (space-stripped)                          what it was
#   815    I                                                  one stray keystroke, 9 h old
#   814    Youwereresumedonaccountnext2afteraweeklylimit…      a recovery prompt, typed, never submitted
#   751    [Pastedtext#1]Z:16ba1a46                           lr-fire-resume's own paste chip + token tail
#   810    _Ga=d,d=I,i=7110,q=225h                            a kitty graphics command leaked as text
#
# Three recovery runs in a row refused 815 and 751, and the "fix" handed to the operator was
# "press Ctrl-U in the pane" — a worksheet, for text nobody meant to keep.
#
# THE CLASSES, each narrow and named. Anything that matches none of them is a DRAFT and every
# caller keeps refusing, exactly as before:
#   rail-prompt     begins with a marker this rail types (exact PREFIX of the space-stripped form)
#   rail-token      ends with lr-fire-resume's submit token, alone or behind a paste chip — the
#                   token is `run:<sid8>:<UTC stamp>:<8 hex>`, minted per run, never typed by hand
#   terminal-reply  begins with an escape-sequence introducer's remnant (_G, P>|, ]N;rgb:, [?N, [>N)
#                   — a terminal query reply or graphics command that reached the pty as input
#   stray-keystroke at most CC_COMPOSER_STRAY_MAX (default 2) characters, not a /command. The loss
#                   is bounded by construction: the worst case discards two typed characters, and
#                   composer_discard_note keeps them on disk.
#
# Kill switch: CC_COMPOSER_UNINTENDED=off — every non-empty composer is a draft again.
# shellcheck shell=bash

# Space-stripped prefixes of prompts THIS rail types into a composer. One per line.
COMPOSER_RAIL_MARKERS='[limit-recover]
/limit-recoveringest
Resumedinplaceon
Youwereresumedonaccount
OPUS55-UPGRADE(
In-placeupgrade:thissessionwasrelaunchedbycc-lrupgrade
[operator-rulingcc-lr-switch'

composer_unintended_class() { # $1=space-stripped composer content → class on stdout; rc 0 unintended · 1 a draft
  local c="${1:-}" m
  [ "${CC_COMPOSER_UNINTENDED:-on}" != off ] || return 1
  [ -n "$c" ] || return 1
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    case "$c" in "$m"*) printf 'rail-prompt'; return 0 ;; esac
  done <<EOF
$COMPOSER_RAIL_MARKERS
EOF
  # handoff-fire --goal's own arm, typed and never submitted (pane 41, 2026-10-01: a fired session
  # hit its weekly limit with `/goal … full brief in the prompt above, DoD at docs/plans/…` sitting
  # in the composer, and the recovery held on it as a "draft"). The fixed clause the house --goal
  # template ends every condition with is the signature (commands/handoff.md § Autonomous fire
  # item 1). The condition itself is not lost by clearing it: handoff-fire's GOAL-ARM mail and
  # ~/.claude/logs/handoffs.jsonl both carry it, and the discard log keeps this copy.
  case "$c" in /goal*fullbriefinthepromptabove*) printf 'rail-goal'; return 0 ;; esac
  # The token must END the content: a draft that merely quotes a token (a pasted log line) keeps
  # typing after it, and the chip form admits nothing but token text between the chip and the end.
  if printf '%s' "$c" | LC_ALL=C grep -qE '\(submittoken:run:[0-9a-f]{8}:[0-9]{8}T[0-9]{6}Z:[0-9a-f]{8}\)?$' \
     || printf '%s' "$c" | LC_ALL=C grep -qE '^\[Pastedtext#[0-9]+(\+[0-9]+lines)?\][A-Za-z0-9:()]*Z:[0-9a-f]{8}\)?$' \
     || printf '%s' "$c" | LC_ALL=C grep -qE '^\[Pastedtext#[0-9]+(\+[0-9]+lines)?\][0-9a-f]{2,8}\)?$'; then
    printf 'rail-token'; return 0
  fi
  if printf '%s' "$c" | LC_ALL=C grep -qE '^(_G[A-Za-z]=|P>\||\][0-9]+;rgb:|\[\?[0-9][0-9;]*[A-Za-z$]|\[>[0-9;]*c)'; then
    printf 'terminal-reply'; return 0
  fi
  if [ "${#c}" -le "${CC_COMPOSER_STRAY_MAX:-2}" ]; then
    case "$c" in /*) return 1 ;; esac
    # Non-ASCII is never a stray (D6.8): one CJK character is one keystroke of a real draft, and
    # ${#c} counts it as 1 under a UTF-8 locale.
    printf '%s' "$c" | LC_ALL=C grep -q '[^ -~]' && return 1
    printf 'stray-keystroke'; return 0
  fi
  return 1
}

# Keep what was discarded. Append-only, one line per discard, never breaks the caller.
composer_discard_note() { # $1=pane $2=class $3=content-as-read → always 0
  local f="${CC_COMPOSER_DISCARD_LOG:-$HOME/.claude/logs/composer-discarded.log}"
  mkdir -p "${f%/*}" 2>/dev/null || return 0
  printf '%s\tpane=%s\tclass=%s\t%s\n' "$(date -u +%FT%TZ)" "${1:-?}" "${2:-?}" "${3:-}" >> "$f" 2>/dev/null || true
  return 0
}
