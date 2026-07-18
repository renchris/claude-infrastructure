#!/usr/bin/env bash
# continue-sentinel.sh — SSOT for the session-continue loose-ends sentinel PATH.
#
# WHY (G-P6-6b / a19 I-1): boundary-handoff's compose-guard yields the Stop turn to session-continue
# when the 🔧 continuation loop is armed — but it hardcoded the sentinel path
# `~/.claude/hooks/.session-continue-armed`, a path session-continue NEVER writes (it writes
# `${CLAUDE_CONFIG_DIR:-~/.claude}/state/continue-<hash(cfg|cwd)>`). The guard checked a path that
# can never exist → a dead no-op → both hooks could inject a `decision:block` on the same Stop. This
# file is the SINGLE definition of that path, sourced by BOTH hooks so they cannot disagree again.
#
# Keyed by (config-dir | cwd): concurrent sessions — including different accounts, each with its own
# CLAUDE_CONFIG_DIR — never collide, and the sentinel lives OUTSIDE any repo (never committed).
#
# Pure function definitions only — no side effects on source (safe under `set -u`).

# Directory holding every continue sentinel for the active config dir.
continue_state_dir() {
  printf '%s/state' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
}

# Absolute sentinel path for a working dir ($1). Stable 16-hex hash → one file per worktree.
# MUST stay byte-for-byte identical to what session-continue.sh's `set` writes.
continue_sentinel_for() {
  local h
  h=$(printf '%s|%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "$1" | shasum 2>/dev/null | cut -c1-16)
  printf '%s/continue-%s' "$(continue_state_dir)" "$h"
}
