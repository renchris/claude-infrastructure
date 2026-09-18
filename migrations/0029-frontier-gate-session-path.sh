#!/bin/bash
# migration-class: c10
# migration-step: register hooks/frontier-spawn-gate.sh under the PreToolUse Bash matcher so a frontier SESSION fire (handoff-fire.sh --model fable) is counted against the same per-session cap an Agent spawn is — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0029-frontier-gate-session-path.sh
# migration-subject: ~/.claude/hooks/frontier-spawn-gate.sh
# migration-verify: jq -e '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]? | select(.command == "~/.claude/hooks/frontier-spawn-gate.sh")] | length == 1' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
# migration-conflict: jq -e '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]? | select(.command == "~/.claude/hooks/frontier-spawn-gate.sh")] | length >= 1 and any(.[]; (.asyncRewake // false) != false or (.timeout // 0) > 10)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0029 — R2 of docs/plans/NONLIMIT_RESUME_LADDER.md § W3 (conviction 93%, "pure safety gap; the only
# real bound").
# Subject: hooks/frontier-spawn-gate.sh · tests/frontier-spawn-gate.bats (24/24, 4 mutants killed)
#
# WHAT IT FIXES. The gate has counted AGENT spawns since it shipped, and CLAUDE.md § Frontier Tier
# Routing describes the agent as escalating "autonomously but BOUNDED (hook-enforced per-session
# spawn cap)" on the strength of that. Measured 2026-09-09 over 4,117 transcripts, the tier's
# dominant carrier is the SESSION path — Fable ran 52 LEAD SESSIONS against 140 subagent runs, and
# the three frontier commands had been invoked once between them. So the cap bounded the minority
# path and NOTHING bounded the majority one: a `handoff-fire.sh --model claude-fable-5-1` spent the
# frontier meter uncounted, without limit, in every session. This registration is the other half of
# the fix — the subject already reads Bash calls after the accompanying commit; until it is
# registered under the Bash matcher the harness never hands it one, and the code is inert.
#
# WHY c10. It edits settings.json. migrations/README.md: "A migration that touches settings.json, a
# launchd plist, or credentials declares c10 and waits for a human." So this STAGES and never
# self-runs.
#
# WHY THE CONFLICT ORACLE WATCHES asyncRewake AND THE TIMEOUT. Both wrong values are silent and
# both are catastrophic in opposite directions. `asyncRewake: true` backgrounds the hook, and a
# backgrounded PreToolUse hook cannot return exit 2 in time to refuse anything — the gate would read
# registered on every audit and gate nothing, which is this repo's most-measured trap (a registered
# no-op reading GREEN). An oversized timeout is the other one: this entry now runs on EVERY Bash
# call in every session, so a hook that can hang for 25 s is a wedge on the hottest tool surface in
# the fleet, not a gate. 5 s matches the Agent-matcher entry and is far above the subject's cost
# (one small sed over model-config.yaml plus one grep over the command string).
#
# BLAST RADIUS, and why it is small enough to hold. This hook now runs on every Bash call.
#   1. It only ADDS an entry to an existing Bash group; no sibling entry is modified or removed, and
#      the Agent-matcher entry is untouched.
#   2. The subject fails OPEN everywhere it cannot decide: a missing/unreadable SSOT, garbage stdin,
#      an absent tool_input, an empty command and any non-frontier model all exit 0 in silence.
#      tests/frontier-spawn-gate.bats pins each of those (cases 17-19, 9, 9b, 11).
#   3. It can only ever refuse a command that BOTH names a session-launching entrypoint AND passes
#      `--model <frontier>`. Naming the tier is not spending it: a grep for the model id and a
#      backlog row quoting the fire command are both explicit uncounted controls (9, 9b), and a
#      `--dry-run` probe spends no slot (10). Those three are the cases where a substring gate would
#      have been strictly worse than the hole it closes.
#   4. Cost is bounded and constant: no transcript read, no network, no write outside its own
#      per-session counter file in TMPDIR.
# Every config file is backed up before it is touched and the edit is verified BY CONTENT before it
# replaces the live file, so "the operator can revert" is a property of this script.
#
# WHY IT WRITES EVERY CONFIG DIR. ~/.claude and its siblings are separate REAL files, not symlinks
# into the checkout, and live sessions run against all of them. Registering in one leaves every
# session launched against another spending the frontier meter uncounted — the same silent
# half-coverage this migration exists to abolish.
set -uo pipefail

