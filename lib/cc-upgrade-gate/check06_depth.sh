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
#   (B) the interactive launcher: `claude` must pass SPAWN_DEPTH=1 into the child (effect-read).
# PASS iff BOTH pin the guard. If the launcher can't be extracted, part B is unverifiable → SKIP.
#
# RETARGETED 2026-08-01 (was `claude-opus5`). Same root cause as check05: the 2026-07-31
# consolidation turned claude-opus5 into a one-line shim `{ claude "$@"; }`, so extracting it and
# effect-reading it found launcher_pins=0 and this check reported "#68619 runaway risk" against a
# system whose guard was in fact intact — the alarm was reading the wrong function. A control run
# on 2026-08-01 confirmed the identical FAIL on BOTH 2.1.219 and 2.1.220, which is what separated
# a stale check from a real regression. Part B now reuses check05's `_gate05_effect_read` helper,
# which derives the stub path from the launcher's own `_bin=` line and plants a passthrough
# cc-close-attrib — without the latter the exec chain dies under the fake $HOME and the empty argv
# reads as an un-pinned guard, i.e. this check would fail LOUD for a purely harness reason.
# shellcheck shell=bash

check_06() {
  local zshrc="$HOME/.zshrc" body_main="" gate_pins=0 launcher_pins=0 argv=""

  # (A) the gate's own headless path pins the guard — introspect the ALREADY-SOURCED gate_headless
  # function body (layout-independent: robust to a CHECKS_DIR override where common.sh is not a
  # sibling file; reads the REAL in-memory contract, not a guessed file path).
  if declare -f gate_headless 2>/dev/null | grep -q 'CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1'; then
    gate_pins=1
  fi

  # (B) effect-read: the launcher passes SPAWN_DEPTH=1 into the candidate binary's env.
  [ -f "$zshrc" ] && body_main="$(extract_function claude "$zshrc")"
  if [ -z "$body_main" ]; then
    emit_result 06 spawn-depth-containment SKIP \
      "claude() not extractable from ~/.zshrc — launcher effect-read unavailable" \
      "gate_headless pins the guard in common.sh=$gate_pins"
    return 0
  fi

  # Shared with check05: derives the stub path from the launcher's OWN `_bin=` line (so a version
  # bump cannot strand this probe) and plants a passthrough cc-close-attrib under the fake $HOME
  # (without it, claude()'s exec chain dies before the stub and the guard reads as ABSENT).
  _g5_main_rel="$(_gate05_bin_relpath "$body_main")"
  if [ -z "$_g5_main_rel" ]; then
    emit_result 06 spawn-depth-containment SKIP \
      "claude() carries no \$HOME/.claude-NNN binary pin to plant a stub against" \
      "gate_headless pins the guard in common.sh=$gate_pins"
    return 0
  fi

  local fakehome=""
  fakehome="$(mktemp -d)"
  _gate05_stub_closeattrib "$fakehome"
  _gate05_effect_read claude "$zshrc" "$fakehome"
  [ "$_g5_depth" = "SPAWN_DEPTH=1" ] && launcher_pins=1
  argv="$_g5_argv"
  rm -rf "$fakehome"

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
