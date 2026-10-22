#!/bin/bash
# migration-class: c10
# migration-step: migration 0076 — refresh the installed copies of the launchd jobs that still exec a `#!` script by path (each tick leaks ~1 KiB of kernel memory until reboot on macOS 15.8.1) from the repo plists that run it through its own interpreter, and reload the loaded ones; launchctl is machine-wide, so this is yours
# migration-run: bash ~/Development/claude-infrastructure/migrations/0076-launchd-explicit-interpreter.sh --confirm launchd
# migration-subject: scripts/hook-interp.py
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0076-launchd-explicit-interpreter.sh" --verify
# migration-batch-hold: manual — reloads LIVE launchd jobs, two of them KeepAlive daemons; launchctl is machine-wide
#
# ══ 0076 — launchd jobs run their `#!` main through its own interpreter ══
# docs/research/kalloc-longterm-2026-10-21/REPORT.md §3 Phase 1, row "Launchd jobs"; the hook half
# of the same fix is 0070.
#
# WHY. Every exec of a `#!` script BY PATH keeps ~1.1 KiB of kernel memory until reboot (~20 GiB
# panics the Mac); `<interpreter> <script>` keeps about 0. 35 of the repo's launchd jobs exec'd their
# main by path on every tick. The repo plists now say `exec /bin/bash "$HOME/.claude/scripts/x.sh"`
# (the script's own shebang interpreter, verbatim), and scripts/hook-shebang-lint.sh holds the tree
# to it at land time. But launchd runs the INSTALLED copy in ~/Library/LaunchAgents and re-reads it
# only on a reload, and install.sh's own copy+reload reaches only part of the fleet: it never copies
# launchd/staged/*.plist (0051/0058/0063/0067 installed those), it skips a job executing at that
# instant, and it does not bounce a KeepAlive daemon unless CC_INSTALL_RESIDENT_RELOAD=1.
#
# CLASS c10, by precedent: README.md puts a launchd plist under c10 until the C10 rescope is
# ratified, and the closest precedent, 0065 (refresh installed plists + reload), is c10 with a
# --confirm gate and a manual batch hold. Nothing here is new behavior for a job: same program,
# same arguments, same $0, only the kernel's `#!` lookup is done by the shell instead.
#
# POPULATION, computed, never listed: every repo plist (launchd/*.plist, launchd/staged/*.plist)
# whose copy exists in ~/Library/LaunchAgents. Per label, judged BY CONTENT through the land gate's
# own predicate (scripts/hook-interp.py lint-plist / lint-args):
#   file   the installed copy execs a `#!` script by path ⇒ install the repo bytes (backup first).
#          A copy that is absent is a job nobody installed: nothing leaks, nothing is written.
#   reload the job is LOADED and the arguments launchd holds (`launchctl print`, the arguments
#          block) still exec by path ⇒ reload it. A job that is not loaded is NEVER bootstrapped:
#          whether a staged job runs is the operator's activation decision, not this migration's.
# A periodic job running a tick is waited for (CC_0076_WAIT_S), else that label exits 75 `busy`
# with its new bytes in place. A KeepAlive daemon is always running, so it is bounced as install.sh
# bounces one (bootout + bootstrap) — except com.claude.compressor-sentinel while its frozen ledger
# is non-empty: it owes those processes a SIGCONT, and install.sh vetoes that bounce for the same
# reason (resident_bounce_vetoed). lead-supervisor already ran through /bin/bash and is untouched.
#
#   0076-launchd-explicit-interpreter.sh [--dry-run | --verify | --confirm launchd]
# Exit: 0 every installed job clean · 1 failure · 2 usage · 75 a job was busy or vetoed (re-run).
# Undo: copy the printed .bak-0076-* file back over ~/Library/LaunchAgents/<label>.plist, then
#       launchctl bootout gui/$(id -u)/<label>; launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/<label>.plist
# The verifier is config-dir invariant (launchd is singular; README.md "per-config-dir loop").
# Seams: CC_0076_LAUNCHCTL · CC_MIGRATION_LA_DIR · CC_MIGRATION_REPO · CC_0076_WAIT_S ·
# CC_0076_POLL_S · CC_SENTINEL_FROZEN_DB · HOME. bash 3.2-safe.
set -uo pipefail

