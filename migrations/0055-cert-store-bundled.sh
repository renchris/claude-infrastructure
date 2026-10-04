#!/bin/bash
# migration-class: c10
# migration-step: stop the startup freeze at its source: add "CLAUDE_CODE_CERT_STORE": "bundled" to env in the ONE shared ~/.claude/settings.json, so Claude Code never loads the macOS system CA store on its main thread. Proved first by a login-free temp-config launch whose debug log must read `CA certs: stores=bundled`. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0055-cert-store-bundled.sh --confirm settings.json
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0055-cert-store-bundled.sh" --verify
# migration-conflict: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0055-cert-store-bundled.sh" --conflict
#
# ══ 0055 — CLAUDE_CODE_CERT_STORE=bundled (docs/research/concurrency-scale-2026-10-04/j-startup-hang.md) ══
# Incident 2026-10-04: every `claude` launch froze at ~100 MB / 0% CPU. Five hung samples all sat in
# one std::call_once on the main thread (claude.exe+0x5595xx: SecItemCopyMatching,
# SecTrustSettingsCopyTrustSettings, SecTrustEvaluateWithError), waiting on a stalled secd/trustd
# with no timeout. Claude Code 2.1.284 loads the system CA store there; `bundled` skips it. A/B
# during the stall: bundled reached the API in 1.6 s, the default was SIGKILLed at 65 s.
#
# WHY settings.json AND NOT ONLY THE LAUNCHER. bin/cc-close-attrib exports the same value, but only
# for launches that pass through it. settings.json `env` reaches every launch that loads user
# settings (raw `claude`, the IDE, --resume) and overrides the shell value.
#
# WHY THE PROBE. An unrecognized value is not an error: Claude Code logs one WARN and silently falls
# back to `bundled,system`, which is the freeze. So a typo here would look applied and fix nothing.
# --probe launches the real binary against a temp config dir holding ONLY this env key and reads the
# debug log: it must show `CA certs: stores=bundled` and no `unrecognized CLAUDE_CODE_CERT_STORE`.
# The launch needs no login (it ends at "Not logged in", rc 1) and spends no quota. With
# `--confirm settings.json --probe` the probe runs BEFORE the write, so a FAIL or BLIND writes
# nothing. It is not on the migration-run line: scripts/c10-batch.sh runs that line in a scratch
# HOME where the binary may not resolve, and a BLIND there would redden the whole rehearsal.
#
# BLAST RADIUS: adds ONE key to env. Nothing else changes; backed up first, verified by content.
# A DIFFERENT value already at that key is somebody's decision (a Mac behind a TLS-inspecting or
# local root needs `bundled,system`, or NODE_EXTRA_CA_CERTS=<root.pem> beside `bundled`), so it is
# REFUSED rc 3, never overwritten. Rollback: the printed `cp -p` line. Takes effect in NEW sessions.
#
# Usage: bash migrations/0055-cert-store-bundled.sh --dry-run | --check | --verify | --conflict | --probe
#        bash migrations/0055-cert-store-bundled.sh --confirm settings.json [--probe]
# Env:   CERT_STORE_PROBE_BIN  claude binary for the probe (default: cc-claude-bin, else `claude` on PATH)
# Exit: 0 applied / already applied / preflight ok / probe PASS · 1 failure or probe FAIL (nothing
#       written) · 2 usage · 3 REFUSED: an account settings.json is forked (run 0037 first), a
#       different value is already set, or the probe was BLIND (nothing written)
# shellcheck disable=SC2016  # every single-quoted string below is a jq program; $v is a jq variable
set -uo pipefail

N=0055
KEY=CLAUDE_CODE_CERT_STORE
VAL=bundled
f="$HOME/.claude/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
command -v jq >/dev/null 2>&1 || { printf '%s: jq required — nothing written\n' "$N" >&2; exit 1; }

mode="" run_probe=0
case "${1:-}" in
  --dry-run) mode=dry ;;
  --check) mode=check ;;
  --verify) mode=verify ;;
  --conflict) mode=conflict ;;
  --probe) mode=probe ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '%s: --confirm must name its target: --confirm settings.json\n' "$N" >&2; exit 2; }
             mode=apply
             case "${3:-}" in '') ;; --probe) run_probe=1 ;; *) printf '%s: unknown argument %s after --confirm settings.json (only --probe)\n' "$N" "$3" >&2; exit 2 ;; esac ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '%s: unknown argument %s (use --dry-run, --check, --verify, --conflict, --probe or --confirm settings.json [--probe])\n' "$N" "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '%s: pass --dry-run, --check, --verify, --conflict, --probe or --confirm settings.json [--probe]\n' "$N" >&2; exit 2; }

is_set() { jq -e --arg k "$KEY" --arg v "$VAL" '(.env // {})[$k] == $v' "$1" >/dev/null 2>&1; }
other_value() { jq -r --arg k "$KEY" --arg v "$VAL" '(.env // {})[$k] // empty | select(. != $v) | tostring' "$1" 2>/dev/null; }

