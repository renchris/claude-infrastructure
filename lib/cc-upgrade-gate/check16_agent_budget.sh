#!/usr/bin/env bash
# check16_agent_budget.sh — #16 the per-agent token budget switch still works (decision D6).
# ─────────────────────────────────────────────────────────────────────────────
# Migration 0060 puts `CLAUDE_CODE_RIPPLING_TULIP=0` in the settings env block so that, if the
# server ever turns on the per-agent token budget, our sub-agents never see it. Measured on 2.1.293
# (docs/research/haiku55-upgrade-2026-10-07/decisions/D6-agent-budget-switch.md): forced on, Opus 5.5
# sub-agents finished an eight-file task in 0 of 9 runs against 6 of 6 with it off, with no error to
# catch. The switch is an undocumented env name, so a later binary can rename it and the line in
# settings.json goes inert without a word. This probe re-proves it on the CANDIDATE binary.
#
# Shape (D6's parent-side arm, the cheapest that separates the states; two model calls):
#   control  budget FORCED ON in the shell (RIPPLING_TULIP=100000, STREAMED_BUMBLEBEE=true), no switch
#   switch   the same shell, plus a --settings file whose env sets RIPPLING_TULIP=0 (the form of the
#            real edit: D6 arm S0 showed a settings value beats a shell value)
# Each asks the model to quote every sentence of its Agent tool description that gives a token
# budget for launched agents. `--setting-sources ""` keeps the operator's settings (where 0060 may
# already have put the switch) out of BOTH arms, or the control could never show the budget.
#
#   control quotes no budget            → SKIP: cannot tell (the forcing env no longer works, or the
#                                         model did not quote it); never a false green
#   control quotes it, switch quotes it → FAIL: the switch no longer removes a forced budget
#   control quotes it, switch does not  → PASS
#   either call returns nothing usable  → SKIP
#
# It also reports whether the server flags tengu_rippling_tulip / tengu_streamed_bumblebee are cached
# in any account's .claude.json (bin/cc-agent-budget-flags). That is context, not the verdict: a flag
# arriving is the day the switch starts to matter.
# shellcheck shell=bash

_G16_PROMPT='Do not launch anything. Quote verbatim every sentence in your Agent tool description that mentions a budget of tokens for agents you launch. If there is no such sentence, reply exactly NONE.'
_G16_RX='budget of [0-9][0-9,]* tokens'

