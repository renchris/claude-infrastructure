#!/bin/bash
# migration-class: c10
# migration-step: migration 0077 — register hooks/workflow-lean-shadow.py as a PreToolUse hook on the Workflow tool (its own "Workflow" entry) in ~/.claude/settings.json, which every account links to. It is LOG-ONLY: it never denies, and records per agent() call whether a deny-mode lean-agent hook would refuse it, whether the brief names commit/ship/Skill/MCP, and the hook's latency against its 5 s timeout — the 3-day shadow data the deny decision waits on. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0077-workflow-lean-shadow-registration.sh --confirm settings.json
# migration-subject: hooks/workflow-lean-shadow.py
# migration-verify: /usr/bin/env python3 "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1 && jq -e 'def cmd_bare: sub("^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"; ""); [.hooks.PreToolUse[]? | select(.matcher == "Workflow") | .hooks[]?.command] | any(((. // "") | cmd_bare) == "~/.claude/hooks/workflow-lean-shadow.py")' "$HOME/.claude/settings.json" >/dev/null
# cmd_bare: a hook command may carry its interpreter (/usr/bin/env python3 ~/.claude/hooks/x.py) since 0070.
#
# ══ 0077 — the Workflow lean-agent shadow hook (docs/plans/USAGE_LEVERS.md W1.3) ══
# A read-only Workflow slot run as the default agent loads CLAUDE.md, rules, memory and skills; as
# `agentType: 'workflow-lean'` it starts ~84% cheaper. A deny-mode hook is the candidate enforcement
# (65% conviction, docs/research/usage-levers-2026-10-23/round2/REPORT.md), and round 2 found the
# 2026-10-04 "deny" was a 5 s hook timeout that let the workflow through. So this registers the
# measuring half first; the deny decision reads its log ($HOME/.claude/logs/workflow-lean-shadow.jsonl).
#
# WHY ITS OWN ENTRY. No "Workflow" matcher exists; research-block.sh on "*" also sees the call, and
# hooks in different groups run in parallel, so a log-only entry can change no decision.
#
# SAFETY. Edits the REAL shared file once (README rule 7), backs it up, verifies BY CONTENT that the
# only change is the appended entry, and reads the effect back through the verifier. Idempotent.
# Revert: delete the entry, set CC_WORKFLOW_SHADOW=off in the environment, or restore the printed
# backup. Takes effect in NEW sessions.
#
# Usage: bash migrations/0077-workflow-lean-shadow-registration.sh --dry-run
#        bash migrations/0077-workflow-lean-shadow-registration.sh --check    # preflight, writes nothing
#        bash migrations/0077-workflow-lean-shadow-registration.sh --verify   # is the effect live?
#        bash migrations/0077-workflow-lean-shadow-registration.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first) · 4 REFUSED, live hook absent
# bash 3.2-safe.
set -uo pipefail

N=0077
# shellcheck disable=SC2088  # the literal "~/" is what settings.json stores; Claude Code expands it
CMD='~/.claude/hooks/workflow-lean-shadow.py'
MATCHER='Workflow'
f="$HOME/.claude/settings.json"
hook="$HOME/.claude/hooks/workflow-lean-shadow.py"
# What settings.json stores: the interpreter named (0070), the path as the cmd_bare form above.
REG_CMD="/usr/bin/env python3 $CMD"
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
  jq -e --arg c "$CMD" --arg m "$MATCHER" \
    'def cmd_bare: sub("^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"; ""); [.hooks.PreToolUse[]? | select(.matcher == $m) | .hooks[]?.command] | any(((. // "") | cmd_bare) == $c)' "$1" >/dev/null 2>&1
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
[ -f "$hook" ] || {
  printf '%s: REFUSED — the live hook %s does not exist yet. Converge first: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' "$N" "$hook" >&2
  exit 4
}

ENTRY=$(jq -nc --arg c "$REG_CMD" --arg m "$MATCHER" '{matcher:$m,hooks:[{type:"command",command:$c,timeout:5}]}')
printf '%s: will append to %s .hooks.PreToolUse: %s\n' "$N" "$real" "$ENTRY"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/workflow-lean-shadow-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
if ! jq --argjson e "$ENTRY" '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$e])' "$real" > "$tmp" 2>/dev/null \
   || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# BY CONTENT: everything but .hooks.PreToolUse is the same document, and PreToolUse gained exactly
# the one entry at its end.
same_rest=$( [ "$(jq -S 'del(.hooks.PreToolUse)' "$real")" = "$(jq -S 'del(.hooks.PreToolUse)' "$tmp")" ] && echo y )
want=$(jq -c --argjson e "$ENTRY" '(.hooks.PreToolUse // []) + [$e]' "$real")
got=$(jq -c '.hooks.PreToolUse' "$tmp")
if [ "$same_rest" != y ] || [ "$want" != "$got" ]; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: registered for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$N" "$bdir"
"${parity_cmd[@]}" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
registered "$f" || { printf '%s: did NOT verify — %s lacks the entry\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s carries the hook.\n' "$N" "$f"
