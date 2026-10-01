#!/bin/bash
# migration-class: c10
# migration-step: register hooks/research-block.sh as a PreToolUse hook on its own "*" entry (every tool, Workflow included) and raise hooks/research-precognition-nudge.sh's UserPromptSubmit timeout from 5 s to 10 s, in ~/.claude/settings.json, which every account links to since 0037 — so ALL accounts at once. It is the research program's tool block (REPORT.md §4.2, §8 item 6): it denies only inside a program the registry shows certifying or certified, so with no program it is inert. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0050-research-block-registration.sh --confirm settings.json
# migration-subject: hooks/research-block.sh
# migration-verify: "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1 && bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0050-research-block-registration.sh" --verify
#
# ══ 0050 — the research block and the router's longer timeout (wave B1, backlog 83fb0ff00849) ════
# docs/plans/RESEARCH_PROGRAM_BUILD.md wave B1; docs/research/upfront-research-exhaustion-2026-09-30/
# REPORT.md §4.1, §4.2 and §8 item 6. Ruled 2026-10-01 ("Proceed as you recommend with all").
#
# WHY "*". A completeness or pushback turn denies EVERY tool but the one certificate read, and the
# research verbs include Workflow, which no existing PreToolUse matcher names; 0024 measured that
# only "*" reaches every class. Its own group, appended: hooks in different groups run in parallel
# and any deny wins, so order does not matter, and no existing chain is touched.
#
# WHY 10 s. The router waits at most 6 s for the classifier (REPORT.md §4.1, an assumed input the
# pilot measures); under today's 5 s registration the hook is killed first. A killed router is not
# silent — it pre-writes `unavailable`, so only the research verbs are denied — but every prompt
# would be a fallback.
#
# COST. With no research program registered the hook is one bash fork and a file test (no jq, no
# python): the registry file is absent on a machine that has never run gate.sh register.
#
# SAFETY. Edits the REAL shared file once (README rule 7), backs it up, verifies BY CONTENT that the
# only changes are the appended entry and that one timeout, and reads the effect back. Idempotent.
# Revert: restore the printed backup, or launch with CC_RESEARCH_BLOCK=0 (the hook's kill switch).
# Takes effect in NEW sessions.
#
# Usage: bash migrations/0050-research-block-registration.sh --dry-run | --check | --verify
#        bash migrations/0050-research-block-registration.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first) · 4 REFUSED, live hook absent
# bash 3.2-safe.
set -uo pipefail

N=0050
# shellcheck disable=SC2088  # the literal "~/" is what settings.json stores; Claude Code expands it
CMD='~/.claude/hooks/research-block.sh'
# shellcheck disable=SC2088
ROUTER_CMD='~/.claude/hooks/research-precognition-nudge.sh'
MATCHER='*'
ROUTER_TIMEOUT=10
f="$HOME/.claude/settings.json"
hook="$HOME/.claude/hooks/research-block.sh"
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

# The target document: a pure function of the current one. The router's timeout is raised wherever
# its command is registered (never lowered); the "*" entry is appended once.
# shellcheck disable=SC2016  # jq program, not shell
TARGET='
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(
      .hooks = ((.hooks // []) | map(
        if .command == $rc and ((.timeout // 0) < $t) then .timeout = $t else . end))))
  | if ([.hooks.PreToolUse[]? | select(.matcher == $m) | .hooks[]?.command] | any(. == $c)) then .
    else .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$e]) end'
ENTRY=$(jq -nc --arg c "$CMD" --arg m "$MATCHER" '{matcher:$m,hooks:[{type:"command",command:$c,timeout:5}]}')
target() { jq --arg c "$CMD" --arg m "$MATCHER" --arg rc "$ROUTER_CMD" --argjson t "$ROUTER_TIMEOUT" --argjson e "$ENTRY" "$TARGET" "$1"; }

registered() {
  jq -e --arg c "$CMD" --arg m "$MATCHER" --arg rc "$ROUTER_CMD" --argjson t "$ROUTER_TIMEOUT" '
      ([.hooks.PreToolUse[]? | select(.matcher == $m) | .hooks[]?.command] | any(. == $c))
      and ([.hooks.UserPromptSubmit[]?.hooks[]? | select(.command == $rc) | (.timeout // 0)]
           | length > 0 and all(. >= $t))' "$1" >/dev/null 2>&1
}

if [ "$mode" = verify ]; then registered "$f"; exit $?; fi

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }

if registered "$real"; then
  printf '%s: already applied — %s is registered on "*" and the router timeout is %ss in %s\n' "$N" "$CMD" "$ROUTER_TIMEOUT" "$real"; exit 0
fi
jq -e --arg rc "$ROUTER_CMD" '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command == $rc)] | length > 0' "$real" >/dev/null 2>&1 || {
  printf '%s: REFUSED — %s is not registered as a UserPromptSubmit hook in %s, so there is no router timeout to raise and no router to label turns; the block would read every turn as unlabeled. Restore that registration first.\n' "$N" "$ROUTER_CMD" "$real" >&2
  exit 1
}
"$parity" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed); the block would reach some accounts and not others. Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}
[ -f "$hook" ] || {
  printf '%s: REFUSED — the live hook %s does not exist yet. Converge first: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' "$N" "$hook" >&2
  exit 4
}

printf '%s: will append to %s .hooks.PreToolUse: %s, and set %s timeout to %ss\n' "$N" "$real" "$ENTRY" "$ROUTER_CMD" "$ROUTER_TIMEOUT"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/research-block-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
if ! target "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# BY CONTENT: outside .hooks.PreToolUse and .hooks.UserPromptSubmit the document is unchanged;
# PreToolUse gained exactly the one entry at its end; UserPromptSubmit differs only in the timeout
# of the router's own command.
same_rest=$( [ "$(jq -S 'del(.hooks.PreToolUse, .hooks.UserPromptSubmit)' "$real")" = "$(jq -S 'del(.hooks.PreToolUse, .hooks.UserPromptSubmit)' "$tmp")" ] && echo y )
want_pre=$(jq -c --argjson e "$ENTRY" '(.hooks.PreToolUse // []) + [$e]' "$real")
got_pre=$(jq -c '.hooks.PreToolUse' "$tmp")
# shellcheck disable=SC2016  # jq program, not shell
strip='[.hooks.UserPromptSubmit[]? | .hooks |= map(if .command == $rc then del(.timeout) else . end)]'
same_ups=$( [ "$(jq -c --arg rc "$ROUTER_CMD" "$strip" "$real")" = "$(jq -c --arg rc "$ROUTER_CMD" "$strip" "$tmp")" ] && echo y )
if [ "$same_rest" != y ] || [ "$same_ups" != y ] || [ "$want_pre" != "$got_pre" ] || ! registered "$tmp"; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: registered for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$N" "$bdir"
"$parity" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
registered "$f" || { printf '%s: did NOT verify — %s lacks the entry or the timeout\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s carries the block and the router timeout.\n' "$N" "$f"
