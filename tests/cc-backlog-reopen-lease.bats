#!/usr/bin/env bats
# cc-backlog REOPEN LEASE — the release side of the claim lease, at the same polarity as the acquire
# side. Item b7fe9507d986, filed 2026-08-11 from a code read and measured here.
#
# THE DEFECT. `reopen`/`unblock` guarded a live claim with `... && claimer_live "$cby" "$cvenue"` —
# a bare `&&`, so it refused ONLY on rc 0 (proven LIVE) and proceeded on BOTH rc 1 (proven dead,
# correct) and rc 2 (UNRESOLVED, a non-verdict). It never asked the worktree at all. The acquire-side
# lease warns against precisely that shape in a comment naming this verb, and the verb kept it. It
# matters because reopen/unblock resolves the fold to "open", which IS cc-dispatch's fire predicate:
# a third party releasing a claim whose <host>-<pid> has merely ROTATED puts a live worker's item back
# in the wave (the 2026-07-20 double-fire, reached through the release door).
#
# WHY A SEPARATE FILE. tests/cc-backlog-venue.bats carries a measured per-site mutant-kill table for
# the venue gates, and its own header says that table decays when the file's kill-set changes. These
# tests are about POLARITY, not venue, and adding them there would silently invalidate a published
# measurement. Same subject, different claim, different file.
#
# THE CASES FAIL DIFFERENTLY ON PURPOSE (memory: per-site-mutation-attributes-coverage). Two cases
# that fail the same way are one case:
#   1  refuses on ORACLE 2   — claimer proven dead, worktree OCCUPIED
#   2  refuses on ORACLE 1   — claimer UNRESOLVED, oracle 2 never consulted
#   3  is not a red-proof case at all but a CONTROL ON THE REMEDY — reap's own cloud release must
#      still go through. It passes before the fix and after it, and fails against the NAIVE version
#      of this fix (tighten the polarity, exempt nobody), which is the version a reader of the item's
#      title would have written. Both oracles return rc 2 for every non-local venue unconditionally,
#      so that version refuses 100% of cloud releases forever — including the sanctioned one — and
#      does it silently, because reap's call site is `elif cmd_transition ...` whose else-arm only
#      writes an IDL row. Measured when this landed: both live claimed rows in the store were
#      venue=cloud, i.e. the naive remedy's blast radius was the whole claimed population.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # An oracle that ANSWERS "not listed" (rc 1). With $HOME owned there is no cc-sessions to resolve,
  # which would be UNRESOLVED (rc 2) and would let every case below pass for the wrong reason — case
  # 2 asserts the rc-2 path explicitly, so it must not be the ambient state of the whole file.
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/nosess"; chmod +x "$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # Present-but-empty root: owned_wait treats an ABSENT root as starvation (rc 2), which would make
  # the "nobody home" cases abstain instead of answering rc 1.
  export CC_BACKLOG_WT_ROOT="$BATS_TEST_TMPDIR/worktrees"; mkdir -p "$CC_BACKLOG_WT_ROOT"
  # lsof stubbed to "answered, nobody there" by default. Per-test overridden in case 1. Left at the
  # real binary this would read the operator's live process table, so a case asserting occupancy
  # would depend on what happens to be running.
  printf '#!/bin/bash\nprintf "p1\\nn/nowhere\\n"\n' > "$BATS_TEST_TMPDIR/lsof-empty"
  chmod +x "$BATS_TEST_TMPDIR/lsof-empty"
  export CC_BACKLOG_LSOF_BIN="$BATS_TEST_TMPDIR/lsof-empty"
}

# dead_pid → a <host>-<pid> whose pid is provably reaped (spawn and wait, never an arithmetic guess).
dead_pid() { printf '%s-%s' "$(hostname -s)" "$(bash -c 'echo $$')"; }

# add_and_claim <source> <claimer> [--venue V] → the id, claimed. Eligibility pinned off for the same
# reason tests/cc-backlog-venue.bats pins it: the off-box classifier matches \bvenue\b and would
# refuse the fixtures themselves, which is not this file's subject.
add_and_claim() {
  local src="$1" who="$2"; shift 2
  local id; id="$("$CB" add --title "reopen lease probe $src" --project probe --source "$src")"
  CC_BACKLOG_ELIGIBLE_GATE=off "$CB" claim "$id" --by "$who" "$@" >/dev/null \
    || { echo "add_and_claim: claim refused for $id ($src, $who $*)" >&2; return 1; }
  printf '%s' "$id"
}

