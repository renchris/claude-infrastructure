#!/usr/bin/env bash
# git-worktree-guard.sh — PreToolUse(Bash): never reap a worktree/branch out from under a
# LIVE Claude session. Born from the 2026-06-12 incident: a manual `git worktree remove` +
# `git branch -D` on a "clean" tree deleted an ACTIVE session's worktree mid-work, because
# clean-tree was used as the only gate — but **clean tree != idle session** (a session that
# just committed has a clean tree). The worktree-gc janitor (scripts/worktree-gc.sh) gates on
# live-claude-cwd / lsof / idle>30m / .teammate-busy and NEVER deletes branches; raw git
# bypasses all of it. This hook reasserts the two load-bearing gates for manual git calls.
#
# Blocks (exit 2) when:
#   (1) `git branch -d|-D <b>` and <b> has a checked-out worktree — branches-with-worktrees
#       are NEVER deleted (the janitor preserves branches so a vanished worktree is recoverable).
#   (2) `git worktree remove [<flags>] <path>` and a live `claude` is cwd'd in <path>, OR any
#       process has files open under it (lsof). Idle worktrees pass → teammate lifecycle +
#       janitor are unaffected (a finished teammate's worktree is idle).
# Fail-OPEN on parse failure / non-matching command. Kill switch: WT_GUARD_DISABLED=1.
set -uo pipefail
[ "${WT_GUARD_DISABLED:-0}" = "1" ] && exit 0

# Builtin read, NOT `$(cat)`: command substitution forks AND execs /bin/cat on the hottest path
# in the system (this hook fires on EVERY Bash tool call). Measured 2026-07-31: ~6 ms per hook,
# ~18% of the 163 ms PreToolUse/Bash chain across the five hooks that did this. `read -d ''`
# returns non-zero at EOF -- the normal case here -- hence `|| true`; it also PRESERVES the
# trailing newline that `$(cat)` strips, so strip it back off for byte-parity with the old value.
IFS= read -r -d '' input || true
while [ "${input%$'\n'}" != "${input}" ]; do input="${input%$'\n'}"; done
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
else
  cmd="$(printf '%s' "$input" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\(.*\)"$/\1/')"
fi
[ -n "${cmd:-}" ] || exit 0

# `git -C <repo> worktree remove …` is the audit-prescribed form and the desk's standard shape —
# the literal matches below never saw it (2026-07-25 defect: every §7 cleanup ran unguarded).
# Normalize for MATCHING (strip `-C <path>` runs after `git`) and capture the repo for the
# worktree-list check, which must interrogate the -C target, not the hook's own cwd.
crepo="$(printf '%s' "$cmd" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p')"
ncmd="$(printf '%s' "$cmd" | sed -E 's/git([[:space:]]+-C[[:space:]]+[^[:space:]]+)+/git/g')"

# Fast pass-through: only inspect branch-delete / worktree-remove.
case "$ncmd" in
  *"git worktree remove"*|*"git branch -d"*|*"git branch -D"*|*"git branch --delete"*) ;;
  *) exit 0 ;;
esac

# (1) branch -d/-D guard — refuse to delete a branch that has a worktree.
if printf '%s' "$ncmd" | grep -qE 'git branch([[:space:]]|.)*-(d|D|-delete)'; then
  if [ -n "$crepo" ]; then wtlist="$(git -C "$crepo" worktree list 2>/dev/null)"; else wtlist="$(git worktree list 2>/dev/null)"; fi
  for tok in $(printf '%s' "$ncmd" | sed -E 's/.*git branch//' | tr ' ' '\n' | grep -vE '^-'); do
    [ -n "$tok" ] || continue
    if printf '%s\n' "$wtlist" | grep -qF "[$tok]"; then
      echo "git-worktree-guard: BLOCKED 'git branch -D $tok' — branch '$tok' has a checked-out worktree. Branches with worktrees are NEVER force-deleted (a live Claude session may depend on it; the worktree-gc janitor preserves branches by design — a vanished worktree must stay recoverable via its branch). If the worktree is genuinely idle, reap it with 'bash scripts/worktree-gc.sh --prune' (it gates on live-claude-cwd/lsof/idle>30m and KEEPS the branch). If it is idle but UNLANDED, --prune will keep it by design; land the branch, or record the abandon decision explicitly with 'bash scripts/worktree-gc.sh --warrant <path> --reason \"<why>\"' then '--dispose-abandoned' (that removes the DIRECTORY only — the branch still preserves every commit)." >&2
      exit 2
    fi
  done
fi

