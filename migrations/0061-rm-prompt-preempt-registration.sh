#!/bin/bash
# migration-class: c10
# migration-step: register hooks/rm-prompt-preempt.sh as a PermissionRequest hook (its own "Bash" entry) in ~/.claude/settings.json, which every account links to since 0037 — so ALL accounts at once. It answers Claude Code's built-in dangerous-removal dialog with an instant deny that carries the rewrite, instead of the 2-minute unattended timer that denies it anyway (64 such auto-denies 2026-09-29..10-11). It only ever denies, and only in auto/plan/bypassPermissions. It refuses to write unless cc-settings-parity reports every account linked and the LIVE hook exists. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0061-rm-prompt-preempt-registration.sh --confirm settings.json
# migration-subject: hooks/rm-prompt-preempt.sh
# migration-batch-hold: manual run scripts/rm-preempt-probe.sh first; register only on its verdict=PASS
# migration-verify: "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1 && jq -e '[.hooks.PermissionRequest[]? | select(.matcher == "Bash") | .hooks[]?.command] | any(. == "~/.claude/hooks/rm-prompt-preempt.sh")' "$HOME/.claude/settings.json" >/dev/null
#
# The verifier is config-dir-INVARIANT (as 0036-0041, 0047): one shared file, one answer from every dir.
#
# ══ 0061 — preempt the timed dangerous-removal dialog (docs/research/autodeny-prompts-2026-10-11/) ═
# Claude Code 2.1.284+ shows "will automatically deny this request in M:SS, to avoid blocking
# progress on an unattended session" for its dangerousRemoval safety check, in auto, plan and
# bypassPermissions mode. No allow rule and no PreToolUse allow clears it; nobody answers it in a
# workflow agent, so it costs 120 s and then denies, and after 3 expiries every later one is denied
# with no dialog. 51 of the 64 census hits were workflow agents; 40 were a `bash -c` script with no
# rm that the 2.1.293 inline-shell scanner cannot read. A PermissionRequest hook decision resolves
# the dialog before its timer and does not count toward the 3-expiry cap. This hook denies at once,
# for the measured shapes only, with a recipe that tells the model how to re-issue the call in a
# form the check can read, and keeps Claude Code's own "only a person may approve a removal" rule.
#
# BEFORE REGISTERING FLEET-WIDE (verdicts.md, efficacy lens, change 3): prove once that a hook deny
# resolves the dialog in under 5 s, both from the main thread and from a workflow-lean Workflow slot,
# with `--permission-mode auto` and a --settings overlay that registers only this hook. The claim
# rests on reading the 2.1.293 code; 35 of the 41 reachable rows are workflow dialogs. That proof is
# scripts/rm-preempt-probe.sh (main + workflow-lean subagent arms); the batch-hold above keeps
# scripts/c10-batch.sh from registering the hook before it has printed verdict=PASS.
#
# WHY ITS OWN ENTRY. The existing PermissionRequest groups (notify.sh, cc-permission-beacon.sh,
# workflow-script-edit-allow.sh) are observers or Write|Edit-only; a separate group appended at the
# end touches none of them. Hooks in different groups run in parallel, so order does not matter.
#
# SAFETY. Edits the REAL shared file once (README rule 7), backs it up, verifies BY CONTENT that the
# only change is the appended entry, and reads the effect back through the verifier. Idempotent.
# Revert: delete the entry, set CC_RM_PREEMPT=off in the environment, or restore the printed backup.
# Takes effect in NEW sessions.
#
# Usage: bash migrations/0061-rm-prompt-preempt-registration.sh --dry-run
#        bash migrations/0061-rm-prompt-preempt-registration.sh --check    # preflight, writes nothing
#        bash migrations/0061-rm-prompt-preempt-registration.sh --verify   # is the effect live?
#        bash migrations/0061-rm-prompt-preempt-registration.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first) · 4 REFUSED, live hook absent
# bash 3.2-safe.
set -uo pipefail

N=0061
# shellcheck disable=SC2088  # the literal "~/" is what settings.json stores; Claude Code expands it
CMD='~/.claude/hooks/rm-prompt-preempt.sh'
MATCHER='Bash'
EVENT='PermissionRequest'
f="$HOME/.claude/settings.json"
hook="$HOME/.claude/hooks/rm-prompt-preempt.sh"
lib="$HOME/.claude/hooks/lib/rm_prompt_shape.py"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
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
  jq -e --arg c "$CMD" --arg m "$MATCHER" \
    '[.hooks.PermissionRequest[]? | select(.matcher == $m) | .hooks[]?.command] | any(. == $c)' "$1" >/dev/null 2>&1
}

if [ "$mode" = verify ]; then
  "$parity" check >/dev/null 2>&1 && registered "$f"; exit $?
fi

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }

if registered "$real"; then
  printf '%s: already applied — %s is registered in %s\n' "$N" "$CMD" "$real"; exit 0
fi
"$parity" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed); the hook would reach some accounts and not others. Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}
if [ ! -x "$hook" ] || [ ! -f "$lib" ]; then
  printf '%s: REFUSED — the live hook %s or its library %s does not exist yet. Converge first: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' "$N" "$hook" "$lib" >&2
  exit 4
fi

ENTRY=$(jq -nc --arg c "$CMD" --arg m "$MATCHER" '{matcher:$m,hooks:[{type:"command",command:$c,timeout:10}]}')
printf '%s: will append to %s .hooks.%s: %s\n' "$N" "$real" "$EVENT" "$ENTRY"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/rm-prompt-preempt-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
if ! jq --argjson e "$ENTRY" '.hooks.PermissionRequest = ((.hooks.PermissionRequest // []) + [$e])' "$real" > "$tmp" 2>/dev/null \
   || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# BY CONTENT: everything but .hooks.PermissionRequest is the same document, and PermissionRequest
# gained exactly the one entry at its end.
same_rest=$( [ "$(jq -S 'del(.hooks.PermissionRequest)' "$real")" = "$(jq -S 'del(.hooks.PermissionRequest)' "$tmp")" ] && echo y )
want=$(jq -c --argjson e "$ENTRY" '(.hooks.PermissionRequest // []) + [$e]' "$real")
got=$(jq -c '.hooks.PermissionRequest' "$tmp")
if [ "$same_rest" != y ] || [ "$want" != "$got" ]; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: registered for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$N" "$bdir"
"$parity" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
registered "$f" || { printf '%s: did NOT verify — %s lacks the entry\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s carries the hook.\n' "$N" "$f"
