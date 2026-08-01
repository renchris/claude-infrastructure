#!/usr/bin/env bash
# shellcheck disable=SC2329  # file-wide: the claude-next / _cc_sync_account stubs are invoked
#   indirectly by the eval'd cc-next body, not statically — shellcheck cannot see the call site.
# check12_resume.sh — #12 Resume flows route a candidate session to the right binary.
# ─────────────────────────────────────────────────────────────────────────────
# We resume sessions via `cc` (per-account) and `ccr` (cross-worktree picker). The gate proves
# `cc` routes a resumable session to the `claude` launcher (which runs the candidate binary) — an
# EFFECT-READ: extract the real cc body, stub `claude` as a recorder, stage a fake resumable session
# under the config dir cc computes, invoke it, and assert it emitted `claude --resume <sid>`.
# `ccr` is a zsh-only picker (emulate -L zsh) not bash-sourceable → its version→track routing is
# checked STRUCTURALLY (the routing line is present + intact).
#
# RETARGETED 2026-08-01 (was `cc-next` → asserting `claude-next --resume`). The 2026-07-31
# consolidation renamed the resumer cc-next → `cc` and made `cc-next() { cc "$@"; }`, while `cc`
# itself now invokes `claude --resume`. So the old assertion could not match any longer: it recorded
# nothing and reported FAIL against a resume path that works. Confirmed harness-side, not
# version-side, by a control run on 2026-08-01 that produced the identical FAIL on 2.1.219 (the
# binary we already run) and 2.1.220. `ccr`'s structural probe likewise now looks for the
# post-rename launcher names — `claude` for >=2.1.150, `claude-previous` for the pinned stable track.
# shellcheck shell=bash

check_12() {
  local zshrc="$HOME/.zshrc" body="" log="" faketmp="" recorded="" ccr_note=""
  if [ ! -f "$zshrc" ]; then
    emit_result 12 resume-routing SKIP "no ~/.zshrc to extract cc-next/ccr from" ""
    return 0
  fi
  body="$(extract_function cc "$zshrc")"
  if [ -z "$body" ]; then
    emit_result 12 resume-routing SKIP "cc() not found in ~/.zshrc" ""
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
    claude() { echo "claude $*" >>"$STUB_LOG"; }
    eval "$body"
    cc >/dev/null 2>&1
  )
  recorded="$(grep '^claude ' "$log" 2>/dev/null | tail -1)"
  rm -rf "$faketmp" "$log"

  # --- structural: ccr routes recorded-version 2.1.150+ to `claude`, older to claude-previous ------
  # Post-2026-07-31 the names moved (claude = eval/candidate track, claude-previous = pinned 2.1.114),
  # so BOTH arms must be present — a picker that lost the stable arm would resume an old session on
  # the wrong binary, which is the exact failure this probe exists to catch.
  local ccr_body=""
  ccr_body="$(extract_function ccr "$zshrc")"
  if printf '%s' "$ccr_body" | grep -q 'launcher=claude-previous' \
     && printf '%s' "$ccr_body" | grep -q 'launcher=claude'; then
    ccr_note="ccr (zsh-only) routes >=2.1.150 to claude and older to claude-previous — both arms present"
  else
    ccr_note="ccr not found / version→track routing arms missing (non-fatal)"
  fi

  case "$recorded" in
    *"--resume gatesid123"*)
      emit_result 12 resume-routing PASS \
        "cc routes a resumable session to the claude launcher (--resume gatesid123)" \
        "$ccr_note" ;;
    *)
      emit_result 12 resume-routing FAIL \
        "cc did NOT route to 'claude --resume <sid>' (got: ${recorded:-<nothing>})" \
        "$ccr_note" ;;
  esac
  return 0
}
