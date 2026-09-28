#!/bin/bash
# migration-class: c10
# migration-step: pin the effort Claude Code gives the 5.5-generation models when nothing else sets one: write "modelSettings": {"claude-opus-5-5": {"effortLevel": "high"}} into each account's settings.json (~/.claude and ~/.claude-{next,secondary,tertiary,quaternary}; every unique physical file). Without it, any launch of Opus 5.5 that passes no --effort runs at MEDIUM, because the top-level "effortLevel": "high" we already set is silently ignored for 5.5 ids. Reversible: delete the key or restore the printed backup. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0044-effort-modelsettings-55.sh --confirm settings.json
# migration-verify: bash ~/Development/claude-infrastructure/migrations/0044-effort-modelsettings-55.sh --check >/dev/null 2>&1
# migration-conflict: bash ~/Development/claude-infrastructure/migrations/0044-effort-modelsettings-55.sh --conflict >/dev/null 2>&1
#
# The verifier is config-dir-INVARIANT: it walks all five account roots itself.
#
# ══ 0044 — per-model effort pins for the 5.5 generation (Sonnet 5.5 adoption, 2026-09-28) ═══════════
# WHY (docs/research/sonnet55-utilization-2026-09-28/notes/probe-effort-binding.md, MEASURED from API
# request bodies through a logging proxy, on 2.1.280 AND 2.1.284):
#   * A launch of claude-opus-5-5 or claude-sonnet-5-5 with no --effort sends output_config.effort
#     "medium" (the catalog default), even with "effortLevel": "high" in user settings.
#   * The binary stores top-level user effortLevel as a LEGACY value and applies it only to a
#     hard-coded list of older models (claude-opus-5, claude-sonnet-5, ...). The 5.5 ids are not on it.
#   * What does bind per model is modelSettings.<model>.effortLevel (the shape /effort writes).
# Who is exposed: every path that launches Opus 5.5 without --effort. The claude() launcher always
# passes --effort high, so interactive leads were never affected; headless scripts, scorers and
# anything that calls the binary directly were running one rung lower than effort_defaults.default.
#
# WHAT THIS DOES NOT DO. It pins only claude-opus-5-5, whose policy default is "high"
# (model-config.yaml effort_defaults.default). Sonnet 5.5 keeps the vendor's Claude Code default
# (medium) unless a slot sets its own effort; its routed slots set effort explicitly per call
# (model-config.yaml effort_defaults.sonnet55_*). An explicit --effort, a Workflow agent() effort, or
# agent frontmatter effort still wins over this pin.
#
# SAFETY. Backs up each file, edits through a temp file, verifies BY CONTENT that only this key
# changed, then reads the effect back. Idempotent. Takes effect in NEW sessions.
#
# Usage: bash migrations/0044-effort-modelsettings-55.sh --dry-run
#        bash migrations/0044-effort-modelsettings-55.sh --confirm settings.json
#        bash migrations/0044-effort-modelsettings-55.sh --check        (exit 0 ⇔ every present file pins every model)
#        bash migrations/0044-effort-modelsettings-55.sh --conflict     (exit 0 ⇔ some file pins a different level)
#        bash migrations/0044-effort-modelsettings-55.sh --self-check   (runs the whole flow on a temp HOME)
# bash 3.2-safe.
set -uo pipefail

# model=level pairs; one per line
PINS='claude-opus-5-5=high'
command -v jq >/dev/null 2>&1 || { printf '0044: jq required — nothing written\n' >&2; exit 1; }

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