# _g16_ask <cfg> <workdir> <settings-file|""> → the reply text on stdout; rc 1 if no usable answer.
# The prompt goes in on STDIN: `--tools` is variadic, so a prompt argument after it is read as a
# second tool name and the binary exits "Input must be provided" (measured on 2.1.293).
_g16_ask() {
  local cfg="$1" wd="$2" sf="$3" out="" to=() i=0 n="${GATE_RETRIES:-3}"
  local args=(--model "$GATE_MODEL" --print --output-format json --effort low --setting-sources ""
              --strict-mcp-config --no-session-persistence --tools Agent)
  [ -n "$sf" ] && args+=(--settings "$sf")
  command -v timeout >/dev/null 2>&1 && to=(timeout -k 5 "${CC_GATE16_TIMEOUT:-180}")
  while [ "$i" -lt "$n" ]; do
    out="$(cd "$wd" && env -u CLAUDE_CODE_TOTAL_TOKENS_REMINDER \
             CLAUDE_CONFIG_DIR="$cfg" DISABLE_AUTOUPDATER=1 CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 \
             CLAUDE_CODE_RIPPLING_TULIP=100000 CLAUDE_CODE_STREAMED_BUMBLEBEE=true \
             ${to[@]+"${to[@]}"} "$GATE_BIN" "${args[@]}" <<<"$_G16_PROMPT" 2>/dev/null)"
    if printf '%s' "$out" | python3 -c '
import json, sys
try:
    o = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if o.get("is_error") or not isinstance(o.get("result"), str):
    sys.exit(1)
print(o["result"])
' 2>/dev/null; then
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

# _g16_flags → one line summarizing the cached server flags across accounts.
_g16_flags() {
  local fl j
  fl="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/bin/cc-agent-budget-flags"
  [ -x "$fl" ] || fl="$HOME/.claude/bin/cc-agent-budget-flags"
  [ -x "$fl" ] || { echo "server flags: not read (cc-agent-budget-flags absent)"; return 0; }
  j="$("$fl" --json 2>/dev/null)"
  printf '%s' "$j" | jq -r '
    if type != "array" then "server flags: unreadable"
    else ([.[] | .account as $a | .flags[] | "\($a | sub(".*/"; "")):\(.flag)=\(.value | tostring)"]) as $hits
      | if ($hits | length) == 0 then "server flags: none cached on \(length) account(s)"
        else "server flags cached: \($hits | join(", "))\(if any(.[]; .alarm) then " — ALARM: ON with the switch absent" else "" end)" end
    end' 2>/dev/null || echo "server flags: unreadable"
}

check_16() {
  local bin="${GATE_BIN:-}" acct cfg wd ctl sw flags
  flags="$(_g16_flags)"

  if [ -z "$bin" ] || [ ! -x "$bin" ]; then
    emit_result 16 agent-budget-switch SKIP "candidate binary not executable — cannot probe the budget switch" "$flags"
    return 0
  fi
  acct="$(gate_primary_account 2>/dev/null)"
  cfg="$(gate_cfg_for "$acct" 2>/dev/null)"
  if [ -z "$cfg" ] || [ ! -d "$cfg" ]; then
    emit_result 16 agent-budget-switch SKIP "no config dir for account '${acct:-?}' — cannot probe" "$flags"
    return 0
  fi
  wd="$(mktemp -d "${TMPDIR:-/tmp}/gate16.XXXXXX")" || {
    emit_result 16 agent-budget-switch SKIP "mktemp failed — cannot probe" "$flags"; return 0; }
  printf '{"env":{"CLAUDE_CODE_RIPPLING_TULIP":"0"}}\n' > "$wd/switch.json"

  if ! ctl="$(_g16_ask "$cfg" "$wd" "")"; then
    emit_result 16 agent-budget-switch SKIP "control arm (budget forced on) returned no usable answer — cannot tell" "$flags"
    rm -rf "$wd"; return 0
  fi
  if ! printf '%s' "$ctl" | grep -Eiq "$_G16_RX"; then
    emit_result 16 agent-budget-switch SKIP \
      "forced-on control shows no agent budget — cannot tell whether =0 still works (forcing env renamed, or not quoted)" \
      "control reply: $(printf '%s' "$ctl" | tr '\n' ' ' | cut -c1-120); $flags"
    rm -rf "$wd"; return 0
  fi
  if ! sw="$(_g16_ask "$cfg" "$wd" "$wd/switch.json")"; then
    emit_result 16 agent-budget-switch SKIP "switch arm returned no usable answer — cannot tell" "$flags"
    rm -rf "$wd"; return 0
  fi
  rm -rf "$wd"

  if printf '%s' "$sw" | grep -Eiq "$_G16_RX"; then
    emit_result 16 agent-budget-switch FAIL \
      "CLAUDE_CODE_RIPPLING_TULIP=0 in settings env NO LONGER removes a forced per-agent budget — migration 0060 is inert on this binary" \
      "switch reply: $(printf '%s' "$sw" | grep -Eio "[^.]*${_G16_RX}[^.]*" | head -1 | cut -c1-140); $flags"
  else
    emit_result 16 agent-budget-switch PASS \
      "forced budget visible in control, removed by CLAUDE_CODE_RIPPLING_TULIP=0 in settings env" \
      "control: $(printf '%s' "$ctl" | grep -Eio "$_G16_RX" | head -1); $flags"
  fi
  return 0
}
