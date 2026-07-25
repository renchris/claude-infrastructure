#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031,SC2329  # file-wide, all intentional: HOME/STUB_LOG are exported
#   INTO subshells on purpose (the log PATH vars log_o5/log_next are set + read in the PARENT, so
#   nothing is lost); the _cc_* stubs are invoked indirectly by the eval'd launcher body, not statically.
# check05_launcher.sh — #5 Launcher resolution (an EFFECT-READ, never a grep).
# ─────────────────────────────────────────────────────────────────────────────
# The way we launch Opus 5 is the `claude-opus5()` shell function in ~/.zshrc. A grep of that
# function proves nothing — a launcher can define a flag and still not pass it (wrong branch, a
# guard that aborts first, an override). So this probe RUNS the real launcher body against a STUB
# binary planted under a fake $HOME and reads what the launcher ACTUALLY handed the child:
# the argv + the exported env. PASS iff the opus5 launcher passes, exactly:
#   --model claude-opus-5   ·   --effort high   ·   --permission-mode default   ·   SPAWN_DEPTH=1
# (the CLAUDE_OPUS5_EFFORT / CLAUDE_OPUS5_PERM defaults + the depth-guard export).
#
# The `_cc_route_check` stub returns 0 with EMPTY stdout on purpose: that leaves `_wt=""` so the
# launcher's DIRECT (non-worktree) branch runs. Returning non-zero would trip the launcher's own
# "worktree isolation failed" guard and abort BEFORE the binary is ever invoked (nothing recorded).
#
# Secondary (non-fatal) spot-check: claude-next inherits the same depth-guard + passes --model.
# shellcheck shell=bash

check_05() {
  local zshrc="$HOME/.zshrc"
  local body_o5="" body_next="" fakehome="" log_o5="" argv_o5="" miss="" next_note=""

  if [ ! -f "$zshrc" ]; then
    emit_result 05 launcher-resolution SKIP "no ~/.zshrc to extract the launcher from" ""
    return 0
  fi
  body_o5="$(extract_function claude-opus5 "$zshrc")"
  if [ -z "$body_o5" ]; then
    emit_result 05 launcher-resolution SKIP "claude-opus5() not found in ~/.zshrc" ""
    return 0
  fi

  # --- primary: effect-read the opus5 launcher against a stub binary under a FAKE HOME ----------
  fakehome="$(mktemp -d)"
  log_o5="$(mktemp)"
  build_stub_binary "$fakehome/.claude-219/node_modules/.bin/claude"
  (
    export HOME="$fakehome" STUB_LOG="$log_o5"
    unset CLAUDE_CONFIG_DIR CLAUDE_OPUS5_PERM CLAUDE_OPUS5_EFFORT
    # shellcheck disable=SC2317  # invoked indirectly by the eval'd launcher body, not statically
    _cc_route_check()  { return 0; }   # empty stdout + rc 0 → _wt="" → direct (non-worktree) branch
    # shellcheck disable=SC2317
    _cc_sync_account() { :; }
    # shellcheck disable=SC2317
    _cc_tlid()         { echo t; }
    eval "$body_o5"
    claude-opus5 -p ok >/dev/null 2>&1
  )
  argv_o5="$(grep '^ARGV:' "$log_o5" 2>/dev/null | tail -1)"

  case "$argv_o5" in *"--model claude-opus-5"*)     : ;; *) miss="$miss model" ;; esac
  case "$argv_o5" in *"--effort high"*)             : ;; *) miss="$miss effort" ;; esac
  case "$argv_o5" in *"--permission-mode default"*) : ;; *) miss="$miss permission-mode" ;; esac
  grep -q '^SPAWN_DEPTH=1$' "$log_o5" 2>/dev/null   ||    miss="$miss depth-guard"

  if [ -n "$miss" ]; then
    emit_result 05 launcher-resolution FAIL \
      "claude-opus5 launcher did NOT pass:${miss} (effect-read of the child argv/env)" \
      "argv=[${argv_o5#ARGV: }] $(grep -m1 '^SPAWN_DEPTH=' "$log_o5" 2>/dev/null)"
    rm -rf "$fakehome" "$log_o5"
    return 0
  fi

  # --- secondary (non-fatal): claude-next inherits the depth-guard + passes --model -------------
  next_note="claude-next: not present in ~/.zshrc (secondary check skipped)"
  body_next="$(extract_function claude-next "$zshrc")"
  if [ -n "$body_next" ]; then
    local log_next="" argv_next="" next_ok=0
    log_next="$(mktemp)"
    build_stub_binary "$fakehome/.claude-183/node_modules/.bin/claude"
    (
      export HOME="$fakehome" STUB_LOG="$log_next"
      unset CLAUDE_CONFIG_DIR CLAUDE_NEXT_MODEL CLAUDE_DEFAULT_EFFORT
      # shellcheck disable=SC2317
      _cc_route_check()  { return 0; }
      # shellcheck disable=SC2317
      _cc_sync_account() { :; }
      # shellcheck disable=SC2317
      _cc_tlid()         { echo t; }
      eval "$body_next"
      claude-next -p ok >/dev/null 2>&1
    )
    argv_next="$(grep '^ARGV:' "$log_next" 2>/dev/null | tail -1)"
    if grep -q '^SPAWN_DEPTH=1$' "$log_next" 2>/dev/null; then
      case "$argv_next" in *"--model "*) next_ok=1 ;; esac
    fi
    if [ "$next_ok" = 1 ]; then
      next_note="claude-next OK: --model present + SPAWN_DEPTH=1 (depth-guard inherited)"
    else
      next_note="claude-next WARN (non-fatal): argv=[${argv_next#ARGV: }]"
    fi
    rm -f "$log_next"
  fi

  emit_result 05 launcher-resolution PASS \
    "claude-opus5 passes --model claude-opus-5 + --effort high + --permission-mode default + SPAWN_DEPTH=1 (effect-read of child argv/env)" \
    "$next_note"
  rm -rf "$fakehome" "$log_o5"
  return 0
}
