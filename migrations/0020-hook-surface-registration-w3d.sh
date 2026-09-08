#!/bin/bash
# migration-class: c10
# migration-step: register the three W3-D observers (PermissionDenied, PostCompact, ConfigChange) across the fleet config dirs — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0020-hook-surface-registration-w3d.sh
# migration-subject: ~/.claude/hooks/permission-denied.sh ~/.claude/hooks/post-compact.sh ~/.claude/hooks/config-change.sh
# migration-verify: jq -e '([.hooks.PermissionDenied[]?.hooks[]?.command] | any(test("permission-denied"))) and ([.hooks.PostCompact[]?.hooks[]?.command] | any(test("post-compact"))) and ([.hooks.ConfigChange[]?.hooks[]?.command] | any(test("config-change")))' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0020 — the registration half of W3-D, and the reason it exists at all is a CLOSE-TIME DEFECT worth
# recording. W3-D landed three handlers + three bats suites (426d5da66). They sat on disk, inert, and
# the session that measured the whole surface tried to close by saying the remainder "is all on disk
# in the plan and picks up cleanly in a fresh session". The operator's reply is the finding:
# **no session is going to randomly know to pick it up.** A plan is an ADVISORY store — writing into
# it always succeeds and reading out of it is discretionary — which is precisely the diode
# migrations/README.md says this directory exists to end. Measured at that moment: 0 backlog rows
# named this registration. It was queued NOWHERE.
#
# WHY THESE THREE AND NOT MORE. StopFailure/InstructionsLoaded/PostToolBatch are already registered
# (migration 0019, run 2026-09-07). FileChanged and CwdChanged were registered by a sibling as § 3e's
# arm/dispatch pair. SubagentStop remains staged under migration 0014 and is deliberately left there
# — a second appender would double-register the same command.
#
# 🚨 TWO ADOPTION CONSTRAINTS THAT ARE NOT STYLE. Both handlers were written to honour them; this
# header records them so a future edit cannot quietly break one:
#   · PermissionDenied's output schema is {hookEventName, retry:boolean} and **retry:true RE-OFFERS
#     the denied call**. Its handler must emit EMPTY stdout. A stray echo silently re-drives work the
#     classifier refused.
#   · ConfigChange is DECISION-class. A handler that writes to stdout silently freezes config/skill
#     hot-reload for the whole session.
# All three are registered MATCHER-LESS: PermissionDenied takes a tool-name matcher and we want every
# denial, not one tool's.
#
# WHY c10. It edits settings.json — staged, never self-run (migrations/README.md).
set -uo pipefail

declare -a EV_NAME=( 'PermissionDenied'                     'PostCompact'                     'ConfigChange' )
# shellcheck disable=SC2088  # tildes are DELIBERATELY literal: these strings are stored INTO
# settings.json, where CC expands them at hook-run time. Expanding here would hard-code this
# machine's $HOME into a config mirrored across five config dirs. (The directive binds to the NEXT
# construct, so it must sit immediately above EV_CMD — not above EV_NAME, which has no tildes.)
declare -a EV_CMD=(  '~/.claude/hooks/permission-denied.sh'   '~/.claude/hooks/post-compact.sh' '~/.claude/hooks/config-change.sh' )
declare -a EV_FILE=( "$HOME/.claude/hooks/permission-denied.sh" "$HOME/.claude/hooks/post-compact.sh" "$HOME/.claude/hooks/config-change.sh" )
declare -a EV_MATCH=( ''                                     ''                                ''             )
declare -a EV_TMO=(  10                                      10                                       10 )
rc=0

command -v jq >/dev/null 2>&1 || { printf '0020: jq required\n' >&2; exit 1; }

# ── precondition, re-derived at CONSUMPTION rather than trusted from the header ──────────────────
# A migration's premise can rot between staging and the converge that reads it (MEMORY.md
# discovery-critic-premise-goes-stale). A registration naming a path that does not run is a
# registered no-op, and it reads GREEN.
for i in "${!EV_NAME[@]}"; do
  if [ ! -x "${EV_FILE[$i]}" ]; then
    printf '0020: NOT registered — %s is missing or not executable.\n' "${EV_FILE[$i]}" >&2
    printf '      hooks/ is symlinked into the live layer by install.sh; run it (or deploy-live) first.\n' >&2
    exit 1
  fi
done

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Fleet discriminator borrowed from an event every fleet config already runs. Testing for one of
  # OUR three would be false everywhere and skip all five — a migration that always succeeds by
  # doing nothing (0014's header makes the same point).
  if ! jq -e '.hooks.Stop | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0020: %s — no Stop array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  bak=""
  for i in "${!EV_NAME[@]}"; do
    ev="${EV_NAME[$i]}"; cmd="${EV_CMD[$i]}"; mt="${EV_MATCH[$i]}"; tmo="${EV_TMO[$i]}"

    if jq -e --arg e "$ev" --arg c "$cmd" \
         '[.hooks[$e][]?.hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
      printf '0020: %s — %s already registered\n' "$f" "$ev"
      continue
    fi

    # ONE backup per file, taken before this file's first real edit.
    if [ -z "$bak" ]; then
      bak="$f.bak-0020-$(date +%Y%m%d%H%M%S)"
      cp -p "$f" "$bak" || { printf '0020: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; break; }
    fi

    tmp="$f.tmp-0020-$$"
    # `.hooks[$e] //= []` then APPEND: creates the array when absent and appends when a sibling is
    # already there, so this can never clobber a consumer it did not write.
    # shellcheck disable=SC2016  # $e/$c/$m/$t are JQ variables bound by --arg below, not shell
    # expansions. Double-quoting here would let the shell eat them before jq ever sees them.
    if [ -n "$mt" ]; then
      jq_expr='.hooks[$e] //= [] | .hooks[$e] += [{"matcher":$m,"hooks":[{"type":"command","command":$c,"timeout":$t}]}]'
    else
      jq_expr='.hooks[$e] //= [] | .hooks[$e] += [{"hooks":[{"type":"command","command":$c,"timeout":$t}]}]'
    fi

    if jq --arg e "$ev" --arg c "$cmd" --arg m "$mt" --argjson t "$tmo" "$jq_expr" \
         "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
      # verify BY CONTENT before it replaces the live file — and re-assert that the OTHER hook
      # arrays survived, because the failure this whole plan is about is a settings file that
      # silently stops running everything it holds.
      if jq -e --arg e "$ev" --arg c "$cmd" \
           '([.hooks[$e][]?.hooks[]?.command] | any(. == $c))
            and (.hooks.Stop | type == "array" and length > 0)
            and (.hooks.PreToolUse | type == "array" and length > 0)' "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$f" && printf '0020: %s — %s registered%s\n' "$f" "$ev" \
          "$( [ -n "$mt" ] && printf ' (matcher %s)' "$mt" )"
      else
        rm -f "$tmp"; printf '0020: %s — %s edit failed its content check; left unchanged\n' "$f" "$ev" >&2; rc=1
      fi
    else
      rm -f "$tmp"; printf '0020: %s — %s jq edit FAILED; left unchanged\n' "$f" "$ev" >&2; rc=1
    fi
  done
  [ -n "$bak" ] && printf '0020: %s — backup: %s\n' "$f" "$bak"
done

exit "$rc"
