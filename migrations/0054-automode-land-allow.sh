#!/bin/bash
# migration-class: c10
# migration-step: let auto-mode agents run the sanctioned commit + land line without a hand-off: add Bash(git commit -m:*), Bash(bash scripts/ship-land.sh:*) and Bash(fnm exec --using=22 bash scripts/ship-land.sh:*) to permissions.allow in the ONE shared ~/.claude/settings.json, then prove it live with scripts/automode-land-probe.sh (the land line runs; a hand push and a --no-verify commit stay gated). It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0054-automode-land-allow.sh --confirm settings.json
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0054-automode-land-allow.sh" --verify
#
# ══ 0054 — the land line on the allow list (docs/research/automode-land-allow-2026-10-03.md) ═════
# Incident 2026-10-03 (reso, auto mode): `git add <file> && git commit -m "…" && fnm exec --using=22
# bash scripts/ship-land.sh` was DENIED by the classifier as [Modify Shared Resources]; the operator
# ran the identical line with `!` and it landed. Operator ruling: agents run what does not genuinely
# need the user's permission. Two of its three parts had no allow rule (`git commit`, the fnm-wrapped
# land script), and one uncovered part sends the WHOLE line to the classifier.
#
# Measured on 2.1.284 (live probe, a classifier fixture that blocks every land and commit): an allow
# rule resolves BEFORE the classifier, server-side included, so these three rules make the line
# deterministic. None is dropped by auto mode: `bash` is dropped only in bare / `:*` / flag-tail form.
#
# BLAST RADIUS: only ADDS three strings to permissions.allow. Nothing removed or reordered; ask and
# deny are untouched, so `git push` stays an ask (an allow rule cannot beat it) and force-push stays
# denied. validate-bash.sh still denies `git commit --no-verify` / `-n` and shared-checkout commits
# (hooks run before rules). The land-script rules trust whatever file sits at scripts/ship-land.sh,
# exactly as the existing Bash(scripts/ship-land.sh:*) already does. Backed up first, verified by
# content. Rollback: the printed `cp -p` line. Takes effect in NEW sessions.
#
# Usage: bash migrations/0054-automode-land-allow.sh --dry-run | --check | --verify
#        bash migrations/0054-automode-land-allow.sh --confirm settings.json [--probe]
# --probe also runs the behavioral proof (three headless sessions, ~$1 of quota). It is NOT on the
# migration-run line on purpose: scripts/c10-batch.sh runs that line verbatim, including in its
# scratch-HOME --check rehearsal, where a headless session has no login and would read BLIND.
# Exit: 0 applied / already applied / preflight ok / probe PASS · 1 failure (nothing written, or the
#       probe FAILED after the write — restore line printed) · 2 usage · 3 REFUSED, an account
#       settings.json is forked (run 0037 first), or the probe was BLIND
# shellcheck disable=SC2016  # every single-quoted string below is a jq program; $a/$r1 are jq variables
set -uo pipefail

N=0054
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
f="$HOME/.claude/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
probe="$here/../scripts/automode-land-probe.sh"
command -v jq >/dev/null 2>&1 || { printf '%s: jq required — nothing written\n' "$N" >&2; exit 1; }

mode="" run_probe=0
case "${1:-}" in
  --dry-run) mode=dry ;;
  --check) mode=check ;;
  --verify) mode=verify ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '%s: --confirm must name its target: --confirm settings.json\n' "$N" >&2; exit 2; }
             mode=apply
             case "${3:-}" in '') ;; --probe) run_probe=1 ;; *) printf '%s: unknown argument %s after --confirm settings.json (only --probe)\n' "$N" "$3" >&2; exit 2 ;; esac ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '%s: unknown argument %s (use --dry-run, --check, --verify or --confirm settings.json [--probe])\n' "$N" "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '%s: pass --dry-run, --check, --verify or --confirm settings.json [--probe]\n' "$N" >&2; exit 2; }

R1='Bash(git commit -m:*)'
R2='Bash(bash scripts/ship-land.sh:*)'
R3='Bash(fnm exec --using=22 bash scripts/ship-land.sh:*)'
applied='(.permissions.allow // []) as $a | ($a | index($r1)) != null and ($a | index($r2)) != null and ($a | index($r3)) != null'
has_rules() { jq -e --arg r1 "$R1" --arg r2 "$R2" --arg r3 "$R3" "$applied" "$1" >/dev/null 2>&1; }

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }

if [ "$mode" = verify ]; then
  has_rules "$f" && { printf '%s: live — %s carries all three land-line rules\n' "$N" "$f"; exit 0; }
  printf '%s: NOT live — %s lacks one or more of: %s  %s  %s\n' "$N" "$f" "$R1" "$R2" "$R3" >&2; exit 1
fi

jq -e '(.permissions // {}) | (.allow // []) | type == "array"' "$real" >/dev/null 2>&1 \
  || { printf '%s: permissions.allow is not an array — left unchanged\n' "$N" >&2; exit 1; }
"$parity" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}

do_probe() {
  [ "$run_probe" = 1 ] || return 0
  printf '%s: proving it live (three headless auto-mode sessions in a scratch repo, ~1 min):\n' "$N"
  bash "$probe"; local prc=$?
  case $prc in
    0) return 0 ;;
    1) printf '%s: probe FAILED — the rules are written but a control did not hold. Restore: cp -p %s %s\n' "$N" "${bdir:-<no backup this run>}/settings.json" "$real" >&2; exit 1 ;;
    *) printf '%s: probe BLIND (rc %s) — the rules are written; no behavioral verdict. Re-run: bash %s\n' "$N" "$prc" "$probe" >&2; exit 3 ;;
  esac
}

if has_rules "$real"; then
  printf '%s: already applied — %s carries all three land-line rules\n' "$N" "$real"
  [ "$mode" = apply ] && do_probe
  exit 0
fi
printf '%s: will add to permissions.allow in %s: %s  %s  %s\n' "$N" "$real" "$R1" "$R2" "$R3"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: preflight ok — accounts share one file, the edit is well-formed; nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/automode-land-allow-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
EDIT='.permissions = ((.permissions // {}) | .allow = ((.allow // []) + ([$r1, $r2, $r3] - (.allow // []))))'
if ! jq --arg r1 "$R1" --arg r2 "$R2" --arg r3 "$R3" "$EDIT" "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
same_rest=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" '($a[0] | del(.permissions.allow)) == ($b[0] | del(.permissions.allow))')
kept=$(jq -n --slurpfile a "$real" --slurpfile b "$tmp" '(($a[0].permissions.allow // []) - $b[0].permissions.allow) == []')
if [ "$same_rest" != true ] || [ "$kept" != true ] || ! has_rules "$tmp"; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: land line allowed. Backup: %s/settings.json (restore: cp -p %s/settings.json %s)\n' "$N" "$bdir" "$bdir" "$real"
"$parity" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with the line above\n' "$N" >&2
has_rules "$f" || { printf '%s: did NOT verify through %s\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s carries all three rules.\n' "$N" "$f"
[ "$run_probe" = 1 ] || printf '%s: prove it live in auto mode: bash %s\n' "$N" "$probe"
do_probe
exit 0
