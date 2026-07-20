#!/usr/bin/env bash
# desk-brief-inject.sh — SessionStart: re-inject the canonical desk brief IFF this pane holds the
# desk role. This is what makes `desk-register` the SINGLE activation trigger for the desk identity.
#
# THE GAP THIS CLOSES: the desk identity used to come only from (a) an ad-hoc brief pasted into a
# handoff-fire recycle prompt and (b) a hand-written ~/.claude/cc-roles/desk. A session started any
# other way — or the SAME pane after a recycle/compact — had neither, so it could not presume the
# role. hooks/dod-persist.sh already re-injects the frozen DoD, but it keys off a hash of the
# WORKTREE (cwd), not the role, so it cannot carry a role-scoped brief: every session in the desk's
# checkout would get it, and the desk in any other cwd would not. This hook keys off the ROLE FILE.
#
# Contract: hold the role → get the brief, on every start/resume/compact, mechanically. The pairing
# is deliberate — dod-persist carries the mutable STATE (frozen DoD), this carries the durable ROLE.
#
# Fail-safe: ALWAYS exits 0 and prints nothing on any failure (a SessionStart hook must never cost a
# session). No `set -e`. Non-desk panes are a silent no-op, which is every session but one.
#
# Env seams (tests):
#   CC_ROLES_DIR      (default ~/.claude/cc-roles)
#   DESK_BRIEF_ROLE   (default desk)
#   DESK_BRIEF_FILE   (default <repo>/docs/templates/desk-boot-brief.md, symlink-resolved)
#   DESK_BRIEF_PANE   (default $ITERM_SESSION_ID's uuid — the pane this session runs in)
set -uo pipefail

# --- resolve THIS script through its symlink ---------------------------------------------------
# ~/.claude/hooks/<name> is a per-file symlink into the checkout, so a naive
# `dirname "${BASH_SOURCE[0]}"` yields ~/.claude/hooks and "../docs/..." resolves to
# ~/.claude/docs/... which DOES NOT EXIST. (scripts/desk-invariant.sh has exactly that bug in its
# BRIEF default; production only survives it because the launchd plist passes an absolute override.)
# bash 3.2-safe: macOS has no `readlink -f`.
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
  _d="$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd)" || break
  _self="$(readlink "$_self")"
  case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd)" || exit 0

ROLES_DIR="${CC_ROLES_DIR:-$HOME/.claude/cc-roles}"
ROLE="${DESK_BRIEF_ROLE:-desk}"
BRIEF="${DESK_BRIEF_FILE:-$SCRIPT_DIR/../docs/templates/desk-boot-brief.md}"

# --- is THIS pane the desk? --------------------------------------------------------------------
pane="${DESK_BRIEF_PANE:-}"
if [ -z "$pane" ]; then
  _itsid="${ITERM_SESSION_ID:-}"
  [ -n "$_itsid" ] || exit 0                      # not an iTerm pane → cannot hold the role
  pane="${_itsid##*:}"
fi
[ -n "$pane" ] || exit 0

holder="$(head -n1 "$ROLES_DIR/$ROLE" 2>/dev/null | tr -d '[:space:]')"
[ -n "$holder" ] || exit 0                        # no desk registered → nothing to presume
[ "$holder" = "$pane" ] || exit 0                 # someone ELSE is the desk → silent no-op

# --- inject ------------------------------------------------------------------------------------
[ -f "$BRIEF" ] || exit 0
content="$(cat "$BRIEF" 2>/dev/null || true)"
[ -n "$content" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

framed="You hold the machine-wide DESK role (~/.claude/cc-roles/${ROLE} names THIS pane, ${pane}), so the canonical desk brief below is re-injected mechanically — on a fresh launch, an in-place adopt, a recycle and a compaction alike. It is BINDING: assume the role now, orient, and drive. Do not re-introduce yourself and do not ask what to do.

${content}"

jq -nc --arg c "$framed" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null || true
exit 0
