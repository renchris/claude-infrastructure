#!/usr/bin/env bats
# THE WEDGE — six finished off-box sessions held all six LOCAL admission slots, and nothing could
# ever release them. Measured 2026-08-12: `free_slots:0, live_workers:6, deferred:318, fired:0` on
# every dispatcher pass from 07:15Z onward, cloud AND local both stopped, with no timeout that would
# end it. Three independent defects composed, and each gets its refusal plus the control that must
# stay admitted:
#
#   D1  cc-dispatch live_workers() folded `.status=="claimed"` with NO venue predicate, so an
#       off-box session — which costs this box no pane, no worktree, no CPU — was charged against
#       the ceiling that bounds exactly those three things.
#   D2  cloud-return.sh latched `<id>.returned` on (landed && wake), omitting the BACKLOG CLOSE. A
#       round trip that landed, verified, and failed to close latched anyway and was then
#       short-circuited at `already returned` forever — unretryable by construction.
#   D3  nothing on the box ever called `cc-cloud retire` (0 `.retired` markers across 38
#       declarations), so `is-offbox` answered LIVE forever and `cc-backlog reap` could never
#       reopen the claim. The ceiling had no self-heal.
#
# D2's fix creates a hazard of its own — a PERMANENT close failure would never latch, never retire,
# and hold the slot exactly as before — so the bounded-retry escape is pinned here too. A fix that
# converts a wedge into a different wedge is not a fix.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_DISPATCH_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_DISPATCH_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export CC_DISPATCH_PROJECT="p"
  : > "$CC_BACKLOG_FILE"; : > "$CC_DISPATCH_IDL"
}

# claimed <id> <venue|-> — a CLAIMED row, i.e. one that charges some ceiling
claimed() {
  local v=""
  [ "${2:--}" != "-" ] && v=", \"venue\":\"$2\""
  printf '{"id":"%s","ts":"2026-08-01T00:00:00Z","event":"add","project":"p","title":"t %s"}\n' "$1" "$1" >> "$CC_BACKLOG_FILE"
  printf '{"id":"%s","ts":"2026-08-01T00:01:00Z","event":"claim","by":"w-%s"%s}\n' "$1" "$1" "$v" >> "$CC_BACKLOG_FILE"
}

# lw <lane> — call cc-dispatch's OWN live_workers against this test's store.
#
# The function is extracted from the subject rather than reimplemented, so a change to the real fold
# reds these cases. It depends on `is_uint`, which lives elsewhere in the file — extracting only
# live_workers made every case return "" (UNKNOWN) and pass VACUOUSLY on the pre-fix binary too.
# That is exactly the trap this repo names in verification-harness-vacuous-pass-traps, met here.
_lw_src() { sed -n '/^is_uint()/p;/^live_workers()/,/^}/p' "$REPO/bin/cc-dispatch"; }
lw() { lw_bin "$REPO/bin/cc-backlog" "$1"; }
lw_bin() {
  local src; src="$(_lw_src)"
  CC_BACKLOG_FILE="$CC_BACKLOG_FILE" bash -c "$src"'
    live_workers "$1" "$2"' _ "$1" "$2"
}

# ── D1 · the ceiling must count the resource it bounds ───────────────────────────────────────────

