#!/usr/bin/env bash
# composer-carry.sh — carry the unsent text in a Claude Code prompt box across a move, and put it back.
# Source AFTER scripts/lib/cc-tui.sh (or a stub of it): every read and keystroke goes through cc_tui_*.
# No side effects at load. bash 3.2 safe (lr-upgrade's drainer runs under launchd's /bin/bash).
#
# Callers: lr-upgrade.sh's switch drain (lru_draft_restore, the composer-occupied save) and
# handoff-fire.sh's transplant recycle (hf_rcy_carry / hf_rcy_carry_putback). One copy, MOVED here out
# of lr-upgrade (2026-10-10, lr-stranded-husk C4/C6, docs/research/lr-stranded-husk-2026-10-10/
# ROOT-CAUSE.md), so the two cannot drift.
#
# IMAGE CHIPS ARE NEVER TYPED. `[Image #N]` in the box is a placeholder for bytes Claude Code keeps
# on disk from paste time at <tmp>/claude-<uid>/<project slug>/<sid>/images/<N>.<ext> (measured
# 2026-10-10 on pane 168: the slug is the transcript's project dir name). Typing the placeholder back
# produces literal text and no image, which lr-upgrade used to do while its space-stripped read-back
# called it "carried". The save COPIES the bytes beside the text; the put-back re-attaches each one by
# a BRACKETED PASTE OF ITS ABSOLUTE SAVED PATH — measured on 2.1.293 (round2/M1b-pty.md): the box
# then shows `[Image #M]` and Claude Code copies the bytes into the receiving session's own store.
# Typing the path, or `@path`, leaves plain text and no image.
#
# PASTED-TEXT CHIPS ARE NOT ON DISK. `[Pasted text #N +M lines]` stands for a block Claude Code holds
# only in memory: a clear destroys it and nothing can bring it back. The save reports it (rc 3, the
# chip listed in unsaved.txt) so a caller with a live source can decline and leave the box alone; a
# put-back never types the placeholder and never reports such a box as exact.
# shellcheck shell=bash

[ -n "${CC_CARRY_LIB_LOADED:-}" ] && return 0 2>/dev/null
CC_CARRY_LIB_LOADED=1

CC_CARRY_IMAGE_RE='\[Image #?[0-9]+\]'
CC_CARRY_PASTED_RE='\[Pasted text #[0-9]+( \+[0-9]+ lines)?\]'

cc_carry_image_dir() { # $1=transcript or tombstone path $2=sid → the session's image store (nothing when $1 is empty)
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 0
  printf '%s/claude-%s/%s/%s/images' "${CC_CARRY_CC_TMPDIR:-${CLAUDE_CODE_TMPDIR:-/tmp}}" "$(id -u)" \
    "$(basename "$(dirname "$1")")" "$2"
}

# The text with every chip cut out (image and pasted-text alike), and the one space each chip leaves
# behind collapsed. What remains is what a keystroke can reproduce.
cc_carry_typeable() { # $1=saved text file → stdout: what may be typed back (no trailing newline)
  local t
  t="$(LC_ALL=C sed -E "s/ ?$CC_CARRY_IMAGE_RE ?/ /g; s/ ?$CC_CARRY_PASTED_RE ?/ /g; s/^ +//; s/ +\$//" < "$1" 2>/dev/null)" || return 1
  printf '%s' "$t"
}

# SAVE: <dir>/draft.txt (the box as read, spaces kept); per image chip its bytes copied into <dir> with
# one line in <dir>/images.txt — the saved path, or `missing:<where it was looked for>`; per pasted
# block its chip in <dir>/unsaved.txt.
cc_carry_save() { # $1=pane $2=dir $3=image store ("" none) → 0 saved · 1 the box is empty · 2 unreadable or unwritable · 3 saved, but a pasted block in it is not on disk
  local pane="${1:-}" dir="${2:-}" src="${3:-}" t n f
  t="$(cc_tui_composer_text "$pane")" || return 2
  [ -n "$t" ] || return 1
  mkdir -p "$dir" 2>/dev/null || return 2
  printf '%s' "$t" > "$dir/draft.txt" 2>/dev/null || return 2
  : > "$dir/images.txt" 2>/dev/null || return 2
  : > "$dir/unsaved.txt" 2>/dev/null || return 2
  for n in $(printf '%s' "$t" | LC_ALL=C grep -oE "$CC_CARRY_IMAGE_RE" | LC_ALL=C tr -cd '0-9\n'); do
    f=""
    if [ -n "$src" ]; then
      for f in "$src/$n".*; do [ -f "$f" ] && break; f=""; done
    fi
    if [ -n "$f" ] && cp -p "$f" "$dir/" 2>/dev/null; then
      printf '%s\n' "$dir/${f##*/}" >> "$dir/images.txt"
    else
      printf 'missing:%s\n' "${src:-<no image store>}/$n.png" >> "$dir/images.txt"
    fi
  done
  printf '%s' "$t" | LC_ALL=C grep -oE "$CC_CARRY_PASTED_RE" >> "$dir/unsaved.txt" 2>/dev/null || true
  [ -s "$dir/unsaved.txt" ] && return 3
  return 0
}

