#!/bin/bash
# migration-class: c10
# migration-step: register the three ready HOOK_SURFACE_100P observers (StopFailure, InstructionsLoaded, PostToolBatch) across the fleet config dirs — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0019-hook-surface-registration.sh
# migration-subject: ~/.claude/hooks/stop-failure-marker.sh ~/.claude/hooks/instructions-loaded.sh ~/.claude/hooks/post-tool-batch.sh
# migration-verify: jq -e '([.hooks.StopFailure[]?.hooks[]?.command] | any(test("stop-failure-marker"))) and ([.hooks.InstructionsLoaded[]?.hooks[]?.command] | any(test("instructions-loaded"))) and ([.hooks.PostToolBatch[]?.hooks[]?.command] | any(test("post-tool-batch")))' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0019 — the registration half of HOOK_SURFACE_100P's W3. Handlers landed across W3-A/B/C and have
# been INERT on disk ever since: measured 2026-09-07, all nine candidate events appear in ZERO
# settings files. This is the plan's own §2 gap — "landed is not wired, and wired is not live".
#
# WHY settings.json, WHEN §4 SAYS "a separate settings file, never ~/.claude/settings.json".
# Because that rule is not satisfiable and this was measured, not assumed. The obvious separate
# file — the user config dir's settings.local.json — is NOT READ as a hook source. Two zero-quota
# `--init-only` runs, each with an in-run control: control settings.json 1 row, target user-level
# settings.local.json 0 rows; a second run adding the project level gave <cfgdir>/settings.json 1,
# <project>/.claude/settings.json 1, <project>/.claude/settings.local.json 1. So hooks load from a
# PROJECT's settings files but not from the user-level local one, and these three are FLEET-WIDE
# consumers that a project-scoped file would leave dark everywhere else.
# Registering into a file CC does not read would have produced a hook that is registered and never
# fires — indistinguishable from success, which is this plan's own signature failure.
# Operator ruled it 2026-09-07 on decision packet ab82a67e2c37: "settings-json: register across the
# config dirs with the count assertion." The count assertion is item (2) below.
#
# WHAT IS DELIBERATELY *NOT* HERE, so a reader does not mistake absence for oversight:
#   · SubagentStop      — migration 0014 already stages exactly this registration. A second
#                         appender would double-register the same command.
#   · FileChanged       — needs the THREE-PART wiring of plan §3e (an absolute matcher to ARM, a
#     + CwdChanged        `*`/no-matcher sibling to DISPATCH, and a CwdChanged hook re-emitting
#                         watchPaths because onCwdChanged overwrites the watch list wholesale).
#                         hooks/cwd-changed.sh does not exist yet, and wiring FileChanged without
#                         its re-arm partner yields a watcher that silently empties on the first
#                         `cd` — worse than not wiring it. Separate migration once that lands.
#   · PermissionDenied, PostCompact, ConfigChange — promoted to WIRE by the W4 refutation pass
#                         AFTER the W3 waves were briefed, so they have no handlers yet.
#
# MATCHER CHOICES, and why each is not the default:
#   · InstructionsLoaded takes matcher "session_start". Its matcher is the load_reason field (NOT a
#     tool name), whose real values are session_start | nested_traversal | path_glob_match |
#     include | compact — read from the binary's own matcherMetadata literal. session_start is
#     BOUNDED at 2-4 rows/session; path_glob_match fires per file touched and is unbounded.
#   · StopFailure and PostToolBatch are matcher-less: StopFailure has no matcher dimension, and
#     PostToolBatch is deliberately match-all — it is the only tool-side observer that fires on a
#     batch containing a DENIED call.
#
# WHY c10. It edits settings.json. migrations/README.md: "A migration that touches settings.json, a
# launchd plist, or credentials declares c10 and waits for a human." Staged, never self-run.
set -uo pipefail

declare -a EV_NAME=( 'StopFailure'                          'InstructionsLoaded'                     'PostToolBatch' )
# shellcheck disable=SC2088  # tildes are DELIBERATELY literal: these strings are stored INTO
# settings.json, where CC expands them at hook-run time. Expanding here would hard-code this
# machine's $HOME into a config mirrored across five config dirs. (The directive binds to the NEXT
# construct, so it must sit immediately above EV_CMD — not above EV_NAME, which has no tildes.)
declare -a EV_CMD=(  '~/.claude/hooks/stop-failure-marker.sh' '~/.claude/hooks/instructions-loaded.sh' '~/.claude/hooks/post-tool-batch.sh' )
declare -a EV_FILE=( "$HOME/.claude/hooks/stop-failure-marker.sh" "$HOME/.claude/hooks/instructions-loaded.sh" "$HOME/.claude/hooks/post-tool-batch.sh" )
declare -a EV_MATCH=( ''                                     'session_start'                          '' )
declare -a EV_TMO=(  10                                      10                                       10 )
rc=0

command -v jq >/dev/null 2>&1 || { printf '0019: jq required\n' >&2; exit 1; }

# ── precondition, re-derived at CONSUMPTION rather than trusted from the header ──────────────────
# A migration's premise can rot between staging and the converge that reads it (MEMORY.md
# discovery-critic-premise-goes-stale). A registration naming a path that does not run is a
# registered no-op, and it reads GREEN.
for i in "${!EV_NAME[@]}"; do
  if [ ! -x "${EV_FILE[$i]}" ]; then
    printf '0019: NOT registered — %s is missing or not executable.\n' "${EV_FILE[$i]}" >&2
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
    printf '0019: %s — no Stop array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  bak=""
  for i in "${!EV_NAME[@]}"; do
    ev="${EV_NAME[$i]}"; cmd="${EV_CMD[$i]}"; mt="${EV_MATCH[$i]}"; tmo="${EV_TMO[$i]}"

    if jq -e --arg e "$ev" --arg c "$cmd" \
         '[.hooks[$e][]?.hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
      printf '0019: %s — %s already registered\n' "$f" "$ev"
      continue
    fi

    # ONE backup per file, taken before this file's first real edit.
    if [ -z "$bak" ]; then
      bak="$f.bak-0019-$(date +%Y%m%d%H%M%S)"
      cp -p "$f" "$bak" || { printf '0019: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; break; }
    fi

    tmp="$f.tmp-0019-$$"
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
        mv "$tmp" "$f" && printf '0019: %s — %s registered%s\n' "$f" "$ev" \
          "$( [ -n "$mt" ] && printf ' (matcher %s)' "$mt" )"
      else
        rm -f "$tmp"; printf '0019: %s — %s edit failed its content check; left unchanged\n' "$f" "$ev" >&2; rc=1
      fi
    else
      rm -f "$tmp"; printf '0019: %s — %s jq edit FAILED; left unchanged\n' "$f" "$ev" >&2; rc=1
    fi
  done
  [ -n "$bak" ] && printf '0019: %s — backup: %s\n' "$f" "$bak"
done

exit "$rc"