N=0076
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CC_MIGRATION_REPO:-$(cd "$here/.." && pwd)}"
PRED="$REPO/scripts/hook-interp.py"
LC="${CC_0076_LAUNCHCTL:-launchctl}"
LA="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}"
WAIT_S="${CC_0076_WAIT_S:-130}"
POLL_S="${CC_0076_POLL_S:-2}"
DOMAIN="gui/$(id -u)"

say() { printf '%s: %s\n' "$N" "$*"; }
err() { printf '%s: %s\n' "$N" "$*" >&2; }

mode=""
case "${1:-}" in
  ''|--dry-run) mode=dry ;;
  --verify) mode=verify ;;
  --confirm) [ "${2:-}" = launchd ] || { err "--confirm must name its target: --confirm launchd"; exit 2; }
             mode=apply ;;
  *) err "unknown argument $1 (use --dry-run, --verify or --confirm launchd)"; exit 2 ;;
esac
[ -f "$PRED" ] || { err "predicate missing at $PRED — nothing done"; exit 1; }

job_print()   { "$LC" print "$DOMAIN/$1" 2>/dev/null; }
job_loaded()  { job_print "$1" >/dev/null; }
job_running() { job_print "$1" | grep -E '^[[:space:]]*state = running' >/dev/null; }
# The arguments launchd holds for a loaded job, one per line (`launchctl print` lists them as a
# tab-indented block under `arguments = {`, the layout 0065 read its `environment = {` block from).
job_args() {
  job_print "$1" | awk '/^[[:space:]]*arguments = \{[[:space:]]*$/ { f = 1; next }
                        f && /^[[:space:]]*\}[[:space:]]*$/ { exit }
                        f { sub(/^[[:space:]]+/, ""); print }'
}
file_bare()   { ! /usr/bin/env python3 "$PRED" lint-plist "$1" --root "$REPO" >/dev/null 2>&1; }
# rc 0 = the loaded job still execs by path · 1 = clean or not loaded · 2 = loaded, arguments unreadable
loaded_bare() {
  local a
  job_loaded "$1" || return 1
  a="$(job_args "$1")"
  [ -n "$a" ] || return 2
  ! printf '%s\n' "$a" | /usr/bin/env python3 "$PRED" lint-args --root "$REPO" >/dev/null 2>&1
}
# scripts/lib/cc-common.sh plist_is_resident's predicate.
resident() {
  case "$(/usr/libexec/PlistBuddy -c 'Print :KeepAlive' "$1" 2>/dev/null | tr -d '[:space:]')" in
    true|1) return 0 ;; *) return 1 ;;
  esac
}
# install.sh resident_bounce_vetoed, same ledger, same reason.
vetoed() {
  local db="${CC_SENTINEL_FROZEN_DB:-$HOME/.claude/logs/compressor-sentinel-frozen.tsv}"
  [ "$1" = com.claude.compressor-sentinel ] && [ -s "$db" ]
}
wait_idle() {
  local waited=0
  while job_running "$1"; do
    [ "$waited" -ge "$WAIT_S" ] && return 1
    sleep "$POLL_S"; waited=$((waited + POLL_S))
  done
  return 0
}

