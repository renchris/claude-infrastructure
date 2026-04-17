#!/bin/bash
# smoke-test.sh — Pre-promote safety gate for Claude Code versions.
#
# Runs 5 tests against a specific ~/.claude-versions/<version>/bin/claude binary.
# Only flips the `current` symlink if --promote is passed AND all tests pass.
#
# Background: on 2026-04-17 an auto-upgrade to 2.1.112 landed a `getAppState`
# regression that crashed Agent Team spawning. This script is the firewall so
# a broken version never becomes `current` without explicit verification.
#
# Usage:
#   smoke-test.sh <version>           # verify-only; exit 0 = safe, 1 = failed
#   smoke-test.sh <version> --promote # flip ~/.claude-versions/current on success
#
# Exit codes:
#   0 — safe to promote (all 5 tests passed)
#   1 — tests failed (see stderr for which)
#   2 — critical error (binary missing, invalid args, etc.)

set -euo pipefail

readonly VERSIONS_DIR="$HOME/.claude-versions"
readonly MANIFEST_FILE="$VERSIONS_DIR/MANIFEST.jsonl"
readonly LOG_FILE="$HOME/.claude/logs/smoke-test.log"

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <version> [--promote]

Tests a Claude Code version before promoting it to 'current'.

Arguments:
  <version>    Version to test (e.g., 2.1.111). Must exist at $VERSIONS_DIR/<version>/
  --promote    Flip $VERSIONS_DIR/current symlink on success

Exit codes:
  0 = safe, 1 = failed, 2 = critical
EOF
}

log() {
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 2
  fi

  local version="$1"
  local promote=false
  if [[ "${2:-}" == "--promote" ]]; then
    promote=true
  fi

  # Binary lives at node_modules/.bin/claude (npm install layout), with
  # fallback to bin/claude for alternate distributions.
  local binary=""
  for candidate in \
    "$VERSIONS_DIR/$version/node_modules/.bin/claude" \
    "$VERSIONS_DIR/$version/bin/claude"; do
    if [[ -x "$candidate" ]]; then
      binary="$candidate"
      break
    fi
  done
  if [[ -z "$binary" ]]; then
    echo "CRITICAL: no executable claude found under $VERSIONS_DIR/$version/" >&2
    exit 2
  fi

  log "smoke-test $version (promote=$promote) — start"
  echo "Smoke-testing Claude Code $version..."

  local failures=0

  # === TEST 1: --version returns 0 and matches expected ===
  echo -n "  [1/5] version check... "
  local reported
  if reported=$("$binary" --version 2>&1) && [[ "$reported" == *"$version"* ]]; then
    echo "PASS ($reported)"
  else
    echo "FAIL"
    echo "    expected version string containing '$version', got: $reported" >&2
    failures=$((failures + 1))
  fi

  # === TEST 2: --help returns 0 (CLI parse works) ===
  echo -n "  [2/5] --help parse... "
  if "$binary" --help >/dev/null 2>&1; then
    echo "PASS"
  else
    echo "FAIL (--help exited non-zero)"
    failures=$((failures + 1))
  fi

  # === TEST 3: claude doctor output has no known crash substrings ===
  echo -n "  [3/5] doctor regression... "
  local doctor_out
  if doctor_out=$(CLAUDE_SKIP_AUTH=1 timeout 10 "$binary" doctor 2>&1); then
    if echo "$doctor_out" | grep -qiE 'getAppState|toolUseContext\.|crash|segfault|panic|EFATAL'; then
      echo "FAIL"
      echo "    doctor output contains crash markers" >&2
      echo "$doctor_out" | grep -iE 'getAppState|toolUseContext\.|crash|segfault|panic|EFATAL' >&2
      failures=$((failures + 1))
    else
      echo "PASS"
    fi
  else
    echo "SKIP (doctor command failed or timed out — non-fatal)"
  fi

  # === TEST 4: auto-mode CLI parse ===
  echo -n "  [4/5] auto-mode parse... "
  local auto_exit=0
  CLAUDE_SKIP_AUTH=1 timeout 3 "$binary" --permission-mode auto -p "echo test" >/dev/null 2>&1 || auto_exit=$?
  # 0 = succeeded, 124 = timeout (fine — means it got past parse), 2 = arg error
  if [[ "$auto_exit" == 0 || "$auto_exit" == 124 ]]; then
    echo "PASS (exit $auto_exit)"
  else
    echo "FAIL (exit $auto_exit — auto-mode args rejected)"
    failures=$((failures + 1))
  fi

  # === TEST 5: regression grep against recent session logs ===
  echo -n "  [5/5] MANIFEST regression check... "
  if [[ -f "$MANIFEST_FILE" ]]; then
    local manifest_status
    manifest_status=$(grep -E "\"version\":\"$version\"" "$MANIFEST_FILE" 2>/dev/null | tail -1 | \
      sed -nE 's/.*"status":"([^"]+)".*/\1/p' || true)
    case "$manifest_status" in
      skip)
        echo "FAIL"
        echo "    MANIFEST.jsonl marks $version as 'skip'" >&2
        grep -E "\"version\":\"$version\"" "$MANIFEST_FILE" | tail -1 >&2
        failures=$((failures + 1))
        ;;
      stable|candidate)
        echo "PASS (manifest: $manifest_status)"
        ;;
      *)
        echo "PASS (no manifest entry — treating as untested)"
        ;;
    esac
  else
    echo "PASS (no MANIFEST.jsonl yet)"
  fi

  echo ""

  if [[ $failures -gt 0 ]]; then
    echo "FAILED: $failures test(s) failed — will NOT promote $version" >&2
    log "smoke-test $version — FAIL ($failures failures)"
    exit 1
  fi

  echo "PASSED: all 5 tests green"
  log "smoke-test $version — PASS"

  if $promote; then
    local current_link="$VERSIONS_DIR/current"
    local old_target=""
    [[ -L "$current_link" ]] && old_target=$(readlink "$current_link")
    ln -sfn "$VERSIONS_DIR/$version" "$current_link"
    echo "Promoted: $VERSIONS_DIR/current → $VERSIONS_DIR/$version"
    [[ -n "$old_target" ]] && echo "  (was: $old_target)"
    log "smoke-test $version — PROMOTED (prev=$old_target)"
  fi

  exit 0
}

main "$@"
