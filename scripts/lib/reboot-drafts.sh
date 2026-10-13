#!/usr/bin/env bash
# reboot-drafts.sh — carry each pane's unsent prompt-box text across a scripted reboot (2026-10-13).
#
# WHY: text typed into a Claude Code prompt box and not sent lives only in that process, so a reboot
# lost it. scripts/alarm-reboot-prep.sh now reads every live pane's box before the reboot, and
# scripts/boot-resume.sh types each saved draft back into the pane its session came back in.
#
#   rd_capture <roster.json> <drafts-dir | ""> [budget-s]
#       read the box of every kitty pane the roster names. With a directory, save each non-empty
#       draft as <dir>/<sid>/ (composer-carry.sh's cc_carry_save layout: draft.txt, images.txt,
#       unsaved.txt); with "" (a dry run) count only and keep nothing. Prints one line:
#       saved=N partial=P empty=E unreadable=U unread=B. rc 2 when the libraries did not load.
#   rd_pick <dir> <lower> <upper>
#       the newest <dir>/reboot-<date>.drafts whose sibling .start epoch is in (lower, upper]; rc 1 none.
#   rd_putback <drafts-dir> <map-file> <log-file> [wait-s] [poll-s]
#       for each `cc-resume-layout: map sid=<sid> wid=<wid> …` line whose session has a saved draft,
#       type it back (cc_carry_putback) and delete it. Prints: typed=N partial=P kept=K left=L.
#
# THE CAPTURE ONLY READS. Every call under rd_capture is `kitty @ get-text` through cc-tui.sh's
# bounded transport; it sends no key, clears nothing and submits nothing. A box that reads UNKNOWN
# (a dialog over it, a torn screen, a kitty that did not answer) is counted unreadable and left alone.
#
# THE PUT-BACK NEVER PRESSES ENTER, and it types only into a box that parsed and read EMPTY on the
# poll before the first keystroke (cc_carry_putback's own gate). A box that is occupied or UNKNOWN
# for the whole wait gets nothing, and its draft stays on disk with the reason in the log.
#
# A DRAFT MAY HOLD A SECRET. The directory is mode 700 and its files 600 (umask 077 around every
# write), it lives under ~/.claude/autonomy, a draft is deleted once it is back in its box, and the
# log names sessions and verdicts, never text.
#
# The parser is cc-tui.sh's (cc_tui_composer_text); this file adds none. bash 3.2 safe: launchd runs
# boot-resume.sh under /bin/bash. Sourced: defines functions only.
# Seams: CC_REBOOT_DRAFT_BUDGET (120 s, the whole capture) · CC_RESTORE_DRAFT_WAIT (60 s per pane) ·
#   CC_RESTORE_DRAFT_POLL (5 s) · RD_CC_TUI / RD_CARRY (library paths) · CC_TUI_RPC_TIMEOUT.
# shellcheck shell=bash

: "${RD_DIR:="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"}"

rd_load() { # → 0 when cc-tui.sh and composer-carry.sh are loaded
  local c
  if ! command -v cc_tui_composer_text >/dev/null 2>&1; then
    for c in "${RD_CC_TUI:-}" "$RD_DIR/cc-tui.sh" "${HOME:-}/.claude/scripts/lib/cc-tui.sh"; do
      [ -n "$c" ] && [ -f "$c" ] || continue
      # shellcheck disable=SC1090  # runtime-resolved sibling
      . "$c" 2>/dev/null && command -v cc_tui_composer_text >/dev/null 2>&1 && break
    done
  fi
  if ! command -v cc_carry_save >/dev/null 2>&1; then
    for c in "${RD_CARRY:-}" "$RD_DIR/composer-carry.sh" "${HOME:-}/.claude/scripts/lib/composer-carry.sh"; do
      [ -n "$c" ] && [ -f "$c" ] || continue
      # shellcheck disable=SC1090  # runtime-resolved sibling
      . "$c" 2>/dev/null && command -v cc_carry_save >/dev/null 2>&1 && break
    done
  fi
  command -v cc_tui_composer_text >/dev/null 2>&1 && command -v cc_carry_save >/dev/null 2>&1
}

