#!/usr/bin/env bash
# check18_lanes.sh — #18 lane certification: the credential-lane design still works on the CANDIDATE binary.
# ─────────────────────────────────────────────────────────────────────────────
# The zero-restart account move (docs/research/midturn-account-move-2026-10-25/REPORT.md) rests on client
# internals that move between releases: the store dir read per call from CLAUDE_SECURESTORAGE_CONFIG_DIR,
# the per-session keychain read cache, the mod ops env.set / turn.step / session.measure, the thread-404
# replay. Every binary move re-proves them by running tests/probes/lane/run.py --all against THIS candidate
# (anchors located by regex, then throwaway sessions only), which writes ~/.reso/lanes/cert/<version>.json
# before the pin moves. The lane broker refuses to arm on a binary without a CERTIFIED file
# (LR_LANE_CERT_REQUIRED), whatever this check reports.
#
# POLARITY: while lanes are not live, an uncertified candidate must not block an upgrade, so it is SKIP
# reported as NEWS (arming stays refused by the cert file). The lane activation (wave W9) sets
# GATE_LANES_GATING=1, and from then on an uncertified candidate is FAIL.
#   run.py 0 CERTIFIED → PASS · 1 UNCERTIFIED → SKIP (FAIL with GATE_LANES_GATING=1) · other → FAIL
#   (fail-closed: no verdict). EXPENSIVE (≈8 throwaway sessions, ~2-3 cents) → honors GATE_SPAWN.
# shellcheck shell=bash

# Resolve this file through symlinks before deriving the repo root (~/.claude is a per-file symlink farm).
_check18_root() {
  local p="${BASH_SOURCE[0]}" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  cd "$(dirname "$p")/../.." && pwd
}

check_18() {
  if [ "${GATE_SPAWN:-1}" != 1 ]; then
    emit_result 18 lane-cert SKIP "GATE_SPAWN=0 (deferred to lead baseline)" ""
    return 0
  fi
  local root suite out rc cert detail
  root="$(_check18_root)"
  suite="$root/tests/probes/lane/run.py"
  if [ ! -f "$suite" ]; then
    emit_result 18 lane-cert FAIL "probe suite missing: $suite" ""
    return 0
  fi

  out="$(python3 -I "$suite" --all --binary "$GATE_BIN" 2>/dev/null)"; rc=$?
  cert="$(printf '%s\n' "$out" | sed -n 's/^cert: //p' | tail -n 1)"
  detail="$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL|SKIP|INCONCLUSIVE|BLOCKED) ' | cut -c1-90 | tr '\n' ';')"
  case "$rc" in
    0) emit_result 18 lane-cert PASS \
         "lanes CERTIFIED on the candidate: pointer move, retrofit, re-home identity and the sensor all hold" \
         "cert=$cert $detail" ;;
    1) if [ "${GATE_LANES_GATING:-0}" = 1 ]; then
         emit_result 18 lane-cert FAIL \
           "lanes UNCERTIFIED on the candidate: a live lane fleet would break on this binary" "cert=$cert $detail"
       else
         emit_result 18 lane-cert SKIP \
           "NEWS: lanes UNCERTIFIED on the candidate (not live, so not a blocker; arming stays refused)" \
           "cert=$cert $detail"
       fi ;;
    *) emit_result 18 lane-cert FAIL "probe suite gave no verdict (rc=$rc)" "cert=$cert $detail" ;;
  esac
  return 0
}
