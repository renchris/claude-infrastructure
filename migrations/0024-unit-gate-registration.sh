#!/bin/bash
# migration-class: c10
# migration-step: register hooks/unit-gate.sh as the FIRST PreToolUse entry with matcher "*" in every fleet config dir — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0024-unit-gate-registration.sh
# migration-subject: ~/.claude/hooks/unit-gate.sh
# migration-verify: bash ~/Development/claude-infrastructure/migrations/0024-unit-gate-registration.sh --verify
# migration-conflict: bash ~/Development/claude-infrastructure/migrations/0024-unit-gate-registration.sh --conflict
#
# 0024 — THERE IS NO KILL SWITCH FOR AN IN-PROCESS UNIT, AND THE REASON IS ONE MISSING MATCHER.
#
# docs/research/oversight-at-scale-2026-08-19.md §5.2. Backlog ad37b0296a56.
#
#   N18, re-measured 2026-09-09 (three weeks after filing, still true): the PreToolUse chain carries
#   `Bash` 9 hooks, `Write|Edit|MultiEdit` 3, `Agent` 2, `AskUserQuestion` 1, an ms365 matcher, and
#   in one dir `WebFetch|WebSearch`. **No `*` matcher exists in any of the four config dirs.** So
#   every tool call a Workflow agent, a subagent or any paneless class makes on `Read`, `Grep`,
#   `Glob`, `Task` or `Workflow` traverses ZERO hooks. This is additive, not a rewrite.
#
#   N17: our `Agent` spawn matcher fires **0 times** for `agent()`, so a spawn gate cannot reach the
#   class at all. N16: PreToolUse DOES fire for a Workflow agent's own calls and a deny there brakes
#   it mid-run and beats `bypassPermissions`. The chokepoint is tool granularity, and only `*`
#   reaches every class that traverses it.
#
# WHY FIRST IN THE CHAIN, NOT APPENDED. The brake's whole value is that it lands before the work
# does. A `Bash` call already traverses 9 hooks; several of them fork, read the IDL, or take a lease.
# A brake that runs tenth has already let the chain spend its cost on a unit the operator has told
# to stop. Prepending is also what makes the cost claim honest: on `Bash` this is +11% on an
# existing chain, and on `Read`/`Grep`/`Task`/`Workflow` it is a new ~3 ms fork where there was none
# (N19: p50 2.85 ms · p90 3.12 ms · max 3.80 ms, n=60).
#
# 🚨 WHY c10 AND NOT mechanical. This edits settings.json — the C10 class, staged and never run by
# the converger. It is also the single most blast-radius-laden hook registration this repo has ever
# staged: a `*` matcher sees EVERY tool call of EVERY class in EVERY session on this machine. The
# operator runs it deliberately, having read that sentence.
#
# FALSIFIER. If `~/.claude/logs/units.jsonl` is still absent 48 h after this runs, either no
# in-process unit has made a tool call, or `agent_id` is not on the payload in this build — and the
# namespace §5.3 depends on it being there. Check with `cc-halt list`, not by assuming.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '0024: jq required\n' >&2; exit 1; }

# shellcheck disable=SC2088  # tilde LITERAL by design; see the comment on this line
CMD='~/.claude/hooks/unit-gate.sh'   # tilde LITERAL — CC expands it at hook-run time. Expanding it
                                     # here would freeze this machine's $HOME into mirrored configs.
MATCHER='*'
TMO=5
FILE='unit-gate.sh'
CONFIG_DIRS=("$HOME/.claude" "$HOME/.claude-next" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary")

# ── verify ──────────────────────────────────────────────────────────────────────────────────────
# ONE config dir per call: registration-state.sh re-runs each verifier once per dir with
# CC_CLAUDE_DIR re-aimed, and everything here lives in that dir's settings.json. Looping all five
# would report `live` off any single dir and make the per-dir `partial` unreachable.
#
# It asserts POSITION, not just presence. "Registered somewhere in the chain" is a different
# guarantee from the one the comment above argues for, and a verifier that could not tell them apart
# would report `live` over a brake that runs tenth.
verify_one() {
  local f="${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json"
  [ -f "$f" ] || { printf '0024 --verify: %s absent\n' "$f" >&2; return 1; }
  jq -e --arg m "$MATCHER" --arg c "$CMD" \
     '(.hooks.PreToolUse // []) | (length > 0)
        and (.[0].matcher == $m)
        and ([.[0].hooks[]?.command] | any(. == $c))' "$f" >/dev/null 2>&1 && return 0
  printf '0024 --verify: %s — unit-gate.sh is not the FIRST PreToolUse entry (first matcher is %s)\n' \
    "$f" "$(jq -c '(.hooks.PreToolUse // [])[0].matcher // "NONE"' "$f" 2>/dev/null)" >&2
  return 1
}

# ── conflict ────────────────────────────────────────────────────────────────────────────────────
# `overridden` = a DIFFERENT command sits at the same key. Declared because it is genuinely
# possible: a `*` matcher is the natural home for any future fleet-wide gate, and a second one
# landing at index 0 would silently displace the brake to second place.
conflict_one() {
  local f="${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json"
  [ -f "$f" ] || return 1
  jq -e --arg m "$MATCHER" --arg c "$CMD" \
     '[(.hooks.PreToolUse // [])[] | select(.matcher == $m)] as $s
      | ($s | length > 0) and ([$s[].hooks[]?.command] | any(. == $c) | not)' "$f" >/dev/null 2>&1
}

case "${1:-}" in
  --verify)   verify_one;   exit $? ;;
  --conflict) conflict_one; exit $? ;;
