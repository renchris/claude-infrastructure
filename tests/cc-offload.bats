#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats: every @test body IS its own subshell, so an `export` inside one
#   is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are invoked from those test
#   subshells rather than from file scope (SC2329).
#
# cc-offload — the ONE-command cloud entrypoint (docs/plans/CLOUD_OBSERVABILITY.md §12).
#
# WHAT THIS SUITE IS ACTUALLY GUARDING. cc-offload owns no state and computes no verdict; it
# composes five tools that each already do. So the defects available to it are not "wrong answer"
# defects — they are LAUNDERING defects: adopting a sibling's honest refusal and re-emitting it as
# success. Every test below pins one of those, and each names the incident class it comes from:
#
#   · a sensor that could not run must never degrade to "nothing is there"   [lookup-miss-is-not-absence]
#   · UNKNOWN must render as UNKNOWN, never as a blank cell                  [alarm-polarity]
#   · a queue ack must never be reported as a read                           [claimed-outcome-vs-checked-outcome]
#   · a live-but-undeclared session must never be auto-retried into a second one
#   · a verdict a sibling computes must never be re-derived here             [sibling-auditors-must-share-the-state-model]
#
# HERMETIC BY CONSTRUCTION: every external tool cc-offload touches is a seam, so setup() points all
# five at stubs in $BATS_TEST_TMPDIR. NO test reaches the network, the real declaration store, the
# operator's ~/.claude, or a real account. The stubs RECORD their argv so the tests can assert on
# what cc-offload asked for, not merely on what it printed.
#
# POSITIVE CONTROLS: every absence assertion ("no row", "not retried", "never delivered") is paired
# in the same test with a case that DOES fire off the same fixture — a detector that fires on
# nothing is not a detector.

setup() {
  SUT="${BATS_TEST_DIRNAME}/../bin/cc-offload"
  [ -x "$SUT" ] || skip "cc-offload not executable"
  command -v jq >/dev/null 2>&1 || skip "jq required"

  # FIXTURE $HOME FIRST. cc-offload resolves its siblings through $HOME/.claude/bin and defaults
  # its create binary to $HOME/.claude-220/…, so an unfixtured suite grades against the OPERATOR'S
  # live install — green on this box and red on any other, for a reason no test names.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # handoff-fire's capacity_gate() refuses a net-new fire above 2.0/core and this box lives well
  # above that, so an unpinned suite would go red BY LOAD rather than by its subject.
  export CC_FIRE_CAPACITY_GATE=off

  export STUBDIR="$BATS_TEST_TMPDIR/stubs"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$STUBDIR"
  : >"$CALLS"

  export CC_OFFLOAD_NOCOLOR=1
  export CC_OFFLOAD_REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$CC_OFFLOAD_REPO"
  export CC_OFFLOAD_WEBSETUP_STATE="$BATS_TEST_TMPDIR/websetup"
  export CC_OFFLOAD_CLOUD_BIN="$STUBDIR/cc-cloud"
  export CC_OFFLOAD_NOTIFY_BIN="$STUBDIR/cc-notify"
  export CC_OFFLOAD_FIRE_BIN="$STUBDIR/handoff-fire.sh"
  export CC_OFFLOAD_RECONCILE_BIN="$STUBDIR/cloud-reconcile.sh"
  export CC_OFFLOAD_ACCOUNTS_BIN="$STUBDIR/claude-accounts"
  export CC_OFFLOAD_KITTY_SPLIT="$STUBDIR/kitty-split-launch.sh"
  # The declaration store is a seam too: `setup` reads the GitHub-App marker from under it, and a
  # suite that inherited the operator's real ~/.claude would grade against THEIR fleet's history —
  # green today, red the moment a real fire writes a marker, for a reason no test names.
  export CC_CLOUD_STATE="$BATS_TEST_TMPDIR/cloudstate"
  export CC_OFFLOAD_FIRE_LOG="$BATS_TEST_TMPDIR/fire.log"
  # Never let the suite inherit the developer's terminal: a kitty branch that reads a live
  # KITTY_WINDOW_ID is green under launchd and red in an operator's pane — the worst polarity.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1

  # ── default stubs; individual tests overwrite the one they are about ──────────────────────────
  # cc-cloud: NDJSON on `list --json --state`, one object per line (never an array).
  export CLOUD_ROWS="$BATS_TEST_TMPDIR/rows.ndjson"
  cat >"$CLOUD_ROWS" <<'EOF'
{"id":"session_alive","branch":"claude/a","age_s":300,"account":"next3","url":"https://claude.ai/code/session_alive","state":"ALIVE","retired":false}
{"id":"session_dead","branch":"claude/b","age_s":90000,"account":"next2","url":"https://claude.ai/code/session_dead","state":"NOT-STARTED","retired":false}
{"id":"session_gone","branch":"claude/c","age_s":99999,"account":"next","url":"https://claude.ai/code/session_gone","state":"ABANDONED","retired":true}
EOF
  cat >"$STUBDIR/cc-cloud" <<'EOF'
#!/usr/bin/env bash
echo "cc-cloud $*" >>"$CALLS"
case "$1" in
  list) cat "$CLOUD_ROWS" ;;
  preflight) echo "PREFLIGHT PASS." ;;
  declare) echo "declared" ;;
  retire) echo "retired $3" ;;
  show) echo "url=https://claude.ai/code/$2" ;;
  *) exit 2 ;;