# occupy <id> → make the item's worktree read OCCUPIED through owned_wait's cwd-occupancy arm (S1b),
# by stubbing lsof to name a process whose cwd is that worktree. The cwd arm and not `pgrep -f` on
# purpose: measured against a live dispatch worktree, pgrep read 0 while cwd occupancy read 13 — the
# launcher's argv is spent and only the cwd survives (memory: argv-is-sampling-cwd-is-durable).
occupy() {
  local wt="$CC_BACKLOG_WT_ROOT/wt-$1"
  mkdir -p "$wt"
  { printf '#!/bin/bash\n'; printf 'printf "p4242\\nn%s\\n"\n' "$wt"; } > "$BATS_TEST_TMPDIR/lsof-busy"
  chmod +x "$BATS_TEST_TMPDIR/lsof-busy"
  export CC_BACKLOG_LSOF_BIN="$BATS_TEST_TMPDIR/lsof-busy"
}

# ── 1 · ORACLE 2 — a rotated shell is not a finished worker ────────────────────────────────────

@test "reopen: REFUSED when the claimer is dead but its WORKTREE is still occupied" {
  local id; id="$(add_and_claim rotated-pid "$(dead_pid)")"
  occupy "$id"
  run "$CB" reopen "$id" --by "$(hostname -s)-$$"
  [ "$status" -eq 4 ]
  [[ "$output" == *"WORKTREE IS LIVE"* ]] || false
  # Names the worktree it saw, so the refusal is checkable rather than an assertion of authority.
  [[ "$output" == *"wt-$id"* ]] || false
  # It must NOT have refused on oracle 1: that would be the right rc for the wrong reason, and would
  # pass just as happily against a guard that refused every third-party reopen unconditionally.
  [[ "$output" != *"which is still LIVE"* ]]
}

@test "1-CONTROL: same dead claimer, EMPTY worktree — the reopen still goes through" {
  # The discriminator for case 1. Without it, case 1 passes against a guard that simply refuses all
  # third-party reopens, and the release path would be dead with a green board (memory:
  # alarm-polarity-and-attention-budget).
  local id; id="$(add_and_claim rotated-pid-free "$(dead_pid)")"
  run "$CB" reopen "$id" --by "$(hostname -s)-$$"
  [ "$status" -eq 0 ]
}

@test "1-CONTROL (claim side): the ACQUIRE lease already refuses that same shape" {
  # The positive control item b7fe9507d986 asks for by name. It proves the harness can build a
  # dead-claimer + occupied-worktree fixture that a correct guard convicts — so case 1's red is a
  # property of the reopen guard, not of a fixture that nothing could ever pass.
  local id; id="$(add_and_claim rotated-pid-claimside "$(dead_pid)")"
  occupy "$id"
  run "$CB" claim "$id" --by "$(hostname -s)-$$"
  [ "$status" -eq 4 ]
  [[ "$output" == *"WORKTREE IS LIVE"* ]]
}

# ── 2 · ORACLE 1 — an unanswered probe is not proof of death ───────────────────────────────────

@test "reopen: REFUSED when the claimer's liveness is UNRESOLVED" {
  # venue=cloud is the honest way to reach rc 2: claimer_live's venue gate returns it unconditionally
  # for any non-local venue, so this asserts the non-verdict path without stubbing the oracle itself.
  local id; id="$(add_and_claim unresolved-claimer "cloudvm-4242" --venue cloud)"
  run "$CB" reopen "$id" --by "$(hostname -s)-$$"
  [ "$status" -eq 4 ]
  [[ "$output" == *"UNRESOLVED"* ]] || false
  [[ "$output" == *"not proof the holder is gone"* ]] || false
  # Refused on oracle 1, so oracle 2 was never reached — a different failure from case 1.
  [[ "$output" != *"WORKTREE IS LIVE"* ]]
}

@test "2-CONTROL: the holder's OWN release is never gated by either oracle" {
  # `[ "$cby" != "$by" ]` runs first and is untouched by this change. reopen --by IS the legitimate
  # direction of this verb; a fix that narrowed it would have broken cc-dispatch:754's rollback.
  local who="cloudvm-4242"
  local id; id="$(add_and_claim self-release "$who" --venue cloud)"
  run "$CB" reopen "$id" --by "$who"
  [ "$status" -eq 0 ]
}

@test "2-CONTROL: --force still overrides, and still says nothing about the terminal guard" {
  local id; id="$(add_and_claim forced "cloudvm-4242" --venue cloud)"
  run "$CB" reopen "$id" --by "$(hostname -s)-$$" --force
  [ "$status" -eq 0 ]
}

# ── 3 · CONTROL ON THE REMEDY — the sanctioned releaser must survive its own tightening ────────

