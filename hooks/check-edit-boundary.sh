#!/bin/bash
# PreToolUse hook: enforce freeze/focus edit boundaries
# Matcher: Write|Edit|MultiEdit
#
# Modes: freeze (deny INSIDE) | focus (deny OUTSIDE)
# State: ~/.claude/edit-boundary.json
# CLI: $0 set <freeze|focus> <dir> [dir2...] | clear | show
# Hook: reads JSON from stdin per PreToolUse protocol (no args).

set -uo pipefail

STATE_FILE="$HOME/.claude/edit-boundary.json"

# ── CLI management mode (called with arguments) ──────────────────────
if [ $# -gt 0 ]; then
  case "$1" in
    set)
      MODE="${2:-}"
      shift 2 2>/dev/null || true
      if [ "$MODE" != "freeze" ] && [ "$MODE" != "focus" ]; then
        echo "Usage: $0 set <freeze|focus> <dir> [dir2 ...]" >&2
        exit 1
      fi
      if [ $# -eq 0 ]; then
        echo "Error: at least one directory path required" >&2
        exit 1
      fi
      # Resolve each path to absolute with trailing slash
      PATHS_JSON="["
      FIRST=true
      for DIR in "$@"; do
        RESOLVED=$(cd "$DIR" 2>/dev/null && pwd -P) || {
          echo "Error: directory not found: $DIR" >&2
          exit 1
        }
        RESOLVED="${RESOLVED%/}/"
        $FIRST && FIRST=false || PATHS_JSON+=","
        PATHS_JSON+="\"$RESOLVED\""
      done
      PATHS_JSON+="]"
      mkdir -p "$(dirname "$STATE_FILE")"
      printf '{"mode":"%s","paths":%s}\n' "$MODE" "$PATHS_JSON" > "$STATE_FILE"
      echo "Edit boundary set: mode=$MODE paths=$PATHS_JSON"
      ;;
    clear)
      rm -f "$STATE_FILE"
      echo "Edit boundary cleared."
      ;;
    show)
      if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
      else
        echo "No edit boundary active."
      fi
      ;;
    *)
      echo "Usage: $0 {set|clear|show}" >&2
      exit 1
      ;;
  esac
  exit 0
fi

# ── Hook mode (PreToolUse, reads JSON from stdin) ─────────────────────

# stdin is drained ONCE, HERE, before any early exit. The duplicate-worker gate below needs `.cwd`,
# and the freeze/focus boundary is inactive most of the time — so a `[ ! -f "$STATE_FILE" ] && exit`
# ahead of it would disarm the gate in exactly the state the box is normally in.
INPUT=$(cat)

# ── DUPLICATE-WORKER GATE (backlog 18323346082a) ──────────────────────────────────────────────
# A claim REFUSED with `verdict=noop-live-claimer` used to reach a journal and nothing else: on
# 2026-08-07 seven sessions were each told "incumbent live" for item 191d4d056c98 and each did the
# whole item anyway, in one shared worktree. `hooks/session-register.sh` DETECTS that at
# SessionStart but structurally cannot act on it — SessionStart has no blocking field on 2.1.114 —
# and a mailbox stand-down needs a turn boundary a session deep in a tool loop never reaches
# (GROUND_UP_DISPATCH.md:615-628, measured). The write is where the same incident log says the
# collision becomes real, so the refusal binds here, mechanically.
#
# IT RUNS BEFORE EVERY EARLY EXIT ABOVE THE BOUNDARY LOGIC — the `24b` lesson from
# tests/capacity-admit-coverage.bats: a gate placed after an early return is a gate the common case
# escapes. Pinned by tests/worker-claim-gate-coverage.bats.
#
# RESOLUTION ORDER — symlink-resolved sibling FIRST. ~/.claude/hooks/*.sh are symlinks into the
# checkout, so resolving $0's link reaches the repo's own scripts/lib/ and the gate goes live the
# moment the file does. A $CLAUDE_CONFIG_DIR-first lookup would find nothing until install.sh
# re-globs on the next deploy — the deployed-layer-bootstrap-circle, verified live in 64a7d1fa.
#
# ABSENT LIBRARY, OR ADMIT ⇒ FALL THROUGH, never exit: a missing gate must not silently disarm the
# freeze/focus boundary this hook already enforces.
_ceb_self="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
for _wcg in "$(dirname "$_ceb_self")/../scripts/lib/worker-claim-gate.sh" \
            "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/worker-claim-gate.sh" \
            "${HOME:-}/.claude/scripts/lib/worker-claim-gate.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  [ -f "$_wcg" ] && . "$_wcg" 2>/dev/null && break