# probe <value> — 0 PASS · 1 FAIL · 3 BLIND. Launches the real binary against a temp config dir whose
# settings.json holds only env.$KEY=<value>, with the variable absent from the shell, and reads the
# debug log. Bounded with -k: a launch that does reach the system store can ignore SIGTERM.
probe() {
  local bin="${CERT_STORE_PROBE_BIN:-}" t log
  [ -n "$bin" ] || bin="$("$HOME/.claude/bin/cc-claude-bin" 2>/dev/null | head -1)"
  [ -n "$bin" ] || bin="$(command -v claude 2>/dev/null)"
  [ -n "$bin" ] && [ -x "$bin" ] || { printf '%s: probe BLIND — no claude binary found (set CERT_STORE_PROBE_BIN)\n' "$N" >&2; return 3; }
  command -v timeout >/dev/null 2>&1 || { printf '%s: probe BLIND — `timeout` not on PATH\n' "$N" >&2; return 3; }
  t="$(mktemp -d "${TMPDIR:-/tmp}/cert-store-probe.XXXXXX")" || { printf '%s: probe BLIND — mktemp failed\n' "$N" >&2; return 3; }
  log="$t/debug.log"
  jq -n --arg k "$KEY" --arg v "$1" '{env: {($k): $v}}' > "$t/settings.json"
  ( cd "$t" && env -u "$KEY" CLAUDE_CONFIG_DIR="$t" timeout -k 5 60 "$bin" -p --debug-file "$log" "hi" </dev/null >/dev/null 2>&1 )
  if ! grep -q 'CA certs: stores=' "$log" 2>/dev/null; then
    printf '%s: probe BLIND — %s logged no `CA certs: stores=` line (log kept: %s)\n' "$N" "$bin" "$log" >&2; return 3
  fi
  if grep -q "unrecognized $KEY" "$log" || ! grep -Eq 'CA certs: stores=bundled(, |$)' "$log"; then
    printf '%s: probe FAIL — %s=%s did not select the bundled store alone:\n' "$N" "$KEY" "$1" >&2
    grep -E "CA certs: stores=|unrecognized $KEY" "$log" >&2
    printf '%s: log kept: %s\n' "$N" "$log" >&2; return 1
  fi
  printf '%s: probe PASS — %s: %s\n' "$N" "${bin##*/}" "$(grep -o 'CA certs: stores=[^ ]*' "$log" | head -1)"
  rm -rf "$t"
  return 0
}

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }
other="$(other_value "$real")"

case "$mode" in
  verify)
    is_set "$f" && { printf '%s: live — %s carries env.%s=%s\n' "$N" "$f" "$KEY" "$VAL"; exit 0; }
    printf '%s: NOT live — %s lacks env.%s=%s\n' "$N" "$f" "$KEY" "$VAL" >&2; exit 1 ;;
  conflict)
    [ -n "$other" ] && { printf '%s: overridden — env.%s is %s, not %s\n' "$N" "$KEY" "$other" "$VAL"; exit 0; }
    exit 1 ;;
  probe)
    v="$VAL"; [ -n "$other" ] && v="$other"
    probe "$v"; exit $? ;;
esac

jq -e '(.env // {}) | type == "object"' "$real" >/dev/null 2>&1 \
  || { printf '%s: env is not an object — left unchanged\n' "$N" >&2; exit 1; }
"$parity" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}

if is_set "$real"; then
  printf '%s: already applied — %s carries env.%s=%s\n' "$N" "$real" "$KEY" "$VAL"
  if [ "$run_probe" = 1 ]; then probe "$VAL"; exit $?; fi
  exit 0
fi
if [ -n "$other" ]; then
  printf '%s: REFUSED — env.%s is already %s. That is a deliberate value (a TLS-inspecting or local root needs the system store); nothing written. To take the fix, set it to %s by hand, or keep it and add NODE_EXTRA_CA_CERTS=<root.pem>.\n' "$N" "$KEY" "$other" "$VAL" >&2
  exit 3
fi
printf '%s: will add env.%s=%s to %s\n' "$N" "$KEY" "$VAL" "$real"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: preflight ok — accounts share one file, the edit is well-formed; nothing written\n' "$N"; exit 0 ;;
esac

if [ "$run_probe" = 1 ]; then
  probe "$VAL"; prc=$?
  [ "$prc" -eq 0 ] || { printf '%s: nothing written (probe rc %s)\n' "$N" "$prc" >&2; exit "$prc"; }
fi

bdir="$HOME/.claude/backups/cert-store-bundled-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
EDIT='.env = ((.env // {}) + {($k): $v})'
if ! jq --arg k "$KEY" --arg v "$VAL" "$EDIT" "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# Two comparisons, not one `del(.env[$k])` on each side: a file with NO env object gains `env: {}`
# once the key is removed again, which is not equal to "no env" and would refuse a correct edit.
same_rest=$(jq -n --arg k "$KEY" --slurpfile a "$real" --slurpfile b "$tmp" '(($a[0] | del(.env)) == ($b[0] | del(.env))) and ((($a[0].env // {}) | del(.[$k])) == ($b[0].env | del(.[$k])))')
if [ "$same_rest" != true ] || ! is_set "$tmp"; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: env.%s=%s set. Backup: %s/settings.json (restore: cp -p %s/settings.json %s)\n' "$N" "$KEY" "$VAL" "$bdir" "$bdir" "$real"
"$parity" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with the line above\n' "$N" >&2
is_set "$f" || { printf '%s: did NOT verify through %s\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s carries env.%s=%s. New sessions pick it up.\n' "$N" "$f" "$KEY" "$VAL"
[ "$run_probe" = 1 ] || printf '%s: prove the value against the real binary: bash %s --probe\n' "$N" "$0"
exit 0
