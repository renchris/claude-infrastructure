# claude-launcher.zsh — account routing for the interactive `claude` entrypoint.
#
# Sourced by ~/.zshrc (wired by migrations/0009-start-latency-router.sh). Repo-owned so the policy
# can change without another ~/.zshrc edit — the rc gets ONE `source` line, once, and never again.
#
# THE SPLIT
#   claude1 … claude4   pinned wrappers — one account each, no routing, ever
#   claude              the router — picks an account, then calls the same body
#
# 🚨 WHY THE PIN MUST NOT BE "CLAUDE_CONFIG_DIR IS SET/UNSET" ALONE. Inside a running session that
# variable is present in the environment of EVERY descendant process, so a signal of the form "route
# when it is unset" is dead on every automated path and, worse, would let a NESTED `claude` re-route
# away from its parent's account. Two independent guards therefore gate routing, and both must hold:
# an unset CLAUDE_CONFIG_DIR (an operator's fresh shell, where it genuinely is unset) AND no
# CC_ACCOUNT_PINNED. handoff-fire sets the latter, so a fire that resolved account `next` and charged
# `--assign next` cannot have its own pick silently overridden at exec — the spread math would be
# inverted rather than merely lost.
#
# 🚨 WHY THE LAUNCH PATH CAN NEVER SWEEP. `--route` on a cache miss takes the single-flight lock,
# degrades to a 600 s grace read, and failing that waits 240 s behind a wedged holder before exit 5;
# if it wins the lock it sweeps, worst case MINUTES (4 accounts x keychain + a 90 s heal subprocess +
# two retry ladders). `--max-wait 0` forbids all of it: serve the cache or abstain. An abstention is
# not an error here — it falls back to the pinned account, which is exactly the status quo.
#
# --max-age 600 is the shipped grace band, and it is free by measurement: at <=10 min staleness the
# stale pick is now-excluded in 0.8% of pairs (median score-ratio 1.000), and across 931 recorded
# routing decisions the band has never once been entered (max observed age 89 s).
#
# Kill switch: CC_CLAUDE_ROUTE=off restores byte-identical pinned behaviour.

# The generated account-name -> config-dir map (SSOT: accounts.json). Sourced lazily and guarded:
# routing is a convenience, and a missing map must degrade to the pinned default, never to an error.
_cc_launcher_map() {
  (( ${+functions[cc_acct_dir_for_name]} )) && return 0
  [[ -r "$HOME/.claude/lib/account-map.generated.sh" ]] || return 1
  source "$HOME/.claude/lib/account-map.generated.sh" 2>/dev/null || return 1
  (( ${+functions[cc_acct_dir_for_name]} ))
}

