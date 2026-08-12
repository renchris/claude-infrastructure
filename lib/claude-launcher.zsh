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
# Kill switch: CC_CLAUDE_ROUTE=off restores the pinned ACCOUNT CHOICE exactly — the pinned body is
# reached with the same arguments and the same environment. It is NOT byte-identical on stderr: the
# off-branch still sets _CC_ROUTE_NOTE and :121 still prints `◆ routing off (CC_CLAUDE_ROUTE)` when
# stderr is a TTY. That is deliberate — the whole reason the fallback notice exists is that an inert
# router and a router that legitimately chose the pinned account are indistinguishable in silence —
# but it was previously documented here as "byte-identical", which it has never been.

# The generated account-name -> config-dir map (SSOT: accounts.json). Guarded: routing is a
# convenience, and a missing map must degrade to the pinned default, never to an error.
#
# RE-SOURCED AT USE TIME, never cached for the life of the shell. The map is a projection of the
# SSOT and the SSOT changes: a pane that routed once would otherwise hold that snapshot for days,
# so regenerating the map (adding, removing or re-homing an account) would reach NEW SHELLS ONLY.
# A *removed* account is the bad case — the router may still name it, the stale in-memory map still
# declares a dir, the dir still exists, and the launch lands on a decommissioned account with no
# warning. Same shape as ~/.zshrc's `_cc_lib` (re-source, then ask whether the function is really in
# scope), inlined rather than called so this lib carries no dependency on an untracked rc function.
# Fail-open like _cc_lib: an unreadable file with the function already in scope is still usable.
_cc_launcher_map() {
  [[ -r "$HOME/.claude/lib/account-map.generated.sh" ]] &&
    source "$HOME/.claude/lib/account-map.generated.sh" 2>/dev/null
  (( ${+functions[cc_acct_dir_for_name]} ))
}

# _cc_route_config_dir → sets _CC_ROUTED_DIR ('' = stay pinned) and _CC_ROUTE_NOTE (one short line),
# plus _CC_ROUTE_ACCT / _CC_ROUTE_BIN for the caller's charge.
# NEVER fails, NEVER blocks, NEVER prints on its own, and — since the charge moved out — NEVER
# writes: it is a pure decision. The caller decides what the operator sees and what gets recorded.
_cc_route_config_dir() {
  emulate -L zsh
  # Every local declared ONCE, at the top: a bare `local x` on a name that is already local PRINTS
  # `x=''` to stdout, so a helper re-declaring one and captured with $( ) hands back a garbage path.
  local bin acct rc dir note
  _CC_ROUTED_DIR='' _CC_ROUTE_NOTE='' _CC_ROUTE_ACCT='' _CC_ROUTE_BIN=''
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
  _CC_ROUTE_ACCT="$acct"
  _CC_ROUTE_BIN="$bin"
}

# _cc_charge_on_commit <bin> <acct> → arms the phantom charge, sets _CC_LAUNCH_SENTINEL.
#
# The charge itself is unchanged in purpose: the router reads its own assignments back at
# invocation time, so a burst of launches walks DOWN the ranking instead of every one of them
# reading the same 90 s cache and stacking on rank[0]. It writes the same ledger `--assign` writes
# — one store, never a second truth.
#
# 🚨 WHAT MOVED, AND WHY. It used to fire inside _cc_route_config_dir, at DECISION time — one gate
# too early. `record_assignment`'s own contract in bin/claude-accounts reads "called by the consumer
# that COMMITS to launching a NEW session", and the launcher was not that consumer: the pinned body
# runs `_cc_route_check` AFTER the router hands off, and refuses the launch outright when a worktree
# claim fails (~/.zshrc:456-457). The account was then carrying a 15-minute phantom (ASSIGN_TTL_MIN)
# for a session that never existed — skewing the very spread math the charge exists to protect.
#
# Mechanism: a sentinel file the CALLER deletes the moment the pinned body returns. A refused launch
# returns without ever exec'ing, so the sentinel is gone before the settle window elapses and nothing
# is charged; a launch that reached the binary is still running, so the charge lands.
#
# HONEST LIMIT — this NARROWS D3, it does not close it. The discriminator is time, so a refusal that
# is itself slow (a worktree fetch that times out past the window) still charges. Widening the window
# trades that against the burst-spread the charge exists for, which is why it is a knob rather than a
# constant: CC_LAUNCH_ASSIGN_SETTLE_S, and 0 restores the immediate pre-fix charge.
_cc_charge_on_commit() {
  emulate -L zsh
  local settle sent
  _CC_LAUNCH_SENTINEL=''
  settle="${CC_LAUNCH_ASSIGN_SETTLE_S:-5}"
  # Detached in every branch: spread is advisory, and a launcher must never wait on a ledger append.
  if [[ "$settle" == 0 ]]; then
    ( "$1" --assign "$2" --src claude-launcher >/dev/null 2>&1 & ) 2>/dev/null
    return 0
  fi
  sent="${TMPDIR:-/tmp}/.cc-launch-charge.$$.$RANDOM"
  # A tmpdir we cannot write is not a reason to lose the spread signal: fall back to charging now,
  # which is exactly the behaviour this replaces, rather than to charging never.
  : > "$sent" 2>/dev/null || {
    ( "$1" --assign "$2" --src claude-launcher >/dev/null 2>&1 & ) 2>/dev/null
    return 0
  }
  _CC_LAUNCH_SENTINEL="$sent"
  ( sleep "$settle"
    [[ -e "$sent" ]] && "$1" --assign "$2" --src claude-launcher >/dev/null 2>&1
    rm -f "$sent" ) >/dev/null 2>&1 &!
}

