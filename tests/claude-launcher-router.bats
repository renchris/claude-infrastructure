#!/usr/bin/env bats
# lib/claude-launcher.zsh — the claude1 / claude split.
#
# HERMETIC (scripts/test-hermeticity-lint.sh — a NEW suite gets no grandfather line, so all rules
# bind). Every seam this suite's subject can reach is pinned in setup():
#   $HOME              fixtured, so the real ~/.claude is never read or written
#   CC_LAUNCHER_ACCOUNTS_BIN   the router binary (rule 5b: unpinned, the subject would execute the
#                              operator's DEPLOYED claude-accounts and the suite would be a
#                              function of live quota rather than of this code)
#   CLAUDE_CONFIG_DIR / CC_ACCOUNT_PINNED / CC_CLAUDE_ROUTE   deliberately UNSET (rule 6). This is
#                              not pedantry: bats inherits the env of whatever launched it, and
#                              inside a Claude session CLAUDE_CONFIG_DIR is always set, which
#                              silently disables routing — every routing assertion would pass
#                              vacuously by taking the pinned branch. Measured during development.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/lib" "$HOME/.claude-next" "$HOME/.claude-quaternary"
  unset CLAUDE_CONFIG_DIR CC_ACCOUNT_PINNED CC_CLAUDE_ROUTE
  LIB="$BATS_TEST_DIRNAME/../lib/claude-launcher.zsh"

  # Minimal stand-in for the generated account map. The subject asks the SSOT for a name->dir
  # mapping and must DECLINE any name the map does not declare.
  cat > "$HOME/.claude/lib/account-map.generated.sh" <<MAP
cc_acct_dir_for_name() {
  case "\$1" in
    next|claude1)  CC_ACCT_DIR="\$HOME/.claude-next" ;;
    next4|claude4) CC_ACCT_DIR="\$HOME/.claude-quaternary" ;;
    *) return 1 ;;
  esac
  return 0
}
MAP
  STUB="$BATS_TEST_TMPDIR/router"
}

# Build a router stub with a given stdout + exit code.
mkrouter() {
  printf '#!/bin/sh\n[ "$1" = --assign ] && exit 0\necho "%s"\nexit %s\n' "$1" "$2" > "$STUB"
  chmod +x "$STUB"
}

# Run the split with a recording stand-in for the real claude(); echoes the config dir it saw.
runlauncher() {
  CC_LAUNCHER_ACCOUNTS_BIN="$STUB" zsh -f -c "
    claude() { print \"cfg=\${CLAUDE_CONFIG_DIR:-unset}\" }
    source '$LIB'
    $1
  " 2>/dev/null
}

@test "claude1 pins account 1" {
  mkrouter next4 0
  run runlauncher "claude1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cfg=$HOME/.claude-next"* ]]
}

@test "bare claude routes to the account the router names" {
  mkrouter next4 0
  run runlauncher "claude"
  [[ "$output" == *"cfg=$HOME/.claude-quaternary"* ]]
}

@test "an abstaining router (exit 3) falls back to the pinned default, never blocks" {
  mkrouter none 3
  run runlauncher "claude"
  [[ "$output" == *"cfg=unset"* ]]
}

@test "a capped fleet (exit 2) falls back rather than firing blind" {
  mkrouter none 2
  run runlauncher "claude"
  [[ "$output" == *"cfg=unset"* ]]
}

@test "an account the map does not declare is DECLINED, not composed into a path" {
  # The failure this pins: guessing \$HOME/.claude-<name> would first-run a brand new config dir.
  mkrouter nosuchaccount 0
  run runlauncher "claude"
  [[ "$output" == *"cfg=unset"* ]]
}

@test "--resume never routes (a session id resolves only under its birth config dir)" {
  mkrouter next4 0
  run runlauncher "claude --resume abc123"
  [[ "$output" == *"cfg=unset"* ]]
}

@test "-c never routes" {
  mkrouter next4 0
  run runlauncher "claude -c"
  [[ "$output" == *"cfg=unset"* ]]
}

@test "an explicit CLAUDE_CONFIG_DIR is never second-guessed" {
  mkrouter next4 0
  run runlauncher "CLAUDE_CONFIG_DIR=\$HOME/.claude-next claude"
  [[ "$output" == *"cfg=$HOME/.claude-next"* ]]
}

