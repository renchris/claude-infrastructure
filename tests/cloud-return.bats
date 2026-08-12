#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats: every @test body IS its own subshell, so an `export` inside one
#   is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are invoked from those test
#   subshells rather than from file scope (SC2329).
#
# cloud-return.sh — THE RETURN PATH for a cloud fire (CLOUD_BACKLOG_PIPELINE.md W2).
#
# WHAT THIS SUITE IS GUARDING. This script is the one thing on the cloud lane that ACTS unattended:
# it lands a branch, marks a backlog item done, discharges a custody debt and tells the originator
# it is safe to close. Every defect available to it is therefore a FALSE COMPLETION — acting on a
# session that is not finished, or reporting one that did not land. Each arm below pins one:
#
#   · `idle` alone must NEVER trigger a land        [shutdown-request-is-not-an-actuator]
#   · a sensor that could not run is not a verdict  [lookup-miss-is-not-absence]
#   · landedness is BY CONTENT, never by sha        (the land re-authors; the pushed sha never lands)
#   · custody/done are discharged only on a VERIFIED land — over an unverified one they would
#     delete the exact mechanism that was going to catch it
#   · the sweep acts only on what the sweep ARMED   (a pre-W2 stranded branch is not its business)
#
# HERMETIC: real git, real local bare remotes, the REAL bin/cc-cloud as the state arbiter (its
# verdicts are the input this file is about, and a stub would test the stub). Only the four things
# that reach the outside world — the control plane, the lander, cc-notify, cc-custody/cc-backlog —
# are stubs, and they RECORD their argv so the tests assert on what was asked for, not on prose.

