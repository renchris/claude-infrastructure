#!/bin/bash
# migration-class: c10
# migration-step: register hooks/subagent-stop.sh as a SubagentStop hook so a finished subagent's report leaves a harvest index — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0014-subagent-stop-registration.sh
# migration-subject: ~/.claude/hooks/subagent-stop.sh
# migration-verify: jq -e '[.hooks.SubagentStop[]?.hooks[]?.command] | any(. == "~/.claude/hooks/subagent-stop.sh")' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0014 — the registration half of the SubagentStop consumer (backlog 7ea31ffa1a08).
# Subject: hooks/subagent-stop.sh, built and symlinked into ~/.claude/hooks since 2026-07-30.
#
# WHAT IT FIXES. The hook has been on disk and executable for eighteen days and is registered in
# ZERO settings.json — measured again today, 2026-08-17: `.hooks.SubagentStop` is ABSENT from all
# five config dirs, while settings-templates/settings.example.json carries it. A built, deployed,
# never-registered hook is this condition's exact subject: the conclusion is on disk and nothing
# enforces it.
#
# WHAT THE ROW GATED THIS ON, AND HOW THAT GATE RESOLVED. Backlog 7ea31ffa1a08 refused to wire this
# until one question was settled: "if unnamed subagents really leave no harvestable trace, this
# unwired hook is a live DATA-LOSS path, not a tidiness gap." Settled by measurement 2026-08-17 —
# 352 subagent transcripts exist on disk under <project>/<parent-sid>/subagents/agent-*.jsonl, so
# the trace is NOT lost and this is not a data-loss path. That does not retire the hook, because
# the hook was never a transcript backup: per its own header it writes a HARVEST INDEX (one pointer
# line to research-artifacts/subagent-reports.log) plus schema discovery. The gap it closes is that
# a finished subagent's report is unFINDABLE, not that it is unWRITTEN — a named background
# subagent cannot SendMessage, so "idle" reads as "delivered" and the report dies in a transcript
# nobody indexes. Wiring it is therefore correct at the row's own lower stakes, which is what the
# row asked to establish first.
#
# WHY THE .claude-next HOOKS FORK DOES NOT BLOCK THIS, though it looks like it should.
# subagent-stop.sh is one of the 25 files missing from ~/.claude-next/hooks (a forked REAL dir; the
# other three config dirs symlink hooks -> ~/.claude/hooks — backlog 11da376d60e3). But the command
# string stored below is the LITERAL `~/.claude/hooks/...`, which CC expands at hook-run time to
# $HOME/.claude/hooks/ regardless of which config dir the settings.json lives in. So a .claude-next
# session runs the primary copy and the fork is irrelevant HERE. Checked rather than assumed: the
# opposite conclusion would have made this a registered no-op reading GREEN in the busiest account.
#
# WHY c10. It edits settings.json. migrations/README.md: "A migration that touches settings.json, a
# launchd plist, or credentials declares c10 and waits for a human." Staged, never self-run.
#
# WHY IT WRITES EVERY CONFIG DIR, and why it CREATES the array. Each config dir's settings.json is a
# separate REAL file, so registering in one leaves every session launched against the others blind —
# the same silent half-coverage 0005's header warns about. Unlike 0005 this cannot append to an
# existing group: no config has a SubagentStop array at all, so the array is created. The
# fleet-config discriminator is therefore borrowed from a DIFFERENT event — a config that already
# runs Stop hooks is a fleet config — because "has a SubagentStop array" would be false everywhere
# and skip all five, i.e. a migration that always succeeds by doing nothing.
set -uo pipefail

# shellcheck disable=SC2088  # the tilde is DELIBERATELY literal: this string is stored INTO
# settings.json, where CC expands it at hook-run time. Expanding it here would hard-code this
# machine's absolute $HOME into a config mirrored across five config dirs.
HOOK_CMD='~/.claude/hooks/subagent-stop.sh'
HOOK_FILE="${CC_CLAUDE_DIR:-$HOME/.claude}/hooks/subagent-stop.sh"
# 10s, matching settings-templates/settings.example.json rather than a fresh guess — the template is
# the declared intent for this hook and a divergent timeout here would be a second SSOT.
TIMEOUT=10
rc=0

command -v jq >/dev/null 2>&1 || { printf '0014: jq required\n' >&2; exit 1; }

# ── precondition, re-derived at CONSUMPTION rather than trusted from the header ──────────────────
# A migration's premise can rot between staging and the converge that reads it (MEMORY.md
# discovery-critic-premise-goes-stale). If the hook is not executable on the live layer, the
# registration names a path that does not run — a registered no-op, which reads GREEN.
if [ ! -x "$HOOK_FILE" ]; then
  printf '0014: NOT registered — %s is missing or not executable.\n' "$HOOK_FILE" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it first.\n' >&2
  exit 1
fi

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # See the header: the discriminator is the Stop array, not the SubagentStop one, because no
  # config carries the latter yet and testing for it would skip every dir and still exit 0.
  if ! jq -e '.hooks.Stop | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0014: %s — no Stop array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  if jq -e --arg c "$HOOK_CMD" \
       '[.hooks.SubagentStop[]?.hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
    printf '0014: %s — already registered\n' "$f"
    continue
  fi

  bak="$f.bak-0014-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0014: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0014-$$"
  # `.hooks.SubagentStop //= []` then append: creates the array when absent and APPENDS when a
  # later migration or a hand-edit has already put a sibling there, so this can never clobber a
  # consumer it did not write. Matcher-less group, exactly as the template declares it.
  if jq --arg c "$HOOK_CMD" --argjson t "$TIMEOUT" \
       '.hooks.SubagentStop //= [] |
        if (.hooks.SubagentStop | length) == 0
        then .hooks.SubagentStop = [{"hooks":[{"type":"command","command":$c,"timeout":$t}]}]
        else .hooks.SubagentStop[0].hooks += [{"type":"command","command":$c,"timeout":$t}]
        end' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # verify the edit BY CONTENT before it replaces the live file
    if jq -e --arg c "$HOOK_CMD" \
         '[.hooks.SubagentStop[]?.hooks[]?.command] | any(. == $c)' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0014: %s — registered (backup: %s)\n' "$f" "$bak"
    else
      rm -f "$tmp"; printf '0014: %s — edit did not contain the hook; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0014: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

exit "$rc"
