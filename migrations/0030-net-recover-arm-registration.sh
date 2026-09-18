#!/bin/bash
# migration-class: c10
# migration-step: register hooks/net-recover-arm.sh on SessionStart AND Stop with asyncRewake, so a session whose turn died on an API error is WOKEN when the path comes back instead of waiting for the operator to notice — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0030-net-recover-arm-registration.sh
# migration-subject: ~/.claude/hooks/net-recover-arm.sh
# migration-verify: jq -e '[.hooks.SessionStart[].hooks[]? , .hooks.Stop[].hooks[]? | select(.command == "~/.claude/hooks/net-recover-arm.sh")] | length == 2 and all(.[]; .asyncRewake == true and .timeout >= 14400)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
# migration-conflict: jq -e '[.hooks.SessionStart[].hooks[]? , .hooks.Stop[].hooks[]? | select(.command == "~/.claude/hooks/net-recover-arm.sh")] | length >= 1 and any(.[]; (.asyncRewake // false) != true or (.timeout // 0) < 14400)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0030 — D4 of docs/plans/NONLIMIT_RESUME_LADDER.md (T6/W2-C, T14).
# Subject: hooks/net-recover-arm.sh · tests/net-recover-arm.bats
# Proof it can work at all: docs/research/api-error-rewake-proof-2026-09.md (W2-0, both arms)
#
# WHAT IT FIXES. On 2026-09-09 six panes sat blocked on a network death and the operator typed the
# correcting paragraph BY HAND, once per pane, in 93 seconds. Nothing on the box noticed the API had
# come back, because nothing was watching for it.
#
# WHY BOTH EVENTS, AND WHY NEITHER OF THEM IS THE DEATH. Measured on-box 2026-09-17 (CC 2.1.114,
# four arms, two controls): a turn that ends with an API error runs NO Stop hook at all, while the
# identical invocation against a healthy endpoint fires every hook in the chain. So the boundary
# where the fault happens is unreachable, and the watcher has to already EXIST when it happens —
# SessionStart arms it at birth, Stop re-arms it at each idle after the previous one has been spent.
# The companion arm is why this is worth registering rather than abandoning: a watcher armed BEFORE
# the death DOES get its exit 2 honoured afterwards, reproduced twice against a control.
#
# WHY THE VERIFIER DEMANDS asyncRewake:true AND timeout >= 14400 — BOTH, and both are silent when
# wrong. This is the INVERSE of 0026's oracle, deliberately:
#   * `asyncRewake: false/absent` ⇒ the hook is dispatched SYNCHRONOUSLY, and a ~4 h watch then
#     BLOCKS SESSION BIRTH for every session on the box. That is not a degraded feature, it is a
#     fleet outage, and it would read as "registered".
#   * a timeout under the subject's own 14340 s watch ⇒ the harness reaps the watcher mid-watch,
#     before it can ever reach its clean exit. The hook then reads as registered and can never fire,
#     which is this repo's most-measured trap — and the exact failure the subject exists to remove.
# Both wrong values are possible and neither announces itself, which is when README says to declare a
# conflict oracle. `overridden` needs the opposite fix from `not-delivered`: repair the entry, not add one.
#
# WHY c10. It edits settings.json. migrations/README.md: "A migration that touches settings.json, a
# launchd plist, or credentials declares c10 and waits for a human." So this STAGES and never self-runs.
#
# BLAST RADIUS. This hook runs at every session birth and every idle boundary on the box — the widest
# surface in this plan. Five bounds, four of them properties of the subject rather than promises:
#   1. It only ADDS entries; no existing entry is modified or removed.
#   2. THE HEADLESS GUARD IS THE LOAD-BEARING ONE. In a plain one-shot `claude -p`, asyncRewake is
#      dispatched SYNCHRONOUSLY, so an unguarded watch would wedge every headless probe and daemon
#      for hours. The subject refuses to arm there, and FAILS SAFE (skip) when it cannot resolve its
#      own harness argv. tests/net-recover-arm.bats pins both directions (cases 2, 3) and mutant 21
#      proves the guard is not decorative.
#   3. It can only ever wake on [an api-error record that is the LAST assistant record] ∧ [the turn
#      ended] ∧ [two unauthenticated reachability greens]. A healthy session never wakes (case 12),
#      a still-red network never wakes (case 11), and a live turn never wakes (case 10).
#   4. One wake per DEATH RECORD, latched on its uuid — never twice on one death (case 13), never
#      silent on a later one (case 14). A duplicate wake costs a model turn, which is the
#      alarm-polarity failure of a mechanism meant to make idleness cheap.
#   5. `CC_NET_RECOVER_ARM=0` is a total no-op, so the behaviour can be killed without editing
#      settings.json again.
# Every config file is backed up before it is touched and the edit is verified BY CONTENT before it
# replaces the live file, so "the operator can revert" is a property of this script.
#
# WHY IT WRITES EVERY CONFIG DIR. ~/.claude and its siblings are separate REAL files, not symlinks
# into the checkout, and live sessions run against all of them. Registering in one leaves every
# session launched against another exactly as blocked as before.
set -uo pipefail

