#!/bin/bash
# migration-class: c10
# migration-step: regroup the 18 SessionStart hooks in ~/.claude/settings.json (every account links to it since 0037, so ALL accounts at once): fold the nine context and banner hooks into ONE registration of hooks/session-start-dispatch.sh, and mark the five pure side-effect hooks "async": true. 18 registrations become 10. It is fix row 17 of docs/research/concurrency-scale-2026-10-04 (startup span p95 10.1 s, max 35.5 s). It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0056-session-start-dispatch.sh --confirm settings.json
# migration-subject: hooks/session-start-dispatch.sh
# migration-verify: "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1 && bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0056-session-start-dispatch.sh" --verify
#
# ══ 0056 — SessionStart: one dispatcher for the nine folded hooks, async for the five side effects ══
# docs/plans/CONCURRENCY_PROGRAM.md stage 1 wave B; docs/research/concurrency-scale-2026-10-04/README.md
# §3 row 17 and j-startup-hang.md. Wave A owns 0055 and 0057; this number is wave B's.
#
# THE REGROUPING, by what each hook owes the session at turn 1:
#   FOLD (9) — print context or an operator banner, small, non-gating: session-start, setup-plan-
#     symlinks, setup-task-symlinks, activation-watch, escalation-watch, accounts-board,
#     session-index-start, config-mirror-assert, frontier-status. They run in parallel inside
#     hooks/session-start-dispatch.sh, which merges them into one additionalContext and one
#     systemMessage, so turn-1 delivery and the banner channel are both kept.
#   ASYNC (5) — side effects only, nothing Claude reads: pre-session-validate (it forks
#     `claude --version`), lead-crash-watchdog, session-register, live-session-registry,
#     net-context-stamp. Claude Code spawns an async hook exactly as a sync one (same $PPID), it just
#     does not wait for it.
#   UNCHANGED (4) — dod-persist, desk-brief-inject and `mailbox-drain.sh session-start` are gating and
#     large (merged they would share one 10,000-char cap), and mailbox-wake-arm is already asyncRewake.
# The banner hooks are NOT made async: an async hook's systemMessage reaches the model as context and
# the terminal hides it — the reverse of the channel they chose (accounts-board.sh's channel proof).
#
# COST. One harness spawn instead of nine for the fold, and the five side effects off the startup path.
# The dispatcher bounds each child at 9 s in its own process group (registered at 12 s), so a hung child
# costs only its own output. Ordering is unchanged: all SessionStart hooks already ran in parallel.
#
# SAFETY. Edits the REAL shared file once (README rule 7), backs it up, verifies BY CONTENT that the only
# changes are: the nine commands gone, the one dispatcher entry appended, `async` set on the five, and any
# group the fold emptied dropped. Idempotent. Revert: restore the printed backup. Takes effect in NEW
# sessions.
#
# Usage: bash migrations/0056-session-start-dispatch.sh --dry-run | --check | --verify
#        bash migrations/0056-session-start-dispatch.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first) · 4 REFUSED, live hook absent
# bash 3.2-safe.
set -uo pipefail

N=0056
# shellcheck disable=SC2088  # the literal "~/" is what settings.json stores; Claude Code expands it
DISPATCH='~/.claude/hooks/session-start-dispatch.sh'
FOLD='["~/.claude/hooks/session-start.sh","~/.claude/hooks/setup-plan-symlinks.sh","~/.claude/hooks/setup-task-symlinks.sh","~/.claude/hooks/activation-watch.sh","~/.claude/hooks/escalation-watch.sh","~/.claude/hooks/accounts-board.sh","~/.claude/hooks/session-index-start.sh","~/.claude/hooks/config-mirror-assert.sh","~/.claude/hooks/frontier-status.sh"]'
ASYNC='["~/.claude/hooks/pre-session-validate.sh","~/.claude/hooks/lead-crash-watchdog.sh","~/.claude/hooks/session-register.sh","~/.claude/hooks/live-session-registry.sh","~/.claude/hooks/net-context-stamp.sh"]'
f="$HOME/.claude/settings.json"
hook="$HOME/.claude/hooks/session-start-dispatch.sh"
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

ENTRY=$(jq -nc --arg d "$DISPATCH" '{hooks:[{type:"command",command:$d,timeout:12}]}')
# The target document: a pure function of the current one.
# shellcheck disable=SC2016  # jq program, not shell
TARGET='
  ([.hooks.SessionStart[]?.hooks[]?.command] | any(. == $d)) as $have
  | .hooks.SessionStart = (
      ((.hooks.SessionStart // [])
        | map(.hooks = ((.hooks // [])
                | map(select(.command as $c | $fold | index([$c]) | not))
                | map(if (.command as $c | $async | index([$c])) then .async = true else . end)))
        | map(select((.hooks | length) > 0)))
      + (if $have then [] else [$e] end))'
target() { jq --arg d "$DISPATCH" --argjson fold "$FOLD" --argjson async "$ASYNC" --argjson e "$ENTRY" "$TARGET" "$1"; }

registered() {
  jq -e --arg d "$DISPATCH" --argjson fold "$FOLD" --argjson async "$ASYNC" '
      [.hooks.SessionStart[]?.hooks[]?] as $h
      | ([$h[] | .command] | any(. == $d))
        and ([$h[] | select(.command as $c | $fold | index([$c]))] | length == 0)
        and ([$h[] | select(.command as $c | $async | index([$c])) | (.async == true)] | all)' "$1" >/dev/null 2>&1
}

if [ "$mode" = verify ]; then registered "$f"; exit $?; fi

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }

if registered "$real"; then
  printf '%s: already applied — %s carries the dispatcher, none of the nine folded hooks, and async on the five\n' "$N" "$real"; exit 0
fi
"$parity" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed); the regrouping would reach some accounts and not others. Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}
[ -x "$hook" ] || {
  printf '%s: REFUSED — the live dispatcher %s does not exist yet, and removing the nine registrations without it would drop their output. Converge first: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' "$N" "$hook" >&2
  exit 4
}

printf '%s: will fold %s into %s and set async on %s in %s\n' "$N" "$FOLD" "$ENTRY" "$ASYNC" "$real"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/session-start-dispatch-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
if ! target "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# BY CONTENT: outside .hooks.SessionStart nothing changed; inside it, the hooks that are neither folded
# nor the dispatcher are the same entries in the same order once `async` is set aside.
same_rest=$( [ "$(jq -S 'del(.hooks.SessionStart)' "$real")" = "$(jq -S 'del(.hooks.SessionStart)' "$tmp")" ] && echo y )
# shellcheck disable=SC2016  # jq program, not shell
kept='[.hooks.SessionStart[]?.hooks[]? | select(.command as $c | ($fold | index([$c]) | not) and $c != $d) | del(.async)]'
same_kept=$( [ "$(jq -c --arg d "$DISPATCH" --argjson fold "$FOLD" "$kept" "$real")" = "$(jq -c --arg d "$DISPATCH" --argjson fold "$FOLD" "$kept" "$tmp")" ] && echo y )
if [ "$same_rest" != y ] || [ "$same_kept" != y ] || ! registered "$tmp"; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: regrouped for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$N" "$bdir"
"$parity" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
registered "$f" || { printf '%s: did NOT verify — %s is not in the regrouped shape\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s carries the dispatcher and the async side effects.\n' "$N" "$f"
