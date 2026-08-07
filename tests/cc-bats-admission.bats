#!/usr/bin/env bats
# cc-bats-admission.bats — the corpus concurrency bound at the bats invocation chokepoint
# (backlog item 22b9f2b5a660; docs/research/machine-lag-and-kitty-2026-08-06.md §4-bis).
#
# WHAT IS UNDER TEST. `scripts/postland-verify.sh` takes its `run.lock.d` mutex INSIDE ITSELF, so an
# agent typing `bats tests/…` bypasses it entirely — on 2026-08-06 that let three corpus-scale runs
# execute at once and 1-min load reached 66.19 on a 10-core box. The bound now lives in `bin/cc-bats`,
# the shim every invocation already passes through, and it is a TWO-TERM conjunction: refuse only if
# live roots >= CC_BATS_MAX_ROOTS *and* 1-min load/core >= CC_BATS_MAX_LOAD_PER_CORE.
#
# PROOF DISCIPLINE (inherited verbatim from tests/qos-chokepoint.bats, and load-bearing here):
#   · Every ADMIT assertion is paired with the REFUSE control that shares its fixture and differs by
#     exactly one lever. An admit test alone proves nothing — a bound that never fires admits too.
#   · Non-final `[[ ]]` / `(( ))` are errexit-EXEMPT and therefore DEAD as assertions; every one
#     carries `|| false` (memory bats-dead-assertions-errexit-exemptions).
#   · The registry is FIXTURED per test (CC_BATS_ROOTS_DIR). An ambient registry would make the
#     count depend on whatever else the box is running, which is the flake rule 1 of the hermeticity
#     ratchet exists to kill — and here it would also silently change the verdict
#     (memory positive-control-the-denominator).
#   · Every invocation passes `BATS_TEST_NAME=`. These tests run INSIDE bats, and the shim's second
#     nesting guard skips the whole bound when BATS_TEST_NAME is set — so without clearing it every
#     test below would pass VACUOUSLY. Test (x) is the control that proves that guard is real.
#
# RED-PROOF, measured against a pristine `git archive` of the parent commit (bin/cc-bats has no
# admission block there at all): **10 of 23 RED** — (ii), (iv), (iv-b), (xi-b), (xii), (xii-b),
# (xiii), (xiii-b), (xiv-b), (xv). The other 13 pass VACUOUSLY on that tree, because a shim with no
# bound admits everything and every ADMIT assertion is trivially satisfied. That asymmetry is the
# point and is why each admit test above is paired with a refusal control sharing its fixture: the
# refusals are the only assertions that can tell the two trees apart.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SHIM="$REPO/bin/cc-bats"
  TMP="$BATS_TEST_TMPDIR"
  # Hermeticity rule 1. The shim's default registry is $HOME/.claude/state/bats-roots.d — an
  # unfixtured run would mint into the OPERATOR's live registry and could refuse their real gate.
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/state"
  # The shim reads every one of these from the environment, so an ambient value would decide the
  # verdict instead of the test. Same reasoning tests/qos-chokepoint.bats records for its own list.
  unset CC_BATS_ACTIVE CC_BATS_QOS CC_BATS_QOS_MODE CC_BATS_QOS_BAND CC_BATS_QUIET \
        CC_BATS_REAL CC_BATS_BAND CC_BATS_TASKPOLICY \
        CC_BATS_MAX_ROOTS CC_BATS_MAX_LOAD_PER_CORE CC_BATS_ROOTS_DIR CC_BATS_ROOT_TTL \
        CC_BATS_SYSCTL_BIN CC_BATS_PS_BIN CC_BATS_ADMIT_SKIP
  ROOTS="$TMP/roots"
  mkdir -p "$ROOTS"
  # A stub standing in for the real bats. The subject here is the ADMISSION DECISION, not bats; a
  # stub makes every test sub-second and removes the real binary as a variable.
  STUB="$TMP/realbats"
  printf '#!/bin/bash\necho STUB-RAN\nexit 0\n' > "$STUB"
  chmod 755 "$STUB"
  HOLDERS=""
}

teardown() {
  local p
  for p in $HOLDERS; do kill "$p" 2>/dev/null || true; done
}

# hold <n> — register n LIVE, non-ancestor pids as registry holders.
# `sleep` children of the test shell are SIBLINGS of the shim invocation, never its ancestors, so
# they exercise the count without tripping the ancestry backstop. 120s outlives any test here and
# teardown reaps them; nothing depends on the duration.
hold() {
  local i p
  for (( i = 0; i < $1; i++ )); do
    /bin/sleep 120 &
    p=$!
    # Detach from job control: without this bash prints "Terminated: 15 /bin/sleep 120" to the TAP
    # stream when teardown reaps it, which is noise a TAP consumer has to parse around.
    disown "$p" 2>/dev/null || true
    HOLDERS="$HOLDERS $p"
    printf 'started=fixture cwd=%s argv1=held\n' "$TMP" > "$ROOTS/$p"
  done
}

