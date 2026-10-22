#!/bin/bash
# migration-class: c10
# migration-step: migration 0072 — retire the async SessionStart registration of hooks/pre-session-validate.sh from ~/.claude/settings.json, which every account links to: it validates ~/.claude-versions/current (the claude-prev track), which no fleet session launches, and all 588 of its "broken" flags were load timeouts. The hook file stays for claude-prev. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0072-retire-pre-session-validate.sh --confirm settings.json
# migration-subject: hooks/pre-session-validate.sh
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0072-retire-pre-session-validate.sh" --verify
# migration-batch-hold: manual — applied alone like 0068/0069 (decision packet f27d3dcf0473, round 2); run its migration-run line by itself
#
# ══ 0072 — retire the pre-session-validate SessionStart registration ══
# docs/research/startup-hooks-2026-10-18/README.md §5 Wave 6 item 6.6a; decision packet f27d3dcf0473.
#
# WHY. pre-session-validate.sh guards ~/.claude-versions/current (2.1.114), the binary `claude-prev`
# runs; fleet sessions launch the pinned binary and never read it. Every one of its 588 "broken" flags
# was a probe timed out under load, and cc-upgrade's activation already runs per-model `--print` checks
# on the fleet binary. So the registration costs a start-time fork and buys nothing. Its model guard
# (strip a saved Fable default) was fixed to write through the shared-file symlink in the same wave.
#
# SAFETY. Edits the ONE shared ~/.claude/settings.json every account links to (0037), never an account
# symlink; backs it up first; matches the command in both spellings through cmd_bare
# (scripts/lib/hook-cmd-bare.jq — bare `~/…` and `/bin/bash ~/…`); removes only that hook (its group
# keeps its other hooks; a group left empty is dropped); and verifies BY CONTENT that nothing else in
# the file changed. Idempotent: a second run says "already applied" and writes nothing. Refuses a
# forked fleet. Revert: restore the printed backup. Takes effect in NEW sessions.
#
# Usage: bash migrations/0072-retire-pre-session-validate.sh --dry-run | --check | --verify
#        bash migrations/0072-retire-pre-session-validate.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first)
# bash 3.2-safe.
set -uo pipefail

N=0072
EVENT='SessionStart'
# shellcheck disable=SC2088  # the literal "~/" is what settings.json stores; Claude Code expands it
CMD='~/.claude/hooks/pre-session-validate.sh'
f="$HOME/.claude/settings.json"
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

# cmd_bare mirrors scripts/lib/hook-cmd-bare.jq (inlined, as 0068-0071 do, so the migration runs from any cwd).
# shellcheck disable=SC2016  # jq programs, not shell
BARE='def cmd_bare: sub("^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"; ""); def hit: ((.command // "") | cmd_bare) == $c;'
# applied: the file parses and no SessionStart hook is the retired command (a missing file is NOT applied).
# shellcheck disable=SC2016
applied() { jq -e --arg e "$EVENT" --arg c "$CMD" "$BARE"' [.hooks[$e][]?.hooks[]? | select(hit)] | length == 0' "$1" >/dev/null 2>&1; }
# target: drop the hook; drop a group only when this edit emptied it.
# shellcheck disable=SC2016
target() { jq --arg e "$EVENT" --arg c "$CMD" "$BARE"' if .hooks[$e] then .hooks[$e] |= map(if any(.hooks[]?; hit) then (.hooks |= map(select(hit | not))) | (if (.hooks | length) == 0 then empty else . end) else . end) else . end' "$1"; }
# rest: everything the edit must leave alone — the file minus .hooks, and every hook of every event
# except the retired one, in order.
# shellcheck disable=SC2016
rest() { jq -S --arg e "$EVENT" --arg c "$CMD" "$BARE"' [del(.hooks), [(.hooks // {}) | to_entries[] | .key as $k | .value[]? | {k: $k, m: (.matcher // null), h: [.hooks[]? | select(($k == $e and hit) | not)]}] | map(select(.h != [] or .k != $e))]' "$1"; }

if [ "$mode" = verify ]; then applied "$f"; exit $?; fi

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }
if applied "$real"; then printf '%s: already applied — %s is not registered on %s\n' "$N" "$CMD" "$EVENT"; exit 0; fi
"${parity_cmd[@]}" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}
printf '%s: will remove the %s registration of %s from %s\n' "$N" "$EVENT" "$CMD" "$real"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/retire-pre-session-validate-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
if ! target "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# BY CONTENT: with the retired hook set aside, the documents are identical, and the hook is gone.
if [ "$(rest "$real")" != "$(rest "$tmp")" ] || ! applied "$tmp"; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: retired for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$N" "$bdir"
"${parity_cmd[@]}" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
applied "$f" || { printf '%s: did NOT verify — %s is still registered on %s\n' "$N" "$CMD" "$EVENT" >&2; exit 1; }
printf '%s: verified — %s is no longer registered on %s.\n' "$N" "$CMD" "$EVENT"
