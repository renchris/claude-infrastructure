#!/bin/bash
# migration-class: c10
# migration-step: register hooks/idle-keepalive.sh on Stop (its own group, asyncRewake, timeout 14400) in ~/.claude/settings.json, which every account links to since 0037 — so ALL accounts at once. It is the LOG-ONLY cache keepalive of docs/plans/USAGE_LEVERS.md § W3: 3300 s after an idle gap starts it writes one would-wake row to ~/.claude/logs/idle-keepalive.jsonl and exits 0. It never wakes a session (its EXIT trap forces exit 0, and asyncRewake wakes only on exit 2). It refuses to write unless cc-settings-parity reports every account linked and the LIVE hook exists. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0077-idle-keepalive-timer-registration.sh --confirm settings.json
# migration-subject: hooks/idle-keepalive.sh
# migration-verify: /usr/bin/env python3 "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1 && jq -e '[.hooks.Stop[]? | .hooks[]? | select(.command == "/bin/bash ~/.claude/hooks/idle-keepalive.sh") | select(.asyncRewake == true)] | length >= 1' "$HOME/.claude/settings.json" >/dev/null
#
# ══ 0077 — the idle-scoped keepalive timer, shadow mode (docs/plans/USAGE_LEVERS.md § W3) ═══════
# Round 2 (docs/research/usage-levers-2026-10-23/round2/REPORT.md, decision 3) reproduced why waiting
# main sessions re-write their whole context after 1-2 h idle: the 3300 s wake floor stands down
# while mailbox-wake-arm.sh is registered, and that watcher times out silently after 14340 s. A
# keepalive bolted onto the watcher would do nothing (its claim guard exits when a watcher is armed),
# so the keepalive is its own Stop hook, timed from the gap start. This registers it. The gap ledger
# that prices it already runs inside hooks/cache-expiry-tracker.sh and needs no registration; this
# step adds the timer, whose rows prove the timing works live, alongside a watcher, before any
# decision to let it wake (due after ~7 days of logs: bin/cc-idle-cache-readout).
#
# WHY ITS OWN GROUP. Hooks in different groups run in parallel; a separate group appended at the end
# of .hooks.Stop touches none of the existing entries. asyncRewake, like mailbox-wake-arm.sh, so the
# harness runs it in the background and does not reap it at the turn end. The hook carries the same
# headless guard as mailbox-wake-arm.sh, so it never blocks a `claude -p`.
#
# SAFETY. Edits the REAL shared file once (README rule 7), backs it up, verifies BY CONTENT that the
# only change is the appended group, and reads the effect back through the verifier. Idempotent.
# Revert: delete the group, set CC_IDLE_KEEPALIVE=off in the environment, or restore the printed
# backup. Takes effect in NEW sessions.
#
# Usage: bash migrations/0077-idle-keepalive-timer-registration.sh --dry-run
#        bash migrations/0077-idle-keepalive-timer-registration.sh --check    # preflight, writes nothing
#        bash migrations/0077-idle-keepalive-timer-registration.sh --verify   # is the effect live?
#        bash migrations/0077-idle-keepalive-timer-registration.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first) · 4 REFUSED, live hook absent
# bash 3.2-safe.
set -uo pipefail

N=0077
# shellcheck disable=SC2088  # the literal "~/" is what settings.json stores; Claude Code expands it
CMD='/bin/bash ~/.claude/hooks/idle-keepalive.sh'
f="$HOME/.claude/settings.json"
hook="$HOME/.claude/hooks/idle-keepalive.sh"
lib="$HOME/.claude/hooks/lib/idle_gap.py"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
# Through its interpreter, never by path: a #! exec keeps ~1.1 KiB of kernel memory on macOS 15.8.1
# (docs/research/kalloc-longterm-2026-10-21/REPORT.md). Read from its own #! line, so a stub still runs.
_pl=""; IFS= read -r _pl < "$parity" 2>/dev/null || true
case "$_pl" in *python3*) parity_cmd=(/usr/bin/env python3 "$parity") ;; *) parity_cmd=("$parity") ;; esac
command -v jq >/dev/null 2>&1 || { printf '%s: jq required — nothing written\n' "$N" >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --check) mode=check ;;
  --verify) mode=verify ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '%s: --confirm must name its target: --confirm settings.json\n' "$N" >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '%s: unknown argument %s (use --dry-run, --check, --verify or --confirm settings.json)\n' "$N" "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '%s: pass --dry-run, --check, --verify or --confirm settings.json\n' "$N" >&2; exit 2; }

registered() {
  jq -e --arg c "$CMD" '[.hooks.Stop[]? | .hooks[]? | select(.command == $c) | select(.asyncRewake == true)] | length >= 1' "$1" >/dev/null 2>&1
}

if [ "$mode" = verify ]; then
  "${parity_cmd[@]}" check >/dev/null 2>&1 && registered "$f"; exit $?
fi

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }

if registered "$real"; then
  printf '%s: already applied — %s is registered in %s\n' "$N" "$CMD" "$real"; exit 0
fi
"${parity_cmd[@]}" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed); the hook would reach some accounts and not others. Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}
if [ ! -f "$hook" ] || [ ! -f "$lib" ]; then
  printf '%s: REFUSED — the live hook %s or its library %s does not exist yet. Converge first: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' "$N" "$hook" "$lib" >&2
  exit 4
fi

ENTRY=$(jq -nc --arg c "$CMD" '{hooks:[{type:"command",command:$c,timeout:14400,asyncRewake:true}]}')
printf '%s: will append to %s .hooks.Stop: %s\n' "$N" "$real" "$ENTRY"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/idle-keepalive-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
if ! jq --argjson e "$ENTRY" '.hooks.Stop = ((.hooks.Stop // []) + [$e])' "$real" > "$tmp" 2>/dev/null \
   || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# BY CONTENT: everything but .hooks.Stop is the same document, and Stop gained exactly the one group
# at its end.
same_rest=$( [ "$(jq -S 'del(.hooks.Stop)' "$real")" = "$(jq -S 'del(.hooks.Stop)' "$tmp")" ] && echo y )
want=$(jq -c --argjson e "$ENTRY" '(.hooks.Stop // []) + [$e]' "$real")
got=$(jq -c '.hooks.Stop' "$tmp")
if [ "$same_rest" != y ] || [ "$want" != "$got" ]; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: registered for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$N" "$bdir"
"${parity_cmd[@]}" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
registered "$f" || { printf '%s: did NOT verify — %s lacks the entry\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s carries the hook.\n' "$N" "$f"
