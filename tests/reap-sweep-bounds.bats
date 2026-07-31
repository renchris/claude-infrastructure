#!/usr/bin/env bats
# reap-sweep-bounds.bats — R5 / A10 (SESSION_REGISTRY_V2 §4.3.1): every external fork in the sweep is
# bounded, and the two foreign calls that do not feed the decision run AFTER it.
#
# Measured before this change: `grep -c 'timeout ' bin/cc-reaper` = 0. Three foreign binaries ran
# synchronously and unbounded between the sweep's start and the evidence — one of them cc-inbox-guard,
# the exact binary whose unbounded fork caused the 5-day gate blockage. Sweep p99 was 2,099s against a
# 300s StartInterval.
#
# DISCRIMINATOR = a MARKER FILE, never wall-clock. Each wedged stub sleeps, then writes a marker. If
# the bound fired the stub was killed mid-sleep and the marker is ABSENT; unbounded, it is PRESENT.
# A timing assertion would be flaky on a box whose reaper runs in the Darwin background QoS band
# (ProcessType Background + Nice 5, com.chrisren.cc-reaper.plist) where wall time is taxed severalfold.
#
# Every bound test is DIFFERENTIAL — it pins the bounded arm AND the unbounded arm. Asserting only
# "the sweep finished" is vacuous: it passes on a tree with no bounds at all whenever the stub is fast.
# The unbounded arm is reached via CC_REAPER_TIMEOUT_BIN= (set-but-empty), the documented disable seam,
# which is also what a box with no timeout(1) installed degrades to.
#
# Assertion style: `[ ]` throughout — a non-final `[[ ]]`/`(( ))` is errexit-EXEMPT under bats and so a
# DEAD assertion (memory: bats-dead-assertions-errexit-exemptions).
#
# NO fixture may background a job (`&`): a bats fixture's background child prints a spurious `not ok`
# beside the `ok` for a body that PASSED, and the landing gate greps `not ok`
# (memory: bats-background-job-fabricates-not-ok). Every stub here sleeps in the FOREGROUND, as a child
# of the sweep, which is precisely what timeout(1) is being asked to kill.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  R="$REPO/bin/cc-reaper"
  D="$BATS_TEST_TMPDIR"; mkdir -p "$D/bin"
  # Fixture $HOME first — an unfixtured sweep resolves the beat/registry dirs under the operator's
  # live ~/ and could read (or act on) a REAL pane. Hermeticity is also a landing-gate ratchet.
  export HOME="$D/home"; mkdir -p "$HOME/.claude"

  # A landed, idle, reapable candidate — so a sweep that is NOT blocked reaches teardown. Anything
  # this suite observes short of that is attributable to a bound and nothing else.
  mkdir -p "$D/clean"; git -C "$D/clean" init -q
  git -C "$D/clean" config user.email t@t; git -C "$D/clean" config user.name t
  echo a > "$D/clean/f"; git -C "$D/clean" add f; git -C "$D/clean" commit -qm c1
  git -C "$D/clean" update-ref refs/remotes/origin/main HEAD

  cat > "$D/bin/teardown" <<EOF
#!/bin/bash
echo "TD" >> "$D/order"
exit 0
EOF
  cat > "$D/bin/checkpoint" <<'EOF'
#!/bin/bash
cat > /dev/null
EOF
  # STAMP TENANCY (2026-07-24 rule 2): the finished-teammate belt reaps only a pane whose CURRENT
  # session booted within CC_FIRED_BOOT_MAX_S of the fire — so firedAt and startedAt must both be
  # anchored to NOW, not to a fixed literal. A hardcoded past date makes the stamp read `none`, the
  # belt refuses, and every test below would silently measure a refusal instead of a bound.
  NOW_S="$(date +%s)"
  FIRED_ISO="$(date -u -r "$NOW_S" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
  STARTED_MS="$(( NOW_S * 1000 ))"

  # Fast (healthy) classify: one reapable candidate.
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
echo "CLASSIFY" >> "$D/order"
cat <<'JSON'
[{"cause":"finished-teammate","name":"w1","paneUUID":"2BE82E97-1111-4222-8333-444455556666","cwd":"CWD","idle_s":9999,
  "work_landed":"yes","session_id":"s1","pid":1,"lstart":"x","startedAt":STARTED}]
