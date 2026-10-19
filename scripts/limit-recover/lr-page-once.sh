#!/bin/bash
# lr-page-once.sh — page the operator ONCE per key, through lr-page.sh (lr-wake 2026-10-18, Wave G).
#
#   source lr-page-once.sh; lr_page_once <key> <title> <message>
#
# Why: the census and the move lane met holds that never end by themselves (pane 350 sat at the
# "Background work is running" modal through 3 × 3600 s waits) and said nothing, while a page per
# pass would be noise. The latch is an mkdir under $LR_STATE_DIR/paged-once/<key>: the first caller
# pages, every later caller with the same key is silent until the latch is removed. A page no leg
# delivered (lr-page.sh rc 1) drops the latch, so the next caller tries again.
#
# Seams: LR_PAGE_ONCE_BIN (the pager, default lr-page.sh beside this file) · LR_STATE_DIR.
# Prints lr-page.sh's verdict line, or `lr-page-once: verdict=latched key=<key>`. Always rc 0.
# bash 3.2-safe.

_lr_page_once_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

lr_page_once() { # $1=key $2=title $3=message → always 0
  local key="${1:-}" title="${2:-limit-recover}" msg="${3:-}" root latch rc=0
  [ -n "$key" ] && [ -n "$msg" ] || return 0
  key="$(printf '%s' "$key" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_' | cut -c1-120)"
  root="${LR_STATE_DIR:-$HOME/.reso/limit-recover}/paged-once"
  mkdir -p "$root" 2>/dev/null || return 0
  latch="$root/$key"
  if ! mkdir "$latch" 2>/dev/null; then
    printf 'lr-page-once: verdict=latched key=%s\n' "$key"
    return 0
  fi
  date -u +%Y-%m-%dT%H:%M:%SZ > "$latch/at" 2>/dev/null || true
  /bin/bash "${LR_PAGE_ONCE_BIN:-$_lr_page_once_here/lr-page.sh}" --title "$title" -- "$msg" || rc=$?
  [ "$rc" -ne 1 ] || rm -f "$latch/at" 2>/dev/null; [ "$rc" -ne 1 ] || rmdir "$latch" 2>/dev/null
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  [ $# -ge 3 ] || { echo "usage: lr-page-once.sh <key> <title> <message>" >&2; exit 2; }
  lr_page_once "$1" "$2" "$3"
fi
