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

# The REAL rc sequence, which the lib-double-source case below cannot reach: ~/.zshrc DEFINES
# claude(), its last line sources this lib, and a re-source runs both again — REDEFINING claude()
# between the two sources. V1/V2 marker bodies make "which body actually ran" observable, so a
# router that quietly un-installed itself cannot pass by taking the pinned branch.
resource_rc() {
  CC_LAUNCHER_ACCOUNTS_BIN="$STUB" zsh -f -c "
    claude() { print \"cfg=\${CLAUDE_CONFIG_DIR:-unset} body=V1\" }
    source '$LIB'
    claude() { print \"cfg=\${CLAUDE_CONFIG_DIR:-unset} body=V2\" }
    source '$LIB'
    $1
  " 2>/dev/null
}

# A router stub that RECORDS every `--assign` it is handed, so the charge is observable.
mkrouter_recording() {   # $1 stdout, $2 exit code, $3 log path
  printf '#!/bin/sh\n[ "$1" = --assign ] && { echo "$2" >> "%s"; exit 0; }\necho "%s"\nexit %s\n' \
      "$3" "$1" "$2" > "$STUB"
  chmod +x "$STUB"
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

# ── D1/D2: the rc re-source, which the case above is structurally blind to ─────────────────────
# The case above double-sources the LIB, which is genuinely idempotent, and never redefines
# claude() in between — so it passed on the broken code. These three reproduce what ~/.zshrc
# actually does.

@test "D1: an rc re-source leaves the router INSTALLED (the marker survives a claude() redefine)" {
  # The failure this pins: the old guard was `_claude_pinned exists ⇒ installed`, true forever
  # after the first source, so the second source left the raw pinned body in place and bare
  # `claude` reverted to account 1 with NO notice line — for the life of that shell.
  mkrouter next4 0
  run resource_rc "functions claude | grep -c _CC_ROUTED_DIR || true"
  # Every non-final `[[ ]]` below is `|| false`-guarded. bash exempts `[[ ]]` (and `(( ))`, and
  # `! cmd`) from errexit, so a non-final one is evaluated, discarded, and DEAD — only being the
  # body's last statement fails the test. `[ ]` is a plain builtin and needs no guard, which is
  # why this line has none. Not theory: the pre-fix lib PASSED the bare-claude case below purely
  # because its failing assertion was not the last line. scripts/bats-assert-liveness.py is the
  # analyzer for this class, and the land gate runs it on every changed suite.
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[1-9] ]]
}

@test "D1: after an rc re-source, bare claude still ROUTES (it does not revert to the pin)" {
  mkrouter next4 0
  run resource_rc "claude"
  [[ "$output" == *"cfg=$HOME/.claude-quaternary"* ]] || false
  [[ "$output" == *"body=V2"* ]]
}

@test "D2: claude1 tracks the LIVE rc body — it is not frozen at the first source" {
  # _claude_pinned is the copy claude1 calls forever. Snapshotted once, it kept launching the old
  # binary/model/effort after every rc edit while claude2/3/4 ran the new one, silently.
  mkrouter next4 0
  run resource_rc "claude1"
  [[ "$output" == *"cfg=$HOME/.claude-next"* ]] || false
  [[ "$output" == *"body=V2"* ]]
}

# ── D3: a refused launch must not be charged a phantom ─────────────────────────────────────────

@test "D3: a launch the pinned body REFUSES is not charged" {
  # ~/.zshrc:456-457 returns 1 without ever exec'ing when the worktree claim fails. The charge
  # used to fire at DECISION time, so the account carried a 15-min phantom for a session that
  # never started — against record_assignment's own "consumer that COMMITS" contract.
  log="$BATS_TEST_TMPDIR/assigns"
  mkrouter_recording next4 0 "$log"
  CC_LAUNCH_ASSIGN_SETTLE_S=1 CC_LAUNCHER_ACCOUNTS_BIN="$STUB" zsh -f -c "
      claude() { return 1 }
      source '$LIB'
      claude" >/dev/null 2>&1 || true
  # Wait WELL past the settle window before concluding "not charged". The charger is a detached
  # subshell, so under load its wake can lag its sleep — and a wait that is merely long enough on
  # an idle box turns this assertion into "we asked too early", which reads as a pass.
  sleep 4
  [ ! -s "$log" ]
}

@test "D3 control: a launch that COMMITS is still charged (the spread signal is not lost)" {
  # Without this the case above passes on a lib that simply never charges anything.
  log="$BATS_TEST_TMPDIR/assigns"
  mkrouter_recording next4 0 "$log"
  CC_LAUNCH_ASSIGN_SETTLE_S=1 CC_LAUNCHER_ACCOUNTS_BIN="$STUB" zsh -f -c "
      claude() { sleep 3 }
      source '$LIB'
      claude" >/dev/null 2>&1
  # POLL, never assert-once. The charge lands from a detached subshell whose wake can lag under
  # load, so a bare assertion here is a race that reds a correct lib. It can still fail: a lib that
  # never charges leaves the log empty for the whole 5 s.
  for _ in $(seq 1 10); do [ -s "$log" ] && break; sleep 0.5; done
  [ -s "$log" ] || false
  grep -q next4 "$log"
}

# ── D4: the account map is a projection of a mutable SSOT, not a shell-lifetime snapshot ───────

@test "D4: the map is re-read per launch — an account removed from it stops being routable" {
  # The bad case is a REMOVED account: the router still names it, a cached map still declares a
  # dir, the dir still exists, and the launch lands on a decommissioned account with no warning.
  mkrouter next4 0
  run runlauncher "claude
    print 'cc_acct_dir_for_name() { return 1 }' > '$HOME/.claude/lib/account-map.generated.sh'
    claude"
  [[ "${lines[0]}" == *"cfg=$HOME/.claude-quaternary"* ]] || false
  [[ "${lines[1]}" == *"cfg=unset"* ]]
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
