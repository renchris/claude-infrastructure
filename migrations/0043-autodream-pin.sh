#!/bin/bash
# migration-class: c10
# migration-step: pin Claude Code's native autoDream consolidation OFF for every account: set "autoDreamEnabled": false in each account's settings.json (~/.claude and ~/.claude-{next,secondary,tertiary,quaternary}; every unique physical file, so a forked copy is covered as well as the shared one). No effect while the server flag is off; if the flag ever turns on, autoDream will not rewrite, shorten or delete memory files. Reversible: delete the key or restore the printed backup. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0043-autodream-pin.sh --confirm settings.json
# migration-verify: bash ~/Development/claude-infrastructure/migrations/0043-autodream-pin.sh --check >/dev/null 2>&1
# migration-conflict: bash ~/Development/claude-infrastructure/migrations/0043-autodream-pin.sh --conflict >/dev/null 2>&1
#
# The verifier is config-dir-INVARIANT: it walks all five account roots itself, so the per-dir
# re-run in scripts/registration-state.sh gets one answer from every dir.
#
# ══ 0043 — autoDream pinned off (TrueMemory adoption, Wave A; decision in research §7) ════════════
# WHY (docs/research/truememory-2026-09-27.md §1 finding 4, §5.10, §7; evidence gap-1.md). Claude
# Code ships two background memory passes gated by server flags: extractMemories
# (tengu_passport_quail) and autoDream (tengu_onyx_plover). Both fork with Edit/Write on any .md in
# our memory stores and `rm -f` of .md files, and `archive/` is not protected. autoDream's Phase 4
# shortens index lines, deletes "contradicted facts" and drops pointers: the lossy half that our
# rotor and /compact-memory deliberately keep human-gated (MEMORY_KNOWLEDGE_V2 §8 R18). Today every
# flag is off in all six caches, but a flip reaches running sessions within about 6 h. Once the flag
# passes, the `autoDreamEnabled` setting wins, so `false` fully blocks autoDream.
#
# WHAT THIS DOES NOT DO. There is no equivalent setting for extraction. Do NOT reach for
# `autoMemoryEnabled:false` (it also stops MEMORY.md loading) or DISABLE_GROWTHBOOK=1 (it disables
# every server flag). Extraction is watched by the NATIVE sentinel in scripts/memory-fleet-sweep.sh
# --reach and undone by scripts/memory-store-snapshot.sh.
#
# WHY PER FILE. The five settings.json files are separate real files on some machines (config-mirror
# does not propagate this key) and one shared file on others (0037). The loop resolves each to its
# physical path and edits each unique file once, so both topologies end in the same state.
#
# SAFETY. Backs up each file, edits through a temp file, verifies BY CONTENT that only this key
# changed, then reads the effect back. Idempotent. Takes effect in NEW sessions.
#
# Usage: bash migrations/0043-autodream-pin.sh --dry-run
#        bash migrations/0043-autodream-pin.sh --confirm settings.json
#        bash migrations/0043-autodream-pin.sh --check        (exit 0 ⇔ every present file pins false)
#        bash migrations/0043-autodream-pin.sh --conflict     (exit 0 ⇔ some file sets it true)
#        bash migrations/0043-autodream-pin.sh --self-check   (runs the whole flow on a temp HOME)
# bash 3.2-safe.
set -uo pipefail

KEY='autoDreamEnabled'
command -v jq >/dev/null 2>&1 || { printf '0043: jq required — nothing written\n' >&2; exit 1; }

# _deref <path> → the physical file behind any symlink chain (BSD-safe, no readlink -f needed).
_deref() {
  local p="$1" t n=0
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$(( n + 1 ))
  done
  printf '%s\n' "$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)/$(basename "$p")"
}

# _targets → one physical settings.json per line, deduplicated, for every account root present.
_targets() {
  local d f seen=""
  for d in "$HOME/.claude" "$HOME/.claude-next" "$HOME/.claude-secondary" \
           "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do
    f="$d/settings.json"
    [ -e "$f" ] || continue
    f="$(_deref "$f")"
    case "$seen" in *"|$f|"*) continue ;; esac
    seen="$seen|$f|"
    printf '%s\n' "$f"
  done
}

_check() { # exit 0 ⇔ at least one file exists and every one pins false
  local f n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$(( n + 1 ))
    jq -e --arg k "$KEY" '.[$k] == false' "$f" >/dev/null 2>&1 || return 1
  done <<EOF
$(_targets)
EOF
  [ "$n" -gt 0 ]
}

_conflict() { # exit 0 ⇔ some file actively sets the key true (a different value at the same key)
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    jq -e --arg k "$KEY" '.[$k] == true' "$f" >/dev/null 2>&1 && return 0
  done <<EOF
$(_targets)
EOF
  return 1
}

