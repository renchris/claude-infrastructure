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
#                        "state":"registered"|"certifying"|"certified"|"build-certifying"|
#                                "build-certified"|"implementation-signed"|"closed"}]}
#
# FUNCTIONS (source this file; Bash 3.2-safe, because hooks and launchd jobs source it):
#   rp_resolve_cwd <dir>  prints "<slug> <state>" for the program one of whose cwd_roots contains
#                         <dir> (the root itself or any path under it; the longest root wins), else
#                         prints nothing. Always exits 0.
#   rp_is_active <dir>    exit 0 iff <dir> resolves to a program in state registered, certifying,
#                         certified, build-certifying, build-certified or implementation-signed
#                         (method v1.2, REPORT.md §11); exit 1 otherwise (closed, unregistered,
#                         no registry).
#   rp_resolve_prompt <text>  prints "<slug> <state>" for the program whose slug or one of whose
#                         aliases appears in <text> as a whole word, case-insensitively (the longest
#                         match wins; two programs tied on it is ambiguous and prints nothing), else
#                         nothing. The re-ask router's second key (REPORT.md §4.1). There is NO third
#                         key: the single-active fallback was deleted (§10 open item 2). Exits 0.
#   rp_program_state <slug>   prints the registry state of <slug>, else nothing. Exits 0.
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
    registered|certifying|certified|build-certifying|build-certified|implementation-signed) [ -n "$_RP_RESULT" ] && return 0 ;;
  esac
  return 1
}

# The registry read shared by the two keys below: one TSV row per program, "<slug> TAB <state> TAB
# <name>" for the slug and each alias. Same void-on-bad-shape rule as _rp_resolve.
_rp_names() {
  local reg
  reg="$(_rp_registry)"
  [ -f "$reg" ] || { _rp_warn_once "registry $reg is missing"; return 1; }
  command -v jq >/dev/null 2>&1 || { _rp_warn_once "jq is not on PATH, so registry $reg cannot be read"; return 1; }
  jq -r '
      if (.programs | type) != "array" then error("programs is not an array") else . end
      | .programs[]
      | if (.slug | type) != "string" or (.state | type) != "string"
        then error("program without a string slug and state") else . end
      | . as $p
      | ([$p.slug] + [($p.aliases // [])[] | select(type == "string" and length > 0)])[]
      | [$p.slug, $p.state, .] | @tsv' "$reg" 2>/dev/null \
    || { _rp_warn_once "registry $reg is unparseable"; return 1; }
}

rp_program_state() {
  local want="${1:-}" rows slug state name
  [ -n "$want" ] || return 0
  rows="$(_rp_names)" || return 0
  while IFS="$(printf '\t')" read -r slug state name; do
    if [ "$slug" = "$want" ]; then printf '%s\n' "$state"; return 0; fi
  done <<EOF
$rows
EOF
  return 0
}

rp_resolve_prompt() {
  local text="${1:-}" rows slug state name lt ln best="" best_len=0 tie=0
  [ -n "$text" ] || return 0
  rows="$(_rp_names)" || return 0
  lt="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  while IFS="$(printf '\t')" read -r slug state name; do
    [ -n "$name" ] || continue
    ln="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
    # Whole word: the name is bounded by a non-word character or the text's edge on both sides.
    # Pure-shell matching (no regex built from the name), so an alias holding regex syntax is literal.
    case " $lt " in
      *[!a-z0-9_-]"$ln"[!a-z0-9_-]*) ;;
      *) continue ;;
    esac
    if [ "${#ln}" -gt "$best_len" ]; then best_len="${#ln}"; best="$slug $state"; tie=0
    elif [ "${#ln}" -eq "$best_len" ] && [ "${best%% *}" != "$slug" ]; then tie=1; fi
  done <<EOF
$rows
EOF
  [ "$tie" -eq 0 ] && [ -n "$best" ] && printf '%s\n' "$best"
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    resolve)   rp_resolve_cwd "${2:-$PWD}" ;;
    is-active) rp_is_active "${2:-$PWD}" ;;
    resolve-prompt) rp_resolve_prompt "${2:-}" ;;
    state)     rp_program_state "${2:-}" ;;
    *) printf 'usage: %s resolve|is-active [dir] | resolve-prompt <text> | state <slug>\n' "${0##*/}" >&2; exit 2 ;;
  esac
fi