# shellcheck disable=SC2088  # the tilde is DELIBERATELY literal: this string is stored INTO
# settings.json, where CC expands it at hook-run time. Every sibling entry is written the same way.
HOOK_CMD='~/.claude/hooks/net-recover-arm.sh'
HOOK_FILE="${CC_CLAUDE_DIR:-$HOME/.claude}/hooks/net-recover-arm.sh"
TIMEOUT=14400                       # 4 h; the subject's own watch is 14340 s, strictly under it
rc=0

command -v jq >/dev/null 2>&1 || { printf '0030: jq required\n' >&2; exit 1; }

# ── preconditions, re-derived at CONSUMPTION rather than trusted from the header ────────────────
# LANDED IS NOT LIVE. hooks/ and scripts/ are per-file symlink farms over the shared checkout, so
# these files exist on trunk long before the live layer carries them. Registering over a live layer
# that lacks them buys entries that run at every session birth and do nothing — a registered no-op
# reading GREEN, which is the failure this whole plan is about. Verify BY CONTENT, never by a lag
# counter.
if [ ! -x "$HOOK_FILE" ]; then
  printf '0030: NOT registered — %s is missing or not executable.\n' "$HOOK_FILE" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it first.\n' >&2
  exit 1
fi
_LR_LIVE="${CC_CLAUDE_DIR:-$HOME/.claude}/scripts/limit-recover/lr-lib.sh"
if [ ! -r "$_LR_LIVE" ] || ! grep -q 'lr_last_api_error' "$_LR_LIVE" 2>/dev/null; then
  printf '0030: NOT registered — the LIVE %s does not carry lr_last_api_error.\n' "$_LR_LIVE" >&2
  printf '      The hook would arm at every session birth and exit immediately, forever.\n' >&2
  exit 1
fi
_PROBE_LIVE="${CC_CLAUDE_DIR:-$HOME/.claude}/scripts/limit-recover/lr-probe.sh"
if [ ! -x "$_PROBE_LIVE" ]; then
  printf '0030: NOT registered — the LIVE %s is missing.\n' "$_PROBE_LIVE" >&2
  printf '      Without the reachability control the hook exits before it can ever wake.\n' >&2
  exit 1
fi
printf '0030: preconditions OK — subject executable, live lr-lib carries the predicate, probe present\n'

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Only touch a config that already runs sibling hooks on BOTH events. A settings.json without them
  # is not a fleet config, and inventing the arrays here would be a scope this migration never claimed.
  if ! jq -e '(.hooks.SessionStart | type == "array" and length > 0)
              and (.hooks.Stop | type == "array" and length > 0)' "$f" >/dev/null 2>&1; then
    printf '0030: %s — no SessionStart/Stop arrays; skipped (not a fleet config)\n' "$f"
    continue
  fi

  if jq -e --arg c "$HOOK_CMD" \
       '[.hooks.SessionStart[].hooks[]?, .hooks.Stop[].hooks[]? | select(.command == $c)] | length >= 2' \
       "$f" >/dev/null 2>&1; then
    printf '0030: %s — already registered\n' "$f"
    continue
  fi

  bak="$f.bak-0030-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0030: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0030-$$"
  # Appended to the FIRST group of each event. Order does not affect correctness: a backgrounded
  # asyncRewake hook cannot block or delay a sibling, which is the property the W2 probe established.
  if jq --arg c "$HOOK_CMD" --argjson t "$TIMEOUT" '
       (.hooks.SessionStart[0].hooks) += [{"type":"command","command":$c,"timeout":$t,
          "asyncRewake":true,
          "rewakeMessage":"🔌 The API path this session died on is reachable again:",
          "rewakeSummary":"net-recover: the API path is back"}]
       | (.hooks.Stop[0].hooks) += [{"type":"command","command":$c,"timeout":$t,
          "asyncRewake":true,
          "rewakeMessage":"🔌 The API path this session died on is reachable again:",
          "rewakeSummary":"net-recover: the API path is back"}]' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # Verify BY CONTENT before replacing the live file: exactly two entries, BOTH asyncRewake:true
    # and BOTH with a timeout at or above the subject's own watch. Those are the two values whose
    # wrong settings are silent and catastrophic (see the conflict oracle above).
    if jq -e --arg c "$HOOK_CMD" '
         [.hooks.SessionStart[].hooks[]?, .hooks.Stop[].hooks[]? | select(.command == $c)]
         | length == 2 and all(.[]; .asyncRewake == true and .timeout >= 14400)' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0030: %s — registered SessionStart + Stop (backup: %s)\n' "$f" "$bak"
    else
      rm -f "$tmp"; printf '0030: %s — edit did not verify; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0030: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

exit "$rc"
