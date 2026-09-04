#!/bin/bash
# migration-class: c10
# migration-step: register hooks/memory-index-drain.sh as a PostToolUse hook so an index write is caught AT the write whichever tool made it — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0015-memory-index-drain-registration.sh
# migration-subject: ~/.claude/hooks/memory-index-drain.sh
# migration-verify: jq -e '[.hooks.PostToolUse[]?.hooks[]?.command] | any(. == "~/.claude/hooks/memory-index-drain.sh")' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0015 — the registration half of the door-agnostic drain (W2 of the memory-compaction plan).
#
# WHAT IT FIXES, AND WHY THE SUBJECT IS INERT WITHOUT IT. hooks/memory-index-drain.sh is the first
# thing in this tree that can see a `Bash >>` append to the auto-loaded index. The PreToolUse gate
# cannot: it matches Write/Edit/MultiEdit, and the observed appends are
# `cd <…>/memory && … >> MEMORY.md`. Neither can the product's own PostToolUse memory-size callback,
# which registers on Read/Glob/Grep/Edit/Write — Bash is absent from BOTH layers. A hook on disk
# that no settings.json names is exactly the condition this directory exists for: the conclusion
# lands and nothing enforces it (docs/research/inertness-generator-2026-08-07.md §3).
#
# WHY THE MATCHER IS ALL FOUR TOOLS AND NOT JUST Bash. Bash is the leak the wave was measured on,
# but the hook has no opinion about which tool ran — it looks at the FILE's stat. The condition it
# actuates on is PER-ENTRY size, and the PreToolUse gate does not judge that dimension at all
# today, so an Edit can write an over-cap line just as an append can. Matching only Bash would be a
# matcher shaped like the anecdote rather than like the class. The cost on the other three is one
# `stat` and an exit, because nothing is measured unless that stat differs from the last recorded.
#
# WHY IT IS APPENDED TO THE EXISTING Bash GROUP'S SIBLING RATHER THAN CREATED AS ONE. It is created
# as its own group: the two existing PostToolUse groups are `Write|Edit|MultiEdit` and `Bash`, and
# this hook spans both, so folding it into either would half-cover it silently — the same
# half-coverage 0005's header warns about, one axis over.
#
# WHY c10. It edits settings.json. migrations/README.md: "A migration that touches settings.json, a
# launchd plist, or credentials declares c10 and waits for a human." Staged, never self-run.
set -uo pipefail

# shellcheck disable=SC2088  # the tilde is DELIBERATELY literal: this string is stored INTO
# settings.json, where CC expands it at hook-run time. Expanding it here would hard-code this
# machine's absolute $HOME into a config mirrored across five config dirs.
HOOK_CMD='~/.claude/hooks/memory-index-drain.sh'
HOOK_FILE="${CC_CLAUDE_DIR:-$HOME/.claude}/hooks/memory-index-drain.sh"
MATCHER='Bash|Write|Edit|MultiEdit'
# 10s. The common path is one stat; the tail — measure, drain, re-measure — is a handful of jq and
# one rotor run, and the rotor's own lock makes a slow case bounded rather than unbounded.
TIMEOUT=10
rc=0

command -v jq >/dev/null 2>&1 || { printf '0015: jq required\n' >&2; exit 1; }

# ── preconditions, re-derived at CONSUMPTION rather than trusted from the header ─────────────────
# A migration's premise can rot between staging and the converge that reads it (MEMORY.md
# discovery-critic-premise-goes-stale). Two things must be true on the LIVE layer, not in the
# checkout: the hook must be executable there, and so must the LIB it sources and the ACTUATOR it
# fires. All three are ADDs in the diff that stages this, and a landed ADD is ABSENT until the
# converger links it — every consumer guard on an absent file is a SILENT skip, so registering over
# a half-converged layer would produce a hook that runs, finds no lib, and exits 0 forever
# (MEMORY.md convergence-counter-measures-distance-not-delivery).
LIVE="${CC_CLAUDE_DIR:-$HOME/.claude}"
if [ ! -x "$HOOK_FILE" ]; then
  printf '0015: NOT registered — %s is missing or not executable.\n' "$HOOK_FILE" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it first.\n' >&2
  exit 1
fi
for dep in "$LIVE/hooks/lib/memory-index-locate.sh" "$LIVE/hooks/lib/memory-index-measure.sh"; do
  if [ ! -r "$dep" ]; then
    printf '0015: NOT registered — %s is not on the live layer yet.\n' "$dep" >&2
    printf '      Registering now would wire a hook that silently does nothing. Converge first.\n' >&2
    exit 1
  fi
done
if [ ! -x "$LIVE/bin/cc-memory-rotate" ]; then
  printf '0015: NOT registered — %s/bin/cc-memory-rotate is missing or not executable.\n' "$LIVE" >&2
  printf '      Without the actuator this hook is detection only, which is the class it replaces.\n' >&2
  exit 1
fi

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Fleet discriminator: a config that already runs PostToolUse hooks is a fleet config. Unlike
  # 0014 this event DOES exist everywhere, so it can be its own discriminator.
  if ! jq -e '.hooks.PostToolUse | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0015: %s — no PostToolUse array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  if jq -e --arg c "$HOOK_CMD" \
       '[.hooks.PostToolUse[]?.hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
    printf '0015: %s — already registered\n' "$f"
    continue
  fi

  bak="$f.bak-0015-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0015: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0015-$$"
  # APPEND a new group. Never rewrite an existing one: a sibling migration or a hand-edit owns
  # those, and this can only ever add its own.
  if jq --arg c "$HOOK_CMD" --arg m "$MATCHER" --argjson t "$TIMEOUT" \
       '.hooks.PostToolUse += [{"matcher":$m,"hooks":[{"type":"command","command":$c,"timeout":$t}]}]' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # verify the edit BY CONTENT before it replaces the live file
    if jq -e --arg c "$HOOK_CMD" \
         '[.hooks.PostToolUse[]?.hooks[]?.command] | any(. == $c)' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0015: %s — registered (backup: %s)\n' "$f" "$bak"
    else
      rm -f "$tmp"; printf '0015: %s — edit did not contain the hook; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0015: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

exit "$rc"