@test "D1 REFUSAL: six cloud claims leave the LOCAL lane empty (pre-fix this folded to 6)" {
  claimed c1 cloud; claimed c2 cloud; claimed c3 cloud
  claimed c4 cloud; claimed c5 cloud; claimed c6 cloud
  run lw local
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "D1: the same six DO charge the cloud lane — the fix must not make cloud free" {
  claimed c1 cloud; claimed c2 cloud; claimed c3 cloud
  claimed c4 cloud; claimed c5 cloud; claimed c6 cloud
  run lw cloud
  [ "$output" = "6" ]
}

@test "D1 CONTROL: a local claim still charges the local lane (the ceiling must not become inert)" {
  claimed L1 local; claimed L2 -; claimed c1 cloud
  run lw local
  # L1 explicitly local AND L2 with NO venue — absence of a venue is LOCAL, the fail-closed direction.
  [ "$output" = "2" ]
}

@test "D1: an UNVENUED claim counts as local, never as cloud (absence is not off-box-ness)" {
  claimed u1 -
  run lw cloud
  [ "$output" = "0" ]
}

@test "D1: an unreadable ledger still collapses to UNKNOWN, never to 0 (the third state survives)" {
  # The caller MUST be able to tell "nobody is out" from "I could not tell". Empty output is the
  # third state; a literal 0 here would be a false all-clear that admits into an unknown fleet.
  run lw_bin /nonexistent-bin local
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "D1 END-TO-END: 6 cloud claims no longer starve a dispatchable cloud row" {
  # The bug reached the operator as free_slots:0 / fired:0 on the IDL. The queue needs a real OPEN
  # row to be non-empty — six CLAIMED rows alone make the pass exit at "backlog empty", which would
  # have passed this test for the wrong reason.
  claimed c1 cloud; claimed c2 cloud; claimed c3 cloud
  claimed c4 cloud; claimed c5 cloud; claimed c6 cloud
  printf '{"id":"open01","ts":"2026-08-01T00:00:00Z","event":"add","project":"p","title":"work","venuePlan":"cloud"}\n' >> "$CC_BACKLOG_FILE"
  run env CC_DISPATCH_VENUE_ONLY=cloud CC_DISPATCH_CLOUD_CEILING=8 "$REPO/bin/cc-dispatch" --decide
  [ "$status" -eq 0 ]
  # cloud lane: 8 − 6 = 2 free, so the open row is ADMITTED. Pre-fix the local fold read 6 against a
  # ceiling of 6 and it deferred with reason "at-ceiling" — the wedge, in one record.
  grep -q '"live_workers":6' "$CC_DISPATCH_IDL"
  ! grep -q '"reason":"at-ceiling"' "$CC_DISPATCH_IDL"
}

@test "D1 END-TO-END CONTROL: the cloud lane STILL wedges when it is genuinely full" {
  # The fix must relocate the ceiling, not delete it. Same six claims, cloud ceiling back at 6.
  claimed c1 cloud; claimed c2 cloud; claimed c3 cloud
  claimed c4 cloud; claimed c5 cloud; claimed c6 cloud
  printf '{"id":"open01","ts":"2026-08-01T00:00:00Z","event":"add","project":"p","title":"work","venuePlan":"cloud"}\n' >> "$CC_BACKLOG_FILE"
  run env CC_DISPATCH_VENUE_ONLY=cloud CC_DISPATCH_CLOUD_CEILING=6 "$REPO/bin/cc-dispatch" --decide
  [ "$status" -eq 0 ]
  grep -q '"reason":"at-ceiling"' "$CC_DISPATCH_IDL"
}

@test "D1: CC_DISPATCH_CLOUD_CEILING must be a non-negative integer (a typo may not narrow to zero)" {
  run env CC_DISPATCH_CLOUD_CEILING=lots "$REPO/bin/cc-dispatch" --decide
  [ "$status" -eq 3 ]
  [[ "$output" == *"CC_DISPATCH_CLOUD_CEILING"* ]]
}

# ── D2/D3 · the latch must cover the close, and a terminal session must release its slot ─────────
#
# These pin the SOURCE, because standing up a full cloud round trip in bats would mean stubbing the
# control plane, git, the lander and the backlog at once — a harness whose own defaults would decide
# the verdict. The properties under test are structural: which facts the latch reads, and whether a
# retire call exists on the terminal path at all. A structural assertion is the honest instrument for
# "this line is present and reachable"; the behavioural proof is the live round trip in the plan.

@test "D2 REFUSAL: the latch condition includes the backlog close, not just land+wake" {
  run grep -n 'landed_ok" -eq 0 \] && \[ "\$done_unsettled" -eq 0 \]' "$REPO/scripts/cloud-return.sh"
  [ "$status" -eq 0 ]
}

@test "D2: the close failure is CAPTURED, not discarded into /dev/null" {
  # The pre-fix call was `>/dev/null 2>&1`, which destroyed the one fact that separated contention
  # from policy. Assert the redirect is gone from the `done` call specifically.
  run grep -n '"\$BACKLOG_BIN" "done" "\$item" .*>/dev/null 2>&1' "$REPO/scripts/cloud-return.sh"
  [ "$status" -ne 0 ]
  run grep -q 'done_err=' "$REPO/scripts/cloud-return.sh"
  [ "$status" -eq 0 ]
}

@test "D3 REFUSAL: the terminal path calls cc-cloud retire — the verb had zero callers" {
  run grep -n 'retire --id "\$id"' "$REPO/scripts/cloud-return.sh"
  [ "$status" -eq 0 ]
}

@test "D3 CONTROL: retire is NOT called before the work is verified on trunk" {
  # Retiring early tells reap a still-working VM is dead and invites a duplicate peer onto live
  # work. Every retire call site must sit under a landed_ok==0 branch.
  run bash -c 'awk "/retire --id/{print NR}" "$1" | while read -r n; do
                 sed -n "1,${n}p" "$1" | grep -q "landed_ok\" -eq 0" || { echo "UNGUARDED at $n"; exit 1; }
               done' _ "$REPO/scripts/cloud-return.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *UNGUARDED* ]]
}

@test "D2-hazard: a permanent close failure is BOUNDED, so the fix cannot re-create the wedge" {
  run grep -q 'CC_RETURN_CLOSE_MAX' "$REPO/scripts/cloud-return.sh"
  [ "$status" -eq 0 ]
  # and the counter lives in a sidecar, NOT in .returned — which is written only on success and
  # would therefore be reset by the very event it bounds.
  run grep -q 'close-attempts' "$REPO/scripts/cloud-return.sh"
  [ "$status" -eq 0 ]
}

# ── the fold's bound must fit the band it runs in ────────────────────────────────────────────────

@test "BAND: the sweep's probe bound exceeds the MEASURED background cost of the fold" {
  # foreground 17.5 s · background 68.1 s · utility 20.3 s, all measured 2026-08-12 on this box.
  # A 60 s bound sat between two of those, which is why fold_rc was 124 on 10 of 10 runs.
  run bash -c 'sed -n "/^_bounded()/,/^}/p" "$1" | grep -oE "CC_SWEEP_BOUND_S:-[0-9]+"' _ "$REPO/scripts/autonomy-sweep.sh"
  [ "$status" -eq 0 ]
  local n="${output##*:-}"
  [ "$n" -gt 68 ]
}

@test "BAND: the probes are lifted out of the E-core-confined Background band" {
  run bash -c 'sed -n "/^_bounded()/,/^}/p" "$1" | grep -q "taskpolicy\|_qos"' _ "$REPO/scripts/autonomy-sweep.sh"
  [ "$status" -eq 0 ]
}

@test "BAND CONTROL: no taskpolicy ⇒ the probe still runs (fail-open, never a new outage)" {
  run bash -c 'sed -n "/^_bounded()/,/^}/p" "$1" | grep -q "\${_qos:+"' _ "$REPO/scripts/autonomy-sweep.sh"
  [ "$status" -eq 0 ]
}
