#!/bin/bash
# research-router.sh — shared by the re-ask router (hooks/research-precognition-nudge.sh) and the
# research block (hooks/research-block.sh), wave B1 of docs/plans/RESEARCH_PROGRAM_BUILD.md.
#
#   rr_init <hook $0>         locates scripts/lib/research-program.sh (wave A1's resolver) and
#                             scripts/research-kit/router.py into RR_LIB / RR_ROUTER; rc 1 when
#                             either is missing, which every caller treats as "no program" (exit 0).
#   rr_registry_present       rc 0 iff the registry file exists — the fast path every tool call takes
#                             on a machine with no research program.
#
# Resolution follows the hook's OWN symlink into the checkout first: a brand-new file has no
# ~/.claude/... link until install.sh runs, while the live hook IS a link into the repo (the
# completion-assert.sh _ca_rp_active pattern, same cause). Bash 3.2-safe.

rr_init() {
  local t base
  t="${1:-$0}"
  [ -L "$t" ] && t="$(readlink "$t")"
  base="$(cd "$(dirname "$t")/.." 2>/dev/null && pwd)"
  RR_LIB="${CC_RESEARCH_PROGRAM_LIB:-$base/scripts/lib/research-program.sh}"
  [ -f "$RR_LIB" ] || RR_LIB="$HOME/.claude/scripts/lib/research-program.sh"
  RR_ROUTER="${CC_RESEARCH_ROUTER_PY:-$base/scripts/research-kit/router.py}"
  [ -f "$RR_ROUTER" ] || RR_ROUTER="$HOME/.claude/scripts/research-kit/router.py"
  [ -f "$RR_LIB" ] && [ -f "$RR_ROUTER" ] || return 1
  # shellcheck source=../../scripts/lib/research-program.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$RR_LIB" 2>/dev/null
}

rr_registry_present() {
  # The resolver's own default (research-program.sh _rp_registry), not the kit's: the two keys
  # must agree on which file is "no registry".
  [ -f "${CC_RESEARCH_REGISTRY:-$HOME/.claude/autonomy/research/programs.json}" ]
}