# shellcheck disable=SC2088  # the tilde is DELIBERATELY literal: this string is stored INTO
# settings.json, where CC expands it at hook-run time. Every sibling entry is written the same way.
HOOK_CMD='~/.claude/hooks/frontier-spawn-gate.sh'
HOOK_FILE="${CC_CLAUDE_DIR:-$HOME/.claude}/hooks/frontier-spawn-gate.sh"
TIMEOUT=5
rc=0

command -v jq >/dev/null 2>&1 || { printf '0029: jq required\n' >&2; exit 1; }

# ── precondition, re-derived at CONSUMPTION rather than trusted from the header ──────────────────
# LANDED IS NOT LIVE. hooks/ is a per-file symlink farm over the shared checkout, so the session-path
# arm exists on trunk long before the live file carries it. Registering the Bash matcher over a live
# hook that still reads only `.tool_input.model` buys an entry that runs on every Bash call, decides
# nothing, and reports registered — the exact registered-no-op this plan is about. Verify BY CONTENT
# (grep the function the arm rests on), never by a lag counter.
if [ ! -x "$HOOK_FILE" ]; then
  printf '0029: NOT registered — %s is missing or not executable.\n' "$HOOK_FILE" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it first.\n' >&2
  exit 1
fi
if ! grep -q 'frontier_fire_model' "$HOOK_FILE" 2>/dev/null; then
  printf '0029: NOT registered — the LIVE %s has no frontier_fire_model().\n' "$HOOK_FILE" >&2
  printf '      It would run on every Bash call and count nothing. Converge the live layer\n' >&2
  printf '      (install.sh / scripts/deploy-live.sh), then re-run this.\n' >&2
  exit 1
fi
printf '0029: precondition OK — live hook carries the session-path arm\n'

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Only touch a config that already runs a PreToolUse Bash group. A settings.json without one is
  # not a fleet config, and inventing the group here would be a scope this migration never claimed.
  if ! jq -e '[.hooks.PreToolUse[]? | select(.matcher == "Bash")] | length > 0' "$f" >/dev/null 2>&1; then
    printf '0029: %s — no PreToolUse Bash group; skipped (not a fleet config)\n' "$f"
    continue
  fi

  if jq -e --arg c "$HOOK_CMD" \
       '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]?.command] | any(. == $c)' \
       "$f" >/dev/null 2>&1; then
    printf '0029: %s — already registered\n' "$f"
    continue
  fi

  bak="$f.bak-0029-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0029: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0029-$$"
  # Appended to the FIRST Bash group. Position within the chain does not affect correctness: every
  # sibling is an independent allow/deny and the harness runs them all, so this gate's exit 2 stands
  # on its own. Appending (rather than prepending) also means the cheaper allowlist hooks decide
  # first on the overwhelming majority of Bash calls, which never reach a frontier decision at all.
  if jq --arg c "$HOOK_CMD" --argjson t "$TIMEOUT" '
       (.hooks.PreToolUse | map(.matcher == "Bash") | index(true)) as $i
       | .hooks.PreToolUse[$i].hooks += [{"type":"command","command":$c,"timeout":$t}]' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # Verify the edit BY CONTENT before it replaces the live file: present EXACTLY once in the Bash
    # group, synchronous, and with the small timeout — the three properties the conflict oracle
    # above watches for. Also assert the Agent entry SURVIVED: a jq path slip that rewrote the wrong
    # group would leave the majority path gated and the minority path silently ungated, which is the
    # same defect inverted and would read as a successful migration.
    if jq -e --arg c "$HOOK_CMD" '
         ([.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]? | select(.command == $c)]
            | length == 1 and ((.[0].asyncRewake // false) == false) and (.[0].timeout == 5))
         and ([.hooks.PreToolUse[] | select(.matcher == "Agent") | .hooks[]? | select(.command == $c)]
            | length == 1)' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0029: %s — registered PreToolUse/Bash (backup: %s)\n' "$f" "$bak"
    else
      rm -f "$tmp"; printf '0029: %s — edit did not verify; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0029: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

exit "$rc"