esac
EOF
  cat >"$STUBDIR/cc-notify" <<'EOF'
#!/usr/bin/env bash
echo "cc-notify $*" >>"$CALLS"
# The ENVIRONMENT is part of this call's contract, not decoration: cc-notify's --cloud transport
# resolves its claude binary from CC_CLAUDE_BIN and falls back to `command -v claude`, which on the
# real box finds a shell function (invisible) or the pinned 2.1.114 (no --cloud verb). A stub that
# recorded only argv could not tell a working call from the dead one backlog 6ad6ec4121d2 names.
echo "cc-notify-env CC_CLAUDE_BIN=${CC_CLAUDE_BIN-UNSET}" >>"$CALLS"
exit "${NOTIFY_RC:-0}"
EOF
  cat >"$STUBDIR/handoff-fire.sh" <<'EOF'
#!/usr/bin/env bash
echo "fire optin=${CC_FIRE_CLOUD:-UNSET} $*" >>"$CALLS"
exit "${FIRE_RC:-0}"
EOF
  cat >"$STUBDIR/cloud-reconcile.sh" <<'EOF'
#!/usr/bin/env bash
echo "reconcile confirm=${CONFIRM:-UNSET} $*" >>"$CALLS"
echo "BRANCH	STATE	DECL	DETAIL"
EOF
  cat >"$STUBDIR/claude-accounts" <<'EOF'
#!/usr/bin/env bash
echo "accounts $*" >>"$CALLS"; echo next3
EOF
  cat >"$STUBDIR/kitty-split-launch.sh" <<'EOF'