# ── the split ──────────────────────────────────────────────────────────────────────────────────
# Installed by COPYING the existing claude() into _claude_pinned and defining a router in its
# place, rather than by editing the body in ~/.zshrc. Three reasons: the rc needs exactly one
# `source` line ever; the original body is preserved byte-for-byte so the change is reversible by
# deleting that line; and no sed ever runs against the operator's live shell config.
#
# Must be sourced AFTER ~/.zshrc defines claude(). Sourcing the LIB twice is a no-op; a re-source of
# the RC — which redefines claude() in between — RE-ARMS.
_cc_install_router() {
  emulate -L zsh
  (( ${+functions[claude]} )) || return 0           # nothing to wrap yet
  # 🚨 GUARD ON THE LIVE BODY, NEVER ON `_claude_pinned` MERELY EXISTING. ~/.zshrc:451 redefines
  # claude() every time the rc is sourced, and the activation script's own closing line tells the
  # operator to `source $ZSHRC`. The old guard read "_claude_pinned exists ⇒ installed", which is
  # true forever after the first source — so every later re-source left the RAW pinned body in
  # place with the router silently gone, permanently, for that shell. Measured on the real rc:
  # `functions claude | grep -c _CC_ROUTED_DIR` → 2 before a re-source, 0 after. And silently gone
  # is indistinguishable from "the router legitimately chose account 1", which is the exact
  # dark-feature failure the :121 fallback notice was written to prevent.
  #
  # The marker is _CC_ROUTED_DIR because it is LOAD-BEARING — the routing branch cannot exist
  # without it — so the marker cannot rot away from the thing it certifies, the way a decorative
  # one deleted or left behind by an edit would. It has to be code, not a comment: zsh strips
  # comments from stored function bodies, so a comment marker is invisible to this test.
  [[ "${functions[claude]}" == *_CC_ROUTED_DIR* ]] && return 0
  # Re-snapshot from the LIVE body. `claude1` calls this copy forever, so taking it once at first
  # source froze it: after any rc edit + re-source, claude1 ran the OLD launcher — different binary,
  # model and effort — while claude2/3/4, which call claude(), ran the new one, silently.
  functions[_claude_pinned]="${functions[claude]}"

  claude() {
    emulate -L zsh
    local _arg _resume=0 _rc=0
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
        _cc_charge_on_commit "$_CC_ROUTE_BIN" "$_CC_ROUTE_ACCT"
        # The sentinel is dropped the instant the pinned body RETURNS — including when it refuses,
        # and including on an interrupt, which is why it is an `always` block rather than a line
        # after the call.
        {
          # Prefix assignment, deliberately NOT `export`: it scopes the pin to exactly this call
          # and leaves the caller's environment untouched, so a later launch in the same shell
          # re-routes instead of inheriting a stale account.
          CLAUDE_CONFIG_DIR="$_CC_ROUTED_DIR" _claude_pinned "$@"
          _rc=$?
        } always {
          [[ -n "$_CC_LAUNCH_SENTINEL" ]] && rm -f "$_CC_LAUNCH_SENTINEL"
        }
        return $_rc
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

# ── _cc_route_check — repo-owned override (start-latency R6, 2026-08-12) ───────────────────────
# Shadows the copy defined inline in ~/.zshrc: this lib is sourced at the rc's tail, so the
# definition below wins in every new shell — the same later-definition mechanism
# _cc_install_router already rides — and it survives a `reload` (the rc re-defines its copy,
# then re-sources this lib, which re-shadows it).
#
# ONE deliberate change from the rc body, and it is the whole point: the PRIMARY checkout's
# tracked pool script is consulted LAST, not first. `/ship` pushes HEAD:main and never advances
# the primary's local main, so that tracked copy is a lagging fork of the claim path — measured
# 2026-08-12 at FIVE WEEKS stale (Jul 3 vs Aug 5) — while `~/.reso/bin/worktree-pool.sh` is
# self-updated to origin/main by every pool `ensure` (self_update_installed). Preferring the
# checkout copy meant every interactive launch ran a five-week-old claim path, and any
# claim-path fix landed on trunk could not reach the operator until local main happened to
# advance. Order now: installed trunk copy → checkout copy (a fresh machine before its first
# ensure) → cold new-worktree.sh. Everything else is byte-equal to the rc body.
_cc_route_check() {
    emulate -L zsh
    [[ "${CLAUDE_ISOLATION_SKIP:-0}" == "1" ]] && return 0
    local _top _wt _wtpath
    _top="$(git rev-parse --show-toplevel 2>/dev/null || echo '')"
    [[ -n "$_top" ]] || return 0                        # not a git repo → launch in place
    [[ -f "$_top/.git" ]] && return 0                   # linked worktree → already isolated
    [[ -d "$_top/.git" && "$(basename "$_top")" == "reso-management-app" ]] || return 0
    _wt="cc-$(date +%H%M%S)-$$"   # +shell PID → unique per pane (no same-second collision)
    if [[ -f "$HOME/.reso/bin/worktree-pool.sh" ]]; then
        _wtpath="$( cd "$_top" && bash "$HOME/.reso/bin/worktree-pool.sh" claim "$_wt" )" || return 1
    elif [[ -f "$_top/scripts/worktree-pool.sh" ]]; then
        _wtpath="$( cd "$_top" && bash scripts/worktree-pool.sh claim "$_wt" )" || return 1
    elif [[ -x "$_top/scripts/new-worktree.sh" ]]; then
        ( cd "$_top" && ./scripts/new-worktree.sh "$_wt" ) >&2 || return 1
        _wtpath="$HOME/Development/.worktrees/wt-$_wt"
    else
        return 0
    fi
    [[ -d "$_wtpath" ]] || return 1
    printf '%s\n' "$_wtpath"
    return 0
}