esac

# ── precondition, re-derived at CONSUMPTION rather than trusted ──────────────────────────────────
# A registration naming a path that does not run is a registered no-op, and it reads GREEN
# (MEMORY: registration-precondition-must-assert-version-not-executability). For a `*` matcher the
# failure is worse than green-but-inert: CC would fork a missing file on every tool call.
if [ ! -x "$HOME/.claude/hooks/$FILE" ]; then
  printf '0024: NOT registered — %s/.claude/hooks/%s is missing or not executable.\n' "$HOME" "$FILE" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it (or deploy-live) first.\n' >&2
  exit 1
fi
# ...and it must actually behave. A `*` matcher over a hook that denies unconditionally brakes the
# whole machine, and settings.json is the only cure — itself a tool call. The gate ships an oracle
# for exactly this; refuse to register if it cannot pass.
if [ -x "$HOME/.claude/bin/cc-halt" ]; then
  if ! "$HOME/.claude/bin/cc-halt" --selftest >/dev/null 2>&1; then
    # shellcheck disable=SC2016  # backticks are PROSE here, not a command substitution
    printf '0024: NOT registered — cc-halt --selftest FAILED. A `*` matcher over a misbehaving gate\n' >&2
    printf '      brakes every tool call on this machine, and settings.json is the only cure.\n' >&2
    exit 1
  fi
else
  printf '0024: NOT registered — %s/.claude/bin/cc-halt absent; the gate would land with no lever\n' "$HOME" >&2
  exit 1
fi

rc=0
for dir in "${CONFIG_DIRS[@]}"; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Fleet discriminator borrowed from an array every fleet config already has — testing for OUR
  # entry would be false in exactly the dirs that need the edit.
  if ! jq -e '.hooks.PreToolUse | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0024: %s — no PreToolUse array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  if jq -e --arg m "$MATCHER" --arg c "$CMD" \
       '(.hooks.PreToolUse[0].matcher == $m) and ([.hooks.PreToolUse[0].hooks[]?.command] | any(. == $c))' \
       "$f" >/dev/null 2>&1; then
    printf '0024: %s — already FIRST\n' "$f"
    continue
  fi

  bak="$f.bak-0024-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0024: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0024-$$"
  # Remove any prior copy of OUR entry, then PREPEND. The delete-then-prepend order is what makes
  # this idempotent and self-correcting: re-running after a later `*` gate displaced us restores
  # first position without ever duplicating the row (MEMORY: denylist-enumerates-spellings — a
  # guard that can only append cannot repair the state it is supposed to own).
  # shellcheck disable=SC2016  # $m/$c/$t are jq variables bound by --arg/--argjson.
  jq --arg m "$MATCHER" --arg c "$CMD" --argjson t "$TMO" '
      .hooks.PreToolUse = (
        [ { matcher: $m, hooks: [ { type: "command", command: $c, timeout: $t } ] } ]
        + [ (.hooks.PreToolUse // [])[]
            | select( (.matcher != $m) or ([.hooks[]?.command] | any(. == $c) | not) ) ]
      )' "$f" > "$tmp" 2>/dev/null || { rm -f "$tmp"; printf '0024: %s — jq FAILED\n' "$f" >&2; rc=1; continue; }

  # Content check before the swap, and it re-asserts the file's OTHER arrays survived: a settings
  # edit that lands valid JSON having dropped .hooks.Stop is the worst outcome available here.
  if [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1 \
     && jq -e --arg m "$MATCHER" --arg c "$CMD" \
          '(.hooks.PreToolUse[0].matcher == $m)
             and ([.hooks.PreToolUse[0].hooks[]?.command] | any(. == $c))
             and ([.hooks.PreToolUse[] | select(.matcher == $m)] | length == 1)' "$tmp" >/dev/null 2>&1 \
     && jq -e '(.hooks.Stop | type == "array" and length > 0)
               and (.hooks.PreToolUse | length >= 2)' "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$f"
    printf '0024: %s — unit-gate.sh registered FIRST on matcher "%s" (backup: %s)\n' "$f" "$MATCHER" "$bak"
  else
    rm -f "$tmp"
    printf '0024: %s — edit FAILED its content check; left unchanged (backup: %s)\n' "$f" "$bak" >&2
    rc=1
  fi
done

exit "$rc"
