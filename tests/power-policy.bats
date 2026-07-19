#!/usr/bin/env bats
# T-P16-3 (power-policy-verify.sh) + T-P16-4 (caffeinate-floor.sh): the machine-awake continuity kit.
# Each tool's --selftest RED-proves its own mechanics; these bats are the independent CLI-level
# regression on the exit contracts + the page shape, driven through the env stubs (no live pmset /
# caffeinate). Also lints the two plists (the G-P16-6 raw-& class) and asserts their load semantics.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FLOOR="$REPO/scripts/caffeinate-floor.sh"
  PPV="$REPO/scripts/power-policy-verify.sh"
  D="$BATS_TEST_TMPDIR"
}

# ── caffeinate-floor.sh (T-P16-4) ───────────────────────────────────────────────────────────────

@test "caffeinate-floor --selftest passes with a non-empty ok-set and no FAIL" {
  run "$FLOOR" --selftest
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  ok ')" -ge 7 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "caffeinate-floor unknown arg → exit 2" {
  run "$FLOOR" --bogus
  [ "$status" -eq 2 ]
}

@test "caffeinate-floor --run builds 'caffeinate -i -s' (default floor flags)" {
  run env CC_CAFFEINATE_BIN=/bin/echo CC_CAFFEINATE_LOG="$D/run.log" "$FLOOR" --run
  [ "$status" -eq 0 ]
  [ "$output" = "-i -s" ]
}

@test "caffeinate-floor --run honors CC_CAFFEINATE_FLAGS downgrade (AC-only -s)" {
  run env CC_CAFFEINATE_BIN=/bin/echo CC_CAFFEINATE_FLAGS=-s CC_CAFFEINATE_LOG="$D/run.log" "$FLOOR" --run
  [ "$status" -eq 0 ]
  [ "$output" = "-s" ]
}

@test "caffeinate-floor --verify PRESENT when a floor (no -t) is running → exit 0" {
  printf '40000 caffeinate -i -s\n30000 caffeinate -i -t 300\n' > "$D/present.ps"
  CC_CAFFEINATE_PS="cat $D/present.ps" run "$FLOOR" --verify
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'PRESENT'
}

@test "caffeinate-floor --verify ABSENT when only per-turn -t keepalives run → exit 1" {
  printf '30000 caffeinate -i -t 300\n' > "$D/perturn.ps"
  CC_CAFFEINATE_PS="cat $D/perturn.ps" run "$FLOOR" --verify
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'ABSENT'
}

# ── power-policy-verify.sh (T-P16-3) ─────────────────────────────────────────────────────────────

# emit a pmset -g custom fixture with a given AC sleep value
mk_pmset() { # <file> <ac-sleep-value>
  printf 'Battery Power:\n sleep                1\n displaysleep         0\nAC Power:\n sleep                %s\n displaysleep         0\n' "$2" > "$1"
}

@test "power-policy-verify --selftest passes with no FAIL" {
  run "$PPV" --selftest
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  ok ')" -ge 12 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "power-policy-verify unknown arg → exit 2" {
  run "$PPV" --bogus
  [ "$status" -eq 2 ]
}

@test "power-policy GREEN: AC matches intent + floor present → exit 0, no page" {
  mk_pmset "$D/ac.txt" 0
  CC_PMSET_CMD="cat $D/ac.txt" CC_FLOOR_VERIFY_CMD=/usr/bin/true \
    CC_PPV_NOTIFY=/usr/bin/true CC_PPV_PAGEDIR="$D/pages" CC_PPV_LOG="$D/pp.log" run "$PPV" --verify
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'GREEN'
  [ ! -f "$D/pages/power-policy.page" ]
}

@test "power-policy floor-absent is informational: still exit 0 when pmset matches" {
  mk_pmset "$D/ac.txt" 0
  CC_PMSET_CMD="cat $D/ac.txt" CC_FLOOR_VERIFY_CMD=/usr/bin/false \
    CC_PPV_NOTIFY=/usr/bin/true CC_PPV_PAGEDIR="$D/pages" CC_PPV_LOG="$D/pp.log" run "$PPV" --verify
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'floor ABSENT'
  [ ! -f "$D/pages/power-policy.page" ]
}

@test "power-policy DRIFT: reverted AC sleep → exit 1, epoch-headed page names the sudo remediation" {
  mk_pmset "$D/ac.txt" 10
  CC_PMSET_CMD="cat $D/ac.txt" CC_FLOOR_VERIFY_CMD=/usr/bin/true \
    CC_PPV_NOTIFY=/usr/bin/true CC_PPV_PAGEDIR="$D/pages" CC_PPV_LOG="$D/pp.log" run "$PPV" --verify
  [ "$status" -eq 1 ]
  [ -f "$D/pages/power-policy.page" ]
  head -1 "$D/pages/power-policy.page" | grep -qE '^[0-9]+$'
  grep -q 'sudo pmset -c' "$D/pages/power-policy.page"
}

@test "power-policy ABSTAIN: no AC block → exit 3, no page (never false-green)" {
  printf 'Battery Power:\n sleep                1\n' > "$D/noac.txt"
  CC_PMSET_CMD="cat $D/noac.txt" CC_FLOOR_VERIFY_CMD=/usr/bin/true \
    CC_PPV_NOTIFY=/usr/bin/true CC_PPV_PAGEDIR="$D/pages" CC_PPV_LOG="$D/pp.log" run "$PPV" --verify
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q 'ABSTAIN'
  [ ! -f "$D/pages/power-policy.page" ]
}

@test "power-policy GREEN after a DRIFT clears the standing page" {
  mkdir -p "$D/pages"; printf '123\nstale\n' > "$D/pages/power-policy.page"
  mk_pmset "$D/ac.txt" 0
  CC_PMSET_CMD="cat $D/ac.txt" CC_FLOOR_VERIFY_CMD=/usr/bin/true \
    CC_PPV_NOTIFY=/usr/bin/true CC_PPV_PAGEDIR="$D/pages" CC_PPV_LOG="$D/pp.log" run "$PPV" --verify
  [ "$status" -eq 0 ]
  [ ! -f "$D/pages/power-policy.page" ]
}

# ── plists (load semantics + the G-P16-6 raw-& lint class) ────────────────────────────────────────

@test "both plists exist and plutil -lint OK" {
  run plutil -lint "$REPO/launchd/com.claude.caffeinate-floor.plist" "$REPO/launchd/com.claude.power-policy-verify.plist"
  [ "$status" -eq 0 ]
}

@test "caffeinate-floor plist: RunAtLoad + KeepAlive, exec's the floor script (no StartInterval)" {
  p="$REPO/launchd/com.claude.caffeinate-floor.plist"
  grep -q 'caffeinate-floor.sh' "$p"
  plutil -extract RunAtLoad raw "$p" | grep -q true
  plutil -extract KeepAlive raw "$p" | grep -q true
  run plutil -extract StartInterval raw "$p"
  [ "$status" -ne 0 ]   # persistent, not periodic — no StartInterval
}

@test "power-policy-verify plist: RunAtLoad + hourly StartInterval, exec's the verify script" {
  p="$REPO/launchd/com.claude.power-policy-verify.plist"
  grep -q 'power-policy-verify.sh' "$p"
  plutil -extract RunAtLoad raw "$p" | grep -q true
  [ "$(plutil -extract StartInterval raw "$p")" -eq 3600 ]
}