setup() {
  SUT="${BATS_TEST_DIRNAME}/../scripts/cloud-return.sh"
  [ -x "$SUT" ] || skip "cloud-return.sh not executable"
  command -v jq >/dev/null 2>&1 || skip "jq required"
  CCLOUD="${BATS_TEST_DIRNAME}/../bin/cc-cloud"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_CLOUD_STATE="$BATS_TEST_TMPDIR/state"; mkdir -p "$CC_CLOUD_STATE"
  export CC_RETURN_CLOUD_BIN="$CCLOUD"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : >"$CALLS"
  export STUBDIR="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBDIR"

  export REMOTE="$BATS_TEST_TMPDIR/remote.git"
  export WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$REMOTE"
  git init -q "$WORK"
  git -C "$WORK" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed
  SEED="$(git -C "$WORK" rev-parse HEAD)"
  git -C "$WORK" branch trunkref "$SEED"
  # the VM's branch: one added file, plus a deletion that must never enter the path set
  git -C "$WORK" checkout -q -b claude/vm "$SEED"
  mkdir -p "$WORK/docs" && printf 'from the vm\n' >"$WORK/docs/vm.md" && printf 'x\n' >"$WORK/doomed"
  git -C "$WORK" add -A
  git -C "$WORK" -c user.email=vm@anthropic -c user.name=vm commit -q -m "vm work"
  git -C "$WORK" rm -q "$WORK/doomed"
  git -C "$WORK" -c user.email=vm@anthropic -c user.name=vm commit -q -m "vm cleanup"
  git -C "$WORK" checkout -q "$SEED"
  # DELIBERATELY NOT PUSHED HERE. A declaration is made BEFORE the fire, and cc-cloud records the
  # branch's pre-fire sha as its baseline: a branch that already exists at declare time reads
  # BOOTING for its whole life budget, never ALIVE. Pushing in setup() would have made every arm
  # below grade a never-booted session and pass for the wrong reason.

  # ── the control plane. Default: idle (which is ALSO the between-turns state — that is the point).
  export STATUS_JSON="$BATS_TEST_TMPDIR/status.json"
  printf '{"worker_status":"idle","status_bucket":"review_ready"}\n' >"$STATUS_JSON"
  cat >"$STUBDIR/status.py" <<'EOF'
import os, sys
sys.stderr.write("status " + " ".join(sys.argv[1:]) + "\n")
if os.environ.get("STATUS_FAIL") == "1":
    sys.exit(1)
sys.stdout.write(open(os.environ["STATUS_JSON"]).read())
EOF
  export CC_RETURN_STATUS_BIN="$STUBDIR/status.py"

  # ── the lander. On success it replays the branch's TREE onto trunkref as a NEW commit — which is
  # what the real reconciler does (it re-authors), so the content is identical and the sha is not.
  # A stub that fast-forwarded would prove landedness by ancestry and never exercise the by-content
  # rule this whole rail turns on.
  cat >"$STUBDIR/reconcile.sh" <<'EOF'
#!/usr/bin/env bash
echo "reconcile confirm=${CONFIRM:-UNSET} $*" >>"$CALLS"
[ "${LAND_SAY_KILLED:-0}" = 1 ] && echo "✗ ship-land: verdict=killed signal=SIGTERM role=outer — TERMINATED from outside"
[ "${LAND_RC:-0}" = 0 ] || { echo "!! land refused (stub)"; exit "${LAND_RC}"; }
[ "${LAND_EMPTY:-0}" = 1 ] && { echo "stub: reported success and landed NOTHING"; exit 0; }
b="$2"
tree="$(git -C "$WORK" rev-parse "refs/heads/$b^{tree}")"
new="$(git -C "$WORK" commit-tree "$tree" -p refs/heads/trunkref -m "landed by a re-author")"
git -C "$WORK" update-ref refs/heads/trunkref "$new"
echo "✓ $b — landed via stub"
EOF
  cat >"$STUBDIR/cc-notify" <<'EOF'
#!/usr/bin/env bash
echo "cc-notify $*" >>"$CALLS"
echo "wake-path armed" >&2
exit "${NOTIFY_RC:-0}"
EOF
  cat >"$STUBDIR/cc-custody" <<'EOF'
#!/usr/bin/env bash
echo "cc-custody $*" >>"$CALLS"
EOF
  cat >"$STUBDIR/cc-backlog" <<'EOF'
#!/usr/bin/env bash
echo "cc-backlog $*" >>"$CALLS"
EOF
  chmod +x "$STUBDIR"/*
  export CC_RETURN_RECONCILE_BIN="$STUBDIR/reconcile.sh"
  export CC_RETURN_NOTIFY_BIN="$STUBDIR/cc-notify"
  export CC_RETURN_CUSTODY_BIN="$STUBDIR/cc-custody"
  export CC_RETURN_BACKLOG_BIN="$STUBDIR/cc-backlog"
}

# Declare a MANAGED cloud session against the fixture, exactly as `cc-offload up` would.
declare_managed() { # [extra cc-cloud declare args…]
  "$CCLOUD" declare --id session_test --branch claude/vm --remote "$REMOTE" --repo "$WORK" \
    --trunk trunkref --account next3 --custody session_test --notify-back PANE-UUID \
    --url "https://claude.ai/code/session_test" "$@" >/dev/null 2>&1
  push_vm
}

# The VM pushing, AFTER the declaration — the order the real thing happens in, and the order that
# makes the state function say ALIVE rather than BOOTING.
push_vm() {
  git -C "$WORK" push -q "$REMOTE" refs/heads/claude/vm:refs/heads/claude/vm 2>/dev/null || true
}

# The push-history sidecar cc-cloud's `poll` writes. `since` is how long the sha has been quiet, and
# it is the axis that makes `idle` mean something — so every test states it explicitly.
seen_at() { # <epoch>
  { printf 'sha=%s\n' "$(git -C "$WORK" rev-parse refs/heads/claude/vm)"; printf 'since=%s\n' "$1"; } \
    >"$CC_CLOUD_STATE/session_test.seen"
}

# ══ RETURN-READY is a CONJUNCTION ═══════════════════════════════════════════════════════════════

@test "a worker that is still RUNNING is never landed" {
  declare_managed
  printf '{"worker_status":"working"}\n' >"$STATUS_JSON"
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"still running"* ]] || false
  ! grep -q reconcile "$CALLS" || false
}

@test "IDLE ALONE DOES NOT LAND — a session between turns reads exactly like a finished one" {
  # The arm this whole design turns on. Measured 2026-08-11: a session that finished 14h earlier and
  # one fired 4 MINUTES earlier both read worker_status=idle. Landing on that flag alone cuts a live
  # session off mid-flight and lands a half-finished branch.
  declare_managed
  seen_at 999900                       # pushed 100s ago …
  CC_RETURN_NOW=1000000 CC_RETURN_QUIET_S=180 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"needs 180s quiet"* ]] || false
  ! grep -q reconcile "$CALLS" || false
  # POSITIVE CONTROL, same fixture, one axis moved: with the push quiet, it DOES land.
  CC_RETURN_NOW=1000000 CC_RETURN_QUIET_S=60 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  grep -q 'reconcile confirm=1 --land claude/vm' "$CALLS" || false
}

@test "a control plane that cannot be read ABSTAINS — it never reads as 'finished'" {
  declare_managed
  seen_at 1000
  STATUS_FAIL=1 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *abstaining* ]] || false
  ! grep -q reconcile "$CALLS" || false
}

@test "a session that has pushed NOTHING is not a return candidate" {
  "$CCLOUD" declare --id session_nopush --branch claude/never --remote "$REMOTE" --repo "$WORK" \
    --trunk trunkref --account next3 --custody session_nopush --notify-back P >/dev/null 2>&1
  run "$SUT" --sweep
  [ "$status" -eq 0 ]
  ! grep -q reconcile "$CALLS" || false
}

# ══ THE HAPPY PATH, end to end ══════════════════════════════════════════════════════════════════

@test "a finished session lands, is content-verified, marks the item done, discharges custody, and WAKES the originator" {
  declare_managed --item deadbeef1234
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  grep -q 'reconcile confirm=1 --land claude/vm' "$CALLS" || false
  [[ "$output" == *"content-verified on trunkref: docs/vm.md"* ]] || false
  # the DELETED path never enters the set — it could not be content-present on trunk after a land
  [[ "$output" != *doomed* ]] || false
  grep -q 'cc-backlog done deadbeef1234' "$CALLS" || false
  grep -q 'cc-custody return session_test' "$CALLS" || false
  grep -q 'cc-notify PANE-UUID HANDOFF-PING cloud/session_test: LANDED+VERIFIED' "$CALLS" || false
}

@test "the wake fires ONCE, ever — an originator re-woken every sweep is an alarm that carries no bits" {
  # ASSERTS THE PROPERTY, NOT THE MECHANISM THAT USED TO DELIVER IT (revised 2026-08-12).
  # This case previously required the second sweep to print "already returned", i.e. it pinned the
  # `.returned` short-circuit as the specific route to wake-once. A terminal session is now also
  # RETIRED (`cc-cloud retire`, the verb that had zero callers and whose absence wedged the
  # dispatcher's ceiling at fired:0), and a retired id leaves `cc-cloud ids()` altogether — so the
  # second sweep does not reach handle() at all. Wake-once is therefore MORE strongly guaranteed
  # than before, by an earlier exit. The invariant under test is "the originator is pinged exactly
  # once", so that is what is asserted; either terminal shape satisfies it, and the count assertion
  # is what would catch a regression.
  declare_managed --item deadbeef1234
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$(grep -c 'cc-notify' "$CALLS")" -eq 1 ]
  [[ "$output" == *"slot: retired"* ]] || false      # the terminal state was reached and released
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$(grep -c 'cc-notify' "$CALLS")" -eq 1 ]        # THE PROPERTY: still exactly one ping, ever
}

@test "a close that FAILS is retried without re-pinging the originator (the two latches are split)" {
  # The regression this pairs with: joining the backlog close to the latch (so a failed close is
  # retryable) would, with a single latch, have re-woken the originator on every sweep — trading a
  # permanent silent failure for a permanent alarm. `.woken` and `.returned` are separate for this
  # reason, and this is the case that holds them apart.
  cat >"$STUBDIR/cc-backlog" <<'EOF'
#!/usr/bin/env bash
echo "cc-backlog $*" >>"$CALLS"
case "$1" in done) echo "refused: contention" >&2; exit 1 ;; esac
EOF
  chmod +x "$STUBDIR/cc-backlog"
  declare_managed --item deadbeef1234
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$(grep -c 'cc-notify' "$CALLS")" -eq 1 ]
  [[ "$output" == *"could NOT mark deadbeef1234 done"* ]] || false
  [[ "$output" == *"refused: contention"* ]] || false   # the reason survives, not >/dev/null
  [[ "$output" != *"slot: retired"* ]] || false         # NOT terminal — the slot is still held
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [[ "$output" == *"already sent"* ]] || false          # retried…
  [ "$(grep -c 'cc-notify' "$CALLS")" -eq 1 ]           # …and still exactly one ping
}

# ══ THE LAUNDERING GUARDS ═══════════════════════════════════════════════════════════════════════

@test "a lander that reports success while landing NOTHING is caught by the CONTENT check" {
  # The one failure a sha- or exit-code-based check cannot see. Custody and the backlog item must
  # both survive it: discharging them here would delete the mechanism that was going to catch it.
  declare_managed --item deadbeef1234
  seen_at 1000
  LAND_EMPTY=1 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT content-verified"* ]] || false
  [[ "$output" == *"left deadbeef1234 open"* ]] || false
  [[ "$output" == *"left session_test OPEN"* ]] || false
  ! grep -q 'cc-backlog done' "$CALLS" || false
  ! grep -q 'cc-custody return' "$CALLS" || false
}

@test "a REFUSED land records the W3 artifact, wakes the originator with the failure, and keeps custody open" {
  declare_managed --item deadbeef1234
  seen_at 1000
  LAND_RC=6 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"land REFUSED (exit 6)"* ]] || false
  [ -f "$CC_CLOUD_STATE/session_test.land-refused" ]
  grep -q 'rc=6' "$CC_CLOUD_STATE/session_test.land-refused"
  grep -q 'cc-notify PANE-UUID HANDOFF-PING cloud/session_test: LAND REFUSED' "$CALLS" || false
  ! grep -q 'cc-custody return' "$CALLS" || false
  ! grep -q 'cc-backlog done' "$CALLS" || false
  # NOT latched: the next sweep must retry rather than leaving the work stranded forever
  [ ! -f "$CC_CLOUD_STATE/session_test.returned" ]
}

@test "a free-text item is never passed to cc-backlog done as if it were an id" {
  # `item` is free text by contract — `cc-offload up` writes "cc-offload <file>" when no backlog id
  # was given. Only the store's own 12-hex shape is treated as a key.
  declare_managed --item "cc-offload brief.txt"
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"no backlog item recorded"* ]] || false
  ! grep -q 'cc-backlog done' "$CALLS" || false
  grep -q 'cc-custody return session_test' "$CALLS" || false   # the rest of the return still runs
}

# ══ THE GOAL, judged from THIS side ═════════════════════════════════════════════════════════════

@test "with no probe the goal IS the landed-by-content verdict" {
  declare_managed
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [[ "$output" == *"goal: MET"* ]] || false
  [[ "$output" == *"default: landed by content"* ]] || false
}

@test "a recorded goal probe DECIDES it — a failing probe is NOT-MET, never silently met" {
  # The probe reads the TRUNK REF, not the working tree: the declared repo is a checkout somebody
  # else owns and may sit on any branch, so a working-tree read grades whatever happens to be
  # checked out — and grep's exit 2 (no such file) would be indistinguishable from a real miss.
  declare_managed --goal "the memo names the branch" \
    --goal-probe "git show trunkref:docs/vm.md | grep -q NOTHING-LIKE-THIS"
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [[ "$output" == *"goal: NOT-MET"* ]] || false
  [[ "$output" == *"the memo names the branch"* ]] || false
}

@test "…and the POSITIVE CONTROL: a probe that passes reads MET" {
  # A SEPARATE test rather than a second half of the one above, and the reason is a property of the
  # subject: the first pass LANDS, which mutates the fixture's trunk. Re-declaring over it would
  # reset the baseline to the already-pushed sha and the session would read BOOTING — the control
  # would then pass or fail for a reason that has nothing to do with the probe. bats gives each test
  # a fresh setup(), which is the only clean way to hold every other axis still.
  declare_managed --goal "the memo is there" \
    --goal-probe "git show trunkref:docs/vm.md | grep -q 'from the vm'"
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [[ "$output" == *"goal: MET"* ]] || false
  [[ "$output" == *"the memo is there"* ]] || false
}

# ══ THE SWEEP'S POPULATION ══════════════════════════════════════════════════════════════════════

@test "the sweep ignores an UNMANAGED declaration but --id still acts on one a person named" {
  # Pre-W2 declarations were fired with nobody promising to land them; several on the real box have
  # pushed, never-landed branches. Sweeping those up would be this script deciding unattended that a
  # three-day-old stranded branch belongs on trunk.
  "$CCLOUD" declare --id session_legacy --branch claude/vm --remote "$REMOTE" --repo "$WORK" \
    --trunk trunkref --account next3 >/dev/null 2>&1
  push_vm
  { printf 'sha=%s\n' "$(git -C "$WORK" rev-parse refs/heads/claude/vm)"; printf 'since=1000\n'; } \
    >"$CC_CLOUD_STATE/session_legacy.seen"
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"no MANAGED cloud declarations"* ]] || false
  ! grep -q reconcile "$CALLS" || false
  # POSITIVE CONTROL: named explicitly, the very same declaration IS actioned.
  CC_RETURN_NOW=999999 run "$SUT" --id session_legacy
  [ "$status" -eq 0 ]
  grep -q 'reconcile confirm=1 --land claude/vm' "$CALLS" || false
}

@test "--dry-run reports RETURN-READY and lands nothing" {
  declare_managed
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"RETURN-READY"* ]] || false
  ! grep -q reconcile "$CALLS" || false
  [ ! -f "$CC_CLOUD_STATE/session_test.returned" ]
}

@test "the pass is SINGLE-FLIGHT — a second one refuses rather than racing the lander" {
  declare_managed
  seen_at 1000
  mkdir -p "$CC_CLOUD_STATE/.return.lock"
  printf '%s\n' 999998 >"$CC_CLOUD_STATE/.return.lock/at"
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 4 ]
  ! grep -q reconcile "$CALLS" || false
  # …and a STALE lock is reaped rather than wedging the rail forever (the failure mode of a
  # lockfile with no reaper).
  CC_RETURN_NOW=1999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  grep -q reconcile "$CALLS" || false
}

@test "usage is refused loudly — a verbless run must never sweep by accident" {
  run "$SUT"
  [ "$status" -eq 2 ]
  run "$SUT" --nonsense
  [ "$status" -eq 2 ]
}

# ══ THE CALLER ══════════════════════════════════════════════════════════════════════════════════
# This repo's most-repeated defect is a correct tool with ZERO CALLERS — a7bf7068's falsifier
# emitter, 596b39a7's cluster detector and settings-drift-assert.sh all landed inert, and the last
# one had been correct-and-uncalled for its entire life. A return path nothing invokes is exactly
# that shape: every arm above would stay green while no cloud session was ever returned. These two
# arms assert the WIRING, and they are structural on purpose — running the real 300 s sweep here
# would cost more than the suite it lives in.

@test "autonomy-sweep INVOKES cloud-return --sweep (a return path nothing calls returns nothing)" {
  local sweep="${BATS_TEST_DIRNAME}/../scripts/autonomy-sweep.sh"
  [ -f "$sweep" ] || skip "autonomy-sweep.sh absent"
  grep -q 'cloud-return.sh' "$sweep"
  grep -q -- '--sweep' "$sweep"
}

@test "…and it is called ABOVE the nothing-new early exit, where a quiet fleet still reaches it" {
  # A finished cloud session produces no page and no alarm — it is silent by construction — so a
  # call site below `total_new -eq 0` would run only on sweeps that already had other news, which
  # on a quiet store is never. Same placement rule, and same reason, as the backlog-health block.
  local sweep="${BATS_TEST_DIRNAME}/../scripts/autonomy-sweep.sh"
  [ -f "$sweep" ] || skip "autonomy-sweep.sh absent"
  # Both anchors are CODE, not prose. The first cut of this test grepped the phrase "nothing-new",
  # which appears in three COMMENTS above the exit it names — so it measured a sentence and reported
  # the call site as too late. Anchor on the mechanism: the assignment that names the tool, and the
  # `total_new` test that IS the early exit.
  local call_line exit_line
  call_line="$(grep -n 'cloud-return.sh' "$sweep" | head -1 | cut -d: -f1)"
  exit_line="$(grep -n 'total_new" -eq 0' "$sweep" | head -1 | cut -d: -f1)"
  [ -n "$call_line" ] && [ -n "$exit_line" ] || false
  [ "$call_line" -lt "$exit_line" ]
}

@test "the sweep's call is GATED to the deployed copy — a suite may never land a branch" {
  # Bought at full price on 2026-08-11: tests/autonomy-sweep.bats runs the real sweep once per test,
  # postland-verify runs that suite from a throwaway worktree of the landed tree, and four
  # concurrent passes landed against the operator's LIVE declaration store, raced the backlog ledger
  # and re-pinged the originator. Every other block in that script is a pure read; this one acts.
  local sweep="${BATS_TEST_DIRNAME}/../scripts/autonomy-sweep.sh"
  [ -f "$sweep" ] || skip "autonomy-sweep.sh absent"
  grep -q 'CLAUDE_CONFIG_DIR' "$sweep"
  grep -q 'skipped-not-deployed' "$sweep"
  # The gate must key on the UNRESOLVED $0: the deployed path is a SYMLINK into the checkout, so a
  # resolved path is identical in both cases and the discriminator disappears.
  local gate_line res_line
  gate_line="$(grep -n 'case "\$0" in' "$sweep" | head -1 | cut -d: -f1)"
  [ -n "$gate_line" ]
  # …and it must precede the invocation it guards.
  res_line="$(grep -n 'cloud-return.sh --sweep' "$sweep" | head -1 | cut -d: -f1)"
  [ -z "$res_line" ] || [ "$gate_line" -lt "$res_line" ]
}

@test "a land CUT by a bound is a NON-VERDICT — no refusal artifact, no 'REFUSED' wake, no latch" {
  # Measured on the second live round trip: the sweep's 240s bound killed a healthy land, ship-land
  # said `verdict=killed signal=SIGTERM … nothing was proven about the tree`, and this code filed a
  # land-refused artifact and woke the originator with a refusal. A bound smaller than what it
  # bounds can only convict (memory: exoneration-bound-must-fit-what-it-bounds).
  declare_managed --item deadbeef1234
  seen_at 1000
  LAND_RC=143 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"CUT by a bound"* ]] || false
  [[ "$output" != *"REFUSED"* ]] || false
  [ ! -f "$CC_CLOUD_STATE/session_test.land-refused" ]
  [ ! -f "$CC_CLOUD_STATE/session_test.returned" ]
  ! grep -q 'HANDOFF-PING' "$CALLS" || false
  # POSITIVE CONTROL off the same fixture: a REAL gate red still files the artifact and wakes.
  LAND_RC=6 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ -f "$CC_CLOUD_STATE/session_test.land-refused" ]
  grep -q 'HANDOFF-PING cloud/session_test: LAND REFUSED' "$CALLS" || false
}

@test "ship-land's OWN killed token abstains too, whatever exit code reaches us" {
  # The signal can arrive as 124, 137 or 143 depending on who cut it and how, so the lander's own
  # verdict token is read as corroboration rather than trusting one number to carry the fact.
  declare_managed
  seen_at 1000
  LAND_RC=70 LAND_SAY_KILLED=1 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"CUT by a bound"* ]] || false
  [ ! -f "$CC_CLOUD_STATE/session_test.land-refused" ]
}
