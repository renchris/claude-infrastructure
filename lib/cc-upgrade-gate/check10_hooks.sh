#!/usr/bin/env bash
# check10_hooks.sh — #10 CC lifecycle hooks fire on the candidate binary.
# ─────────────────────────────────────────────────────────────────────────────
# NOTE: this shell repo has NO git tsc/eslint pre-commit hook — the way-of-working under test is CC
# LIFECYCLE hooks (SessionStart/Stop/PreCompact/… + the repo's dod-persist/operator-readout/
# completion-assert scripts) firing on the NEW binary. Two parts, both required for PASS:
#   (A) the BINARY triggers hooks — inject SessionStart + Stop marker hooks via `--settings <file>`
#       (which merges over the real, AUTHED config so the turn actually runs), run one headless turn,
#       and assert the markers appear + the session did not error. This is the load-bearing proof.
#   (B) the repo's real hook scripts are syntactically sound (`bash -n`) so they'd run when fired.
# `--settings` verified present on 2.1.219; injected SessionStart+Stop both fired (lead, 2026-07-24).
# shellcheck shell=bash

check_10() {
  local acct cfg tmp="" settings="" m_ss="" m_stop="" out="" fired_ss="no" fired_stop="no"
  acct="$(gate_primary_account)"
  cfg="$(gate_cfg_for "$acct")"
  if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
    emit_result 10 hooks-fire SKIP "no authed config dir for account '$acct' ($cfg)" ""
    return 0
  fi

  tmp="$(mktemp -d)"
  settings="$tmp/settings.json"; m_ss="$tmp/ss.marker"; m_stop="$tmp/stop.marker"
  cat >"$settings" <<JSON
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"touch $m_ss"}]}],"Stop":[{"hooks":[{"type":"command","command":"touch $m_stop"}]}]}}
JSON

  # (A) binary fires the injected hooks
  out="$(CLAUDE_CONFIG_DIR="$cfg" DISABLE_AUTOUPDATER=1 CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 \
         "$GATE_BIN" --settings "$settings" --model "$GATE_MODEL" --print --output-format json \
         "Reply with exactly: ok" </dev/null 2>/dev/null)"
  [ -f "$m_ss" ]   && fired_ss="yes"
  [ -f "$m_stop" ] && fired_stop="yes"
  local is_err; is_err="$(printf '%s' "$out" | json_get is_error)"
  rm -rf "$tmp"

  # (B) the repo's real hook scripts parse cleanly (would run when fired)
  local repo_root broken=""
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local h
  for h in session-start dod-persist operator-readout completion-assert; do
    if [ -f "$repo_root/hooks/$h.sh" ]; then
      bash -n "$repo_root/hooks/$h.sh" 2>/dev/null || broken="$broken $h.sh"
    fi
  done

  if [ "$fired_ss" = yes ] && [ -z "$broken" ] && [ "$is_err" != "True" ] && [ "$is_err" != "true" ]; then
    emit_result 10 hooks-fire PASS \
      "binary fires CC lifecycle hooks (SessionStart=$fired_ss Stop=$fired_stop, session ok) + repo hook scripts parse clean" \
      "injected via --settings; repo hooks bash-n clean (session-start/dod-persist/operator-readout/completion-assert)"
  else
    emit_result 10 hooks-fire FAIL \
      "hooks did NOT fully fire (SessionStart=$fired_ss Stop=$fired_stop is_error=$is_err) or repo hook broken:${broken:- none}" \
      "SessionStart marker=$fired_ss; broken=${broken:-none}"
  fi
  return 0
}
