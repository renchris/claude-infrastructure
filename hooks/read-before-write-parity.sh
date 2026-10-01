#!/bin/bash
# read-before-write-parity.sh — PreToolUse(Write|Edit|MultiEdit) entry point for
# hooks/lib/read-before-write-parity.sh. Refuses a write to an EXISTING file this session has never
# Read/Written/Edited, on a model whose native "File has not been read yet" guard Claude Code no
# longer applies (2.1.284: every model outside a 10-id legacy set, wherever a Read is auto-allowed).
#
# The decision lives in the lib (pure, 32-case suite tests/read-before-write-parity.bats); this file
# only drains stdin, calls rbw_should_deny, and speaks the PreToolUse protocol. Every uncertainty
# the lib cannot resolve returns allow, so this hook can only refuse what the binary used to refuse.
# Registered by migration 0047 (c10). Kill switch for one session: CC_RBW=off.
set -uo pipefail

[ "${CC_RBW:-on}" = off ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lib="$here/lib/read-before-write-parity.sh"
[ -f "$lib" ] || exit 0
# shellcheck disable=SC1090,SC1091  # resolved at runtime beside this file
. "$lib"

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
case "$tool" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac
tp="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
target="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
# Notebooks are exempt natively (the binary's own .ipynb term) — stay out.
case "$target" in *.ipynb) exit 0 ;; esac

rbw_should_deny "$tp" "$target" "$cwd" || exit 0

jq -n --arg p "$target" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("File has not been read yet. Read it first before writing to it: \($p). (read-before-write-parity: Claude Code no longer applies this guard to this model, so this hook restores it. Read the file, then integrate your change with Edit — never overwrite an existing file blind. One-session override: CC_RBW=off.)")
  }
}'
exit 0
