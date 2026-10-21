#!/bin/bash
# migration-class: c10
# migration-step: migration 0074 — remove the blanket permissions.ask rule Bash(git push:*) from ~/.claude/settings.json, which every account links to: it was 307 of the 644 permission prompts in the 14 days to 2026-10-20, every one answered yes. hooks/validate-bash.sh now asks on exactly the pushes worth a question (someone else's repository, a delete, mirror or forced refspec); the force-push deny rules stay. It refuses unless the LIVE hooks carry that push check. It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0074-git-push-ask-to-hook.sh --confirm settings.json
# migration-subject: hooks/validate-bash.sh hooks/lib/smart-bash-allowlist.py
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0074-git-push-ask-to-hook.sh" --verify
#
# ══ 0074 — the blanket push ask becomes one owner-aware hook decision ══
# docs/research/permission-prompt-reduction-2026-10-20/REPORT.md; operator ruling of 2026-10-20 on
# decision 29d62f1ad390 ("permission prompts is virtually always a yes … pattern recognized and
# allowed"), scoped by that packet's "narrows" answer (third parties and publishing keep a yes/no).
#
# WHY. In the 14 days to 2026-10-20 the beacon archive recorded 644 Bash permission prompts; 307 of
# them carried a `git push`, almost all `git push origin HEAD:main` from a /ship flow, 302 approved
# and 0 refused on their merits (the 5 Stop-resolved rows were long-stalled sessions the operator
# interrupted to arm a /goal). A push to trunk in every repo measured is FREE (reso-web-app and
# reso-management-app: "a push to main deploys nothing"), and the ship policy already pre-authorizes
# landing. hooks/ship-rail-push-allow.sh was built to clear exactly this and is inert while the ask
# stands (deny > ask > allow; a hook allow cannot beat an ask rule — measured 2026-10-03).
#
# WHAT REPLACES IT (hooks/validate-bash.sh, GIT-OWNERSHIP PUSH arm; tests/permission-widening-2026-10-20.bats):
#   a push is admitted only when it is non-force, names a literal remote and refspecs (no `+`, no
#   leading `:`, no --delete/--mirror/--prune/--receive-pack), and EVERY remote it can reach is a
#   github/gitlab/bitbucket repository owned by CC_VB_PUSH_OWNERS (default renchris) or a local path.
#   Anything else asks. hooks/lib/smart-bash-allowlist.py admits the same push segment inside a
#   compound command, so the auto-mode classifier is not handed the line instead.
# WHAT STAYS: deny Bash(git push --force:*) and Bash(git push -f:*); ask Bash(fly deploy:*) and
#   Bash(git stash clear:*) — production, and an irreversible clear of every session's stash.
#
# SAFETY. Refuses unless the live hook carries the PUSH arm (removing the rule first would leave
# third-party pushes with no question at all). Edits the ONE shared ~/.claude/settings.json every
# account links to (0037), backs it up, and verifies BY CONTENT that the only change is that one
# entry. Idempotent. Revert: re-add "Bash(git push:*)" to .permissions.ask, or restore the printed
# backup. Takes effect in NEW sessions.
#
# Usage: bash migrations/0074-git-push-ask-to-hook.sh --dry-run | --check | --verify
#        bash migrations/0074-git-push-ask-to-hook.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first) ·
#       4 REFUSED, the live hook does not carry the push check yet (converge first)
# bash 3.2-safe.
set -uo pipefail

N=0074
RULE='Bash(git push:*)'
f="$HOME/.claude/settings.json"
hook="${CC_0074_LIVE_HOOK:-$HOME/.claude/hooks/validate-bash.sh}"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
command -v jq >/dev/null 2>&1 || { printf '%s: jq required — nothing written\n' "$N" >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --check) mode=check ;;
  --verify) mode=verify ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '%s: --confirm must name its target: --confirm settings.json\n' "$N" >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '%s: unknown argument %s (use --dry-run, --check, --verify or --confirm settings.json)\n' "$N" "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '%s: pass --dry-run, --check, --verify or --confirm settings.json\n' "$N" >&2; exit 2; }

absent() { jq -e --arg r "$RULE" '(.permissions.ask // []) | index($r) == null' "$1" >/dev/null 2>&1; }
hook_live() { grep -q '_go_push_owned' "$hook" 2>/dev/null; }

if [ "$mode" = verify ]; then absent "$f" && hook_live; exit $?; fi

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }
if absent "$real"; then printf '%s: already applied — %s is not in %s .permissions.ask\n' "$N" "$RULE" "$real"; exit 0; fi
hook_live || {
  printf '%s: REFUSED — the live hook %s does not carry the push check yet.\n' "$N" "$hook" >&2
  printf '%s: removing the rule now would leave pushes to other people'\''s repositories unasked. Converge first: CC_DEPLOY_MAX_LAG_COMMITS=0 bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' "$N" >&2
  exit 4
}
"$parity" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}
printf '%s: will remove %s from %s .permissions.ask\n' "$N" "$RULE" "$real"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written\n' "$N"; exit 0 ;;
  check) printf '%s: CHECK ok — preflight passes, nothing written\n' "$N"; exit 0 ;;
esac

bdir="$HOME/.claude/backups/git-push-ask-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
if ! jq --arg r "$RULE" '.permissions.ask = [(.permissions.ask // [])[] | select(. != $r)]' "$real" > "$tmp" 2>/dev/null \
   || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# BY CONTENT: everything but .permissions.ask is the same document, and the ask list lost exactly
# that one rule and nothing else.
same_rest=$( [ "$(jq -S 'del(.permissions.ask)' "$real")" = "$(jq -S 'del(.permissions.ask)' "$tmp")" ] && echo y )
want_ask=$(jq -c --arg r "$RULE" '[(.permissions.ask // [])[] | select(. != $r)]' "$real")
got_ask=$(jq -c '.permissions.ask' "$tmp")
if [ "$same_rest" != y ] || [ "$want_ask" != "$got_ask" ]; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: removed for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$N" "$bdir"
"$parity" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$N" "$bdir" "$real" >&2
# Read the effect back through the verifier, never through the writer's own claim.
absent "$f" || { printf '%s: did NOT verify — %s is still in %s\n' "$N" "$RULE" "$f" >&2; exit 1; }
printf '%s: verified — %s is gone and the live validate-bash.sh owns the push decision.\n' "$N" "$RULE"
