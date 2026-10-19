#!/bin/bash
# migration-class: c10
# migration-step: migration 0070 — run every hook command and the status line through an explicit interpreter (/bin/bash ~/.claude/hooks/x.sh) in the settings.json of all five config dirs, because each bare `#!` exec leaks 1 KiB of kernel memory on macOS 15.7.9 and that leak panicked the machine on 2026-10-18. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0070-hook-explicit-interpreter.sh --confirm settings.json
# migration-subject: scripts/hook-interp.py
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0070-hook-explicit-interpreter.sh" --verify
#
# ══ 0070 — hook commands and the status line name their interpreter ══
# docs/research/panic-2026-10-18-zone-map-shebang-leak.md, Answer §1-2 and improvement 1.
#
# WHY. On macOS 15.7.9 every execve() of a `#!` script leaves one 1 KiB element in data.kalloc.1024
# that outlives the process (+0.94/exec measured on-box); `/bin/bash script` leaves about 0. The zone
# reached its ~20 GiB ceiling and panicked the kernel on 2026-10-18. 100 of the 102 hook commands in
# the shared settings.json, and the status line, run as bare `#!` paths, ~20 of them on every Bash
# tool call.
#
# WHAT. scripts/hook-interp.py prefixes each such command with its script's own shebang interpreter,
# verbatim: `~/.claude/hooks/x.sh arg` → `/bin/bash ~/.claude/hooks/x.sh arg`, `#!/usr/bin/env bash`
# → `/usr/bin/env bash …` (bash still resolves on the hook's own PATH). `~` and `$HOME` expand exactly
# as before, in the shell Claude Code runs the command through. Matchers, `if` filters, timeouts,
# async flags and order are untouched; mcpServers are not hooks and are not read.
#
# SAFETY. Every config dir's settings.json is resolved to its real file (they are symlinks to one
# shared file since 0037) and each real file is rewritten once, in place, so the links survive. Each
# is backed up first and verified BY CONTENT: with cmd_bare (scripts/lib/hook-cmd-bare.jq) applied to
# every command, old and new are identical, and the new file has no bare `#!` command left.
# Idempotent: an already-prefixed command is not a `#!` path. Readers that match hook commands by
# string compare through cmd_bare, so they see one hook in either spelling. Revert: restore the
# printed backup. Takes effect in NEW sessions (and the status line on its next redraw).
#
# Usage: bash migrations/0070-hook-explicit-interpreter.sh --dry-run | --check | --verify
#        bash migrations/0070-hook-explicit-interpreter.sh --confirm settings.json
# Seams: CC_HOOK_INTERP_DIRS (colon-separated config dirs), CC_MIGRATION_REPO (checkout holding
# scripts/hook-interp.py), CC_HOOK_INTERP_BACKUP_ROOT.
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage
# bash 3.2-safe.
set -uo pipefail

N=0070
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _d="$(cd "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
REPO="${CC_MIGRATION_REPO:-$(cd "$(dirname "$_src")/.." && pwd)}"
PRED="$REPO/scripts/hook-interp.py"
LIB="$REPO/scripts/lib"
DIRS="${CC_HOOK_INTERP_DIRS:-$HOME/.claude:$HOME/.claude-next:$HOME/.claude-secondary:$HOME/.claude-tertiary:$HOME/.claude-quaternary}"
BROOT="${CC_HOOK_INTERP_BACKUP_ROOT:-$HOME/.claude/backups}"

say() { printf '%s: %s\n' "$N" "$*"; }
die() { printf '%s: %s\n' "$N" "$1" >&2; exit "${2:-1}"; }
command -v jq >/dev/null 2>&1 || die "jq required — nothing written"
[ -f "$PRED" ] || die "predicate missing at $PRED — nothing written"
[ -f "$LIB/hook-cmd-bare.jq" ] || die "normalizer missing at $LIB/hook-cmd-bare.jq — nothing written"

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --check) mode=check ;;
  --verify) mode=verify ;;
  --confirm) [ "${2:-}" = "settings.json" ] || die "--confirm must name its target: --confirm settings.json" 2; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) die "unknown argument $1 (use --dry-run, --check, --verify or --confirm settings.json)" 2 ;;
esac
[ -n "$mode" ] || die "pass --dry-run, --check, --verify or --confirm settings.json" 2

# realpath_of <file> — bash 3.2 has no realpath; follow links by hand.
realpath_of() {
  local p="$1" t
  while [ -L "$p" ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd -P)" "$(basename "$p")"
}

