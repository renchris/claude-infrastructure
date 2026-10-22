#!/bin/bash
# migration-class: c10
# migration-step: migration 0071 — register a FileChanged watch on ~/.claude/state/startup-health/alerts in ~/.claude/settings.json, which every account links to, so a startup fault written there for a session reaches that session's pane within about a second, idle or not, as a 5-second toast plus a tab bell and a kitty desktop notification (0 tokens; probed on 2.1.293). It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0071-filechanged-startup-alerts.sh --confirm settings.json
# migration-subject: hooks/startup-alert-notify.sh
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0071-filechanged-startup-alerts.sh" --verify
#
# ══ 0071 — FileChanged push for startup faults (idle panes) ══
# docs/research/startup-hooks-2026-10-18/README.md §5 Wave 6 item 6.2 (§2 row #13a); design in
# gap-G2.md §4 G2-2; probe in probes/probeA-RESULT.md (2.1.293: (a)-(f) and (h) pass).
#
# WHAT. Appends two groups to hooks.FileChanged:
#   A  matcher = the ABSOLUTE alerts dir, hook `true`. An absolute matcher arms the watch at setup,
#      before any SessionStart hook runs, so no hook has to survive for the watch to exist. It is
#      regex-tested against the changed file's basename, so it never dispatches (probe A: 0 runs).
#   B  no matcher, `/bin/bash ~/.claude/hooks/startup-alert-notify.sh`, timeout 5. Runs for every
#      watched path; the hook acts only on <alerts>/<its own session id>.
# The matcher is written expanded ($HOME/…): a `~/` matcher is not absolute and would be joined to
# the session's cwd. The alerts dir is created so the watch has a target. Existing FileChanged groups
# (0017's file-changed.sh pair) are left exactly as they are.
#
# SAFETY. Edits the ONE shared ~/.claude/settings.json every account links to (0037), backs it up,
# and verifies BY CONTENT that with these two groups removed the document is unchanged. A group
# already present is not added twice. Idempotent. Revert: restore the printed backup. Takes effect
# in NEW sessions. Until a writer exists (README #11 late collector, #8 sentinel: gap-G2 G2-3)
# nothing is written to the dir and the cost is one idle watch per session.
#
# Usage: bash migrations/0071-filechanged-startup-alerts.sh --dry-run | --check | --verify
#        bash migrations/0071-filechanged-startup-alerts.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first)
# bash 3.2-safe.
set -uo pipefail

N=0071
DIR="$HOME/.claude/state/startup-health/alerts"
# shellcheck disable=SC2088  # the literal "~/" is what settings.json stores; Claude Code expands it
CMD='~/.claude/hooks/startup-alert-notify.sh'
TO=5
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
DEFS='def cmd_bare: sub("^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"; "");
def isA: (.matcher // "") == $d and ([.hooks[]? | .command] == ["true"]);
def isB: ((.matcher // "") == "") and ([.hooks[]? | (.command // "") | cmd_bare] == [$c]);
def hasA: [.hooks.FileChanged[]? | select(isA)] | length > 0;
def hasB: [.hooks.FileChanged[]? | select(isB)] | length > 0;'
jqd() { jq --arg d "$DIR" --arg c "$CMD" --argjson t "$TO" "$@"; }
applied() { jqd -e "$DEFS hasA and hasB" "$1" >/dev/null 2>&1; }
target() {
  # shellcheck disable=SC2016
  jqd "$DEFS"' .hooks.FileChanged = ((.hooks.FileChanged // [])
      + (if hasA then [] else [{matcher: $d, hooks: [{type: "command", command: "true", timeout: $t}]}] end)
      + (if hasB then [] else [{hooks: [{type: "command", command: ("/bin/bash " + $c), timeout: $t}]}] end))' "$1"
}
# shellcheck disable=SC2016
norm() { jqd -S "$DEFS"' .hooks.FileChanged |= ((. // []) | map(select((isA or isB) | not))) | if .hooks.FileChanged == [] then del(.hooks.FileChanged) else . end' "$1"; }

if [ "$mode" = verify ]; then applied "$f"; exit $?; fi

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }
if applied "$real"; then printf '%s: already applied — FileChanged watches %s and runs %s\n' "$N" "$DIR" "$CMD"; exit 0; fi
"${parity_cmd[@]}" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}
printf '%s: will register FileChanged on %s (arm) and %s (notifier) in %s\n' "$N" "$DIR" "$CMD" "$real"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/filechanged-alerts-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
if ! target "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# BY CONTENT: with the two groups set aside, the documents are identical.
if [ "$(norm "$real")" != "$(norm "$tmp")" ] || ! applied "$tmp"; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mkdir -p "$DIR" || { rm -f "$tmp"; printf '%s: could not create %s — nothing written\n' "$N" "$DIR" >&2; exit 1; }
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: registered for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$N" "$bdir"
"${parity_cmd[@]}" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
applied "$f" || { printf '%s: did NOT verify — FileChanged on %s is not registered\n' "$N" "$DIR" >&2; exit 1; }
printf '%s: verified — FileChanged arms %s and runs %s.\n' "$N" "$DIR" "$CMD"