_apply() { # $1 = dry|apply
  local mode="$1" f tmp bdir rc=0 same
  bdir="$HOME/.claude/backups/autodream-pin-0043-$(date +%Y%m%d%H%M%S)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! jq -e . "$f" >/dev/null 2>&1; then
      printf '0043: %s is not valid JSON — left unchanged\n' "$f" >&2; rc=1; continue
    fi
    if jq -e --arg k "$KEY" '.[$k] == false' "$f" >/dev/null 2>&1; then
      printf '0043: already pinned — %s\n' "$f"; continue
    fi
    printf '0043: will set %s: false in %s (now: %s)\n' "$KEY" "$f" "$(jq -c --arg k "$KEY" '.[$k] // "unset"' "$f")"
    [ "$mode" = dry ] && continue
    # A backup name that keeps the account visible: .claude-next/settings.json → .claude-next.settings.json
    mkdir -p "$bdir" && cp -p "$f" "$bdir/$(basename "$(dirname "$f")").settings.json" \
      || { printf '0043: backup FAILED for %s — left unchanged\n' "$f" >&2; rc=1; continue; }
    tmp="$(dirname "$f")/.settings.json.tmp-0043-$$"
    if ! jq --arg k "$KEY" '.[$k] = false' "$f" >"$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp"; printf '0043: jq edit FAILED for %s — left unchanged\n' "$f" >&2; rc=1; continue
    fi
    # BY CONTENT: every other key is unchanged and the key reads false.
    same=$(jq -n --slurpfile a "$f" --slurpfile b "$tmp" --arg k "$KEY" \
      '($a[0] | del(.[$k])) == ($b[0] | del(.[$k])) and $b[0][$k] == false')
    if [ "$same" != true ]; then
      rm -f "$tmp"; printf '0043: edit of %s did not verify by content — left unchanged\n' "$f" >&2; rc=1; continue
    fi
    mv "$tmp" "$f" || { rm -f "$tmp"; printf '0043: write FAILED for %s\n' "$f" >&2; rc=1; continue; }
  done <<EOF
$(_targets)
EOF
  if [ "$mode" = dry ]; then printf '0043: DRY RUN — nothing written\n'; return "$rc"; fi
  [ -d "$bdir" ] && printf '0043: backups in %s\n' "$bdir"
  if _check; then
    printf '0043: verified — every account settings.json pins %s: false. Takes effect in NEW sessions.\n' "$KEY"
  else
    printf '0043: NOT verified — at least one settings.json does not read %s: false\n' "$KEY" >&2; rc=1
  fi
  return "$rc"
}

_self_check() { # the whole flow on a throwaway HOME: forked files, one shared symlink, idempotence
  local th fail=0 out
  th="$(mktemp -d "${TMPDIR:-/tmp}/0043-selfcheck.XXXXXX")" || return 1
  mkdir -p "$th/.claude" "$th/.claude-next" "$th/.claude-secondary"
  printf '{"model":"opus","hooks":{"Stop":[]}}\n' >"$th/.claude/settings.json"
  printf '{"model":"sonnet","autoDreamEnabled":true}\n' >"$th/.claude-next/settings.json"
  ln -s ../.claude/settings.json "$th/.claude-secondary/settings.json"
  out="$(HOME="$th" bash "$0" --check 2>&1)" && { echo "self-check: --check passed before apply"; fail=1; }
  HOME="$th" bash "$0" --conflict >/dev/null 2>&1 || { echo "self-check: --conflict missed a true value"; fail=1; }
  out="$(HOME="$th" bash "$0" --dry-run 2>&1)"
  jq -e '.autoDreamEnabled == true' "$th/.claude-next/settings.json" >/dev/null || { echo "self-check: dry run wrote"; fail=1; }
  [ "$(printf '%s\n' "$out" | grep -c 'will set')" = 2 ] || { echo "self-check: expected 2 unique targets, got: $out"; fail=1; }
  HOME="$th" bash "$0" --confirm settings.json >/dev/null 2>&1 || { echo "self-check: apply failed"; fail=1; }
  HOME="$th" bash "$0" --check >/dev/null 2>&1 || { echo "self-check: --check failed after apply"; fail=1; }
  HOME="$th" bash "$0" --conflict >/dev/null 2>&1 && { echo "self-check: conflict still reported"; fail=1; }
  [ -L "$th/.claude-secondary/settings.json" ] || { echo "self-check: symlink was replaced by a file"; fail=1; }
  jq -e '.model == "opus" and .hooks == {"Stop":[]}' "$th/.claude/settings.json" >/dev/null || { echo "self-check: other keys changed"; fail=1; }
  out="$(HOME="$th" bash "$0" --confirm settings.json 2>&1)"
  [ "$(printf '%s\n' "$out" | grep -c 'already pinned')" = 2 ] || { echo "self-check: not idempotent: $out"; fail=1; }
  rm -rf "$th"
  if [ "$fail" -eq 0 ]; then echo "0043 self-check: PASS"; return 0; fi
  echo "0043 self-check: FAIL"; return 1
}

case "${1:-}" in
  --check) _check; exit $? ;;
  --conflict) _conflict; exit $? ;;
  --self-check) _self_check; exit $? ;;
  --dry-run) _apply dry; exit $? ;;
  --confirm)
    [ "${2:-}" = "settings.json" ] || { printf '0043: --confirm must name its target: --confirm settings.json\n' >&2; exit 2; }
    _apply apply; exit $? ;;
  '')
    # The converger never runs a c10 body; a bare run outside it is refused rather than guessed at.
    if [ -n "${CC_MIGRATION_STATE:-}" ]; then _apply apply; exit $?; fi
    printf '0043: pass --dry-run to preview or --confirm settings.json to apply\n' >&2; exit 2 ;;
  *) printf '0043: unknown argument %s\n' "$1" >&2; exit 2 ;;
esac
