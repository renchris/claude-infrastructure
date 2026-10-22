#!/bin/bash
# migration-class: c10
# migration-step: migration 0068 — raise the SessionStart dispatcher registration (hooks/session-start-dispatch.sh) timeout from 12 to 20 s in ~/.claude/settings.json, which every account links to, so a dispatcher that prints by its 9 s deadline under harness lag is not cancelled (6 whole-output losses per 2 days). It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0068-ssd-timeout-20.sh --confirm settings.json
# migration-subject: hooks/session-start-dispatch.sh
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0068-ssd-timeout-20.sh" --verify
#
# ══ 0068 — SessionStart dispatcher registration timeout 12 → 20 s ══
# docs/research/startup-hooks-2026-10-18/README.md §5 Wave 6 item 6.1 (§2 row #9).
#
# WHY. The dispatcher prints by its own 9 s deadline (Wave 2) but the harness lags up to ~25 s under load,
# and a cancelled SessionStart hook's stdout is discarded whole: the board, the recycle packet and every
# notice (6 such losses per 2 days, docs/research/startup-hooks-2026-10-18/A3-dispatcher.md §2.6). 20 s
# narrows that window at 0 ms cost on a healthy start (the hook exits as soon as it prints). It is a
# backstop paired with the cost work (1.1, Wave 2), not the fix (§6: "do not simply raise the timeout").
# 0056 cannot re-fire for this: its registered() ignores the timeout.
#
# SAFETY. Edits the ONE shared ~/.claude/settings.json every account links to (0037), backs it up,
# and verifies BY CONTENT that the only change is the timeout of that one registration. A value
# already at or above 20 is left alone (an operator may have raised it further). Idempotent.
# Revert: restore the printed backup. Takes effect in NEW sessions.
#
# Usage: bash migrations/0068-ssd-timeout-20.sh --dry-run | --check | --verify
#        bash migrations/0068-ssd-timeout-20.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first) · 4 REFUSED, not registered
# bash 3.2-safe.
set -uo pipefail

N=0068
EVENT='SessionStart'
# shellcheck disable=SC2088  # the literal "~/" is what settings.json stores; Claude Code expands it
CMD='~/.claude/hooks/session-start-dispatch.sh'
TO=20
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

# cmd_bare: a hook command may carry its interpreter (/bin/bash ~/.claude/hooks/x.sh) since 0070.
# shellcheck disable=SC2016  # jq programs, not shell
present() { jq -e --arg e "$EVENT" --arg c "$CMD" 'def cmd_bare: sub("^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"; ""); [.hooks[$e][]?.hooks[]? | select(((.command // "") | cmd_bare) == $c)] | length > 0' "$1" >/dev/null 2>&1; }
# shellcheck disable=SC2016
applied() { jq -e --arg e "$EVENT" --arg c "$CMD" --argjson t "$TO" 'def cmd_bare: sub("^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"; ""); [.hooks[$e][]?.hooks[]? | select(((.command // "") | cmd_bare) == $c)] as $h | ($h | length > 0) and ($h | all((.timeout // 0) >= $t))' "$1" >/dev/null 2>&1; }
# shellcheck disable=SC2016
target() { jq --arg e "$EVENT" --arg c "$CMD" --argjson t "$TO" 'def cmd_bare: sub("^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"; ""); .hooks[$e] |= map(.hooks |= map(if ((.command // "") | cmd_bare) == $c and ((.timeout // 0) < $t) then .timeout = $t else . end))' "$1"; }

if [ "$mode" = verify ]; then applied "$f"; exit $?; fi

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }
present "$real" || { printf '%s: REFUSED — %s is not registered on %s in %s; nothing to raise\n' "$N" "$CMD" "$EVENT" "$real" >&2; exit 4; }
if applied "$real"; then printf '%s: already applied — %s on %s has timeout >= %s\n' "$N" "$CMD" "$EVENT" "$TO"; exit 0; fi
"${parity_cmd[@]}" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}
printf '%s: will raise the %s timeout of %s to %s s in %s\n' "$N" "$EVENT" "$CMD" "$TO" "$real"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/ssd-timeout-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
if ! target "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# BY CONTENT: with every timeout of the one registration set aside, the documents are identical.
# shellcheck disable=SC2016
norm='def cmd_bare: sub("^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"; ""); .hooks[$e] |= map(.hooks |= map(if ((.command // "") | cmd_bare) == $c then del(.timeout) else . end))'
if [ "$(jq -S --arg e "$EVENT" --arg c "$CMD" "$norm" "$real")" != "$(jq -S --arg e "$EVENT" --arg c "$CMD" "$norm" "$tmp")" ] || ! applied "$tmp"; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: raised for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$N" "$bdir"
"${parity_cmd[@]}" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
applied "$f" || { printf '%s: did NOT verify — %s is not at %s s\n' "$N" "$CMD" "$TO" >&2; exit 1; }
printf '%s: verified — %s on %s now has timeout %s s.\n' "$N" "$CMD" "$EVENT" "$TO"
