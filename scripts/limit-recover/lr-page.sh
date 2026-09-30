#!/bin/bash
# lr-page.sh — page the operator on channels with NO liveness dependency (FLEET_V2 W6, resolution 13,
# D6.3). Every limit-recover hold that waits on a human (a held draft, a held team lead whose wake
# failed, an exhausted request) pages through here.
#
#   lr-page.sh [--title <tail>] [--] <message>   page; prints ONE verdict line on stdout
#   lr-page.sh --failures                        print how many pages reached no channel
#   source lr-page.sh                            defines lr_page (same contract) without running
#
# Why a new helper rather than cc-notify: the reconciler paged with `cc-notify --page`, an option
# cc-notify never had (it exits 2 on it), and discarded the exit code, so every page was lost and
# counted as sent. cc-notify also needs a live desk pane; there has been none for weeks. Neither
# leg here needs a pane, a role file or a session.
#
# Legs:
#   os     macOS Notification Center via osascript. The text is passed as an AppleScript ARGV item,
#          never interpolated into the script source: pages quote operator drafts and command lines,
#          and interpolation would be an injection hole (the poller's older notifications do that).
#          Capped at 200 characters, bounded at LR_PAGE_OS_TIMEOUT_S (10). Moved from
#          lead-supervisor.sh page_escalate_os, same contract.
#   phone  Pushover via scripts/push-send.sh, which trusts only an API status:1. Runs only when
#          PUSHOVER_TOKEN and PUSHOVER_USER are both set; otherwise it is skipped silently, since
#          wiring the credentials is an operator step (D6.9).
#
# Verdict (stdout): `lr-page: verdict=<posted|failed> os=<posted|failed|off> phone=<sent|failed|skipped>`
# Exit: 0 = at least one leg put the page in front of a human · 1 = no leg did (counted) · 2 = usage.
# Every attempt appends one line to LR_PAGE_LOG (no message text, so a draft never lands on disk);
# `--failures` counts the failed ones.
#
# Env: LR_PAGE_OS_CHANNEL=auto|on|off (default: CC_SUP_OS_CHANNEL, else auto — `off` is the switch
# for a box where Notification Center is the wrong surface) · LR_PAGE_OSASCRIPT_BIN (osascript) ·
# LR_PAGE_PUSH_BIN (push-send.sh beside this repo's scripts/) · LR_PAGE_TIMEOUT_BIN (timeout(1),
# set-but-empty runs unbounded) · LR_PAGE_LOG (~/.reso/limit-recover/pages.log).
# bash 3.2-safe: launchd runs /bin/bash.

_lr_page_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_lr_page_timeout_bin() {
  if [ -n "${LR_PAGE_TIMEOUT_BIN+set}" ]; then
    printf '%s' "$LR_PAGE_TIMEOUT_BIN"
    return 0
  fi
  local c
  for c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
    /opt/homebrew/bin/timeout /usr/local/bin/timeout /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    if [ -n "$c" ] && [ -x "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 0
}

_lr_page_bounded() { # $1=seconds $2..=command — rc 124 on a cut; unbounded when no timeout(1) exists
  local s="$1" tb
  shift
  tb="$(_lr_page_timeout_bin)"
  if [ -z "$tb" ] || [ ! -x "$tb" ]; then
    "$@"
    return $?
  fi
  "$tb" -k 5 "$s" "$@"
}

_lr_page_os() { # $1=title-tail $2=message → echoes posted|failed|off
  local osa="${LR_PAGE_OSASCRIPT_BIN:-osascript}"
  case "${LR_PAGE_OS_CHANNEL:-${CC_SUP_OS_CHANNEL:-auto}}" in
    off)
      echo off
      return 0
      ;;
    on) ;;
    *)
      if ! command -v "$osa" >/dev/null 2>&1; then
        echo off
        return 0
      fi
      ;;
  esac
  if _lr_page_bounded "${LR_PAGE_OS_TIMEOUT_S:-10}" "$osa" - "$1" "$2" >/dev/null 2>&1 <<'OSA'; then
on run argv
  set v to item 1 of argv
  set m to item 2 of argv
  if (count of m) > 200 then set m to (text 1 thru 200 of m)
  display notification m with title ("Claude fleet — " & v) sound name "Funk"
end run
OSA
    echo posted
  else
    echo failed
  fi
}

_lr_page_phone() { # $1=title-tail $2=message → echoes sent|failed|skipped
  if [ -z "${PUSHOVER_TOKEN:-}" ] || [ -z "${PUSHOVER_USER:-}" ]; then
    echo skipped
    return 0
  fi
  local push="${LR_PAGE_PUSH_BIN:-$_lr_page_here/../push-send.sh}"
  # push-send bounds its own curl (--max-time 8); the outer bound only catches a wedged interpreter.
  if _lr_page_bounded 20 bash "$push" send --title "Claude fleet — $1" --message "$2" >/dev/null 2>&1; then
    echo sent
  else
    echo failed
  fi
}

_lr_page_log() {
  printf '%s' "${LR_PAGE_LOG:-$HOME/.reso/limit-recover/pages.log}"
}

lr_page() { # [--title <tail>] [--] <message> → verdict line on stdout; rc 0 posted · 1 failed · 2 usage
  local title="limit-recover" msg="" have=0 os phone verdict log
  while [ $# -gt 0 ]; do
    case "$1" in
      --title)
        [ $# -ge 2 ] || {
          echo "lr-page: --title needs text" >&2
          return 2
        }
        title="$2"
        shift 2
        ;;
      --)
        shift
        [ $# -gt 0 ] && {
          msg="$1"
          have=1
          shift
        }
        ;;
      -*)
        echo "lr-page: unknown option '$1'" >&2
        return 2
        ;;
      *)
        [ "$have" = 0 ] || {
          echo "lr-page: too many arguments" >&2
          return 2
        }
        msg="$1"
        have=1
        shift
        ;;
    esac
  done
  if [ "$have" = 0 ] || [ -z "$msg" ]; then
    echo "lr-page: no message" >&2
    return 2
  fi
  os="$(_lr_page_os "$title" "$msg")"
  phone="$(_lr_page_phone "$title" "$msg")"
  verdict=failed
  if [ "$os" = posted ] || [ "$phone" = sent ]; then
    verdict=posted
  fi
  log="$(_lr_page_log)"
  mkdir -p "$(dirname "$log")" 2>/dev/null
  printf '%s\t%s\tos=%s\tphone=%s\n' "$(date +%s)" "$verdict" "$os" "$phone" >>"$log" 2>/dev/null
  printf 'lr-page: verdict=%s os=%s phone=%s\n' "$verdict" "$os" "$phone"
  [ "$verdict" = posted ]
}

lr_page_failures() {
  local log n
  log="$(_lr_page_log)"
  n=0
  [ -f "$log" ] && n="$(grep -c "	failed	" "$log" 2>/dev/null)"
  echo "${n:-0}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --failures) lr_page_failures ;;
    -h | --help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)
      lr_page "$@"
      exit $?
      ;;
  esac
fi