JSON
EOF
  sed -i '' -e "s#CWD#$D/clean#" -e "s#STARTED#$STARTED_MS#" "$D/bin/classify"
  chmod +x "$D/bin/teardown" "$D/bin/checkpoint" "$D/bin/classify"

  export CC_REAPER_TEARDOWN_BIN="$D/bin/teardown"
  export CC_REAPER_CHECKPOINT_BIN="$D/bin/checkpoint"
  export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
  export CC_REAPER_SETTLE_S=100
  export CC_REAPER_TRUNK=origin/main
  export CC_REAPER_LOG="$D/reaper.log"
  export CC_REAPER_LOCKDIR="$D/sweep.lock.d"
  # The fired-peer stamp the finished-teammate cause requires at act time.
  export CC_FIRED_DIR="$D/fired"; mkdir -p "$D/fired"
  printf '{"firedAt":"%s"}' "$FIRED_ISO" > "$D/fired/2BE82E97-1111-4222-8333-444455556666.json"
  # No desk target ⇒ no paging; no ps stub needed beyond a live count of 1.
  export CC_REAPER_NOTIFY_BIN="/usr/bin/true"
}

# Build a stub that sleeps past its bound and only THEN writes its marker. Presence of the marker is
# the whole discriminator: bound fired ⇒ killed mid-sleep ⇒ no marker.
mkwedge() { # <path> <marker> <label>
  cat > "$1" <<EOF
#!/bin/bash
echo "$3" >> "$D/order"
sleep 8
touch "$2"
EOF
  chmod +x "$1"
}

@test "R5/A10: cc-reaper contains timeout bounds at all (the acceptance grep that read 0)" {
  run grep -c 'timeout ' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
}

@test "every foreign invocation in the sweep goes through the bounded helper (none left bare)" {
  # The chokepoint check: a bound that covers three of four calls leaves the fourth as the wedge.
  run grep -c '_rp_bounded ' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -ge 4 ]
}

@test "DIFFERENTIAL: a wedged cc-reconcile is KILLED by its bound — and unbounded it runs to completion" {
  mkwedge "$D/bin/reconcile" "$D/reconcile-finished" "RECONCILE"
  export CC_REAPER_RECONCILE_BIN="$D/bin/reconcile"
  export CC_REAPER_RECONCILE_TIMEOUT_S=2

  run "$R" sweep --reap
  [ ! -e "$D/reconcile-finished" ]                       # bound fired: stub died mid-sleep
  run grep -c 'bound-fired reconcile' "$D/reaper.log"    # and said so — a silent bound hides an inert one
  [ "$output" -ge 1 ]

  # UNBOUNDED ARM — without timeout(1) the identical stub runs to completion. This is what proves the
  # arm above is attributable to the bound rather than to a stub that never ran.
  rm -f "$D/reaper.log" "$D/order"
  CC_REAPER_TIMEOUT_BIN='' run "$R" sweep --reap
  [ -e "$D/reconcile-finished" ]
}

@test "DIFFERENTIAL: a wedged cc-backlog is KILLED by its bound — and unbounded it runs to completion" {
  mkwedge "$D/bin/backlog" "$D/backlog-finished" "BACKLOG"
  export CC_REAPER_BACKLOG_BIN="$D/bin/backlog"
  export CC_REAPER_BACKLOG_TIMEOUT_S=2

  run "$R" sweep --reap
  [ ! -e "$D/backlog-finished" ]
  run grep -c 'bound-fired backlog-reap' "$D/reaper.log"
  [ "$output" -ge 1 ]

  rm -f "$D/reaper.log" "$D/order"
  CC_REAPER_TIMEOUT_BIN='' run "$R" sweep --reap
  [ -e "$D/backlog-finished" ]
}

@test "DIFFERENTIAL: a wedged cc-inbox-guard is KILLED by its bound — and unbounded it runs to completion" {
  # The 5-day-gate-blockage binary. Its unbounded fork is the concrete incident R5 exists to prevent.
  mkwedge "$D/bin/guard" "$D/guard-finished" "GUARD"
  export CC_REAPER_GUARD_BIN="$D/bin/guard"
  export CC_REAPER_GUARD_TIMEOUT_S=2

  run "$R" sweep --reap
  [ ! -e "$D/guard-finished" ]
  run grep -c 'bound-fired inbox-guard' "$D/reaper.log"
  [ "$output" -ge 1 ]

  rm -f "$D/reaper.log" "$D/order"
  CC_REAPER_TIMEOUT_BIN='' run "$R" sweep --reap
  [ -e "$D/guard-finished" ]
}