# (2) worktree remove guard — refuse if a live claude is cwd'd in the path (or it's open).
if printf '%s' "$ncmd" | grep -qE 'git worktree remove([[:space:]]|$)'; then
  wt="$(printf '%s' "$ncmd" | sed -E 's/.*git worktree remove//' | tr ' ' '\n' | grep -vE '^-' | tail -1)"
  [ -n "${wt:-}" ] || exit 0
  wtabs="$(cd "$wt" 2>/dev/null && pwd -P || echo "$wt")"
  live=0
  # ONE lsof over the whole candidate set — never one per pid. `pgrep -f claude` matches the FULL
  # argv, so it returns every process whose command line merely CONTAINS the string: measured 73-78
  # pids here, of which only ~13 are actually claude (the rest are bash/zsh/tee/timeout wrappers and
  # agent briefs that mention it). The old per-pid loop paid one lsof for each — 5.98 s per hook
  # invocation, vs 0.092 s batched (65x; tests/git-worktree-guard.bats took 263 s because of it).
  # Deliberately NOT fixed by narrowing the matcher or adding a timeout: this is a SAFETY refusal, so
  # a smaller population or a bound that gives up can only make it fail OPEN — permitting a removal
  # it should block. Batching keeps the population and the predicate byte-identical; it is the same
  # check, spawned once. The -n guard is load-bearing: `lsof -p ""` lists EVERY process on the box
  # (measured 1890 lines), which would silently widen the predicate to "anyone, anywhere".
  # RESOLVE lsof ABSOLUTELY. It lives in /usr/sbin, which is NOT on the PATH a LaunchAgent — or a
  # session spawned by one — hands its hooks ($HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin:
  # /usr/bin:/bin). So the bare name resolves in an operator's shell and does not exist off-session,
  # and both calls below then found nothing, `live` stayed 0, and this SAFETY REFUSAL returned 0: it
  # permitted exactly the removal it exists to block. Measured at trunk 2026-08-08 under that literal
  # PATH — tests/git-worktree-guard.bats test A ("a LIVE worktree is BLOCKED") returns 0, not 2; the
  # same suite on the same tree with /usr/sbin restored is 8/8, which is what isolates the cause.
  # The `command -v` on the second call made it worse rather than better: it converted a visible
  # "command not found" into a clean skip. (Class = memory path-resolved-dependency-in-daemon-code;
  # first landed as e6de2e15, auto-reverted for a collision in a different suite — this is that half
  # re-landed alone.) An EXPLICIT override is honoured VERBATIM, including empty, because that is the
  # only way to exercise the unresolvable branch below on a host where /usr/sbin/lsof exists.
  if   [ -n "${CC_WTG_LSOF+set}" ]; then LSOF="$CC_WTG_LSOF"
  elif [ -x /usr/sbin/lsof ];       then LSOF=/usr/sbin/lsof
  else                                   LSOF="$(command -v lsof 2>/dev/null || true)"
  fi
  if [ -z "$LSOF" ] || [ ! -x "$LSOF" ]; then
    # THIRD STATE, and it must not be silence. Liveness is UNREADABLE here — which is not the same
    # as "nothing is live" — and this file's header is explicit that anything giving up on this leg
    # can only fail OPEN. Refuse: a blocked removal is recoverable, a removal out from under a live
    # session is not.
    echo "git-worktree-guard: BLOCKED 'git worktree remove $wt' — lsof is not resolvable (PATH=$PATH), so this guard CANNOT determine whether a live process is cwd'd in the worktree. Refusing rather than guessing — a blocked removal is recoverable, a removal out from under a live session is not. If lsof lives elsewhere on this host, set CC_WTG_LSOF=<path>." >&2
    exit 2
  fi
  cpids="$(pgrep -f claude 2>/dev/null | sort -u | paste -sd, -)"
  if [ -n "$cpids" ] && "$LSOF" -a -p "$cpids" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | grep -qxF "$wtabs"; then live=1; fi
  if [ "$live" = "0" ] && "$LSOF" -- "$wtabs" 2>/dev/null | grep -q .; then live=1; fi
  if [ "$live" = "1" ]; then
    echo "git-worktree-guard: BLOCKED 'git worktree remove $wt' — a live process (likely a Claude session) is cwd'd in / has files open under it. Removing it now yanks the worktree out from under active work (clean tree != idle session). Let 'bash scripts/worktree-gc.sh --prune' handle reaping — it KEEPS anything live and only removes clean+merged+idle>30m worktrees, preserving the branch. Or wait for that session to finish." >&2
    exit 2
  fi
fi
exit 0
