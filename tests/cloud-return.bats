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
# IDENTITY ON THE COMMAND, like every other commit this suite makes (lines 42/49/51). setup()
# fixtures $HOME for hermeticity, which hides ~/.gitconfig — so on any box whose identity lives
# there rather than in the environment (a cloud VM, a fresh CI runner) this was the ONE commit in
# the file with no identity to fall back on. It died with `unable to auto-detect email address`,
# trunkref never received the tree, and SIX cases went red on the content-verify leg: precisely the
# shape of "the return rail is broken", against pristine trunk, for a reason that is entirely the
# environment's. Recorded in docs/research/cloud-land-arm-step-2026-08-25.md §4, where those reds
# were nearly reported as corroboration that the lane had stopped.
new="$(git -C "$WORK" -c user.email=lander@t -c user.name=lander commit-tree "$tree" -p refs/heads/trunkref -m "landed by a re-author")"
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

@test "the abstain NAMES ITS CAUSE — the callee's stderr and rc reach the ledger, not a bare 'unreadable'" {
  # The defect this pins, measured on the live box 2026-08-17: 384 abstain rows, every one of them
  # exactly `{"why":"control plane unreadable"}`, and not one able to tell a locked keychain from a
  # missing python3 from an expired grant — three failures with three unrelated repairs. TWO things
  # had to be true for that: the sensor muted its callee with `2>/dev/null`, AND its caller invoked
  # it inside a command substitution, so any diagnostic it set would have died in that subshell
  # regardless. Both halves are asserted here, because fixing either one alone changes nothing.
  declare_managed
  seen_at 1000
  export CC_RETURN_LEDGER="$BATS_TEST_TMPDIR/ledger.jsonl"
  STATUS_FAIL=1 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]

  row="$(jq -c 'select(.outcome=="abstain")' "$CC_RETURN_LEDGER" | head -1)"
  [ -n "$row" ] || false
  # the callee's OWN stderr survived the subshell — the stub writes its argv there, which is the
  # slot a real cloud-create-api.py `die()` line ("keychain item … unreadable (rc N)") occupies
  [[ "$(printf '%s' "$row" | jq -r '.err')" == *"--verify"* ]] || false
  # the rc, which is the field that separates the three repairs above
  [ "$(printf '%s' "$row" | jq -r '.rc')" = 1 ]
  # and the account, because a session id is only readable through the account that created it
  [ "$(printf '%s' "$row" | jq -r '.account')" = next3 ]
  # the operator-facing line carries it too — a diagnosis only the ledger holds is one nobody reads
  [[ "$output" == *"rc 1"* ]] || false
}