# _cc_route_config_dir → sets _CC_ROUTED_DIR ('' = stay pinned) and _CC_ROUTE_NOTE (one short line).
# NEVER fails, NEVER blocks, NEVER prints on its own — the caller decides what the operator sees.
_cc_route_config_dir() {
  emulate -L zsh
  # Every local declared ONCE, at the top: a bare `local x` on a name that is already local PRINTS
  # `x=''` to stdout, so a helper re-declaring one and captured with $( ) hands back a garbage path.
  local bin acct rc dir note
  _CC_ROUTED_DIR='' _CC_ROUTE_NOTE=''
  case "${CC_CLAUDE_ROUTE:-on}" in
    off|0|false) _CC_ROUTE_NOTE='routing off (CC_CLAUDE_ROUTE)'; return 0 ;;
  esac
  # Seam, not a convenience: a suite that cannot pin the router binary silently executes the
  # operator's DEPLOYED one, which makes the test a function of what happens to be live rather
  # than of the code under test (hermeticity rule 5).
  bin="${CC_LAUNCHER_ACCOUNTS_BIN:-$HOME/.claude/bin/claude-accounts}"
  [[ -x "$bin" ]] || { _CC_ROUTE_NOTE='router absent'; return 0 }

  # Captured directly, never piped: `$(cmd | tail -1)` yields TAIL's status, which would make the
  # documented 0/2/3 exit enum unreadable and turn every abstention into an apparent success.
  acct="$("$bin" --route interactive --max-wait 0 --max-age 600 2>/dev/null)"
  rc=$?
  if (( rc != 0 )) || [[ -z "$acct" || "$acct" == none ]]; then
    case $rc in
      2) note='every account capped' ;;
      3) note='no fresh quota data' ;;
      *) note="router rc=$rc" ;;
    esac
    _CC_ROUTE_NOTE="pinned — $note"
    return 0
  fi
  _cc_launcher_map || { _CC_ROUTE_NOTE='pinned — account map unreadable'; return 0 }
  # Ask the SSOT, never compose a path from the name. An account the map does not declare is a
  # DECLINE, not a guess: launching against a dir that does not exist would first-run a new config.
  cc_acct_dir_for_name "$acct" >/dev/null 2>&1 || {
    _CC_ROUTE_NOTE="pinned — map declares no dir for '$acct'"; return 0
  }
  dir="$CC_ACCT_DIR"
  [[ -d "$dir" ]] || { _CC_ROUTE_NOTE="pinned — '$acct' dir absent"; return 0 }
  _CC_ROUTED_DIR="$dir"
  _CC_ROUTE_NOTE="routed → $acct"
  # Charge the phantom the router reads back at invocation time, so a burst of launches walks DOWN
  # the ranking instead of every one of them reading the same cache and stacking on rank[0].
  # Backgrounded and fully detached: spread is advisory, and a launcher must never wait on a ledger
  # append. Same ledger `--assign` writes — one store, never a second truth.
  ( "$bin" --assign "$acct" --src claude-launcher >/dev/null 2>&1 & ) 2>/dev/null
}

# ── the split ──────────────────────────────────────────────────────────────────────────────────
# Installed by COPYING the existing claude() into _claude_pinned and defining a router in its
# place, rather than by editing the body in ~/.zshrc. Three reasons: the rc needs exactly one
# `source` line ever; the original body is preserved byte-for-byte so the change is reversible by
# deleting that line; and no sed ever runs against the operator's live shell config.
#
# Must be sourced AFTER ~/.zshrc defines claude(). Idempotent — re-sourcing is a no-op.
_cc_install_router() {
  emulate -L zsh
  (( ${+functions[claude]} ))         || return 0   # nothing to wrap yet
  (( ${+functions[_claude_pinned]} )) && return 0   # already installed
  functions[_claude_pinned]="${functions[claude]}"

  claude() {
    emulate -L zsh
    local _arg _resume=0
    for _arg in "$@"; do
      case "$_arg" in --resume|--resume=*|-r|--continue|-c) _resume=1; break ;; esac
    done
    # A resume NEVER routes. A session id resolves only under the config dir it was born in, so
    # re-routing a resume turns a live transcript into "No conversation found" — and the account
    # is launch-time identity, which no later correction can undo.
    if (( ! _resume )) && [[ -z "${CLAUDE_CONFIG_DIR:-}" && -z "${CC_ACCOUNT_PINNED:-}" ]]; then
      _cc_route_config_dir
      if [[ -n "$_CC_ROUTED_DIR" ]]; then
        [[ -t 2 ]] && print -u2 "◆ ${_CC_ROUTE_NOTE}"
        # Prefix assignment, deliberately NOT `export`: it scopes the pin to exactly this call and
        # leaves the caller's environment untouched, so a later launch in the same shell re-routes
        # instead of inheriting a stale account.
        CLAUDE_CONFIG_DIR="$_CC_ROUTED_DIR" _claude_pinned "$@"
        return
      fi
      # Fell back. Say so — an inert router and a router that legitimately chose the pinned
      # account are indistinguishable in silence, which is how a dark feature survives for weeks.
      [[ -t 2 && -n "$_CC_ROUTE_NOTE" ]] && print -u2 "◆ ${_CC_ROUTE_NOTE}"
    fi
    _claude_pinned "$@"
  }

  # Account 1's pinned name. claude2/3/4 already have this shape and keep working unchanged: they
  # set CLAUDE_CONFIG_DIR, which the router reads as "pinned" and passes straight through.
  claude1() { CLAUDE_CONFIG_DIR="$HOME/.claude-next" _claude_pinned "$@" }
}
_cc_install_router
