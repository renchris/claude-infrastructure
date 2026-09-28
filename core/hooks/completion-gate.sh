#!/bin/bash
# completion-gate.sh — Stop hook: a "done" claim must agree with git.
#
# When the model's last message says the work is done, complete, finished, landed or safe to close,
# and the repository it is working in still has uncommitted tracked changes or commits its upstream
# does not have, the stop is blocked once and the facts are fed back. The model then finishes the
# work or says plainly what remains; the same git state is never blocked twice, so it cannot loop.
#
# It reads facts only (git status, the upstream count), never judges scope. Outside a git repository,
# with no upstream, or with no readable last message it stays silent.
# Kill switch: AUTONOMY_CORE_GATE=off. This hook always exits 0; it blocks only via JSON.

# shellcheck disable=SC1091  # lib.sh sits beside this hook
. "$(dirname "$0")/lib.sh"
[ "${AUTONOMY_CORE_GATE:-on}" = off ] && exit 0
command -v git >/dev/null 2>&1 || exit 0

input="$(cat)"
msg="$(ac_json_get "$input" last_assistant_message)"
[ -n "$msg" ] || exit 0
cwd="$(ac_json_get "$input" cwd)"
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd" 2>/dev/null || true
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# A completion claim, not a negated or conditional one. Lower-cased for the match.
low="$(printf '%s' "$msg" | tr '[:upper:]' '[:lower:]')"
printf '%s' "$low" | grep -Eq '(^|[^a-z])(done|complete|completed|finished|landed|shipped)([^a-z]|$)|safe to close|good to close: yes|all set|✅' || exit 0
printf '%s' "$low" | grep -Eq '(not|isn.t|aren.t|once|when|until|before|if) (yet )?(fully )?(done|complete|completed|finished)|good to close: no' && exit 0

dirty="$(git status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')"
untracked="$(git status --porcelain 2>/dev/null | grep -c '^??' | tr -d ' ')"
ahead=0
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
fi
[ "$dirty" -gt 0 ] || [ "$ahead" -gt 0 ] || exit 0

# Once per (session, git state): the second stop on the same state is allowed through.
sid="$(ac_json_get "$input" session_id)"
fp="$(ac_key "$(git rev-parse HEAD 2>/dev/null)|$(git status --porcelain 2>/dev/null)|$ahead")"
mark="$AC_STATE/gate/$(ac_key "${sid:-nosid}|$(pwd)")"
mkdir -p "$AC_STATE/gate" 2>/dev/null
[ "$(cat "$mark" 2>/dev/null)" = "$fp" ] && exit 0
printf '%s' "$fp" > "$mark"

facts=""
[ "$dirty" -gt 0 ] && facts="$facts
- $dirty tracked file(s) with uncommitted changes (git status)"
[ "$ahead" -gt 0 ] && facts="$facts
- $ahead commit(s) not pushed to $(git rev-parse --abbrev-ref '@{u}' 2>/dev/null)"
[ "$untracked" -gt 0 ] && facts="$facts
- $untracked untracked file(s)"
ac_block "Your last message says the work is done, but git in $(pwd) disagrees:$facts

Finish it (commit, and push if this work should be pushed), or say plainly what remains and who owns it. If these changes are not yours, say so and stop; this check will not fire again on this same git state."
exit 0
