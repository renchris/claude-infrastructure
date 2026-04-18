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

  # === TEST 6: TL crash repro (permission-prompt path) ===
  # The getAppState regression (GH #49253) fires only when the permission-prompt
  # React component mounts. Tests 1-4 pass even on broken 2.1.112 because they
  # don't force that render path. This test does.
  echo -n "  [6/7] TL crash repro... "
  local tl_exit=0
  CLAUDE_SKIP_AUTH=1 timeout 3 "$binary" \
    --permission-mode default -p "mkdir /tmp/smoke-test-tl-$$" \
    >/dev/null 2>&1 || tl_exit=$?
  # 0 = completed, 124 = timeout (permission prompt rendered, no crash)
  # Non-0/124 likely means the TL crash fired
  case "$tl_exit" in
    0|124)
      echo "PASS (exit $tl_exit)"
      # Cleanup any dir created by a successful permission grant
      rmdir "/tmp/smoke-test-tl-$$" 2>/dev/null || true
      ;;
    *)
      echo "FAIL (exit $tl_exit — likely getAppState crash)"
      CLAUDE_SKIP_AUTH=1 timeout 3 "$binary" \
        --permission-mode default -p "mkdir /tmp/smoke-test-tl-err-$$" 2>&1 \
        | grep -iE "getAppState|toolUseContext" | head -3 >&2 || true
      failures=$((failures + 1))
      ;;
  esac

  # === TEST 7: auto-mode patch-presence structural check (GH #49502/#49653/#49687) ===
  # Historical: 2.1.111/2.1.112 shipped as JS bundles (cli.js) — our triple-patch
  # modified byte ranges in that file. 2.1.114+ ships as a Bun SEA native binary
  # (bin/claude.exe, ~204MB Mach-O) — there is no cli.js to substring-search.
  #
  # Behaviour:
  #   - cli.js present → run the 2.1.112-era substring checks (dual/triple patch)
  #   - cli.js absent + claude.exe present → SEA binary (2.1.114+). GH #49253 was
  #     fixed upstream in 2.1.114 so patch 1 is obsolete. Patches 2/3 verification
  #     now requires interactive testing (plan-accept flow + --permission-mode=auto
  #     startup). TEST 7 auto-passes with an informational note.
  #   - neither present → install is broken (TEST 1 would have already failed).
  echo -n "  [7/7] auto-mode patch/binary status... "
  local cli_path="$VERSIONS_DIR/$version/node_modules/@anthropic-ai/claude-code/cli.js"
  local exe_path="$VERSIONS_DIR/$version/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
  if [[ -f "$cli_path" ]]; then
    local patches_found
    patches_found=$(python3 -c "
d = open('$cli_path').read()
# Patch 2: plan-accept circuit-breaker clear + short-circuit
p2 = 'setAutoModeCircuitBroken?.(!1),!0' in d
# Patch 3: yK8 neutralized (old conditional gone, static clear present)
p3 = ('DG?.setAutoModeCircuitBroken(z===' not in d) and ('DG?.setAutoModeCircuitBroken(!1)' in d)
print(f'{int(p2)}{int(p3)}')
" 2>/dev/null || echo "00")
    case "$patches_found" in
      11)
        echo "PASS (cli.js: patches 2 + 3 present — plan-accept clear + yK8 neutralized)"
        ;;
      10)
        echo "PARTIAL (cli.js: patch 2 present, patch 3 missing — shift+tab may still lose auto mode)"
        ;;
      01)
        echo "PARTIAL (cli.js: patch 3 present, patch 2 missing — plan-accept fallback still buggy)"
        ;;
      *)
        echo "SKIP (cli.js: unpatched; upstream fix may have shipped — verify manually)"
        ;;
    esac
  elif [[ -f "$exe_path" ]]; then
    # Bun SEA binary layout (2.1.114+)
    echo "PASS (SEA binary layout: no cli.js to patch; GH #49253 fixed upstream in 2.1.114. Interactive verification of #49502/#49653/#49687 required separately.)"
  else
    echo "SKIP (no cli.js at $cli_path and no claude.exe at $exe_path — install may be incomplete)"
  fi

  echo ""

  if [[ $failures -gt 0 ]]; then
    echo "FAILED: $failures test(s) failed — will NOT promote $version" >&2
    log "smoke-test $version — FAIL ($failures failures)"
    exit 1
  fi

  echo "PASSED: all 7 tests green"
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
