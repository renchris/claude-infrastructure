#!/usr/bin/env bats
# deathwatch-watchfile — the producer L1 death-watch never had (backlog ed6d0716caa7 / 0328e7cc5742).
#
# THE TEST THAT MATTERS IS THE ROUND-TRIP (§2). Everything else here is shape; §2 is the only one
# that can catch the failure that would actually hurt, and it is a COUPLING, not a format:
# bin/cc-deathwatch-kqueue compares the `start` cell by STRING EQUALITY against its own
# `ps -o lstart=`.strip(). Any normalisation this producer applies that the helper does not — a
# `tr -s ' '` (which bin/cc-reaper's proc_lstart DOES apply, and which looks like the obvious helper
# to reuse), an `LC_ALL=C` against an un-forced reader — makes every live session read `recycled`,
# i.e. fires an INSTANT false DEATH for the whole fleet. A page storm on a healthy machine is worse
# than no watcher. So §2 drives a REAL live pid through the REAL helper and asserts it is not
# convicted; a shape assertion could never see it (memory: control-must-replay-the-real-artifact).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PROD="$REPO/scripts/deathwatch-watchfile.sh"
  KQ="$REPO/bin/cc-deathwatch-kqueue"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_DEATHWATCH_WATCHFILE="$BATS_TEST_TMPDIR/watch-list"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  PIDS=""
}
teardown() { for p in $PIDS; do kill "$p" 2>/dev/null || true; done; }

# Sets SPAWNED. NOT `p=$(spawn)`: a background job inside a command substitution holds the
# substitution's stdout open, so `$(...)` blocks for the child's whole lifetime.
spawn() { sleep 300 >/dev/null 2>&1 & SPAWNED=$!; PIDS="$PIDS $SPAWNED"; }

reg() { # <paneUUID> <pid> [name] [cwd]
  printf '{"paneUUID":"%s","pid":%s,"name":"%s","cwd":"%s","session_id":"s-%s"}\n' \
    "$1" "$2" "${3:-proj-$1}" "${4:-/tmp/wt-$1}" "$1" > "$CC_REGISTRY_DIR/$1.json"
}

# ── §1 shape ──────────────────────────────────────────────────────────────────────────────────────

@test "a live registered row becomes one TAB line in lead-deathwatch's 5-field format" {
  spawn; local p="$SPAWNED"
  reg 101 "$p" lead-101 /tmp/wt-101
  run bash "$PROD"
  [ "$status" -eq 0 ]
  # 5 fields, tab-separated, in the documented order: pid start label waiter worktree
  local line; line="$(head -1 "$CC_DEATHWATCH_WATCHFILE")"
  [ "$(printf '%s' "$line" | awk -F'\t' '{print NF}')" -eq 5 ]
  [ "$(printf '%s' "$line" | cut -f1)" = "$p" ]
  [ "$(printf '%s' "$line" | cut -f3)" = "lead-101" ]
  [ "$(printf '%s' "$line" | cut -f5)" = "/tmp/wt-101" ]
  [ -n "$(printf '%s' "$line" | cut -f2)" ]          # a start-time was actually resolved
}

@test "a provisional row with NO pid is skipped and COUNTED, never armed" {
  printf '{"paneUUID":"202","name":"prov","provisional":true}\n' > "$CC_REGISTRY_DIR/202.json"
  run bash "$PROD"
  [ "$status" -eq 0 ]
  [ ! -s "$CC_DEATHWATCH_WATCHFILE" ]
  echo "$output" | grep -q "1 no-pid"
}

@test "a registered pid that is ALREADY DEAD is skipped — a stale row must not page a fresh death" {
  # The discriminator pair: same shape, differing only in whether the process is alive.
  spawn; local live="$SPAWNED"
  spawn; local dead="$SPAWNED"
  kill "$dead" 2>/dev/null || true
  wait "$dead" 2>/dev/null || true
  reg 301 "$live" alive-301
  reg 302 "$dead" dead-302
  run bash "$PROD"
  [ "$status" -eq 0 ]
  grep -q "alive-301" "$CC_DEATHWATCH_WATCHFILE"
  ! grep -q "dead-302" "$CC_DEATHWATCH_WATCHFILE" || false
  echo "$output" | grep -q "1 already-dead"
}

@test "an unreadable registry FAILS CLOSED and leaves a good watch-file untouched" {
  spawn; reg 401 "$SPAWNED"
  run bash "$PROD"; [ "$status" -eq 0 ]
  local before; before="$(cat "$CC_DEATHWATCH_WATCHFILE")"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/gone"
  run bash "$PROD"
  [ "$status" -eq 3 ]
  # Never truncate a live fleet's coverage because the registry blipped for one tick.
  [ "$(cat "$CC_DEATHWATCH_WATCHFILE")" = "$before" ]
}

