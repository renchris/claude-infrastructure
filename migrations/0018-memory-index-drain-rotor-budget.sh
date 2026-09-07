#!/bin/bash
# migration-class: c10
# migration-step: raise hooks/memory-index-drain.sh's declared PostToolUse timeout from 10s to 30s and set env MID_DEADLINE_S=24 in the same settings.json edit, so the hook's internal rotor budget fits inside the deadline the harness enforces — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0018-memory-index-drain-rotor-budget.sh
# migration-subject: ~/.claude/hooks/memory-index-drain.sh
# migration-verify: jq -e '([.hooks.PostToolUse[]?.hooks[]?|select(.command=="~/.claude/hooks/memory-index-drain.sh")|.timeout] | length > 0 and all(. >= 30)) and ((.env.MID_DEADLINE_S // "0" | tonumber) >= 20 and (.env.MID_DEADLINE_S | tonumber) <= 27)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
# migration-conflict: jq -e '[.hooks.PostToolUse[]?.hooks[]?|select(.command=="~/.claude/hooks/memory-index-drain.sh")|.timeout] | length > 0 and any(. < 30)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0018 — the DECLARATION half of bounding the drain's actuator. 0015 registered the hook with
# timeout=10 and a header that reasoned "the rotor's own lock makes a slow case bounded rather than
# unbounded". That was wrong about the quantity that matters: the lock bounds CONCURRENCY, not
# DURATION, and the rotor was measured at 118s under a forced breach (the hub scan forks one grep
# per topic file per candidate). Past 10s the harness kills the hook, and a killed hook renders no
# additionalContext at all — the operator is told nothing in the one turn the index needed it.
#
# WHY BOTH VALUES MOVE IN ONE EDIT, AND WHY THAT IS THE WHOLE POINT. The hook now spends a single
# shared rotor budget (MID_DEADLINE_S, defaulting to 7 so it is correct under the UNRAISED
# declaration) across both of its call sites. Two numbers describe one deadline: the budget the hook
# enforces on itself, and the deadline the harness enforces on the hook. Raising one without the
# other produces either a hook that is killed anyway (budget > declaration) or an actuator given no
# time to work (declaration raised, budget left at the safe default). They are one fact, so they are
# one edit — a raise landed as two migrations could half-apply and read healthy
# (MEMORY.md conclusion-must-reach-the-enforcing-store).
#
# WHY 30 AND 24. 24s of rotor budget is enough for the ordinary rotation the second call site runs;
# the 6s of headroom covers the stat, the jq payload and mim_measure_file around it. Neither number
# is a claim that the rotor is fast — it is not, and the rotor's own cost is a separate open row.
# This bounds the DAMAGE of that slowness to a message the operator can read.
#
# WHY c10. It edits settings.json. Staged, never self-run.
set -uo pipefail

# shellcheck disable=SC2088  # the tilde is DELIBERATELY literal — it is stored INTO settings.json,
# where CC expands it at hook-run time, and this config is mirrored across five config dirs.
HOOK_CMD='~/.claude/hooks/memory-index-drain.sh'
TIMEOUT=30
BUDGET=24
rc=0

command -v jq >/dev/null 2>&1 || { printf '0018: jq required\n' >&2; exit 1; }

# ── precondition, re-derived at CONSUMPTION ──────────────────────────────────────────────────────
# The raise is only meaningful over a hook that actually spends a budget. A live layer still holding
# the pre-fix, unbounded copy would get a 30s deadline over an unbounded call — strictly worse than
# the 10s it has now, because it triples how long the hottest matcher in the config can stall before
# the harness cuts it. So assert the SUBJECT carries the bound before touching the declaration
# (MEMORY.md registration-precondition-must-assert-version-not-executability).
LIVE="${CC_CLAUDE_DIR:-$HOME/.claude}"
HOOK_FILE="$LIVE/hooks/memory-index-drain.sh"
if [ ! -x "$HOOK_FILE" ]; then
  printf '0018: NOT applied — %s is missing or not executable.\n' "$HOOK_FILE" >&2
  exit 1
fi
if ! grep -q 'MID_DEADLINE_S' "$HOOK_FILE"; then
  printf '0018: NOT applied — %s on the live layer does not spend a rotor budget yet.\n' "$HOOK_FILE" >&2
  printf '      Raising the declaration over an unbounded call makes the stall LONGER. Converge first.\n' >&2
  exit 1
fi

# ── which configs this edits, and why CC_CLAUDE_DIR is honoured here ─────────────────────────────
# scripts/registration-state.sh re-runs each verifier once per config dir with CC_CLAUDE_DIR
# re-aimed (migrations/README.md, "mind the per-config-dir loop"), so a settings.json migration that
# ignores it can only ever be verified against the dir it happened to enumerate. When the variable
# is set, that ONE dir is the subject; unset, the fleet is.
if [ -n "${CC_CLAUDE_DIR:-}" ]; then
  DIRS="$CC_CLAUDE_DIR"
else
  DIRS="$HOME/.claude $HOME/.claude-next $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary"
fi
seen=0

for dir in $DIRS; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue
  seen=$(( seen + 1 ))

  # Only configs that already registered the hook (0015's own discriminator, one axis narrower).
  if ! jq -e --arg c "$HOOK_CMD" \
       '[.hooks.PostToolUse[]?.hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
    printf '0018: %s — hook not registered here; skipped\n' "$f"
    continue
  fi

  if jq -e --arg c "$HOOK_CMD" --argjson t "$TIMEOUT" --arg b "$BUDGET" \
       '([.hooks.PostToolUse[]?.hooks[]?|select(.command==$c)|.timeout] | all(. >= $t))
        and ((.env.MID_DEADLINE_S // "") == $b)' "$f" >/dev/null 2>&1; then
    printf '0018: %s — already applied\n' "$f"
    continue
  fi

  bak="$f.bak-0018-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0018: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0018-$$"
  # Rewrite ONLY this hook's timeout, by matching its command, and add ONE env key. Every other
  # group, hook and env entry is carried through untouched — a sibling migration or a hand-edit owns
  # those.
  if jq --arg c "$HOOK_CMD" --argjson t "$TIMEOUT" --arg b "$BUDGET" \
       '.hooks.PostToolUse |= map(.hooks |= map(if .command == $c then .timeout = $t else . end))
        | .env = ((.env // {}) + {MID_DEADLINE_S: $b})' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # verify the edit BY CONTENT before it replaces the live file
    if jq -e --arg c "$HOOK_CMD" --argjson t "$TIMEOUT" --arg b "$BUDGET" \
         '([.hooks.PostToolUse[]?.hooks[]?|select(.command==$c)|.timeout] | length > 0 and all(. >= $t))
          and ((.env.MID_DEADLINE_S // "") == $b)' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0018: %s — timeout=%s env.MID_DEADLINE_S=%s (backup: %s)\n' "$f" "$TIMEOUT" "$BUDGET" "$bak"
    else
      rm -f "$tmp"; printf '0018: %s — edit did not carry both values; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0018: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

# A migration that touched nothing and said nothing is indistinguishable from one that worked
# (MEMORY.md claimed-outcome-vs-checked-outcome). Say which happened.
[ "$seen" -gt 0 ] || printf '0018: no settings.json found under %s — nothing applied\n' "${CC_CLAUDE_DIR:-the fleet config dirs}" >&2

exit "$rc"
