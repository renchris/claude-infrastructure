#!/bin/bash
# migration-class: c10
# migration-step: turn the Task tools on fleet-wide (CLAUDE_CODE_ENABLE_TODO_TOOLS=1) and register TaskCreated -> task-created-attrib.sh + StopFailure -> session-beat.sh stop — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0023-todo-tools-and-task-hooks.sh
# migration-subject: ~/.claude/hooks/task-created-attrib.sh
# migration-verify: bash ~/Development/claude-infrastructure/migrations/0023-todo-tools-and-task-hooks.sh --verify
#
# 0023 — THE SHARED TASK LIST IS BUILT, SHARED, AND SWITCHED OFF.
#
# Three separate facts wearing one name, all measured 2026-09-08 (docs/research/
# exhaustive-drive-2026-09-08/A03-shared-task-list.md, re-run in its .skeptic.md):
#
#   1. The TOOLS are off. `pM()` @163543861 enables the Task family iff the session is background/
#      daemon, OR the model predates the cutoff, OR `CLAUDE_CODE_ENABLE_TODO_TOOLS===true`, OR the
#      remote flag `tengu_rosy_wren` — and that flag is ABSENT from all five GrowthBook caches, so
#      the env var is the only lever this machine has. Measured absent from the `env` block of all
#      FIVE settings.json (5/5 `ABSENT`), which are five separate inodes.
#   2. The STORE is already shared. All five config dirs' `tasks/` realpath to /Users/chrisren/
#      .claude/tasks (measured ×5). Nothing here needs to move it.
#   3. Nothing writes down WHO opened an item. `TaskCreate` sets `owner: void 0` (@164041206);
#      10 of 293 open items (3.4%) carry `metadata.owner_session`, all ten hand-written.
#
# WHAT THIS MIGRATION DOES, AND WHY EACH PART IS HERE
#
# (a) `"CLAUDE_CODE_ENABLE_TODO_TOOLS": "1"` in the `env` block of all five config dirs. Measured
#     A/B on 2.1.260 + opus-5: the flag adds exactly TaskCreate/TaskGet/TaskList/TaskUpdate and
#     nothing else, via the environment AND via settings `env` (probe C). Cost +26 tokens, because
#     all four carry `shouldDefer:!0` — only the NAME is in context until the model ToolSearches.
#     `env` is the right surface and the launcher is the wrong one: a shell-profile edit misses
#     `claude -p`, `--bg`, daemon, cron and resumed sessions whose env was lost, and it trips
#     `autoMode.soft_deny` "Unauthorized Persistence".
#
# 🚨 (a') `CLAUDE_CODE_ENABLE_TASKS` IS DELIBERATELY NOT TOUCHED. It is a KILL switch, default ON —
#     `$_()` @159792244 is `if(a.CLAUDE_CODE_ENABLE_TASKS===!1)return!1;return!0`. Setting it false
#     swaps the disk-backed Task family for `TodoWrite`, whose `isEnabled` is `!$_()&&pM()` and
#     which writes to IN-MEMORY app state, not to ~/.claude/tasks. Setting it "true" is a no-op at
#     best. Either way the fleet would end up with a tracker no Stop hook can read, which is the
#     defect this migration exists to end.
#
# (b) `TaskCreated -> hooks/task-created-attrib.sh`. `TaskCreated` is a real event in this build
#     (event list @156773548) that our settings register NOWHERE — its payload carries `session_id`
#     AND `task_id` in one object (@157890649), the attribution join that has no field on disk.
#
# (c) `StopFailure -> hooks/session-beat.sh stop`. No beat writer runs on StopFailure today, so a
#     session that dies at a Stop leaves `kind=prompt` standing on a still-live pid and the
#     liveness surfaces read it as BUSY — measured, 9 markers over 5 sids, 2 reading falsely BUSY.
#     The timeout and argument are COPIED from the existing Stop registration (`session-beat.sh
#     stop`, timeout 5), not re-derived: a second spelling here would be a second source of truth
#     that cannot learn the first one changed.
#
# WHY c10. It edits settings.json — staged, never self-run (migrations/README.md). The rescope of
# C10 from "operator runs" to "operator can revert" is the one clause the inertness doc says a human
# must ratify, and it has not been ratified.
#
# NUMBERING. The brief that commissioned this said 0022; `0022-mitl-decider-shadow.sh` landed on
# origin/main first (f3402d860), so this is 0023. Migrations run in LEXICAL order and nothing here
# depends on 0022, so the collision would have been harmless — it is avoided because a duplicate
# prefix makes `--status` ambiguous to read, which is how 0009/0016/0021 already read today.
#
# FALSIFIER FOR THE PART A MIGRATION CANNOT DO. Enabling a deferred tool does not make the model
# use it. If `count(tasks created after this migration runs) == 0` within 48 h, the flip landed a
# switch and nothing else, and the adoption half (a CLAUDE.md clause naming the tools) is the real
# remaining work. This migration is not evidence that anyone tracks anything.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '0023: jq required\n' >&2; exit 1; }