# shim <extra env...> — invoke the shim on a trivial argv with the registry and stub pinned.
shim() {
  run env CC_BATS_ROOTS_DIR="$ROOTS" CC_BATS_REAL="$STUB" BATS_TEST_NAME= "$@" \
      /bin/bash "$SHIM" tests/does-not-need-to-exist.bats
}

entries() { find "$ROOTS" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '; }

# ── the conjunction: BOTH terms, or no refusal ────────────────────────────────────────────────

@test "(i) below the roots ceiling the load term alone never refuses" {
  hold 1
  # CC_BATS_MAX_LOAD_PER_CORE=0 makes the load term unconditionally TRUE (any load >= 0). One
  # holder against a ceiling of 2 is the ONLY difference from (ii), which refuses.
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 0 ] || false
  [[ "$output" == *STUB-RAN* ]] || false
}

@test "(ii) at the roots ceiling WITH the load term true, the run is REFUSED (rc 75)" {
  hold 2
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 75 ] || false
  [[ "$output" == *REFUSED* ]] || false
  # The one thing a refusal must never do is look like a pass.
  [[ "$output" != *STUB-RAN* ]] || false
}

@test "(iii) at the roots ceiling with the load term FALSE, the run is admitted" {
  hold 2
  # Same fixture as (ii). One lever moves: a ceiling no real box reaches.
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=9999
  [ "$status" -eq 0 ] || false
  [[ "$output" == *STUB-RAN* ]] || false
}

# ── the refusal is a DEFERRAL, and says so ────────────────────────────────────────────────────

@test "(iv) the refusal names itself a deferral, not a test result, and carries the re-run command" {
  hold 2
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 75 ] || false
  # A wrapper that returned 0 for a suite it never ran would manufacture a green
  # (memory claimed-outcome-vs-checked-outcome); a wrapper that returned 1 would manufacture a RED,
  # which in this repo reaches auto_revert. 75 is EX_TEMPFAIL and collides with neither, nor with
  # the shim's own 127.
  [[ "$output" == *"nothing ran, nothing was verified"* ]] || false
  [[ "$output" == *"tests/does-not-need-to-exist.bats"* ]] || false
  [[ "$output" == *"CC_BATS_MAX_ROOTS=0"* ]] || false
}

@test "(iv-b) the refusal names the live holders it lost to" {
  hold 2
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 75 ] || false
  local p
  for p in $HOLDERS; do
    [[ "$output" == *"pid $p"* ]] || false
  done
}

# ── every unknown ADMITS — the deliberate failure direction ───────────────────────────────────

@test "(v) an UNREADABLE load instrument admits (an unread instrument is never a refusal)" {
  hold 2
  # CC_BATS_SYSCTL_BIN set-but-EMPTY ⇒ no sysctl ⇒ the load term cannot be evaluated. Control: the
  # identical fixture in (ii), which differs only by having a working sysctl, refuses.
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0 CC_BATS_SYSCTL_BIN=
  [ "$status" -eq 0 ] || false
  [[ "$output" == *STUB-RAN* ]] || false
}

@test "(vi) a MALFORMED load ceiling admits rather than refusing on a value nobody can read" {
  hold 2
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=abc
  [ "$status" -eq 0 ] || false
}

@test "(vii) CC_BATS_MAX_ROOTS=0 is the admission-only kill switch" {
  hold 2
  shim CC_BATS_MAX_ROOTS=0 CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 0 ] || false
}

@test "(vii-b) a MALFORMED roots ceiling disables the bound rather than refusing" {
  hold 2
  shim CC_BATS_MAX_ROOTS=notanumber CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 0 ] || false
}

@test "(viii) CC_BATS_ROOTS_DIR SET-BUT-EMPTY disables the bound verbatim" {
  hold 2
  # The file's stated VALUE-seam discipline: a seam that cannot turn a thing OFF is not a seam.
  run env CC_BATS_ROOTS_DIR= CC_BATS_REAL="$STUB" BATS_TEST_NAME= \
      CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0 \
      /bin/bash "$SHIM" tests/does-not-need-to-exist.bats
  [ "$status" -eq 0 ] || false
}

@test "(ix) CC_BATS_QOS=off bypasses the admission bound too (whole-shim escape hatch)" {
  hold 2
  shim CC_BATS_QOS=off CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 0 ] || false
}

# ── nesting: three layered guards, each proven ────────────────────────────────────────────────

@test "(x) INSIDE a bats test the bound is skipped — and this is why every other test clears it" {
  hold 2
  # BATS_TEST_NAME is NOT cleared here: it is whatever bats set for this very test. Guard 2.
  run env CC_BATS_ROOTS_DIR="$ROOTS" CC_BATS_REAL="$STUB" \
      CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0 \
      /bin/bash "$SHIM" tests/does-not-need-to-exist.bats
  [ "$status" -eq 0 ] || false
  # ...and it takes no slot: the count is still exactly the two fixture holders.
  [ "$(entries)" -eq 2 ] || false
}