_rd_transcript() { # <sid> → a transcript of that session, for its image store; nothing when none
  local f
  for f in "${HOME:-}"/.claude*/projects/*/"$1".jsonl; do
    [ -f "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 0
}

rd_capture() {
  local roster="${1:-}" out="${2:-}" budget="${3:-${CC_REBOOT_DRAFT_BUDGET:-120}}"
  local t0 sid pane sock rc tx src saved=0 partial=0 empty=0 bad=0 unread=0
  rd_load || return 2
  [ -f "$roster" ] || return 2
  if [ -n "$out" ]; then
    ( umask 077; mkdir -p "$out" ) 2>/dev/null || return 2
    chmod 700 "$out" 2>/dev/null || return 2
  fi
  t0="$(date +%s)"
  # fd 3, so no kitty call inside the loop can swallow the list from stdin. The separator is `|`, not
  # a tab: a tab is IFS whitespace, and an empty cell would shift the columns after it.
  while IFS='|' read -r sid pane sock <&3; do
    case "$sid" in ''|*[!A-Za-z0-9._-]*) continue ;; esac
    case "$pane" in ''|*[!0-9]*) continue ;; esac
    [ -n "$sock" ] || continue
    # A kitty that stopped answering costs one bounded call per pane; the budget ends that, out loud.
    if [ $(( $(date +%s) - t0 )) -ge "$budget" ]; then unread=$((unread + 1)); continue; fi
    rc=0
    if [ -n "$out" ]; then
      tx="$(_rd_transcript "$sid")"; src="$(cc_carry_image_dir "$tx" "$sid")"
      ( umask 077; CC_TERM_KITTY_TO="$sock" cc_carry_save "$pane" "$out/$sid" "$src" ) || rc=$?
    else
      # Counted in a subshell whose output is one digit, so the text never reaches this shell.
      rc="$( if t="$(CC_TERM_KITTY_TO="$sock" cc_tui_composer_text "$pane")"; then
               if [ -n "$t" ]; then printf 0; else printf 1; fi
             else printf 2; fi )"
    fi
    case "$rc" in
      0) saved=$((saved + 1)) ;;
      3) saved=$((saved + 1)); partial=$((partial + 1)) ;;
      1) empty=$((empty + 1)) ;;
      *) bad=$((bad + 1)) ;;
    esac
  done 3< <(jq -r '(if type == "array" then . else (.sessions // []) end)[]
      | select(type == "object" and (.session_id // "") != "" and ((.paneUUID // "") | tostring) != "")
      | ((.kitty_pid // 0) | tonumber? // 0) as $k | select($k != 0)
      | [.session_id, (.paneUUID | tostring),
         ((.kitty_listen_on // "") | if . == "" then "unix:/tmp/kitty-\($k)" else . end)] | join("|")' "$roster" 2>/dev/null)
  [ -n "$out" ] && [ "$saved" = 0 ] && rmdir "$out" 2>/dev/null
  printf 'saved=%s partial=%s empty=%s unreadable=%s unread=%s\n' "$saved" "$partial" "$empty" "$bad" "$unread"
  return 0
}

rd_pick() {
  local base="${1:-}" lo="${2:-}" hi="${3:-}" d st best="" bs=0
  case "$lo$hi" in ''|*[!0-9]*) return 1 ;; esac
  for d in "$base"/reboot-*.drafts; do
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    st="$(head -n 1 "${d%.drafts}.start" 2>/dev/null | awk '{ print $1 }')"
    case "$st" in ''|*[!0-9]*) continue ;; esac
    { [ "$st" -gt "$lo" ] && [ "$st" -le "$hi" ] && [ "$st" -gt "$bs" ]; } || continue
    best="$d"; bs="$st"
  done
  [ -n "$best" ] || return 1
  printf '%s' "$best"
}

_rd_ready() { cc_tui_composer "$1" >/dev/null 2>&1; }   # the box parses: the session's TUI is up

rd_putback() {
  local drafts="${1:-}" map="${2:-}" log="${3:-/dev/null}"
  local wait="${4:-${CC_RESTORE_DRAFT_WAIT:-60}}" poll="${5:-${CC_RESTORE_DRAFT_POLL:-5}}"
  local line sid wid rc v why d typed=0 partial=0 kept=0 left=0
  rd_load || return 2
  [ -d "$drafts" ] && [ -f "$map" ] || return 2
  while IFS= read -r line <&3; do
    sid="$(printf '%s\n' "$line" | tr ' ' '\n' | sed -n 's/^sid=//p' | head -n 1)"
    wid="$(printf '%s\n' "$line" | tr ' ' '\n' | sed -n 's/^wid=//p' | head -n 1)"
    case "$sid" in ''|*[!A-Za-z0-9._-]*) continue ;; esac
    case "$wid" in ''|*[!0-9]*) continue ;; esac
    d="$drafts/$sid"
    [ -f "$d/draft.txt" ] || continue
    rc=0; why=""
    # A saved draft is one line of text. Anything else is not what the capture wrote, and a control
    # byte typed as a keystroke acts (a CR submits), so it is refused before any call.
    if LC_ALL=C grep -q '[[:cntrl:]]' "$d/draft.txt" 2>/dev/null; then
      rc=9
    else
      ( umask 077; cc_carry_putback "$wid" "$d" "$wait" "$poll" _rd_ready "$wid" ) || rc=$?
    fi
    case "$rc" in
      0) v=typed; typed=$((typed + 1)) ;;
      5) v="typed-partial"; typed=$((typed + 1)); partial=$((partial + 1)); why="$(cc_carry_unput "$d")" ;;
      1) v=kept; why="the box was not empty, or could not be read, for ${wait}s: nothing was typed" ;;
      2) v=kept; why="a send failed" ;;
      3) v=kept; why="typed, but the box reads differently from the draft" ;;
      4) v=kept; why="nothing in the draft can be typed (only attachments)" ;;
      9) v=kept; why="the saved draft holds a control byte: not typed" ;;
      *) v=kept; why="rc $rc" ;;
    esac
    if [ "$v" = kept ]; then kept=$((kept + 1)); else rm -rf "${drafts:?}/$sid"; fi
    printf '%s sid=%s wid=%s rc=%s %s%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$wid" "$rc" "$v" "${why:+ — $why}" \
      >> "$log" 2>/dev/null
  done 3< "$map"
  for d in "$drafts"/*/draft.txt; do [ -f "$d" ] && left=$((left + 1)); done
  left=$((left - kept)); [ "$left" -ge 0 ] || left=0
  rmdir "$drafts" 2>/dev/null
  printf 'typed=%s partial=%s kept=%s left=%s\n' "$typed" "$partial" "$kept" "$left"
  return 0
}
