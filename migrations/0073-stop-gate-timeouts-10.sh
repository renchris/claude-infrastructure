#!/bin/bash
# migration-class: c10
# migration-step: migration 0073 — raise the Stop-hook timeouts of completion-assert.sh, session-continue.sh and boundary-handoff.sh from 5 to 10 s in ~/.claude/settings.json, which every account links to: they were killed at 5 s often enough to lose close-gate verdicts. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0073-stop-gate-timeouts-10.sh --confirm settings.json
# migration-subject: hooks/completion-assert.sh hooks/session-continue.sh hooks/boundary-handoff.sh
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0073-stop-gate-timeouts-10.sh" --verify
#
# ══ 0073 — Stop close-gate timeouts 5 → 10 s ══
# docs/research/startup-hooks-2026-10-18/README.md §5 Wave 6 item 6.8 (§2 rows #32-#35); decision
# packet 39421508c872, approved by the operator 2026-10-20.
#
# WHY. The three close gates run at every Stop. Measured cancels at the 5 s bound were 88 / 85 / 14
# (completion-assert / session-continue / boundary-handoff;
# ~/.claude/autonomy/research/startup-hooks-w6-decisions-2026-10-19/REPORT.md, Round 2 and Re-check).
# A killed gate returns no verdict, so a done-claim or an uncommitted stop goes unchecked. The Stop
# bound delays nothing the operator types; asyncRewake (#32) stays parked until kills remain >= 2% of
# Stops 48 h after this raise.
#
# SAFETY. Edits the ONE shared ~/.claude/settings.json every account links to (0037), backs it up,
# and verifies BY CONTENT that the only change is the timeouts of those three Stop registrations.
# Commands match through cmd_bare (scripts/lib/hook-cmd-bare.jq), so `~/…`, `/bin/bash ~/…` and
# `/usr/bin/env bash ~/…` are one hook. A value already at or above 10 is left alone. Idempotent.
# Revert: restore the printed backup. Takes effect in NEW sessions.
#
# Usage: bash migrations/0073-stop-gate-timeouts-10.sh --dry-run | --check | --verify
#        bash migrations/0073-stop-gate-timeouts-10.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first) · 4 REFUSED, a gate is not registered
# bash 3.2-safe.
set -uo pipefail

N=0073
EVENT='Stop'
# A JSON literal; the "~/" is what settings.json stores (Claude Code expands it).
CMDS='["~/.claude/hooks/completion-assert.sh","~/.claude/hooks/session-continue.sh","~/.claude/hooks/boundary-handoff.sh"]'
TO=10
f="$HOME/.claude/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _d="$(cd "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
REPO="${CC_MIGRATION_REPO:-$(cd "$(dirname "$_src")/.." && pwd)}"
LIB="$REPO/scripts/lib"
command -v jq >/dev/null 2>&1 || { printf '%s: jq required — nothing written\n' "$N" >&2; exit 1; }
[ -f "$LIB/hook-cmd-bare.jq" ] || { printf '%s: normalizer missing at %s/hook-cmd-bare.jq — nothing written\n' "$N" "$LIB" >&2; exit 1; }

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

q() { jq -L "$LIB" --arg e "$EVENT" --argjson cs "$CMDS" --argjson t "$TO" "$@"; }
# shellcheck disable=SC2016  # jq programs, not shell
DEFS='include "hook-cmd-bare"; def mine: ((.command // "") | cmd_bare) as $b | any($cs[]; . == $b);'
# missing: the gates with no Stop registration, one per line (empty when all three are registered).
# shellcheck disable=SC2016
missing() { q -r "$DEFS"' [.hooks[$e][]?.hooks[]? | (.command // "") | cmd_bare] as $have | $cs[] | select(. as $c | ($have | index($c)) == null)' "$1"; }
# shellcheck disable=SC2016
applied() { q -e "$DEFS"' [.hooks[$e][]?.hooks[]? | (.command // "") | cmd_bare] as $have | all($cs[]; . as $c | ($have | index($c)) != null) and ([.hooks[$e][]?.hooks[]? | select(mine)] | all((.timeout // 0) >= $t))' "$1" >/dev/null 2>&1; }
# shellcheck disable=SC2016
target() { q "$DEFS"' .hooks[$e] |= map(.hooks |= map(if mine and ((.timeout // 0) < $t) then .timeout = $t else . end))' "$1"; }
# shellcheck disable=SC2016
norm() { q -S "$DEFS"' .hooks[$e] |= map(.hooks |= map(if mine then del(.timeout) else . end))' "$1"; }

if [ "$mode" = verify ]; then applied "$f"; exit $?; fi

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }
gone="$(missing "$real")" || { printf '%s: could not read the %s registrations of %s — nothing written\n' "$N" "$EVENT" "$real" >&2; exit 1; }
[ -z "$gone" ] || { printf '%s: REFUSED — not registered on %s in %s: %s; nothing raised\n' "$N" "$EVENT" "$real" "$(printf '%s' "$gone" | tr '\n' ' ')" >&2; exit 4; }
if applied "$real"; then printf '%s: already applied — the three %s close gates have timeout >= %s\n' "$N" "$EVENT" "$TO"; exit 0; fi
"$parity" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}
printf '%s: will raise the %s timeouts of completion-assert.sh, session-continue.sh and boundary-handoff.sh to %s s in %s\n' "$N" "$EVENT" "$TO" "$real"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/stop-gate-timeouts-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
if ! target "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# BY CONTENT: with every timeout of the three registrations set aside, the documents are identical.
if [ "$(norm "$real")" != "$(norm "$tmp")" ] || ! applied "$tmp"; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: raised for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$N" "$bdir"
"$parity" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
applied "$f" || { printf '%s: did NOT verify — the three %s close gates are not all at %s s\n' "$N" "$EVENT" "$TO" >&2; exit 1; }
printf '%s: verified — completion-assert.sh, session-continue.sh and boundary-handoff.sh on %s now have timeout %s s.\n' "$N" "$EVENT" "$TO"
