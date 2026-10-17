#!/bin/bash
# wtgc-scope.sh — the repo-scope table and the event-mode switch shared by the worktree-gc wake run
# (scripts/worktree-gc-wake.sh) and its 04:15 backstop (scripts/worktree-gc-infra-run.sh).
# DESIGN docs/research/load-root-cause-2026-10-17/DESIGN.md §3.4, row X9, WP-15.
#
# Two switches, two owners, and neither is written by any shipped code:
#   ~/.claude/autonomy/worktree-gc-events.mode     one word, observe | act. Written only by the
#       operator's activation script (docs/activation/pending-activation/52-load-2026-10-17-activate.sh).
#       Absent, unreadable or any other word ⇒ observe: evaluate and log, touch nothing.
#   ~/.claude/autonomy/worktree-gc-repos.promoted  one absolute git common dir per line (OP-5). Written
#       only by the operator, after reviewing that repo's observe log. This file only READS it.
# A foreign repo acts only when it is promoted AND the mode is act; the home repo needs only act;
# reso-management-app is never in scope (its own janitor owns it).
#
# Source it; functions return, never exit. bash 3.2 safe. Seams: WTGC_EVENTS, CC_WTGC_EVENTS_MODE_FILE,
# CC_WTGC_PROMOTED_FILE, CC_WTGC_SCOPE_EXCLUDE (space-separated repo basenames), CC_WTGC_GIT.

WTGC_MODE_FILE="${CC_WTGC_EVENTS_MODE_FILE:-$HOME/.claude/autonomy/worktree-gc-events.mode}"
WTGC_PROMOTED_FILE="${CC_WTGC_PROMOTED_FILE:-$HOME/.claude/autonomy/worktree-gc-repos.promoted}"
WTGC_SCOPE_EXCLUDE="${CC_WTGC_SCOPE_EXCLUDE:-reso-management-app}"

# wtgc_events_mode → prints observe | act. The env var wins over the file, so a test or a manual
# run can pin either; anything that is not exactly `act` reads as observe (fail closed).
wtgc_events_mode() {
  local m="${WTGC_EVENTS:-}"
  if [ -z "$m" ] && [ -r "$WTGC_MODE_FILE" ]; then
    read -r m _ < "$WTGC_MODE_FILE" 2>/dev/null || m=""
  fi
  if [ "$m" = act ]; then echo act; else echo observe; fi
}

# wtgc_repo_of <path> → prints the repo root (common dir minus a trailing /.git); rc 1 if not a repo.
wtgc_repo_of() {
  local cd
  cd="$("${CC_WTGC_GIT:-git}" -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ -n "$cd" ] || return 1
  echo "${cd%/.git}"
}

# wtgc_trunk_of <repo-root> → prints e.g. origin/main from refs/remotes/origin/HEAD; rc 1 if none.
wtgc_trunk_of() {
  local t
  t="$("${CC_WTGC_GIT:-git}" -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || return 1
  [ -n "$t" ] || return 1
  echo "$t"
}

# wtgc_promoted <repo-root> → rc 0 iff the promoted file lists it, as the root or as <root>/.git.
wtgc_promoted() {
  local root="${1%/}" line
  root="${root%/.git}"
  [ -r "$WTGC_PROMOTED_FILE" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%/}"; line="${line%/.git}"
    [ -n "$line" ] && [ "$line" = "$root" ] && return 0
  done < "$WTGC_PROMOTED_FILE"
  return 1
}

# wtgc_scope <repo-root> <home-repo-root> → prints excluded | act | observe.
wtgc_scope() {
  local root="${1%/}" home="${2%/}" b x
  root="${root%/.git}"; home="${home%/.git}"
  b="$(basename "$root")"
  for x in $WTGC_SCOPE_EXCLUDE; do
    [ "$b" = "$x" ] && { echo excluded; return 0; }
  done
  if [ "$(wtgc_events_mode)" = act ] && { [ "$root" = "$home" ] || wtgc_promoted "$root"; }; then
    echo act
  else
    echo observe
  fi
}