@test "a declaration with NO account abstains on THAT, and never on a generic 'unreadable'" {
  # The sensor's first refusal is local and costs no network. It must stay distinguishable from an
  # API failure: "nobody recorded an account" and "the control plane refused us" share no repair.
  "$CCLOUD" declare --id session_noacct --branch claude/vm --remote "$REMOTE" --repo "$WORK" \
    --trunk trunkref --custody session_noacct --notify-back P >/dev/null 2>&1
  push_vm
  { printf 'sha=%s\n' "$(git -C "$WORK" rev-parse refs/heads/claude/vm)"; printf 'since=1000\n'; } \
    >"$CC_CLOUD_STATE/session_noacct.seen"
  export CC_RETURN_LEDGER="$BATS_TEST_TMPDIR/ledger.jsonl"
  CC_RETURN_NOW=999999 run "$SUT" --id session_noacct
  [ "$status" -eq 0 ]
  row="$(jq -c 'select(.id=="session_noacct" and .outcome=="abstain")' "$CC_RETURN_LEDGER" | head -1)"
  [ -n "$row" ] || false
  [ "$(printf '%s' "$row" | jq -r '.rc')" = no-account ]
  [[ "$(printf '%s' "$row" | jq -r '.err')" == *"records no account"* ]] || false
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

# ══ THE PARK — the second terminal disposition ══════════════════════════════════════════════════
#
# A cloud worker can finish a row (`done`) or discover that the next step is the OPERATOR's, which
# it cannot take. The brief tells it to park those with `cc-backlog block`, and that verb cannot
# reach the store from a VM — it answers `unknown id`, exits 3, writes nothing. The row therefore
# stayed `open` and was re-dispatched forever (f85fce7c26f5: ten dispatches, ten branches, one
# unchanged verdict). The park is now a landed file the VM CAN push, and these four arms pin the
# properties that make it safe to act on unattended.

# Append an entry to the park log on the VM's branch, exactly as scripts/cloud-park.sh writes it.
park_entry_on_vm() { # <id> <branch-named-in-the-entry> <needs>
  git -C "$WORK" checkout -q claude/vm
  mkdir -p "$WORK/docs/parks"
  { printf '## 2026-08-29T00:00:00Z\n\n'; printf 'branch: %s\n' "$2"; printf 'needs: %s\n' "$3"; printf '\n'; } \
    >>"$WORK/docs/parks/$1.md"
  git -C "$WORK" add -A
  git -C "$WORK" -c user.email=vm@anthropic -c user.name=vm commit -q -m "park $1"
  git -C "$WORK" checkout -q "$SEED"
}

@test "a park written by THIS dispatch BLOCKS the row on the operator's step instead of closing it" {
  # Two entries, and the LAST one is this branch's: the reader must take the last, or a row's park
  # history would make the first dispatch that ever parked it the permanent answer.
  park_entry_on_vm deadbeef1234 claude/superseded "an older dispatch's step"
  park_entry_on_vm deadbeef1234 claude/vm "bash scripts/cloud-land-arm-diagnose.sh"
  declare_managed --item deadbeef1234
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  grep -q 'cc-backlog block deadbeef1234 --needs bash scripts/cloud-land-arm-diagnose.sh' "$CALLS" || false
  ! grep -q 'cc-backlog done' "$CALLS" || false
  [[ "$output" == *"PARKED deadbeef1234 on the operator: bash scripts/cloud-land-arm-diagnose.sh"* ]] || false
  # A park is TERMINAL for this dispatch: the land is verified, so custody is discharged and the
  # admission slot is released. Leaving the slot held is how a parked row silently costs a worker.
  grep -q 'cc-custody return session_test' "$CALLS" || false
  [[ "$output" == *"slot: retired"* ]] || false
  [ "$(grep -c 'cc-notify' "$CALLS")" -eq 1 ]
}

@test "a park from an EARLIER dispatch is inert — the file outlives the park, the park does not" {
  # The failure this refuses: docs/parks/<id>.md stays on trunk after the operator unblocks the row,
  # so a reader keyed on the file's EXISTENCE would re-block the row on the next land, forever.
  park_entry_on_vm deadbeef1234 claude/some-older-fire "a step that was taken three days ago"
  declare_managed --item deadbeef1234
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"an earlier dispatch's park, not this one's; ignored"* ]] || false
  grep -q 'cc-backlog done deadbeef1234' "$CALLS" || false
  ! grep -q 'cc-backlog block' "$CALLS" || false
}

@test "a park naming this branch with NO step in it settles NOTHING — neither parked nor done" {
  # The worker said "this is not finished" and the only executable half of that statement is missing.
  # Falling through to `done` here would be the loudest false completion available on this rail.
  park_entry_on_vm deadbeef1234 claude/vm ""
  declare_managed --item deadbeef1234
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"REFUSED to settle deadbeef1234"* ]] || false
  ! grep -q 'cc-backlog done' "$CALLS" || false
  ! grep -q 'cc-backlog block' "$CALLS" || false
  [[ "$output" != *"slot: retired"* ]] || false     # unsettled ⇒ not latched, the next sweep retries
}