_cc_carry_chips() { # stdin: a space-stripped box → the number of image chips in it
  LC_ALL=C grep -oE '\[Image#?[0-9]+\]' | LC_ALL=C wc -l | LC_ALL=C tr -d '[:space:]'
}

# PUT BACK, once the caller's readiness command has held on two consecutive polls AND the box reads
# empty. Images first, each a bracketed paste of its saved path (the order measured on 2.1.293: chip,
# then typed text); then the text as KEYSTROKES (a paste attaches whatever image is on the clipboard),
# falling back to the paste for a payload the keystroke path refuses (a leading ! # / ? &). A paste
# that does not raise the chip count is not an attach: the box is cleared and only the text goes back,
# so the box never keeps a literal path. <dir>/putback.txt names every part: attached:<path>,
# not-attached:<path>, missing:<path>, not-saved:<pasted chip>.
#   rc 0 everything is back and reads exact · 1 never ready with an empty box inside the bound (nothing
#   typed) · 2 a send failed · 3 the box reads differently · 4 nothing could be put back · 5 what is on
#   disk is back and reads exact, and putback.txt names the parts that could not be
cc_carry_putback() { # $1=pane $2=dir $3=wait-s $4=poll-s $5...=readiness command
  local pane="${1:-}" dir="${2:-}" wait="${3:-300}" poll="${4:-5}" calm=0 c want got deadline tf trc=0
  local pb p n0 n1 att=0 short=0 chips=""
  shift 4
  tf="$dir/typeback.txt"; pb="$dir/putback.txt"
  cc_carry_typeable "$dir/draft.txt" > "$tf" 2>/dev/null || return 2
  : > "$pb" 2>/dev/null || return 2
  LC_ALL=C grep '^missing:' "$dir/images.txt" >> "$pb" 2>/dev/null || true
  LC_ALL=C sed 's/^/not-saved:/' "$dir/unsaved.txt" >> "$pb" 2>/dev/null || true
  [ -s "$pb" ] && short=1
  if [ ! -s "$tf" ] && ! LC_ALL=C grep -qv '^missing:' "$dir/images.txt" 2>/dev/null; then
    return 4
  fi
  deadline=$(( $(date +%s) + wait ))
  while :; do
    if "$@"; then calm=$((calm + 1)); else calm=0; fi
    if [ "$calm" -ge 2 ]; then
      c="$(cc_tui_composer "$pane")" && [ -z "$c" ] && break
    fi
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep "$poll"
  done
  # fd 3, so nothing inside the loop (a kitty RPC) can swallow the list from stdin.
  while IFS= read -r p <&3; do
    case "$p" in ''|missing:*) continue ;; esac
    if [ "$short" = 2 ]; then printf 'not-attached:%s\n' "$p" >> "$pb"; continue; fi
    n0="$(cc_tui_composer "$pane" | _cc_carry_chips)"
    printf '%s' "$p" > "$dir/paste.txt"
    cc_tui_type "$pane" "$dir/paste.txt" >/dev/null 2>&1 || { printf 'not-attached:%s\n' "$p" >> "$pb"; short=2; continue; }
    sleep "${CC_CARRY_SETTLE_S:-3}"
    n1="$(cc_tui_composer "$pane" | _cc_carry_chips)"
    if [ "${n1:-0}" -gt "${n0:-0}" ]; then
      att=$((att + 1)); printf 'attached:%s\n' "$p" >> "$pb"
    else
      # Not an attach: whatever the paste left (the literal path) goes, and with it any chip already
      # attached — those are named not-attached too, so the box and the record agree.
      printf 'not-attached:%s\n' "$p" >> "$pb"; short=2
      cc_tui_clear "$pane" >/dev/null 2>&1 || return 3
      if [ "$att" -gt 0 ]; then
        LC_ALL=C sed 's/^attached:/not-attached:/' "$pb" > "$pb.t" 2>/dev/null && mv -f "$pb.t" "$pb"
        att=0
      fi
    fi
  done 3< "$dir/images.txt"
  if [ -s "$tf" ]; then
    cc_tui_type_keys "$pane" "$tf" >/dev/null 2>&1 || trc=$?
    if [ "$trc" = 2 ]; then
      trc=0; cc_tui_type "$pane" "$tf" >/dev/null 2>&1 || trc=1
    fi
    [ "$trc" = 0 ] || return 2
  fi
  sleep "${CC_CARRY_SETTLE_S:-3}"
  got="$(cc_tui_composer "$pane")" || got=""
  got="$(printf '%s' "$got" | LC_ALL=C sed -E 's/\[Image#?[0-9]+\]/[Image#]/g')"
  n0=0; while [ "$n0" -lt "$att" ]; do chips="${chips}[Image#]"; n0=$((n0 + 1)); done
  want="$chips$(LC_ALL=C tr -d '[:space:]' < "$tf")"
  [ "$got" = "$want" ] || return 3
  [ -n "$want" ] || return 4
  [ "$short" = 0 ] || return 5
  return 0
}
