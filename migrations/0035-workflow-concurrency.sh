#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in one round instead of two — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0035-workflow-concurrency.sh
# migration-verify: jq -e '.env.CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS == "12"' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
# migration-conflict: jq -e '(.env // {}) | has("CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS") and .CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS != "12"' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0035 — lever 4 of docs/research/opus55-feature-adoption-2026-09-22/README.md.
#
# WHAT THE BINARY DOES WITHOUT IT. Read out of 2.1.280 (~/.claude-280/.../bin/claude.exe):
#
#   function Lr(e){ return Math.min(16, Math.max(2, e-2)) }
#   var Dr = Lr(Or())                          // Or = os.availableParallelism
#   $t = a.CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS ?? Dr
#   No = Bs($t, …)                             // the semaphore every agent() call awaits
#   Rn = D.int({min:1, max:256, digitsOnly:!0}) // the env var's parser
#
# This box reports availableParallelism() = 10, so the gate is 8. The research-subagents skill's
# default wave is N = 10 (band 8–12), and read-only fan-outs of >= ~8 units run as Workflows. So a
# default wave puts 2 agents in a queue behind the first to finish: its wall-clock is the slowest
# of the first 8 plus a whole second agent, up to ~2x a single round. At 12 the whole band runs
# in one round.
#
# WHY 12 AND NOT HIGHER. 12 is the top of the band this fleet actually fans out at; nothing
# measured here asks for more. Workflow agents are in-process (no new session, so the machine
# admission gate in scripts/lib/capacity-admit.sh never sees them), and each one's Bash calls do
# spawn processes, which is why the vendor sized the default off the core count. A cap raised only
# to the band's top keeps that CPU exposure bounded to 4 more agents than the vendor default. It
# changes WHEN tokens are spent, not how many: a wave's total is the same, it just reaches the
# 5-hour window's meter sooner.
#
# WHY THE settings `env` BLOCK, NOT THE LAUNCHER. Same reasoning as 0023: `env` reaches
# `claude -p`, background, daemon and resumed sessions, which a shell-profile export misses.
#
# TAKES EFFECT IN NEW SESSIONS: the value is read from the process environment when a Workflow run
# starts. The binary logs `workflow: concurrent agent gate = 12` on each run once it is set.
# Revert: delete the key from `env` (the vendor default returns), or set another value in 1..256.
set -uo pipefail

KEY="CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS"
VAL="12"
rc=0
changed=0
command -v jq >/dev/null 2>&1 || { printf '0035: jq required\n' >&2; exit 1; }

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  if ! jq -e . "$f" >/dev/null 2>&1; then
    printf '0035: %s — not valid JSON; left unchanged\n' "$f" >&2; rc=1; continue
  fi

  if jq -e --arg k "$KEY" --arg v "$VAL" '.env[$k] == $v' "$f" >/dev/null 2>&1; then
    printf '0035: %s — env.%s already "%s"\n' "$f" "$KEY" "$VAL"
    continue
  fi

  bak="$f.bak-0035-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0035: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0035-$$"
  # shellcheck disable=SC2016  # $k/$v are jq variables bound by --arg.
  if jq --arg k "$KEY" --arg v "$VAL" '.env //= {} | .env[$k] = $v' "$f" > "$tmp" 2>/dev/null \
     && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # Verify BY CONTENT: the key is set, no top-level key was lost, and no other env key changed.
    # (`env` itself may be new, so it is left out of the top-level comparison.)
    before_keys=$(jq -r 'keys[] | select(. != "env")' "$f" | sort | tr '\n' ' ')
    after_keys=$(jq -r 'keys[] | select(. != "env")' "$tmp" | sort | tr '\n' ' ')
    # shellcheck disable=SC2016
    before_env=$(jq -c --arg k "$KEY" '(.env // {}) | del(.[$k])' "$f")
    # shellcheck disable=SC2016
    after_env=$(jq -c --arg k "$KEY" '(.env // {}) | del(.[$k])' "$tmp")
    if jq -e --arg k "$KEY" --arg v "$VAL" '.env[$k] == $v' "$tmp" >/dev/null 2>&1 \
       && [ "$before_keys" = "$after_keys" ] \
       && [ "$before_env" = "$after_env" ]; then
      mv "$tmp" "$f" && printf '0035: %s — env.%s="%s" (backup: %s)\n' "$f" "$KEY" "$VAL" "$bak" && changed=$((changed+1))
    else
      rm -f "$tmp"; printf '0035: %s — edit did not verify; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0035: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

printf '0035: %d config dir(s) changed. Takes effect in NEW sessions.\n' "$changed"
printf '0035: to revert — jq \x27del(.env.%s)\x27 on each settings.json.\n' "$KEY"
exit "$rc"
