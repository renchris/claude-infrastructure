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
# ── WHY IT NOW WRITES AN IDL ROW (backlog 04010b4c8074, 2026-08-13) ────────────────────────────────
# "Silent on stdout" was correct and stays correct. "Silent on the WIRE" was the defect. This hook
# keys on ~/.claude/cc-roles/<role>; that file was DELETED by a cleanup (scripts/autonomy-sweep.sh:
# "No desk orchestrator runs here. cc-roles/desk holds an iTerm2 pane uuid from 2026-07-26 whose
# pane has self-closed…") and nothing connected the removal to this consumer. Because the hook
# emitted NO telemetry of any kind, the state "the role file this hook exists to read is gone" was
# indistinguishable from "every session so far was correctly not the desk" — and from the hook never
# having run at all. scripts/idl-abstain-alarm.sh could not even list it: a hook with zero records
# leaves the table by design. So a mechanism that had been dead since 2026-07-26 looked exactly like
# a healthy one, for as long as anyone cared to look.
#   docs/research/idle-recycle-not-proactive-2026-08-08.md §"Secondary items".
# Every exit path now appends ONE disposition row (hooks/lib/idl-log.sh, the same SSOT writer the
# other five IDL hooks use). `no-role-file` / `role-empty` are the dead-consumer states and are
# DISTINCT from `other-holder`, which is the correct-and-common no-op. None of those tokens is in
# idl-abstain-alarm's blind set, so the hook reports DORMANT-100 (green, surfaced for review) rather
# than paging: a desk-less machine is a deliberate state, not a fault — the same D6 reading
# scripts/desk-invariant.sh's `not-opted-in` branch already ships. Telemetry can never fail the
# hook; log_idl swallows every error and the sourcing ladder degrades to a no-op writer.
#
# Env seams (tests):
#   CC_ROLES_DIR      (default ~/.claude/cc-roles)
#   DESK_BRIEF_ROLE   (default desk)
#   DESK_BRIEF_FILE   (default <repo>/docs/templates/desk-boot-brief.md, symlink-resolved)
#   DESK_BRIEF_PANE   (default $ITERM_SESSION_ID's uuid — the pane this session runs in)
#   DESK_BRIEF_IDL    (default ~/.claude/autonomy/idl.jsonl — the disposition log)
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
IDL="${DESK_BRIEF_IDL:-$HOME/.claude/autonomy/idl.jsonl}"

# --- the disposition writer (SSOT: hooks/lib/idl-log.sh) ---------------------------------------
# Resolution ladder mirrors waiting-recycle's: $SCRIPT_DIR is ALREADY symlink-resolved above, so the
# checkout copy is found on the same fast-forward that delivers this hook — a brand-new lib file has
# no ~/.claude/hooks/lib symlink until install.sh runs, and without this the hook would land inert.
# If nothing resolves, `log_idl`/`abstain` are stubbed so every call site below still works: a hook
# that cannot log its disposition must still never cost the session it runs in.
_ilib="$SCRIPT_DIR/lib/idl-log.sh"
[ -f "$_ilib" ] || _ilib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/idl-log.sh"
[ -f "$_ilib" ] || _ilib="$HOME/.claude/hooks/lib/idl-log.sh"
# shellcheck source=lib/idl-log.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if [ -f "$_ilib" ] && . "$_ilib" 2>/dev/null; then
  idl_init "$IDL" "desk-brief-inject" "SID"
else
  log_idl() { :; }
  abstain() { exit 0; }
fi
# SID rides the SessionStart payload. Read stdin only when it is NOT a tty — a hook invoked by hand
# in a terminal must never hang waiting for input it will not get.
SID="?"
if [ ! -t 0 ]; then
  _in="$(cat 2>/dev/null || true)"
  if [ -n "$_in" ] && command -v jq >/dev/null 2>&1; then
    SID="$(printf '%s' "$_in" | jq -r '.session_id // "?"' 2>/dev/null || echo '?')"
    [ -n "$SID" ] || SID="?"
  fi
fi

# jq is required BOTH to emit the brief and to write the IDL row, so this abstain is necessarily
# silent on the wire too. It is in idl-abstain-alarm's blind set for exactly that reason.
command -v jq >/dev/null 2>&1 || abstain "no-jq"

# --- is THIS pane the desk? --------------------------------------------------------------------
pane="${DESK_BRIEF_PANE:-}"
if [ -z "$pane" ]; then
  _itsid="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"
  [ -n "$_itsid" ] || abstain "no-pane"           # not an iTerm pane → cannot hold the role
  pane="${_itsid##*:}"
fi
[ -n "$pane" ] || abstain "no-pane"

# THE DEAD-CONSUMER SPLIT. Absent and empty are the states a cleanup leaves behind; `other-holder`
# is the correct, overwhelmingly common no-op. Collapsing them is what hid this hook's death.
[ -f "$ROLES_DIR/$ROLE" ] || abstain "no-role-file"
holder="$(head -n1 "$ROLES_DIR/$ROLE" 2>/dev/null | tr -d '[:space:]')"
[ -n "$holder" ] || abstain "role-empty"          # registered but names no pane → can never match
[ "$holder" = "$pane" ] || abstain "other-holder" # someone ELSE is the desk → silent no-op

# --- inject ------------------------------------------------------------------------------------
[ -f "$BRIEF" ] || abstain "brief-missing"
content="$(cat "$BRIEF" 2>/dev/null || true)"
[ -n "$content" ] || abstain "brief-empty"

framed="You hold the machine-wide DESK role (~/.claude/cc-roles/${ROLE} names THIS pane, ${pane}), so the canonical desk brief below is re-injected mechanically — on a fresh launch, an in-place adopt, a recycle and a compaction alike. It is BINDING: assume the role now, orient, and drive. Do not re-introduce yourself and do not ask what to do.

${content}"

if jq -nc --arg c "$framed" \
     '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null
then
  # The POSITIVE CONTROL for the whole record stream: without a `fired` row, an all-abstain table is
  # ambiguous between "the desk is elsewhere" and "this hook can no longer inject anything".
  log_idl fired "injected" "$(jq -cn --arg r "$ROLE" --arg p "$pane" '{role:$r,pane:$p}' 2>/dev/null || echo '{}')"
else
  log_idl failed "render-failed"
fi
exit 0