@test "(x-b) CC_BATS_ACTIVE=1 short-circuits before the bound (guard 1)" {
  hold 2
  shim CC_BATS_ACTIVE=1 CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 0 ] || false
  [ "$(entries)" -eq 2 ] || false
}

@test "(xi) a REGISTERED ANCESTOR admits and takes no slot (guard 3)" {
  hold 2
  # $$ is this test's shell, a genuine ancestor of the shim invocation below. Registering it is
  # exactly the shape of a nested fixture run that lost guards 1 and 2.
  printf 'started=fixture cwd=%s argv1=ancestor\n' "$TMP" > "$ROOTS/$$"
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 0 ] || false
  [ "$(entries)" -eq 3 ] || false     # the 2 holders + the ancestor entry, and nothing minted
}

@test "(xi-b) POSITIVE CONTROL — the same fixture WITHOUT the ancestor entry refuses" {
  hold 2
  # (xi) minus one file. If this passed too, (xi) would be proving nothing about ancestry.
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 75 ] || false
}

@test "(xii) ps(1) unavailable ADMITS, and says LOUDLY that the bound went inert (R4)" {
  hold 2
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0 CC_BATS_PS_BIN=
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"INERT"* ]] || false
}

@test "(xii-b) the inert notice is NOT suppressible by CC_BATS_QUIET" {
  hold 2
  # Same rule the QoS-not-applied notice follows: a mechanism that looks applied and is not is the
  # entire defect class this shim exists to close, so its one inert path may never be quiet.
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0 CC_BATS_PS_BIN= CC_BATS_QUIET=1
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"INERT"* ]] || false
}

# ── the registry: what counts, what is reaped, what is minted ─────────────────────────────────

@test "(xiii) a DEAD-pid entry is reaped and does not count toward the ceiling" {
  hold 1
  # A pid that has certainly exited. `kill -0` is the same liveness oracle run.lock.d uses.
  /bin/sleep 0 & local dead=$!
  wait "$dead" 2>/dev/null || true
  printf 'started=fixture cwd=%s argv1=corpse\n' "$TMP" > "$ROOTS/$dead"
  [ "$(entries)" -eq 2 ] || false        # two files on disk...
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 0 ] || false           # ...but only ONE live root, so the ceiling is not reached
  [ ! -e "$ROOTS/$dead" ] || false       # and the corpse is gone
}

@test "(xiii-b) POSITIVE CONTROL — two LIVE entries in that same slot count, and refuse" {
  hold 2
  [ "$(entries)" -eq 2 ] || false
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 75 ] || false
}

@test "(xiv) a LIVE entry older than the TTL is reaped — the pid-recycling backstop" {
  hold 2
  # Both entries are live pids. Age them past a 1-second TTL: with recycling, a live pid is not
  # sufficient evidence that the ROOT it was minted for is still running.
  /bin/sleep 2
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0 CC_BATS_ROOT_TTL=1
  [ "$status" -eq 0 ] || false
}

@test "(xiv-b) POSITIVE CONTROL — the same aged entries under the DEFAULT TTL still count" {
  hold 2
  /bin/sleep 2
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0
  [ "$status" -eq 75 ] || false
}

@test "(xv) an admitted run mints exactly one entry, keyed on the pid that becomes bats" {
  shim CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=9999
  [ "$status" -eq 0 ] || false
  [ "$(entries)" -eq 1 ] || false
  # `exec` preserves the pid, so the entry names the process that IS bats — which is what makes the
  # liveness reaper correct without any resident wrapper or EXIT trap.
  local f; f="$(basename "$(find "$ROOTS" -mindepth 1 -maxdepth 1)")"
  [[ "$f" =~ ^[0-9]+$ ]] || false
  [[ "$(cat "$ROOTS/$f")" == *"argv1=tests/does-not-need-to-exist.bats"* ]] || false
}

@test "(xvi) non-executing invocations take no slot and are never refused" {
  hold 2
  # --count only PARSES (postland-verify calls it once per suite while building its corpus) and
  # --version forks nothing. Counting them would let a metadata call consume a slot a real run
  # then loses. Refusing them would break corpus construction outright.
  local flag
  for flag in --count --version; do
    run env CC_BATS_ROOTS_DIR="$ROOTS" CC_BATS_REAL="$STUB" BATS_TEST_NAME= \
        CC_BATS_MAX_ROOTS=2 CC_BATS_MAX_LOAD_PER_CORE=0 \
        /bin/bash "$SHIM" "$flag"
    [ "$status" -eq 0 ] || false
    [ "$(entries)" -eq 2 ] || false
  done
}

# ── R1 lives in ONE place, deliberately ───────────────────────────────────────────────────────
#
# There is no R1 "never waits" test in this file. tests/qos-chokepoint.bats (xiii) already owns that
# guard for bin/cc-bats and was AMENDED by this same change to state the invariant precisely (no
# wait loop on load, no gate_admit, no sleep in the shim) rather than the substring proxy it used to
# assert. M2 in MACHINE_CAPACITY_V2 says it in terms — *"extend it to the new shim rather than
# duplicating policy"* — and two copies of one policy is how they drift apart.