ENV_KEY="CLAUDE_CODE_ENABLE_TODO_TOOLS"
ENV_VAL="1"

# event · command · timeout · the hook file the command needs on disk. Both rows are matcher-less,
# which is what the fleet already does for both events (StopFailure carries stop-failure-marker.sh
# with no matcher in all five dirs), so there is no matcher field to get wrong.
# The tilde is DELIBERATELY literal — CC expands it at hook-run time; expanding it here would
# hard-code this machine's $HOME into five mirrored configs (0021's lesson, same shape).
# shellcheck disable=SC2088
declare -a ROWS=(
  'TaskCreated|~/.claude/hooks/task-created-attrib.sh|5|task-created-attrib.sh'
  'StopFailure|~/.claude/hooks/session-beat.sh stop|5|session-beat.sh'
)
_row() { local IFS='|'; read -r EV CMD TMO FILE <<<"$1"; }

CONFIG_DIRS=("$HOME/.claude" "$HOME/.claude-next" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary")

# ── verify ──────────────────────────────────────────────────────────────────────────────────────
# ONE config dir per call: `scripts/registration-state.sh` re-runs each verifier once per config dir
# with CC_CLAUDE_DIR re-aimed, and everything this migration writes lives in that dir's
# settings.json. A verifier that looped all five here would report `live` from any single dir and
# make the per-dir loop's `partial` unreachable.
verify_one() {
  local f="${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" row miss=0 have
  [ -f "$f" ] || { printf '0023 --verify: %s absent\n' "$f" >&2; return 1; }

  jq -e --arg k "$ENV_KEY" --arg v "$ENV_VAL" '.env[$k] == $v' "$f" >/dev/null 2>&1 \
    || { printf '0023 --verify: %s — env.%s is %s, expected "%s"\n' "$f" "$ENV_KEY" \
           "$(jq -c --arg k "$ENV_KEY" '.env[$k] // "ABSENT"' "$f" 2>/dev/null)" "$ENV_VAL" >&2; miss=1; }

  have="$(jq -r '.hooks // {} | to_entries[] | .key as $e | (.value // [])[]? | (.hooks // [])[]? | "\($e)|\(.command)"' "$f" 2>/dev/null)" || return 1
  for row in "${ROWS[@]}"; do
    _row "$row"
    grep -qxF -- "$EV|$CMD" <<<"$have" \
      || { printf '0023 --verify: %s — NOT registered: %s|%s\n' "$f" "$EV" "$CMD" >&2; miss=1; }
  done
  [ "$miss" -eq 0 ]
}

if [ "${1:-}" = "--verify" ]; then verify_one; exit $?; fi

# ── precondition, re-derived at CONSUMPTION rather than trusted from the header ──────────────────
# A registration naming a path that does not run is a registered no-op, and it reads GREEN
# (memory: registration-precondition-must-assert-version-not-executability).
for row in "${ROWS[@]}"; do
  _row "$row"
  if [ ! -x "$HOME/.claude/hooks/$FILE" ]; then
    printf '0023: NOT registered — %s/.claude/hooks/%s is missing or not executable.\n' "$HOME" "$FILE" >&2
    printf '      hooks/ is symlinked into the live layer by install.sh; run it (or deploy-live) first.\n' >&2
    exit 1
  fi
done

rc=0
for dir in "${CONFIG_DIRS[@]}"; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Fleet discriminator borrowed from an event every fleet config already runs — testing for one of
  # OUR two rows would be false in exactly the dirs that need the edit.
  if ! jq -e '.hooks.Stop | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0023: %s — no Stop array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  bak=""
  _backup() { # README rule 4: veto-after only works if the prior state survives.
    [ -n "$bak" ] && return 0
    bak="$f.bak-0023-$(date +%Y%m%d%H%M%S)"
    cp -p "$f" "$bak" || { printf '0023: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; bak=""; return 1; }
    return 0
  }

  _commit() { # <tmp> <content-check jq expr, extra args after --> ; re-asserts the file still holds its other arrays
    local tmp="$1"; shift
    if [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1 \
       && jq -e "$@" "$tmp" >/dev/null 2>&1 \
       && jq -e '(.hooks.Stop | type == "array" and length > 0)
                 and (.hooks.PreToolUse | type == "array" and length > 0)
                 and ((.env // {}) | length > 0)' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f"; return 0
    fi
    rm -f "$tmp"; return 1
  }

  # ── (a) the env flag ──────────────────────────────────────────────────────────────────────────
  if jq -e --arg k "$ENV_KEY" --arg v "$ENV_VAL" '.env[$k] == $v' "$f" >/dev/null 2>&1; then
    printf '0023: %s — env.%s already "%s"\n' "$f" "$ENV_KEY" "$ENV_VAL"
  else
    if _backup; then
      tmp="$f.tmp-0023-$$"
      # `.env //= {}` then SET one key: creates the block when absent, and can never drop a sibling.
      # shellcheck disable=SC2016  # $k/$v are jq variables bound by --arg below.
      if jq --arg k "$ENV_KEY" --arg v "$ENV_VAL" '.env //= {} | .env[$k] = $v' "$f" > "$tmp" 2>/dev/null \
         && _commit "$tmp" --arg k "$ENV_KEY" --arg v "$ENV_VAL" '.env[$k] == $v'; then
        printf '0023: %s — env.%s set to "%s"\n' "$f" "$ENV_KEY" "$ENV_VAL"
      else
        printf '0023: %s — env.%s edit FAILED its content check; left unchanged\n' "$f" "$ENV_KEY" >&2; rc=1
      fi
    fi
  fi

  # ── (b)+(c) the two hook registrations ────────────────────────────────────────────────────────
  for row in "${ROWS[@]}"; do
    _row "$row"

    if jq -e --arg e "$EV" --arg c "$CMD" \
         '[.hooks[$e][]?.hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
      printf '0023: %s — %s|%s already registered\n' "$f" "$EV" "$CMD"
      continue
    fi

    _backup || continue
    tmp="$f.tmp-0023-$$"
    # `.hooks[$e] //= []` then APPEND — creates the array when absent, appends when a sibling is
    # already there (StopFailure already carries stop-failure-marker.sh in all five dirs), so this
    # can never clobber a consumer it did not write.
    # shellcheck disable=SC2016  # $e/$c/$t are jq variables bound by --arg/--argjson below.
    jq_expr='.hooks[$e] //= [] | .hooks[$e] += [{"hooks":[{"type":"command","command":$c,"timeout":$t}]}]'

    # shellcheck disable=SC2016  # same: the expression is jq's, not the shell's.
    if jq --arg e "$EV" --arg c "$CMD" --argjson t "$TMO" "$jq_expr" "$f" > "$tmp" 2>/dev/null \
       && _commit "$tmp" --arg e "$EV" --arg c "$CMD" '[.hooks[$e][]?.hooks[]?.command] | any(. == $c)'; then
      printf '0023: %s — %s registered (%s)\n' "$f" "$EV" "$CMD"
    else
      printf '0023: %s — %s registration FAILED its content check; left unchanged\n' "$f" "$EV" >&2; rc=1
    fi
  done

  [ -n "$bak" ] && printf '0023: %s — backup: %s\n' "$f" "$bak"
done

exit "$rc"
