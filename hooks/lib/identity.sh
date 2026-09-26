#!/usr/bin/env bash
# hooks/lib/identity.sh — bash twin of hooks/lib/identity.py: the ONE resolution of the operator's
# personal identity overlay. Values live in a gitignored local file because this repo is public;
# the tracked identity.example.json shows the shape with example-domain values.
#
#   Resolution: $CC_IDENTITY_FILE if set, else $HOME/.claude/identity.local.json (absolute, so a
#   worktree, the live layer and a githook running as a COPY all read the same bytes).
#
#   cc_identity_path                 → prints the resolved path
#   cc_identity_get '<jq filter>'    → prints the value; rc 1 when the file is missing/unreadable
#                                      or the value is null/empty (the CALLER picks the failure
#                                      direction — a security gate must treat rc 1 as REFUSE).
#
# Sourcing is side-effect free. Needs jq (already a hard dependency of the live layer).

cc_identity_path() {
  if [ -n "${CC_IDENTITY_FILE:-}" ]; then
    printf '%s\n' "$CC_IDENTITY_FILE"
  else
    printf '%s\n' "$HOME/.claude/identity.local.json"
  fi
}

cc_identity_get() {
  local f v
  f="$(cc_identity_path)"
  [ -r "$f" ] || return 1
  v="$(jq -er "$1 // empty" "$f" 2>/dev/null)" || return 1
  [ -n "$v" ] || return 1
  printf '%s\n' "$v"
}
