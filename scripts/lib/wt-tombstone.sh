# shellcheck shell=bash
# wt-tombstone.sh — one repo-qualified, reversible record before any automated worktree removal,
# plus PARK / unpark and the pin predicate (DESIGN load-root-cause-2026-10-17 §3, note X6, WP-9).
#
# SOURCE this file; it defines functions only and changes no shell option of its caller. It must run
# under /bin/bash 3.2 (bin/cc-reaper and launchd jobs use it): no associative arrays, no `${x,,}`,
# no `mapfile`, no `case` + `continue` inside `$( )`.
#
# API contract (every caller codes against it): docs/research/load-root-cause-2026-10-17/W2-CONTRACT.md
# The PARK / pin half lives in wt-park.sh beside this file and is sourced at the end.
#
# Every path below has an env override so the §3.7 lab runs in a throwaway HOME, never on real trees.

[ -n "${_WT_TOMBSTONE_SH:-}" ] && return 0
_WT_TOMBSTONE_SH=1

WT_GIT="${WT_GIT:-git}"
WT_LEDGER="${WT_LEDGER:-${CC_WTGC_DISPOSAL_LOG:-$HOME/.claude/autonomy/worktree-disposals.jsonl}}"
WT_TOMB_DIR="${WT_TOMB_DIR:-$HOME/.claude/autonomy/worktree-tombstones}"
WT_STATE_DIR="${WT_STATE_DIR:-$HOME/.claude/state}"
WT_EVENTS_FILE="${WT_EVENTS_FILE:-$WT_STATE_DIR/wt-events.jsonl}"
WT_WAKE_FILE="${WT_WAKE_FILE:-$WT_STATE_DIR/worktree-gc.wake}"
WT_PARK_INDEX="${WT_PARK_INDEX:-$WT_STATE_DIR/wt-parked}"
WT_PARK_ROOT="${WT_PARK_ROOT:-$HOME/Development/.worktrees/.parked}"
# Colon-separated config roots; each may hold settings.json and projects/. Empty ⇒ glob ~/.claude*.
WT_CONFIG_ROOTS="${WT_CONFIG_ROOTS:-}"

wt__now() { printf '%s' "${WT_NOW:-$(date +%s)}"; }   # epoch; WT_NOW is the lab clock

wt__ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

wt__json_esc() { # <s> → JSON string body (no quotes); control chars dropped
  printf '%s' "${1:-}" | LC_ALL=C sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | LC_ALL=C tr -d '\000-\010\013-\037'
}

wt__sha1() { printf '%s' "$1" | shasum -a 1 | cut -c1-40; }

wt__canon() { # <path> → physical absolute path if it exists, else the input unchanged
  if [ -d "$1" ]; then (cd -P -- "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; else printf '%s' "$1"; fi
}

wt__id_new() { # <path> → a fresh tombstone id: <utc-stamp>-<8 hex of path>-<pid><rand>
  printf '%s-%s-%s%s' "$(date -u +%Y%m%dT%H%M%SZ)" "$(wt__sha1 "$1" | cut -c1-8)" "$$" "${RANDOM:-0}"
}

wt__repo_of() { # <worktree-path> → absolute path of the main worktree (dirname of the common dir)
  local cd
  cd="$("$WT_GIT" -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ -n "$cd" ] || return 1
  case "$cd" in */.git) printf '%s' "${cd%/.git}" ;; *) printf '%s' "$cd" ;; esac
}

wt__common_dir_of() { "$WT_GIT" -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }

wt__trunk_of() { # <repo> → the trunk ref to compare against: $WT_TRUNK, origin/HEAD's target, else origin/main
  if [ -n "${WT_TRUNK:-}" ]; then printf '%s' "$WT_TRUNK"; return 0; fi
  local t
  t="$("$WT_GIT" -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$t" ]; then printf '%s' "$t"; return 0; fi
  if "$WT_GIT" -C "$1" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then printf 'origin/main'; return 0; fi
  return 1   # AC-4: an unresolvable trunk is its own verdict; callers must not treat it as "landed"
}

wt__ledger_append() { # <json-object-line> → one append to the disposal ledger; rc≠0 if the write failed
  local dir; dir="$(dirname "$WT_LEDGER")"
  mkdir -p "$dir" 2>/dev/null || return 1
  printf '%s\n' "$1" >> "$WT_LEDGER" 2>/dev/null
}

wt__config_roots() { # → one config root per line (env list, else every ~/.claude* dir holding settings.json or projects/)
  if [ -n "$WT_CONFIG_ROOTS" ]; then printf '%s\n' "$WT_CONFIG_ROOTS" | tr ':' '\n' | sed '/^$/d'; return 0; fi
  local d
  for d in "$HOME"/.claude "$HOME"/.claude-*; do
    [ -d "$d/projects" ] || [ -f "$d/settings.json" ] || continue
    printf '%s\n' "$d"
  done
}

wt__slug() { printf '%s' "$1" | sed 's#[/.]#-#g'; }   # Claude Code's projects/<slug> naming

# ---- WP-9a (tombstone core) and WP-9b (wt-park.sh) implement the functions named in W2-CONTRACT.md ----

_wt_park_lib="$(dirname "${BASH_SOURCE[0]}")/wt-park.sh"
# shellcheck source=/dev/null
[ -f "$_wt_park_lib" ] && . "$_wt_park_lib"
unset _wt_park_lib
