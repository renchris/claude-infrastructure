#!/bin/bash
# migration-class: c10
# migration-step: register hooks/goal-inert-watch.sh as a Stop hook so a SKIPPED /goal stops being silent — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0005-goal-inert-watch-registration.sh
#
# 0005 — the registration half of the goal-inertness sensor.
# Subject: hooks/goal-inert-watch.sh · tests/goal-inert-watch.bats (14/14)
# Finding: docs/research/goal-in-handoff-2026-08-08.md § RESOLVED 2026-08-09
#
# WHAT IT FIXES. `/goal <condition>` registers a `type:"prompt"` Stop hook; CC's Stop handler then
# deletes it again whenever the task registry holds non-terminal background work, and restores it in
# a `finally`. The registry therefore reads correct before and after the Stop and is wrong only
# DURING — the one moment nothing observes. This box tells every session to arm
# `cc-await-ping --timeout 14400` as a background Bash "before you go idle"; that task is
# non-terminal for four hours, so an armed goal here is inert by default. Measured on session
# d33abf12: 2 h, ~12 turns, ZERO evaluations, no log the operator ever sees.
#
# The deferral is CC's, is deliberate, and is not ours to change. The SILENCE is ours, and this hook
# is the only part of the loop we own. It is advisory-only (`systemMessage`) — it cannot block a
# stop, cannot force a turn, and cannot hold a session open, so the blast radius of a regression is
# bounded to one unwanted line of output.
#
# WHY c10. It edits `settings.json`. migrations/README.md: "A migration that touches settings.json, a
# launchd plist, or credentials declares c10 and waits for a human." The §3 rescope of C10 has not
# been ratified, so this STAGES and never self-runs; promotion is the one-word diff.
#
# WHY IT WRITES EVERY CONFIG DIR. `~/.claude/settings.json` and `~/.claude-tertiary/settings.json`
# are separate REAL files, not symlinks into the checkout (measured 2026-08-09 — 35 940 B and
# 35 955 B, already divergent). Registering in one leaves every session launched against the other
# blind, which is the same silent-half-coverage this hook exists to report. Each dir is handled
# independently and idempotently, so a partial previous run completes cleanly.
set -uo pipefail

# shellcheck disable=SC2088  # the tilde is DELIBERATELY literal: this string is stored INTO
# settings.json, where CC expands it at hook-run time. Every sibling Stop entry is written the same
# way (`~/.claude/hooks/session-continue.sh`). Expanding it here would hard-code this machine's
# absolute $HOME into a config that is mirrored across four config dirs.
HOOK_CMD='~/.claude/hooks/goal-inert-watch.sh'
HOOK_FILE="${CC_CLAUDE_DIR:-$HOME/.claude}/hooks/goal-inert-watch.sh"
TIMEOUT=5
rc=0

command -v jq >/dev/null 2>&1 || { printf '0005: jq required\n' >&2; exit 1; }

# ── precondition, re-derived at CONSUMPTION rather than trusted from the header ──────────────────
# A migration's premise can rot between staging and the converge that reads it
# (MEMORY.md discovery-critic-premise-goes-stale). If the hook is not on the live layer yet, the
# registration would name a path that does not execute — a registered no-op, which reads GREEN.
if [ ! -x "$HOOK_FILE" ]; then
  printf '0005: NOT registered — %s is missing or not executable.\n' "$HOOK_FILE" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it first.\n' >&2
  exit 1
fi

for dir in "$HOME"/.claude "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Only touch a config that already runs the sibling Stop hooks. A settings.json with no Stop array
  # is not a fleet config, and inventing one here would be a scope this migration never claimed.
  if ! jq -e '.hooks.Stop | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0005: %s — no Stop array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  if jq -e --arg c "$HOOK_CMD" \
       '[.hooks.Stop[].hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
    printf '0005: %s — already registered\n' "$f"
    continue
  fi

  bak="$f.bak-0005-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0005: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0005-$$"
  # Append to the FIRST Stop group — the matcher-less advisory group that already carries
  # session-continue / anti-deference / operator-readout. Ordering is irrelevant to correctness:
  # CC dispatches Stop hooks as CONCURRENT generators (uL @237793) and drains every result, so this
  # hook can neither be shadowed by, nor shadow, a sibling that returns a blocking decision.
  if jq --arg c "$HOOK_CMD" --argjson t "$TIMEOUT" \
       '.hooks.Stop[0].hooks += [{"type":"command","command":$c,"timeout":$t}]' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # verify the edit BY CONTENT before it replaces the live file
    if jq -e --arg c "$HOOK_CMD" '[.hooks.Stop[].hooks[]?.command] | any(. == $c)' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0005: %s — registered (backup: %s)\n' "$f" "$bak"
    else
      rm -f "$tmp"; printf '0005: %s — edit did not contain the hook; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0005: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

exit "$rc"