@test "the park is read from the TRUNK REF, never from a working tree" {
  # It is acted on unattended, so it must have passed the same content-verify as everything else
  # this step touches. A `[ -f "$repo/docs/parks/<id>.md" ]` spelling would honour a file that never
  # landed — and on the operator's box `$repo` is a live checkout somebody is working in.
  mkdir -p "$WORK/docs/parks"
  printf 'branch: claude/vm\nneeds: a step that was never committed\n' >"$WORK/docs/parks/deadbeef1234.md"
  declare_managed --item deadbeef1234
  seen_at 1000
  CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  grep -q 'cc-backlog done deadbeef1234' "$CALLS" || false
  ! grep -q 'cc-backlog block' "$CALLS" || false
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
  #
  # 🚨 THIS ARM IS STRUCTURAL AND THAT IS ITS LIMIT — it stayed green for six days while the guard
  # it describes was defeated. The prefix test it used to pin (`case "$0" in "$_cc_cfg"/*`) admits
  # `$_cc_cfg/autonomy/postland/wt-run-NNNNN/scripts/autonomy-sweep.sh`, because postland-verify
  # mints its worktrees UNDER the config dir; caught in the act 2026-08-17T07:56Z holding the live
  # `.return.lock`. A grep over source text cannot see that, so the BEHAVIOURAL arm now lives in
  # tests/autonomy-sweep.bats ("a VERIFIER COPY UNDER the config dir may not land") and this one is
  # kept only as the cheap ordering check it always really was.
  grep -q 'CLAUDE_CONFIG_DIR' "$sweep"
  grep -q 'skipped-not-deployed' "$sweep"
  # The gate must key on the UNRESOLVED $0: the deployed path is a SYMLINK into the checkout, so a
  # resolved path is identical in both cases and the discriminator disappears. It must also be an
  # EXACT comparison — a prefix is what failed.
  local gate_line res_line
  gate_line="$(grep -n '\[ "\$0" = "\$_cc_cfg/scripts/autonomy-sweep.sh" \]' "$sweep" | head -1 | cut -d: -f1)"
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

@test "NOTHING TO LAND (66) is a non-verdict too — no artifact, no wake, no latch, row untouched" {
  # The absence contract (CLOUD_OBSERVABILITY.md §4.1/§16) moves a whole population ACROSS this
  # script's boundary. Before it, a VM that booted and committed nothing had no ref, read C1
  # NOT-STARTED and returned at step 1 with "nothing to return". Once it pushes its branch as its
  # first act, the same session reads ALIVE/STALLED and arrives HERE, at the land — where the
  # reconciler answers 66 (the branch carries no content). Without this arm it takes the refusal
  # path: an artifact latched to the head, a LAND REFUSED wake, custody left open — three alarms
  # about a branch with nothing wrong with it, once per dead session.
  declare_managed --item deadbeef1234
  seen_at 1000
  LAND_RC=66 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to return"* ]] || false
  [[ "$output" != *"REFUSED"* ]] || false
  [ ! -f "$CC_CLOUD_STATE/session_test.land-refused" ]
  [ ! -f "$CC_CLOUD_STATE/session_test.returned" ]
  ! grep -q 'HANDOFF-PING' "$CALLS" || false
  # POSITIVE CONTROL off the same fixture: a REAL gate red still files the artifact and wakes, so
  # this arm is a statement about 66 and not about the fixture being unable to reach either path.
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

# ══ A REFUSAL IS EARNED ONCE PER BRANCH HEAD ════════════════════════════════════════════════════
# Measured 2026-08-25 on the live ledger: 980 land-refused rows, 45 sessions, 93 attempts against
# ONE of them, because every 300 s tick re-ran a verdict that could not have changed. The refusal
# artifact had recorded `seen_sha=` the whole time and nothing read it back.

# Advance the VM branch, which is the ONLY thing that can legitimately change a refusal's answer.
push_new_vm_commit() {
  git -C "$WORK" checkout -q claude/vm
  printf 'another turn\n' >>"$WORK/docs/vm.md"
  git -C "$WORK" add -A
  git -C "$WORK" -c user.email=vm@anthropic -c user.name=vm commit -q -m "vm second turn"
  git -C "$WORK" checkout -q trunkref
  push_vm
}
reconcile_calls() { grep -c '^reconcile ' "$CALLS" 2>/dev/null || printf '0'; }

@test "a refusal already earned on this exact branch head is NOT re-run on the next sweep" {
  declare_managed
  seen_at 1
  LAND_RC=5 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [ -f "$CC_CLOUD_STATE/session_test.land-refused" ]
  [ "$(reconcile_calls)" -eq 1 ]
  # Second tick, nothing about the branch changed. Pre-fix this called the lander again — and again,
  # 93 times on one session. The count, not the prose, is the assertion: a message can be added
  # while the wasteful call still happens.
  LAND_RC=5 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [ "$(reconcile_calls)" -eq 1 ]
  [[ "$output" == *"already REFUSED"* ]] || false
}

@test "the skip does NOT latch — a new push re-earns the attempt with no expiry or sweeper" {
  declare_managed
  seen_at 1
  LAND_RC=5 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$(reconcile_calls)" -eq 1 ]
  # The VM pushed again: the branch head differs, so the prior verdict is about a tree that no
  # longer exists and the lander must be asked afresh. This is the whole falsifier — without it the
  # fix would be a permanent block wearing a cache's clothes.
  push_new_vm_commit
  seen_at 1
  LAND_RC=0 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [ "$(reconcile_calls)" -eq 2 ]
}

@test "CC_RETURN_RETRY_REFUSED=1 forces the re-ask, for the conflict a branch-head key cannot see" {
  declare_managed
  seen_at 1
  LAND_RC=5 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$(reconcile_calls)" -eq 1 ]
  # A rebase conflict is a function of the branch AND of trunk. Keying the skip on trunk would
  # re-open the loop (trunk moves many times a day), so the escape is explicit and human-driven.
  CC_RETURN_RETRY_REFUSED=1 LAND_RC=0 CC_RETURN_NOW=999999 run "$SUT" --sweep
  [ "$status" -eq 0 ]
  [ "$(reconcile_calls)" -eq 2 ]
}

# ══ THE PASS MUST FIT ITS BOUND ═════════════════════════════════════════════════════════════════
#
# The defect these pin (docs/plans/DRAIN_CIRCUIT_2026-09-01.md §3b A/B/D): an unbounded pass over a
# store that only grows spent ~675 s of its caller's 900 s bound on FIXED cost before attempting a
# single land, was SIGKILLed every tick, and left its single-flight lock behind each time — so the
# next ~12 ticks exited 4 without doing any work either. The `cloud_return_rc` timeline holds no
# success at all: 137, 4, 4, 4, 4, 4, 137, 137, 137.
#
# Each arm below pins ONE half of the repair, and the two that could quietly widen into a defect of
# their own — a cap that hides what it skipped, and a lock reap that steals from a live pass — carry
# an explicit control that must FAIL if the guard is removed.

# N managed declarations, declared oldest-first so `declared_at` ordering is assertable.
declare_n() { # <count>
  local i t; t=$(( $(date +%s) - 10000 ))
  for i in $(seq 1 "$1"); do
    "$CCLOUD" declare --id "session_$i" --branch claude/vm --remote "$REMOTE" --repo "$WORK" \
      --trunk trunkref --account next3 --custody "session_$i" --notify-back PANE-UUID >/dev/null 2>&1
    # Stamp declared_at explicitly: seq is faster than the clock, so every row would otherwise share
    # one second and "newest first" would have no observable content to be right or wrong about.
    # NOT `sed -i ''` — that is the BSD in-place idiom, and on GNU sed the empty string IS the
    # script, which makes the real script a FILENAME: `sed: can't read s/^declared_at=…`, exit 2,
    # and tests 32-35 fail on Linux while passing on the operator's mac. A cloud worker runs on
    # Linux, so the one venue that most needs to verify this suite was the one that could not.
    sed "s/^declared_at=.*/declared_at=$((t + i * 100))/" "$CC_CLOUD_STATE/session_$i.decl" \
      >"$CC_CLOUD_STATE/session_$i.decl.new" \
      && mv "$CC_CLOUD_STATE/session_$i.decl.new" "$CC_CLOUD_STATE/session_$i.decl"
  done
  push_vm
}

@test "--limit BOUNDS the pass: 2 of 5 examined, and the other 3 are named as deferred" {
  declare_n 5
  printf '{"worker_status":"working"}\n' >"$STATUS_JSON"   # nothing lands; we are measuring SCOPE
  run bash "$SUT" --sweep --limit 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 of 5 pending managed session(s)"* ]] || false
  # 🚨 NEVER A SILENT CAP. A bounded pass that says nothing about what it skipped reads exactly like
  # one that covered everything — which is how "the lane is drained" gets asserted over 25 of 466.
  run jq -sc '[.[] | select(.outcome=="pass-scope")] | last' "$CC_CLOUD_STATE/return.jsonl"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.taken')" = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.deferred')" = "3" ]
  [ "$(printf '%s' "$output" | jq -r '.pending_total')" = "5" ]
}

@test "NEWEST FIRST — staleness compounds, so the freshest branches get the budget" {
  declare_n 5
  printf '{"worker_status":"working"}\n' >"$STATUS_JSON"
  run bash "$SUT" --sweep --limit 2
  [ "$status" -eq 0 ]
  # session_5 and session_4 carry the LATEST declared_at, so they are the pass's population.
  [[ "$output" == *"session_5"* ]] || false
  [[ "$output" == *"session_4"* ]] || false
  [[ "$output" != *"session_1"* ]]
}

@test "the CURSOR reaches the tail — a fixed limit alone would re-examine one head forever" {
  declare_n 5
  printf '{"worker_status":"working"}\n' >"$STATUS_JSON"
  run bash "$SUT" --sweep --limit 2; first="$output"
  run bash "$SUT" --sweep --limit 2; second="$output"
  # THE CONTROL THAT CAN FAIL: without the persisted cursor both passes take the same newest two,
  # `second` is identical to `first`, and the older 60% of the store is never looked at again — a
  # cap that reads as coverage. Asserting only "the cursor file changed" would pass over a cursor
  # nothing consumes, so this asserts the OBSERVABLE consequence instead.
  [ "$first" != "$second" ]
  [[ "$second" == *"session_3"* ]] || false
  [[ "$second" != *"session_5"* ]]
}

@test "the probing calls are SCOPED — --limit alone would bound nothing that costs" {
  declare_n 3
  printf '{"worker_status":"working"}\n' >"$STATUS_JSON"
  # A recording pass-through, not a stub: the real cc-cloud's verdicts ARE the input under test.
  printf '#!/usr/bin/env bash\necho "cc-cloud $*" >>"%s"\nexec "%s" "$@"\n' "$CALLS" "$CCLOUD" \
    >"$STUBDIR/cc-cloud-rec"
  chmod +x "$STUBDIR/cc-cloud-rec"
  CC_RETURN_CLOUD_BIN="$STUBDIR/cc-cloud-rec" run bash "$SUT" --sweep --limit 1
  [ "$status" -eq 0 ]
  # 🚨 THE LOAD-BEARING ASSERTION. `poll` and `list --state` each spend one bounded ls-remote PER
  # DECLARATION IN THE STORE. Unscoped, they stay O(every declaration ever created) — 583 today,
  # +20-80/day — so a --limit that did not reach them would bound only the cheap half while the
  # fixed cost went on growing underneath it, and the pass would still be unfinishable next month.
  grep -q 'cc-cloud poll --only ' "$CALLS"
  grep -q 'cc-cloud list --json --state --only ' "$CALLS"
}

# ══ A KILLED PASS MUST NOT WEDGE THE NEXT TWELVE TICKS ══════════════════════════════════════════

# A pid that is certainly free: spawn, reap, reuse the number.
dead_pid() { bash -c 'exit 0' & local p=$!; wait "$p" 2>/dev/null; printf '%s' "$p"; }

@test "a lock whose HOLDER IS DEAD is reaped at once, even while its timestamp is fresh" {
  declare_managed
  seen_at $(( $(date +%s) - 10000 ))
  mkdir -p "$CC_CLOUD_STATE/.return.lock"
  dead_pid > "$CC_CLOUD_STATE/.return.lock/pid"
  date +%s > "$CC_CLOUD_STATE/.return.lock/at"      # FRESH: the age window alone would refuse
  run bash "$SUT" --sweep --dry-run
  # This is the `4, 4, 4, 4, 4` run in the production timeline. `timeout -k` sends SIGKILL, the
  # EXIT/INT/TERM trap cannot run on one, so the lock outlives every cut pass by construction — and
  # a 3600 s age window against a 300 s cadence turned each kill into ~12 dead ticks.
  [ "$status" -eq 0 ]
  [[ "$output" == *"reaping the lock"* ]] || [[ "${lines[*]}" == *"reaping"* ]]
}

@test "CONTROL: a lock held by a LIVE pid inside the window is still REFUSED (rc 4)" {
  declare_managed
  mkdir -p "$CC_CLOUD_STATE/.return.lock"
  printf '%s\n' "$$" > "$CC_CLOUD_STATE/.return.lock/pid"   # this shell: certainly alive
  date +%s > "$CC_CLOUD_STATE/.return.lock/at"
  run bash "$SUT" --sweep --dry-run
  # THE CONTROL THAT CAN FAIL. The instruction on this repair was explicit: do not widen the reap to
  # where a genuinely concurrent pass could be stolen from. Without this arm, "reap harder" passes
  # the test above by simply deleting every lock it meets, and two passes would then land the same
  # branch concurrently — a strictly worse failure than the one being fixed.
  [ "$status" -eq 4 ]
  [ -d "$CC_CLOUD_STATE/.return.lock" ]
}

@test "an UNREADABLE holder is not called dead — it falls through to the age window" {
  declare_managed
  mkdir -p "$CC_CLOUD_STATE/.return.lock"
  : > "$CC_CLOUD_STATE/.return.lock/pid"                    # no pid recorded at all
  date +%s > "$CC_CLOUD_STATE/.return.lock/at"
  run bash "$SUT" --sweep --dry-run
  # A pid we cannot READ is a miss, not an absence: treating it as a dead holder would make an
  # unstamped lock unstealable-from into always-stealable (memory: lookup-miss-is-not-absence).
  [ "$status" -eq 4 ]
}

@test "a pass whose BOUND IS EXCEEDED leaves the lock reapable on the very next tick" {
  declare_managed
  seen_at $(( $(date +%s) - 10000 ))
  # The real shape: `timeout -k 10 <bound>` escalating to SIGKILL, so no trap runs and the lock dir
  # survives with its holder's pid in it. CC_RETURN_SLEEP is not a seam this script has, so the cut
  # is produced the way production produces it — an external SIGKILL to a pass mid-flight.
  bash "$SUT" --sweep --dry-run >/dev/null 2>&1 &
  victim=$!
  # Let it take the lock, then kill it the way its caller's `-k` does.
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -d "$CC_CLOUD_STATE/.return.lock" ] && break; sleep 0.1; done
  kill -9 "$victim" 2>/dev/null || true
  wait "$victim" 2>/dev/null || true
  if [ ! -d "$CC_CLOUD_STATE/.return.lock" ]; then
    skip "the pass completed before it could be cut — this arm needs the lock still held"
  fi
  # THE DoD CLAUSE: the bound WAS exceeded, and the next tick must still be able to work.
  run bash "$SUT" --sweep --dry-run
  [ "$status" -eq 0 ]
}
