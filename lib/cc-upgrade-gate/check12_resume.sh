#!/usr/bin/env bash
# shellcheck disable=SC2329  # file-wide: the claude-next / _cc_sync_account stubs are invoked
#   indirectly by the eval'd cc-next body, not statically — shellcheck cannot see the call site.
# check12_resume.sh — #12 Resume flows route a candidate session to the right binary.
# ─────────────────────────────────────────────────────────────────────────────
# We resume sessions via `cc-next` (per-account) and `ccr` (cross-worktree picker). The gate proves
# `cc-next` routes a resumable session to the `claude-next` eval-track launcher (which runs the
# candidate binary) — an EFFECT-READ: extract the real cc-next body, stub `claude-next` as a recorder,
# stage a fake resumable session under the config dir cc-next computes, invoke it, and assert it
# emitted `claude-next --resume <sid>`. `ccr` is a zsh-only picker (emulate -L zsh) not bash-sourceable
# → its version→track routing is checked STRUCTURALLY (the routing line is present + intact).
# shellcheck shell=bash

check_12() {
  local zshrc="$HOME/.zshrc" body="" log="" faketmp="" recorded="" ccr_note=""
  if [ ! -f "$zshrc" ]; then
    emit_result 12 resume-routing SKIP "no ~/.zshrc to extract cc-next/ccr from" ""
    return 0
  fi
  body="$(extract_function cc-next "$zshrc")"
  if [ -z "$body" ]; then
    emit_result 12 resume-routing SKIP "cc-next() not found in ~/.zshrc" ""
    return 0
  fi

  # --- effect-read: stage a fake resumable session, stub the launcher, assert the resume route ------
  faketmp="$(mktemp -d)"
  log="$(mktemp)"
  (
    export CLAUDE_CONFIG_DIR="$faketmp" STUB_LOG="$log"
    cd "$faketmp" || exit 0
    hash="$(realpath . | sed 's/[^a-zA-Z0-9]/-/g')"
    pdir="$faketmp/projects/$hash"
    mkdir -p "$pdir"
    printf 'gatesid123' >"$pdir/.last-session-id"
    printf '{"type":"user"}\n' >"$pdir/gatesid123.jsonl"
    _cc_sync_account() { :; }
    claude-next() { echo "claude-next $*" >>"$STUB_LOG"; }
    eval "$body"
    cc-next >/dev/null 2>&1
  )
  recorded="$(grep '^claude-next' "$log" 2>/dev/null | tail -1)"
  rm -rf "$faketmp" "$log"

  # --- structural: ccr routes recorded-version 2.1.150+ to the claude-next track --------------------
  if extract_function ccr "$zshrc" | grep -q 'claude-next'; then
    ccr_note="ccr (zsh-only) routes to claude-next for the eval track — routing line present"
  else
    ccr_note="ccr not found / no claude-next route (non-fatal)"
  fi

  case "$recorded" in
    *"--resume gatesid123"*)
      emit_result 12 resume-routing PASS \
        "cc-next routes a resumable session to the claude-next eval-track launcher (--resume gatesid123)" \
        "$ccr_note" ;;
    *)
      emit_result 12 resume-routing FAIL \
        "cc-next did NOT route to 'claude-next --resume <sid>' (got: ${recorded:-<nothing>})" \
        "$ccr_note" ;;
  esac
  return 0
}
