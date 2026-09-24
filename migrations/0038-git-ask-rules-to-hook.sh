#!/bin/bash
# migration-class: c10
# migration-step: remove the three blanket permissions.ask rules Bash(git reset --hard:*), Bash(git stash drop:*) and Bash(git restore:*) from ~/.claude/settings.json (every account links to it) — hooks/validate-bash.sh now asks on exactly the lossy cases itself, so these rules only stall the lossless ones (104 prompts, ~150 h of stalled sessions in 30 days). It refuses unless the LIVE hook carries the GIT-OWNERSHIP block. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0038-git-ask-rules-to-hook.sh --confirm settings.json
# migration-subject: hooks/validate-bash.sh
# migration-verify: jq -e '[(.permissions.ask // [])[] | select(. == "Bash(git reset --hard:*)" or . == "Bash(git stash drop:*)" or . == "Bash(git restore:*)")] | length == 0' "$HOME/.claude/settings.json" >/dev/null && grep -q 'GIT-OWNERSHIP BEGIN' "$HOME/.claude/hooks/validate-bash.sh"
#
# The verifier is spelled config-dir-INVARIANT: since 0037 every account's settings.json is a symlink
# to ~/.claude/settings.json, so there is one file and one answer (migrations/README.md, "Mind the
# per-config-dir loop"). It also requires the LIVE hook to carry the block — the rules' removal is
# only safe while the hook that replaces them is the one actually running.
#
# ══ 0038 — three static ask rules become one state-aware hook decision ══════════════════════════
# docs/plans/PERMISSION_PROMPT_CONSOLIDATION.md, census 2026-09-24 over 30 days of
# ~/.claude/autonomy/permission-archive: `git reset --hard` 64 prompts / 40 sessions / ~67 h,
# `git stash drop` 29 / 13 / ~57 h, `git restore` 11 / 10 / ~25 h. A static prefix rule cannot see
# whether anything would be lost, so it asked about a reset of a clean tree onto its own upstream,
# about the harness's OWN stash recipe (push -m TAG … drop the entry re-found by TAG), and about
# `git restore --staged`, which only unstages. For a dispatched session an ask is terminal.
#
# WHAT REPLACES THEM (hooks/validate-bash.sh, GIT-OWNERSHIP block; tests/validate-bash-git-ownership.bats):
#   reset --hard  permitted only when the tree has no tracked change, no local commit is missing from
#                 the target (`git cherry`), the target is a literal ref, the repo is the payload cwd
#                 (no cd / -C / GIT_DIR) and nothing before it in the command can dirty the tree.
#   stash drop    permitted only for an entry this command re-found by its own tag; bare `drop`
#                 (stash@{0} — maybe another session's on the shared stack) and `stash@{N}` ask.
#   restore       permitted only for --staged without --worktree.
# Everything else asks, as before. The hook ALSO now catches `git -C x reset --hard` and
# `git reset -q --hard`, which neither the old hook regex nor these prefix rules ever matched.
#
# WHAT STAYS: Bash(git push:*), Bash(git stash clear:*), Bash(fly deploy:*) — deliberate policy.
#
# SAFETY. Refuses unless the live hook carries the block (else removing the rules would drop the
# protection). Backs the real file up, edits it through its REAL path (never `mv` over an account
# link — README rule 7), and verifies BY CONTENT that the only change is those three entries.
# Idempotent: a second run prints "already applied". Revert: re-add the three strings to
# .permissions.ask, or restore the printed backup. Takes effect in NEW sessions.
#
# Usage: bash migrations/0038-git-ask-rules-to-hook.sh --dry-run
#        bash migrations/0038-git-ask-rules-to-hook.sh --confirm settings.json
set -uo pipefail

RULES='["Bash(git reset --hard:*)","Bash(git stash drop:*)","Bash(git restore:*)"]'
f="$HOME/.claude/settings.json"
hook="$HOME/.claude/hooks/validate-bash.sh"
command -v jq >/dev/null 2>&1 || { printf '0038: jq required — nothing written\n' >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '0038: --confirm must name its target: --confirm settings.json\n' >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;   # run by deploy-migrations after a promotion to mechanical
  *) printf '0038: unknown argument %s (use --dry-run or --confirm settings.json)\n' "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '0038: pass --dry-run to preview or --confirm settings.json to apply\n' >&2; exit 2; }

real=$(cd "$(dirname "$f")" && cd "$(dirname "$(readlink "$f" 2>/dev/null || printf '%s' "$f")")" && pwd)/$(basename "$(readlink "$f" 2>/dev/null || printf '%s' "$f")")
[ -f "$real" ] || { printf '0038: %s not found — nothing written\n' "$real" >&2; exit 1; }
jq -e . "$real" >/dev/null 2>&1 || { printf '0038: %s is not valid JSON — nothing written\n' "$real" >&2; exit 1; }

present=$(jq -r --argjson r "$RULES" '[(.permissions.ask // [])[] | select(. as $x | $r | index($x))] | .[]' "$real")
if [ -z "$present" ]; then
  printf '0038: already applied — none of the three rules is in %s\n' "$real"; exit 0
fi

grep -q 'GIT-OWNERSHIP BEGIN' "$hook" 2>/dev/null || {
  printf '0038: REFUSED — the live hook %s does not carry the GIT-OWNERSHIP block yet.\n' "$hook" >&2
  printf '0038: removing the rules now would drop the protection. Converge first: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' >&2
  exit 1
}

printf '0038: will remove from %s .permissions.ask:\n' "$real"; printf '%s\n' "$present" | sed 's/^/        /'
[ "$mode" = dry ] && { printf '0038: DRY RUN — nothing written\n'; exit 0; }

bdir="$HOME/.claude/backups/git-ask-rules-0038-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '0038: backup FAILED — nothing written\n' >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-0038-$$"
if ! jq --argjson r "$RULES" '.permissions.ask = [(.permissions.ask // [])[] | select(. as $x | ($r | index($x)) | not)]' "$real" > "$tmp" 2>/dev/null \
   || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0038: jq edit FAILED — nothing written\n' >&2; exit 1
fi
# BY CONTENT: everything but .permissions.ask is byte-for-byte the same document, and the ask list
# lost exactly the three rules and nothing else.
same_rest=$( [ "$(jq -S 'del(.permissions.ask)' "$real")" = "$(jq -S 'del(.permissions.ask)' "$tmp")" ] && echo y )
want_ask=$(jq -c --argjson r "$RULES" '[(.permissions.ask // [])[] | select(. as $x | ($r | index($x)) | not)]' "$real")
got_ask=$(jq -c '.permissions.ask' "$tmp")
if [ "$same_rest" != y ] || [ "$want_ask" != "$got_ask" ]; then
  rm -f "$tmp"; printf '0038: edit did not verify by content — nothing written\n' >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '0038: write FAILED — nothing written\n' >&2; exit 1; }
printf '0038: removed. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$bdir"
# Read the effect back through the verifier, never through the writer's own claim.
jq -e '[(.permissions.ask // [])[] | select(. == "Bash(git reset --hard:*)" or . == "Bash(git stash drop:*)" or . == "Bash(git restore:*)")] | length == 0' "$f" >/dev/null \
  && printf '0038: verified — the rules are gone from %s and the live hook owns the decision.\n' "$f"
