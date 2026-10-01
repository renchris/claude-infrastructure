#!/bin/bash
# migration-class: c10
# migration-step: register hooks/read-before-write-parity.sh as a PreToolUse hook (its own "Write|Edit|MultiEdit" entry) in ~/.claude/settings.json, which every account links to since 0037 — so ALL accounts at once. It refuses a write to an existing file the session never Read, the native guard Claude Code 2.1.284 no longer applies to opus-5-5 / sonnet-5-5. It refuses to write unless cc-settings-parity reports every account linked and the LIVE hook exists. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0047-read-before-write-parity-registration.sh --confirm settings.json
# migration-subject: hooks/read-before-write-parity.sh
# migration-verify: "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1 && jq -e '[.hooks.PreToolUse[]? | select(.matcher == "Write|Edit|MultiEdit") | .hooks[]?.command] | any(. == "~/.claude/hooks/read-before-write-parity.sh")' "$HOME/.claude/settings.json" >/dev/null
#
# The verifier is config-dir-INVARIANT (as 0036-0041): one shared file, one answer from every dir.
#
# ══ 0047 — the read-before-write guard, restored for the models that lost it (backlog 504d0bc2fe50) ═
# CLAUDE.md's "INTEGRATE, never overwrite" rule had a mechanical backstop: the binary's own
# "File has not been read yet" refusal. 2.1.284 applies it only to 10 legacy model ids; on
# claude-opus-5-5 and claude-sonnet-5-5 a Write to an existing never-read file succeeds (measured
# 2026-09-30, docs/research/c10-staged-residuals-2026-10.md § read-before-write). backup-before-
# write.sh backs up and warns but has never refused. The shim (hooks/lib/read-before-write-parity.sh,
# 35-case suite) refuses exactly that call and allows every case it cannot prove.
#
# WHY ITS OWN ENTRY. The existing "Write|Edit|MultiEdit" chains are mirrored elsewhere; a separate
# group appended at the end touches none of them and leaves PreToolUse[0] (0024's unit-gate slot)
# alone. Hooks in different groups run in parallel and any deny wins, so order does not matter.
#
# SAFETY. Edits the REAL shared file once (README rule 7), backs it up, verifies BY CONTENT that the
# only change is the appended entry, and reads the effect back through the verifier. Idempotent.
# Revert: delete the entry, set CC_RBW=off in the environment, or restore the printed backup.
# Takes effect in NEW sessions.
#
# Usage: bash migrations/0047-read-before-write-parity-registration.sh --dry-run
#        bash migrations/0047-read-before-write-parity-registration.sh --check    # preflight, writes nothing
#        bash migrations/0047-read-before-write-parity-registration.sh --verify   # is the effect live?
#        bash migrations/0047-read-before-write-parity-registration.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first) · 4 REFUSED, live hook absent
# bash 3.2-safe.
set -uo pipefail

N=0047
# shellcheck disable=SC2088  # the literal "~/" is what settings.json stores; Claude Code expands it
CMD='~/.claude/hooks/read-before-write-parity.sh'
MATCHER='Write|Edit|MultiEdit'
f="$HOME/.claude/settings.json"
hook="$HOME/.claude/hooks/read-before-write-parity.sh"
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
    '[.hooks.PreToolUse[]? | select(.matcher == $m) | .hooks[]?.command] | any(. == $c)' "$1" >/dev/null 2>&1
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
[ -f "$hook" ] || {
  printf '%s: REFUSED — the live hook %s does not exist yet. Converge first: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' "$N" "$hook" >&2
  exit 4
}

ENTRY=$(jq -nc --arg c "$CMD" --arg m "$MATCHER" '{matcher:$m,hooks:[{type:"command",command:$c,timeout:10}]}')
printf '%s: will append to %s .hooks.PreToolUse: %s\n' "$N" "$real" "$ENTRY"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/read-before-write-parity-$N-$(date +%Y%m%d%H%M%S)"
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
"$parity" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
registered "$f" || { printf '%s: did NOT verify — %s lacks the entry\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s carries the hook.\n' "$N" "$f"
