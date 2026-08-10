#!/bin/bash
# migration-class: c10
# migration-step: register hooks/coldcompile-admit.sh as a PreToolUse(Bash) hook so cold compiles are admission-serialised — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0006-coldcompile-admit-registration.sh
# migration-subject: ~/.claude/hooks/coldcompile-admit.sh
# migration-verify: jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | any(. == "~/.claude/hooks/coldcompile-admit.sh")' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0006 — the registration half of Wave C's cold-compile admission serializer.
# Subject: hooks/coldcompile-admit.sh · bin/cc-ignition-gate · config/coldcompile.patterns
#          tests/coldcompile-admit.bats (27/27, 4 mutation controls)
# Finding: docs/plans/CONCURRENCY_PROGRAM.md §S6.5 · docs/research/crash-rootcause-2026-08-09.md
#
# WHAT IT FIXES. Six kernel panics on this box, all ignited by a dev-toolchain burst — `next dev`
# cold compile, `next-server` postcss worker pools — never by session count. Measured storm shape:
# 18→372 procs in 90 s · 700 procs / 38.9 GB · 736 / 44.7 GB. At the concurrency program's design
# point of 150 resident sessions the entire burst budget is ~19 GB against a measured 372-proc wave
# at ~23 GB, so there is no room for even ONE unbounded cold compile. The compressor sentinel
# (armed 2026-08-09) SIGSTOPs the horde only AFTER segments climb, with ~10 s of exposure on a
# >400-member wave: it is the backstop. This hook is the fix, and until it is registered the fix is
# a file nobody executes.
#
# WHY c10 AND NOT mechanical. `settings.json` is the live permission/hook surface of every account,
# and §3's rescope of C10 — "operator RUNS" becomes "operator CAN REVERT" — is the one clause
# migrations/README.md says a human must ratify, once. That ratification has not happened, so this
# migration STAGES: the runner files it to `cc-backlog needs` (event-keyed, folded onto one id) and
# never executes the body. The day the operator ratifies, `c10` becomes `mechanical` on line 2 and
# the converger takes it over — a one-word diff, no rewrite, no second author.
#
# THE BLAST RADIUS, STATED PLAINLY, BECAUSE IT IS A SPAWN-PATH HOOK. Registering this makes a hook
# run on EVERY agent Bash call box-wide. Three independent things bound that:
#   1. It emits for a matched command only, and its match is calibrated against the live corpus
#      (145 of 49,510 entries — 0.3%). Everything else costs one bounded read and an exit 0.
#   2. Every path in the hook and in the gate exits 0. A missing table, an unresolvable gate, an
#      unreadable `ps`, an exhausted wait budget — all ADMIT. It cannot strand a command by
#      refusing one; the worst it can do is stagger one by up to CC_IGNITION_WAIT_S (90 s default,
#      deliberately under the Bash tool's 120 s default timeout).
#   3. Three independent off-switches, none of which needs a code change or a re-registration:
#      CC_COLDCOMPILE_ADMIT=off (hook) · CC_IGNITION_GATE=off (gate) · deleting a table row.
#
# TO REVERT: re-run with --undo, or delete the entry from the Bash matcher group by hand. The
# per-dir backup this writes is the same shape 0005 uses.
set -uo pipefail

# shellcheck disable=SC2088  # the tilde is DELIBERATELY literal: this string is stored INTO
# settings.json, where CC expands it at hook-run time. Every sibling Bash entry is written the same
# way. Expanding it here would hard-code this machine's absolute $HOME into a config that is
# mirrored across four config dirs.
HOOK_CMD='~/.claude/hooks/coldcompile-admit.sh'
CLAUDE_DIR="${CC_CLAUDE_DIR:-$HOME/.claude}"
HOOK_FILE="$CLAUDE_DIR/hooks/coldcompile-admit.sh"
TIMEOUT=10
UNDO=0
[ "${1:-}" = "--undo" ] && UNDO=1
rc=0

command -v jq >/dev/null 2>&1 || { printf '0006: jq required\n' >&2; exit 1; }

