#!/usr/bin/env bash
# memory-index-locate.sh — "which auto-loaded MEMORY.md does THIS session read?"
#
# The slug the harness keys on is the project root with `/` and `.` folded to `-`, under
# <config-dir>/projects/<slug>/memory/MEMORY.md. Getting it wrong is not a wrong answer, it is a
# SILENT one: a hook that resolves nothing measures nothing and reports healthy.
#
# Three traps, all of them measured, all of them encoded below:
#   1. LINKED WORKTREES. The harness keys on the MAIN worktree, so the root has to come through
#      the git COMMON dir, not `git rev-parse --show-toplevel`. Every session in this repo's
#      ~100 linked worktrees resolves to the wrong slug without it.
#   2. /var vs /private/var. git reports a fully resolved path while the harness keys on the cwd
#      it was handed, and on macOS those two share no prefix — so each candidate base is tried in
#      BOTH its logical and its physical spelling or one of them silently finds nothing.
#   3. THE INDEX MAY NOT EXIST YET. The session that has to CREATE it is exactly the one that most
#      needs the path named, so WHERE-IT-BELONGS is returned even when WHERE-IT-IS is empty.
#
# ⚠️ SECOND IMPLEMENTATION, NAMED SO IT CANNOT DRIFT UNNOTICED. hooks/memory-nudge.sh:68-118 has
# carried this same derivation inline since 2026-07-31 and is NOT converted to source this file in
# the wave that adds it. That is a deliberate blast-radius call, not an oversight: memory-nudge is
# a fleet-wide UserPromptSubmit hook whose failure mode is total silence, and a landed ADD is
# ABSENT until the converger links it (MEMORY.md convergence-counter-measures-distance-not-delivery)
# — so pointing the live advisory at a file that is not yet on the live layer would silence the
# nudge fleet-wide for exactly as long as the converge lag. Convert it in a wave that is allowed to
# touch that hook, and delete the inline copy in the same diff.
#
# mil_locate [cwd] → "<index-path-or-empty><TAB><index-path-where-it-belongs>"
#   Always returns 0 and always prints a TAB. A caller reads field 1 to MEASURE and field 2 to
#   NAME. MEMORY_INDEX_PATH overrides both — that is the test seam and the operator escape hatch.

mil_slugify() { printf '%s' "$1" | tr '/.' '--'; }

mil_locate() {
  local cwd="${1:-$PWD}" cfg mem want root gcd cand phys base p
  cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  mem="${MEMORY_INDEX_PATH:-}"
  want="$mem"
  if [ -n "$mem" ]; then printf '%s\t%s' "$mem" "$want"; return 0; fi

  [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
  root=""
  if gcd=$(cd "$cwd" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
     && [ -n "$gcd" ]; then
    root=$(dirname "$gcd")
  fi
  for cand in "$root" "$cwd"; do
    [ -n "$cand" ] || continue
    phys=$(cd "$cand" 2>/dev/null && pwd -P) || phys=""
    for base in "$cand" "$phys"; do
      [ -n "$base" ] || continue
      p="$cfg/projects/$(mil_slugify "$base")/memory/MEMORY.md"
      [ -n "$want" ] || want="$p"
      if [ -f "$p" ]; then mem="$p"; break 2; fi
    done
  done
  printf '%s\t%s' "$mem" "$want"
  return 0
}
