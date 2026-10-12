#!/usr/bin/env bash
# check17_rm_preempt.sh — #17 the rm-prompt-preempt hook still answers the TIMED dangerous-removal dialog.
# ─────────────────────────────────────────────────────────────────────────────
# Unattended work depends on it: Claude Code raises a dangerousRemoval dialog with a 120 s auto-deny
# timer for removals it cannot check (and for `bash -c` scripts it cannot read), no allow rule clears
# it, and hooks/rm-prompt-preempt.sh answers it at once with a deny that carries the rewrite
# (docs/research/autodeny-prompts-2026-10-11/). Both the scanner and the PermissionRequest contract move
# between releases, so every binary move re-proves the hook with scripts/rm-preempt-probe.sh, run against
# THIS candidate: real interactive auto-mode sessions (main thread + a Workflow slot) in detached tmux.
# Self-evidencing: PASS needs the hook's own deny text in the transcript within 30 s of the tool_use.
#   probe 0 PASS → PASS · 1 FAIL (the dialog waited out its timer) → FAIL · 4 NOTRIGGER (the candidate no
#   longer raises the dialog for the trap shape) → SKIP, reported as news · 3 / anything else → FAIL
#   (fail-closed: tmux missing, timeout, no transcript). EXPENSIVE (two sessions) → honors GATE_SPAWN.
# shellcheck shell=bash

# Resolve this file through symlinks before deriving the repo root (~/.claude is a per-file symlink farm).
_check17_root() {
  local p="${BASH_SOURCE[0]}" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  cd "$(dirname "$p")/../.." && pwd
}

check_17() {
  if [ "${GATE_SPAWN:-1}" != 1 ]; then
    emit_result 17 rm-preempt SKIP "GATE_SPAWN=0 (deferred to lead baseline)" ""
    return 0
  fi

  local acct cfg root probe out rc
  acct="$(gate_primary_account)"
  cfg="$(gate_cfg_for "$acct")"
  if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
    emit_result 17 rm-preempt SKIP "no config dir for account '$acct' ($cfg)" ""
    return 0
  fi
  root="$(_check17_root)"
  probe="$root/scripts/rm-preempt-probe.sh"
  if [ ! -f "$probe" ]; then
    emit_result 17 rm-preempt FAIL "probe missing: $probe" ""
    return 0
  fi

  out="$(CLAUDE_CONFIG_DIR="$cfg" CC_PROBE_BIN="$GATE_BIN" CC_PROBE_MODEL="$GATE_MODEL" \
    bash "$probe" --arm both 2>&1)"; rc=$?
  out="$(printf '%s' "$out" | grep -E '^(arm=|verdict=)' | tr '\n' ' ')"
  case "$rc" in
    0) emit_result 17 rm-preempt PASS \
         "the hook denies the timed removal dialog at once, main thread and Workflow slot" "$out" ;;
    4) emit_result 17 rm-preempt SKIP \
         "NEWS: this binary no longer raises the removal dialog for the bash -c trap shape; re-check whether the hook is still needed" "$out" ;;
    1) emit_result 17 rm-preempt FAIL \
         "the hook no longer preempts the timed removal dialog: unattended removals wait 120 s and are denied again" "$out" ;;
    *) emit_result 17 rm-preempt FAIL "probe gave no verdict (rc=$rc)" "$out" ;;
  esac
  return 0
}