# The unique real files behind every present config dir's settings.json.
reals=""
IFS=: read -r -a _dirs <<< "$DIRS"
for d in "${_dirs[@]}"; do
  [ -n "$d" ] && [ -e "$d/settings.json" ] || continue
  r="$(realpath_of "$d/settings.json")"
  case "
$reals
" in *"
$r
"*) ;; *) reals="${reals:+$reals
}$r" ;; esac
done
[ -n "$reals" ] || die "no settings.json in any of $DIRS — nothing to do"

bare_count() { # <file> → number of bare #! commands, or "x" when the file yields no rows at all
  local rows
  rows="$(/usr/bin/env python3 "$PRED" list "$1" --root "$REPO" 2>/dev/null)" || { echo x; return; }
  [ -n "$rows" ] || { echo x; return; }
  printf '%s\n' "$rows" | awk -F'\t' '$1=="bare"{n++} END{print n+0}'
}

# shellcheck disable=SC2016  # a jq program, not shell
NORM='include "hook-cmd-bare";
  def nh: if type == "array" then map(if (.hooks | type) == "array"
            then .hooks |= map(if (.command | type) == "string" then .command |= cmd_bare else . end) else . end) else . end;
  (if (.hooks | type) == "object" then .hooks |= map_values(nh) else . end)
  | if (.statusLine.command? | type) == "string" then .statusLine.command |= cmd_bare else . end'

verify_all() {
  local r
  while IFS= read -r r; do
    [ "$(bare_count "$r")" = 0 ] || return 1
  done <<< "$reals"
}

if [ "$mode" = verify ]; then verify_all; exit $?; fi

todo=0
while IFS= read -r r; do
  jq -e . "$r" >/dev/null 2>&1 || die "$r is not valid JSON — nothing written"
  n="$(bare_count "$r")"
  [ "$n" = x ] && die "could not classify the hook commands in $r — nothing written"
  if [ "$n" = 0 ]; then say "already applied — $r has no bare #! hook command"; continue; fi
  say "will prefix the interpreter on $n hook/statusLine command(s) in $r"
  todo=$(( todo + 1 ))
done <<< "$reals"
[ "$todo" -gt 0 ] || { say "already applied in every config dir"; exit 0; }
case "$mode" in
  dry)
    while IFS= read -r r; do
      /usr/bin/env python3 "$PRED" rewrite "$r" --root "$REPO" 2>&1 >/dev/null | awk -F'\t' '$1=="rewrote"{print "  " $3}'
    done <<< "$reals"
    say "DRY RUN — nothing written"; exit 0 ;;
  check) say "CHECK ok — preflight passes, nothing written"; exit 0 ;;
esac

bdir="$BROOT/hook-interp-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" || die "backup dir $bdir could not be made — nothing written"
i=0
while IFS= read -r r; do
  [ "$(bare_count "$r")" = 0 ] && continue
  i=$(( i + 1 ))
  cp -p "$r" "$bdir/settings.$i.json" && printf '%s\t%s\n' "$bdir/settings.$i.json" "$r" >> "$bdir/MANIFEST" \
    || die "backup of $r FAILED — nothing written"
  tmp="$(dirname "$r")/.settings.json.tmp-$N-$$"
  if ! /usr/bin/env python3 "$PRED" rewrite "$r" --root "$REPO" 2>"$bdir/rewrite.$i.log" | jq . > "$tmp" \
       || ! jq -e . "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; die "rewrite of $r FAILED ($bdir/rewrite.$i.log) — nothing written to it"
  fi
  # BY CONTENT: with the interpreter prefix set aside, the documents are identical, and none is left.
  if [ "$(jq -S -L "$LIB" "$NORM" "$r")" != "$(jq -S -L "$LIB" "$NORM" "$tmp")" ] || [ "$(bare_count "$tmp")" != 0 ]; then
    rm -f "$tmp"; die "rewrite of $r did not verify by content — nothing written to it"
  fi
  mv "$tmp" "$r" || { rm -f "$tmp"; die "write of $r FAILED — nothing written to it"; }
  say "rewrote $r (backup $bdir/settings.$i.json)"
done <<< "$reals"

verify_all || die "did NOT verify — a bare #! hook command remains; backups in $bdir (MANIFEST lists backup → file)"
say "verified — every hook command and the status line name their interpreter, in every config dir."
say "Takes effect in NEW sessions. Revert: while IFS=\$'\\t' read -r b f; do cp -p \"\$b\" \"\$f\"; done < $bdir/MANIFEST"