@test "CC_ACCOUNT_PINNED blocks routing, so a fire's own pick cannot be overridden at exec" {
  mkrouter next4 0
  run runlauncher "CC_ACCOUNT_PINNED=1 claude"
  [[ "$output" == *"cfg=unset"* ]]
}

@test "CC_CLAUDE_ROUTE=off restores pinned behaviour" {
  mkrouter next4 0
  run runlauncher "CC_CLAUDE_ROUTE=off claude"
  [[ "$output" == *"cfg=unset"* ]]
}

@test "routing does not leak into the caller's environment" {
  # Prefix assignment, not export: a second launch in the same shell must re-route rather than
  # inherit the first pick.
  mkrouter next4 0
  run runlauncher "claude >/dev/null; print \"after=\${CLAUDE_CONFIG_DIR:-unset}\""
  [[ "$output" == *"after=unset"* ]]
}

@test "re-sourcing the lib is a no-op (does not wrap the router in itself)" {
  mkrouter next4 0
  run runlauncher "source '$LIB'; source '$LIB'; claude1"
  [[ "$output" == *"cfg=$HOME/.claude-next"* ]]
}

@test "the DECISION is recorded in _CC_ROUTE_NOTE — routed vs pinned are distinguishable" {
  # The print itself is `[[ -t 2 ]]`-gated so scripted callers stay quiet; the note is the
  # observable contract and is what makes a dark router distinguishable from a pinned choice.
  mkrouter next4 0
  out="$(CC_LAUNCHER_ACCOUNTS_BIN="$STUB" zsh -f -c "
      claude() { : }; source '$LIB'; claude >/dev/null; print \"note=\$_CC_ROUTE_NOTE\"" 2>/dev/null)"
  [[ "$out" == *"note=routed → next4"* ]] || false

  mkrouter none 3
  out="$(CC_LAUNCHER_ACCOUNTS_BIN="$STUB" zsh -f -c "
      claude() { : }; source '$LIB'; claude >/dev/null; print \"note=\$_CC_ROUTE_NOTE\"" 2>/dev/null)"
  [[ "$out" == *"pinned — no fresh quota data"* ]]
}

@test "and it actually reaches a terminal (pty control for the -t 2 gate)" {
  command -v script >/dev/null || skip "no script(1) to provide a pty"
  mkrouter next4 0
  # Without a pty the gate suppresses the line — which is why the bats-captured assertion above
  # cannot substitute for this one. `script -q /dev/null` gives stderr a real tty.
  out="$(CC_LAUNCHER_ACCOUNTS_BIN="$STUB" script -q /dev/null zsh -f -c "
      claude() { : }; source '$LIB'; claude" 2>&1 || true)"
  [[ "$out" == *"routed"* ]]
}

@test "MUTANT: a lib that ignores the router's exit code must fail the abstain case" {
  # Control-can-fail. Strip the rc guard and the abstain test above stops discriminating: 'none'
  # would be looked up in the map, miss, and still decline — so the mutant must be aimed at the
  # branch that actually reads rc, using a name the map DOES declare.
  mutant="$BATS_TEST_TMPDIR/mutant.zsh"
  sed 's/if (( rc != 0 )) || \[\[ -z "$acct" || "$acct" == none \]\]; then/if false; then/' \
      "$LIB" > "$mutant"
  grep -q 'if false; then' "$mutant"          # the mutation landed
  printf '#!/bin/sh\n[ "$1" = --assign ] && exit 0\necho next4\nexit 3\n' > "$STUB"
  chmod +x "$STUB"
  out="$(CC_LAUNCHER_ACCOUNTS_BIN="$STUB" zsh -f -c "
      claude() { print \"cfg=\${CLAUDE_CONFIG_DIR:-unset}\" }
      source '$mutant'
      claude" 2>/dev/null)"
  # The mutant ROUTES on a failed router call; the real lib must not.
  [[ "$out" == *"cfg=$HOME/.claude-quaternary"* ]] || false
  real="$(runlauncher "claude")"
  [[ "$real" == *"cfg=unset"* ]]
}