# The population: "label<TAB>repo plist" for every repo job with an installed copy.
population() {
  local src label
  for src in "$REPO"/launchd/*.plist "$REPO"/launchd/staged/*.plist; do
    [ -f "$src" ] || continue
    label="$(basename "$src" .plist)"
    [ -f "$LA/$label.plist" ] && printf '%s\t%s\n' "$label" "$src"
  done
}
pop="$(population)"
[ -n "$pop" ] || { say "no repo launchd job is installed in $LA — nothing to do"; exit 0; }

if [ "$mode" = verify ]; then
  rc=0
  # The loops read fd 3, so nothing inside them (launchctl, python) can swallow the list on stdin.
  while IFS=$'\t' read -r label src <&3; do
    if file_bare "$LA/$label.plist"; then err "NOT live — $LA/$label.plist still execs a #! script by path"; rc=1; fi
    loaded_bare "$label"; r=$?
    if [ "$r" -eq 0 ]; then err "NOT live — the loaded $label still execs a #! script by path (reload it)"; rc=1
    elif [ "$r" -eq 2 ]; then err "no verdict — $label is loaded but launchctl print shows no arguments"; rc=1; fi
  done 3<<< "$pop"
  [ "$rc" -eq 0 ] && say "live — every installed launchd job runs its #! main through its interpreter"
  exit "$rc"
fi

# Plan, shared by dry run and apply: "label<TAB>src<TAB>file|-<TAB>reload|-".
plan=""
while IFS=$'\t' read -r label src <&3; do
  f=-; l=-
  file_bare "$LA/$label.plist" && f="file"
  loaded_bare "$label"; r=$?
  if [ "$r" -eq 0 ] || { [ "$f" = file ] && [ "$r" -ne 1 ]; }; then l=reload; fi
  [ "$f" = - ] && [ "$l" = - ] && continue
  if file_bare "$src" || ! plutil -lint -s "$src" >/dev/null 2>&1; then
    err "$src itself fails the lint or plutil — the wiring commit did not land intact; refusing"; exit 1
  fi
  plan="${plan:+$plan
}$label	$src	$f	$l"
done 3<<< "$pop"
[ -n "$plan" ] || { say "already applied — no installed launchd job execs a #! script by path"; exit 0; }

if [ "$mode" = dry ]; then
  while IFS=$'\t' read -r label src f l <&3; do
    if [ "$f" = file ]; then act="install $src over $LA/$label.plist"; else act="keep $LA/$label.plist"; fi
    if [ "$l" = reload ]; then act="$act, then reload $label"; else act="$act ($label is not loaded: no reload)"; fi
    say "would $act"
  done 3<<< "$plan"
  say "dry run — nothing changed; act with: bash $REPO/migrations/$N-launchd-explicit-interpreter.sh --confirm launchd"
  exit 0
fi

# One label end to end. rc 0 done · 1 failure · 75 busy or vetoed.
apply_one() {
  local label="$1" src="$2" f="$3" l="$4" dst="$LA/$1.plist" bak="" tmp i
  if [ "$l" = reload ]; then
    if resident "$src"; then
      if vetoed "$label"; then
        say "vetoed: re-run — $label owes SIGCONT to frozen pid(s) (install.sh's veto); nothing changed"
        return 75
      fi
    elif ! wait_idle "$label"; then
      say "busy: re-run — $label was running at every poll for ${WAIT_S}s; nothing changed"
      return 75
    fi
  fi
  if [ "$f" = file ]; then
    bak="$dst.bak-$N-$(date +%Y%m%d%H%M%S)"
    cp -p "$dst" "$bak" || { err "backup of $dst FAILED — $label left as it was"; return 1; }
    tmp="$LA/.$label.plist.tmp.$$"
    if ! { cp "$src" "$tmp" && mv -f "$tmp" "$dst"; }; then
      rm -f "$tmp"; err "install of $dst FAILED — $label left as it was (backup $bak)"; return 1
    fi
    cmp -s "$src" "$dst" || { err "$dst does not match $src after the install"; return 1; }
    say "installed $src -> $dst (backup $bak)"
  fi
  [ "$l" = reload ] || return 0
  "$LC" bootout "$DOMAIN/$label" 2>/dev/null || { err "bootout of $label FAILED — the new bytes apply at its next load"; return 1; }
  i=0
  while job_loaded "$label" && [ "$i" -lt 20 ]; do sleep 1; i=$((i + 1)); done
  if job_loaded "$label"; then err "$label still loaded 20 s after bootout — not bootstrapped; re-run"; return 1; fi
  if ! "$LC" bootstrap "$DOMAIN" "$dst"; then
    err "bootstrap of $label FAILED — it is NOT loaded; load it: launchctl bootstrap $DOMAIN $dst"
    return 1
  fi
  # Read back through a different call than the one that made the change.
  loaded_bare "$label"; r=$?
  case "$r" in
    1) say "$label reloaded; launchd now holds the interpreter-led arguments" ;;
    0) err "$label reloaded but launchd still holds a by-path exec"; return 1 ;;
    *) err "$label reloaded but launchctl print shows no arguments to check"; return 1 ;;
  esac
  return 0
}

mkdir -p "$LA" || { err "mkdir $LA FAILED"; exit 1; }
worst=0
while IFS=$'\t' read -r label src f l <&3; do
  apply_one "$label" "$src" "$f" "$l"; rc=$?
  if [ "$rc" -eq 1 ] || { [ "$rc" -eq 75 ] && [ "$worst" -eq 0 ]; }; then worst=$rc; fi
done 3<<< "$plan"
[ "$worst" -eq 0 ] && say "done — every installed launchd job runs its #! main through its interpreter"
exit "$worst"
