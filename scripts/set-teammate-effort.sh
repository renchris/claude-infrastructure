#!/usr/bin/env bash
# set-teammate-effort.sh — per-teammate reasoning effort for Agent Teams panes.
#
# Usage: set-teammate-effort.sh <worktree-path> <low|medium|high|xhigh>
#
# WHY THIS WORKS (binary-verified on CC 2.1.170, 2026-06-11):
#   Teammate panes launch a FRESH `claude` process via shell (`cd <worktree> &&
#   env ... <binary> ...`), which re-runs full settings resolution from its cwd —
#   including <worktree>/.claude/settings.local.json. The lead's live effort is
#   NOT forwarded (CLAUDE_CODE_EFFORT_LEVEL is absent from the pane env-forward
#   whitelist) and no --effort flag appears in the pane argv, so the worktree's
#   project-local `effortLevel` deterministically sets that teammate's effort.
#   Precedence: cli flag > project-local settings > user settings (xhigh floor).
#
# ⚠️ SUPERSEDED FROM 2.1.220 ON (2026-09-22). The paragraph above is the 2.1.170 record and stays
#   true of that build only. From 2.1.220 the teammate pane builder pushes `--effort <lead's live
#   level>` onto every member's argv (recorded in skills/agent-teams on 2.1.220, re-read on the
#   2.1.280 binary), and by the precedence line above that flag outranks the file this script
#   writes. So on every binary this fleet runs, a member runs at its LEAD's effort and this script
#   does not change it. It still writes the file (harmless, and correct on a pre-2.1.220 build),
#   but it says so instead of claiming the file binds. To run members at another rung, fire that
#   wave's own session at it: `handoff-fire.sh --effort medium` (rungs: model-config.yaml
#   effort_defaults.opus55_*).
#
# SCOPE: teammate PANES only. In-process subagents (Agent tool, no team_name)
#   inherit the lead's live effort with NO override surface (AgentInput has no
#   effort field; frontmatter `effort` is not parsed — GH #25591/#25669/#31536/
#   #65598 all open as of 2026-06-11). Do not point this script at the lead's
#   own checkout.
#
# NOTE: `max` is intentionally rejected — the settings schema enum caps at xhigh
#   and silently drops "max" (.catch(void 0)), which would fall back to the user
#   floor while LOOKING configured. Spawned agents should not run max anyway
#   (SSOT effort_defaults; CursorBench xhigh→max = +0.9pt for +20% cost).
set -euo pipefail

wt="${1:-}"
level="${2:-}"

usage() { echo "usage: set-teammate-effort.sh <worktree-path> <low|medium|high|xhigh>" >&2; exit 1; }

[ -n "$wt" ] && [ -n "$level" ] || usage
[ -d "$wt" ] || { echo "set-teammate-effort: worktree not found: $wt" >&2; exit 1; }

case "$level" in
  low|medium|high|xhigh) ;;
  max) echo "set-teammate-effort: 'max' is settings-inexpressible (schema caps at xhigh; 'max' silently drops to the user floor). Use xhigh, or launch a dedicated session with --effort max." >&2; exit 1 ;;
  *) usage ;;
esac

dir="$wt/.claude"
f="$dir/settings.local.json"
mkdir -p "$dir"

if command -v jq >/dev/null 2>&1 && [ -s "$f" ]; then
  tmp="$(mktemp)"
  jq --arg lvl "$level" '.effortLevel = $lvl' "$f" > "$tmp" && mv "$tmp" "$f"
else
  # Fresh file (or no jq): settings.local.json is conventionally gitignored.
  printf '{\n  "effortLevel": "%s"\n}\n' "$level" > "$f"
fi

echo "set-teammate-effort: ⚠ on Claude Code 2.1.220+ this file does NOT set the member's effort — the pane builder passes the lead's --effort, which outranks it. For another rung, fire the wave's own session: handoff-fire.sh --effort $level" >&2
echo "set-teammate-effort: $f → effortLevel=$level (binds a pane only on a pre-2.1.220 build; lead unaffected)"
