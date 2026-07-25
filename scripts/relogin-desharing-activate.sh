#!/usr/bin/env bash
# relogin-desharing-activate.sh — C10 OPERATOR step. Turn on Phase-5 Variant-A token
# de-sharing (per-session-class CLAUDE_CONFIG_DIR isolation). NOT run by any agent.
#
#   relogin-desharing-activate.sh            # dry-run: print the plan + rollback, touch nothing
#   CONFIRM=1 relogin-desharing-activate.sh  # write the enable flag
#
# PRECONDITION — do not run this until BOTH hold:
#   1. Experiment E1 has RETURNED VARIANT A — i.e. a second full-scope login for the same
#      account (different CLAUDE_CONFIG_DIR) was confirmed NOT to invalidate the first.
#      If E1 returned Variant B, de-sharing via config dirs is the WRONG mechanism: delete
#      bin/cc-config-slot rather than enabling it, and use the setup-token supplement
#      (CLAUDE_CODE_OAUTH_TOKEN, inference-only scope) instead.
#      Run + record: scripts/relogin-probes/e1-concurrent-logins.sh
#                    docs/research/RELOGIN_E1_E3_VERDICT_TEMPLATE.md
#   2. The executor (bin/cc-relogin) has PROVEN at least one real renewal. De-sharing
#      multiplies the number of credential stores that need renewing (4 accounts x 3 slots
#      = 12/month). Enabling it before renewal is proven multiplies an UNPROVEN process —
#      which is why the design puts this phase last.
#
# WHAT THIS DOES: writes {"enabled": true} to the flag file bin/cc-config-slot reads.
# That is ALL. It does not touch a launcher, a credential, an account, or a keychain item.
#
# WHAT IT DOES NOT DO — the second half is still yours. Slots only take effect once a
# launcher actually calls the resolver. The launchers are shell FUNCTIONS in ~/.zshrc
# (claude-next and its per-account aliases), which is live operator state outside this
# repo, so no agent edits it. The one-line change is printed below; apply it by hand.
#
# ROLLBACK: rm the flag file (or set {"enabled": false}) and undo the ~/.zshrc line. The
# resolver fails CLOSED — with the flag gone every session resolves to the canonical
# config dir it uses today. Existing slot dirs are inert once the flag is off; remove them
# only after confirming no session is using them.
set -uo pipefail

FLAG_FILE="${CC_CONFIG_SLOT_FLAG_FILE:-$HOME/.claude/autonomy/relogin-desharing.json}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "${1:-}" in
  -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

echo "Phase 5 — Variant A token de-sharing"
echo
echo "  flag file : $FLAG_FILE"
echo "  resolver  : $REPO/bin/cc-config-slot"
echo "  current   : $("$REPO/bin/cc-config-slot" --status 2>/dev/null | head -1 || echo 'unknown')"
echo
echo "PRECONDITIONS (verify BOTH before continuing):"
echo "  [ ] E1 returned VARIANT A  — concurrent same-account logins coexist"
echo "  [ ] cc-relogin has proven at least one real renewal"
echo
echo "Then apply the launcher half by hand in ~/.zshrc — inside claude-next(), replace:"
# SC2016: the single quotes are the point — these two lines are LITERAL shell source the
# operator copies into ~/.zshrc. Expanding them here would print this machine's resolved
# paths instead of the portable snippet, which is exactly the wrong thing to paste.
# shellcheck disable=SC2016
echo '      local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"'
echo "  with:"
# shellcheck disable=SC2016
echo '      local _cfg="$(cc-config-slot "${CC_ACCT:-next}" --class "${CC_SESSION_CLASS:-default}" 2>/dev/null || echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}")"'
echo "  (the '||' fallback keeps the launcher working even if the resolver is absent)"
echo
echo "ROLLBACK: rm '$FLAG_FILE' and revert the ~/.zshrc line."
echo

if [ "${CONFIRM:-0}" != "1" ]; then
  echo "DRY RUN — nothing written. Re-run with CONFIRM=1 to write the enable flag."
  exit 1
fi

mkdir -p "$(dirname "$FLAG_FILE")" || { echo "cannot create $(dirname "$FLAG_FILE")" >&2; exit 1; }
printf '{"enabled": true, "variant": "A", "activated_by": "operator"}\n' > "$FLAG_FILE" || {
  echo "failed to write $FLAG_FILE" >&2; exit 1; }

echo "wrote $FLAG_FILE"
"$REPO/bin/cc-config-slot" --status
echo
echo "NEXT: apply the ~/.zshrc line above, then 'exec zsh' in new shells."
