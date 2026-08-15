#!/usr/bin/env bash
# worktree-memory-link.sh — make a linked worktree's PROJECT MEMORY resolve to the primary repo's.
#
# THE DEFECT. Claude Code keys project state on the session's cwd: memory lives at
# $CLAUDE_CONFIG_DIR/projects/<encode(cwd)>/memory/. A linked worktree has a different cwd from the
# primary checkout, so it gets a DIFFERENT project dir — and that dir has no memory/. Measured
# 2026-07-31: 164 worktree-keyed project dirs on this box, **0** with a memory/ directory, against
# 213 topic files + a 108-line MEMORY.md index in the primary repo's. Sessions that ran in a
# worktree ran memory-blind: `gu-session-lifecycle` has 4 real transcripts totalling 5.1 MB and no
# memory dir. This is not hypothetical and it is not rare — 79 of this repo's 116 linked worktrees
# are auto-generated per-dispatch `wt-<12hex>` trees, i.e. the autonomous fleet is the main victim.
#
# WHY A SYMLINK AND NOT A COPY. Memory is knowledge about the REPO, not about the worktree. Copying
# would fork it: each worktree would accumulate its own learnings, none of which reach the primary
# index, and MEMORY.md is already over its loader cap so fragmenting it is strictly worse. A symlink
# gives every session in the repo ONE memory, which is what "project memory" has to mean for a fleet
# whose sessions are spread across 100+ worktrees. Concurrency is no worse than today: two sessions
# in the primary checkout already share this exact directory.
#
# THIS IS THE cc-tlid PATTERN. bin/cc-tlid solved the identical class for TASK BOARDS (per-cwd
# keying handed every worktree a private board — measured residue: 373 empty boards) by keying on
# repo identity via `--git-common-dir`, which in a linked worktree always resolves to the PRIMARY
# repo's .git. Same load-bearing call here, for the same reason. Read that file's header first if
# you are changing this one.
#
# FAIL-SOFT BY CONSTRUCTION. This runs from a WorktreeCreate hook whose stdout contract is strict
# (only the worktree path may be printed) and whose failure aborts `claude -w`. So: all diagnostics
# go to stderr or the log, every failure path still exits 0, and an existing real memory/ directory
# in the worktree is NEVER touched (we do not know what put it there; destroying it could lose the
# only copy of something).
#
# Usage:
#   worktree-memory-link.sh [<worktree-path>]   link one worktree (default: $PWD)
#   worktree-memory-link.sh --all [<repo>]      backfill every linked worktree of <repo> that
#                                               ALREADY has a project dir
#   worktree-memory-link.sh --all --create [<repo>]
#                                               …and MINT the project dir for those that do not
#   worktree-memory-link.sh --check [<path>]    report state, change nothing (exit 0 always)
#
# Env: CC_WML_CONFIG_DIRS  space-separated config dirs to consider (default: the real ones).
#      CC_WML_QUIET=1      suppress stderr progress.

set -uo pipefail

log() { [ "${CC_WML_QUIET:-0}" = "1" ] || printf 'worktree-memory-link: %s\n' "$1" >&2; }