@test "3-CONTROL: reap's CLOUD dead-worker release still goes through" {
  # Not a red-proof case: it passes pre-fix. It fails against the naive tightening (no exemption),
  # which is the whole point — both oracles abstain on every cloud claim by construction, so the
  # naive version refuses the one caller that had already convicted with stronger evidence.
  #
  # The subject is COPIED, not re-implemented, so this replays the real artifact (memory:
  # control-must-replay-the-real-artifact). Only its SIBLING resolution moves: cloud_state resolves
  # `$(dirname "$0")/cc-cloud` first, which is the seam being fixtured.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cp "$CB" "$BATS_TEST_TMPDIR/bin/cc-backlog"
  printf '#!/bin/bash\necho "state=ABANDONED"\n' > "$BATS_TEST_TMPDIR/bin/cc-cloud"
  chmod +x "$BATS_TEST_TMPDIR/bin/cc-cloud"
  local CBC="$BATS_TEST_TMPDIR/bin/cc-backlog"

  local id; id="$("$CBC" add --title "reap cloud release" --project probe --source reap-cloud)"
  CC_BACKLOG_ELIGIBLE_GATE=off "$CBC" claim "$id" --by "cloudvm-9001" --venue cloud >/dev/null

  # Positive control on the STUB before the assertion that depends on it: ABANDONED must map to the
  # `open` verb. A stub that silently stopped being read would make the real assertion vacuous.
  run env CC_BACKLOG_NOW=$(( $(date +%s) + 100000 )) "$CBC" reap --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD-REOPEN $id"* ]] || false
  [[ "$output" == *"cloud-abandoned"* ]] || false

  # The assertion: for real, not --dry-run. The transition must be TAKEN, not merely intended.
  run env CC_BACKLOG_NOW=$(( $(date +%s) + 100000 )) "$CBC" reap
  [ "$status" -eq 0 ]
  [[ "$output" == *"REOPEN $id"* ]] || false
  # Read the fold, never the reap's own claim about itself: the else-arm that would fire under the
  # naive remedy is SILENT, so the printed line is exactly what could not be trusted here.
  run "$CBC" list --all --json
  [ "$status" -eq 0 ]
  local st; st="$(printf '%s' "$output" | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')"
  [ "$st" = "open" ]
}

@test "3-CONTROL: a LOCAL occupied worktree never reaches 'open' through the reap" {
  # THE NARROWING, and how it was found. The first draft of this fix exempted reap outright,
  # justified as "reap already convicted with both oracles, so re-asking is redundant". That reason
  # is false: the guard re-probes at a LATER TIME, and tests/cc-backlog.bats "journal: a REFUSED
  # transition is recorded with acted:false" is the landed proof — it flips a stateful sessions stub
  # dead-then-live across the two calls and asserts the guard catches the claimer that revived in
  # between. The blanket exemption turned that test red, which is what forced the venue half of the
  # condition. That file owns the guard-level local pin (a TOCTOU flip); duplicating it here would be
  # churn, so this asserts the OUTCOME the pair must jointly guarantee, by a different route.
  #
  # The route matters: reap's OWN owned_wait arm escalates an occupied worktree to `block` before the
  # guard is ever reached, so this never exercises the guard — asserting "still claimed" here would
  # have been asserting a state the code cannot produce. What it does pin is the end-to-end property
  # a widened exemption would break together with anything else: on a local claim, an occupied
  # worktree does not become dispatchable.
  local id; id="$(add_and_claim reap-local-guarded "$(dead_pid)")"
  occupy "$id"
  run env CC_BACKLOG_NOW=$(( $(date +%s) + 100000 )) "$CB" reap
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCK $id"* ]] || false
  [[ "$output" == *"0 reopened"* ]] || false
  run "$CB" list --all --json
  local st; st="$(printf '%s' "$output" | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')"
  [ "$st" != "open" ] || false
  [ "$st" = "blocked" ]
}

@test "3-CONTROL: the reap exemption does NOT lift the terminal-done guard" {
  # The exemption is scoped to the live-claim guard alone. If it had been spelled `--force` it would
  # also have lifted this one, and a reap able to resurrect a landed item is incident 1a226422cb37.
  local id; id="$("$CB" add --title "terminal" --project probe --source terminal-guard)"
  # `'done'` quoted: it is cc-backlog's verb, but shellcheck parses a bare `done` as the loop
  # keyword (SC1010). The subject quotes it at its own call sites for the same reason.
  "$CB" 'done' "$id" --evidence "landed abc1234" >/dev/null
  run "$CB" reopen "$id" --by "$(hostname -s)-$$"
  [ "$status" -eq 4 ]
  [[ "$output" == *"TERMINAL"* ]]
}