done
if command -v cc_worker_claim_admit >/dev/null 2>&1; then
  _ceb_cwd=""
  if command -v jq >/dev/null 2>&1; then
    _ceb_cwd="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
  fi
  [ -n "$_ceb_cwd" ] || _ceb_cwd="$PWD"
  _ceb_tool="$(printf '%s' "$INPUT" | jq -r '.tool_name // "write"' 2>/dev/null || echo write)"
  CC_WCLAIM_SID="$(printf '%s' "$INPUT" | jq -r '.session_id // "?"' 2>/dev/null || echo '?')" \
    cc_worker_claim_admit edit-boundary "$_ceb_cwd" "$_ceb_tool" || {
      jq -n --arg r "$(cc_worker_claim_reason)" \
            --arg i "$(cc_worker_claim_item)" \
            --arg h "$(cc_worker_claim_holder)" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: ("DUPLICATE WORKER — this session does not hold the lease on item \($i). \($r). Another LIVE session (\($h)) holds it and is doing this work right now; two sessions writing one worktree is how item 191d4d056c98 produced duplicate tools, duplicate suites and three rewrites of one doc on 2026-08-07. DO NOT retry, and DO NOT work around this by writing elsewhere — you are the duplicate, and the refusal is a FACT about a live lease, not a transient throttle. STAND DOWN: stop work, and retire this pane with `$HOME/.claude/scripts/handoff-fire.sh self-close --terminal` (it refuses a dirty tree, which is the intended safety). If you believe the incumbent is DEAD, do not force it — the lease self-releases the moment its claimer dies or `cc-backlog reap` ages it out, and the next write is then admitted automatically. Override for this session only: CC_WCLAIM_GATE=off. Rule: backlog 18323346082a, docs/plans/CONCURRENCY_PROGRAM.md#s4.")
        }
      }'
      exit 0
    }
fi

# No state file = no boundary active, allow everything
[ ! -f "$STATE_FILE" ] && exit 0

# Require jq — fail-open if unavailable
if ! command -v jq &>/dev/null; then
  exit 0
fi

STATE=$(cat "$STATE_FILE")

MODE=$(printf '%s' "$STATE" | jq -r '.mode // empty')
[ -z "$MODE" ] && exit 0

# Extract file_path from tool input
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Resolve to absolute path
case "$FILE_PATH" in
  /*) ;;
  *)  FILE_PATH="$(pwd)/$FILE_PATH" ;;
esac

# Normalize: collapse double slashes, resolve parent dir symlinks
FILE_DIR=$(dirname "$FILE_PATH")
FILE_BASE=$(basename "$FILE_PATH")
FILE_DIR=$(cd "$FILE_DIR" 2>/dev/null && pwd -P || printf '%s' "$FILE_DIR")
FILE_PATH="$FILE_DIR/$FILE_BASE"

# Read boundary paths into array
BOUNDARY_PATHS=()
while IFS= read -r p; do
  [ -n "$p" ] && BOUNDARY_PATHS+=("$p")
done < <(printf '%s' "$STATE" | jq -r '.paths[]')

# Check if file is inside ANY boundary path (prefix match with trailing /)
inside_boundary() {
  for BP in "${BOUNDARY_PATHS[@]}"; do
    case "$1" in
      "${BP}"*) return 0 ;;
    esac
  done
  return 1
}

# Format boundary list for messages
BOUNDARY_LIST=$(printf '%s' "$STATE" | jq -r '.paths | join(", ")')

# ── Decision ──────────────────────────────────────────────────────────
DENY=false
if [ "$MODE" = "freeze" ]; then
  # Freeze: deny edits INSIDE boundary paths
  if inside_boundary "$FILE_PATH"; then
    DENY=true
    REASON="[edit-boundary] Blocked: $FILE_PATH is inside frozen directory ($BOUNDARY_LIST). Edits inside frozen directories are not allowed."
  fi
elif [ "$MODE" = "focus" ]; then
  # Focus: deny edits OUTSIDE boundary paths
  if ! inside_boundary "$FILE_PATH"; then
    DENY=true
    REASON="[edit-boundary] Blocked: $FILE_PATH is outside the focus boundary ($BOUNDARY_LIST). Only edits inside the focus directories are allowed."
  fi
fi

if [ "$DENY" = true ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$REASON"
  }
}
EOF
fi

exit 0
