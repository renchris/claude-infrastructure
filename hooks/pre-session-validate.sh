#!/bin/bash
# pre-session-validate.sh — SessionStart hook: auto-rollback broken versions.
#
# Every time `claude` launches, this hook verifies ~/.claude-versions/current
# points at a working binary. If the current version is broken (e.g., a fresh
# npm install promoted a crashing build), it atomically re-points `current`
# to the next-highest known-good version and emits a stderr warning so the
# user knows about the fallback.
#
# This is the safety net that prevents "auto-upgrade broke my session" — the
# user always gets a working Claude even if the latest tag is broken.
#
# Kill switch: export PRE_SESSION_VALIDATE_DISABLED=1
#
# Exit codes:
#   0 — OK (session proceeds)
#   0 with stderr — rolled back (session proceeds with different version)
#   No other exits — we never block a session (fail-open).

set -euo pipefail

# Kill switch
if [[ "${PRE_SESSION_VALIDATE_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

readonly VERSIONS_DIR="$HOME/.claude-versions"
readonly LOG_FILE="$HOME/.claude/logs/pre-session-validate.log"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Consume stdin (SessionStart hook receives JSON but we don't need it)
cat >/dev/null 2>&1 || true

if [[ ! -L "$VERSIONS_DIR/current" ]]; then
  log "no current symlink at $VERSIONS_DIR/current — nothing to validate"
  exit 0
fi

current_target=$(readlink "$VERSIONS_DIR/current")

find_binary() {
  local ver_dir="$1"
  for candidate in \
    "$ver_dir/node_modules/.bin/claude" \
    "$ver_dir/bin/claude"; do
    [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }
  done
  return 1
}

current_binary="$(find_binary "$current_target" || echo '')"

# Sanity-check: binary exists and responds to --version
if [[ -n "$current_binary" ]] && CLAUDE_SKIP_AUTH=1 timeout 2 "$current_binary" --version >/dev/null 2>&1; then
  # Healthy — exit silently
  exit 0
fi

# BROKEN — find fallback
log "current version broken: $current_target — attempting rollback"
echo "[pre-session-validate] WARNING: $current_target failed --version check" >&2

# Find highest semver-sorted version directory that ISN'T the broken one
fallback=""
for candidate in $(ls -1 "$VERSIONS_DIR" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | sort -V -r); do
  candidate_path="$VERSIONS_DIR/$candidate"
  # Skip the current broken target
  [[ "$candidate_path" == "$current_target" ]] && continue
  # Must have a working binary
  candidate_binary="$(find_binary "$candidate_path" || echo '')"
  [[ -n "$candidate_binary" ]] || continue
  # Binary must answer --version in <2s
  if CLAUDE_SKIP_AUTH=1 timeout 2 "$candidate_binary" --version >/dev/null 2>&1; then
    fallback="$candidate_path"
    break
  fi
done

if [[ -z "$fallback" ]]; then
  log "no working fallback found — session will likely fail"
  echo "[pre-session-validate] ERROR: no working version in $VERSIONS_DIR" >&2
  exit 0  # fail-open: let the session continue and die loudly
fi

# Atomic re-point
ln -sfn "$fallback" "$VERSIONS_DIR/current"
log "rolled back: $current_target → $fallback"
echo "[pre-session-validate] reverted $(basename "$VERSIONS_DIR/current" | xargs readlink 2>/dev/null || echo "?") → $(basename "$fallback")" >&2

exit 0