#!/usr/bin/env bash
echo "split $*" >>"$CALLS"
EOF
  chmod +x "$STUBDIR"/*
}

# ══ ls — the board ══════════════════════════════════════════════════════════════════════════════

@test "ls renders one row per non-retired declaration, and hides the retired one" {
  run "$SUT" ls
  [ "$status" -eq 0 ]
  [[ "$output" == *session_alive* ]] || false
  [[ "$output" == *session_dead* ]] || false
  [[ "$output" != *session_gone* ]] || false # retired is excluded by default …
  run "$SUT" ls --all
  [[ "$output" == *session_gone* ]]        # … and the POSITIVE CONTROL: --all shows it
}

@test "ls sources state from cc-cloud --state and never re-derives it" {
  # The arbiter's answer is printed VERBATIM. A stub emitting a state cc-offload has never heard of
  # must survive to the output — if this file ever grows its own opinion of liveness, this fails.
  printf '%s\n' '{"id":"session_x","branch":"b","age_s":1,"account":"a","url":"u","state":"WEDGED-NEW-ARM","retired":false}' >"$CLOUD_ROWS"
  run "$SUT" ls
  [ "$status" -eq 0 ]
  [[ "$output" == *WEDGED-NEW-ARM* ]] || false
  grep -q -- '--state' "$CALLS"
}

@test "ls on an EMPTY store says nothing is declared, and exits 0" {
  : >"$CLOUD_ROWS"
  run "$SUT" ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"no cloud sessions declared"* ]]
}

@test "ls when the SENSOR FAILS is UNKNOWN, not an empty fleet" {
  # THE load-bearing test. `cc-cloud list --json` prints zero bytes for an empty store, so an empty
  # read is ambiguous by construction: it means "nothing declared" OR "the sensor died". Conflating
  # them reports a healthy silent fleet while N cloud sessions burn quota.
  cat >"$STUBDIR/cc-cloud" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$STUBDIR/cc-cloud"
  run "$SUT" ls
  [ "$status" -eq 1 ]
  [[ "$output" == *UNKNOWN* ]] || false
  [[ "$output" != *"no cloud sessions declared"* ]]
}

@test "ls renders a missing state as the literal word UNKNOWN, never as a blank cell" {
  printf '%s\n' '{"id":"session_q","branch":"b","age_s":5,"account":"a","url":"u","retired":false}' >"$CLOUD_ROWS"
  run "$SUT" ls
  [ "$status" -eq 0 ]
  [[ "$output" == *UNKNOWN* ]]
}

@test "ls counts LANDED as done, not as working" {
  printf '%s\n' '{"id":"session_l","branch":"b","age_s":5,"account":"a","url":"u","state":"LANDED","retired":false}' >"$CLOUD_ROWS"
  run "$SUT" ls
  [[ "$output" == *"0 working · 1 landed"* ]]
}

# ══ say — the here→cloud arm ════════════════════════════════════════════════════════════════════

@test "say reports QUEUED and never claims the session read it" {
  run "$SUT" say session_alive "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *QUEUED* ]] || false
  [[ "$output" == *"queued is not read"* ]] || false
  [[ "$output" != *delivered* ]] || false
  [[ "$output" != *"read by"* ]] || false
  grep -q 'cc-notify --cloud session_alive hello' "$CALLS"
}

@test "say surfaces cc-notify's undeclared refusal instead of laundering it" {
  NOTIFY_RC=3 run "$SUT" say session_nope "hi"
  [ "$status" -eq 3 ]
  [[ "$output" == *undeclared* ]] || false
  [[ "$output" != *QUEUED* ]]
}

@test "say all targets only ALIVE and BOOTING sessions" {
  run "$SUT" say all "ping"
  [ "$status" -eq 0 ]
  grep -q 'cc-notify --cloud session_alive ping' "$CALLS"
  ! grep -q 'session_dead' "$CALLS" || false # NOT-STARTED is not a live target …
  ! grep -q 'session_gone' "$CALLS"        # … and retired never is
}

@test "say pins the SAME claude binary default that up carries — the steering arm's dead-by-default" {
  # backlog 6ad6ec4121d2. `up` passed CC_CLAUDE_BIN="${CC_CLAUDE_BIN:-$CLOUD_CLAUDE}" and `say` did
  # not, so the create+brief path worked and the mid-flight steering arm exited 4 (no usable claude
  # binary) until it was pinned by hand. The assertion is on the ENV of the call, because that is
  # where the whole difference lives — both call sites print identical argv.
  export CC_CLOUD_CREATE_BIN="$BATS_TEST_TMPDIR/claude-220"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$CC_CLOUD_CREATE_BIN"; chmod +x "$CC_CLOUD_CREATE_BIN"
  run "$SUT" say session_alive "steer"
  [ "$status" -eq 0 ]
  grep -q "cc-notify-env CC_CLAUDE_BIN=$CC_CLOUD_CREATE_BIN" "$CALLS"
  ! grep -q 'cc-notify-env CC_CLAUDE_BIN=UNSET' "$CALLS" || false
}

@test "say does not OVERRIDE an explicit CC_CLAUDE_BIN — the default is a floor, not a clamp" {
  # POSITIVE CONTROL for the arm above: `:-` must keep the caller's own choice. A `=` there would
  # pin every send to the create binary and silently defeat the seam the suite itself relies on.
  export CC_CLAUDE_BIN="$BATS_TEST_TMPDIR/mine"
  run "$SUT" say session_alive "steer"
  [ "$status" -eq 0 ]
  grep -q "cc-notify-env CC_CLAUDE_BIN=$BATS_TEST_TMPDIR/mine" "$CALLS"
}

@test "say all with nothing live refuses rather than reporting success" {
  printf '%s\n' '{"id":"s","branch":"b","age_s":1,"account":"a","url":"u","state":"NOT-STARTED","retired":false}' >"$CLOUD_ROWS"
  run "$SUT" say all "ping"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no ALIVE or BOOTING"* ]]
}

# ══ up — the fire ═══════════════════════════════════════════════════════════════════════════════

@test "up passes the opt-in as the literal string 'on'" {
  # CC_FIRE_CLOUD=1 or =true are REFUSED by the fire path with exit 2. Only `on` works.
  echo "do the thing" >"$BATS_TEST_TMPDIR/task.txt"
  run "$SUT" up --task "$BATS_TEST_TMPDIR/task.txt" --via cli
  [ "$status" -eq 0 ]
  grep -q '^fire optin=on ' "$CALLS"
  grep -q -- '--cloud' "$CALLS"
  grep -q -- '--prompt-file' "$CALLS"
}

@test "up on exit 11 (live but undeclared) is LOUD and does NOT retry" {
  # 11 means a session is spending quota that nothing local can see, address or reap. Retrying it
  # buys a SECOND invisible session. With -n 3 the fire must be invoked exactly once.
  echo "task" >"$BATS_TEST_TMPDIR/task.txt"
  FIRE_RC=11 run "$SUT" up --task "$BATS_TEST_TMPDIR/task.txt" --via cli -n 3
  [ "$status" -eq 11 ]
  [[ "$output" == *"IS LIVE"* ]] || [[ "$output" == *"EXIT 11"* ]] || false
  [ "$(grep -c '^fire ' "$CALLS")" -eq 1 ]
}

@test "up on exit 10 says nothing is running — the safe-to-retry case" {
  echo "task" >"$BATS_TEST_TMPDIR/task.txt"
  FIRE_RC=10 run "$SUT" up --task "$BATS_TEST_TMPDIR/task.txt" --via cli
  [ "$status" -eq 10 ]
  [[ "$output" == *"NOTHING is running"* ]]
}

@test "up refuses an empty brief" {
  : >"$BATS_TEST_TMPDIR/empty.txt"
  run "$SUT" up --task "$BATS_TEST_TMPDIR/empty.txt" --via cli
  [ "$status" -eq 2 ]
  [[ "$output" == *empty* ]] || false
  ! grep -q '^fire ' "$CALLS"
}

@test "up refuses a missing task file rather than firing blind" {
  run "$SUT" up --task "$BATS_TEST_TMPDIR/nope.txt" --via cli
  [ "$status" -eq 2 ]
  ! grep -q '^fire ' "$CALLS"
}

# ══ setup — the grader ══════════════════════════════════════════════════════════════════════════

@test "setup FAILS when the create binary cannot do --cloud" {
  local fake="$BATS_TEST_TMPDIR/oldclaude"
  printf '#!/usr/bin/env bash\necho "2.1.114 (Claude Code)"\n' >"$fake"; chmod +x "$fake"
  CC_CLOUD_CREATE_BIN="$fake" run "$SUT" setup
  [ "$status" -eq 3 ]
  [[ "$output" == *"no --cloud verb"* ]] || false
  [[ "$output" == *"NOT READY"* ]]
}

@test "setup grades the GitHub App as UNKNOWN, never as absent" {
  # Measured 2026-08-10: gh holds an OAuth (gho_) token and every installation endpoint needs an
  # App JWT or an installation token — a credential CLASS wall. The check-suites proxy can only
  # PROVE PRESENT; its silence proves nothing, so absence must never be asserted.
  local fake="$BATS_TEST_TMPDIR/newclaude"
  printf '#!/usr/bin/env bash\necho "2.1.220 (Claude Code)"\n' >"$fake"; chmod +x "$fake"
  CC_CLOUD_CREATE_BIN="$fake" PATH="$STUBDIR:$PATH" run "$SUT" setup
  [[ "$output" == *"NOT DETECTABLE"* ]] || false
  [[ "$output" != *"App is not installed"* ]]
}

@test "setup reports the App as ABSENT once a live create has PROVEN it, and blocks" {
  # The evidence is behavioural and it had to be bought with a create attempt: the CLI only bundles
  # when it has no git_repository source. Having paid for it once, setup must not re-spend it.
  mkdir -p "$CC_CLOUD_STATE"
  printf 'verdict=absent\nts=1\n' >"$CC_CLOUD_STATE/github-app.observed"
  local fake="$BATS_TEST_TMPDIR/newclaude"
  printf '#!/usr/bin/env bash\necho "2.1.220 (Claude Code)"\n' >"$fake"; chmod +x "$fake"
  CC_CLOUD_CREATE_BIN="$fake" run "$SUT" setup
  [ "$status" -eq 3 ]
  [[ "$output" == *"PROVEN ABSENT"* ]] || false
  [[ "$output" == *"github.com/apps/claude"* ]]
}

@test "a bundle refusal writes the App marker; any other exit-10 refusal does NOT" {
  # ONE-DIRECTIONAL, and this is the whole point: bundle ⇒ absent is sound, but a refusal for any
  # other reason says nothing about the App, and inferring from it would be the exact
  # absence-is-ambiguous error the subsystem exists to refuse.
  echo "task" >"$BATS_TEST_TMPDIR/t.txt"
  cat >"$STUBDIR/handoff-fire.sh" <<'EOF'
#!/usr/bin/env bash
echo "fire optin=${CC_FIRE_CLOUD:-UNSET} $*" >>"$CALLS"
echo "!! cloud fire: REFUSED — refused-bundle" >&2
exit 10
EOF
  chmod +x "$STUBDIR/handoff-fire.sh"
  run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --via cli
  [ -f "$CC_CLOUD_STATE/github-app.observed" ]
  grep -q 'verdict=absent' "$CC_CLOUD_STATE/github-app.observed"

  # NEGATIVE CONTROL, same fixture, only the refusal reason changed.
  rm -f "$CC_CLOUD_STATE/github-app.observed"
  cat >"$STUBDIR/handoff-fire.sh" <<'EOF'
#!/usr/bin/env bash
echo "fire optin=${CC_FIRE_CLOUD:-UNSET} $*" >>"$CALLS"
echo "!! cloud fire: REFUSED — refused-quota" >&2
exit 10
EOF
  chmod +x "$STUBDIR/handoff-fire.sh"
  run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --via cli
  [ ! -f "$CC_CLOUD_STATE/github-app.observed" ]
}

@test "a create that never bundles RETRACTS a recorded absent, and never flips it to present" {
  # The marker's own success condition is what makes it stale: it exists to send the operator to
  # install the App, so the install is guaranteed to obsolete it. Measured 2026-08-10 — 3/3 bundle
  # refusals wrote `absent`, the App went in minutes later, and setup kept asserting PROVEN ABSENT.
  mkdir -p "$CC_CLOUD_STATE"
  printf 'verdict=absent\nts=1\n' >"$CC_CLOUD_STATE/github-app.observed"
  echo "task" >"$BATS_TEST_TMPDIR/t.txt"
  run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --via cli
  [ "$status" -eq 0 ]
  [ ! -f "$CC_CLOUD_STATE/github-app.observed" ] || false   # retracted …
  run "$SUT" ls --json
  [[ "$output" != *"verdict=present"* ]] || false           # … but NEVER flipped to present

  # NEGATIVE CONTROL: a create that DID bundle leaves the absent verdict standing.
  printf 'verdict=absent\nts=1\n' >"$CC_CLOUD_STATE/github-app.observed"
  cat >"$STUBDIR/handoff-fire.sh" <<'EOF'
#!/usr/bin/env bash
echo "fire optin=${CC_FIRE_CLOUD:-UNSET} $*" >>"$CALLS"
echo "cloud-create: attempt 1/3 hit refused-bundle — retrying" >&2
exit 0
EOF
  chmod +x "$STUBDIR/handoff-fire.sh"
  run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --via cli
  grep -q 'verdict=absent' "$CC_CLOUD_STATE/github-app.observed" || false
}

@test "setup FAILS when the reconciler kill-switch is off (every check would pass vacuously)" {
  local fake="$BATS_TEST_TMPDIR/newclaude"
  printf '#!/usr/bin/env bash\necho "2.1.220 (Claude Code)"\n' >"$fake"; chmod +x "$fake"
  CC_CLOUD_CREATE_BIN="$fake" CC_CLOUD_RECONCILE=off run "$SUT" setup
  [ "$status" -eq 3 ]
  [[ "$output" == *VACUOUSLY* ]]
}

@test "setup reports a router that could not SEE the fleet as UNKNOWN, not exhausted" {
  cat >"$STUBDIR/claude-accounts" <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
  chmod +x "$STUBDIR/claude-accounts"
  local fake="$BATS_TEST_TMPDIR/newclaude"
  printf '#!/usr/bin/env bash\necho "2.1.220 (Claude Code)"\n' >"$fake"; chmod +x "$fake"
  CC_CLOUD_CREATE_BIN="$fake" run "$SUT" setup
  [[ "$output" == *"could not be SEEN"* ]] || false
  [[ "$output" != *"nothing routable"* ]]
}

# ══ land / gc / watch ═══════════════════════════════════════════════════════════════════════════

@test "land without --all is read-only and never passes CONFIRM" {
  run "$SUT" land
  [ "$status" -eq 0 ]
  grep -q 'reconcile confirm=UNSET --list' "$CALLS"
  ! grep -q 'confirm=1' "$CALLS"
}

@test "land --all passes CONFIRM=1 to the reconciler" {
  run "$SUT" land --all
  [ "$status" -eq 0 ]
  grep -q 'reconcile confirm=1 --all' "$CALLS"
}

@test "gc without CONFIRM lists the dead and retires nothing" {
  run "$SUT" gc
  [ "$status" -eq 0 ]
  [[ "$output" == *session_dead* ]] || false
  ! grep -q 'cc-cloud retire' "$CALLS" || false
  # POSITIVE CONTROL: the same fixture DOES retire when confirmed.
  CONFIRM=1 run "$SUT" gc
  grep -q 'cc-cloud retire --id session_dead' "$CALLS"
}

@test "gc never retires a session that is merely ALIVE" {
  CONFIRM=1 run "$SUT" gc
  [ "$status" -eq 0 ]
  ! grep -q 'retire --id session_alive' "$CALLS"
}

@test "watch refuses an interval that would hammer the remote for no new information" {
  run "$SUT" watch --interval 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"below 5s"* ]]
}

@test "watch --pane delegates the split so the anchor discipline lives in ONE place" {
  # A bare `kitty @ launch` splits whatever tab kitty last focused, not the calling pane (measured
  # 2026-08-05, three panes landed in an unrelated OS window). cc-offload must never open its own.
  KITTY_WINDOW_ID=99 run "$SUT" watch --pane
  [ "$status" -eq 0 ]
  grep -q '^split ' "$CALLS"
  ! grep -q 'launch --type=' "$SUT"
}

@test "watch --pane outside kitty degrades to a named fallback, not a crash" {
  run timeout 2 "$SUT" watch --pane --interval 5
  [[ "$output" == *"needs kitty"* ]] || [ "$status" -ne 0 ]
}

# ══ dispatch ════════════════════════════════════════════════════════════════════════════════════

@test "open never hands over a bare URL — it carries the account the link is scoped to" {
  # Measured 2026-08-10: a bare cloud URL was handed to the operator, opened under a different
  # account, and the web UI answered "This session could not be found. It may have been deleted,
  # or you may not have access." — indistinguishable from a session that never existed. A session
  # id is scoped to its CREATING account (§10.2), so an identity-scoped link without its identity
  # is a trap. Same law as: every /login instruction names the mailbox it authenticates.
  mkdir -p "$HOME/.claude"
  cat >"$HOME/.claude/accounts.json" <<'EOF'
{"accounts":[{"name":"next3","email":"who@example.com","dia_profile":"Claude3"}]}
EOF
  cat >"$STUBDIR/cc-cloud" <<'EOF'
#!/usr/bin/env bash
echo "cc-cloud $*" >>"$CALLS"
[ "$1" = show ] && { echo "account=next3"; echo "url=https://claude.ai/code/$2"; }
EOF
  chmod +x "$STUBDIR/cc-cloud"
  run "$SUT" open session_abc --print
  [ "$status" -eq 0 ]
  [[ "$output" == *next3* ]] || false
  [[ "$output" == *who@example.com* ]] || false
  [[ "$output" == *"could not be found"* ]] || false   # names the wrong-account failure mode
  [[ "$output" == *"https://claude.ai/code/session_abc"* ]] || false

  # POSITIVE CONTROL for the other arm: an undeclared account must say UNKNOWN, never go silent —
  # a bare URL with no warning is exactly the trap this test exists to prevent.
  cat >"$STUBDIR/cc-cloud" <<'EOF'
#!/usr/bin/env bash
[ "$1" = show ] && { echo "url=https://claude.ai/code/$2"; }
EOF
  chmod +x "$STUBDIR/cc-cloud"
  run "$SUT" open session_abc --print
  [[ "$output" == *UNKNOWN* ]] || false
}

@test "up --via api creates, declares, THEN delivers — and never delivers to an undeclared id" {
  # The order is forced. cc-notify refuses to claim a send about an undeclared target (exit 3), and
  # a session that exists but is undeclared is quota burning where no local instrument can see it.
  echo "brief" >"$BATS_TEST_TMPDIR/t.txt"
  mkdir -p "$CC_OFFLOAD_REPO" && git -C "$CC_OFFLOAD_REPO" init -q 2>/dev/null
  git -C "$CC_OFFLOAD_REPO" remote add origin https://github.com/renchris/claude-infrastructure.git
  cat >"$STUBDIR/create-api.py" <<'EOF'
#!/usr/bin/env python3
import sys
print(" ".join(sys.argv[1:]), file=sys.stderr)
print("session_apitest")
EOF
  chmod +x "$STUBDIR/create-api.py"
  CC_OFFLOAD_CREATE_API="$STUBDIR/create-api.py" run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --account next3
  [ "$status" -eq 0 ]
  grep -q 'cc-cloud declare --id session_apitest' "$CALLS" || false
  grep -q 'cc-notify --cloud session_apitest' "$CALLS" || false
  # declare must precede the send in the recorded order
  [ "$(grep -n 'cc-cloud declare' "$CALLS" | head -1 | cut -d: -f1)" -lt \
    "$(grep -n 'cc-notify --cloud' "$CALLS" | head -1 | cut -d: -f1)" ] || false
}

@test "up --via api derives owner/name portably (no GNU-only lazy quantifier)" {
  # The first implementation used `sed -E 's#…([^/]+/[^/]+?)…'`, which BSD sed rejects outright
  # with "repetition-operator operand invalid" — green on Linux CI, dead on every Mac that runs it.
  echo "brief" >"$BATS_TEST_TMPDIR/t.txt"
  mkdir -p "$CC_OFFLOAD_REPO" && git -C "$CC_OFFLOAD_REPO" init -q 2>/dev/null
  git -C "$CC_OFFLOAD_REPO" remote add origin git@github.com:acme/widget.git
  cat >"$STUBDIR/create-api.py" <<'EOF'
#!/usr/bin/env python3
import sys
open(__import__("os").environ["CALLS"],"a").write("api "+" ".join(sys.argv[1:])+"\n")
print("session_x")
EOF
  chmod +x "$STUBDIR/create-api.py"
  CC_OFFLOAD_CREATE_API="$STUBDIR/create-api.py" run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --account next3
  grep -q -- '--repo acme/widget' "$CALLS" || false
}

@test "up --via rejects anything but api or cli" {
  echo x >"$BATS_TEST_TMPDIR/t.txt"
  run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --via bundle
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be"* ]] || false
}

# ══ up — the W2 management arms (custody · goal · wake) ═════════════════════════════════════════
# Each of these pins a fact that CANNOT be reconstructed after the fire: the originator's pane, the
# goal, and the custody debt are properties of the moment of firing, and by the time the VM finishes
# the process that knew them is gone. A test that only checked the id would pass on the exact
# fire-and-forget behaviour W2 exists to end.

_api_fixture() { # the create stub + a git remote, shared by the arms below
  echo "brief" >"$BATS_TEST_TMPDIR/t.txt"
  mkdir -p "$CC_OFFLOAD_REPO" && git -C "$CC_OFFLOAD_REPO" init -q 2>/dev/null
  git -C "$CC_OFFLOAD_REPO" remote add origin https://github.com/renchris/claude-infrastructure.git 2>/dev/null
  cat >"$STUBDIR/create-api.py" <<'EOF'
#!/usr/bin/env python3
import sys
print(" ".join(sys.argv[1:]), file=sys.stderr)
print("session_apitest")
EOF
  chmod +x "$STUBDIR/create-api.py"
  cat >"$STUBDIR/cc-custody" <<'EOF'
#!/usr/bin/env bash
echo "cc-custody $*" >>"$CALLS"
exit "${CUSTODY_RC:-0}"
EOF
  chmod +x "$STUBDIR/cc-custody"
  export CC_OFFLOAD_CUSTODY_BIN="$STUBDIR/cc-custody"
  export CC_OFFLOAD_CREATE_API="$STUBDIR/create-api.py"
}

@test "up OPENS CUSTODY at the fire, keyed on the session id" {
  # Not at the return: a close during the flight is the hole, so the debt must exist from the
  # instant the session does.
  _api_fixture
  ITERM_SESSION_ID="w0t0p9:PANE-UUID" run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --account next3
  [ "$status" -eq 0 ]
  grep -q 'cc-custody open .*--target cloud:session_apitest' "$CALLS" || false
  grep -q 'cc-custody open .*--marker session_apitest' "$CALLS" || false
}

@test "up arms the wake target and the goal ON THE DECLARATION, where the return path can read them" {
  _api_fixture
  ITERM_SESSION_ID="w0t0p9:PANE-UUID" run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --account next3 \
    --goal "the memo is on trunk" --goal-probe "test -f x" --item deadbeef1234
  [ "$status" -eq 0 ]
  grep -q 'cc-cloud declare .*--notify-back PANE-UUID' "$CALLS" || false
  grep -q 'cc-cloud declare .*--goal the memo is on trunk' "$CALLS" || false
  grep -q 'cc-cloud declare .*--goal-probe test -f x' "$CALLS" || false
  # the backlog id must reach the declaration verbatim — the return path marks THAT item done
  grep -q 'cc-cloud declare .*--item deadbeef1234' "$CALLS" || false
  [[ "$output" == *"managed: custody OPEN"* ]] || false
}

@test "up defaults the wake target to the FIRING pane — managed is the default, not an option" {
  _api_fixture
  ITERM_SESSION_ID="w0t0p9:DEFAULTED-UUID" run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --account next3
  [ "$status" -eq 0 ]
  grep -q 'cc-cloud declare .*--notify-back DEFAULTED-UUID' "$CALLS" || false
}

@test "--unmanaged is the explicit opt-out, and SAYS so rather than looking like a managed fire" {
  # POSITIVE CONTROL for the arm above: the same fixture, the same pane, one flag — and no wake
  # target reaches the declaration. An unmanaged fire that printed identically to a managed one is
  # how fire-and-forget stayed invisible.
  _api_fixture
  ITERM_SESSION_ID="w0t0p9:DEFAULTED-UUID" run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --account next3 --unmanaged
  [ "$status" -eq 0 ]
  ! grep -q 'declare .*--notify-back' "$CALLS" || false
  [[ "$output" == *UNMANAGED* ]] || false
}

@test "a custody failure is SURFACED and never silently downgrades the fire to fire-and-forget" {
  _api_fixture
  CUSTODY_RC=3 ITERM_SESSION_ID="w0t0p9:PANE-UUID" run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --account next3
  [ "$status" -eq 0 ]                       # a fire is not aborted by bookkeeping …
  [[ "$output" == *"close-integrity arm is NOT armed"* ]] || false   # … but it is never silent
}

@test "up --via api --dry-run says WOULD, never created" {
  echo x >"$BATS_TEST_TMPDIR/t.txt"
  mkdir -p "$CC_OFFLOAD_REPO" && git -C "$CC_OFFLOAD_REPO" init -q 2>/dev/null
  git -C "$CC_OFFLOAD_REPO" remote add origin https://github.com/acme/widget.git
  # A python stub, because cc-offload invokes it with `python3` — a bash stub named .py dies with
  # SyntaxError and the test then measures the stub, not the subject.
  printf '#!/usr/bin/env python3\nraise SystemExit(0)\n' >"$STUBDIR/create-api.py"
  chmod +x "$STUBDIR/create-api.py"
  CC_OFFLOAD_CREATE_API="$STUBDIR/create-api.py" run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --account next3 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *WOULD* ]] || false
  ! grep -q 'cc-cloud declare' "$CALLS"
}

@test "an unknown verb refuses with usage rather than doing something adjacent" {
  run "$SUT" frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown verb"* ]]
}

@test "the bare command is the board" {
  run "$SUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *SESSION* ]]
}

@test "--help names every verb the dispatch actually accepts" {
  run "$SUT" --help
  [ "$status" -eq 0 ]
  for v in setup up ls watch say land open gc; do
    [[ "$output" == *"cc-offload $v"* ]] || false
  done
}

# ── THE API LANE'S BRIEF IS A PAYLOAD, NOT A MESSAGE (backlog 0c8b39b67665) ────────────────────
# This lane used to hand cc-notify the operator's brief RAW — no branch, no push instruction of any
# kind. The sibling CLI lane at least told its session to push before finishing; this one told it
# nothing, so a session created here could do the whole job, commit it, and be reclaimed with the
# container. And for the instrument it is worse than a lost result: with no push instructed, "no ref
# past the boot budget" is the EXPECTED reading of a healthy session, so CLOUD_OBSERVABILITY.md
# §4.3's C1 NOT-STARTED had no contract under it while three oracles still consumed it — one of them
# the destructive `com.claude.team-orphan-reaper` (§5.2).
#
# RED-PROOF (re-runnable): replay against `git show 9e00181c:bin/cc-offload`. RED — the delivered
# brief is `$(cat "$pf")` and nothing else, so neither the branch nor `--allow-empty` appears.
@test "up --via api delivers the BOOT BEACON with the brief, keyed on the branch it declared" {
  echo "brief" >"$BATS_TEST_TMPDIR/t.txt"
  mkdir -p "$CC_OFFLOAD_REPO" && git -C "$CC_OFFLOAD_REPO" init -q 2>/dev/null
  git -C "$CC_OFFLOAD_REPO" remote add origin https://github.com/renchris/claude-infrastructure.git
  cat >"$STUBDIR/create-api.py" <<'EOF'
#!/usr/bin/env python3
import sys
print("session_beacon")
EOF
  chmod +x "$STUBDIR/create-api.py"
  CC_OFFLOAD_CREATE_API="$STUBDIR/create-api.py" run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --account next3
  [ "$status" -eq 0 ]
  # The operator's own brief still arrives — the trailer is an addition, never a replacement.
  grep -q 'brief' "$CALLS" || false
  grep -q -- '--allow-empty' "$CALLS" \
    || { echo "the delivered brief instructs no boot beacon — a healthy session reads NOT-STARTED"; false; }
  # THE SAME branch that was declared. A beacon pushed to a different name is watched by nothing,
  # which is the §11.2 finding-2 defect (a declaration against a branch with no producer) arriving
  # from the other side.
  local br
  br="$(grep -o -- '--branch claude/fire-[A-Za-z0-9._/-]*' "$CALLS" | head -1 | awk '{print $2}')"
  [ -n "$br" ] || { echo "no branch was declared at all"; false; }
  grep -q "git switch -c $br" "$CALLS" || { echo "the beacon targets a branch other than the declared $br"; false; }
}

@test "up --via api REFUSES before the create when the trailer library has no beacon" {
  # A create is quota. Spending it on a session that is unobservable by construction is the failure
  # this lane exists to end, so the precondition is checked first and fail-closed — the same
  # direction as the CLI lane's own lib-absent refusal.
  echo "brief" >"$BATS_TEST_TMPDIR/t.txt"
  mkdir -p "$CC_OFFLOAD_REPO" && git -C "$CC_OFFLOAD_REPO" init -q 2>/dev/null
  git -C "$CC_OFFLOAD_REPO" remote add origin https://github.com/renchris/claude-infrastructure.git
  cat >"$STUBDIR/create-api.py" <<'EOF'
#!/usr/bin/env python3
import sys, os
open(os.environ["CALLS"],"a").write("api-create-REACHED\n")
print("session_never")
EOF
  chmod +x "$STUBDIR/create-api.py"
  : >"$BATS_TEST_TMPDIR/empty-lib.sh"
  CC_OFFLOAD_CREATE_API="$STUBDIR/create-api.py" \
  CC_OFFLOAD_CREATE_LIB="$BATS_TEST_TMPDIR/empty-lib.sh" \
    run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt" --account next3
  [ "$status" -ne 0 ]
  ! grep -q 'api-create-REACHED' "$CALLS" || { echo "quota spent on an unobservable session"; false; }
}