# _pins_json → {"model":"level",...}
_pins_json() {
  local line out='{}'
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    out="$(jq -c --arg m "${line%%=*}" --arg l "${line#*=}" '.[$m] = $l' <<<"$out")"
  done <<EOF
$PINS
EOF
  printf '%s\n' "$out"
}
P="$(_pins_json)"

_check() {
  local f n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$(( n + 1 ))
    jq -e --argjson p "$P" '. as $s | [$p | to_entries[] | ($s.modelSettings[.key].effortLevel // null) == .value] | all' "$f" >/dev/null 2>&1 || return 1
  done <<EOF
$(_targets)
EOF
  [ "$n" -gt 0 ]
}

_conflict() { # exit 0 ⇔ some file pins one of these models at a DIFFERENT level
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    jq -e --argjson p "$P" '. as $s | [$p | to_entries[] | ($s.modelSettings[.key].effortLevel // null) as $v | $v != null and $v != .value] | any' "$f" >/dev/null 2>&1 && return 0
  done <<EOF
$(_targets)
EOF
  return 1
}

_apply() { # $1 = dry|apply
  local mode="$1" f tmp bdir rc=0 same
  bdir="$HOME/.claude/backups/effort-modelsettings-0044-$(date +%Y%m%d%H%M%S)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! jq -e . "$f" >/dev/null 2>&1; then
      printf '0044: %s is not valid JSON — left unchanged\n' "$f" >&2; rc=1; continue
    fi
    if jq -e --argjson p "$P" '. as $s | [$p | to_entries[] | ($s.modelSettings[.key].effortLevel // null) == .value] | all' "$f" >/dev/null 2>&1; then
      printf '0044: already pinned — %s\n' "$f"; continue
    fi
    printf '0044: will set modelSettings %s in %s (now: %s)\n' "$P" "$f" "$(jq -c '.modelSettings // "unset"' "$f")"
    [ "$mode" = dry ] && continue
    mkdir -p "$bdir" && cp -p "$f" "$bdir/$(basename "$(dirname "$f")").settings.json" \
      || { printf '0044: backup FAILED for %s — left unchanged\n' "$f" >&2; rc=1; continue; }
    tmp="$(dirname "$f")/.settings.json.tmp-0044-$$"
    if ! jq --argjson p "$P" 'reduce ($p | to_entries[]) as $e (.; .modelSettings[$e.key].effortLevel = $e.value)' "$f" >"$tmp" 2>/dev/null \
       || ! jq -e . "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp"; printf '0044: jq edit FAILED for %s — left unchanged\n' "$f" >&2; rc=1; continue
    fi
    # BY CONTENT: outside the pinned model entries nothing changed, and every pin reads back.
    same=$(jq -n --slurpfile a "$f" --slurpfile b "$tmp" --argjson p "$P" '
      def strip: reduce ($p | keys[]) as $k (.; del(.modelSettings[$k])) | (if (.modelSettings // {}) == {} then del(.modelSettings) else . end);
      def pinsonly: reduce ($p | keys[]) as $k (.; .modelSettings[$k] |= (. // {} | del(.effortLevel)));
      (($a[0] | strip) == ($b[0] | strip))
      and (($a[0] | pinsonly | .modelSettings // {} | with_entries(select(.key as $k | $p | has($k)))) == ($b[0] | pinsonly | .modelSettings // {} | with_entries(select(.key as $k | $p | has($k)))))
      and ([$p | to_entries[] as $e | $b[0].modelSettings[$e.key].effortLevel == $e.value] | all)')
    if [ "$same" != true ]; then
      rm -f "$tmp"; printf '0044: edit of %s did not verify by content — left unchanged\n' "$f" >&2; rc=1; continue
    fi
    mv "$tmp" "$f" || { rm -f "$tmp"; printf '0044: write FAILED for %s\n' "$f" >&2; rc=1; continue; }
  done <<EOF
$(_targets)
EOF
  if [ "$mode" = dry ]; then printf '0044: DRY RUN — nothing written\n'; return "$rc"; fi
  [ -d "$bdir" ] && printf '0044: backups in %s\n' "$bdir"
  if _check; then
    printf '0044: verified — every account settings.json pins %s. Takes effect in NEW sessions.\n' "$P"
  else
    printf '0044: NOT verified — at least one settings.json lacks a pin\n' >&2; rc=1
  fi
  return "$rc"
}

_self_check() {
  local th fail=0 out
  th="$(mktemp -d "${TMPDIR:-/tmp}/0044-selfcheck.XXXXXX")" || return 1
  mkdir -p "$th/.claude" "$th/.claude-next" "$th/.claude-secondary"
  printf '{"model":"opus","effortLevel":"high","hooks":{"Stop":[]}}\n' >"$th/.claude/settings.json"
  printf '{"modelSettings":{"claude-opus-5-5":{"effortLevel":"low","maxEffortLevel":"xhigh"},"claude-sonnet-5":{"effortLevel":"max"}}}\n' >"$th/.claude-next/settings.json"
  ln -s ../.claude/settings.json "$th/.claude-secondary/settings.json"
  HOME="$th" bash "$0" --check >/dev/null 2>&1 && { echo "self-check: --check passed before apply"; fail=1; }
  HOME="$th" bash "$0" --conflict >/dev/null 2>&1 || { echo "self-check: --conflict missed a different level"; fail=1; }
  out="$(HOME="$th" bash "$0" --dry-run 2>&1)"
  jq -e '.modelSettings["claude-opus-5-5"].effortLevel == "low"' "$th/.claude-next/settings.json" >/dev/null || { echo "self-check: dry run wrote"; fail=1; }
  [ "$(printf '%s\n' "$out" | grep -c 'will set')" = 2 ] || { echo "self-check: expected 2 unique targets, got: $out"; fail=1; }
  HOME="$th" bash "$0" --confirm settings.json >/dev/null 2>&1 || { echo "self-check: apply failed"; fail=1; }
  HOME="$th" bash "$0" --check >/dev/null 2>&1 || { echo "self-check: --check failed after apply"; fail=1; }
  HOME="$th" bash "$0" --conflict >/dev/null 2>&1 && { echo "self-check: conflict still reported"; fail=1; }
  [ -L "$th/.claude-secondary/settings.json" ] || { echo "self-check: symlink was replaced by a file"; fail=1; }
  jq -e '.model == "opus" and .effortLevel == "high" and .hooks == {"Stop":[]}' "$th/.claude/settings.json" >/dev/null || { echo "self-check: other keys changed"; fail=1; }
  jq -e '.modelSettings["claude-opus-5-5"].maxEffortLevel == "xhigh" and .modelSettings["claude-sonnet-5"].effortLevel == "max"' "$th/.claude-next/settings.json" >/dev/null || { echo "self-check: sibling modelSettings keys changed"; fail=1; }
  out="$(HOME="$th" bash "$0" --confirm settings.json 2>&1)"
  [ "$(printf '%s\n' "$out" | grep -c 'already pinned')" = 2 ] || { echo "self-check: not idempotent: $out"; fail=1; }
  rm -rf "$th"
  if [ "$fail" -eq 0 ]; then echo "0044 self-check: PASS"; return 0; fi
  echo "0044 self-check: FAIL"; return 1
}

case "${1:-}" in
  --check) _check; exit $? ;;
  --conflict) _conflict; exit $? ;;
  --self-check) _self_check; exit $? ;;
  --dry-run) _apply dry; exit $? ;;
  --confirm)
    [ "${2:-}" = "settings.json" ] || { printf '0044: --confirm must name its target: --confirm settings.json\n' >&2; exit 2; }
    _apply apply; exit $? ;;
  '')
    if [ -n "${CC_MIGRATION_STATE:-}" ]; then _apply apply; exit $?; fi
    printf '0044: pass --dry-run to preview or --confirm settings.json to apply\n' >&2; exit 2 ;;
  *) printf '0044: unknown argument %s\n' "$1" >&2; exit 2 ;;
esac
