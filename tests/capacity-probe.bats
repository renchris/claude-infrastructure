#!/usr/bin/env bats
# scripts/lib/capacity-admit.sh — cc_capacity_probe, the NON-CHARGING read (LIMIT_RECOVER_100P).
#
# THE DEFECT. Every REFUSE from cc_capacity_admit charges a per-caller budget and the next evaluation
# after CC_ADMIT_BUDGET consecutive refusals ADMITS and pages. A fleet recovery that asks "may I
# relaunch?" before each /exit — and must ask, because a pane exited with nothing to relaunch into
# is a stranded session — would therefore FORCE its own admission on the fourth ask. The probe is
# the same evaluation with the budget, the page and the reset inert. This suite pins that the probe
# refuses when admit would, admits when admit would, and moves NOTHING: no state file, no page,
# and the very next charging call still sees an unspent budget.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/capacity-admit.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ADMIT_NOTIFY_BIN="$BATS_TEST_TMPDIR/notify"
  cat > "$CC_ADMIT_NOTIFY_BIN" <<EOF
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/pages.txt"
EOF
  chmod +x "$CC_ADMIT_NOTIFY_BIN"
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0
  export CC_ADMIT_HEADROOM_OVERRIDE=64
  export CC_ADMIT_SEGMENT_OVERRIDE=1
  export CC_ADMIT_ACTIVE_TERM=off
  export CC_ADMIT_RESERVE_TERM=off
  export CC_ADMIT_BUDGET=3
  export CC_ADMIT_SYSCTL="$BATS_TEST_TMPDIR/sysctl"
  cat > "$CC_ADMIT_SYSCTL" <<'EOF'
#!/usr/bin/env bash
case "$*" in *hw.ncpu*) echo 10 ;; *vm.loadavg*) echo "{ 1.00 1.00 1.00 }" ;; *) echo 0 ;; esac
EOF
  chmod +x "$CC_ADMIT_SYSCTL"
  . "$LIB"
}

@test "a healthy box: probe ADMITS, records basis=measured like admit, and charges nothing" {
  run cc_capacity_probe lr100p-test "resume x"
  [ "$status" -eq 0 ]
  [ ! -s "$CC_ADMIT_STATE_DIR/lr100p-test.refusals" ]
}

@test "over the load ceiling: probe REFUSES with rc 9 and basis=probe, the budget file stays EMPTY" {
  export CC_ADMIT_LOADAVG_OVERRIDE=50
  run cc_capacity_probe lr100p-test "resume x"
  [ "$status" -eq 9 ]
  grep -q '"basis":"probe"' "$CC_ADMIT_IDL"
  grep -q '"term":"load"' "$CC_ADMIT_IDL"
  [ ! -s "$CC_ADMIT_STATE_DIR/lr100p-test.refusals" ] || { echo "the probe CHARGED: $(cat "$CC_ADMIT_STATE_DIR/lr100p-test.refusals")"; false; }
  [ ! -f "$BATS_TEST_TMPDIR/pages.txt" ]
}

@test "THE POINT: N probes never release the bound — the next CHARGING call is refusal 1 of the budget" {
  export CC_ADMIT_LOADAVG_OVERRIDE=50
  for _ in 1 2 3 4 5; do run cc_capacity_probe lr100p-test "resume x"; [ "$status" -eq 9 ]; done
  run cc_capacity_admit lr100p-test "resume x"
  [ "$status" -eq 9 ]
  tail -1 "$CC_ADMIT_IDL" | grep -q 'refusal 1 of budget 3' || { tail -1 "$CC_ADMIT_IDL"; false; }
  [ ! -f "$BATS_TEST_TMPDIR/pages.txt" ]
}

@test "CONTROL: the charging call still spends — three refusals then the fourth ADMITS and pages" {
  export CC_ADMIT_LOADAVG_OVERRIDE=50
  for _ in 1 2 3; do run cc_capacity_admit lr100p-test "resume x"; [ "$status" -eq 9 ]; done
  run cc_capacity_admit lr100p-test "resume x"
  [ "$status" -eq 0 ]
  grep -q 'budget-expired' "$CC_ADMIT_IDL"
  [ -f "$BATS_TEST_TMPDIR/pages.txt" ]
}

@test "a probe ADMIT does not RESET a partially-spent budget either — it observes, it does not act" {
  export CC_ADMIT_LOADAVG_OVERRIDE=50
  run cc_capacity_admit lr100p-test "resume x"; [ "$status" -eq 9 ]
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0
  run cc_capacity_probe lr100p-test "resume x"; [ "$status" -eq 0 ]
  export CC_ADMIT_LOADAVG_OVERRIDE=50
  run cc_capacity_admit lr100p-test "resume x"
  [ "$status" -eq 9 ]
  tail -1 "$CC_ADMIT_IDL" | grep -q 'refusal 2 of budget 3' || { tail -1 "$CC_ADMIT_IDL"; false; }
}

@test "the probe flag is not sticky: after a probe, a plain admit refusal charges as before" {
  export CC_ADMIT_LOADAVG_OVERRIDE=50
  run cc_capacity_probe lr100p-test "resume x"; [ "$status" -eq 9 ]
  run cc_capacity_admit lr100p-test "resume x"; [ "$status" -eq 9 ]
  [ -s "$CC_ADMIT_STATE_DIR/lr100p-test.refusals" ]
}
