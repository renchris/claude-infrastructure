#!/usr/bin/env bash
# shellcheck disable=SC2329  # file-wide: the _cc_* stubs are invoked indirectly by the eval'd
#   launcher body (not statically), so shellcheck cannot see their call site.
# check06_depth.sh — #6 Nested-spawn containment (GH #68619 runaway).
# ─────────────────────────────────────────────────────────────────────────────
# CC 2.1.219 flipped the nested-subagent spawn-depth DEFAULT 1→3, re-opening the still-open #68619
# runaway (4M tok / 5min) on this shared, spawn-heavy 4-account eval binary. The runaway is contained
# ONLY when CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 actually REACHES the binary. Distinct concern from
# #5 (which checks the whole launched flag-set): here the single question is CONTAINMENT, verified on
# BOTH surfaces that start the binary in this system —
#   (A) the gate's OWN headless path: `gate_headless` in common.sh must export the guard, and
#   (B) the interactive launcher: `claude-opus5` must pass SPAWN_DEPTH=1 into the child (effect-read).
# PASS iff BOTH pin the guard. If the launcher can't be extracted, part B is unverifiable → SKIP.
# shellcheck shell=bash

check_06() {
  local zshrc="$HOME/.zshrc" body_o5="" gate_pins=0 launcher_pins=0 argv=""

  # (A) the gate's own headless path pins the guard — introspect the ALREADY-SOURCED gate_headless
  # function body (layout-independent: robust to a CHECKS_DIR override where common.sh is not a
  # sibling file; reads the REAL in-memory contract, not a guessed file path).
  if declare -f gate_headless 2>/dev/null | grep -q 'CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1'; then
    gate_pins=1
  fi

  # (B) effect-read: the launcher passes SPAWN_DEPTH=1 into the candidate binary's env.
  [ -f "$zshrc" ] && body_o5="$(extract_function claude-opus5 "$zshrc")"
  if [ -z "$body_o5" ]; then
    emit_result 06 spawn-depth-containment SKIP \
      "claude-opus5() not extractable from ~/.zshrc — launcher effect-read unavailable" \
      "gate_headless pins the guard in common.sh=$gate_pins"
    return 0
  fi

  local fakehome="" log=""
  fakehome="$(mktemp -d)"
  log="$(mktemp)"
  build_stub_binary "$fakehome/.claude-219/node_modules/.bin/claude"
  (
    export HOME="$fakehome" STUB_LOG="$log"
    unset CLAUDE_CONFIG_DIR CLAUDE_OPUS5_PERM CLAUDE_OPUS5_EFFORT
    # shellcheck disable=SC2317  # invoked indirectly by the eval'd launcher body
    _cc_route_check()  { return 0; }
    # shellcheck disable=SC2317
    _cc_sync_account() { :; }
    # shellcheck disable=SC2317
    _cc_tlid()         { echo t; }
    eval "$body_o5"
    claude-opus5 -p ok >/dev/null 2>&1
  )
  grep -q '^SPAWN_DEPTH=1$' "$log" 2>/dev/null && launcher_pins=1
  argv="$(grep '^ARGV:' "$log" 2>/dev/null | tail -1)"
  rm -rf "$fakehome" "$log"

  if [ "$gate_pins" = 1 ] && [ "$launcher_pins" = 1 ]; then
    emit_result 06 spawn-depth-containment PASS \
      "SPAWN_DEPTH=1 reaches the binary via BOTH surfaces (launcher + gate_headless) — #68619 runaway contained" \
      "launcher child env SPAWN_DEPTH=1; common.sh gate_headless exports the guard"
  else
    emit_result 06 spawn-depth-containment FAIL \
      "spawn-depth guard NOT fully contained (launcher_pins=$launcher_pins gate_pins=$gate_pins) — #68619 runaway risk" \
      "argv=[${argv#ARGV: }]"
  fi
  return 0
}
