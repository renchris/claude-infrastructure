#!/usr/bin/env bash
# research-program.sh — resolve a working directory to a registered research program.
#
# The standing-rule exemption for an ACTIVE research program (REPORT.md §3.1 ruling 2, ruled
# 2026-10-01, packet 83adb541ea19) is keyed on THIS resolution, never on a DoD marker: no step of
# the method writes a marker, and the re-ask router (wave B1) resolves the same registry by
# directory, so the rules, the Stop hook and the router share one key (REPORT.md §10 open item 10,
# option 1). Path:
#   docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md
#
# THE REGISTRY CONTRACT (wave A2's gate.sh is its only writer; do not change the shape here):
#   file   ${CC_RESEARCH_REGISTRY:-$HOME/.claude/autonomy/research/programs.json}
#   shape  {"programs":[{"slug":str,"aliases":[str],"cwd_roots":[abs path],
#                        "state":"registered"|"certifying"|"certified"|"closed"}]}
#
# FUNCTIONS (source this file; Bash 3.2-safe, because hooks and launchd jobs source it):
#   rp_resolve_cwd <dir>  prints "<slug> <state>" for the program one of whose cwd_roots contains
#                         <dir> (the root itself or any path under it; the longest root wins), else
#                         prints nothing. Always exits 0.
#   rp_is_active <dir>    exit 0 iff <dir> resolves to a program in state registered, certifying or
#                         certified; exit 1 otherwise (closed, unregistered, no registry).
#
# A missing or unparseable registry means NO PROGRAM, so every exemption stays off: the failure
# direction is "the standing rules apply", which is what they did before this existed. It is said
# on stderr once per shell that sources this lib, because a silent fallback would read exactly like
# "not in a program".
#
# CLI (for rules and hand checks): research-program.sh resolve <dir> | is-active <dir>

_rp_registry() {
  printf '%s' "${CC_RESEARCH_REGISTRY:-$HOME/.claude/autonomy/research/programs.json}"
}

_rp_warn_once() {
  [ -n "${_RP_WARNED:-}" ] && return 0
  _RP_WARNED=1
  printf 'research-program: %s — treating this as no research program\n' "$1" >&2
}

# Physical path when the directory exists (so /tmp and /private/tmp, or a symlinked checkout,
# compare equal); otherwise the literal with trailing slashes removed.
_rp_canon() {
  local p="$1" c
  if [ -d "$p" ] && c="$(cd "$p" 2>/dev/null && pwd -P)" && [ -n "$c" ]; then
    printf '%s' "$c"
    return 0
  fi
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  printf '%s' "$p"
}

# Resolves into the global _RP_RESULT, in the CALLER's shell: a `$( )` here would run the
# warn-once flag in a subshell and lose it, so every rp_is_active call would warn again.
_rp_resolve() {
  local dir="${1:-}" reg rows cdir root slug state croot best_len=-1 best=""
  _RP_RESULT=""
  [ -n "$dir" ] || return 0
  reg="$(_rp_registry)"
  if [ ! -f "$reg" ]; then
    _rp_warn_once "registry $reg is missing"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    _rp_warn_once "jq is not on PATH, so registry $reg cannot be read"
    return 0
  fi
  # One TSV row per (root, slug, state). A shape that is not the contract (no programs array, a
  # non-string slug or state) is unparseable, not empty: jq errors and the whole registry is void.
  if ! rows="$(jq -r '
        if (.programs | type) != "array" then error("programs is not an array") else . end
        | .programs[]
        | if (.slug | type) != "string" or (.state | type) != "string"
          then error("program without a string slug and state") else . end
        | . as $p
        | (.cwd_roots // [])[]
        | select(type == "string" and length > 0)
        | [., $p.slug, $p.state] | @tsv' "$reg" 2>/dev/null)"; then
    _rp_warn_once "registry $reg is unparseable"
    return 0
  fi
  cdir="$(_rp_canon "$dir")"
  while IFS="$(printf '\t')" read -r root slug state; do
    [ -n "$root" ] || continue
    case "$root" in /*) ;; *) continue ;; esac   # the contract says absolute; a relative root matches nothing
    croot="$(_rp_canon "$root")"
    case "$cdir" in
      "$croot"|"$croot"/*)
        if [ "${#croot}" -gt "$best_len" ]; then best_len="${#croot}"; best="$slug $state"; fi ;;
    esac
    # `/` as a root contains everything; the case above needs it spelled without the double slash.
    if [ "$croot" = "/" ] && [ "$best_len" -lt 1 ]; then best_len=1; best="$slug $state"; fi
  done <<EOF
$rows
EOF
  _RP_RESULT="$best"
  return 0
}

rp_resolve_cwd() {
  _rp_resolve "${1:-}"
  [ -n "$_RP_RESULT" ] && printf '%s\n' "$_RP_RESULT"
  return 0
}

rp_is_active() {
  _rp_resolve "${1:-}"
  case "${_RP_RESULT##* }" in
    registered|certifying|certified) [ -n "$_RP_RESULT" ] && return 0 ;;
  esac
  return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    resolve)   rp_resolve_cwd "${2:-$PWD}" ;;
    is-active) rp_is_active "${2:-$PWD}" ;;
    *) printf 'usage: %s resolve|is-active [dir]\n' "${0##*/}" >&2; exit 2 ;;
  esac
fi