@test "a wedged foreign binary does NOT stop the sweep from reaping (bounded ⇒ degrade, never block)" {
  # The point of the bound is not merely to kill the stub — it is that the DECISION still happens.
  # Unbounded, this same sweep would sit in the fork instead of reaching teardown.
  mkwedge "$D/bin/reconcile" "$D/reconcile-finished" "RECONCILE"
  export CC_REAPER_RECONCILE_BIN="$D/bin/reconcile"
  export CC_REAPER_RECONCILE_TIMEOUT_S=2
  run "$R" sweep --reap
  run grep -c '^TD$' "$D/order"
  [ "$output" -ge 1 ]
}

@test "FAIL-CLOSED: a wedged cc-classify yields NO candidates — a bounded evidence producer never half-reaps" {
  # If the thing that PRODUCES the verdict wedges, there is no verdict. The failure direction must be
  # "reap nothing", never "reap on a partial candidate set".
  cat > "$D/bin/classify-slow" <<EOF
#!/bin/bash
sleep 8
echo '[{"cause":"finished-teammate","name":"w1","paneUUID":"2BE82E97-1111-4222-8333-444455556666","cwd":"$D/clean","idle_s":9999,"work_landed":"yes","session_id":"s1"}]'
EOF
  chmod +x "$D/bin/classify-slow"
  export CC_REAPER_CLASSIFY_BIN="$D/bin/classify-slow"
  export CC_REAPER_CLASSIFY_TIMEOUT_S=2

  run "$R" sweep --reap
  [ ! -e "$D/order" ]                                    # teardown never called
  run grep -c 'bound-fired classify' "$D/reaper.log"
  [ "$output" -ge 1 ]
  run grep -c 'sweep end: 0 classified' "$D/reaper.log"  # empty set, not a partial one
  [ "$output" -ge 1 ]
}

@test "ORDERING: the two non-decision foreign calls run AFTER the reap, not between evidence and act" {
  # cc-backlog and cc-inbox-guard feed no part of the reap decision, yet ran BEFORE classify — putting
  # two unbounded forks between the sweep's start and the evidence. They still ride the cadence; they
  # may no longer delay a decision or the act that follows it.
  printf '#!/bin/bash\necho BACKLOG >> "%s"\n' "$D/order" > "$D/bin/backlog"
  printf '#!/bin/bash\necho GUARD >> "%s"\n'   "$D/order" > "$D/bin/guard"
  chmod +x "$D/bin/backlog" "$D/bin/guard"
  export CC_REAPER_BACKLOG_BIN="$D/bin/backlog"
  export CC_REAPER_GUARD_BIN="$D/bin/guard"

  run "$R" sweep --reap
  [ -e "$D/order" ]
  # Expected sequence: CLASSIFY … TD … BACKLOG, GUARD
  run bash -c "grep -n '^TD\$'      '$D/order' | head -1 | cut -d: -f1"
  td="$output"
  run bash -c "grep -n '^BACKLOG\$' '$D/order' | head -1 | cut -d: -f1"
  bk="$output"
  run bash -c "grep -n '^GUARD\$'   '$D/order' | head -1 | cut -d: -f1"
  gd="$output"
  [ -n "$td" ]; [ -n "$bk" ]; [ -n "$gd" ]
  [ "$td" -lt "$bk" ]
  [ "$td" -lt "$gd" ]
}

@test "A8: decided_age is measured from CLASSIFY, and sweep_age is logged beside it (neither hidden)" {
  # decided_age previously started at sweep_t0 — before classify ran — so it charged the decision→act
  # gap for foreign work that finished before the evidence existed. Both spans are now emitted, so the
  # narrower number can never be read as the wider one having improved.
  run grep -c 'decided_age=\${decided_age}s sweep_age=\${sweep_age}s' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  run grep -c 'decided_age=$(( decided_at - classify_t0 ))' "$REPO/bin/cc-reaper"
  [ "$output" -ge 1 ]
}

@test "the suspend guard still reads sweep_t0 (changing the A8 span must not move the sleep detector)" {
  # Gap-3 detects a machine sleep DURING the sweep via intra = now_act - sweep_t0. Re-anchoring
  # decided_age to classify_t0 must leave that detector on its original, wider span.
  run grep -c 'intra=$(( now_act - sweep_t0 ))' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
