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
  retire) echo "retired $3" ;;
  show) echo "url=https://claude.ai/code/$2" ;;
  *) exit 2 ;;
esac
EOF
  cat >"$STUBDIR/cc-notify" <<'EOF'
#!/usr/bin/env bash
echo "cc-notify $*" >>"$CALLS"
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
  run "$SUT" up --task "$BATS_TEST_TMPDIR/task.txt"
  [ "$status" -eq 0 ]
  grep -q '^fire optin=on ' "$CALLS"
  grep -q -- '--cloud' "$CALLS"
  grep -q -- '--prompt-file' "$CALLS"
}

@test "up on exit 11 (live but undeclared) is LOUD and does NOT retry" {
  # 11 means a session is spending quota that nothing local can see, address or reap. Retrying it
  # buys a SECOND invisible session. With -n 3 the fire must be invoked exactly once.
  echo "task" >"$BATS_TEST_TMPDIR/task.txt"
  FIRE_RC=11 run "$SUT" up --task "$BATS_TEST_TMPDIR/task.txt" -n 3
  [ "$status" -eq 11 ]
  [[ "$output" == *"IS LIVE"* ]] || [[ "$output" == *"EXIT 11"* ]] || false
  [ "$(grep -c '^fire ' "$CALLS")" -eq 1 ]
}

@test "up on exit 10 says nothing is running — the safe-to-retry case" {
  echo "task" >"$BATS_TEST_TMPDIR/task.txt"
  FIRE_RC=10 run "$SUT" up --task "$BATS_TEST_TMPDIR/task.txt"
  [ "$status" -eq 10 ]
  [[ "$output" == *"NOTHING is running"* ]]
}

@test "up refuses an empty brief" {
  : >"$BATS_TEST_TMPDIR/empty.txt"
  run "$SUT" up --task "$BATS_TEST_TMPDIR/empty.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *empty* ]] || false
  ! grep -q '^fire ' "$CALLS"
}

@test "up refuses a missing task file rather than firing blind" {
  run "$SUT" up --task "$BATS_TEST_TMPDIR/nope.txt"
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
  run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt"
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
  run "$SUT" up --task "$BATS_TEST_TMPDIR/t.txt"
  [ ! -f "$CC_CLOUD_STATE/github-app.observed" ]
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