# ── preconditions, re-derived at CONSUMPTION rather than trusted from the header ────────────────
# A migration's premise can rot between staging and the converge that reads it
# (MEMORY.md discovery-critic-premise-goes-stale). Both halves are checked, because a registration
# naming a path that does not execute is a registered no-op — and a registered no-op reads GREEN.
if [ "$UNDO" -eq 0 ]; then
  if [ ! -x "$HOOK_FILE" ]; then
    printf '0006: NOT registered — %s is missing or not executable.\n' "$HOOK_FILE" >&2
    printf '      hooks/ is symlinked into the live layer by install.sh; run it first.\n' >&2
    exit 1
  fi
  # The hook resolves the gate through its OWN physical path, so the gate is reached in the
  # checkout even before bin/ acquires a live symlink. Assert it there, the way the hook will.
  _self="$HOOK_FILE"; _hops=0
  while [ -L "$_self" ] && [ "$_hops" -lt 20 ]; do
    _d=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd) || break
    _self=$(readlink "$_self") || break
    case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac
    _hops=$((_hops + 1))
  done
  _dir=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd) || _dir=""
  if [ -z "$_dir" ] || [ ! -x "$_dir/../bin/cc-ignition-gate" ] || [ ! -r "$_dir/../config/coldcompile.patterns" ]; then
    printf '0006: NOT registered — the hook resolves to %s, where bin/cc-ignition-gate or\n' "${_dir:-?}" >&2
    printf '      config/coldcompile.patterns is missing. Registering it there would be inert.\n' >&2
    exit 1
  fi
fi

for dir in "$HOME"/.claude "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Only touch a config that already runs the sibling Bash hooks. A settings.json with no Bash
  # matcher group is not a fleet config, and inventing one here would be a scope this migration
  # never claimed.
  if ! jq -e '[.hooks.PreToolUse[]? | select(.matcher? // "" | test("Bash"))] | length > 0' "$f" >/dev/null 2>&1; then
    printf '0006: %s — no PreToolUse Bash group; skipped (not a fleet config)\n' "$f"
    continue
  fi

  present=0
  jq -e --arg c "$HOOK_CMD" '[.hooks.PreToolUse[]?.hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1 && present=1

  if [ "$UNDO" -eq 0 ] && [ "$present" -eq 1 ]; then
    printf '0006: %s — already registered\n' "$f"; continue
  fi
  if [ "$UNDO" -eq 1 ] && [ "$present" -eq 0 ]; then
    printf '0006: %s — not registered; nothing to undo\n' "$f"; continue
  fi

  bak="$f.bak-0006-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0006: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0006-$$"
  if [ "$UNDO" -eq 0 ]; then
    # Append to the FIRST group whose matcher mentions Bash. Position within the group is not
    # load-bearing: this hook is disjoint from qos-rewrite.sh by construction (it declines every
    # command shape qos can rewrite), which is precisely why the design does not have to know
    # whether two updatedInput emissions resolve first-wins, last-wins, or not at all — a question
    # that is UNDOCUMENTED on 2.1.220 and was checked before this was written.
    # shellcheck disable=SC2016  # $i and $c are JQ variables, not shell ones — expansion here
    # would substitute the shell's (empty) values into the program and silently no-op the edit.
    prog='(.hooks.PreToolUse | map(.matcher? // "" | test("Bash")) | index(true)) as $i
          | if $i == null then . else .hooks.PreToolUse[$i].hooks += [{"type":"command","command":$c,"timeout":$t}] end'
    want=1
  else
    # shellcheck disable=SC2016  # $c is a JQ variable — see above.
    prog='.hooks.PreToolUse |= map(.hooks |= map(select(.command != $c)))'
    want=0
  fi

  if jq --arg c "$HOOK_CMD" --argjson t "$TIMEOUT" "$prog" "$f" > "$tmp" 2>/dev/null \
     && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # verify the edit BY CONTENT before it replaces the live file — a count is not evidence
    got=0
    jq -e --arg c "$HOOK_CMD" '[.hooks.PreToolUse[]?.hooks[]?.command] | any(. == $c)' "$tmp" >/dev/null 2>&1 && got=1
    if [ "$got" -eq "$want" ]; then
      mv "$tmp" "$f" && printf '0006: %s — %s (backup: %s)\n' "$f" \
        "$([ "$UNDO" -eq 0 ] && echo registered || echo unregistered)" "$bak"
    else
      rm -f "$tmp"; printf '0006: %s — edit did not reach the intended state; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0006: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

exit "$rc"