@test "a corrupt registry row costs only itself, never the rest of the fleet" {
  spawn; reg 501 "$SPAWNED" good-501
  printf 'not json at all\n' > "$CC_REGISTRY_DIR/502.json"
  run bash "$PROD"
  [ "$status" -eq 0 ]
  grep -q "good-501" "$CC_DEATHWATCH_WATCHFILE"
}

# ── §2 THE COUPLING: real output, real helper, real live pid ──────────────────────────────────────

@test "ROUND-TRIP: a live pid's start survives the kqueue helper's {pid,start} guard uncondemned" {
  spawn; local p="$SPAWNED"
  reg 601 "$p" rt-601
  run bash "$PROD"; [ "$status" -eq 0 ]
  # --once: arm, guard, report, exit — no watch loop, so this cannot hang the suite.
  run timeout 20 python3 "$KQ" --once "$CC_DEATHWATCH_WATCHFILE"
  # The guard convicts on mismatch by emitting DEATH … recycled. A live process must NEVER be that.
  ! echo "$output" | grep -q "recycled" || false
}

@test "ROUND-TRIP RED-PROOF: a MANGLED start IS convicted — so the pass above is not vacuous" {
  # L2: the same fixture, with only the normalisation under suspicion applied. `tr -s ' '` is the
  # exact transform bin/cc-reaper's proc_lstart performs, and reusing that helper in the producer is
  # the plausible wrong turn this pair exists to catch. If the helper ever stops comparing raw
  # lstart, THIS test goes green-when-it-should-red and the pair says so.
  spawn; local p="$SPAWNED"
  reg 701 "$p" rt-701
  run bash "$PROD"; [ "$status" -eq 0 ]
  # Perturb the start cell's VALUE, leaving every other cell — and its whitespace — intact.
  #
  # ⚠️ THIRD VERSION, and each rewrite moved the mangle onto an axis the guard actually still
  # discriminates. v1 collapsed runs with `tr -s ' '`, which `ps -o lstart=` only pads on a
  # single-digit day-of-month, so on 20 days a month the mangle was a NO-OP and the case proved
  # nothing. v2 INSERTED a space, on the stated premise that "the guard is whitespace-EXACT".
  # 33c462990 then made it deliberately whitespace-TOLERANT: `start_is_same` opens with
  # `" ".join(recorded.split())`, because the same instant renders as `Fri Aug 21 15:45:00 2026`
  # canonically and `Fri 21 Aug 08:45:00 2026` under the ambient locale, and an exact compare
  # against one dialect reports a LIVE process as recycled. So from that commit on, v2 asked the
  # guard to convict on the ONE axis it had just been fixed to forgive — a control pinning behaviour
  # the subject removed on purpose, which is red against correct code (memory:
  # stale-assertion-becomes-an-inverted-guard).
  #
  # The YEAR is the axis that survives every dialect: TZ and LC_TIME reorder and re-spell the day
  # and month and shift the clock, but no rendering of THIS pid's start instant says 1999. So a
  # guard that has stopped discriminating start instants at all — the vacuity this pair exists to
  # catch — is still the only thing that can make this green when it should be red.
  awk -F'\t' 'BEGIN{OFS="\t"}{sub(/[0-9][0-9][0-9][0-9]$/,"1999",$2); print}' "$CC_DEATHWATCH_WATCHFILE" \
    > "$CC_DEATHWATCH_WATCHFILE.mangled"
  # Non-vacuity: the mangle must actually have changed something, or "convicted" means nothing.
  ! cmp -s "$CC_DEATHWATCH_WATCHFILE" "$CC_DEATHWATCH_WATCHFILE.mangled" || false
  run timeout 20 python3 "$KQ" --once "$CC_DEATHWATCH_WATCHFILE.mangled"
  echo "$output" | grep -q "recycled"
}

# ── §3 deliverability: a death captured and told to nobody ────────────────────────────────────────

@test "an unroutable waiter WARNS — capture without a page is a watcher nobody hears" {
  spawn; reg 801 "$SPAWNED"
  run bash "$PROD"
  [ "$status" -eq 0 ]                                   # loud, never fatal: capture still works
  echo "$output" | grep -q "resolves to nothing"
}

@test "an EMPTY role file is unroutable too — existence is not deliverability" {
  # cc-roles/orchestrator was a 0-byte file on this box, and `[ -f ]` would have called it wired.
  spawn; reg 901 "$SPAWNED"
  : > "$CC_ROLES_DIR/desk"
  run bash "$PROD"
  echo "$output" | grep -q "resolves to nothing"
  printf 'claude-infrastructure-399\n' > "$CC_ROLES_DIR/desk"
  run bash "$PROD"
  ! echo "$output" | grep -q "resolves to nothing" || false
}