# Claude Code's project-dir encoding: EVERY character outside [a-zA-Z0-9] becomes '-'.
#
# This used to read "BOTH '/' and '.' become '-'", above the claim "Verified 2026-07-31 against
# ground truth … not inferred". The verification was real; its SPAN was two characters wide, and
# both example paths contained only '/' and '.', so the check could not distinguish the rule it
# stated from the rule that is actually implemented. A narrower encoder is not a harmless
# approximation here — it emits a key Claude Code can NEVER emit, so the primary's memory is looked
# up at a slot that does not exist (silent skip at the `[ -d "$pmem" ]` continue below), and a
# worktree link is minted at a slot no session will ever read.
#
# RE-MEASURED 2026-08-15 against the live fleet rather than one build. Across all four config roots
# — 1,661 project dirs written by the versions actually in service — ZERO contain '_' or '.', and
# every one matches ^[-a-zA-Z0-9]+$. The positive control that makes that non-vacuous:
# /Users/chrisren/Development/doc_classifier exists on disk and is keyed
# -Users-chrisren-Development-doc-classifier in all four roots (227 session files); the narrow
# rule's -Users-…-doc_classifier exists nowhere. The upstream encoder is
# `A.replace(/[^a-zA-Z0-9]/g, "-")`.
#
# Still LOSSY, and now lossy in more places (feat/x, feat.x, feat_x and feat-x all collide). That is
# Claude Code's property, not ours; we only have to reproduce it, and a collision degrades to
# "shares memory with a sibling", which is the direction we are moving in anyway.
encode() { printf '%s' "$1" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g'; }

config_dirs() {
  if [ -n "${CC_WML_CONFIG_DIRS:-}" ]; then
    # Deliberate split on whitespace — the var is a space-separated LIST, so quoting it whole would
    # yield one bogus path. Split explicitly via read -a rather than an unquoted expansion, so the
    # intent is legible and shellcheck stays clean.
    local _d _dirs=(); read -r -a _dirs <<<"$CC_WML_CONFIG_DIRS"
    for _d in "${_dirs[@]}"; do [ -n "$_d" ] && printf '%s\n' "$_d"; done
    return
  fi
  # Every config dir that actually has a projects/ tree. The fleet runs both the stable and the
  # eval track, and a session may be on either, so link in both rather than guessing from
  # CLAUDE_CONFIG_DIR (which is set to whichever track THIS process is on, not the next one's).
  for d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.claude" "$HOME/.claude-next"; do
    [ -n "$d" ] && [ -d "$d/projects" ] && printf '%s\n' "$d"
  done | sort -u
}

# Resolve the primary (main) worktree for a path. `--git-common-dir` is the load-bearing call: in a
# linked worktree `--show-toplevel` is the WORKTREE, while the common dir is always the primary's
# .git. Returns empty for a non-repo.
primary_of() {
  local p="$1" common
  common="$(git -C "$p" rev-parse --git-common-dir 2>/dev/null)" || return 0
  [ -n "$common" ] || return 0
  # --git-common-dir may be relative to cwd; make it absolute before taking its dirname.
  case "$common" in /*) ;; *) common="$(cd "$p" 2>/dev/null && cd "$(dirname "$common")" 2>/dev/null && pwd -P)/$(basename "$common")" ;; esac
  [ -d "$common" ] || return 0
  (cd "$common/.." 2>/dev/null && pwd -P)
}

# Link one worktree's memory. Never fails the caller.
link_one() {
  local wt="$1" mode="${2:-apply}" primary wtabs pkey wkey cfg pmem wmem rel n=0
  wtabs="$(cd "$wt" 2>/dev/null && pwd -P)" || { log "skip (unreadable): $wt"; return 0; }
  primary="$(primary_of "$wtabs")"
  [ -n "$primary" ] || { log "skip (not a git worktree): $wtabs"; return 0; }
  if [ "$primary" = "$wtabs" ]; then log "skip (this IS the primary checkout): $wtabs"; return 0; fi

  pkey="$(encode "$primary")"; wkey="$(encode "$wtabs")"

  while read -r cfg; do
    [ -n "$cfg" ] || continue
    pmem="$cfg/projects/$pkey/memory"
    wmem="$cfg/projects/$wkey/memory"
    [ -d "$pmem" ] || continue                      # primary has no memory here — nothing to share
    if [ -L "$wmem" ]; then
      # Already a symlink. Re-point only if it dangles or aims elsewhere.
      if [ -d "$wmem" ] && [ "$(cd "$wmem" && pwd -P)" = "$(cd "$pmem" && pwd -P)" ]; then continue; fi
      [ "$mode" = "check" ] && { log "WOULD repoint $wmem"; continue; }
      rm -f "$wmem"
    elif [ -e "$wmem" ]; then
      # A REAL directory (or file) already lives there. Never clobber it — we do not know what wrote
      # it, and it may hold the only copy of something. Report and move on.
      log "LEAVING real memory dir untouched: $wmem"
      continue
    fi
    # BACKFILL IS DELIBERATELY NARROWER THAN CREATE. For a freshly created worktree (the hook path)
    # the project dir does not exist yet and minting it IS the point. For a sweep over an existing
    # repo it is not: measured 2026-07-31, only 5 of this repo's 118 worktrees have ever hosted a
    # session, so linking all of them would mint ~226 project dirs for trees that will never run one
    # — feeding the same unbounded-cardinality problem (244 -> 1,334 branches in 7 days) that argued
    # against always-isolate in the first place. So --all links only slots that already exist.
    if [ "$mode" = "existing" ] && [ ! -d "$cfg/projects/$wkey" ]; then continue; fi
    [ "$mode" = "check" ] && { log "WOULD link $wmem -> $pmem"; n=$((n+1)); continue; }
    mkdir -p "$cfg/projects/$wkey" 2>/dev/null || { log "mkdir failed: $cfg/projects/$wkey"; continue; }
    # Relative link: projects/<wkey>/memory -> ../<pkey>/memory. Survives the config dir being
    # moved or mirrored between tracks, which absolute links would not.
    rel="../$pkey/memory"
    if ln -s "$rel" "$wmem" 2>/dev/null; then n=$((n+1)); log "linked $wmem -> $rel"
    else log "ln failed: $wmem"; fi
  done < <(config_dirs)

  [ "$n" -gt 0 ] && log "$wtabs: $n link(s)"
  return 0
}

main() {
  local mode=apply target=""
  case "${1:-}" in
    --all)
      shift
      # `--all --create` opts into minting project dirs for worktrees that have never hosted a
      # session; plain `--all` only links slots that already exist (see the note in link_one).
      # The comment here used to name the flag `--all-create`, which nothing implements: the code
      # tests `--create`, so `--all --all-create <repo>` consumed nothing, fell through to the
      # target, and reported `not a git repo: --all-create` at exit 0. Neither spelling appeared in
      # the usage block, so the comment was the only documentation and it was wrong.
      local amode=existing
      [ "${1:-}" = "--create" ] && { amode=apply; shift; }
      target="${1:-$PWD}"
      local primary; primary="$(primary_of "$target")"
      [ -n "$primary" ] || { log "not a git repo: $target"; exit 0; }
      # `sed s/^worktree //`, not `awk '{print $2}'`: --porcelain does not quote, so a worktree
      # whose path contains a SPACE gave awk only its first field — `…/my tree` yielded `…/my`,
      # which then lost the whole worktree to `skip (unreadable)` at exit 0. Stripping the fixed
      # prefix keeps the rest of the line whatever it contains.
      while read -r wt; do [ -n "$wt" ] && link_one "$wt" "$amode"; done \
        < <(git -C "$primary" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
      ;;
    --check) shift; link_one "${1:-$PWD}" check ;;
    # 1,42p — the header block ends at line 42; `set -uo pipefail` is 43. Widened from 1,40p when
    # the usage list grew: a fixed line range silently TRUNCATES its own documentation, which is
    # how the last Env line stopped printing.
    -h|--help) sed -n '1,42p' "$0"; ;;
    *) link_one "${1:-$PWD}" apply ;;
  esac
  exit 0
}

main "$@"
