#!/usr/bin/env bash
# dod-persist.sh — durable frozen-DoD carrier (a19 §2 HOP A-E: the 100/100 contract dies at the 90%
# auto-compact with no plan file — "inline-only DoD evaporates with zero advisory and zero
# re-injection"). This hook is the durable, self-reconstructing home the contract lacked.
#
# THREE modes:
#   SessionStart : if a durable DoD file exists for this worktree, re-inject its verbatim content as
#                  additionalContext → the frozen scope re-enters EVERY fresh / recycled / compacted
#                  session mechanically (closes HOP A "zero re-injection" + HOP E recycle loss).
#   PreCompact   : extract the newest `Scope (frozen):` line from the transcript (mechanical grep, NO
#                  model call) and APPEND it (timestamped, INTEGRATE-never-overwrite) to the durable
#                  file IF ABSENT-or-stale → the contract survives the 90% auto-compact summarizer.
#   set "<scope>": CLI for the desk playbook / /handoff capture to freeze a scope explicitly.
#   path [cwd]   : print the resolved durable-DoD path (debug / playbook / tests).
#
# PATH CONTRACT — MUST match scripts/wrap-ledger.sh:87-93 (and thus hooks/completion-assert.sh, which
# reads the ledger). Producer (this) and consumers resolve the SAME file:
#   ${WRAP_DOD_FILE} if set, else ${WRAP_DOD_DIR:-~/.claude/autonomy/dod}/<hash(git-toplevel|cwd)>.md
#
# Fail-safe: hook modes ALWAYS exit 0 (a PreCompact/SessionStart hook must never cost a session); any
# jq/read failure degrades to a silent no-op. No `set -e`. The dedup (skip when the scope is
# unchanged) keeps the durable file small — it accumulates only DISTINCT frozen scopes.
#
# Env seams (tests): WRAP_DOD_FILE · WRAP_DOD_DIR — SHARED with wrap-ledger, so a test that points
# both at one file proves the producer↔consumer contract end-to-end.
set -uo pipefail

# ── DoD path — IDENTICAL resolution to wrap-ledger.sh (the consumer) ──
dod_file_for() {  # $1 = cwd
  if [ -n "${WRAP_DOD_FILE:-}" ]; then printf '%s' "$WRAP_DOD_FILE"; return; fi
  local dir top hash
  dir="${WRAP_DOD_DIR:-$HOME/.claude/autonomy/dod}"
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$1")"
  hash="$(printf '%s' "$top" | shasum 2>/dev/null | cut -c1-16)"
  printf '%s/%s.md' "$dir" "${hash:-unknown}"
}

# ── newest "Scope (frozen): …" line already recorded in the durable file ──
last_recorded_scope() { grep -aoE 'Scope \(frozen\):.*' "$1" 2>/dev/null | tail -1; }

# ── newest "Scope (frozen): …" line stated anywhere in a transcript (all text records) ──
extract_scope() {  # $1 = transcript path
  jq -r 'select(.type=="assistant" or .type=="user")
         | .message.content
         | if type=="string" then .
           elif type=="array" then ([.[]?|select(.type=="text")|.text]|join("\n"))
           else empty end' "$1" 2>/dev/null \
    | grep -aoE 'Scope \(frozen\):.*' | tail -1
}

# ── append (INTEGRATE, timestamped) — never overwrite prior captures ──
persist_dod() {  # $1=file  $2=scope  $3=cwd  $4=source-label
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  mkdir -p "$(dirname "$1")" 2>/dev/null || true
  if [ ! -f "$1" ]; then
    {
      printf '# Durable frozen DoD — %s\n' "$3"
      printf '# producer: dod-persist.sh · consumers: wrap-ledger.sh, completion-assert.sh\n'
      printf '# INTEGRATE-only: each capture APPENDS below; history is never rewritten (a19 HOP A).\n\n'
    } > "$1" 2>/dev/null || return 0
  fi
  printf '## %s (%s)\n%s\n\n' "$ts" "$4" "$2" >> "$1" 2>/dev/null || true
}

# ── CLI modes ──
case "${1:-}" in
  set)
    scope="${2:-}"
    [ -n "$scope" ] || { printf 'usage: dod-persist.sh set "<Scope (frozen): DoD>"\n' >&2; exit 2; }
    case "$scope" in *"Scope (frozen):"*) ;; *) scope="Scope (frozen): $scope" ;; esac
    f="$(dod_file_for "$PWD")"
    if [ -f "$f" ] && [ "$scope" = "$(last_recorded_scope "$f")" ]; then
      printf 'unchanged → %s\n' "$f"; exit 0
    fi
    persist_dod "$f" "$scope" "$PWD" "manual-set"
    printf 'captured → %s\n' "$f"
    exit 0 ;;
  path)
    dod_file_for "${2:-$PWD}"; printf '\n'; exit 0 ;;
esac

# ── Hook modes (JSON on stdin; dispatch by hook_event_name) ──
command -v jq >/dev/null 2>&1 || exit 0
input="$(cat 2>/dev/null || printf '{}')"
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"

case "$event" in
  SessionStart)
    f="$(dod_file_for "$cwd")"
    [ -f "$f" ] || exit 0                        # no durable DoD → nothing to re-inject
    content="$(cat "$f" 2>/dev/null || true)"
    [ -n "$content" ] || exit 0
    framed="Durable frozen DoD for this worktree — re-injected across recycle/compaction as the completeness baseline (a19 HOP A). Every 'Scope (frozen):' line below is binding; do NOT narrow scope or declare done until it is met.

$content"
    jq -nc --arg c "$framed" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null || true
    exit 0 ;;
  PreCompact)
    tp="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
    case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
    trigger="$(printf '%s' "$input" | jq -r '.trigger // "auto"' 2>/dev/null || echo auto)"
    { [ -n "$tp" ] && [ -f "$tp" ]; } || exit 0
    scope="$(extract_scope "$tp")"
    [ -n "$scope" ] || exit 0                    # no frozen scope stated → nothing to persist
    f="$(dod_file_for "$cwd")"
    if [ -f "$f" ] && [ "$scope" = "$(last_recorded_scope "$f")" ]; then exit 0; fi   # fresh → skip
    persist_dod "$f" "$scope" "$cwd" "PreCompact:${trigger}"
    exit 0 ;;
  *)
    exit 0 ;;
esac
