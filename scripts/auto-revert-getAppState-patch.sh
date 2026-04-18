#!/bin/bash
# auto-revert-getAppState-patch.sh — detect upstream fix and unpatch 2.1.112.
#
# STATUS (2026-04-18): SUPERSEDED.
# GH #49253 was fixed in 2.1.114. Upgrade was performed manually on 2026-04-18
# via: npm install + atomic symlink flip + MANIFEST candidate entry. Triple-patched
# 2.1.112 retained on disk as rollback fallback.
# This script's smoke-test path (TEST 7 substring grep in cli.js) does NOT apply
# to 2.1.114+ which ships as a Bun SEA binary with no cli.js — if re-used for
# future versions, expect TEST 7 to report "SKIP (no cli.js)" which is now correct
# behavior, not a failure.
# Safe to delete after 2026-05-02 if no regression recurs.
#
# Historical purpose: when Anthropic ships a fix for GH #49253 (new version
# ≠ 2.1.111/2.1.112 marked stable in MANIFEST OR the issue is closed-as-completed):
#   1. Install the new version via claude-update
#   2. Smoke-test it
#   3. On pass: atomic symlink flip to new version
#   4. Our local cli.js patch on 2.1.112 becomes inert (different file)
#   5. The patched 2.1.112 stays on disk as fallback
#
# Manual invoke: ~/.claude/scripts/auto-revert-getAppState-patch.sh [new_version]
# If new_version omitted: queries npm + MANIFEST for a stable candidate.

set -euo pipefail

readonly VERSIONS_DIR="$HOME/.claude-versions"
readonly MANIFEST="$VERSIONS_DIR/MANIFEST.jsonl"
readonly LOG_FILE="$HOME/.claude/logs/auto-revert.log"
readonly SMOKE_TEST="$HOME/.claude/scripts/smoke-test.sh"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

new_version="${1:-}"

# Auto-detect if not provided
if [[ -z "$new_version" ]]; then
  npm_latest=$(timeout 5 npm view @anthropic-ai/claude-code version 2>/dev/null || echo "")
  if [[ -z "$npm_latest" ]]; then
    echo "✗ npm registry unreachable"
    exit 1
  fi
  # Require: newer than 2.1.112 AND marked stable in MANIFEST (or absent)
  if [[ "$npm_latest" == "2.1.111" || "$npm_latest" == "2.1.112" ]]; then
    echo "✗ npm latest is still $npm_latest — not a fix"
    exit 1
  fi
  if [[ -f "$MANIFEST" ]]; then
    status=$(grep -E "\"version\":\"${npm_latest//./\\.}\"" "$MANIFEST" 2>/dev/null | tail -1 \
      | sed -nE 's/.*"status":"([^"]+)".*/\1/p' || true)
    if [[ "$status" == "skip" ]]; then
      echo "✗ $npm_latest is MANIFEST-flagged skip — not safe"
      exit 1
    fi
  fi
  new_version="$npm_latest"
fi

echo "Auto-revert: attempting upgrade to $new_version"
log "start $new_version (from $(readlink "$VERSIONS_DIR/current" | xargs basename))"

# Install (claude-update's gate will block if MANIFEST marks skip)
if ! /Users/chrisren/bin/claude-update "$new_version"; then
  echo "✗ claude-update $new_version failed"
  log "install $new_version FAILED"
  exit 1
fi

# Smoke test
if ! "$SMOKE_TEST" "$new_version"; then
  echo "✗ smoke-test $new_version FAILED — keeping current symlink"
  log "smoke-test $new_version FAILED — no promotion"
  # Add candidate entry if not already marked
  if ! grep -qE "\"version\":\"${new_version//./\\.}\"" "$MANIFEST" 2>/dev/null; then
    echo "{\"version\":\"$new_version\",\"status\":\"candidate\",\"date_added\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"notes\":\"smoke-test failed on auto-revert; manual review needed\"}" >> "$MANIFEST"
  fi
  exit 1
fi

# Promote via atomic symlink (claude-update did this already)
readlink "$VERSIONS_DIR/current"
echo "✓ Now on $new_version (patched 2.1.112 retained as fallback at $VERSIONS_DIR/2.1.112)"

# Mark stable in MANIFEST if not already
if ! grep -qE "\"version\":\"${new_version//./\\.}\".*stable" "$MANIFEST" 2>/dev/null; then
  echo "{\"version\":\"$new_version\",\"status\":\"stable\",\"date_added\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"notes\":\"upstream fix for GH #49253 getAppState regression — auto-reverted\"}" >> "$MANIFEST"
fi

log "promoted $new_version — patched 2.1.112 retained as fallback"

# Desktop notification
osascript -e "display notification \"Auto-reverted to $new_version. GH #49253 appears fixed upstream.\" with title \"Claude Code upgraded\" sound name \"Glass\"" 2>/dev/null || true
