#!/bin/bash
# migration-class: c10
# migration-step: REPLACE file-changed.sh with cwd-changed.sh in the CwdChanged slot — the slot holds the SILENT emitter, so a re-arm that carried nothing is indistinguishable from one that never fired. Edits settings.json ⇒ C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0021-cwdchanged-slot-replace.sh
# migration-subject: ~/.claude/hooks/cwd-changed.sh
# migration-verify: jq -e '([.hooks.CwdChanged[]?.hooks[]?.command] | any(test("cwd-changed"))) and ([.hooks.CwdChanged[]?.hooks[]?.command] | all(test("file-changed") | not))' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0021 — found by claude-infrastructure-330 (backlog e35329880deb) and owned here because the
# handler is this wave's (W3-E). Migration 0017 registered `file-changed.sh` into the **CwdChanged**
# slot across all five config dirs; measured 2026-09-07 that command is the ONLY thing in
# `.hooks.CwdChanged`, and `cwd-changed.sh` — built for this slot, landed, 24 tests, 14-site
# red-proof — is registered NOWHERE.
#
# WHY THAT IS A DEFECT AND NOT A COSMETIC PREFERENCE. Both handlers re-emit `watchPaths` on a
# CwdChanged payload, so the watch survives a `cd` either way. But `file-changed.sh` writes **no log
# row** on that path, and § 3e's failure class is exactly that `onCwdChanged` OVERWRITES the dynamic
# watch list with whatever the hooks return — so a re-arm that rebuilt an EMPTY list looks identical
# to one that never fired. `cwd-changed.sh` exists to close that: it logs one row per transition
# carrying the COUNT re-armed, **including the count-0 case**, which is the only row that
# distinguishes the two. The slot currently holds the emitter that cannot tell you which happened.
#
# WHY REPLACE AND NOT APPEND — and this is the part that makes a second emitter unsafe rather than
# merely redundant. `onCwdChanged` sets the watch list to what the hooks RETURN. With two emitters
# registered the result depends on provider N-hook resolution order (does it take the first
# non-empty stdout, the last, or union them?) — and § 3b lists that resolution order as
# EXPLICITLY UNSETTLED, deliberately unprobed because settling it empirically means registering a
# second observer on a live provider, which is the § 4 prohibition. So appending would make the
# fleet's watch list depend on an unknown. 330 correctly declined to append for this reason.
#
# WHY THE REPLACE IS SAFE, from a mechanical proof and not from inspection. `tests/cwd-changed.bats`
# carries an AGREEMENT arm: it writes one watchlist, feeds the same payload to BOTH handlers, and
# asserts `.hookSpecificOutput.watchPaths` is byte-identical. They share the file and the
# `CC_FILECHANGED_WATCHLIST` env seam, so the emission does not change — only the observability is
# added. Change either reader without the other and that arm goes red.
#
# FileChanged's own registrations are NOT touched: `file-changed.sh` stays in the FileChanged slot,
# where § 3e's arm/dispatch pair needs it. Only the CwdChanged slot is rewritten.
#
# WHY c10. It edits settings.json — staged, never self-run (migrations/README.md).
set -uo pipefail

# shellcheck disable=SC2088  # tildes are DELIBERATELY literal: stored INTO settings.json, where CC
# expands them at hook-run time. Expanding here hard-codes this machine's $HOME into five configs.
OLD_CMD='~/.claude/hooks/file-changed.sh'
# shellcheck disable=SC2088  # same literal-tilde reason; a directive binds to the NEXT construct
# only, so OLD_CMD's does not cover this line — the exact trap this repo's lint-directive memory names.
NEW_CMD='~/.claude/hooks/cwd-changed.sh'
NEW_FILE="$HOME/.claude/hooks/cwd-changed.sh"
rc=0

command -v jq >/dev/null 2>&1 || { printf '0021: jq required\n' >&2; exit 1; }

# Precondition re-derived at CONSUMPTION, not trusted from the header: a registration naming a path
# that does not run is a registered no-op, and it reads GREEN (MEMORY.md discovery-critic-premise-goes-stale).
if [ ! -x "$NEW_FILE" ]; then
  printf '0021: NOT applied — %s is missing or not executable.\n' "$NEW_FILE" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it (or deploy-live) first.\n' >&2
  exit 1
fi

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  if ! jq -e '.hooks.CwdChanged | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0021: %s — no CwdChanged array; skipped (0017 has not run here)\n' "$f"
    continue
  fi

  if jq -e --arg c "$NEW_CMD" '[.hooks.CwdChanged[]?.hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
    printf '0021: %s — already replaced\n' "$f"
    continue
  fi

  if ! jq -e --arg o "$OLD_CMD" '[.hooks.CwdChanged[]?.hooks[]?.command] | any(. == $o)' "$f" >/dev/null 2>&1; then
    printf '0021: %s — CwdChanged holds neither command; left ALONE for a human\n' "$f" >&2; rc=1; continue
  fi

  bak="$f.bak-0021-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0021: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0021-$$"
  # REPLACE in place, scoped to the CwdChanged subtree only — FileChanged's own entries are
  # untouched because the walk never leaves .hooks.CwdChanged.
  # shellcheck disable=SC2016  # $o/$c are JQ variables bound by --arg, not shell expansions
  if jq --arg o "$OLD_CMD" --arg c "$NEW_CMD" \
       '.hooks.CwdChanged |= map(.hooks |= map(if .command == $o then .command = $c else . end))' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # Verify BY CONTENT before it replaces the live file: the new command present, the old GONE from
    # this slot, FileChanged's own registrations intact, and the load-bearing arrays still there.
    if jq -e --arg o "$OLD_CMD" --arg c "$NEW_CMD" \
         '([.hooks.CwdChanged[]?.hooks[]?.command] | any(. == $c))
          and ([.hooks.CwdChanged[]?.hooks[]?.command] | any(. == $o) | not)
          and ([.hooks.FileChanged[]?.hooks[]?.command] | length) > 0
          and (.hooks.Stop | type == "array" and length > 0)
          and (.hooks.PreToolUse | type == "array" and length > 0)' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0021: %s — CwdChanged slot now runs cwd-changed.sh (backup: %s)\n' "$f" "$bak"
    else
      rm -f "$tmp"; printf '0021: %s — edit failed its content check; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0021: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

exit "$rc"
